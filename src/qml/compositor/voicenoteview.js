/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * What the recording screen (VoiceNoteOverlay.qml) works out, kept pure so
 * that the tests can check it without drawing: the duration's text, the
 * waveform's bars from the levels, and the line under it for each way a note
 * can end. The main repo's docs/prd/voice_notes.md § 8.4 has the numbers;
 * bridge/PROTOCOL.md § 6.14.4 has the State and Levels that feed it.
 */
.pragma library

// A note is at most 10 minutes long: ioslink stops it there.
var LIMIT_MS = 600000
// The last 30 s count down in amber.
var COUNTDOWN_S = 30

// The bars, in the mockup's pixels at 454 × 454: 6 px for the room and 100 px
// for speech at its loudest. A level is the RMS of 50 ms, in dBFS; a bar covers
// 100 ms.
var BAR_MIN = 6
var BAR_MAX = 100
var BAR_MS = 100

// What a level draws as depends on the room. Speech sits 8 to 18 dB above a
// quiet room, and the room's own level wanders by 5 dB or more, so a fixed scale
// can't show silence flat and speech tall: the bars are measured from the room's
// floor, which a note tracks as it goes.
//  - The floor is the 15th percentile of the last 80 bars (8 s), kept between
//    FLOOR_BOTTOM and FLOOR_TOP. It starts at FLOOR_START, a quiet room's, falls
//    to a quieter room at once, and rises by FLOOR_RISE a bar at the most (0.1 dB
//    a second): speech has few gaps and must not become the floor, and a louder
//    room is followed slowly. FLOOR_TOP is low on purpose: a room louder than it
//    draws as activity, but speech keeps its height, whatever the length of the
//    note.
//  - A bar is flat (BAR_MIN) up to KNEE_DB above the floor, full height
//    (BAR_MAX) from LOUD_DB, and between the two it follows a smoothstep: flat at
//    both ends and steepest in the middle, so that the room's wander draws as
//    nothing and a syllable as much.
var FLOOR_START = -52
var FLOOR_TOP = -50
var FLOOR_BOTTOM = -60
var FLOOR_BARS = 80
var FLOOR_PERCENTILE = 0.15
var FLOOR_RISE = 0.01
var KNEE_DB = 8
var LOUD_DB = -33

// "0:42", "4:07", "10:00": from the press, and no more than the limit.
function clock(ms) {
    var s = Math.floor(Math.max(0, Math.min(ms, LIMIT_MS)) / 1000)
    return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
}

// "18:02", the watch's local time of day.
function timeOfDay(unixMs) {
    var d = new Date(unixMs)
    return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
}

// A bar's height for a level in dBFS over the room's floor in dBFS.
function barHeight(db, floor) {
    var knee = (floor === undefined ? FLOOR_START : floor) + KNEE_DB
    var x = Math.min(1, Math.max(0, (db - knee) / (LOUD_DB - knee)))
    return BAR_MIN + x * x * (3 - 2 * x) * (BAR_MAX - BAR_MIN)
}

// The q-th quantile of numbers in ascending order, interpolated.
function quantile(sorted, q) {
    var at = q * (sorted.length - 1)
    var below = Math.floor(at)
    var above = Math.min(below + 1, sorted.length - 1)
    return sorted[below] + (sorted[above] - sorted[below]) * (at - below)
}

// The levels of a note, by bar: bars[k] is the loudest level, in dBFS, that
// starts within [100 k, 100 k + 100) ms of the press. A level is a hundredth
// of a dBFS in a signal, and starts at fromMs + 50 i. A bar with no level yet
// is undefined. The bars change only through here, which notes the first one
// that did, for floors().
function addLevels(bars, fromMs, centibels) {
    for (var i = 0; i < centibels.length; i++) {
        var k = Math.floor((fromMs + 50 * i) / BAR_MS)
        var db = centibels[i] / 100
        if (k >= 0 && (bars[k] === undefined || db > bars[k])) {
            bars[k] = db
            bars.touched = bars.touched === undefined ? k : Math.min(bars.touched, k)
        }
    }
}

// The room's floor under the bars up to `newest`, in dBFS: floors[k] is the
// floor for bars[k], worked out from the bars up to k alone, so that a bar's
// height never depends on what comes after it. They are kept on the array of
// bars, and worked out again from the first bar that addLevels has changed since
// (the newest, but for a late chunk of levels).
function floors(bars, newest) {
    var kept = bars.floors
    if (kept === undefined) {
        kept = []
        bars.floors = kept
    }
    var from = bars.touched === undefined ? kept.length : Math.min(kept.length, bars.touched)
    bars.touched = undefined
    kept.length = from
    var floor = from > 0 ? kept[from - 1] : FLOOR_START
    for (var k = from; k <= newest; k++) {
        if (bars[k] !== undefined) {
            var window = []
            for (var j = Math.max(0, k - FLOOR_BARS + 1); j <= k; j++) {
                if (bars[j] !== undefined)
                    window.push(bars[j])
            }
            window.sort(function(a, b) { return a - b })
            var seen = Math.max(FLOOR_BOTTOM, Math.min(FLOOR_TOP, quantile(window, FLOOR_PERCENTILE)))
            floor = seen > floor ? Math.min(seen, floor + FLOOR_RISE) : seen
        }
        kept[k] = floor
    }
    return kept
}

