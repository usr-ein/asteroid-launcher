/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The voicenote scene of sonic/test/test.sh: the launcher's own recording
 * screen, VoiceNoteOverlay.qml, and the hold that drives it, VoiceNoteHold.qml
 * (the main repo's docs/prd/voice_notes.md § 8.2 and § 8.4), compiled in as in
 * the launcher, with stand-ins in the harness for what they call on the test
 * bus: ioslink's VoiceNotes (bridge/PROTOCOL.md § 6.14.4) as `voicenotes`, and
 * mce's request interface as `mce`.
 * - What the screen works out, in voicenoteview.js: the duration's text, the
 *   bars' heights from the levels, the countdown, and the line for each end.
 * - The screens, fed through the bus as ioslink feeds them: recording; the
 *   last 30 s; saved, with the iPhone and without; a drop past the cache's cap;
 *   the 10 min limit; a note that alone passed the cache's cap, ended early;
 *   a note cut short by a lost microphone, and kept; too short; storage full
 *   and no microphone; the second between the release and the outcome; and
 *   ioslink gone. Each is a screenshot of the overlay alone at 454 × 454,
 *   checked against the circle 12 px inside the round edge (nothing that isn't
 *   black beyond it), and for what it must show: the red dot or the green
 *   check, the red or grey bars, the line's colour, the "now" line. The
 *   mockup's own levels, the synthetic test note with the watch's room noise,
 *   draw the bars.
 * - How it moves: the row slides 10 px over each 100 ms, or steps; the end shows
 *   for 2 s, 2.5 s for a drop, and fades for 250 ms; the countdown.
 * - The hold, with the button's real events through a FIFO, and the stand-ins
 *   answering as ioslink does: the order of what it calls (the keepalive first,
 *   then Arm; the blanking pause and Keep at 0.5 s; Stop at the release) and
 *   that mce's leases go only once the screen has; a click, which Arms and
 *   Cancels and shows nothing; no ioslink on the bus, which does nothing at
 *   all; a refusal (storage, microphone); an error from Arm; an Arm answered
 *   late, with a click, a hold and a hold released before it; the display off,
 *   which mce turns on; ioslink going away mid-note; its limit at 10:00 with
 *   the button still held; ioslink never answering, ended by the release's
 *   watchdog and by the hard limit; and a second hold over the first's screen.
 * - Where a hold records, with compositor.qml's wiring of the hold and of the
 *   rings face's single press, and the scene's state in place of the compositor's:
 *   the home's face page, whatever the face shows and whatever the display does.
 *   A short press on the rings face opens its Timer or Stopwatch app after the
 *   release, and a long press there records and opens none; a hold records on
 *   every face, with the display on, ambient and off; and never in an app or on
 *   another panel, the display off included, where it calls nothing at all.
 * - What the screen costs under emulation: frames and CPU for a second of
 *   it, with the bars sliding and stepping, against the same with it hidden.
 */
import QtQuick 2.15
import QtQuick.Window 2.2
import Nemo.DBus 2.0
import org.asteroid.launcher 1.0
import "qrc:/qml/compositor"
import "qrc:/qml/voicenoteview.js" as View
import "qrc:/qml/voicebutton.js" as VoiceButton
import "qrc:/qml/ringsbutton.js" as RingsButton

Scene {
    id: desktop

    readonly property string fifo: "/tmp/sonic-voicenote"
    readonly property int keyMenu: 139
    readonly property int evKey: 1
    readonly property int evSyn: 0

    // The mockup's test note: the levels of the synthetic speech mixed with the
    // watch's room noise, one character each for 50 ms, as dBFS + 60 from "A".
    readonly property string noteLevels: "@LEVELS@"

    // What compositor.qml has, with the harness' stand-ins behind it.
    DBusInterface {
        id: mceRequest
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
    }

    DBusInterface {
        id: voiceNotesBus
        bus: DBus.SessionBus
        service: "org.sonicscrewdriver.ioslink"
        path: "/org/sonicscrewdriver/ioslink"
        iface: "org.sonicscrewdriver.ioslink.VoiceNotes"
        watchServiceStatus: true
    }

    // Every call that the hold makes, in the order it sends them.
    property var trace: []
    // What compositor.qml reads: the display, the home, where the panels are,
    // and the view of the rings that the face shows; and the apps that the
    // single press opened.
    property bool displayOn: true
    property bool ambient: false
    property bool homeActive: true
    property int panelX: 0
    property int panelY: 0
    property string ringsView: ""
    property var opened: []

    // The compositor's state as a test sets it: what it names, the rest as the
    // face's page has it, with the display on.
    function scene(state) {
        desktop.displayOn = state.displayOn !== undefined ? state.displayOn : true
        desktop.ambient = state.ambient !== undefined ? state.ambient : false
        desktop.homeActive = state.homeActive !== undefined ? state.homeActive : true
        desktop.panelX = state.panelX !== undefined ? state.panelX : 0
        desktop.panelY = state.panelY !== undefined ? state.panelY : 0
        desktop.ringsView = state.ringsView !== undefined ? state.ringsView : ""
    }

    VoiceNoteOverlay {
        id: overlay
        width: 454
        height: 454
    }

    VoiceNoteHold {
        id: hold
        overlay: overlay
        ioslinkUp: voiceNotesBus.status === DBusInterface.Available
        displayLit: desktop.displayOn && !desktop.ambient
        callMce: function(method, args, callback) {
            desktop.trace.push("mce " + method + (typeof args === "string" ? " " + args : ""))
            mceRequest.call(method, args, callback)
        }
        callIoslink: function(method, args, callback, errback) {
            desktop.trace.push("ioslink " + method + args.map(function(a) { return " " + a.value }).join(""))
            voiceNotesBus.typedCall(method, args, callback, errback)
        }
    }

    // The button, wired as compositor.qml wires it: the hold through voicebutton.js'
    // guard, and the single press through ringsbutton.js, with the scene's state in
    // place of the compositor's.
    ButtonDoubleClick {
        id: button
        onHoldStarted: {
            if (VoiceButton.canRecord(desktop.displayOn, desktop.ambient, desktop.homeActive, desktop.panelX, desktop.panelY))
                hold.start(pressedAt)
        }
        onHoldConfirmed: hold.confirm()
        onHoldEnded: hold.end(releasedAt, confirmed)
        onSingleClicked: {
            var app = RingsButton.app(desktop.displayOn, desktop.ambient, desktop.homeActive, desktop.panelX, desktop.panelY,
                                      desktop.ringsView)
            if (app !== "")
                desktop.opened.push(app)
        }
    }

    ContactSheet {
        id: sheet
        x: desktop.width + 100
        columns: 4
        title: "The recording screen, at 454 × 454: recording, the last 30 s, the second before the outcome, saved, saved with the iPhone away, a drop, the limit, a note past the cache's cap, a microphone lost, too short, storage full, no microphone, ioslink gone, and a hold live"
    }

    property var files: []
    property var labels: []

    function keep(name, label, done) {
        files.push(shots + "/" + name + ".png")
        labels.push(label)
        shot(name, done, overlay)
    }

    // ---- the stream of levels, as ioslink signals them ----

    function noteLevel(t) {
        // dBFS at t ms since the press: the room, then the note.
        if (t < 750)
            return -50 + 3 * Math.sin(t / 37)
        var i = Math.floor((t - 750) / 50)
        return noteLevels.charCodeAt(i % noteLevels.length) - 65 - 60
    }

    // Levels for [from, to) ms since the press, in centibels, from the
    // microphone's start (250 ms) on.
    function levelsBetween(from, to) {
        var out = []
        for (var t = Math.max(from, 250); t + 50 <= to; t += 50)
            out.push(Math.round(noteLevel(t) * 100))
        return out
    }

    // Sends a stretch of the note's levels at once.
    function sendLevels(id, from, to) {
        var first = Math.max(from, 250)
        first -= first % 50
        voicenotes.levels(id, first, levelsBetween(first, to))
    }

    // A stream of levels every 100 ms from a press at a boot-time stamp, once
    // ioslink has a note, as ioslink does.
    Timer {
        id: feeder
        property double stamp: 0
        property double sent: 250
        // The note's id when it isn't ioslink's own.
        property string id: ""
        interval: 100
        repeat: true
        onTriggered: {
            var id = feeder.id !== "" ? feeder.id : voicenotes.recording
            if (id === "")
                return
            var t = test.bootMs() - stamp
            var out = levelsBetween(sent, t)
            if (out.length > 0) {
                voicenotes.levels(id, sent, out)
                sent += 50 * out.length
            }
        }
        function run(from) {
            stamp = from
            sent = 250
            start()
        }
    }

    // The screen's phases, each with the time it began.
    property var phaseLog: []
    Connections {
        target: overlay
        function onPhaseChanged() { desktop.phaseLog.push({phase: overlay.phase, at: Date.now()}) }
    }

    // The frames that Qt Quick has drawn.
    property int frames: 0
    Connections {
        target: desktop.Window.window
        ignoreUnknownSignals: true
        function onAfterRendering() { desktop.frames++ }
    }

    // What a live screen costs, per second over 4 s after one to settle:
    // frames drawn, and CPU time in ms. mode: "hidden", "steps" or "slide".
    function measure(mode, then) {
        var live = mode !== "hidden"
        overlay.slide = mode === "slide"
        overlay.nowMs = function() { return Date.now() }
        if (live) {
            overlay.arm()
            overlay.begin("COST")
            voicenotes.setState(JSON.stringify({recording: {id: "COST", startedAt: Date.now() - 600, phase: "recording"},
                                                onWatch: 1, connected: true, seq: ++desktop.serial}))
            feeder.id = "COST"
            feeder.run(test.bootMs() - 600)
        }
        waitFor(function() { return !live || overlay.startedAt !== 0 }, 5000, "the " + mode + " screen is ready", function() {
            if (live)
                overlay.show()
            after(1000, function() {
                var frames0 = desktop.frames, cpu0 = test.cpuMs(), t0 = Date.now()
                after(4000, function() {
                    var seconds = (Date.now() - t0) / 1000
                    var result = {frames: (desktop.frames - frames0) / seconds, cpu: (test.cpuMs() - cpu0) / seconds}
                    feeder.stop()
                    feeder.id = ""
                    overlay.hide()
                    after(300, function() { then(result) })
                })
            })
        })
    }

    // ---- what a scene shows ----

    // The overlay as it stands after the compositor armed and showed it for a
    // note `elapsed` ms old, with the levels of its last 4 s, and the clock held
    // still: State has the note recording, and the Levels come over the bus.
    property double now: 0
    property int serial: 0

    function recording(id, elapsed, then) {
        overlay.slide = false
        overlay.nowMs = function() { return desktop.now }
        overlay.arm()
        overlay.begin(id)
        voicenotes.setState(JSON.stringify({recording: {id: id, startedAt: desktop.now - elapsed, phase: "recording"},
                                            onWatch: 1, connected: true, seq: ++desktop.serial}))
        sendLevels(id, elapsed - 4000, elapsed)
        var last = Math.floor((elapsed - 50) / 100)
        waitFor(function() { return overlay.startedAt !== 0 && View.lastBar(overlay.bars) >= last - 1 }, 5000,
                "the screen has State's clock and the levels", function() {
            overlay.show()
            after(300, then)
        })
    }

    // Ends the note as ioslink does: State's `last`, and no `recording`.
    function ended(last, extra, then) {
        var state = {last: last, onWatch: 1, connected: true, seq: ++desktop.serial}
        for (var k in extra)
            state[k] = extra[k]
        voicenotes.setState(JSON.stringify(state))
        waitFor(function() { return overlay.phase === "ended" || overlay.phase === "refused" }, 5000,
                "the screen has the outcome", function() { after(300, then) })
    }

    // Checks a screenshot of the overlay against the circle, 12 px inside the
    // round edge, and for what it must show.
    function look(name, spec) {
        var file = shots + "/" + name + ".png"
        var edge = test.outside(file, 227, 227, 215, 16)
        check(edge.count === 0, name + ": nothing but black beyond the circle 12 px inside the edge"
              + (edge.count === 0 ? "" : " (" + edge.count + " pixels, the first at (" + edge.x + ", " + edge.y + "), " + edge.value + "/255)"))
        function share(x, y, w, h, colour, tolerance) { return test.share(file, x, y, w, h, colour, tolerance === undefined ? 40 : tolerance) }
        var live = spec.live === true
        var dot = share(219, 84, 16, 16, "#ff453a")
        check(live ? dot > 0.6 : dot < 0.02, name + ": the red dot " + (live ? "is there" : "is gone") + " (" + dot.toFixed(2) + ")")
        var tick = share(210, 75, 34, 34, "#30d158")
        check(spec.check === true ? tick > 0.4 : tick < 0.02, name + ": the green check " + (spec.check === true ? "is there" : "is not") + " (" + tick.toFixed(2) + ")")
        var now = share(340, 214, 2, 116, "#ff453a")
        check(live ? now > 0.9 : now < 0.02, name + ": the red \"now\" line " + (live ? "is there" : "is gone") + " (" + now.toFixed(2) + ")")
        var red = share(116, 214, 224, 116, "#ff453a")
        var grey = share(116, 214, 224, 116, "#4a505a", 20)
        if (spec.bars === "red")
            check(red > 0.04 && grey < 0.005, name + ": red bars (" + red.toFixed(3) + " red, " + grey.toFixed(3) + " grey)")
        else if (spec.bars === "grey")
            check(grey > 0.02 && red < 0.005, name + ": grey bars, frozen (" + grey.toFixed(3) + " grey, " + red.toFixed(3) + " red)")
        else
            check(grey < 0.005 && red < 0.005, name + ": no bars (" + grey.toFixed(3) + " grey, " + red.toFixed(3) + " red)")
        var amber = share(63, 350, 328, 44, "#ffb340", 50)
        var plain = share(63, 350, 328, 44, "#c9cfd8", 50)
        if (spec.amber === true)
            check(amber > 0.01 && plain < 0.002, name + ": the line is amber (" + amber.toFixed(3) + ")")
        else
            check(plain > 0.01 && amber < 0.002, name + ": the line is light grey (" + plain.toFixed(3) + ")")
        var white = share(90, 95, 274, 110, "#ffffff", 40)
        var dim = share(90, 95, 274, 110, "#4a505a", 20)
        if (spec.dim === true)
            check(dim > 0.02 && white < 0.002, name + ": the duration is dimmed (" + dim.toFixed(3) + ")")
        else
            check(white > 0.05 && dim < 0.005, name + ": the duration is white (" + white.toFixed(3) + ")")
    }

    // One screen: what the overlay says, and the screenshot.
    function screen(name, label, says, spec, done) {
        expectEqual({duration: overlay.durationText, line: overlay.lineText}, says, name + ": the screen's words")
        keep(name, label, function() {
            look(name, spec)
            done()
        })
    }

    // Waits for the stand-ins' calls, and the overlay's end.
    function settled(then) {
        waitFor(function() { return overlay.phase === "idle" && !hold.keepaliveHeld && !hold.blankingPaused }, 8000,
                "the screen is away and nothing is held", then)
    }

    function reset() {
        desktop.trace = []
        voicenotes.clear()
        mce.clear()
    }

    function press(stamp) {
        test.inputEvents(fifo, [[stamp, evKey, keyMenu, 1], [stamp, evSyn, 0, 0]])
    }

    function release(stamp) {
        test.inputEvents(fifo, [[stamp, evKey, keyMenu, 0], [stamp, evSyn, 0, 0]])
    }

    function stripped(list) {
        return list.map(function(c) { return c.replace(/NOTE-\d+/, "NOTE").replace(/ \d{4,}$/, " <time>") })
    }

    readonly property string session: "sonic-launcher-voicenote"
    readonly property string startCall: "mce req_cpu_keepalive_start " + session
    readonly property string stopCall: "mce req_cpu_keepalive_stop " + session

    // Each step ends 450 ms before the next begins: a press within 400 ms of
    // the last one's is a double-click's second, and starts no hold.
    function spaced(list) {
        return list.map(function(step) {
            return function(done) {
                step(function() { after(450, done) })
            }
        })
    }

    steps: spaced([
        // What the screen works out.
        function(done) {
            expectEqual([View.clock(0), View.clock(999), View.clock(42300), View.clock(247000), View.clock(599999), View.clock(600000), View.clock(700000)],
                        ["0:00", "0:00", "0:42", "4:07", "9:59", "10:00", "10:00"], "the duration: m:ss, from 0:00 to 9:59, then 10:00")
            expectEqual([View.barHeight(-60), View.barHeight(-40), View.barHeight(-20), View.barHeight(-90), View.barHeight(0)],
                        [6, 53, 100, 6, 100], "a bar is 6 px at -60 dBFS and 100 px at -20, in between linearly, and no more or less")
            var bars = []
            View.addLevels(bars, 200, [-5000, -3000, -4000])
            View.addLevels(bars, 450, [-2500])
            expectEqual([bars[2], bars[3], bars[4], bars[5]], [-30, -40, -25, undefined],
                        "a bar takes the louder of its two 50 ms levels: 200 and 250 ms are one, 300 ms another, and one level alone is a bar")
            expectEqual(View.heights(bars, 4, 5), [View.barHeight(-25), View.barHeight(-40), View.barHeight(-30), 0, 0],
                        "the heights run back from the newest bar, and 0 where there is no level")
            expectEqual([View.newestBar(1000, 150), View.newestBar(149, 150)], [8, -1], "the newest bar leaves out the lag")
            expectEqual([View.breath(0), View.breath(500), View.breath(1000)].map(function(v) { return Math.round(v * 100) / 100 }),
                        [1, 0.35, 1], "the dot breathes once a second")
            expectEqual([View.recordingLine(42000), View.recordingLine(569000), View.recordingLine(570000), View.recordingLine(581000), View.recordingLine(599500), View.recordingLine(600000)],
                        [{text: "Release to save", amber: false}, {text: "Release to save", amber: false},
                         {text: "30 s left", amber: true}, {text: "19 s left", amber: true}, {text: "1 s left", amber: true},
                         {text: "Saving…", amber: false}],
                        "the line says \"Release to save\", and from 9:30 the seconds left, in amber")
            expectEqual(View.ending({outcome: "saved"}, 3, true), {text: "Saved · sending", amber: false, check: true, dim: false}, "saved, the iPhone in reach")
            expectEqual(View.ending({outcome: "saved"}, 3, false), {text: "Saved · 3 on watch", amber: false, check: true, dim: false}, "saved, the iPhone away")
            expectEqual(View.ending({outcome: "saved"}, 0, false).text, "Saved · 1 on watch", "the note itself waits on the watch")
            expectEqual(View.ending({outcome: "saved"}, 12345, false).text, "Saved · 999+ on watch", "and the count stays short")
            expectEqual(View.ending({outcome: "dropped", dropped: [{startedAt: Date.UTC(2026, 10, 3, 8, 2)}]}, 3, true),
                        {text: "Saved · 08:02 dropped", amber: true, check: true, dim: false}, "a drop: the time of the note, in amber")
            expectEqual(View.ending({outcome: "dropped", dropped: [{startedAt: 0}, {startedAt: 1}, {startedAt: 2}]}, 3, true).text, "Saved · 3 dropped", "several drops: how many")
            expectEqual(View.ending({outcome: "dropped", dropped: [{}]}, 3, true).text, "Saved · dropped", "a drop with no time: no time")
            expectEqual(View.ending({outcome: "limit", dropped: [{startedAt: Date.UTC(2026, 10, 3, 18, 2)}]}, 3, true).text, "Saved · 18:02 dropped", "a drop is told whatever else the note did")
            expectEqual(View.ending({outcome: "limit"}, 3, true).text, "10 min limit · saved", "the 10 min limit")
            expectEqual(View.ending({outcome: "limit", reason: "storage"}, 3, true), {text: "Storage full · saved", amber: true, check: true, dim: false},
                        "a note alone past the cache's cap ends as a limit before 10:00: it says storage, in amber")
            expectEqual(View.ending({outcome: "saved", reason: "microphone"}, 3, true), {text: "Microphone lost · saved", amber: true, check: true, dim: false},
                        "a note cut short by its microphone and kept")
            expectEqual(View.ending({outcome: "saved", reason: "encoder"}, 3, true), {text: "Encoder failed · saved", amber: true, check: true, dim: false},
                        "and by its encoder")
            expectEqual(View.ending({outcome: "saved", reason: "microphone", dropped: [{startedAt: Date.UTC(2026, 10, 3, 8, 2)}]}, 3, true).text, "Saved · 08:02 dropped",
                        "a drop is told before an early end")
            expectEqual(View.ending({outcome: "failed", reason: "encoder"}, 0, true).text, "Couldn't record", "an encoder that gave nothing")
            expectEqual(View.ending({outcome: "tooShort"}, 3, true), {text: "Too short", amber: false, check: false, dim: true}, "too short")
            expectEqual(View.ending({outcome: "failed", reason: "storage"}, 0, true), {text: "Watch storage full", amber: true, check: false, dim: true}, "storage full")
            expectEqual(View.ending({outcome: "failed", reason: "microphone"}, 0, true).text, "Microphone unavailable", "no microphone")
            expectEqual(View.ending({outcome: "failed", reason: "x"}, 0, true).text, "Couldn't record", "any other failure")
            expectEqual(View.ending(undefined, 0, true).text, "Couldn't record", "and no word at all")
            var source = sh("cat /src/src/qml/compositor/VoiceNoteOverlay.qml").output
            check(source.indexOf("Canvas") === -1 || source.replace(/\/\*[\s\S]*?\*\//, "").indexOf("Canvas") === -1, "the overlay has no Canvas: the bars are Rectangles of the scene graph")
            done()
        },

        // The stand-ins come on the bus.
        function(done) {
            check(mce.start(), "the stand-in for mce comes on the bus")
            check(voicenotes.start(), "the stand-in for ioslink's VoiceNotes comes on the bus")
            waitFor(function() { return hold.ioslinkUp && overlay.info.onWatch !== undefined }, 8000,
                    "ioslink is on the bus, and the screen has read State", function() {
                expectEqual(overlay.phase, "idle", "the screen is created hidden")
                expectEqual(overlay.visible, false, "and isn't visible")
                check(overlay.z === 5.5, "between the gesture area (z 5) and the round mask (z 6)")
                desktop.now = Date.now()
                done()
            })
        },

        // The screens.
        function(done) {
            recording("N1", 42000, function() {
                screen("voicenote-recording", "Recording, 0:42", {duration: "0:42", line: "Release to save"},
                       {live: true, bars: "red"}, done)
            })
        },
        function(done) {
            recording("N2", 581000, function() {
                screen("voicenote-last30", "The last 30 s: \"19 s left\"", {duration: "9:41", line: "19 s left"},
                       {live: true, bars: "red", amber: true}, done)
            })
        },
        function(done) {
            recording("N3", 42000, function() {
                overlay.released(42000)
                after(300, function() {
                    screen("voicenote-saving", "Released, before the outcome", {duration: "0:42", line: "Saving…"},
                           {bars: "grey"}, done)
                })
            })
        },
        function(done) {
            recording("N3", 42000, function() {
                ended({id: "N3", outcome: "saved", durationMs: 42000, dropped: [], reason: ""}, {}, function() {
                    screen("voicenote-saved", "Saved, the iPhone in reach", {duration: "0:42", line: "Saved · sending"},
                           {check: true, bars: "grey"}, done)
                })
            })
        },
        function(done) {
            recording("N4", 96000, function() {
                ended({id: "N4", outcome: "saved", durationMs: 96000, dropped: [], reason: ""}, {onWatch: 3, connected: false}, function() {
                    screen("voicenote-saved-on-watch", "Saved, the iPhone away: 3 on watch", {duration: "1:36", line: "Saved · 3 on watch"},
                           {check: true, bars: "grey"}, done)
                })
            })
        },
        function(done) {
            recording("N5", 247000, function() {
                var dropped = Date.UTC(2026, 10, 3, 8, 2)
                ended({id: "N5", outcome: "dropped", durationMs: 247000, dropped: [{startedAt: dropped, durationMs: 64000}], reason: ""},
                      {onWatch: 3}, function() {
                    screen("voicenote-dropped", "Saved past the cache's cap: the oldest dropped", {duration: "4:07", line: "Saved · 08:02 dropped"},
                           {check: true, bars: "grey", amber: true}, done)
                })
            })
        },
        function(done) {
            recording("N6", 599000, function() {
                ended({id: "N6", outcome: "limit", durationMs: 600000, dropped: [], reason: ""}, {}, function() {
                    screen("voicenote-limit", "The 10 min limit", {duration: "10:00", line: "10 min limit · saved"},
                           {check: true, bars: "grey"}, done)
                })
            })
        },
        function(done) {
            recording("N6b", 200000, function() {
                ended({id: "N6b", outcome: "limit", durationMs: 200000, dropped: [], reason: "storage"}, {}, function() {
                    screen("voicenote-limit-storage", "A note past the cap: storage full", {duration: "3:20", line: "Storage full · saved"},
                           {check: true, bars: "grey", amber: true}, done)
                })
            })
        },
        function(done) {
            recording("N6c", 20000, function() {
                ended({id: "N6c", outcome: "saved", durationMs: 20000, dropped: [], reason: "microphone"}, {}, function() {
                    screen("voicenote-microphone-lost", "The microphone lost, the note kept", {duration: "0:20", line: "Microphone lost · saved"},
                           {check: true, bars: "grey", amber: true}, done)
                })
            })
        },
        function(done) {
            recording("N7", 800, function() {
                ended({id: "N7", outcome: "tooShort", durationMs: 800, dropped: [], reason: ""}, {}, function() {
                    screen("voicenote-too-short", "Released under 1 s: too short", {duration: "0:00", line: "Too short"},
                           {bars: "grey", dim: true}, done)
                })
            })
        },
        function(done) {
            overlay.slide = false
            overlay.arm()
            voicenotes.setState(JSON.stringify({last: {id: "", outcome: "failed", durationMs: 0, dropped: [], reason: "storage"},
                                                onWatch: 40, connected: true, seq: ++desktop.serial}))
            waitFor(function() { return overlay.info.last !== undefined && overlay.info.last.reason === "storage" }, 5000, "the screen has State", function() {
                overlay.refused()
                after(300, function() {
                    screen("voicenote-storage-full", "Watch storage full", {duration: "0:00", line: "Watch storage full"},
                           {amber: true, dim: true}, done)
                })
            })
        },
        function(done) {
            overlay.arm()
            voicenotes.setState(JSON.stringify({last: {id: "", outcome: "failed", durationMs: 0, dropped: [], reason: "microphone"},
                                                onWatch: 0, connected: true, seq: ++desktop.serial}))
            waitFor(function() { return overlay.info.last.reason === "microphone" }, 5000, "the screen has State", function() {
                overlay.refused()
                after(300, function() {
                    screen("voicenote-no-microphone", "Microphone unavailable", {duration: "0:00", line: "Microphone unavailable"},
                           {amber: true, dim: true}, done)
                })
            })
        },
        function(done) {
            recording("N8", 12000, function() {
                voicenotes.stop()
                waitFor(function() { return overlay.phase === "stopped" }, 5000, "ioslink goes away: the screen says so", function() {
                    after(300, function() {
                        screen("voicenote-ioslink-gone", "ioslink gone mid-note", {duration: "0:12", line: "Recorder stopped"},
                               {bars: "grey", amber: true, dim: true}, function() {
                            check(voicenotes.start(), "ioslink comes back")
                            waitFor(function() { return hold.ioslinkUp }, 8000, "on the bus", function() {
                                overlay.hide()
                                done()
                            })
                        })
                    })
                })
            })
        },

        // ---- the hold: the button's own events, and the stand-ins' answers ----

        // A long hold, with the iPhone connected, at the defaults: the order of
        // what the hold calls, and what shows, and when it goes.
        function(done) {
            sh("rm -f " + fifo + " && mkfifo " + fifo)
            test.inputEvents(fifo, [])
            button.devices = [fifo]
            overlay.slide = true
            overlay.nowMs = function() { return Date.now() }
            desktop.scene({})
            voicenotes.answer = "id"
            voicenotes.outcome = "auto"
            reset()
            desktop.phaseLog = []
            var t0 = Date.now(), stamp = test.bootMs()
            feeder.run(stamp)
            press(stamp)
            waitFor(function() { return overlay.phase === "live" }, 5000, "the recording screen shows once the hold is confirmed", function() {
                var wait = Date.now() - t0
                check(wait >= 480 && wait < 2500, "at 0.5 s from the press: " + wait + " ms")
                waitFor(function() { return voicenotes.calls.length >= 2 && mce.calls.length >= 3 }, 3000, "ioslink and mce have their calls", function() {
                    expectEqual(stripped(desktop.trace), [startCall, "mce req_cpu_keepalive_period " + session + "-period", "ioslink Arm <time>",
                                                          "mce req_display_blanking_pause", "ioslink Keep NOTE"],
                                "the keepalive first, then Arm; at 0.5 s the blanking pause, then Keep; the display was on, so no wake")
                    expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Keep NOTE"], "ioslink heard Arm, then Keep")
                    expectEqual(voicenotes.calls[0], "Arm " + stamp, "Arm has the press' own boot-time stamp")
                    expectEqual(mce.calls, ["req_cpu_keepalive_start " + session, "req_cpu_keepalive_period " + session + "-period", "req_display_blanking_pause"],
                                "and mce heard its calls")
                    check(overlay.shown && overlay.opacity === 1 && overlay.visible, "the screen is up, whole")
                    expectEqual(overlay.noteId, voicenotes.recording, "it has the note's id")
                    after(1300, function() {
                        var drawn = overlay.heights.filter(function(h) { return h > 0 }).length
                        check(drawn >= 8, "the bars come with the levels: " + drawn + " of them after 1.3 s")
                        check(/^0:0[12]$/.test(overlay.durationText), "the duration runs on the note's clock: " + overlay.durationText)
                        // The slide.
                        var least = 0, tries = 0
                        function sample() {
                            least = Math.min(least, overlay.offset)
                            if (++tries < 16) {
                                after(25, sample)
                                return
                            }
                            check(least <= -3, "the row slides: down to " + least.toFixed(1) + " px within 100 ms")
                            overlay.slide = false
                            after(250, function() {
                                var steps = 0
                                for (var i = 0; i < 6; i++)
                                    steps += overlay.offset
                                expectEqual(steps, 0, "with the slide off the row steps and never moves between")
                                overlay.slide = true
                                keep("voicenote-live", "A hold, live", function() {
                                    release(test.bootMs())
                                    waitFor(function() { return overlay.phase === "ended" }, 5000, "the release ends the note", function() {
                                        var endedAt = Date.now()
                                        check(/^0:0[1-3]$/.test(overlay.durationText), "the duration stands at the note's own: " + overlay.durationText)
                                        expectEqual(overlay.lineText, "Saved · sending", "saved, the iPhone in reach")
                                        waitFor(function() { return voicenotes.calls.length >= 3 }, 3000, "ioslink has Stop", function() {
                                            expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Keep NOTE", "Stop NOTE <time>"], "Stop came with the release")
                                            check(hold.keepaliveHeld && hold.blankingPaused, "mce's keepalive and blanking pause are held while the screen shows")
                                            settled(function() {
                                                var shown = Date.now() - endedAt
                                                check(shown >= 2100 && shown < 3600, "2 s of \"Saved\" and 250 ms of fade, and the leases go with it: " + shown + " ms")
                                                waitFor(function() { return mce.calls.length >= 5 }, 3000, "mce has its last calls", function() {
                                                    expectEqual(mce.calls.slice(3), ["req_cpu_keepalive_stop " + session, "req_display_cancel_blanking_pause"],
                                                                "the keepalive ends, then the blanking pause")
                                                    expectEqual(stripped(desktop.trace).slice(5), ["ioslink Stop NOTE <time>", stopCall, "mce req_display_cancel_blanking_pause"],
                                                                "after the screen: Stop was sent first, and the leases end last")
                                                    var phases = desktop.phaseLog.map(function(p) { return p.phase })
                                                    expectEqual(phases, ["armed", "live", "saving", "ended", "idle"], "the screen's phases")
                                                    feeder.stop()
                                                    done()
                                                })
                                            })
                                        })
                                    })
                                })
                            })
                        }
                        sample()
                    })
                })
            })
        },

        // A click: Arm, then Cancel; the screen is never shown.
        function(done) {
            reset()
            desktop.phaseLog = []
            var stamp = test.bootMs()
            feeder.run(stamp)
            press(stamp)
            after(90, function() {
                release(test.bootMs())
                waitFor(function() { return voicenotes.calls.length >= 2 && mce.calls.length >= 2 && !hold.keepaliveHeld }, 5000,
                        "ioslink has Arm and Cancel, and the keepalive was let go", function() {
                    feeder.stop()
                    expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Cancel NOTE"], "a click Arms and Cancels: no Keep, no Stop")
                    expectEqual(mce.calls, ["req_cpu_keepalive_start " + session, "req_cpu_keepalive_stop " + session],
                                "the keepalive starts and stops, and the display isn't touched")
                    var t = stripped(desktop.trace)
                    check(t[0] === startCall && t[1] === "ioslink Arm <time>" && t.indexOf("ioslink Cancel NOTE") > 1 && t.indexOf(stopCall) > 0,
                          "the keepalive first, then Arm, and Cancel after it: " + t)
                    expectEqual(desktop.phaseLog.map(function(p) { return p.phase }), ["armed", "idle"], "the screen was armed and never shown")
                    check(!hold.blankingPaused && !hold.keepaliveHeld && overlay.phase === "idle", "nothing is held")
                    done()
                })
            })
        },

        // A double-click: the first press Arms and Cancels like a click, and the
        // second press is no hold at all.
        function(done) {
            reset()
            desktop.phaseLog = []
            var first = test.bootMs()
            press(first)
            after(60, function() {
                release(test.bootMs())
                after(60, function() {
                    press(test.bootMs())
                    after(700, function() {
                        release(test.bootMs())
                        settled(function() {
                            expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Cancel NOTE"], "a double-click: one Arm, one Cancel, nothing from the second press, held 0.7 s")
                            expectEqual(mce.calls, ["req_cpu_keepalive_start " + session, "req_cpu_keepalive_stop " + session], "one keepalive, and no display call")
                            expectEqual(desktop.phaseLog.map(function(p) { return p.phase }), ["armed", "idle"], "the screen never showed")
                            done()
                        })
                    })
                })
            })
        },

        // With no ioslink on the bus, a hold does nothing at all.
        function(done) {
            voicenotes.stop()
            waitFor(function() { return !hold.ioslinkUp }, 5000, "ioslink leaves the bus", function() {
                reset()
                desktop.phaseLog = []
                press(test.bootMs())
                after(900, function() {
                    release(test.bootMs())
                    after(500, function() {
                        expectEqual(desktop.trace, [], "a hold with no ioslink calls nothing")
                        expectEqual(mce.calls, [], "mce hears nothing: no keepalive for nothing")
                        expectEqual(desktop.phaseLog, [], "and the screen doesn't stir")
                        check(voicenotes.start(), "ioslink comes back")
                        waitFor(function() { return hold.ioslinkUp }, 8000, "on the bus", done)
                    })
                })
            })
        },

        // Arm answers "": no room, no microphone. The screen says so at 0.5 s.
        function(done) {
            voicenotes.answer = "refused"
            voicenotes.refusal = "storage"
            reset()
            desktop.phaseLog = []
            var stamp = test.bootMs()
            press(stamp)
            waitFor(function() { return overlay.phase === "refused" }, 5000, "a refusal shows at 0.5 s", function() {
                expectEqual({duration: overlay.durationText, line: overlay.lineText, amber: overlay.lineAmber},
                            {duration: "0:00", line: "Watch storage full", amber: true}, "storage full, in amber")
                after(400, function() {
                    release(test.bootMs())
                    settled(function() {
                        expectEqual(stripped(desktop.trace), [startCall, "ioslink Arm <time>", "mce req_display_blanking_pause", stopCall,
                                                              "mce req_display_cancel_blanking_pause"],
                                    "no Keep, no Stop and no Cancel for no note; the screen on, the leases ended with it")
                        expectEqual(stripped(voicenotes.calls), ["Arm <time>"], "ioslink only heard Arm")
                        done()
                    })
                })
            })
        },

        // Arm fails: ioslink busy, or without VoiceNotes. Nothing shows.
        function(done) {
            voicenotes.answer = "busy"
            reset()
            desktop.phaseLog = []
            var stamp = test.bootMs()
            press(stamp)
            after(1000, function() {
                expectEqual(overlay.phase, "idle", "an error from Arm: no screen at 0.5 s")
                check(!hold.keepaliveHeld, "and the keepalive, with nothing to keep it for, is let go at 0.5 s")
                release(test.bootMs())
                after(300, function() {
                    expectEqual(stripped(desktop.trace), [startCall, "ioslink Arm <time>", stopCall], "Arm, and the keepalive's end: no Keep, no Stop")
                    expectEqual(desktop.phaseLog.map(function(p) { return p.phase }), ["armed", "idle"], "the screen was armed and never shown")
                    done()
                })
            })
        },

        // Arm's answer comes late: a click, a hold, and a hold released first.
        function(done) {
            voicenotes.answer = "id"
            voicenotes.armDelay = 800
            reset()
            var stamp = test.bootMs()
            press(stamp)
            after(100, function() {
                release(test.bootMs())
                waitFor(function() { return voicenotes.calls.length >= 2 }, 5000, "ioslink has Cancel, after Arm's answer", function() {
                    check(voicenotes.times[1] - voicenotes.times[0] >= 600, "Cancel waited for Arm's answer: " + (voicenotes.times[1] - voicenotes.times[0]) + " ms later")
                    expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Cancel NOTE"], "a late click: Arm, then Cancel")
                    check(!hold.keepaliveHeld, "the keepalive didn't wait for it")
                    done()
                })
            })
        },
        function(done) {
            voicenotes.armDelay = 1300
            reset()
            desktop.phaseLog = []
            press(test.bootMs())
            after(1100, function() {
                release(test.bootMs())
                waitFor(function() { return voicenotes.calls.length >= 3 }, 5000, "ioslink has Keep and Stop, after Arm's answer", function() {
                    expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Keep NOTE", "Stop NOTE <time>"],
                                "a hold released before Arm's answer: Keep, then Stop, when it comes")
                    expectEqual(stripped(desktop.trace).slice(0, 5), [startCall, "ioslink Arm <time>", "mce req_display_blanking_pause", "ioslink Keep NOTE", "ioslink Stop NOTE <time>"],
                                "in the order it sent them")
                    waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                        expectEqual(overlay.lineText, "Saved · sending", "saved: the hold lasted 1.1 s")
                        voicenotes.armDelay = 0
                        overlay.farewellMs = 600
                        overlay.fadeMs = 100
                        settled(done)
                    })
                })
            })
        },

        // The display off: mce turns it on at 0.5 s.
        function(done) {
            desktop.scene({displayOn: false})
            reset()
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                after(300, function() {
                    release(test.bootMs())
                    settled(function() {
                        expectEqual(stripped(desktop.trace), [startCall, "ioslink Arm <time>", "mce req_display_state_on", "mce req_display_blanking_pause",
                                                              "ioslink Keep NOTE", "ioslink Stop NOTE <time>", stopCall, "mce req_display_cancel_blanking_pause"],
                                    "with the display off: the screen, then mce's wake, then the pause and Keep")
                        desktop.scene({})
                        done()
                    })
                })
            })
        },

        // A drop past the cache's cap shows 2.5 s.
        function(done) {
            voicenotes.outcome = "dropped"
            voicenotes.drops = [{startedAt: Date.UTC(2026, 10, 3, 8, 2), durationMs: 64000}]
            overlay.farewellMs = 2000
            overlay.dropFarewellMs = 2500
            overlay.fadeMs = 250
            reset()
            desktop.phaseLog = []
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                after(400, function() {
                    release(test.bootMs())
                    waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                        expectEqual(overlay.lineText, "Saved · 08:02 dropped", "the drop, in amber: " + overlay.lineAmber)
                        settled(function() {
                            var log = desktop.phaseLog
                            var shown = log[log.length - 1].at - log[log.length - 2].at
                            check(shown >= 2600 && shown < 4200, "a drop shows 2.5 s, and the fade is 250 ms more: " + shown + " ms")
                            voicenotes.outcome = "auto"
                            voicenotes.drops = []
                            overlay.farewellMs = 600
                            overlay.dropFarewellMs = 600
                            overlay.fadeMs = 100
                            done()
                        })
                    })
                })
            })
        },

        // ioslink goes away mid-note.
        function(done) {
            reset()
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                after(300, function() {
                    voicenotes.stop()
                    waitFor(function() { return overlay.phase === "stopped" }, 5000, "ioslink goes: the screen says so", function() {
                        expectEqual(overlay.lineText, "Recorder stopped", "the line")
                        release(test.bootMs())
                        settled(function() {
                            check(true, "and the leases end with the screen")
                            check(voicenotes.start(), "ioslink comes back")
                            waitFor(function() { return hold.ioslinkUp }, 8000, "on the bus", done)
                        })
                    })
                })
            })
        },

        // ioslink goes away before the hold is confirmed: the leases go at once,
        // and the hold, still down at 0.5 s, shows nothing.
        function(done) {
            reset()
            desktop.phaseLog = []
            press(test.bootMs())
            after(150, function() {
                voicenotes.stop()
                waitFor(function() { return !hold.ioslinkUp && !hold.keepaliveHeld }, 5000, "ioslink goes: the keepalive is let go at once", function() {
                    after(700, function() {
                        expectEqual(desktop.phaseLog.map(function(p) { return p.phase }), ["armed", "idle"], "no screen at 0.5 s, though the button is down")
                        release(test.bootMs())
                        after(300, function() {
                            check(voicenotes.start(), "ioslink comes back")
                            waitFor(function() { return hold.ioslinkUp }, 8000, "on the bus", done)
                        })
                    })
                })
            })
        },

        // The 10:00 limit, with the button still held: ioslink's own stop.
        function(done) {
            reset()
            desktop.phaseLog = []
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                after(300, function() {
                    voicenotes.limit()
                    waitFor(function() { return overlay.phase === "ended" }, 5000, "ioslink stops the note itself", function() {
                        expectEqual({duration: overlay.durationText, line: overlay.lineText}, {duration: "10:00", line: "10 min limit · saved"}, "the limit")
                        settled(function() {
                            check(true, "the leases end with the screen though the button is still down")
                            release(test.bootMs())
                            waitFor(function() { return voicenotes.calls.length >= 3 }, 5000, "the release still calls Stop", function() {
                                expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Keep NOTE", "Stop NOTE <time>"], "the release still calls Stop, past the note's own end")
                                after(300, function() {
                                    expectEqual(voicenotes.errors, [], "ioslink takes it with no error, as it does for the note that ended last")
                                    expectEqual(overlay.phase, "idle", "and the screen stays away")
                                    done()
                                })
                            })
                        })
                    })
                })
            })
        },

        // A call for an id that no note had is NotFound: the hold's failed calls
        // are only logged, and nothing else changes.
        function(done) {
            reset()
            hold.fire("Cancel", [{type: "s", value: "NOBODY"}])
            waitFor(function() { return voicenotes.errors.length > 0 }, 5000, "ioslink answers NotFound", function() {
                expectEqual(voicenotes.errors, ["NotFound NOBODY"], "to an id that no note had")
                expectEqual({phase: overlay.phase, held: hold.keepaliveHeld}, {phase: "idle", held: false}, "and nothing else stirs")
                done()
            })
        },

        // ioslink never says how the note ended: the release's watchdog.
        function(done) {
            voicenotes.stopDelay = 60000
            overlay.savingMs = 700
            reset()
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                after(300, function() {
                    release(test.bootMs())
                    var at = Date.now()
                    waitFor(function() { return overlay.phase === "saving" }, 3000, "the release freezes the screen", function() {
                        expectEqual(overlay.lineText, "Saving…", "the line, until ioslink says")
                        settled(function() {
                            var wait = Date.now() - at
                            check(wait >= 600 && wait < 3000, "no word in 0.7 s: the screen goes with no claim, after " + wait + " ms")
                            voicenotes.stopDelay = 80
                            overlay.savingMs = 5000
                            done()
                        })
                    })
                })
            })
        },

        // ioslink never answers Arm at all, and the button is held: the limit
        // on what is held.
        function(done) {
            voicenotes.answer = "hang"
            hold.capMs = 1500
            reset()
            var at = Date.now()
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                settled(function() {
                    var held = Date.now() - at
                    check(held >= 1400 && held < 3500, "the hard limit lets go of everything: after " + held + " ms")
                    expectEqual(overlay.phase, "idle", "and the screen goes")
                    release(test.bootMs())
                    after(300, function() {
                        expectEqual(stripped(desktop.trace), [startCall, "ioslink Arm <time>", "mce req_display_blanking_pause", stopCall, "mce req_display_cancel_blanking_pause"],
                                    "no Keep and no Stop for a note that never was")
                        voicenotes.answer = "id"
                        hold.capMs = 635000
                        done()
                    })
                })
            })
        },

        // A second hold while the first's screen still shows: the screen is cut
        // at the press, and the leases go with the new hold, a click.
        function(done) {
            overlay.farewellMs = 2000
            overlay.fadeMs = 250
            reset()
            desktop.phaseLog = []
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                release(test.bootMs())
                waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                    check(hold.keepaliveHeld, "the first screen holds the leases")
                    press(test.bootMs())
                    after(90, function() {
                        release(test.bootMs())
                        waitFor(function() { return overlay.phase === "idle" && !hold.keepaliveHeld }, 3000, "the second press cut the screen, and the click let go", function() {
                            expectEqual(desktop.phaseLog.map(function(p) { return p.phase }), ["armed", "live", "saving", "ended", "armed", "idle"],
                                        "the phases: the first note's, then armed again and idle at once, with no second fade")
                            expectEqual(stripped(desktop.trace).filter(function(c) { return c === startCall || c === stopCall }), [startCall, stopCall],
                                        "one keepalive for both, ended once")
                            overlay.farewellMs = 600
                            overlay.fadeMs = 100
                            done()
                        })
                    })
                })
            })
        },

        // The rings face, which the user's watch face becomes while timers or
        // stopwatches run: a short press opens its app, after the release, and
        // is a click to ioslink; a long press records, and opens no app.
        function(done) {
            desktop.scene({ringsView: "timers"})
            desktop.opened = []
            reset()
            desktop.phaseLog = []
            press(test.bootMs())
            after(90, function() {
                release(test.bootMs())
                after(900, function() {
                    expectEqual(desktop.opened, ["sonic-timer"], "a short press on the rings face, timers running, opens the Timer app, after the release")
                    expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Cancel NOTE"], "and is a click to ioslink: Arm, then Cancel")
                    expectEqual(desktop.phaseLog.map(function(p) { return p.phase }), ["armed", "idle"], "no screen")
                    done()
                })
            })
        },
        function(done) {
            desktop.scene({ringsView: "stopwatches"})
            desktop.opened = []
            reset()
            press(test.bootMs())
            after(90, function() {
                release(test.bootMs())
                after(900, function() {
                    expectEqual(desktop.opened, ["sonic-stopwatch"], "stopwatches running: the Stopwatch app")
                    done()
                })
            })
        },
        function(done) {
            desktop.scene({ringsView: "timers"})
            desktop.opened = []
            reset()
            desktop.phaseLog = []
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "a long press on the rings face records", function() {
                after(400, function() {
                    release(test.bootMs())
                    waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                        after(800, function() {
                            expectEqual(desktop.opened, [], "and opens no app, at the release or after it")
                            expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Keep NOTE", "Stop NOTE <time>"], "it recorded: Arm, Keep, Stop")
                            settled(done)
                        })
                    })
                })
            })
        },

        // A hold records on every face the user's watch face has, with the
        // display on, ambient and off. The face's mode is no input of the hold:
        // only the rings' view is read, by the single press.
        function(done) {
            var cases = [
                {face: "the music face's cover", display: "on", state: {}},
                {face: "the rings face, timers running", display: "on", state: {ringsView: "timers"}},
                {face: "the rings face, stopwatches running", display: "on", state: {ringsView: "stopwatches"}},
                {face: "the door glyph", display: "on", state: {}},
                {face: "the plain digital face", display: "on", state: {}},
                {face: "the music face's cover", display: "ambient", state: {ambient: true}},
                {face: "the rings face, timers running", display: "ambient", state: {ambient: true, ringsView: "timers"}},
                {face: "the rings face, stopwatches running", display: "off", state: {displayOn: false, ringsView: "stopwatches"}},
                {face: "the plain digital face", display: "off", state: {displayOn: false}},
                {face: "the door glyph", display: "off and ambient", state: {displayOn: false, ambient: true}}
            ]
            function next(i) {
                if (i === cases.length) {
                    desktop.scene({})
                    done()
                    return
                }
                var c = cases[i]
                var label = "on " + c.face + ", the display " + c.display
                desktop.scene(c.state)
                desktop.opened = []
                reset()
                press(test.bootMs())
                waitFor(function() { return overlay.phase === "live" }, 5000, "a hold records " + label, function() {
                    after(300, function() {
                        release(test.bootMs())
                        waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                            expectEqual({calls: stripped(voicenotes.calls), opened: desktop.opened},
                                        {calls: ["Arm <time>", "Keep NOTE", "Stop NOTE <time>"], opened: []},
                                        label + ": Arm, Keep, Stop, and no app")
                            if (!(c.state.displayOn === undefined && c.state.ambient === undefined))
                                check(mce.calls.indexOf("req_display_state_on") !== -1, label + ": mce turns the display on")
                            settled(function() { after(450, function() { next(i + 1) }) })
                        })
                    })
                })
            }
            next(0)
        },

        // Never in an app, nor on another panel, with the screen off too: a
        // hold does nothing at all, and calls nothing.
        function(done) {
            var cases = [
                {where: "an app in front, the display on", state: {homeActive: false}},
                {where: "an app in front, the display off", state: {homeActive: false, displayOn: false}},
                {where: "an app in front, ambient", state: {homeActive: false, ambient: true}},
                {where: "the app list", state: {panelY: 1}},
                {where: "the app list, the display off", state: {panelY: 1, displayOn: false}},
                {where: "Today", state: {panelX: 1}},
                {where: "the quick panel", state: {panelY: -1}},
                {where: "the notifications, the display off", state: {panelX: -1, displayOn: false}}
            ]
            function next(i) {
                if (i === cases.length) {
                    desktop.scene({})
                    done()
                    return
                }
                var c = cases[i]
                desktop.scene(c.state)
                reset()
                desktop.phaseLog = []
                press(test.bootMs())
                after(900, function() {
                    release(test.bootMs())
                    after(300, function() {
                        expectEqual({trace: desktop.trace, mce: mce.calls, ioslink: voicenotes.calls, phases: desktop.phaseLog},
                                    {trace: [], mce: [], ioslink: [], phases: []},
                                    "in " + c.where + " a hold of 0.9 s does nothing and calls nothing")
                        after(450, function() { next(i + 1) })
                    })
                })
            }
            next(0)
        },

        // What it costs, under emulation. Qt's software renderer, in QEMU: only
        // the relation between the three is of any use.
        function(done) {
            overlay.farewellMs = 2000
            overlay.fadeMs = 250
            measure("hidden", function(hidden) {
                measure("steps", function(steps) {
                    measure("slide", function(slide) {
                        test.log("     cost per second, under emulation: hidden " + hidden.frames.toFixed(1) + " frames, " + hidden.cpu.toFixed(0) + " ms CPU;"
                                 + " steps " + steps.frames.toFixed(1) + " frames, " + steps.cpu.toFixed(0) + " ms CPU;"
                                 + " slide " + slide.frames.toFixed(1) + " frames, " + slide.cpu.toFixed(0) + " ms CPU")
                        check(hidden.frames < 1, "hidden, it draws nothing: " + hidden.frames.toFixed(1) + " frames a second")
                        check(steps.frames > 5 && steps.frames < 25, "stepping, it draws about 10 frames a second: " + steps.frames.toFixed(1))
                        check(slide.frames > steps.frames * 2, "sliding, it draws many more than stepping: " + slide.frames.toFixed(1))
                        done()
                    })
                })
            })
        },

        function(done) {
            sheet.files = files
            sheet.labels = labels
            after(400, function() { shot("voicenote-sheet", done, sheet) })
        }
    ])
}
