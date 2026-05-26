import Foundation

// Whoop v2 API response models.

//token response from /oauth/oauth2/token
struct WhoopTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

//recovery metric stuff from /v2/cycle/{cycleId}/recovery
struct WhoopRecovery: Codable {
    let cycleId: Int
    let sleepId: String
    let userId: Int
    let createdAt: String
    let updatedAt: String
    let scoreState: String
    let score: WhoopRecoveryScore?
    
    enum CodingKeys: String, CodingKey {
        case cycleId = "cycle_id"
        case sleepId = "sleep_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case scoreState = "score_state"
        case score
    }
}

struct WhoopRecoveryScore: Codable {
    let userCalibrating: Bool
    let recoveryScore: Double
    let restingHeartRate: Double
    let hrvRmssdMilli: Double
    let spo2Percentage: Double?
    let skinTempCelsius: Double?
    
    enum CodingKeys: String, CodingKey {
        case userCalibrating = "user_calibrating"
        case recoveryScore = "recovery_score"
        case restingHeartRate = "resting_heart_rate"
        case hrvRmssdMilli = "hrv_rmssd_milli"
        case spo2Percentage = "spo2_percentage"
        case skinTempCelsius = "skin_temp_celsius"
    }
}

// cycle from /v2/cycle or /v2/cycle/{cycleId}
struct WhoopCycle: Codable {
    let id: Int
    let userId: Int
    let createdAt: String
    let updatedAt: String
    let start: String
    let end: String?
    let timezoneOffset: String
    let scoreState: String
    let score: WhoopCycleScore?
    
    enum CodingKeys: String, CodingKey {
        case id, start, end, score
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case timezoneOffset = "timezone_offset"
        case scoreState = "score_state"
    }
}

struct WhoopCycleScore: Codable {
    let strain: Double
    let kilojoule: Double
    let averageHeartRate: Int
    let maxHeartRate: Int
    
    enum CodingKeys: String, CodingKey {
        case strain, kilojoule
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
    }
}

// paginated response wrapper used by the collection endpoints.
struct WhoopPaginated<T: Codable>: Codable {
    let records: [T]
    let nextToken: String?
    
    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

// snapshot passed to the UI and the session recorder.
// constants for the whole session, they are pulled once at session start.
struct WhoopSessionContext {
    let recoveryScore: Double
    let hrvRmssd: Double
    let restingHeartRate: Double
    let dayStrainSoFar: Double
    let timestamp: Date
    
    static let empty = WhoopSessionContext(
        recoveryScore: 0,
        hrvRmssd: 0,
        restingHeartRate: 0,
        dayStrainSoFar: 0,
        timestamp: Date()
    )
}
