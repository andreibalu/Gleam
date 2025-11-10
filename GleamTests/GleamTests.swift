//
//  GleamTests.swift
//  GleamTests
//
//  Created by andrei on 01.10.2025.
//

import XCTest
@testable import Gleam

final class GleamUnitTests: XCTestCase {

    func testScanResultCodableRoundTrip() throws {
        let original = ScanResult(
            whitenessScore: 50,
            shade: "A3",
            detectedIssues: [DetectedIssue(key: "staining", severity: "low", notes: "")],
            confidence: 0.8,
            referralNeeded: false,
            disclaimer: "Not a diagnosis",
            personalTakeaway: "Summary"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScanResult.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
