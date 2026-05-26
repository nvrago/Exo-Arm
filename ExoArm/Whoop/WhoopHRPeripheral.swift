import Foundation
import Combine
import CoreBluetooth

// BLE heart rate service.
// Works with any HR broadcasting device

@MainActor
final class WhoopHRPeripheral: NSObject, ObservableObject {
    
    nonisolated private static let heartRateServiceUUID = CBUUID(string: "180D")
    nonisolated private static let heartRateMeasurementUUID = CBUUID(string: "2A37")
    
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var deviceName: String?
    @Published private(set) var currentHR: Int = 0
    @Published private(set) var lastUpdate: Date?
    
    var onHeartRateUpdate: ((Int, Date) -> Void)?
    
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }
    
    func startScan() {
        guard central.state == .poweredOn else { return }
        isScanning = true
        central.scanForPeripherals(
            withServices: [Self.heartRateServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    func stopScan() {
        central.stopScan()
        isScanning = false
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }
    
    private func parseHeartRate(_ data: Data) -> Int? {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data)
        let flags = bytes[0]
        let is16Bit = (flags & 0x01) != 0
        
        if is16Bit {
            guard data.count >= 3 else { return nil }
            let hr = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return Int(hr)
        } else {
            return Int(bytes[1])
        }
    }
}

extension WhoopHRPeripheral: CBCentralManagerDelegate {
    
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                self.startScan()
            }
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard self.peripheral == nil else { return }
            self.peripheral = peripheral
            self.deviceName = peripheral.name ?? "Heart Rate Monitor"
            self.stopScan()
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.isConnected = true
            peripheral.discoverServices([Self.heartRateServiceUUID])
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.peripheral = nil
            self.deviceName = nil
        }
    }
    
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.isConnected = false
            self.peripheral = nil
            self.deviceName = nil
            self.currentHR = 0
        }
    }
}

extension WhoopHRPeripheral: CBPeripheralDelegate {
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.heartRateServiceUUID {
            peripheral.discoverCharacteristics([Self.heartRateMeasurementUUID], for: service)
        }
    }
    
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics where char.uuid == Self.heartRateMeasurementUUID {
            peripheral.setNotifyValue(true, for: char)
        }
    }
    
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.heartRateMeasurementUUID,
              let data = characteristic.value else { return }
        
        Task { @MainActor in
            guard let hr = self.parseHeartRate(data) else { return }
            let now = Date()
            self.currentHR = hr
            self.lastUpdate = now
            self.onHeartRateUpdate?(hr, now)
        }
    }
}
