import Foundation

enum Fixtures {
    static func scanResultJSON() throws -> Data {
        let dict: [String: Any] = [
            "whitenessScore": 70,
            "shade": "B1",
            "detectedIssues": [[
                "key": "staining",
                "severity": "low",
                "notes": "Mild staining"
            ]],
            "confidence": 0.9,
            "referralNeeded": false,
            "disclaimer": "Not a medical diagnosis.",
            "personalTakeaway": "Keep up gentle whitening habits."
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }
}


