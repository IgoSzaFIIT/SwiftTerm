import XCTest
@testable import SwiftTerm

/// The pure landing rule behind `TerminalView.accessibilityScroll` — where a viewport move that no
/// finger made leaves the terminal's own viewport model. The scroll view's `contentOffset` says what
/// is rendered; `yDisp` says which buffer rows the viewport *names*, and everything derived from the
/// viewport (the row, the distance behind the live tail, whether output is being followed) is read
/// off `yDisp` alone. When the two disagree they agree wrongly — the viewport reports that it
/// follows output while the reader sits up in history — so this rule is what keeps them together for
/// a move the drag path never sees.
///
/// Every expectation pins the *rule*, never the shipped tuning: thresholds and cell heights are
/// passed in, and the geometry below is chosen for arithmetic that is obvious by eye.
final class ViewportScrollTests: XCTestCase {
    // A viewport 10 rows tall over a 100-row buffer: 90 rows of history above the newest screen,
    // and a bottom that rests 900 pt down.
    private let cellHeight = 10.0
    private let maxRow = 90
    private let maxContentOffsetY = 900.0
    private let atBottomThreshold = 5.0     // half a cell, as the view derives it
    private let offsetTolerance = 1.0 / 3.0 // one device pixel at 3x

    private func landing (_ targetOffsetY: Double,
                          maxContentOffsetY: Double? = nil,
                          file: StaticString = #filePath,
                          line: UInt = #line) throws -> ViewportScrollLanding {
        try XCTUnwrap (viewportScrollLanding (targetOffsetY: targetOffsetY,
                                              maxContentOffsetY: maxContentOffsetY ?? self.maxContentOffsetY,
                                              maxRow: maxRow,
                                              cellHeight: cellHeight,
                                              atBottomThreshold: atBottomThreshold,
                                              offsetTolerance: offsetTolerance),
                       file: file, line: line)
    }

    /// A move that lands short of the bottom names the row under it and **engages** the freeze. This
    /// is the whole point: without it the viewport keeps naming the live tail, reports that it is
    /// following output, and the next arriving line yanks the reader back down.
    func testALandingShortOfTheBottomNamesItsRowAndFreezes () throws {
        XCTAssertEqual (try landing (500), ViewportScrollLanding (row: 50, freezesScrolling: true, offsetWithinRow: 0))
        XCTAssertEqual (try landing (0),   ViewportScrollLanding (row: 0,  freezesScrolling: true, offsetWithinRow: 0))
    }

    /// A move that lands at the bottom names the newest screen and **releases** the freeze, so
    /// auto-follow re-engages exactly as a drag back to the bottom makes it.
    func testALandingAtTheBottomFollowsOutputAgain () throws {
        XCTAssertEqual (try landing (maxContentOffsetY),
                        ViewportScrollLanding (row: maxRow, freezesScrolling: false, offsetWithinRow: 0))
    }

    /// The at-bottom band is inclusive at its far edge and exclusive just inside it: resting exactly
    /// `atBottomThreshold` short of the maximum still counts as the bottom, and a hair further up
    /// does not. A partial last row and `contentInset` rounding are why the band exists at all — an
    /// exact-maximum test left the freeze permanently engaged.
    func testTheAtBottomBandIsRespectedAtItsBoundary () throws {
        let onTheEdge = try landing (maxContentOffsetY - atBottomThreshold)
        XCTAssertFalse (onTheEdge.freezesScrolling)
        XCTAssertEqual (onTheEdge.row, maxRow)

        let justInside = try landing (maxContentOffsetY - atBottomThreshold - 0.5)
        XCTAssertTrue (justInside.freezesScrolling)
        XCTAssertEqual (justInside.row, 89)
    }

    /// An overscroll past the bottom is still the bottom, and a move above the first row is still
    /// the first row — a landing can never name a row outside the buffer's window.
    func testTargetsOutsideTheScrollableRangeClampIntoIt () throws {
        XCTAssertEqual (try landing (maxContentOffsetY + 400),
                        ViewportScrollLanding (row: maxRow, freezesScrolling: false, offsetWithinRow: 0))

        let aboveTheTop = try landing (-400)
        XCTAssertEqual (aboveTheTop.row, 0)
        XCTAssertTrue (aboveTheTop.freezesScrolling)
        XCTAssertEqual (aboveTheTop.offsetWithinRow, 0, accuracy: 0.000_1)
    }

    /// A bottom inset — an accessory view, the safe area, the keyboard — pushes the scroll view's
    /// resting maximum *past* the last row's own offset, which is the whole reason the landing
    /// clamps to `maxRow` rather than trusting the division. Here the maximum sits 40 pt beyond
    /// row 90, so an offset short of the at-bottom band can still divide out to a row the buffer
    /// does not have; the viewport must name the newest screen instead of one past it, and the
    /// remainder must still reproduce where the view rests.
    func testAnInsetPastTheLastRowStillNamesTheLastRow () throws {
        let withInset = try landing (930, maxContentOffsetY: 940)
        XCTAssertEqual (withInset.row, maxRow)
        XCTAssertTrue (withInset.freezesScrolling)
        XCTAssertEqual (Double (withInset.row) * cellHeight + withInset.offsetWithinRow, 930, accuracy: 0.000_1)
    }

    /// `offsetWithinRow` is the remainder that reproduces the resting offset from the row, so a
    /// landing between two rows renders where it landed instead of snapping to the cell grid.
    func testOffsetWithinRowReproducesTheRestingOffset () throws {
        let between = try landing (503)
        XCTAssertEqual (between.row, 50)
        XCTAssertEqual (Double (between.row) * cellHeight + between.offsetWithinRow, 503, accuracy: 0.000_1)
    }

    /// The sub-pixel tolerance rounds an offset resting a hair under a row boundary onto that row,
    /// rather than leaving it naming the row above — the same slack the drag path applies.
    func testASubPixelShortfallStillNamesTheRowBelow () throws {
        XCTAssertEqual (try landing (500 - offsetTolerance / 2).row, 50)
    }

    /// With no cell grid to read — a view that has not been laid out yet — there is **no** landing.
    /// The tempting answer, the bottom, is the harmful one: it would say the viewport follows output
    /// while the offset moves away from the tail, which is the exact false reading this rule exists
    /// to prevent. Answering `nil` leaves the viewport model untouched instead.
    func testAZeroCellHeightHasNoLanding () {
        XCTAssertNil (viewportScrollLanding (targetOffsetY: 500,
                                             maxContentOffsetY: maxContentOffsetY,
                                             maxRow: maxRow,
                                             cellHeight: 0,
                                             atBottomThreshold: atBottomThreshold,
                                             offsetTolerance: offsetTolerance))
    }
}
