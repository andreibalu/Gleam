import Foundation

enum SampleData {
    static let sampleResult = ScanResult(
        whitenessScore: 68,
        shade: "A2",
        detectedIssues: [
            DetectedIssue(key: "staining", severity: "medium", notes: "Surface staining along incisors"),
            DetectedIssue(key: "plaque", severity: "low", notes: "Minor plaque visible near gumline")
        ],
        confidence: 0.85,
        referralNeeded: false,
        disclaimer: "Not a medical diagnosis. Consult a dentist for concerns.",
        personalTakeaway: "Moderate staining—keep up gentle whitening habits."
    )
}


