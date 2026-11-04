/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The voicenote-docs scene of sonic/test/test.sh, on request only: the
 * pictures of sonic/docs/, the recording screen live, through the screen's own
 * tick on a clock the scene holds (voicenote-live.js), on the user's note of
 * 22:30 as ioslink sends its levels on the watch (every 100 ms, 135 ms after
 * they were heard), and on a hold on the watch at 00:10, its Levels signals as
 * they came (voicenote-levels.js' LIVE_0010). It loads VoiceNoteOverlay.qml
 * alone, so that it runs on an older one too: the pictures of before are this
 * scene on that build.
 * - voicenote-docs-first2s.png: the note's screen at eight moments of the
 *   first 2 s, from 0.5 s, when the hold shows it.
 * - voicenote-docs-whole.png: every bar of the note as it was first drawn, in
 *   red, and grey behind it where the bar changed after it was drawn, to the
 *   height it ended at.
 * - voicenote-docs-watch-first2s.png: the hold of 00:10's screen at the same
 *   eight moments.
 */
import QtQuick 2.15
import "qrc:/qml/compositor"
import "voicenote-levels.js" as Fixtures
import "voicenote-live.js" as Live

Scene {
    id: desktop

    // Before is #19's screen, which has no nextTickMs.
    readonly property string label: overlay.nextTickMs === undefined ? "before (#19)" : "after"
    readonly property var levels: Fixtures.decode(Fixtures.NOTE_2230)
    readonly property int bars: Math.floor((50 * levels.length - 50) / 100) + 1

    VoiceNoteOverlay {
        id: overlay
        width: 454
        height: 454
    }

    ContactSheet {
        id: sheet
        x: desktop.width + 100
        columns: 4
        title: desktop.label + ": the user's note of 22:30, its first 2 s on the recording screen, as ioslink sends the levels on the watch (every 100 ms, 135 ms after they were heard)"
    }

    ContactSheet {
        id: watchSheet
        x: desktop.width + 100
        y: 700
        columns: 4
        title: desktop.label + ": a hold on the watch at 00:10, the room and the start tick, its first 2 s on the recording screen, the Levels as they came"
    }

    // Every bar of the note: as first drawn, and where it changed, its last height.
    Rectangle {
        id: strip
        x: desktop.width + 100
        y: 1400
        width: 40 + 5 * desktop.bars + 20
        height: 230
        color: "#000000"
        property var first: []
        property var last: []

        Text {
            x: 16
            y: 10
            text: desktop.label + ": every bar of the user's note of 22:30 as the screen first drew it (red), and, in grey behind, the height a bar changed to after it was drawn"
            color: "#e8ecf2"
            font.pixelSize: 15
        }
        Repeater {
            model: 27
            Text {
                x: 40 + 50 * index - 4
                y: 196
                text: index + " s"
                color: "#98a2b0"
                font.pixelSize: 11
            }
        }
        // The quiet room, 11.0 to 15.5 s.
        Rectangle {
            x: 40 + 5 * 110
            y: 40
            width: 5 * 45
            height: 150
            color: "#10261a"
        }
        Repeater {
            model: desktop.bars
            Item {
                x: 40 + 5 * index
                y: 115
                Rectangle {
                    readonly property real h: strip.last[index] || 0
                    visible: h > 0 && h !== strip.first[index]
                    y: -h / 2 * 1.4
                    width: 4
                    height: h * 1.4
                    color: "#6a707a"
                }
                Rectangle {
                    readonly property real h: strip.first[index] || 0
                    visible: h > 0
                    y: -h / 2 * 1.4
                    width: 4
                    height: h * 1.4
                    color: "#ff453a"
                }
            }
        }
    }

    readonly property var arrival: Live.arrivals("ioslink")
    readonly property var moments: [500, 700, 900, 1100, 1300, 1500, 1700, 2000]

    // A fresh run to the frame at or just before ms: the screen as it stood then.
    function standAt(ms, watch) {
        var run = watch ? Live.replay(overlay, Fixtures.LIVE_0010, 500) : Live.start(overlay, levels, arrival, 500)
        run.to(ms)
        return run
    }

    // The eight moments of a run's first 2 s on a sheet.
    function moments2s(prefix, watch, target, done) {
        var files = [], labels = []
        function next(i) {
            if (i === moments.length) {
                overlay.hide()
                target.files = files
                target.labels = labels
                after(400, function() { shot(prefix, done, target) })
                return
            }
            standAt(moments[i], watch)
            var name = prefix + "-at-" + moments[i]
            after(100, function() {
                shot(name, function() {
                    files.push(shots + "/" + name + ".png")
                    labels.push((moments[i] / 1000).toFixed(1) + " s")
                    next(i + 1)
                }, overlay)
            })
        }
        next(0)
    }

    steps: [
        function(done) { moments2s("voicenote-docs-first2s", false, sheet, done) },
        function(done) { moments2s("voicenote-docs-watch-first2s", true, watchSheet, done) },
        function(done) {
            var run = Live.start(overlay, levels, arrival, 500)
            run.to(50 * levels.length + 1000)
            overlay.hide()
            var seen = Live.barsSeen(run.frames)
            var first = [], last = [], changed = 0
            for (var k = 0; k < bars; k++) {
                var list = seen[k] || []
                first.push(list.length > 0 ? list[0] : 0)
                last.push(list.length > 0 ? list[list.length - 1] : 0)
                if (list.some(function(h) { return h !== list[0] }))
                    changed++
            }
            strip.first = first
            strip.last = last
            test.log("     " + label + ": " + changed + " of " + bars + " bars changed after they were drawn")
            after(400, function() { shot("voicenote-docs-whole", done, strip) })
        }
    ]
}
