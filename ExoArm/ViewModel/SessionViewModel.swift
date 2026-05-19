//
//  SessionViewModel.swift
//  ExoArm
//
//  Created by Nathan Rago on 5/13/26.
//

// ViewModel/SessionViewModel.swift
// Three-tier pipeline: BLE queue -> ring buffer -> 144Hz display timer.

import Foundation
import Combine
import RealityKit

final class SessionViewModel: ObservableObject {
    @Published var espConnected = false
    @Published var whoopConnected = false
    @Published var isStreaming = false
    @Published var latestFrame: ProcessedFrame?
    @Published var heartRate: Int?
    @Published var fps: Int = 0
    @Published var pitchCount: Int = 0
    @Published var calibration: [String: CalibrationData]?
    @Published var shoulderHistory: [Float] = []
    @Published var elbowHistory: [Float] = []
    @Published var wristHistory: [Float] = []
    @Published var hrHistory: [Int] = []
    @Published var isRecording = false
    @Published var logMessages: [LogEntry] = []
    @Published var useICloud = true
    @Published var iCloudAvailable = false
    @Published var storageLocation = "Local"
    @Published var dataRate: Int = 0
    @Published var isCalibrated = false

    // 3D renderer reference, assigned by ArmSceneView in makeNSView
    weak var armRenderer: OrbitARView?

    let bleManager: BLEManager
    let recorder = SessionRecorder()
    private let kinematics = KinematicsEngine.shared
    private let frameBuffer = FrameRingBuffer(capacity: 512)
    let interpolator = FrameInterpolator()

    private var fpsCounter = 0
    private var dataCounter = 0
    private var fpsTimer: Timer?
    private var displayTimer: DispatchSourceTimer?
    private let maxHistory = 400
    private var currentHR: Int?

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    init() {
        bleManager = BLEManager()
        bleManager.delegate = self
        iCloudAvailable = recorder.iCloudAvailable
        storageLocation = recorder.storageLocation

        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.fps = self.fpsCounter
            self.dataRate = self.dataCounter
            self.fpsCounter = 0
            self.dataCounter = 0
        }

        displayTimer = DispatchSource.makeTimerSource(queue: .main)
        displayTimer?.schedule(deadline: .now(), repeating: .milliseconds(7))
        displayTimer?.setEventHandler { [weak self] in
            self?.pullFrameToUI()
        }
        displayTimer?.resume()
    }

    deinit {
        displayTimer?.cancel()
        fpsTimer?.invalidate()
    }

    private func pullFrameToUI() {
        guard let frame = frameBuffer.readLatest() else { return }

        interpolator.pushTarget(frame)
        latestFrame = frame
        fpsCounter += 1

        // Drive the 3D renderer with the new frame
        armRenderer?.updatePose(frame, interpolator: interpolator)

        appendHistory(
            shoulder: frame.shoulderAngle,
            elbow: frame.elbowAngle,
            wrist: frame.wristAngle)

        if let hr = frame.heartRate {
            heartRate = hr
            hrHistory.append(hr)
            if hrHistory.count > maxHistory { hrHistory.removeFirst() }
        }
    }

    func interpolatedPose() -> InterpolatedPose? {
        return interpolator.interpolated()
    }

    func startScanning() {
        addLog("Scanning for devices...")
        bleManager.startScanning()
    }

    func sendCommand(_ cmd: ESPCommand) {
        bleManager.sendCommand(cmd)
        addLog("Sent: \(cmd.rawValue)")
        switch cmd {
        case .start: isStreaming = true
        case .stop: isStreaming = false
        default: break
        }
    }

    func sendRate(_ hz: Int) {
        bleManager.sendRateCommand(hz)
        addLog("Rate set to \(hz) Hz")
    }

    func startRecording() {
        recorder.startRecording()
        isRecording = true
        addLog("Recording started (\(recorder.storageLocation))")
    }

    func stopRecording() {
        recorder.stopRecording()
        isRecording = false
        addLog("Recording stopped (\(recorder.frameCount) frames)")
    }

    func calibrate() {
        guard let frame = latestFrame else {
            addLog("Cannot calibrate: no data")
            return
        }
        kinematics.calibrate(with: frame.raw)
        isCalibrated = true
        addLog("Calibrated zero pose")
    }

    func clearCalibration() {
        kinematics.clearCalibration()
        isCalibrated = false
        addLog("Calibration cleared")
    }

    func toggleICloud(_ enabled: Bool) {
        recorder.useICloud = enabled
        useICloud = enabled
        storageLocation = recorder.storageLocation
        addLog("Storage: \(storageLocation)")
    }

    func clearHistory() {
        shoulderHistory.removeAll()
        elbowHistory.removeAll()
        wristHistory.removeAll()
        hrHistory.removeAll()
        armRenderer?.clearTrail()
    }

    private func addLog(_ msg: String) {
        logMessages.append(LogEntry(timestamp: Date(), message: msg))
        if logMessages.count > 100 { logMessages.removeFirst(logMessages.count - 100) }
    }

    private func appendHistory(shoulder: Float, elbow: Float, wrist: Float) {
        shoulderHistory.append(shoulder)
        elbowHistory.append(elbow)
        wristHistory.append(wrist)
        if shoulderHistory.count > maxHistory { shoulderHistory.removeFirst() }
        if elbowHistory.count > maxHistory { elbowHistory.removeFirst() }
        if wristHistory.count > maxHistory { wristHistory.removeFirst() }
    }
}

extension SessionViewModel: BLEManagerDelegate {
    func didReceiveSensorData(_ raw: RawSensorData) {
        let frame = kinematics.process(raw, heartRate: currentHR)
        dataCounter += 1
        frameBuffer.write(frame)
        if recorder.isRecording { recorder.record(frame) }
    }

    func didReceiveHeartRate(_ bpm: Int) {
        currentHR = bpm
    }

    func didUpdateESPConnection(_ connected: Bool) {
        espConnected = connected
        addLog(connected ? "ESP32 connected" : "ESP32 disconnected")
    }

    func didUpdateWhoopConnection(_ connected: Bool) {
        whoopConnected = connected
        addLog(connected ? "HR monitor connected" : "HR monitor disconnected")
    }

    func didReceiveESPResponse(_ message: String) {
        addLog("ESP32: \(message)")
        if message.hasPrefix("ACK:START") { isStreaming = true }
        if message.hasPrefix("ACK:STOP") { isStreaming = false }
        if message.hasPrefix("MARK,") {
            let parts = message.split(separator: ",")
            if parts.count >= 3, let num = Int(parts[2]) {
                pitchCount = num
                addLog("Pitch #\(num) marked")
            }
        }
    }

    func didReceiveCalibration(_ data: [String: CalibrationData]) {
        calibration = data
        addLog("Calibration received")
    }
}
