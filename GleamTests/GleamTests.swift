//
//  GleamTests.swift
//  GleamTests
//
//  Created by andrei on 01.10.2025.
//

import XCTest
@testable import Gleam

@MainActor
final class GleamUnitTests: XCTestCase {

    // MARK: - ScanResult

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

    func testScanResultDecodesLegacyPlanSummaryKey() throws {
        let json: [String: Any] = [
            "whitenessScore": 72,
            "shade": "B1",
            "confidence": 0.9,
            "planSummary": "Legacy takeaway text"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = try JSONDecoder().decode(ScanResult.self, from: data)
        XCTAssertEqual(result.personalTakeaway, "Legacy takeaway text")
        XCTAssertEqual(result.whitenessScore, 72)
    }

    func testScanResultDecodesWithMissingOptionalFields() throws {
        let json: [String: Any] = [
            "whitenessScore": 60,
            "shade": "A2",
            "confidence": 0.75
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = try JSONDecoder().decode(ScanResult.self, from: data)
        XCTAssertEqual(result.detectedIssues, [])
        XCTAssertEqual(result.disclaimer, "")
        XCTAssertEqual(result.personalTakeaway, "")
        XCTAssertFalse(result.referralNeeded)
    }

    func testScanResultPersonalTakeawayPreferredOverLegacy() throws {
        let json: [String: Any] = [
            "whitenessScore": 65,
            "shade": "A3",
            "confidence": 0.8,
            "personalTakeaway": "New field value",
            "planSummary": "Legacy field value"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = try JSONDecoder().decode(ScanResult.self, from: data)
        XCTAssertEqual(result.personalTakeaway, "New field value")
    }

    // MARK: - HistoryItem

    func testHistoryItemCodableRoundTrip() throws {
        let original = HistoryItem(
            id: "test-id-42",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            result: SampleData.sampleResult,
            contextTags: ["coffee", "tea"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(HistoryItem.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testHistoryItemDecodesWithMissingContextTags() throws {
        let resultJSON: [String: Any] = [
            "whitenessScore": 68,
            "shade": "A2",
            "confidence": 0.85
        ]
        let json: [String: Any] = [
            "id": "some-id",
            "createdAt": "2024-01-01T12:00:00Z",
            "result": resultJSON
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(HistoryItem.self, from: data)
        XCTAssertEqual(item.contextTags, [])
    }

    func testHistoryItemEncodesContextTagsWhenNonEmpty() throws {
        let item = HistoryItem(
            id: "id",
            createdAt: Date(timeIntervalSince1970: 1_000),
            result: SampleData.sampleResult,
            contextTags: ["coffee"]
        )
        let data = try JSONEncoder().encode(item)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tags = try XCTUnwrap(json["contextTags"] as? [String])
        XCTAssertEqual(tags, ["coffee"])
    }

    func testHistoryItemOmitsContextTagsWhenEmpty() throws {
        let item = HistoryItem(
            id: "id",
            createdAt: Date(timeIntervalSince1970: 1_000),
            result: SampleData.sampleResult,
            contextTags: []
        )
        let data = try JSONEncoder().encode(item)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["contextTags"])
    }

    // MARK: - DetectedIssue

    func testDetectedIssueCodableRoundTrip() throws {
        let issue = DetectedIssue(key: "plaque", severity: "high", notes: "Significant buildup")
        let data = try JSONEncoder().encode(issue)
        let decoded = try JSONDecoder().decode(DetectedIssue.self, from: data)
        XCTAssertEqual(issue, decoded)
    }

    // MARK: - Fixtures

    func testFixturesScanResultJSONDecodesSuccessfully() throws {
        let data = try Fixtures.scanResultJSON()
        let result = try JSONDecoder().decode(ScanResult.self, from: data)
        XCTAssertEqual(result.whitenessScore, 70)
        XCTAssertEqual(result.shade, "B1")
        XCTAssertEqual(result.confidence, 0.9)
        XCTAssertFalse(result.referralNeeded)
        XCTAssertEqual(result.detectedIssues.count, 1)
    }
}
