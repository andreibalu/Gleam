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
    // 👇 REPLACE THIS with your Firebase Functions URL
    static let firebaseFunctionsURL = "YOUR_FIREBASE_FUNCTIONS_URL_HERE"
    
    // MARK: - Computed Properties
    static var baseURL: URL {
        // First try to get from Info.plist (if using xcconfig)
        if let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !value.isEmpty,
           !value.contains("YOUR_"),
           let url = URL(string: value) {
            return url
        }
        
        // Fall back to hardcoded value (for quick setup)
        if !firebaseFunctionsURL.contains("YOUR_"),
           let url = URL(string: firebaseFunctionsURL) {
            return url
        }
        
        // Default for development/mocking
        return URL(string: "https://example.invalid")!
    }
    
    /// Check if API is configured
    static var isConfigured: Bool {
        let urlString = baseURL.absoluteString
        return !urlString.contains("example.invalid") && !urlString.contains("YOUR_")
    }
}

