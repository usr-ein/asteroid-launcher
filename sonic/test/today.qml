/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The Today scene of sonic/test/test.sh: the fork's Today screen, compiled
 * in, with the SDK's real AgendaModel over mkcal, and the mockup's sample
 * days, invented, from seed-calendar.cpp, in four coloured notebooks. The
 * weather is partly sunny, 12° and 7° (run.sh). It checks:
 *   - every event, with its notebook's colour, read back from a screenshot
 *     too; timed events as blocks, all-day ones as chips;
 *   - the layout: short events on one line, overlapping ones side by side,
 *     titles on two lines at most;
 *   - that it centres on now when it comes into view, and the now line;
 *   - the bubble while it scrolls, gone a second after;
 *   - that long titles move only while the screen shows and they're in view;
 *   - that it follows the calendar: a quiet day, then an empty one;
 *   - the round fit (P-031): the middle Timeline.ZOOM times the size, the
 *     rows shrinking toward the rim and squeezed, never overlapping, blocks
 *     that touch still touching, and the header fading while it scrolls.
 * Screenshots: at now (13:42), at 21:00, at the day's start and its end, in the morning, while scrolling, a long title
 * rolling, the quiet and the empty day, and a contact sheet of them.
 */
import QtQuick 2.9
import "qrc:/qml/"
import "qrc:/qml/timeline.js" as Timeline

