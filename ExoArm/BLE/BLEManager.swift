// BLE/BLEManager.swift
// CoreBluetooth on a dedicated background queue. Data never touches main.

import CoreBluetooth
import Combine
import Foundation

protocol BLEManagerDelegate: AnyObject {
    func didReceiveSensorData(_ raw: RawSensorData)
    func didReceiveHeartRate(_ bpm: Int)
    func didUpdateESPConnection(_ connected: Bool)
    func didUpdateWhoopConnection(_ connected: Bool)
    func didReceiveESPResponse(_ message: String)
    func didReceiveCalibration(_ data: [String: CalibrationData])
}

struct CalibrationData {
    let sys: Int
    let gyro: Int
    let accel: Int
    let mag: Int
}

final class BLEManager: NSObject, ObservableObject {
    weak var delegate: BLEManagerDelegate?

    private let bleQueue = DispatchQueue(label: "com.exoarm.ble", qos: .userInteractive)
    private var centralManager: CBCentralManager!
    private var espPeripheral: CBPeripheral?
    private var whoopPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var isScanning = false

    @Published var espConnected = false
    @Published var whoopConnected = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    func startScanning() {
        bleQueue.async { [weak self] in
            guard let self, self.centralManager.state == .poweredOn else {
                print("[BLE] Not ready")
                return
            }
            guard !self.isScanning else { return }
            self.isScanning = true
            self.centralManager.scanForPeripherals(
                withServices: [BLEUUID.imuService, BLEUUID.heartRateService],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            print("[BLE] Scanning...")
        }
    }

    func stopScanning() {
        bleQueue.async { [weak self] in
            self?.centralManager.stopScan()
            self?.isScanning = false
        }
    }

    func sendCommand(_ cmd: ESPCommand) {
        sendRaw(cmd.rawValue)
    }

    func sendRateCommand(_ hz: Int) {
        sendRaw(ESPCommand.rate(hz))
    }

    func disconnect() {
        bleQueue.async { [weak self] in
            if let esp = self?.espPeripheral { self?.centralManager.cancelPeripheralConnection(esp) }
            if let whoop = self?.whoopPeripheral { self?.centralManager.cancelPeripheralConnection(whoop) }
        }
    }

    private func sendRaw(_ str: String) {
        bleQueue.async { [weak self] in
            guard let self,
                  let p = self.espPeripheral,
                  let c = self.commandCharacteristic,
                  let data = str.data(using: .utf8) else {
                print("[BLE] Cannot send: not connected")
                return
            }
            p.writeValue(data, for: c, type: .withResponse)
            print("[BLE] Sent: \(str)")
        }
    }

    private func onMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("[BLE] State: \(central.state.rawValue)")
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown"
        let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []

        if uuids.contains(BLEUUID.imuService) && espPeripheral == nil {
            print("[BLE] Found ESP32: \(name)")
            espPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        }

        if uuids.contains(BLEUUID.heartRateService) && whoopPeripheral == nil {
            print("[BLE] Found HR device: \(name)")
            whoopPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        }

        if espPeripheral != nil && whoopPeripheral != nil {
            centralManager.stopScan()
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral == espPeripheral {
            onMain { [weak self] in
                self?.espConnected = true
                self?.delegate?.didUpdateESPConnection(true)
            }
            peripheral.discoverServices([BLEUUID.imuService])
        } else if peripheral == whoopPeripheral {
            onMain { [weak self] in
                self?.whoopConnected = true
                self?.delegate?.didUpdateWhoopConnection(true)
            }
            peripheral.discoverServices([BLEUUID.heartRateService])
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didDisconnectPeripheral peripheral: CBPeripheral,
                         error: Error?) {
        if peripheral == espPeripheral {
            espPeripheral = nil
            commandCharacteristic = nil
            statusCharacteristic = nil
            onMain { [weak self] in
                self?.espConnected = false
                self?.delegate?.didUpdateESPConnection(false)
            }
        } else if peripheral == whoopPeripheral {
            whoopPeripheral = nil
            onMain { [weak self] in
                self?.whoopConnected = false
                self?.delegate?.didUpdateWhoopConnection(false)
            }
        }
        if !isScanning {
            bleQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.startScanning()
            }
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didFailToConnect peripheral: CBPeripheral,
                         error: Error?) {
        print("[BLE] Failed: \(peripheral.name ?? "?") \(error?.localizedDescription ?? "")")
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for svc in services {
            if svc.uuid == BLEUUID.imuService {
                peripheral.discoverCharacteristics(
                    [BLEUUID.imuData, BLEUUID.imuCommand, BLEUUID.imuStatus], for: svc)
            } else if svc.uuid == BLEUUID.heartRateService {
                peripheral.discoverCharacteristics(
                    [BLEUUID.heartRateMeasurement], for: svc)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverCharacteristicsFor service: CBService,
                     error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            switch c.uuid {
            case BLEUUID.imuData:
                peripheral.setNotifyValue(true, for: c)
            case BLEUUID.imuCommand:
                commandCharacteristic = c
            case BLEUUID.imuStatus:
                statusCharacteristic = c
                peripheral.setNotifyValue(true, for: c)
            case BLEUUID.heartRateMeasurement:
                peripheral.setNotifyValue(true, for: c)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case BLEUUID.imuData:
            if let raw = RawSensorData.fromBLEData(data) {
                delegate?.didReceiveSensorData(raw)
            }
        case BLEUUID.imuStatus:
            if let str = String(data: data, encoding: .utf8) {
                handleResponse(str)
            }
        case BLEUUID.heartRateMeasurement:
            let bpm = parseHeartRate(data)
            if bpm > 0 { delegate?.didReceiveHeartRate(bpm) }
        default:
            break
        }
    }

    private func handleResponse(_ str: String) {
        if str.hasPrefix("PONG") {
            let calib = parseCalibration(str)
            onMain { [weak self] in self?.delegate?.didReceiveCalibration(calib) }
        } else {
            onMain { [weak self] in self?.delegate?.didReceiveESPResponse(str) }
        }
    }

    private func parseCalibration(_ str: String) -> [String: CalibrationData] {
        var result = [String: CalibrationData]()
        let parts = str.replacingOccurrences(of: "PONG,", with: "").split(separator: ",")
        for part in parts {
            let segs = part.split(separator: ":")
            if segs.count == 5,
               let s = Int(segs[1]), let g = Int(segs[2]),
               let a = Int(segs[3]), let m = Int(segs[4]) {
                result[String(segs[0])] = CalibrationData(sys: s, gyro: g, accel: a, mag: m)
            }
        }
        return result
    }

    private func parseHeartRate(_ data: Data) -> Int {
        guard data.count >= 2 else { return 0 }
        let is16Bit = (data[0] & 0x01) != 0
        if is16Bit && data.count >= 3 {
            return Int(data[1]) | (Int(data[2]) << 8)
        }
        return Int(data[1])
    }
}
