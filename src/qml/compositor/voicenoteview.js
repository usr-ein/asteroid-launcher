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
// 100 ms, and its value for the room's floor is the mean in dB of its two
// levels (the louder of the two, which the mockup took, made a click in the
// quiet room draw 3 times as tall). What it draws is that, smoothed (below).
var BAR_MIN = 6
var BAR_MAX = 100
var BAR_MS = 100

// What a level draws as depends on the room. The user's room at night is at
// -60 dBFS and below, one in the afternoon -50, and speech is 20 to 30 dB over
// either, so a fixed scale can't show silence flat and speech tall: the bars
// are measured from the room's floor, which a note tracks as it goes.
//  - The floor is the 15th percentile of the last 80 bars (8 s), kept between
//    FLOOR_BOTTOM and FLOOR_TOP. Bars before the press, and bars with no level
//    yet, count as FLOOR_START, the user's quiet room as measured: the first
//    bars come before the floor knows anything, and never set it on their own
//    (a microphone's first tenths of a second can be silence or a pop). It
//    falls to a quieter room at once, as soon as 15 % of the window is quieter,
//    and rises by FLOOR_RISE a bar at the most (1 dB a second): speech has few
//    gaps and must not become the floor, and a louder room is followed slowly.
//    FLOOR_TOP keeps speech over a loud room: it still shows from 8 dB over it.
//  - A bar is flat (BAR_MIN) up to KNEE_DB above the floor, full height
//    (BAR_MAX) from LOUD_DB, and between the two it follows a smoothstep: flat at
//    both ends and steepest in the middle, so that the room's wander draws as
//    nothing and a syllable as much.
//  - What a bar draws is its levels smoothed, in dB: each 50 ms level moves the
//    envelope towards it, quickly on the way up (ATTACK_MS) and slowly on the
//    way down (RELEASE_MS), and a bar is the mean of the envelope at its two
//    levels. A click or the start tick, 50 ms alone, draws low; a word falls
//    away over a few bars instead of flickering between full and flat.
var FLOOR_START = -55
var FLOOR_TOP = -42
var FLOOR_BOTTOM = -60
var FLOOR_BARS = 80
var FLOOR_PERCENTILE = 0.15
var FLOOR_RISE = 0.1
var KNEE_DB = 8
var LOUD_DB = -27
var LEVEL_MS = 50
var ATTACK_MS = 80
var RELEASE_MS = 300

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

// The levels of a note, by bar: bars[k] is the mean, in dBFS, of the levels that
// start within [100 k, 100 k + 100) ms of the press, or the one that has come so
// far. A level is a hundredth of a dBFS in a signal, and starts at fromMs +
// 50 i. A bar with no level yet is undefined. The bars change only through
// here, which keeps the levels of each (bars.halves) and notes the first bar
// that changed, for floors().
function addLevels(bars, fromMs, centibels) {
    var halves = bars.halves
    if (halves === undefined) {
        halves = []
        bars.halves = halves
    }
    for (var i = 0; i < centibels.length; i++) {
        var at = fromMs + 50 * i
        var k = Math.floor(at / BAR_MS)
        if (k < 0)
            continue
        var half = at - BAR_MS * k < BAR_MS / 2 ? 0 : 1
        var db = centibels[i] / 100
        var pair = halves[k]
        if (pair === undefined) {
            pair = [undefined, undefined]
            halves[k] = pair
        }
        if (pair[half] === db)
            continue
        pair[half] = db
        var other = pair[1 - half]
        bars[k] = other === undefined ? db : (db + other) / 2
        bars.touched = bars.touched === undefined ? k : Math.min(bars.touched, k)
    }
}

// What the bars up to `newest` draw: {floors, drawn}, kept on the array of
// bars. floors[k] is the room's floor for bars[k], in dBFS, and drawn[k] the
// bar's smoothed level, in dBFS (undefined for a bar with no level), both
// worked out from the levels up to bar k alone, so that a bar's height never
// depends on what comes after it. They are worked out again from the first bar
// that addLevels has changed since (the newest, but for a late chunk of
// levels).
function shape(bars, newest) {
    var kept = bars.shape
    if (kept === undefined) {
        kept = {floors: [], drawn: [], envelope: []}
        bars.shape = kept
    }
    var from = bars.touched === undefined ? kept.floors.length : Math.min(kept.floors.length, bars.touched)
    bars.touched = undefined
    kept.floors.length = from
    kept.drawn.length = from
    kept.envelope.length = from
    var floor = from > 0 ? kept.floors[from - 1] : FLOOR_START
    var envelope = from > 0 ? kept.envelope[from - 1] : FLOOR_START
    var up = 1 - Math.exp(-LEVEL_MS / ATTACK_MS)
    var down = 1 - Math.exp(-LEVEL_MS / RELEASE_MS)
    var halves = bars.halves
    for (var k = from; k <= newest; k++) {
        var drawn = undefined
        if (bars[k] !== undefined) {
            var window = []
            for (var j = k - FLOOR_BARS + 1; j <= k; j++)
                window.push(j >= 0 && bars[j] !== undefined ? bars[j] : FLOOR_START)
            window.sort(function(a, b) { return a - b })
            var seen = Math.max(FLOOR_BOTTOM, Math.min(FLOOR_TOP, quantile(window, FLOOR_PERCENTILE)))
            floor = seen > floor ? Math.min(seen, floor + FLOOR_RISE) : seen
            // The envelope through the bar's levels, in the order they were heard.
            var pair = halves !== undefined && halves[k] !== undefined ? halves[k] : [bars[k], undefined]
            var sum = 0, n = 0
            for (var h = 0; h < 2; h++) {
                if (pair[h] === undefined)
                    continue
                envelope += (pair[h] - envelope) * (pair[h] > envelope ? up : down)
                sum += envelope
                n++
            }
            drawn = sum / n
        }
        kept.floors[k] = floor
        kept.drawn[k] = drawn
        kept.envelope[k] = envelope
    }
    return kept
}

// The room's floor under the bars up to `newest`: floors[k] is the floor for
// bars[k], in dBFS (shape()).
function floors(bars, newest) {
    return shape(bars, newest).floors
}

// The newest bar's index for a time since the press. The levels reach the
// screen a moment after they were heard, so `lag` ms of the clock are left
// out, so that the newest bar has its levels.
function newestBar(elapsedMs, lagMs) {
    return Math.floor((elapsedMs - lagMs) / BAR_MS)
}

// The heights of the `count` bars from the newest back, 0 where there is no
// level, in the mockup's pixels.
function heights(bars, newest, count) {
    var kept = shape(bars, newest)
    var out = []
    for (var k = 0; k < count; k++) {
        var at = newest - k
        var level = at >= 0 ? kept.drawn[at] : undefined
        out.push(level === undefined ? 0 : barHeight(level, kept.floors[at]))
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

// The newest bar whose levels are all in, or -1: one with both its levels, or
// any bar before the newest that has one. ioslink sends the levels in order,
// so a bar that has its second level, or a later bar's, has all it will have.
function lastComplete(bars) {
    var k = lastBar(bars)
    if (k < 0)
        return -1
    var pair = bars.halves !== undefined ? bars.halves[k] : undefined
    return pair !== undefined && pair[1] !== undefined ? k : k - 1
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
