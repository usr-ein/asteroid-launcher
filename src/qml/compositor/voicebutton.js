/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Where a hold of the bottom button records a voice note (the main repo's
 * docs/prd/voice_notes.md, decision 8 and § 8.2). The user's rule: "I want the
 * voice note to start when long press and that I am on the main watchface (not
 * in an app). That includes: when playing music, when stopwatches/timers are
 * on, etc etc. Not just 'only when regular watchface is shown'."
 *
 * So a hold records when the home's face page is in front: the home, with the
 * panels on the face itself, whatever the face shows (the music face's cover,
 * the rings face with timers or stopwatches running, the door, the plain face)
 * and whatever the display does: on, ambient or off. Never inside an app, nor
 * on another panel (the notifications, the quick panel, the app list, the
 * Today screen), with the screen off too: a hold does nothing there, as a press
 * does today.
 *
 * With the screen off, the face is what is in front soon enough: MainScreen
 * moves the panels back to (0, 0) 150 ms after the display goes off, and
 * compositor.qml closes the app in front 5 s after.
 */
.pragma library

// Whether a hold may start a note. panelX and panelY are the panels' position
// (0, 0 is the face itself); -1 when the panels aren't there yet. displayOn and
// ambient don't matter: they are in the signature so that a test can show it.
function canRecord(displayOn, ambient, homeActive, panelX, panelY) {
    return !!homeActive && panelX === 0 && panelY === 0
}
