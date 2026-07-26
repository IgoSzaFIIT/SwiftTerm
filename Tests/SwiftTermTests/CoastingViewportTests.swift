import XCTest
@testable import SwiftTerm

/// The pure rule that decides which momentum-coast samples move the terminal's viewport model
/// (`syncYDispFromContentOffset` in iOSTerminalView). Coasts pull in opposite directions and both
/// sides are real:
///
/// - A flick that begins at the live tail never engages the freeze — its whole finger-down phase
///   sits inside the at-bottom band — so unless the coast is tracked, the viewport model stays
///   pinned to the newest line while the reader travels up into history. Everything read off it
///   then agrees, and agrees wrongly: the viewport reports that it follows output, so the one
///   control that gets the reader home is hidden.
/// - A coast the reader has already **overruled** must be left alone. Three shapes of that exist —
///   the fling *to* the bottom under streaming output, a jump back to the tail landed mid-coast,
///   and the caret pulling the viewport home — and each re-freezes a viewport the reader just sent
///   back to the tail if the rule picks it up.
///
/// Timing cannot tell them apart: every one is post-lift deceleration on an unfrozen view. Nor can
/// direction alone, since all of them travel away from a bottom that has just moved. What separates
/// them is **gesture scope** — whether the freeze engaged anywhere in the gesture the coast belongs
/// to — and that, with direction as the second condition, is what these expectations pin.
final class CoastingViewportTests: XCTestCase {
    private let offsetTolerance = 1.0 / 3.0 // one device pixel at 3x

    private func moves (isFrozen: Bool,
                        froze freezeEngagedDuringGesture: Bool = false,
                        from previousOffsetY: Double,
                        to offsetY: Double) -> Bool {
        coastMovesTheViewport (isFrozen: isFrozen,
                               freezeEngagedDuringGesture: freezeEngagedDuringGesture,
                               offsetY: offsetY,
                               previousOffsetY: previousOffsetY,
                               offsetTolerance: offsetTolerance)
    }

    /// A coast on an already-frozen view always moves the viewport, whichever way it travels: the
    /// reader has unpinned from the tail, and the content is still visibly scrolling under them.
    func testAFrozenCoastAlwaysMovesTheViewport () {
        XCTAssertTrue (moves (isFrozen: true, from: 5000, to: 4000))
        XCTAssertTrue (moves (isFrozen: true, from: 4000, to: 5000))
        XCTAssertTrue (moves (isFrozen: true, from: 5000, to: 5000))
    }

    /// The flick that begins at the live tail: the freeze never engaged anywhere in the gesture, so
    /// this coast is the only chance to notice the reader left.
    func testAnUnfrozenCoastFromAGestureThatNeverFrozeMovesTheViewport () {
        XCTAssertTrue (moves (isFrozen: false, froze: false, from: 53788, to: 53741))
    }

    /// The same sample, from a gesture that *did* freeze earlier — the fling to the bottom whose
    /// at-bottom landing released the freeze, the jump home tapped mid-coast, the caret pulling the
    /// viewport back. The reader has overruled this coast; picking it up would strand them in
    /// history one frame after they asked for the tail.
    func testAnUnfrozenCoastFromAGestureThatFrozeIsLeftAlone () {
        XCTAssertFalse (moves (isFrozen: false, froze: true, from: 53788, to: 53741))
    }

    /// Direction still has to hold on top of the scope. A coast travelling *toward* the bottom is
    /// not the reader leaving, whatever the gesture did earlier.
    func testAnUnfrozenCoastTowardTheBottomIsLeftAlone () {
        XCTAssertFalse (moves (isFrozen: false, froze: false, from: 53741, to: 53788))
    }

    /// And a coast that has run out while streaming output pushes the bottom away: the offset stands
    /// still. Standing still is not travel.
    func testAnUnfrozenCoastStandingStillIsLeftAlone () {
        XCTAssertFalse (moves (isFrozen: false, froze: false, from: 53741, to: 53741))
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

    /// Scope outranks the frozen shortcut in neither direction: a frozen view is tracked even though
    /// its gesture froze — that *is* how it froze — so the two conditions cannot be collapsed into
    /// one. This is the pair that would break if `freezeEngagedDuringGesture` were checked first.
    func testAFrozenCoastIsTrackedEvenThoughItsGestureFroze () {
        XCTAssertTrue  (moves (isFrozen: true,  froze: true, from: 53788, to: 53741))
        XCTAssertFalse (moves (isFrozen: false, froze: true, from: 53788, to: 53741))
    }
}
