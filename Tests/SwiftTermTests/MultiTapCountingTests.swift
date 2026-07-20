import XCTest
@testable import SwiftTerm

/// The pure double-tap-window rule behind `TerminalView.registerLocalTap` — the tap counting that
/// restores double-tap word-select / triple-tap line-select after the multi-tap
/// `UITapGestureRecognizer`s were removed for the iOS 26.5 delayed-touch crash. The gesture
/// plumbing can't be unit-tested, but this rule can, and it's the part a future upstream merge could
/// silently clobber. Thresholds are passed in, not the shipped tuning: every expectation pins the
/// *rule* ("continue only within both windows, else restart at 1"), never the specific 0.3 s /
/// 1.5-cell values the caller happens to use.
final class MultiTapCountingTests: XCTestCase {
    private let maxInterval: TimeInterval = 0.3
    private let maxDistance = 30.0

    private func length (previousCount: Int, interval: TimeInterval, distance: Double) -> Int {
        tapRunLength (previousCount: previousCount, interval: interval, distance: distance,
                      maxInterval: maxInterval, maxDistance: maxDistance)
    }

    /// A tap inside both windows advances the run, so 1→2 arms word-select and 2→3 arms line-select.
    func testCloseTapAdvancesTheRun () {
        XCTAssertEqual (length (previousCount: 1, interval: 0.1, distance: 5), 2)
        XCTAssertEqual (length (previousCount: 2, interval: 0.1, distance: 5), 3)
        XCTAssertEqual (length (previousCount: 3, interval: 0.1, distance: 5), 4)
    }

    /// A tap that is too slow, too far, or both restarts the run at 1 — breaking *either* window is
    /// enough on its own, so a stray tap can't accidentally seed a word/line selection.
    func testSlowOrFarTapRestartsAtOne () {
        XCTAssertEqual (length (previousCount: 2, interval: 0.5, distance: 5),   1)  // slow, near
        XCTAssertEqual (length (previousCount: 2, interval: 0.1, distance: 999), 1)  // fast, far
        XCTAssertEqual (length (previousCount: 2, interval: 0.5, distance: 999), 1)  // both
    }

    /// The window is inclusive (`<=`), so a tap exactly at the time and distance limits still
    /// continues the run — borderline-fast double-taps aren't dropped.
    func testBoundaryIsInclusive () {
        XCTAssertEqual (length (previousCount: 1, interval: maxInterval, distance: maxDistance), 2)
    }

    /// The first tap of a fresh sequence (no prior run: `previousCount` 0 and the initial, huge
    /// interval) is length 1 — never 0, so the `case 2` / `case 3` selection dispatch can't misfire.
    func testFirstTapIsLengthOne () {
        XCTAssertEqual (length (previousCount: 0, interval: 999, distance: 5), 1)
    }
}
