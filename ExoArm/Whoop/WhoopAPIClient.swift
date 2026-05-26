import Foundation

// thin REST client for the Whoop API.
// all calls go through currentAccessToken() so refresh is clear

@MainActor
final class WhoopAPIClient {
    
    private let oauth: WhoopOAuthManager
    private let session: URLSession
    
    init(oauth: WhoopOAuthManager) {
        self.oauth = oauth
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }
    
    // pulls a full session context snapshot
    // walks recent cycles to find the most recent one with some recovery score (if its been a while since it was worn, might show up blank)
    func fetchSessionContext() async throws -> WhoopSessionContext {
        let cycles = try await fetchRecentCycles(limit: 10)
        let latest = cycles.first
        let dayStrain = latest?.score?.strain ?? 0
        
        var foundRecovery: WhoopRecovery?
        for cycle in cycles {
            do {
                let recovery = try await fetchRecovery(forCycleId: cycle.id)
                foundRecovery = recovery
                break
            } catch WhoopAPIError.notFound {
                continue
            }
        }
        
        let recoveryPct = foundRecovery?.score?.recoveryScore ?? 0
        let hrv = foundRecovery?.score?.hrvRmssdMilli ?? 0
        let rhr = foundRecovery?.score?.restingHeartRate ?? 0
        
        return WhoopSessionContext(
            recoveryScore: recoveryPct,
            hrvRmssd: hrv,
            restingHeartRate: rhr,
            dayStrainSoFar: dayStrain,
            timestamp: Date()
        )
    }
    
    func fetchRecentCycles(limit: Int) async throws -> [WhoopCycle] {
        let url = URL(string: "\(WhoopConfig.apiBase)/v2/cycle?limit=\(limit)")!
        let page: WhoopPaginated<WhoopCycle> = try await get(url: url)
        return page.records
    }
    
    func fetchRecovery(forCycleId cycleId: Int) async throws -> WhoopRecovery {
        let url = URL(string: "\(WhoopConfig.apiBase)/v2/cycle/\(cycleId)/recovery")!
        return try await get(url: url)
    }
    
    private func get<T: Decodable>(url: URL) async throws -> T {
        var token = try await oauth.currentAccessToken()
        var (data, response) = try await performGet(url: url, token: token)
        
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            token = try await oauth.currentAccessToken()
            (data, response) = try await performGet(url: url, token: token)
        }
        
        guard let http = response as? HTTPURLResponse else {
            throw WhoopAPIError.invalidResponse
        }
        
        switch http.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw WhoopAPIError.decodeFailed(error.localizedDescription)
            }
        case 401:
            throw WhoopAPIError.unauthorized
        case 404:
            throw WhoopAPIError.notFound
        case 429:
            throw WhoopAPIError.rateLimited
        default:
            throw WhoopAPIError.httpError(http.statusCode)
        }
    }
    
    private func performGet(url: URL, token: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await session.data(for: request)
    }
}

enum WhoopAPIError: Error, LocalizedError {
    case unauthorized
    case notFound
    case rateLimited
    case emptyResponse
    case invalidResponse
    case httpError(Int)
    case decodeFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Whoop API rejected the token. Re-authorize."
        case .notFound: return "Whoop resource not found."
        case .rateLimited: return "Whoop rate limit hit. Back off and retry."
        case .emptyResponse: return "Whoop returned no records."
        case .invalidResponse: return "Whoop response was not an HTTP response."
        case .httpError(let code): return "Whoop HTTP error \(code)."
        case .decodeFailed(let msg): return "Failed to decode Whoop response: \(msg)"
        }
    }
}
