import Foundation

// snapshot of Whoop data passed into the recorder per frame
// live values update each frame, context values are session constants.

struct WhoopFrameContext {
    // live, updated per frame
    let heartRate: Int?
    let sessionLoad: Double
    let hrZone: Int
    
    // session constants, set once at startRecording
    let recoveryScore: Double
    let hrvRmssd: Double
    let restingHeartRate: Double
    let dayStrainAtStart: Double
    
    static let empty = WhoopFrameContext(
        heartRate: nil,
        sessionLoad: 0,
        hrZone: 0,
        recoveryScore: 0,
        hrvRmssd: 0,
        restingHeartRate: 0,
        dayStrainAtStart: 0
    )
}
