/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Where a hold of the bottom button records a voice note (the main repo's
 * docs/prd/voice_notes.md, decision 8 and § 8.2): on the watch face with the
 * screen on, and with the screen off or in ambient, where a note can be
 * caught without waking the watch first. Not over an app, the app list, the
 * Today screen, the quick panel or the notifications with the screen on: a
 * hold does nothing there, as a press does today.
 */
.pragma library

// Whether a hold may start a note. panelX and panelY are the panels' position
// (0, 0 is the face itself); -1 when the panels aren't there yet.
function canRecord(displayOn, ambient, homeActive, panelX, panelY) {
    // The launcher closes an app 5 s after the screen goes off, so behind a
    // dark screen it's the face.
    if (!displayOn || ambient)
        return true
    return !!homeActive && panelX === 0 && panelY === 0
}
