/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The recording screen of a voice note, drawn over whatever is on the watch
 * while the bottom button is held (the main repo's docs/prd/voice_notes.md
 * § 8.4): black, a red dot that breathes, the duration in light 104 px digits,
 * the loudness scrolling by as Voice Memos draws it, and one line. No
 * buttons, no touch: the hold is the only control. It sits in compositor.qml
 * between the gesture area (z 5) and the round mask (z 6), is created at start
 * and hidden, and has no Canvas: about 30 rectangles of the scene graph.
 *
 * What it reads, from ioslink's VoiceNotes interface on the session bus
 * (bridge/PROTOCOL.md § 6.14.4), through Nemo.DBus:
 * - the `Levels` signal, every 100 ms while a note is armed or records: the
 *   RMS of each 50 ms since the last, in hundredths of a dBFS. They arrive
 *   from the press on, so that the waveform opens already drawn;
 * - `State`, a JSON: `recording` (id, startedAt, phase) while a note is armed
 *   or records, and `last` (id, outcome, durationMs, dropped, reason) once it
 *   ended, with `onWatch` and `connected` for the line.
 *
 * What VoiceNoteHold, in compositor.qml, tells it, as the button goes:
 * - arm(): the press. Whatever was on show is cut, and the levels start over.
 *   disarm(): it was a click.
 * - begin(id): ioslink's answer to Arm, the note's id.
 * - show(): the hold passed 0.5 s. It is there at once, with no fade.
 * - released(durationMs): the release. The waveform freezes, and the line
 *   says "Saving…" until State has the outcome.
 * - refused(): Arm answered "": State says why, and that shows.
 * It ends by itself: the outcome shows for 2 s (2.5 s when notes were
 * dropped), the screen fades out in 250 ms, and finished() says it's done.
 * The duration runs on the note's own clock, State's startedAt.
 *
 * The row of bars slides one bar every 100 ms; with `slide` false it steps
 * instead, which draws about a sixth of the frames (10 a second, not 60).
 * It moves one bar at each tick, and never more, and only to a bar whose levels
 * are all in: a bar, once drawn, keeps its height. The levels come in bursts
 * (ioslink sends them every 100 ms, after the capture's own delay), so the row
 * runs `lag` ms behind the clock, and the ticks fall in the middle between two
 * bars' starts on that clock, so that a tick a frame late, or early, still
 * moves one bar. When the levels are late, the row waits for them, then catches
 * up a bar every `catchUpMs`. A burst that comes once the screen shows is drawn
 * bar by bar, at that pace: never several bars at once.
 */
import QtQuick 2.15
import Nemo.DBus 2.0
import "../voicenoteview.js" as View

Item {
    id: overlay

    // The design's pixels are those of the 454 × 454 screen.
    readonly property real unit: width / 454
    readonly property int slots: 30

    // The row of bars slides 10 px over each 100 ms, or steps 10 px at the end.
    property bool slide: true
    // The levels reach the screen some tenths of a second after they were
    // heard: this much of the clock isn't drawn, so that the newest bar has its
    // levels. On the watch (a hold of 2026-11-04, 00:10, its Levels as they
    // came), a level reaches the launcher 135 to 190 ms after its 50 ms end, the
    // capture's delay and ioslink's 100 ms between sends, so a bar has its
    // second level about 315 ms after the bar began: the tick that moves the
    // row to it comes 350 ms after, halfway between two bars' starts.
    property int lag: 300
    // A tick while the row is behind the clock, catching up.
    property int catchUpMs: 60
    // When the next tick comes, in ms after the last: for the tests.
    readonly property int nextTickMs: tickTimer.interval
    // The long press' threshold, for a clock that State hasn't started yet.
    property int holdMs: 500
    // How long the end shows, and how long it fades.
    property int farewellMs: 2000
    property int dropFarewellMs: 2500
    property int fadeMs: 250
    // How long after the release ioslink may take to say how the note ended.
    property int savingMs: 5000
    // The clock, which the tests hold still.
    property var nowMs: function() { return Date.now() }

    // idle: hidden, nothing under way; armed: hidden, the levels gather;
    // live: the note records; saving: released, State yet to say how it ended;
    // ended: the outcome; refused: Arm said no, and why; stopped: ioslink
    // went away.
    property string phase: "idle"
    readonly property bool shown: phase !== "idle" && phase !== "armed"
    property string noteId: ""

    // What it shows: the duration, the line, and the dot or check.
    property real elapsed: 0
    property string lineText: ""
    property bool lineAmber: false
    property bool dim: false
    property bool check: false
    property bool frozen: false
    readonly property string durationText: View.clock(elapsed)

    // The levels by bar (View.addLevels), the newest bar drawn while it
    // records, the bars to draw, and State, parsed.
    property var bars: []
    property int newestDrawn: -1
    property var heights: []
    property var info: ({})
    property real startedAt: 0
    property real dotOpacity: 1

    // How far the row of bars has slid, for the tests: 0 to -10 px.
    readonly property real offset: row.x

    // The note ended, or its screen was cut: its leases can go.
    signal finished()

    visible: shown
    z: 5.5

    // Stepping from now on: the row stays where it is.
    onSlideChanged: {
        if (!slide) {
            slideAnimation.stop()
            row.x = 0
        }
    }

    function arm() {
        cut()
        bars = []
        newestDrawn = -1
        heights = []
        frozen = false
        noteId = ""
        startedAt = 0
        elapsed = 0
        phase = "armed"
    }

    // The press was a click after all: nothing was shown, and nothing is left.
    function disarm() {
        if (phase !== "armed")
            return
        cut()
        phase = "idle"
    }

    function begin(id) {
        if (phase === "armed" || phase === "live")
            noteId = id
    }

    function show() {
        if (phase !== "armed")
            return
        frozen = false
        dim = false
        check = false
        opacity = 1
        if (startedAt === 0)
            startedAt = nowMs() - holdMs
        phase = "live"
        // It opens with the levels gathered since the press, all at once.
        elapsed = nowMs() - startedAt
        newestDrawn = Math.max(-1, Math.min(View.newestBar(elapsed, lag), View.lastComplete(bars)))
        tick()
    }

    function released(durationMs) {
        if (phase !== "live")
            return
        elapsed = durationMs
        freeze()
        phase = "saving"
        lineText = "Saving…"
        lineAmber = false
        savingTimer.restart()
    }

    function refused() {
        if (phase !== "armed" && phase !== "live" && phase !== "saving")
            return
        cut()
        bars = []
        heights = []
        elapsed = 0
        opacity = 1
        frozen = true
        // The reason is State's, when it's a refusal that it holds: any other
        // `last` is an older note's.
        var last = info.last && info.last.outcome === "failed" ? info.last : {outcome: "failed", reason: ""}
        farewell(View.ending(last, info.onWatch, info.connected), farewellMs)
        phase = "refused"
    }

    // Everything goes now, with no fade.
    function hide() {
        if (phase === "idle")
            return
        cut()
        phase = "idle"
        finished()
    }

    // Stops what runs, for another state or for none.
    function cut() {
        tickTimer.stop()
        slideAnimation.stop()
        savingTimer.stop()
        farewellTimer.stop()
        fadeAnimation.stop()
        row.x = 0
        opacity = 1
    }

    // The bars stop sliding, and the row ends at the latest level heard.
    function freeze() {
        tickTimer.stop()
        slideAnimation.stop()
        row.x = 0
        frozen = true
        check = false
        rebuild()
    }

    // ioslink said how the note ended.
    function end(last) {
        if (phase !== "live" && phase !== "saving")
            return
        savingTimer.stop()
        if (last.durationMs !== undefined)
            elapsed = last.durationMs
        freeze()
        var drops = last.dropped ? last.dropped.length : 0
        farewell(View.ending(last, info.onWatch, info.connected),
                 drops > 0 || last.outcome === "dropped" ? dropFarewellMs : farewellMs)
        phase = "ended"
    }

    function farewell(ending, ms) {
        lineText = ending.text
        lineAmber = ending.amber
        check = ending.check
        dim = ending.dim
        farewellTimer.interval = ms
        farewellTimer.restart()
    }

    // ioslink left the bus: the note is cut, and saved at its next start.
    function stopped() {
        if (phase === "armed") {
            phase = "idle"
            finished()
            return
        }
        if (phase !== "live" && phase !== "saving")
            return
        cut()
        freeze()
        farewell({text: "Recorder stopped", amber: true, check: false, dim: true}, farewellMs)
        phase = "stopped"
    }

    // The screen's tick, about every 100 ms while it records: one bar more,
    // when its levels are in, and the time of the next tick.
    function tick() {
        elapsed = nowMs() - startedAt
        dotOpacity = View.breath(elapsed)
        var line = View.recordingLine(elapsed)
        lineText = line.text
        lineAmber = line.amber
        var target = View.newestBar(elapsed, lag)
        var step = newestDrawn < Math.min(target, View.lastComplete(bars))
        if (step)
            newestDrawn++
        // The next tick: halfway between two bars' starts, or sooner while the
        // row is behind.
        var at = (elapsed - lag) / View.BAR_MS
        var wait = newestDrawn < target ? catchUpMs : (Math.floor(at) + 1.5 - at) * View.BAR_MS
        wait = Math.round(Math.max(catchUpMs, Math.min(1.5 * View.BAR_MS, wait)))
        rebuild()
        if (slide && step) {
            // The bars just moved one place left, as the row moves one bar
            // right; then it slides back to where it began, by the next tick.
            row.x = 0
            slideAnimation.duration = wait
            slideAnimation.restart()
        }
        if (phase === "live") {
            tickTimer.interval = wait
            tickTimer.restart()
        }
    }

    function rebuild() {
        var newest = frozen ? View.lastBar(bars) : newestDrawn
        heights = View.heights(bars, newest, slots)
    }

    function read(json) {
        var parsed
        try {
            parsed = JSON.parse(json)
        } catch (error) {
            return
        }
        if (parsed === null || typeof parsed !== "object")
            return
        info = parsed
        if (phase !== "armed" && phase !== "live" && phase !== "saving")
            return
        var recording = parsed.recording
        if (recording && recording.id !== undefined && (noteId === "" || recording.id === noteId)) {
            // Only this note can be recording: ioslink has one at a time.
            noteId = recording.id
            if (recording.startedAt)
                startedAt = recording.startedAt
            if (recording.phase === "saving" && phase === "live") {
                freeze()
                phase = "saving"
                lineText = "Saving…"
                lineAmber = false
                savingTimer.restart()
            }
        }
        var last = parsed.last
        if (phase !== "armed" && noteId !== "" && last && last.id === noteId
                && !(recording && recording.id === noteId))
            end(last)
    }

    function addLevels(id, fromMs, centibels) {
        if (noteId === "" || id !== noteId || phase === "idle")
            return
        View.addLevels(bars, fromMs, centibels)
        // While it records, the bars move at the tick; frozen, the screen
        // shows the note's last levels as they come.
        if (frozen)
            rebuild()
    }

    // Started by show(), and again by each tick() for the next.
    Timer {
        id: tickTimer
        interval: 100
        onTriggered: overlay.tick()
    }

    // The end shows for a while, then the screen fades out.
    Timer {
        id: farewellTimer
        onTriggered: fadeAnimation.start()
    }

    // The release, and no word from ioslink in time: the screen goes, with no
    // claim about the note.
    Timer {
        id: savingTimer
        interval: overlay.savingMs
        onTriggered: overlay.hide()
    }

    NumberAnimation {
        id: fadeAnimation
        target: overlay
        property: "opacity"
        to: 0
        duration: overlay.fadeMs
        onFinished: overlay.hide()
    }

    // ioslink on the session bus, whose VoiceNotes is read afresh each time it
    // comes back, as the quick panel's Find phone reads its FindPhone.
    DBusInterface {
        id: onBus
        bus: DBus.SessionBus
        service: "org.sonicscrewdriver.ioslink"
        path: "/org/sonicscrewdriver/ioslink"
        iface: "org.sonicscrewdriver.ioslink.VoiceNotes"
        watchServiceStatus: true
        onStatusChanged: {
            if (status !== DBusInterface.Available)
                overlay.stopped()
        }
    }

    Loader {
        active: onBus.status === DBusInterface.Available
        sourceComponent: DBusInterface {
            bus: DBus.SessionBus
            service: "org.sonicscrewdriver.ioslink"
            path: "/org/sonicscrewdriver/ioslink"
            iface: "org.sonicscrewdriver.ioslink.VoiceNotes"
            propertiesEnabled: true
            signalsEnabled: true
            property string state: ""
            onStateChanged: overlay.read(state)
            // The Levels signal.
            function levels(id, fromMs, centibels) {
                overlay.addLevels(id, fromMs, centibels)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // The dot that breathes while it records, and the check once it's saved.
    Rectangle {
        objectName: "dot"
        x: 219 * overlay.unit
        y: 84 * overlay.unit
        width: 16 * overlay.unit
        height: width
        radius: width / 2
        antialiasing: true
        color: "#ff453a"
        visible: overlay.phase === "live"
        opacity: overlay.dotOpacity
        Behavior on opacity {
            enabled: overlay.slide
            NumberAnimation { duration: 100 }
        }
    }

    Image {
        objectName: "check"
        x: 210 * overlay.unit
        y: 75 * overlay.unit
        width: 34 * overlay.unit
        height: width
        sourceSize: Qt.size(width, height)
        source: "qrc:/sonic/icons/voice-note-saved.svg"
        visible: overlay.check
    }

    Text {
        objectName: "duration"
        x: 0
        y: 150 * overlay.unit - height / 2
        width: overlay.width
        horizontalAlignment: Text.AlignHCenter
        text: overlay.durationText
        color: overlay.dim ? "#4a505a" : "#ffffff"
        font.family: "Noto Sans"
        font.weight: Font.Light
        font.pixelSize: 104 * overlay.unit
        font.letterSpacing: -2.08 * overlay.unit
    }

    // The loudness: bars 6 px wide every 10 px, round ended, about y 272, the
    // newest at x 330 and the oldest fading out to the left of x 116. The
    // row is clipped at x 56 and slides inside it.
    Item {
        objectName: "waveform"
        x: 56 * overlay.unit
        y: 200 * overlay.unit
        width: 284 * overlay.unit
        height: 144 * overlay.unit
        clip: true

        Item {
            id: row

            NumberAnimation {
                id: slideAnimation
                target: row
                property: "x"
                from: 0
                to: -10 * overlay.unit
                duration: 100
            }

            Repeater {
                model: overlay.slots

                Rectangle {
                    readonly property real bar: overlay.heights[index] || 0
                    visible: bar > 0
                    x: (330 - 56 - 10 * index) * overlay.unit
                    y: (272 - 200 - bar / 2) * overlay.unit
                    width: 6 * overlay.unit
                    height: bar * overlay.unit
                    radius: width / 2
                    antialiasing: true
                    color: overlay.frozen ? "#4a505a" : "#ff453a"
                }
            }
        }
    }

    // The fade at the left: the bars are black behind it by x 56, and whole
    // from x 116.
    Rectangle {
        x: 56 * overlay.unit
        y: 200 * overlay.unit
        width: 60 * overlay.unit
        height: 144 * overlay.unit
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ff000000" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    // "Now": a red line a bar's width after the newest bar.
    Rectangle {
        objectName: "now"
        x: 340 * overlay.unit
        y: 214 * overlay.unit
        width: 2 * overlay.unit
        height: 116 * overlay.unit
        color: "#ff453a"
        visible: overlay.phase === "live"
    }

    Text {
        objectName: "line"
        x: (454 - 296) / 2 * overlay.unit
        y: 372 * overlay.unit - height / 2
        width: 296 * overlay.unit
        horizontalAlignment: Text.AlignHCenter
        text: overlay.lineText
        color: overlay.lineAmber ? "#ffb340" : "#c9cfd8"
        font.family: "Noto Sans"
        font.pixelSize: 26 * overlay.unit
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 16 * overlay.unit
    }
}
