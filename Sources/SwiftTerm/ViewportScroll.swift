//
//  ViewportScroll.swift
//
//  The pure rules behind a user-intended viewport move on the iOS terminal view: where a move
//  lands, and which momentum-coast samples are travel. Both are read by `iOSTerminalView` — the
//  landing by the finger's drag (`syncYDispFromContentOffset`) and by the scroll that has no finger
//  behind it (`accessibilityScroll`), off the one function so the two can never name different rows
//  for the same offset. Kept free of UIKit and of a live scroll view so they can be unit-tested on
//  any platform — the scroll view they drive cannot.
//

import Foundation

/// Where a user-intended viewport move settles: which buffer row the viewport names, whether the
/// manual-scroll freeze engages, and how far into that row the resting offset sits.
struct ViewportScrollLanding: Equatable {
    /// The buffer row the viewport names once the move settles (`yDisp`).
    let row: Int
    /// Whether the manual-scroll freeze engages. A move that lands at — or past — the bottom
    /// releases it, which is what re-engages auto-follow; anything short of the bottom holds it.
    let freezesScrolling: Bool
    /// The part of the resting offset that falls inside `row`, so the offset the view rests at can
    /// be reproduced from the row without snapping to the cell grid.
    let offsetWithinRow: Double
}

/// Where a viewport move to `targetOffsetY` lands.
///
/// This is the same reading `syncYDispFromContentOffset` makes of a finger's drag, lifted out so a
/// scroll that has no finger behind it — VoiceOver's three-finger scroll — can make it too. The
/// at-bottom band is checked first and wins: within `atBottomThreshold` of `maxContentOffsetY` the
/// viewport names the newest screen (`maxRow`) and the freeze releases, so auto-follow re-engages
/// exactly as a drag back to the bottom makes it. Short of that band the row is the one under the
/// offset and the freeze engages, so the viewport keeps naming where the reader is while output
/// arrives below it.
///
/// `offsetTolerance` is the sub-pixel slack (one device pixel) that keeps an offset resting a hair
/// under a row boundary from naming the row above it.
///
/// Returns `nil` when there is no row grid to read — a non-positive `cellHeight`, which is a view
/// that has not been laid out yet. There is no honest answer there, and the tempting one is the
/// harmful one: reporting the bottom would say the viewport follows output, which is exactly the
/// false reading this rule exists to prevent. The caller leaves the viewport model alone instead,
/// which is also what the drag path's own `cellHeight > 0` guard does.
func viewportScrollLanding (targetOffsetY: Double,
                            maxContentOffsetY: Double,
                            maxRow: Int,
                            cellHeight: Double,
                            atBottomThreshold: Double,
                            offsetTolerance: Double) -> ViewportScrollLanding? {
    guard cellHeight > 0 else {
        return nil
    }
    let restingOffsetY = min (max (targetOffsetY, 0), maxContentOffsetY)
    if restingOffsetY >= maxContentOffsetY - atBottomThreshold {
        return ViewportScrollLanding (row: maxRow, freezesScrolling: false, offsetWithinRow: 0)
    }
    // The row can still divide out past `maxRow` while short of the band: a bottom inset pushes the
    // scroll view's resting maximum *beyond* the last row's own offset, so the clamp is
    // load-bearing, not defensive.
    let row = max (0, min (maxRow, Int (floor ((restingOffsetY + offsetTolerance) / cellHeight))))
    return ViewportScrollLanding (row: row,
                                  freezesScrolling: true,
                                  offsetWithinRow: restingOffsetY - Double (row) * cellHeight)
}

/// Whether a momentum-coast sample should move the terminal's viewport model — track the row the
/// viewport now names, and hold it there against arriving output.
///
/// Deceleration only ever follows a real drag, so every sample is the tail of a gesture the reader
/// made; the question is which of them mean the reader is *travelling*. Two do:
///
/// - **A view that is already frozen.** The content keeps visibly scrolling after the lift, so a
///   viewport left at the finger-lift row names rows the reader is no longer looking at.
/// - **A view that is not frozen, from a gesture in which the freeze never engaged, whose offset is
///   moving *away* from the bottom.** A flick that begins at the live tail spends its whole
///   finger-down phase inside the at-bottom band, so the freeze never engages and every pixel of
///   travel happens under momentum. Left alone, the viewport model stays pinned to the live tail
///   while the reader coasts up into history.
///
/// What it must **not** pick up is any coast the reader has *already overruled*. Three of those
/// exist and they share one shape — the freeze engaged earlier in the same gesture, then something
/// released it and put the viewport back on the live tail, while the coast from that gesture is
/// still in flight:
///
/// - The fling *to* the bottom under streaming output. Content grows faster than the coast, so once
///   the at-bottom band releases the freeze, sample after sample reads "not at the bottom yet".
/// - A jump back to the tail landed mid-coast. The viewport is re-pinned under a coast that is
///   still travelling the other way.
/// - The caret pulling the viewport home as output arrives, mid-coast, for the same reason.
///
/// Picking any of them up re-freezes a viewport the reader just sent back to the tail. **Gesture
/// scope is what separates them from the flick**, where the freeze never engaged at all: a flick
/// that begins at the live tail spends its whole finger-down phase inside the at-bottom band, so
/// `freezeEngagedDuringGesture` is false for it and true for all three above. Timing cannot tell
/// them apart — every one is post-lift deceleration on an unfrozen view — and neither can direction
/// alone, since all three travel away from a bottom that has just moved.
///
/// Direction still has to hold too: the offset must have moved up by more than `offsetTolerance`, a
/// sub-device-pixel drift at the end of a coast being noise rather than travel. Pass the *clamped*,
/// resting offsets, so an overscroll bounce — which does come back down — cannot read as travel.
///
/// The scope opens when a finger goes down and closes at the next one, so a release that lands
/// inside a gesture holds for the rest of it. That is deliberate: the reader's later act outranks
/// the earlier fling, and the cost is only that the tail of one coast goes untracked.
func coastMovesTheViewport (isFrozen: Bool,
                            freezeEngagedDuringGesture: Bool,
                            offsetY: Double,
                            previousOffsetY: Double,
                            offsetTolerance: Double) -> Bool {
    if isFrozen {
        return true
    }
    return !freezeEngagedDuringGesture && offsetY < previousOffsetY - offsetTolerance
}
