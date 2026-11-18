/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Where a hold of the bottom button records a voice note (the main repo's
 * docs/prd/voice_notes.md, decision 8 and § 8.2). The user's rule: "I want the
 * voice note to start when long press and that I am on the main watchface (not
 * in an app). That includes: when playing music, when stopwatches/timers are
 * on, etc etc. Not just 'only when regular watchface is shown'." And with the
 * screen off, where the user can't see what is in front, a hold records
 * whatever was in front.
 *
 * With the display on, or ambient (which is the display on, showing the
 * ambient face), a hold records when the home's face page is in front: the
 * home, with the panels on the face itself, whatever the face shows (the music
 * face's cover, the rings face with timers or stopwatches running, the door,
 * the plain face). Never inside an app, nor on another panel (the
 * notifications, the quick panel, the app list, the Today screen): a hold does
 * nothing there, as a press does today.
 *
 * With the display off, a hold always records: an app in front, the app list,
 * the quick panel, anything. The recording screen comes up over what is there,
 * and nothing in the hold closes or moves a window, so that what was in front
 * is in front again when the screen has gone.
 */
.pragma library

// Whether a hold may start a note. panelX and panelY are the panels' position
// (0, 0 is the face itself); -1 when the panels aren't there yet.
//
// The display is off when displayOn is false and the watch isn't ambient.
// Lipstick emits displayOff for mce's off state, and with ambient enabled that
// state is the ambient display: compositor.qml's displayOn is false then too,
// and ambient counts as the display on.
function canRecord(displayOn, ambient, homeActive, panelX, panelY) {
    if (!displayOn && !ambient)
        return true
    return !!homeActive && panelX === 0 && panelY === 0
}
