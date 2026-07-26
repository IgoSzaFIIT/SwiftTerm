import XCTest
@testable import SwiftTerm

/// The pure rule that decides which momentum-coast samples move the terminal's viewport model
/// (`syncYDispFromContentOffset` in iOSTerminalView). Two coasts pull in opposite directions and
/// both are real:
///
/// - A flick that begins at the live tail never engages the freeze — its whole finger-down phase
///   sits inside the at-bottom band — so unless the coast is tracked, the viewport model stays
///   pinned to the newest line while the reader travels up into history. Everything read off it
///   then agrees, and agrees wrongly: the viewport reports that it follows output, so the one
///   control that gets the reader home is hidden.
/// - A fling *to* the bottom under streaming output must not re-freeze. The content grows faster
///   than the coast, so sample after sample reads "not at the bottom yet" while the reader has
///   already asked to go back to following.
///
/// Timing cannot tell them apart — both are post-lift deceleration on an unfrozen view. Direction
/// can, and that is what these expectations pin.
final class CoastingViewportTests: XCTestCase {
    private let offsetTolerance = 1.0 / 3.0 // one device pixel at 3x

    private func moves (isFrozen: Bool,
                        from previousOffsetY: Double,
                        to offsetY: Double,
                        previousOffsetIsFromTheScrollView: Bool = true) -> Bool {
        coastMovesTheViewport (isFrozen: isFrozen,
                               offsetY: offsetY,
                               previousOffsetY: previousOffsetY,
                               offsetTolerance: offsetTolerance,
                               previousOffsetIsFromTheScrollView: previousOffsetIsFromTheScrollView)
    }

    /// A coast on an already-frozen view always moves the viewport, whichever way it travels: the
    /// reader has unpinned from the tail, and the content is still visibly scrolling under them.
    func testAFrozenCoastAlwaysMovesTheViewport () {
        XCTAssertTrue (moves (isFrozen: true, from: 5000, to: 4000))
        XCTAssertTrue (moves (isFrozen: true, from: 4000, to: 5000))
        XCTAssertTrue (moves (isFrozen: true, from: 5000, to: 5000))
    }

    /// An unfrozen coast travelling *away* from the bottom is the flick that began at the live tail:
    /// the freeze never engaged, so this is the only chance to notice the reader left.
    func testAnUnfrozenCoastAwayFromTheBottomMovesTheViewport () {
        XCTAssertTrue (moves (isFrozen: false, from: 53788, to: 53741))
    }

    /// An unfrozen coast travelling *toward* the bottom is the fling home under streaming output,
    /// and must be left alone — freezing there would strand a reader who just asked to follow again.
    func testAnUnfrozenCoastTowardTheBottomIsLeftAlone () {
        XCTAssertFalse (moves (isFrozen: false, from: 53741, to: 53788))
    }

    /// The same fling, at the moment the coast has run out but streaming output keeps extending the
    /// content: the offset stands still while the bottom recedes ahead of it. Standing still is not
    /// travel, so this is left alone too — the case direction is chosen over "how far from the
    /// bottom" precisely to cover.
    func testAnUnfrozenCoastStandingStillIsLeftAlone () {
        XCTAssertFalse (moves (isFrozen: false, from: 53741, to: 53741))
    }

    /// A downward drift smaller than a device pixel is float noise at the end of a coast, not the
    /// reader travelling — it must not be enough to freeze a view that is following output. A whole
    /// pixel is; the line falls at `offsetTolerance`, which is what the caller renders with.
    func testASubPixelDriftIsNotTravel () {
        XCTAssertFalse (moves (isFrozen: false, from: 51666.67, to: 51666.5))
        XCTAssertTrue  (moves (isFrozen: false, from: 51666.67, to: 51665.67))
    }

    /// The tolerance is the exclusive edge, not the first qualifying value: a move of exactly one
    /// device pixel is still noise, and anything past it is travel. Pinned because the rule is a
    /// strict comparison and an off-by-one-pixel reading here is a freeze the reader did not ask for.
    func testTheToleranceItselfIsNotYetTravel () {
        XCTAssertFalse (moves (isFrozen: false, from: 51666.67, to: 51666.67 - offsetTolerance))
        XCTAssertTrue  (moves (isFrozen: false, from: 51666.67, to: 51666.67 - offsetTolerance - 0.01))
    }

    /// An offset the *view* wrote is not a sample of where the reader is travelling, and comparing
    /// against one is how the protected case comes back. While the freeze is off the view writes the
    /// offset between coast frames — pinning to the tail as output arrives, landing a jump home,
    /// following the caret — and every one of those writes moves it toward the bottom, so the next
    /// genuine sample reads as a move away from it. Read that as travel and a view the reader just
    /// sent back to the live tail freezes itself again.
    func testACoastSampleAfterTheViewWroteTheOffsetIsLeftAlone () {
        XCTAssertFalse (moves (isFrozen: false, from: 53788, to: 53741, previousOffsetIsFromTheScrollView: false))
    }

    /// The frozen half does not depend on the comparison at all, so a written predecessor cannot
    /// strand a reader who *is* travelling through history — that coast keeps being tracked.
    func testAFrozenCoastIsUnaffectedByAWrittenPredecessor () {
        XCTAssertTrue (moves (isFrozen: true, from: 53788, to: 53741, previousOffsetIsFromTheScrollView: false))
    }

    /// And the very next sample has a real predecessor again, so a flick that began at the tail is
    /// caught one frame later rather than never — the cost of the rule above, bounded and pinned.
    func testTheSampleAfterThatIsReadNormally () {
        XCTAssertTrue (moves (isFrozen: false, from: 53741, to: 53694, previousOffsetIsFromTheScrollView: true))
    }
}
