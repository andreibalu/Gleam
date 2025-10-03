import Foundation

enum AppConfig {
    static var apiBaseURL: URL {
        return APIConfiguration.baseURL
    }
    
    static var isAPIConfigured: Bool {
        return APIConfiguration.isConfigured
    }
}


