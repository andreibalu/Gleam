import XCTest
@testable import Gleam

@MainActor
final class ScanSessionTests: XCTestCase {

    #if DEBUG
    private static var leakedSessions: [ScanSession] = []
    #endif

    private func makeSession() -> ScanSession {
        let session = ScanSession()
        #if DEBUG
        Self.leakedSessions.append(session)
        #endif
        return session
    }

    func testInitialStateIsEmpty() {
        let session = makeSession()
        XCTAssertNil(session.capturedImageData)
        XCTAssertFalse(session.shouldOpenCamera)
        XCTAssertFalse(session.shouldOpenHistory)
    }

    func testResetClearsAllState() {
        let session = makeSession()
        session.capturedImageData = Data([0x01])
        session.shouldOpenCamera = true
        session.shouldOpenHistory = true

        session.reset()

        XCTAssertNil(session.capturedImageData)
        XCTAssertFalse(session.shouldOpenCamera)
        XCTAssertFalse(session.shouldOpenHistory)
    }

    func testCapturedImageDataCanBeSet() {
        let session = makeSession()
        let data = Data([0xFF, 0xD8])
        session.capturedImageData = data
        XCTAssertEqual(session.capturedImageData, data)
    }

    func testResetAfterOnlySettingImageData() {
        let session = makeSession()
        session.capturedImageData = Data([0xAB])
        session.reset()
        XCTAssertNil(session.capturedImageData)
        XCTAssertFalse(session.shouldOpenCamera)
        XCTAssertFalse(session.shouldOpenHistory)
    }
}