// The newest bar's index for a time since the press. The levels reach the
// screen a moment after they were heard, so `lag` ms of the clock are left
// out, so that the newest bar isn't empty.
function newestBar(elapsedMs, lagMs) {
    return Math.floor((elapsedMs - lagMs) / BAR_MS)
}

// The heights of the `count` bars from the newest back, 0 where there is no
// level, in the mockup's pixels.
function heights(bars, newest, count) {
    var floor = floors(bars, newest)
    var out = []
    for (var k = 0; k < count; k++) {
        var at = newest - k
        var level = at >= 0 ? bars[at] : undefined
        out.push(level === undefined ? 0 : barHeight(level, floor[at]))
    }
    return out
}

// The newest bar that has a level, or -1.
function lastBar(bars) {
    for (var k = bars.length - 1; k >= 0; k--) {
        if (bars[k] !== undefined)
            return k
    }
    return -1
}

// The red dot's opacity as it breathes once a second: 1, 0.35 at half a
// second, and 1 again.
function breath(elapsedMs) {
    var turn = (((elapsedMs % 1000) + 1000) % 1000) / 1000
    return 0.35 + 0.65 * (0.5 + 0.5 * Math.cos(2 * Math.PI * turn))
}

// The line while the note records: "Release to save", and from 9:30 the
// seconds left, in amber.
function recordingLine(elapsedMs) {
    var left = Math.ceil((LIMIT_MS - elapsedMs) / 1000)
    if (left <= 0)
        return {text: "Saving…", amber: false}
    if (left <= COUNTDOWN_S)
        return {text: left + " s left", amber: true}
    return {text: "Release to save", amber: false}
}

// Which notes were dropped, for "Saved · ... dropped": the time of the one,
// or how many.
function dropped(drops) {
    if (drops.length > 1)
        return drops.length + " "
    return isFinite(drops[0].startedAt) && drops[0].startedAt > 0 ? timeOfDay(drops[0].startedAt) + " " : ""
}

// How many notes wait, for a line that must stay short.
function count(n) {
    return n > 999 ? "999+" : String(Math.max(1, n | 0))
}

// How a note ended, from State's `last` and its `onWatch` and `connected`:
//   {text, amber, check, dim}
// check: the green check in place of the dot; dim: the duration greyed.
// A drop is told whatever else the note did, so that it's never silent.
// `last.reason` says why a note couldn't start, or ended early and was kept
// (PROTOCOL.md § 6.14.4): "storage", "microphone" or "encoder". A note that
// ended early says so in amber, as its duration is short of what was held.
function ending(last, onWatch, connected) {
    var drops = last && last.dropped ? last.dropped : []
    var outcome = last ? last.outcome : ""
    var reason = last && last.reason ? last.reason : ""
    var saved = outcome === "saved" || outcome === "dropped" || outcome === "limit"
    if (saved && drops.length > 0)
        return {text: "Saved · " + dropped(drops) + "dropped", amber: true, check: true, dim: false}
    switch (outcome) {
    case "saved":
        if (reason === "microphone")
            return {text: "Microphone lost · saved", amber: true, check: true, dim: false}
        if (reason === "encoder")
            return {text: "Encoder failed · saved", amber: true, check: true, dim: false}
        return {text: connected ? "Saved · sending" : "Saved · " + count(onWatch) + " on watch",
                amber: false, check: true, dim: false}
    case "limit":
        // A note alone past the cache's cap ends before 10:00.
        if (reason === "storage")
            return {text: "Storage full · saved", amber: true, check: true, dim: false}
        return {text: "10 min limit · saved", amber: false, check: true, dim: false}
    case "dropped":
        // Said to be dropped, with none listed.
        return {text: "Saved · dropped", amber: true, check: true, dim: false}
    case "tooShort":
        return {text: "Too short", amber: false, check: false, dim: true}
    }
    if (reason === "storage")
        return {text: "Watch storage full", amber: true, check: false, dim: true}
    if (reason === "microphone")
        return {text: "Microphone unavailable", amber: true, check: false, dim: true}
    return {text: "Couldn't record", amber: true, check: false, dim: true}
}
