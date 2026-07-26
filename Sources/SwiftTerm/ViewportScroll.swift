//
//  ViewportScroll.swift
//
//  The pure rule behind a programmatic, user-intended viewport move on the iOS terminal view
//  (see `accessibilityScroll` in iOSTerminalView). Kept free of UIKit and of a live scroll view so
//  it can be unit-tested on any platform — the scroll view it drives cannot.
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
/// under a row boundary from naming the row above it. A non-positive `cellHeight` has no row grid
/// to read, so it reports the bottom rather than dividing by it.
func viewportScrollLanding (targetOffsetY: Double,
                            maxContentOffsetY: Double,
                            maxRow: Int,
                            cellHeight: Double,
                            atBottomThreshold: Double,
                            offsetTolerance: Double) -> ViewportScrollLanding {
    let atBottom = ViewportScrollLanding (row: maxRow, freezesScrolling: false, offsetWithinRow: 0)
    let restingOffsetY = min (max (targetOffsetY, 0), maxContentOffsetY)
    if restingOffsetY >= maxContentOffsetY - atBottomThreshold || cellHeight <= 0 {
        return atBottom
    }
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
/// - **A view that is not frozen but whose offset is moving *away* from the bottom.** A flick that
///   begins at the live tail spends its whole finger-down phase inside the at-bottom band, so the
///   freeze never engages and every pixel of travel happens under momentum. Left alone, the
///   viewport model stays pinned to the live tail while the reader coasts up into history.
///
/// What it must **not** pick up is the fling *to* the bottom under streaming output: there the
/// content grows faster than the coast, so sample after sample reads "not at the bottom yet" while
/// the offset is still travelling toward the bottom — or standing still as the bottom recedes ahead
/// of it. Freezing on one of those would re-freeze a view the reader just flung to the tail.
/// Direction separates the two where timing cannot, so only an offset that actually moved up
/// qualifies, and it must move by more than `offsetTolerance` — a sub-device-pixel drift at the end
/// of a coast is noise, not travel. Pass the *clamped*, resting offsets: an overscroll bounce does
/// come back down, and clamping keeps that from reading as travel into history.
func coastMovesTheViewport (isFrozen: Bool,
                            offsetY: Double,
                            previousOffsetY: Double,
                            offsetTolerance: Double) -> Bool {
    isFrozen || offsetY < previousOffsetY - offsetTolerance
}
