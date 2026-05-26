import Foundation
import Combine

// TRIMP calculator.
// buckets HR samples into five zones and accumulates weighted time.
// also runs a 60-second resting HR calibration at start.

@MainActor
final class TRIMPCalculator: ObservableObject {
    
    @Published private(set) var sessionLoad: Double = 0
    @Published private(set) var currentZone: Int = 0
    @Published private(set) var timeInZones: [TimeInterval] = [0, 0, 0, 0, 0, 0]
    @Published private(set) var isCalibrating: Bool = true
    @Published private(set) var calibratedRHR: Double = 0
    
    // override with setMaxHR() once user enters their age or we pull from Whoop.
    private var maxHR: Double = 198
    private var lastSampleTime: Date?
    private var sessionStartTime: Date?
    private var calibrationSamples: [Int] = []
    private let calibrationDuration: TimeInterval = 60
    
    // configure with user-specific values. call before startSession().
    func setMaxHR(_ value: Double) {
        maxHR = value
    }
    
    // seed RHR from Whoop if available, skips calibration phase.
    func seedRestingHR(_ value: Double) {
        calibratedRHR = value
        isCalibrating = false
    }
    
    func startSession() {
        sessionLoad = 0
        currentZone = 0
        timeInZones = [0, 0, 0, 0, 0, 0]
        lastSampleTime = nil
        sessionStartTime = Date()
        if calibratedRHR == 0 {
            isCalibrating = true
            calibrationSamples = []
        }
    }
    
    func stopSession() {
        lastSampleTime = nil
        sessionStartTime = nil
    }
    
    // feed every BLE HR sample through this.
    func ingest(hr: Int, at time: Date) {
        // calibration phase: collect samples for the first 60 seconds
        if isCalibrating, let start = sessionStartTime {
            calibrationSamples.append(hr)
            if time.timeIntervalSince(start) >= calibrationDuration {
                finishCalibration()
            }
            lastSampleTime = time
            return
        }
        
        //active accumulation
        let zone = computeZone(hr: hr)
        currentZone = zone
        
        if let last = lastSampleTime {
            let dt = time.timeIntervalSince(last)
            //cap dt to avoid runaway accumulation on BLE gaps
            let clampedDt = min(dt, 5.0)
            timeInZones[zone] += clampedDt
            //  minutes_in_zone * zone_weight
            sessionLoad += (clampedDt / 60.0) * Double(zone)
        }
        lastSampleTime = time
    }
    
    private func finishCalibration() {
        guard !calibrationSamples.isEmpty else {
            isCalibrating = false
            calibratedRHR = 60
            return
        }
        let sum = calibrationSamples.reduce(0, +)
        calibratedRHR = Double(sum) / Double(calibrationSamples.count)
        isCalibrating = false
        calibrationSamples = []
    }
    
    // zone boundaries based on percentage of max HR.
    // zone 0 = below 50% (unweighted, recovery / pre-session)
    // zone 1-5 = the standard Edwards bands.
    private func computeZone(hr: Int) -> Int {
        let pct = Double(hr) / maxHR
        switch pct {
        case ..<0.50: return 0
        case 0.50..<0.60: return 1
        case 0.60..<0.70: return 2
        case 0.70..<0.80: return 3
        case 0.80..<0.90: return 4
        default: return 5
        }
    }
}
