/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The recording screen live, frame by frame, for sonic/test/voicenote.qml and
 * voicenote-docs.qml: a note's levels reach the screen as ioslink sends them,
 * and the screen ticks when it asks to, on a clock that this holds. Nothing
 * waits on real time, so the frames are the same on every run.
 *
 *   var run = Live.start(overlay, levels, arrival, 500)
 *   run.to(2000)   // the frames up to 2 s after the press
 *   run.frames     // [{at, newest, heights}], one per tick
 *
 * `levels` are dBFS, one per 50 ms from the press; `arrival(i)` is when level
 * i reaches the screen, in ms since the press. Levels that arrive together
 * come as one signal, as ioslink's do. The screen shows at `showAt`, the hold's
 * 0.5 s, and then ticks at the intervals it chooses (nextTickMs), or every
 * 100 ms for a screen that doesn't choose. It works with any version of
 * VoiceNoteOverlay.qml that has arm(), begin(), show(), tick(), addLevels(),
 * heights and lag: #19's too, for the pictures of before.
 */
.pragma library

// The press, on the wall clock the screen reads.
var PRESS = 1793725215000

function start(overlay, levels, arrival, showAt) {
    var run = {now: 0, frames: [], deliveries: [], shownYet: false, nextTick: showAt, ai: 0}
    var order = []
    for (var i = 0; i < levels.length; i++)
        order.push({at: arrival(i), i: i})
    order.sort(function(a, b) { return a.at - b.at || a.i - b.i })
    run.order = order
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
            var nextArrival = run.ai < order.length ? order[run.ai].at : Infinity
            if (Math.min(nextArrival, run.nextTick) > until)
                break
            if (nextArrival <= run.nextTick) {
                run.now = nextArrival
                // Levels that arrive together, in order, are one signal.
                var first = order[run.ai].i, batch = []
                while (run.ai < order.length && order[run.ai].at === run.now
                       && order[run.ai].i === first + batch.length) {
                    batch.push(Math.round(levels[order[run.ai].i] * 100))
                    run.ai++
                }
                run.deliveries.push({at: run.now, from: 50 * first, count: batch.length})
                overlay.addLevels("LIVE", 50 * first, batch)
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
// per frame that drew it, for a screen that says its newest bar.
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

// The arrivals ioslink makes: each 50 ms level as soon as it is heard
// ("live"), or at its next 100 ms send after the capture's delay, with the
// bus' ("ioslink"); `hold` keeps every level heard before it until then, as a
// capture that starts with a backlog, or a screen that gets the first levels
// at once.
function arrivals(kind, hold, delay) {
    var lateBy = delay === undefined ? 40 : delay
    return function(i) {
        var heard = 50 * (i + 1)
        var at = heard
        if (kind === "ioslink")
            at = Math.ceil((heard + lateBy) / 100) * 100 + 5
        if (hold !== undefined && at < hold)
            at = hold
        return at
    }
}
