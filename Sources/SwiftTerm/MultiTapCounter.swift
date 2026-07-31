//
//  MultiTapCounter.swift
//
//  The pure run-length rule behind the iOS terminal view's double-tap / triple-tap selection
//  counting (see `registerLocalTap` in iOSTerminalView). Kept free of UIKit and a live clock so it
//  can be unit-tested on any platform — the gesture plumbing that feeds it cannot.
//

import Foundation

/// The running length of a run of consecutive taps, given the previous run length and how far the
/// new tap fell from the one before it in time and space. The tap **continues** the run
/// (`previousCount + 1`) only when it lands within *both* `maxInterval` seconds and `maxDistance`
/// of the previous tap; any slower or farther tap **restarts** the run at `1`. This is the
/// double-tap-window rule that gives word/line selection without the multi-tap
/// `UITapGestureRecognizer`s (see `setupGestures`); the caller derives `maxDistance` from the
/// cell size.
func tapRunLength (previousCount: Int,
                   interval: TimeInterval,
                   distance: Double,
                   maxInterval: TimeInterval,
                   maxDistance: Double) -> Int {
    (interval <= maxInterval && distance <= maxDistance) ? previousCount + 1 : 1
}
