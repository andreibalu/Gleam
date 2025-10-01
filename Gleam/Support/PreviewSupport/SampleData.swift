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
        recommendations: Recommendations(
            immediate: ["Rinse with water", "Brush for 2 minutes"],
            daily: ["Use whitening toothpaste", "Floss once"],
            weekly: ["Whitening strips (low strength) 1x/week"],
            caution: ["Avoid highly acidic drinks"]
        ),
        referralNeeded: false,
        disclaimer: "Not a medical diagnosis. Consult a dentist for concerns.",
        planSummary: "Moderate staining; gradual whitening plan recommended."
    )
}


