/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The bottom button's single press on the rings face, the face that Sonic
 * Screwdriver's watch face shows while a timer or a stopwatch runs (the main
 * repo's docs/prd/clock.md § 8.8): it opens the app of the view on screen.
 * Only with the display on and not ambient, the home in front, and the
 * panels on the face itself; anywhere else, nothing.
 */
.pragma library

// The app to open, or "" for none. view is the face's sonicRingsView:
// "timers", "stopwatches", or "" when the rings don't show.
function app(displayOn, ambient, homeActive, panelX, panelY, view) {
    if (!displayOn || ambient || !homeActive || panelX !== 0 || panelY !== 0)
        return ""
    if (view === "timers")
        return "sonic-timer"
    if (view === "stopwatches")
        return "sonic-stopwatch"
    return ""
}
