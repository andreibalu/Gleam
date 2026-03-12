import XCTest
@testable import Gleam

@MainActor
final class ScanSessionTests: XCTestCase {

    func testInitialStateIsEmpty() {
        let session = ScanSession()
        XCTAssertNil(session.capturedImageData)
        XCTAssertFalse(session.shouldOpenCamera)
        XCTAssertFalse(session.shouldOpenHistory)
    }

    func testResetClearsAllState() {
        let session = ScanSession()
        session.capturedImageData = Data([0x01])
        session.shouldOpenCamera = true
        session.shouldOpenHistory = true

        session.reset()

        XCTAssertNil(session.capturedImageData)
        XCTAssertFalse(session.shouldOpenCamera)
        XCTAssertFalse(session.shouldOpenHistory)
    }

    func testCapturedImageDataCanBeSet() {
        let session = ScanSession()
        let data = Data([0xFF, 0xD8])
        session.capturedImageData = data
        XCTAssertEqual(session.capturedImageData, data)
    }

    func testResetAfterOnlySettingImageData() {
        let session = ScanSession()
        session.capturedImageData = Data([0xAB])
        session.reset()
        XCTAssertNil(session.capturedImageData)
        XCTAssertFalse(session.shouldOpenCamera)
        XCTAssertFalse(session.shouldOpenHistory)
    }
}
