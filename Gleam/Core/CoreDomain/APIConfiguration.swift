import Foundation

/// API Configuration - Replace these values with your actual API endpoints
/// 
/// IMPORTANT: 
/// - Replace FIREBASE_FUNCTIONS_URL with your Firebase Functions URL
/// - Example: "https://us-central1-gleam-prod.cloudfunctions.net"
/// - The OpenAI API key should NEVER be here - it belongs in your backend
/// - Set it in Firebase with: firebase functions:config:set openai.key="your-key"
enum APIConfiguration {
    
    // MARK: - Configuration Values
    // 👇 REPLACE THIS with one of your Firebase Functions URLs (e.g. analyze)
    static let firebaseFunctionsURL = "https://analyze-a7vtvf6tua-uc.a.run.app"
    
    // MARK: - Public Endpoints
    static var analyzeURL: URL {
        configuredURL(for: "API_ANALYZE_URL") ?? defaultURL(for: "analyze")
    }
    
    static var planURL: URL {
        configuredURL(for: "API_PLAN_URL") ?? defaultURL(for: "plan")
    }
    
    static var historyLatestURL: URL {
        configuredURL(for: "API_HISTORY_LATEST_URL") ?? defaultURL(for: "history", extraPath: "latest")
    }
    
    // Backwards compatibility
    static var baseURL: URL {
        analyzeURL
    }
    
    /// Check if API is configured
    static var isConfigured: Bool {
        let urlString = analyzeURL.absoluteString
        return !urlString.contains("example.invalid") && !urlString.contains("YOUR_")
    }
    
    // MARK: - Helpers
    
    private static func configuredURL(for key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("YOUR_"),
              let url = URL(string: value) else {
            return nil
        }
        return url
    }
    
    private static func defaultURL(for functionName: String, extraPath: String? = nil) -> URL {
        let fallback = URL(string: "https://example.invalid/\(functionName)")!
        
        guard !firebaseFunctionsURL.contains("YOUR_"),
              let base = URL(string: firebaseFunctionsURL) else {
            return fallback
        }
        
        if let host = base.host, host.contains(".a.run.app") {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            if let hyphenIndex = host.firstIndex(of: "-") {
                let suffix = host[hyphenIndex...] // includes the dash
                components?.host = "\(functionName)\(suffix)"
            } else {
                components?.host = "\(functionName)-\(host)"
            }
            let normalizedPath = extraPath?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
            components?.path = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"
            if let url = components?.url {
                return url
            }
        } else {
            var url = base.appendingPathComponent(functionName)
            if let extra = extraPath {
                url.appendPathComponent(extra)
            }
            return url
        }
        
        return fallback
    }
}

