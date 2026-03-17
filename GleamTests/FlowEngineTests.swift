import XCTest
@testable import Gleam

@MainActor
final class FlowEngineTests: XCTestCase {

    #if DEBUG
    private static var leakedEngines: [FlowEngine] = []
    #endif

    private func makeEngine() -> FlowEngine {
        let engine = FlowEngine()
        #if DEBUG
        Self.leakedEngines.append(engine)
        #endif
        return engine
    }

    // MARK: - FlowQuadrant

    func testFlowQuadrantHasFourCases() {
        XCTAssertEqual(FlowQuadrant.allCases.count, 4)
    }

    func testFlowQuadrantCaseOrder() {
        let cases = FlowQuadrant.allCases
        XCTAssertEqual(cases[0], .upperRight)
        XCTAssertEqual(cases[1], .upperLeft)
        XCTAssertEqual(cases[2], .lowerLeft)
        XCTAssertEqual(cases[3], .lowerRight)
    }

    func testFlowQuadrantInstructionsAreNonEmpty() {
        for quadrant in FlowQuadrant.allCases {
            XCTAssertFalse(quadrant.instruction.isEmpty, "\(quadrant) instruction should not be empty")
        }
    }

    // MARK: - Initial state

    func testInitialStatusIsIdle() {
        let engine = makeEngine()
        XCTAssertEqual(engine.status, .idle)
    }

    func testInitialTimeRemainingIs120() {
        let engine = makeEngine()
        XCTAssertEqual(engine.timeRemaining, 120)
    }

    func testInitialProgressIsZero() {
        let engine = makeEngine()
        XCTAssertEqual(engine.progress, 0)
    }

    func testInitialQuadrantIsUpperRight() {
        let engine = makeEngine()
        XCTAssertEqual(engine.currentQuadrant, .upperRight)
    }

    func testInitialBriefingIsNil() {
        let engine = makeEngine()
        XCTAssertNil(engine.currentBriefing)
    }

    // MARK: - start()

    func testStartFromIdleTransitionsToRunning() {
        let engine = makeEngine()
        engine.start()
        XCTAssertEqual(engine.status, .running)
    }

    func testStartFromIdleSetsTimeRemainingTo120() {
        let engine = makeEngine()
        engine.start()
        XCTAssertEqual(engine.timeRemaining, 120)
    }

    func testStartFromRunningIsNoOp() {
        let engine = makeEngine()
        engine.start()
        engine.start()
        XCTAssertEqual(engine.status, .running)
    }

    // MARK: - pause()

    func testPauseFromRunningTransitionsToPaused() {
        let engine = makeEngine()
        engine.start()
        engine.pause()
        XCTAssertEqual(engine.status, .paused)
    }

    func testPauseFromIdleIsNoOp() {
        let engine = makeEngine()
        engine.pause()
        XCTAssertEqual(engine.status, .idle)
    }

    func testPauseFromPausedIsNoOp() {
        let engine = makeEngine()
        engine.start()
        engine.pause()
        engine.pause()
        XCTAssertEqual(engine.status, .paused)
    }

    // MARK: - reset()

    func testResetFromRunningRestoresIdleState() {
        let engine = makeEngine()
        engine.start()
        engine.reset()
        XCTAssertEqual(engine.status, .idle)
        XCTAssertEqual(engine.timeRemaining, 120)
        XCTAssertEqual(engine.currentQuadrant, .upperRight)
        XCTAssertEqual(engine.progress, 0)
    }

    func testResetFromPausedRestoresIdleState() {
        let engine = makeEngine()
        engine.start()
        engine.pause()
        engine.reset()
        XCTAssertEqual(engine.status, .idle)
        XCTAssertEqual(engine.timeRemaining, 120)
        XCTAssertEqual(engine.progress, 0)
    }

    func testResetFromIdleIsNoOp() {
        let engine = makeEngine()
        engine.reset()
        XCTAssertEqual(engine.status, .idle)
        XCTAssertEqual(engine.timeRemaining, 120)
    }

    // MARK: - Resume (start from paused)

    func testStartFromPausedResumesWithoutResetting() {
        let engine = makeEngine()
        engine.start()
        engine.pause()
        engine.start()
        XCTAssertEqual(engine.status, .running)
    }
}
