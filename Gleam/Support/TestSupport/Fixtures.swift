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
            "recommendations": [
                "immediate": ["Rinse"],
                "daily": ["Brush twice"],
                "weekly": ["Whitening strips"],
                "caution": ["Avoid coffee"]
            ],
            "referralNeeded": false,
            "disclaimer": "Not a medical diagnosis.",
            "planSummary": "Light whitening plan"
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }
}


