/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The Today timeline's layout (Today.qml), as the approved mockup draws it:
 * the sizes are the mockup's pixels, on the watch's 454 × 454 screen, which
 * Today.qml scales to the screen it has.
 */
.pragma library

var PPH = 76            // pixels per hour
var CENTRE_Y = 227      // the line that the time bubble reads
var X0 = 112            // the blocks' column, from X0 to X1
var X1 = 378
var GAP = 4             // between events side by side
var NORMAL_MIN = 56     // the smallest block with the title above the time
var COMPACT_MIN = 31    // the smallest block: one line, the time first
var LINE = 25           // a title line
var TIME_H = 18         // the time's line
var PAD_V = 12          // a block's padding, top and bottom together

// The minute of the day of a date, from 0 to 1440, clipped to the day that
// starts at dayStart and ends at dayEnd.
function minuteOfDay(date, dayStart, dayEnd) {
    if (date <= dayStart)
        return 0
    if (date >= dayEnd)
        return 1440
    return date.getHours() * 60 + date.getMinutes() + date.getSeconds() / 60
}

// Lays the day's timed events out: each event, which has startMin and endMin,
// gets top, height, x and width in the mockup's pixels, compact for a short
// one, and lines, how many lines its title may take. Events that overlap
// share the column's width side by side; overlaps count a short event at its
// drawn height, which is at least COMPACT_MIN.
function layout(events) {
    var ppm = PPH / 60
    events.forEach(function(ev) {
        var h = Math.max(0, ev.endMin - ev.startMin) * ppm
        ev.compact = h < NORMAL_MIN
        ev.top = ev.startMin * ppm
        ev.height = ev.compact ? Math.max(h, COMPACT_MIN) : h
        ev.bottom = ev.top + ev.height
    })
    events.sort(function(a, b) {
        return a.top - b.top || b.bottom - a.bottom
    })

    var cluster = []
    var clusterEnd = -1
    function flush() {
        var columns = []
        cluster.forEach(function(ev) {
            var col = -1
            for (var i = 0; i < columns.length; i++) {
                if (columns[i] <= ev.top + 0.5) {
                    col = i
                    break
                }
            }
            if (col === -1) {
                col = columns.length
                columns.push(0)
            }
            columns[col] = ev.bottom
            ev.col = col
        })
        cluster.forEach(function(ev) { ev.ncol = columns.length })
        cluster = []
        clusterEnd = -1
    }
    events.forEach(function(ev) {
        if (cluster.length && ev.top >= clusterEnd)
            flush()
        cluster.push(ev)
        clusterEnd = Math.max(clusterEnd, ev.bottom)
    })
    if (cluster.length)
        flush()

    events.forEach(function(ev) {
        var width = (X1 - X0 - GAP * (ev.ncol - 1)) / ev.ncol
        ev.x = X0 + ev.col * (width + GAP)
        ev.width = width
        ev.lines = Math.max(1, Math.min(2, Math.floor((ev.height - PAD_V - TIME_H - 2) / LINE)))
    })
    return events
}

function pad(n) {
    return (n < 10 ? "0" : "") + n
}

// "09:30", or "9:30" on a 12-hour clock.
function formatMinutes(minutes, use12h) {
    var m = Math.max(0, Math.min(1440, Math.round(minutes)))
    var h = Math.floor(m / 60)
    var mm = pad(m % 60)
    if (use12h)
        return ((h + 11) % 12 + 1) + ":" + mm
    return pad(h) + ":" + mm
}

function formatTime(date, use12h) {
    return formatMinutes(date.getHours() * 60 + date.getMinutes(), use12h)
}

// "09:30–10:15", or "09:30" when it ends as it starts.
function timeRange(start, end, use12h) {
    var from = formatTime(start, use12h)
    var to = formatTime(end, use12h)
    return end > start && to !== from ? from + "–" + to : from
}

// "14:00", or "2 PM" on a 12-hour clock.
function hourLabel(hour, use12h) {
    if (!use12h)
        return pad(hour) + ":00"
    return ((hour + 11) % 12 + 1) + (hour % 24 < 12 ? " AM" : " PM")
}

// A calendar's colour, as the iPhone sync sets it on the notebook, or the
// accent blue when it has none.
function calendarColour(colour) {
    return /^#[0-9A-Fa-f]{6}$/.test(colour) ? colour : "#0a84ff"
}

// The weather glyph's colour, by its icon's name (weathericons.js).
function weatherColour(icon) {
    if (icon.indexOf("sunny") >= 0 || icon.indexOf("thunderstorm") >= 0)
        return "#ffd60a"
    if (icon.indexOf("rainy") >= 0)
        return "#64a8ff"
    if (icon.indexOf("flame") >= 0)
        return "#ff9f0a"
    if (icon.indexOf("snow") >= 0)
        return "#e8f1ff"
    return "#d7dde6"
}
