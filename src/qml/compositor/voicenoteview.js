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

// The bars: −60 dBFS is 6 px tall and −20 dBFS 100 px, in the mockup's pixels
// at 454 × 454. A level is the RMS of 50 ms; a bar covers 100 ms.
var DB_QUIET = -60
var DB_LOUD = -20
var BAR_MIN = 6
var BAR_MAX = 100
var BAR_MS = 100

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

// A bar's height for a level in dBFS.
function barHeight(db) {
    var f = (db - DB_QUIET) / (DB_LOUD - DB_QUIET)
    return BAR_MIN + Math.min(1, Math.max(0, f)) * (BAR_MAX - BAR_MIN)
}

// The levels of a note, by bar: bars[k] is the loudest level, in dBFS, that
// starts within [100 k, 100 k + 100) ms of the press. A level is a hundredth
// of a dBFS in a signal, and starts at fromMs + 50 i. A bar with no level yet
// is undefined.
function addLevels(bars, fromMs, centibels) {
    for (var i = 0; i < centibels.length; i++) {
        var k = Math.floor((fromMs + 50 * i) / BAR_MS)
        var db = centibels[i] / 100
        if (k >= 0 && (bars[k] === undefined || db > bars[k]))
            bars[k] = db
    }
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
    var out = []
    for (var k = 0; k < count; k++) {
        var level = newest - k >= 0 ? bars[newest - k] : undefined
        out.push(level === undefined ? 0 : barHeight(level))
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
function ending(last, onWatch, connected) {
    var drops = last && last.dropped ? last.dropped : []
    var outcome = last ? last.outcome : ""
    var saved = outcome === "saved" || outcome === "dropped" || outcome === "limit"
    if (saved && drops.length > 0)
        return {text: "Saved · " + dropped(drops) + "dropped", amber: true, check: true, dim: false}
    switch (outcome) {
    case "saved":
        return {text: connected ? "Saved · sending" : "Saved · " + count(onWatch) + " on watch",
                amber: false, check: true, dim: false}
    case "limit":
        return {text: "10 min limit · saved", amber: false, check: true, dim: false}
    case "dropped":
        // Said to be dropped, with none listed.
        return {text: "Saved · dropped", amber: true, check: true, dim: false}
    case "tooShort":
        return {text: "Too short", amber: false, check: false, dim: true}
    }
    var reason = last ? last.reason : ""
    if (reason === "storage")
        return {text: "Watch storage full", amber: true, check: false, dim: true}
    if (reason === "microphone")
        return {text: "Microphone unavailable", amber: true, check: false, dim: true}
    return {text: "Couldn't record", amber: true, check: false, dim: true}
}
