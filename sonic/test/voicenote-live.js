/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The recording screen live, frame by frame, for sonic/test/voicenote.qml and
 * voicenote-docs.qml: a note's levels reach the screen as ioslink sends them,
 * and the screen ticks when it asks to, on a clock that this holds. Nothing
 * waits on real time, so the frames are the same on every run.
 *
 *   var run = Live.start(overlay, levels, arrival, 500)
 *   var run = Live.replay(overlay, signals, 500)
 *   run.to(2000)   // the frames up to 2 s after the press
 *   run.frames     // [{at, newest, heights}], one per tick
 *
 * start(): `levels` are dBFS, one per 50 ms from the press; `arrival(i)` is
 * when level i reaches the screen, in ms since the press. Levels that arrive
 * together come as one signal, as ioslink's do. replay(): the Levels signals
 * as a watch sent them, each {at, from, cb}: when it came, its fromMs and its
 * centibels (voicenote-levels.js' LIVE_0010). Either way the screen shows at
 * `showAt`, the hold's 0.5 s, and then ticks at the intervals it chooses
 * (nextTickMs), or every 100 ms for a screen that doesn't choose. It works
 * with any version of VoiceNoteOverlay.qml that has arm(), begin(), show(),
 * tick(), addLevels(), heights and lag: #19's too, for the pictures of before.
 */
.pragma library

// The press, on the wall clock the screen reads.
var PRESS = 1793725215000

function start(overlay, levels, arrival, showAt) {
    var order = []
    for (var i = 0; i < levels.length; i++)
        order.push({at: arrival(i), i: i})
    order.sort(function(a, b) { return a.at - b.at || a.i - b.i })
    // Levels that arrive together, in order, are one signal.
    var signals = []
    for (var j = 0; j < order.length; j++) {
        var last = signals[signals.length - 1]
        if (last !== undefined && last.at === order[j].at && last.next === order[j].i) {
            last.cb.push(Math.round(levels[order[j].i] * 100))
            last.next++
        } else {
            signals.push({at: order[j].at, from: 50 * order[j].i, cb: [Math.round(levels[order[j].i] * 100)], next: order[j].i + 1})
        }
    }
    return replay(overlay, signals, showAt)
}

function replay(overlay, signals, showAt) {
    var run = {now: 0, frames: [], deliveries: [], shownYet: false, nextTick: showAt, si: 0}
    overlay.slide = false
    overlay.nowMs = function() { return PRESS + run.now }
    overlay.arm()
    overlay.begin("LIVE")
    overlay.startedAt = PRESS

    // The newest bar a frame shows: the screen's own (newestDrawn), or, for one
    // that doesn't say, the clock's, as such a screen draws it.
    function newestOf() {
        if (overlay.newestDrawn !== undefined)
            return overlay.newestDrawn
        return Math.floor((run.now - overlay.lag) / 100)
    }

    run.to = function(until) {
        while (true) {
            var nextSignal = run.si < signals.length ? signals[run.si].at : Infinity
            if (Math.min(nextSignal, run.nextTick) > until)
                break
            if (nextSignal <= run.nextTick) {
                var s = signals[run.si++]
                run.now = s.at
                run.deliveries.push({at: s.at, from: s.from, count: s.cb.length})
                overlay.addLevels("LIVE", s.from, s.cb)
            } else {
                run.now = run.nextTick
                if (!run.shownYet) {
                    overlay.show()
                    run.shownYet = true
                } else {
                    overlay.tick()
                }
                run.frames.push({at: run.now, newest: newestOf(), heights: overlay.heights.slice()})
                run.nextTick = run.now + (overlay.nextTickMs !== undefined ? overlay.nextTickMs : 100)
            }
        }
        run.now = until
    }
    return run
}

// What the frames showed of each bar: bars[k] is the list of its heights, one
// per frame that drew it.
function barsSeen(frames) {
    var seen = []
    frames.forEach(function(f) {
        if (f.newest === undefined)
            return
        for (var s = 0; s < f.heights.length; s++) {
            var k = f.newest - s
            if (k < 0)
                break
            if (seen[k] === undefined)
                seen[k] = []
            seen[k].push(f.heights[s])
        }
    })
    return seen
}

// How far each frame moved the row: the newest bar's change from the frame
// before, for every frame after the first.
function steps(frames) {
    var out = []
    for (var i = 1; i < frames.length; i++)
        out.push(frames[i].newest - frames[i - 1].newest)
    return out
}

// The arrivals of a note's levels: each 50 ms level as soon as it is heard
// ("live"), or as ioslink sends them ("ioslink"): `delay` ms after it was
// heard, the capture's, at the next of its sends, every 100 ms from 18 ms after
// the press, as on the watch (LIVE_0010: a level comes 135 to 190 ms after it
// ended). `hold` keeps every level until then, as a capture that starts with a
// backlog, or a screen that gets the first levels at once.
function arrivals(kind, hold, delay) {
    var lateBy = delay === undefined ? 135 : delay
    return function(i) {
        var heard = 50 * (i + 1)
        var at = heard
        if (kind === "ioslink")
            at = Math.ceil((heard + lateBy - 18) / 100) * 100 + 18
        if (hold !== undefined && at < hold)
            at = hold
        return at
    }
}