Scene {
    id: desktop

    QtObject {
        id: localeManager
        property string changesObserver: ""
    }

    Today {
        id: today
        width: desktop.width
        height: desktop.height
    }

    ContactSheet {
        id: sheet
        x: desktop.width + 100
        columns: 4
    }

    // seed-calendar runs through the SDK's loader, as the harness does.
    readonly property string seed: "$ARM /out/seed-calendar "
    property var files: []
    property var labels: []

    function at(hours, minutes) {
        var d = new Date()
        return new Date(d.getFullYear(), d.getMonth(), d.getDate(), hours, minutes, 0)
    }

    function find(item, predicate) {
        if (predicate(item))
            return item
        for (var i = 0; i < item.children.length; i++) {
            var found = find(item.children[i], predicate)
            if (found)
                return found
        }
        return null
    }

    // The round fit (RoundFit.qml) that the timeline is drawn with.
    function fit() {
        return find(today, function(item) { return item.positionTo !== undefined && item.mapY !== undefined })
    }

    // Its Flickable, which takes the drag.
    function timeline() {
        return find(today, function(item) { return item.flick !== undefined && item.contentY !== undefined })
    }

    function block(title) {
        for (var i = 0; i < today.blocks.length; i++) {
            if (today.blocks[i].title.indexOf(title) === 0)
                return today.blocks[i]
        }
        return null
    }

    // The TodayEvent that draws an event.
    function eventItem(title) {
        return find(fit(), function(item) {
            return item.block !== undefined && item.animating !== undefined && item.block.title.indexOf(title) === 0
        })
    }

    function animatingTitles() {
        var list = []
        var items = fit().children
        for (var i = 0; i < items.length; i++) {
            if (items[i].animating)
                list.push(items[i].block.title.substring(0, 12))
        }
        return list.sort()
    }

    function centreOn(hours, minutes) {
        fit().positionTo((hours * 60 + minutes) * today.ppm)
    }

    // The hour labels in view that overlap a block, as "14:00/Review the".
    function labelsOverBlocks() {
        var f = fit()
        var labels = [], events = [], out = []
        var walk = function(item) {
            if (item.objectName === "hourLabel")
                labels.push(item)
            if (item.block !== undefined && item.animating !== undefined)
                events.push(item)
            for (var i = 0; i < item.children.length; i++)
                walk(item.children[i])
        }
        walk(f)
        labels.forEach(function(l) {
            if (l.opacity < 0.5 || l.parent.opacity < 0.05 || !l.parent.visible)
                return
            var r = l.mapToItem(f, 0, 0, l.contentWidth, l.contentHeight)
            events.forEach(function(e) {
                if (!e.visible || e.opacity < 0.05)
                    return
                if (r.x < e.x + e.width && e.x < r.x + r.width && r.y < e.y + e.height && e.y < r.y + r.height)
                    out.push(l.text + "/" + e.block.title.substring(0, 10))
            })
        })
        return out
    }

    // A screenshot, kept for the contact sheet.
    function keep(name, label, done) {
        files.push(shots + "/" + name + ".png")
        labels.push(label)
        shot(name, done)
    }

    steps: [
        function(done) {
            waitFor(function() { return today.blocks.length === 9 && today.chips.length === 3 }, 60000,
                    "the busy day from mkcal: 9 timed events and 3 all-day ones", done)
        },
        function(done) {
            var colours = {
                "Morning run": "#30D158", "Stand-up": "#0A84FF", "Brunch": "#BF5AF2",
                "Call the landlord": "#FF9F0A", "Groceries": "#FF9F0A", "Review the watch": "#0A84FF",
                "Climbing": "#30D158", "Dinner": "#BF5AF2", "Plan the week": "#0A84FF"
            }
            var wrong = []
            for (var title in colours) {
                var b = block(title)
                if (!b || b.colour.toUpperCase() !== colours[title])
                    wrong.push(title + ": " + (b ? b.colour : "missing"))
            }
            expectEqual(wrong, [], "each block has its notebook's colour")
            expectEqual(today.chips.map(function(c) { return c.title + " " + c.colour.toUpperCase() }).sort(), [
                "Friends in town #BF5AF2", "Pack for the trip #FF9F0A", "Release week #0A84FF"
            ], "the all-day events are chips, in their notebooks' colours")

            var shape = function(title) {
                var b = block(title)
                return [b.compact, b.ncol, b.col, b.lines, b.timeText]
            }
            expectEqual(shape("Stand-up"), [true, 1, 0, 1, "09:30–09:45"], "a 15-minute event is one line, the time first")
            expectEqual(shape("Plan the week"), [true, 1, 0, 1, "21:30–22:00"], "a 30-minute one too")
            expectEqual(shape("Groceries"), [false, 1, 0, 1, "13:00–13:45"], "a 45-minute one has its title above its time")
            expectEqual(shape("Brunch"), [false, 2, 0, 2, "10:30–12:00"], "overlapping events share the width: the first")
            expectEqual(shape("Call the landlord"), [true, 2, 1, 1, "11:00–11:20"], "and the second, beside it")
            expectEqual(shape("Review the watch"), [false, 1, 0, 2, "14:30–16:00"], "a long title takes two lines at most")
            expectEqual(shape("Dinner"), [false, 1, 0, 2, "19:30–21:30"], "events that only touch don't share the width")
            check(Math.abs(block("Call the landlord").width - (266 - 4) / 2) < 0.01, "side by side, each takes half the column")
            done()
        },

        // Now: 13:42, and the screen comes into view.
        function(done) {
            today.now = at(13, 42)
            today.visible = false
            today.visible = true
            after(300, function() {
                check(Math.abs(fit().position - (13 * 60 + 42) * today.ppm) < 1,
                      "it centres on now when it comes into view")
                check(!today.peeking, "no bubble without scrolling")
                keep("today-1342", "Now, 13:42", done)
            })
        },
        function(done) {
            // The work review's block, 14:30 to 16:00: the Work blue darkened, under the now line.
            var file = shots + "/today-1342.png"
            var share = test.share(file, 140, 300, 200, 70, "#022345", 6)
            check(share > 0.5, "the review's block shows in Work's blue, darkened: " + Math.round(share * 100) + " %")
            var red = test.share(file, 104, 225, 270, 6, "#ff453a", 40)
            check(red > 0.15, "the now line shows in red at the middle: " + Math.round(red * 100) + " %")
            done()
        },

        // The round fit: full size at the middle, smaller toward the rim, and
        // squeezed there, never overlapping.
        function(done) {
            var f = fit()
            var mid = f.height / 2
            check(Math.abs(f.scaleAt(mid) - 1.2) < 0.001, "the middle is 1.2 times today's size: " + f.scaleAt(mid))
            var rim = f.scaleAt(f.height * 0.95)
            check(rim < 0.6 && rim >= 1.2 * 0.42 - 0.001, "near the rim, a row is about half today's size: " + rim.toFixed(2))
            var ys = []
            for (var h = 0; h <= 24; h++)
                ys.push(f.mapY(h * 60 * today.ppm))
            var rising = true
            for (h = 1; h <= 24; h++)
                rising = rising && ys[h] > ys[h - 1]
            check(rising, "the hours keep their order: none overlaps")
            expectEqual(labelsOverBlocks(), [], "at 13:42, no hour label overlaps a block")
            var near = ys[14] - ys[13], far = ys[16] - ys[15]
            check(near > far * 1.15 && near > 1.15 * Timeline.PPH * today.px,
                  "an hour at the middle is taller than today's, and one toward the rim shorter: "
                  + near.toFixed(0) + " px, then " + far.toFixed(0) + " px")
            var review = eventItem("Review the watch")
            check(review.width > block("Review the watch").width * today.px * 1.15,
                  "the review's block, across the middle, is wider than today's: " + review.width.toFixed(0) + " px")
            f.positionTo((21 * 60) * today.ppm)
            after(100, function() {
                var dinner = eventItem("Dinner"), plan = eventItem("Plan the week")
                var gap = plan.y - (dinner.y + dinner.height)
                check(gap >= 0 && gap < 4 * today.px, "blocks that touch keep touching, without overlapping: "
                      + gap.toFixed(1) + " px apart")
                expectEqual(labelsOverBlocks(), [], "at 21:00, no hour label overlaps a block")
                keep("today-2100", "21:00: blocks that touch", done)
            })
        },
        // The day's start and its end, each at the middle.
        function(done) {
            fit().positionTo(0)
            after(100, function() {
                keep("today-0000", "The start: 00:00", function() {
                    fit().positionTo(24 * 60 * today.ppm)
                    after(100, function() { keep("today-2400", "The end: 24:00", done) })
                })
            })
        },

        // Long titles move only in view, and only while the screen shows.
        function(done) {
            centreOn(15, 10)
            waitFor(function() { return eventItem("Review the watch").animating }, 3000,
                    "the review's long title rolls once in view", function() {
                keep("today-roll-1", "A long title, at its start", function() {
                    // The end of the roll: 18 % and 64 % of its 6.8 s cycle, in the pause at the end.
                    after(6000, function() { keep("today-roll-2", "Rolled up to its end", done) })
                })
            })
        },
        function(done) {
            centreOn(9, 0)
            after(300, function() {
                check(!eventItem("Review the watch").animating, "out of view, it stops")
                expectEqual(animatingTitles(), ["Brunch with ", "Call the lan", "Morning run "],
                            "in view at 09:00: the run and the brunch roll, the call slides")
                today.visible = false
                after(300, function() {
                    expectEqual(animatingTitles(), [], "with the screen out of view, nothing moves")
                    today.visible = true
                    done()
                })
            })
        },

        // The bubble, while it scrolls.
        function(done) {
            centreOn(9, 15)
            after(300, function() {
                expectEqual(labelsOverBlocks(), [], "at 09:15, no hour label overlaps a block")
                keep("today-0915", "The morning", function() {
                    timeline().flick(0, -900)
                    waitFor(function() { return today.peeking }, 2000, "scrolling brings the bubble", function() {
                        var band = find(today, function(item) { return item.objectName === "todayBand" })
                        waitFor(function() { return !band.visible }, 2000,
                                "and the date, the weather and the chips fade out", function() {
                            keep("today-scrolling", "Scrolling: the whole round day", done)
                        })
                    })
                })
            })
        },
        function(done) {
            waitFor(function() { return !timeline().moving }, 15000, "the flick stops", function() {
                after(500, function() {
                    check(today.peeking, "the bubble stays for a second after")
                    waitFor(function() { return !today.peeking }, 2000, "then fades out", function() {
                        var band = find(today, function(item) { return item.objectName === "todayBand" })
                        waitFor(function() { return band.visible && band.opacity === 1 }, 2000,
                                "and the header comes back", done)
                    })
                })
            })
        },

        // The calendar changes under the open screen.
        function(done) {
            var result = sh(seed + "quiet")
            check(result.status === 0, "seed the quiet day")
            waitFor(function() { return today.blocks.length === 2 && today.chips.length === 1 }, 60000,
                    "the screen follows: the quiet day", function() {
                today.now = at(13, 42)
                today.visible = false
                today.visible = true
                after(300, function() {
                    centreOn(11, 0)
                    after(300, function() { keep("today-quiet", "A quiet day", done) })
                })
            })
        },
        function(done) {
            var result = sh(seed + "empty")
            check(result.status === 0, "seed the empty day")
            waitFor(function() { return today.blocks.length === 0 && today.chips.length === 0 }, 60000,
                    "and the empty day", function() {
                var empty = find(today, function(item) {
                    return item.text !== undefined && item.text === "No events today"
                })
                check(empty !== null && empty.visible, "it says \"No events today\"")
                today.visible = false
                today.visible = true
                after(300, function() { keep("today-empty", "An empty day", done) })
            })
        },
        function(done) {
            sheet.title = "The Today screen, a timeline with the round fit (P-031's approved mockup, on the watch's own Qt)"
            sheet.files = files
            sheet.labels = labels
            after(300, function() { shot("today", done, sheet) })
        }
    ]
}
