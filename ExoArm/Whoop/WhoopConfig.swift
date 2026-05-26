import Foundation

// Whoop OAuth and API configuration.
// GITIGNORE THIS FILE. Client secret must never be committed.

enum WhoopConfig {
    
    //from the Whoop Developer Dashboard
    static let clientID = "input client id here"
    static let clientSecret = "input client secret here"
    
    //must match what is registered in the dashboard
    static let redirectURI = "pitcherrehab://oauth/callback"
    static let redirectScheme = "pitcherrehab"
    
    //Whoop OAuth endpoints
    static let authURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    static let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"
    static let apiBase = "https://api.prod.whoop.com/developer"
    
    //offline gives us a refresh token.
    //read:recovery covers HRV, RHR, recovery score, and read:cycles covers day strain context.
    static let scopes = [
        "offline",
        "read:recovery",
        "read:cycles"
    ]
    
    static var scopeString: String {
        scopes.joined(separator: " ")
    }
}
