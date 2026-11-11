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
 *   and no microphone; the second between the stop press and the outcome; and
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
 *   then Arm; the blanking pause and Keep at 0.5 s; the release does nothing, and Stop
 *   comes at the next press) and
 *   that mce's leases go only once the screen has; a click, which Arms and
 *   Cancels and shows nothing; no ioslink on the bus, which does nothing at
 *   all; a refusal (storage, microphone); an error from Arm; an Arm answered
 *   late, with a click, a hold and a note stopped before it; the display off,
 *   which mce turns on; ioslink going away mid-note; its limit at 10:00 with
 *   the note latched; ioslink never answering, ended by the stop press's
 *   watchdog and by the hard limit; and a press over the "Saved" screen, which does nothing.
 * - Where a hold records, with compositor.qml's wiring of the hold and of the
 *   rings face's single press, and the scene's state in place of the compositor's:
 *   with the display off, wherever the watch was; with it on or ambient, the
 *   home's face page, whatever the face shows. A short press on the rings face
 *   opens its Timer or Stopwatch app after the release, and a long press there
 *   records and opens none; a hold records on every face, with the display on,
 *   ambient and off; with the display off it records in an app, on the app
 *   list, the quick panel, Today and the notifications, and leaves them where
 *   they were; and with the display on or ambient it does nothing in an app or
 *   on another panel, and calls nothing at all.
 * - The waveform's mapping, against the fixtures of voicenote-levels.js: the
 *   user's own note of 22:30 (its quiet room draws flat, his speech tall, the
 *   gaps between his words showing), a quiet room, a busier room, quieter
 *   speech; the floor is the room's whatever speech does to it; and the screen
 *   at five moments of that note, as a contact sheet.
 * - The waveform live, through the screen's own tick, frame by frame on a
 *   clock the scene holds: a hold on the watch, its Levels signals as they came
 *   (voicenote-levels.js' LIVE_0010), and the user's note fed as heard, as
 *   ioslink sends them on the watch, in bursts and late. A bar keeps its height
 *   once drawn, the row moves one bar a tick at the most and never back, and
 *   never waits on the watch's own timing; the first second isn't full height;
 *   each bar is the view's.
 * - The screen kept on, against the stand-in for mce, which plays mce's own
 *   rules: an unlock refused while the display is off and allowed once it is
 *   on, a pause ignored unless the display is on and the touch lock off, and
 *   the lockscreen's blank. From the screen off and from the screen on, the
 *   display stays on for the whole note; the touch lock is asked to unlock only
 *   once the display is on, again while it is locked, and at once when it
 *   locks mid-note; the pause comes after the unlock; and every way a note ends
 *   locks it again when the face is in front, with a model of compositor.qml's
 *   lockscreen that the panels moving meanwhile leave alone.
 * - What the screen costs under emulation: frames and CPU for a second of
 *   it, with the bars sliding and stepping, against the same with it hidden.
 */
import QtQuick 2.15
import QtQuick.Window 2.2
import Nemo.DBus 2.0
import org.asteroid.launcher 1.0
import "qrc:/qml/compositor"
import "qrc:/qml/voicenoteview.js" as View
import "voicenote-levels.js" as Fixtures
import "voicenote-live.js" as Live
import "qrc:/qml/voicebutton.js" as VoiceButton
import "qrc:/qml/ringsbutton.js" as RingsButton

Scene {
    id: desktop

    readonly property string fifo: "/tmp/sonic-voicenote"
    readonly property int keyMenu: 139
    readonly property int evKey: 1
    readonly property int evSyn: 0

    // The mockup's test note: the levels of the synthetic speech mixed with the
    // watch's room noise, one per 50 ms, in dBFS (voicenote-levels.js). A scene
    // may set a `program` instead: a function of the ms since the press, in dBFS.
    readonly property var noteLevels: Fixtures.decode(Fixtures.SPEECH)
    property var program: null
    readonly property var note2230: Fixtures.decode(Fixtures.NOTE_2230)

    // The user's own note of 22:30 as a program: its levels, and the room's
    // after the end.
    function noteOf2230(t) {
        var i = Math.floor(t / 50)
        return i < note2230.length ? note2230[i] : -60
    }

    // What compositor.qml has, with the harness' stand-ins behind it.
    DBusInterface {
        id: mceRequest
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
    }

    // mce's signals, as the stand-in sends them: what the test of the stand-in
    // heard, while `heard` is a list.
    DBusInterface {
        id: mceSignals
        property var heard: null
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/signal"
        iface: "com.nokia.mce.signal"
        signalsEnabled: true
        watchServiceStatus: true
        function tklock_mode_ind(mode) {
            if (heard)
                heard.push("tklock " + mode)
        }
        function display_blanking_pause_allowed_ind(allowed) {
            if (heard)
                heard.push("allowed " + allowed)
        }
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
    // face's page has it, with the display on. mce starts from the same: the
    // display on, or off (ambient is mce's low power state, not on), and the
    // touch lock locked, as with the face or the display off.
    function scene(state) {
        desktop.displayOn = state.displayOn !== undefined ? state.displayOn : true
        desktop.ambient = state.ambient !== undefined ? state.ambient : false
        desktop.homeActive = state.homeActive !== undefined ? state.homeActive : true
        desktop.panelX = state.panelX !== undefined ? state.panelX : 0
        desktop.panelY = state.panelY !== undefined ? state.panelY : 0
        desktop.ringsView = state.ringsView !== undefined ? state.ringsView : ""
        mce.reset(desktop.displayOn && !desktop.ambient ? "on" : "off", "locked")
    }

    // The display as mce has it, as lipstick tells the compositor: on, it is
    // out of ambient too.
    Connections {
        target: mce
        function onDisplayChanged(on) {
            desktop.displayOn = on
            if (on)
                desktop.ambient = false
        }
    }

    // What compositor.qml does with the lockscreen: the face, its longTimeout,
    // is the lockscreen, set whenever longTimeout changes, but not while a note
    // keeps the screen (VoiceNoteHold.qml locks it again after). `locks` is
    // every value it set, `sequence` the same with the hold's calls to mce, in
    // order. The model only records: lipstick's own calls to mce aren't the
    // hold's.
    property bool longTimeout: desktop.homeActive && desktop.panelX === 0 && desktop.panelY === 0
    property var locks: []
    property var sequence: []
    onLongTimeoutChanged: {
        if (hold.screenKept)
            return
        desktop.locks.push(desktop.longTimeout)
        desktop.sequence.push("lockscreen " + (desktop.longTimeout ? "locked" : "unlocked"))
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
        lockWanted: desktop.longTimeout
        callMce: function(method, args, callback) {
            var call = "mce " + method + (typeof args === "string" ? " " + args : "")
            desktop.trace.push(call)
            desktop.sequence.push(call)
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
        captured: hold.recording || overlay.shown
        onCapturedPressed: hold.stop(pressedAt)
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
        title: "The recording screen, at 454 × 454: recording, silence then speech then silence, the last 30 s, the second before the outcome, saved, saved with the iPhone away, a drop, the limit, a note past the cache's cap, a microphone lost, too short, storage full, no microphone, ioslink gone, and a hold live"
    }

    ContactSheet {
        id: sheetNote
        x: desktop.width + 100
        y: 1800
        columns: 5
        title: "The user's own note of 22:30 on the recording screen, whole through the view's floor and its curve, at five moments of it: speech, then the room begins, the quiet room, then speech begins, and speech"
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
        if (program !== null)
            return program(t)
        if (t < 750)
            return -50 + 3 * Math.sin(t / 37)
        return noteLevels[Math.floor((t - 750) / 50) % noteLevels.length]
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

    function recording(id, elapsed, then, from) {
        overlay.slide = false
        overlay.nowMs = function() { return desktop.now }
        overlay.arm()
        overlay.begin(id)
        voicenotes.setState(JSON.stringify({recording: {id: id, startedAt: desktop.now - elapsed, phase: "recording"},
                                            onWatch: 1, connected: true, seq: ++desktop.serial}))
        sendLevels(id, from !== undefined ? from : elapsed - 4000, elapsed)
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
            check(red > (spec.tall === true ? 0.08 : 0.04) && grey < 0.005, name + ": red bars (" + red.toFixed(3) + " red, " + grey.toFixed(3) + " grey)")
        else if (spec.bars === "grey")
            check(grey > 0.02 && red < 0.005, name + ": grey bars, frozen (" + grey.toFixed(3) + " grey, " + red.toFixed(3) + " red)")
        else if (spec.bars === "flatred")
            check(red > 0.02 && red < 0.07 && grey < 0.005, name + ": the room's bars, flat and red (" + red.toFixed(3) + " red, " + grey.toFixed(3) + " grey)")
        else if (spec.bars === "flat")
            check(grey > 0.003 && grey < 0.02 && red < 0.005, name + ": the room's bars, flat and grey, frozen (" + grey.toFixed(3) + " grey, " + red.toFixed(3) + " red)")
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
        waitFor(function() { return overlay.phase === "idle" && !hold.keepaliveHeld && !hold.blankingPaused && !hold.screenKept }, 8000,
                "the screen is away and nothing is held", then)
    }

    function reset() {
        desktop.trace = []
        desktop.locks = []
        desktop.sequence = []
        voicenotes.clear()
        mce.clear()
    }

    // A note held holdMs from the scene's state, mce blanking a locked display
    // 1.5 s after it came on and an unlocked one after 3 s: the display stays on
    // for all of it, with the touch lock unlocked and the pause held, and mce
    // never refuses an unlock or ignores a pause; after the screen the leases
    // end, then the touch lock is locked again. then(order): what the hold
    // asked of mce and what mce did, in order, up to the pause held.
    function keptScreen(label, holdMs, then) {
        mce.lockBlankMs = 1500
        mce.blankMs = 3000
        reset()
        var stamp = test.bootMs()
        feeder.run(stamp)
        press(stamp)
        waitFor(function() { return overlay.phase === "live" }, 5000, label + ": the screen shows", function() {
            after(holdMs - 500, function() {
                check(mce.display === "on" && mce.paused && mce.tklock === "unlocked",
                      label + ": " + (holdMs / 1000) + " s into the note the display is on, the pause held, the touch lock unlocked: "
                      + mce.display + ", " + (mce.paused ? "paused" : "not paused") + ", " + mce.tklock)
                check(mce.events.every(function(e) { return e.indexOf("blanked") === -1 && e.indexOf("denied") === -1 && e !== "pause ignored" && e !== "pause dropped" }),
                      label + ": mce never blanked it, refused an unlock or ignored a pause: " + mce.events.join(", "))
                stopPress()
                settled(function() {
                    feeder.stop()
                    waitFor(function() { return mce.log.indexOf("mce req_tklock_mode_change locked-delay") !== -1 }, 3000, label + ": mce has the lock", function() {
                        var log = mce.log
                        var tail = log.slice(log.lastIndexOf(stopCall))
                        expectEqual(tail.filter(function(e) { return e.indexOf("mce ") === 0 }),
                                    ["mce req_cpu_keepalive_stop " + session, "mce req_display_cancel_blanking_pause", "mce req_tklock_mode_change locked-delay"],
                                    label + ": after the screen, the keepalive and the pause end, then the touch lock is locked again")
                        check(mce.tklock === "locked", label + ": mce has it locked: " + mce.tklock)
                        mce.lockBlankMs = 0
                        mce.blankMs = 0
                        var wanted = ["mce req_display_state_on", "the display is on", "mce req_tklock_mode_change unlocked", "unlocked",
                                      "mce req_display_blanking_pause", "pause held"]
                        var order = []
                        for (var i = 0; i < log.length && order.indexOf("pause held") === -1; i++) {
                            if (wanted.indexOf(log[i]) !== -1 && order.indexOf(log[i]) === -1)
                                order.push(log[i])
                        }
                        then(order)
                    })
                })
            })
        })
    }

    // After a note with the face in front: the touch lock locked again, the
    // hold's last call to mce, after it had asked to unlock it (the calls go
    // out at once; mce has them a moment later).
    function relocked(label) {
        var calls = stripped(desktop.trace).filter(function(c) { return c.indexOf("mce ") === 0 })
        check(calls.indexOf("mce req_tklock_mode_change unlocked") !== -1 && calls[calls.length - 1] === "mce req_tklock_mode_change locked-delay",
              label + ": the face is locked again after the note (the last call " + calls[calls.length - 1] + ")")
    }

    function press(stamp) {
        test.inputEvents(fifo, [[stamp, evKey, keyMenu, 1], [stamp, evSyn, 0, 0]])
    }

    function release(stamp) {
        test.inputEvents(fifo, [[stamp, evKey, keyMenu, 0], [stamp, evSyn, 0, 0]])
    }

    // What ends a note: the long press' release, which does nothing, then the
    // press that stops it, and its release.
    function stopPress() {
        release(test.bootMs())
        press(test.bootMs())
        release(test.bootMs())
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
            expectEqual([View.barHeight(-60, -52), View.barHeight(-44, -52), View.barHeight(-35.5, -52), View.barHeight(-27, -52), View.barHeight(0, -52)].map(Math.round),
                        [6, 6, 53, 100, 100], "a bar is flat up to 8 dB over the floor, 100 px from -27 dBFS, and an S-curve between: 53 px in the middle, no more or less")
            expectEqual([View.barHeight(-44, -58), View.barHeight(-44, -52), View.barHeight(-44)].map(Math.round), [22, 6, 6],
                        "it is measured from the room's floor: -44 dBFS is 22 px over a quiet room's, flat over a usual one's, and the floor is -52 until the note says otherwise")
            var bars = []
            View.addLevels(bars, 200, [-5000, -3000, -4000])
            View.addLevels(bars, 450, [-2500])
            expectEqual([bars[2], bars[3], bars[4], bars[5]], [-40, -40, -25, undefined],
                        "a bar is the mean in dB of its two 50 ms levels: 200 and 250 ms are one, 300 ms another, and one level alone is a bar until its other comes")
            expectEqual(View.heights(bars, 4, 5).map(Math.round), [100, 19, 19, 0, 0],
                        "the heights run back from the newest bar, over each one's floor, and 0 where there is no level")
            expectEqual([View.lastComplete([]), View.lastComplete(bars)], [-1, 4],
                        "the newest bar with all its levels: none, then the one with its second level")
            var halfway = []
            View.addLevels(halfway, 0, [-5000, -5000, -4000])
            expectEqual(View.lastComplete(halfway), 0, "a bar with its first level alone isn't complete; the one before it is")
            View.addLevels(bars, 350, [-3000])
            expectEqual(bars[3], -35, "the other level of a bar comes: -40 and -30 are -35")
            View.addLevels(bars, 350, [-3000])
            expectEqual(bars[3], -35, "and comes again: the same")
            expectEqual([View.newestBar(1000, 300), View.newestBar(299, 300)], [7, -1], "the newest bar leaves out the lag")
            expectEqual([View.breath(0), View.breath(500), View.breath(1000)].map(function(v) { return Math.round(v * 100) / 100 }),
                        [1, 0.35, 1], "the dot breathes once a second")
            expectEqual([View.recordingLine(42000), View.recordingLine(569000), View.recordingLine(570000), View.recordingLine(581000), View.recordingLine(599500), View.recordingLine(600000)],
                        [{text: "Press to save", amber: false}, {text: "Press to save", amber: false},
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

        // The waveform's mapping, against the fixtures of voicenote-levels.js: the
        // user's own note of 22:30 first, with the quiet room he recorded in it (the
        // room flat, the speech around it tall, the gaps between the words
        // showing), then the earlier ones: a quiet room, a busier room, and
        // quieter speech. The floor is the room's, whatever speech does to it.
        function(done) {
            function barsOf(text) {
                var bars = []
                View.addLevels(bars, 0, Fixtures.centibels(text))
                return bars
            }
            function drawn(text) {
                var bars = barsOf(text)
                return View.heights(bars, View.lastBar(bars), bars.length).reverse()
            }
            function share(list, pred) { return list.filter(pred).length / list.length }
            function at(list, q) { return View.quantile(list.slice().sort(function(a, b) { return a - b }), q) }
            function top(list) { return Math.max.apply(null, list) }
            function flat(h) { return h <= View.BAR_MIN + 3 }
            function low(h) { return h < 35 }
            function dips(list) {
                var n = 0
                for (var i = 1; i < list.length - 1; i++) {
                    if (list[i - 1] - list[i] >= 35 && list[i + 1] - list[i] >= 35)
                        n++
                }
                return n
            }
            function describe(list) {
                return "flat " + share(list, flat).toFixed(2) + ", median " + at(list, 0.5).toFixed(0) + " px, p75 " + at(list, 0.75).toFixed(0)
                       + " px, max " + top(list).toFixed(0) + " px, under 35 px " + share(list, low).toFixed(2)
            }

            // The user's note. Bars 112 to 153 are the quiet room he recorded (11.2 to
            // 15.3 s); 12 to 48 and 160 to 215 are speech (1.2 to 4.9 s and 16 to 21.6 s).
            var note = drawn(Fixtures.NOTE_2230)
            var room = note.slice(112, 154)
            var first = note.slice(12, 49), second = note.slice(160, 216)
            var talk = first.concat(second)
            test.log("     bars: the user's quiet room: " + describe(room))
            test.log("     bars: the user's speech: " + describe(talk) + ", " + (dips(first) + dips(second)) + " dips")
            check(share(room, flat) >= 0.98 && top(room) <= 12, "the quiet room the user recorded draws flat: " + describe(room))
            check(at(talk, 0.5) >= 70 && at(talk, 0.75) >= 85 && share(talk, function(h) { return h >= 80 }) >= 0.45,
                  "and his speech around it draws tall: " + describe(talk))
            check(share(talk, low) >= 0.1 && share(talk, low) <= 0.3 && dips(first) + dips(second) >= 4,
                  "with the gaps between his words showing: " + share(talk, low).toFixed(2) + " of the bars are under 35 px, and " + (dips(first) + dips(second)) + " are dips")
            var bars = barsOf(Fixtures.NOTE_2230)
            function row(ms) { return View.heights(bars, View.newestBar(ms, 300), 30).reverse() }
            check(row(15000).every(function(h) { return h <= View.BAR_MIN + 4 }), "at 15 s the screen is a flat line: " + row(15000).map(Math.round).join(" "))
            check(at(row(4000), 0.5) >= 60 && at(row(20000), 0.5) >= 60, "and tall at 4 s and at 20 s: " + at(row(4000), 0.5).toFixed(0) + " and " + at(row(20000), 0.5).toFixed(0) + " px at the median")
            var begins = row(17000)
            check(begins.slice(0, 22).every(function(h) { return h <= View.BAR_MIN + 4 }) && top(begins.slice(26)) >= 30, "at 17 s the room, then speech beginning at the right: " + begins.map(Math.round).join(" "))
            var padded = Fixtures.NOTE_2230 + "A"
            var three = barsOf(padded + padded + padded)
            var third = View.heights(three, View.lastBar(three), three.length).reverse().slice(note.length * 2).slice(160, 216)
            check(share(third, function(h) { return h >= 80 }) >= 0.9 * share(second, function(h) { return h >= 80 }),
                  "the third time through the note it is as tall: " + share(third, function(h) { return h >= 80 }).toFixed(2) + " of the speech at 80 px and more, against " + share(second, function(h) { return h >= 80 }).toFixed(2))

            // The earlier fixtures.
            var quiet = drawn(Fixtures.ROOM_QUIET), skewed = drawn(Fixtures.ROOM_QUIET_SKEWED)
            var busy = drawn(Fixtures.ROOM_BUSY), speech = drawn(Fixtures.SPEECH)
            test.log("     bars: quiet room: " + describe(quiet))
            test.log("     bars: skewed quiet room: " + describe(skewed))
            test.log("     bars: busier room: " + describe(busy))
            test.log("     bars: the mockup's speech: " + describe(speech))
            check(share(quiet, flat) >= 0.98 && top(quiet) <= 12, "a quiet room (-52 dBFS, 3 either way) draws flat: " + describe(quiet))
            check(share(skewed, flat) >= 0.98 && top(skewed) <= 15, "so does one with a heavy tail: " + describe(skewed))
            check(share(busy, flat) >= 0.4 && at(busy, 0.5) <= 15, "the busier room draws low: " + describe(busy))
            check(at(busy, 0.5) + 30 <= at(talk, 0.5), "and far lower than the user's speech: median " + at(busy, 0.5).toFixed(0) + " against " + at(talk, 0.5).toFixed(0) + " px")
            check(top(speech) >= 90 && share(speech, function(h) { return h > 35 }) >= 0.2,
                  "the mockup's speech, 5 to 8 dB under the user's, still shows, to the top: " + describe(speech))
            var three2 = barsOf(Fixtures.SPEECH + Fixtures.SPEECH + Fixtures.SPEECH)
            var last = View.heights(three2, View.lastBar(three2), three2.length).reverse().slice(speech.length * 2)
            check(share(last, function(h) { return h > 35 }) >= 0.75 * share(speech, function(h) { return h > 35 }),
                  "and speech doesn't become the floor: the third time through it shows as much (" + share(last, function(h) { return h > 35 }).toFixed(2) + " against " + share(speech, function(h) { return h > 35 }).toFixed(2) + ")")

            // The floor.
            var fixed = []
            View.addLevels(fixed, 0, Array(200).fill(-5800))
            View.addLevels(fixed, 10000, [-4600])
            check(View.heights(fixed, 100, 1)[0] >= 10 && View.barHeight(-46, -52) === View.BAR_MIN,
                  "a quieter room lowers the floor at once: -46 dBFS is " + View.heights(fixed, 100, 1)[0].toFixed(0) + " px over -58, flat over -52")
            var loud = []
            View.addLevels(loud, 0, Array(800).fill(-4700))
            var floors = View.floors(loud, 399)
            check(Math.abs(floors[99] - (View.FLOOR_START + 100 * View.FLOOR_RISE)) < 0.011,
                  "a louder room raises the floor slowly: " + floors[99].toFixed(2) + " dBFS after 10 s of -47")
            var loudest = []
            View.addLevels(loudest, 0, Array(1200).fill(-3000))
            check(top(View.floors(loudest, 599)) === View.FLOOR_TOP, "and never above " + View.FLOOR_TOP + " dBFS, in a room as loud as speech: " + top(View.floors(loudest, 599)))
            var all = barsOf(Fixtures.SPEECH)
            var head = barsOf(Fixtures.SPEECH.slice(0, 82))
            expectEqual(View.floors(head, 40), View.floors(all, 200).slice(0, 41), "a bar's floor depends on the bars before it alone")
            var late = []
            View.addLevels(late, 0, Fixtures.centibels(Fixtures.ROOM_BUSY.slice(0, 40)))
            View.addLevels(late, 4000, Fixtures.centibels(Fixtures.ROOM_BUSY.slice(80, 120)))
            View.floors(late, 59)
            View.addLevels(late, 2000, Fixtures.centibels(Fixtures.ROOM_BUSY.slice(40, 80)))
            var whole = []
            View.addLevels(whole, 0, Fixtures.centibels(Fixtures.ROOM_BUSY.slice(0, 120)))
            expectEqual(View.floors(late, 59), View.floors(whole, 59), "a late chunk of levels works the floors out again from its first bar, to what they would have been")

            // What it costs the screen's tick: one bar more each time, over a minute's worth.
            var run = []
            var heard = Fixtures.decode(Fixtures.SPEECH)
            var t0 = Date.now()
            for (var n = 0; n < 600; n++) {
                View.addLevels(run, 100 * n, [heard[(2 * n) % heard.length] * 100, heard[(2 * n + 1) % heard.length] * 100])
                View.heights(run, n, 30)
            }
            var ms = Date.now() - t0
            test.log("     the view's cost: " + ms + " ms for 600 ticks (1 minute of note), under emulation")
            check(ms < 3000, "a tick of the screen is cheap: " + (ms / 600).toFixed(1) + " ms each, under emulation")
            done()
        },

        // The waveform live, through the screen's own tick, frame by frame on a
        // clock the scene holds (voicenote-live.js). The screen shows at 0.5 s,
        // the hold's threshold. First the hold of 2026-11-04 00:10 on the watch,
        // its Levels signals at the times they came (LIVE_0010): the room, not
        // speech. Then the user's note of 22:30: its levels as they are heard,
        // one every 50 ms from the press; as ioslink sends them on the watch,
        // every 100 ms, 135 ms after they were heard; the first half second's in
        // a burst as the screen shows; the first second's held back to 1.2 s;
        // and later than the screen's lag. Each time: a bar keeps its height once
        // drawn, the row moves one bar a tick at the most and never back, and
        // without waiting on the watch's own timing; the first second isn't full
        // height; the bars are #19's, as the view draws the whole note at once.
        function(done) {
            function top(list) { return list.length === 0 ? 0 : Math.max.apply(null, list) }
            function at(list, q) { return View.quantile(list.slice().sort(function(a, b) { return a - b }), q) }
            // What a run drew: each bar as first drawn, how many changed after,
            // the row's steps and waits while there was a bar to move to, and the
            // frames that show the first second alone.
            function judge(run, lastBar) {
                var seen = Live.barsSeen(run.frames)
                var changed = 0, worst = 0
                seen.forEach(function(list) {
                    if (list === undefined)
                        return
                    list.forEach(function(h) {
                        if (h !== list[0]) {
                            changed++
                            worst = Math.max(worst, Math.abs(h - list[0]))
                        }
                    })
                })
                var during = run.frames.filter(function(f) { return f.newest < lastBar })
                var steps = Live.steps(during)
                var drawn = []
                for (var k = 0; k <= lastBar; k++)
                    drawn.push(seen[k] !== undefined ? seen[k][0] : -1)
                return {drawn: drawn, changed: changed, worst: worst,
                        bad: steps.filter(function(s) { return s < 0 || s > 1 }).length,
                        stalls: steps.filter(function(s) { return s === 0 }).length,
                        first: run.frames.filter(function(f) { return f.newest <= 9 })}
            }
            function common(name, j, stalls) {
                check(j.drawn.every(function(h) { return h >= 0 }), "live, " + name + ": every bar is drawn")
                check(j.changed === 0, "live, " + name + ": a bar keeps its height once drawn" + (j.changed === 0 ? "" : " (" + j.changed + " changes, " + j.worst.toFixed(0) + " px at the most)"))
                check(j.bad === 0 && (stalls < 0 || j.stalls === stalls),
                      "live, " + name + ": the row moves one bar a tick, never two, never back" + (stalls < 0 ? ", waiting " + j.stalls + " ticks for late levels" : ", and never waits"))
            }

            // The watch's own hold: the room at about -40 dBFS, -29 after the
            // start tick (Keep at 0.52 s).
            var replay = Live.replay(overlay, Fixtures.LIVE_0010, 500)
            replay.to(Fixtures.LIVE_0010_STOP + 1000)
            overlay.hide()
            var capture = []
            Fixtures.LIVE_0010.forEach(function(sig) { View.addLevels(capture, sig.from, sig.cb) })
            var watchLast = View.lastComplete(capture)
            var watch = judge(replay, watchLast)
            test.log("     live, the hold of 00:10 on the watch: " + replay.frames.length + " frames, " + replay.deliveries.length + " signals; the first second: "
                     + watch.drawn.slice(0, 10).map(Math.round).join(" "))
            common("the hold of 00:10 on the watch", watch, 0)
            check(top(watch.drawn.slice(0, 5)) <= 30 && top(watch.first.map(function(f) { return top(f.heights) })) < 90,
                  "live, the hold of 00:10 on the watch: nothing before 0.5 s is tall (" + top(watch.drawn.slice(0, 5)).toFixed(0)
                  + " px at the most), and the first second isn't full height: " + top(watch.first.map(function(f) { return top(f.heights) })).toFixed(0) + " px at the most")
            check(JSON.stringify(watch.drawn) === JSON.stringify(View.heights(capture, watchLast, watchLast + 1).reverse()),
                  "live, the hold of 00:10 on the watch: each bar as the view draws the whole of it at once")

            // The user's note.
            var levels = desktop.note2230
            // The last bar with both its levels: the one after it has its first
            // alone, and only the frozen screen at the release draws that.
            var lastBar = Math.floor(levels.length / 2) - 1
            var still = []
            View.addLevels(still, 0, Fixtures.centibels(Fixtures.NOTE_2230))
            var whole = View.heights(still, lastBar, lastBar + 1).reverse()
            var cases = [
                {name: "as heard, a level every 50 ms", arrival: Live.arrivals("live"), stalls: 0},
                {name: "as ioslink sends them on the watch, every 100 ms, 135 ms after", arrival: Live.arrivals("ioslink"), stalls: 0},
                {name: "the first half second's in a burst as the screen shows", arrival: Live.arrivals("live", 500), stalls: 0},
                {name: "the first second's held back to 1.2 s", arrival: Live.arrivals("ioslink", 1200), stalls: -1},
                {name: "235 ms late, past the screen's lag", arrival: Live.arrivals("ioslink", undefined, 235), stalls: -1}
            ]
            cases.forEach(function(c) {
                var run = Live.start(overlay, levels, c.arrival, 500)
                run.to(50 * levels.length + 1000)
                overlay.hide()
                var j = judge(run, lastBar)
                var talk = j.drawn.slice(12, 49).concat(j.drawn.slice(160, 216))
                test.log("     live, " + c.name + ": " + run.frames.length + " frames, " + run.deliveries.length + " signals; " + j.stalls + " ticks waited for levels")
                common(c.name, j, c.stalls)
                check(top(j.drawn.slice(0, 10)) < 90 && j.first.every(function(f) { return top(f.heights) < 90 }),
                      "live, " + c.name + ": the first second isn't full height: " + top(j.drawn.slice(0, 10)).toFixed(0) + " px at the most, the start tick, in each of the "
                      + j.first.length + " frames that show it")
                check(top(j.drawn.slice(110, 155)) <= 12, "live, " + c.name + ": the quiet room stays flat: " + top(j.drawn.slice(110, 155)).toFixed(0) + " px at the most from 11.0 to 15.5 s")
                check(top(talk) >= 99 && at(talk, 0.5) >= 70, "live, " + c.name + ": speech reaches the top: " + top(talk).toFixed(0) + " px, " + at(talk, 0.5).toFixed(0) + " px at the median")
                check(JSON.stringify(j.drawn) === JSON.stringify(whole), "live, " + c.name + ": the whole note draws as the view draws it at once")
            })
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
                screen("voicenote-recording", "Recording, 0:42", {duration: "0:42", line: "Press to save"},
                       {live: true, bars: "red"}, done)
            })
        },
        // The user's own note of 22:30, whole, as the screen shows it at five
        // moments: speech, the room beginning, the quiet room the user recorded
        // (a flat line), speech beginning again, and speech.
        function(done) {
            var moments = [
                {at: 4000, name: "speech", label: "4 s: speech", bars: "red", tall: true},
                {at: 12000, name: "room-begins", label: "12 s: speech, then the room", bars: "red", tall: true},
                {at: 15000, name: "quiet", label: "15 s: the quiet room", bars: "flatred"},
                {at: 17000, name: "speech-begins", label: "17 s: the room, then speech", bars: "red"},
                {at: 20000, name: "speech-again", label: "20 s: speech", bars: "red", tall: true}
            ]
            sheetNote.files = []
            sheetNote.labels = []
            function next(i) {
                if (i === moments.length) {
                    shot("voicenote-note2230", done, sheetNote)
                    return
                }
                var m = moments[i]
                var name = "voicenote-note-" + m.name
                desktop.program = desktop.noteOf2230
                recording("W" + i, m.at, function() {
                    desktop.program = null
                    var seconds = Math.floor(m.at / 1000)
                    expectEqual({duration: overlay.durationText, line: overlay.lineText},
                                {duration: "0:" + (seconds < 10 ? "0" : "") + seconds, line: "Press to save"}, name + ": the screen's words")
                    shot(name, function() {
                        look(name, {live: true, bars: m.bars, tall: m.tall})
                        sheetNote.files = sheetNote.files.concat([shots + "/" + name + ".png"])
                        sheetNote.labels = sheetNote.labels.concat([m.label])
                        next(i + 1)
                    }, overlay)
                }, 0)
            }
            next(0)
        },
        function(done) {
            recording("N2", 581000, function() {
                screen("voicenote-last30", "The last 30 s: \"19 s left\"", {duration: "9:41", line: "19 s left"},
                       {live: true, bars: "red", amber: true}, done)
            })
        },
        function(done) {
            recording("N3", 42000, function() {
                overlay.stopPressed(42000)
                after(300, function() {
                    screen("voicenote-saving", "Stopped, before the outcome", {duration: "0:42", line: "Saving…"},
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
                    screen("voicenote-too-short", "Stopped within 1 s: too short", {duration: "0:00", line: "Too short"},
                           {bars: "flat", dim: true}, done)
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
                waitFor(function() { return voicenotes.calls.length >= 2 && mce.calls.length >= 4 }, 3000, "ioslink and mce have their calls", function() {
                    expectEqual(stripped(desktop.trace), [startCall, "mce req_cpu_keepalive_period " + session + "-period", "ioslink Arm <time>",
                                                          "mce req_tklock_mode_change unlocked", "ioslink Keep NOTE", "mce req_display_blanking_pause"],
                                "the keepalive first, then Arm; at 0.5 s the unlock, as the display is on, and Keep; the pause once mce says unlocked; no wake")
                    expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Keep NOTE"], "ioslink heard Arm, then Keep")
                    expectEqual(voicenotes.calls[0], "Arm " + stamp, "Arm has the press' own boot-time stamp")
                    expectEqual(mce.calls, ["req_cpu_keepalive_start " + session, "req_cpu_keepalive_period " + session + "-period",
                                            "req_tklock_mode_change unlocked", "req_display_blanking_pause"],
                                "and mce heard its calls")
                    expectEqual(mce.events, ["unlocked", "pause held"], "mce unlocked, and held the pause")
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
                                    // The release alone: the note is latched, and goes on.
                                    release(test.bootMs())
                                    after(700, function() {
                                    expectEqual({phase: overlay.phase, recording: hold.recording, captured: button.captured, calls: stripped(voicenotes.calls)},
                                                {phase: "live", recording: true, captured: true, calls: ["Arm <time>", "Keep NOTE"]},
                                                "the release sends no Stop: the note goes on recording, and the button is captured")
                                    check(/^0:0[12]$/.test(overlay.durationText) || /^0:0[3-9]$/.test(overlay.durationText), "and the duration still runs: " + overlay.durationText)
                                    press(test.bootMs())
                                    release(test.bootMs())
                                    waitFor(function() { return overlay.phase === "ended" }, 5000, "the next press ends the note", function() {
                                        var endedAt = Date.now()
                                        check(/^0:0[1-3]$/.test(overlay.durationText), "the duration stands at the note's own: " + overlay.durationText)
                                        expectEqual(overlay.lineText, "Saved · sending", "saved, the iPhone in reach")
                                        waitFor(function() { return voicenotes.calls.length >= 3 }, 3000, "ioslink has Stop", function() {
                                            expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Keep NOTE", "Stop NOTE <time>"], "Stop came with the press")
                                            check(hold.keepaliveHeld && hold.blankingPaused && hold.screenKept && mce.tklock === "unlocked" && mce.paused,
                                                  "mce's keepalive and blanking pause, and the touch lock unlocked, are held while the screen shows")
                                            settled(function() {
                                                var shown = Date.now() - endedAt
                                                check(shown >= 2100 && shown < 3600, "2 s of \"Saved\" and 250 ms of fade, and the leases go with it: " + shown + " ms")
                                                waitFor(function() { return mce.calls.length >= 7 }, 3000, "mce has its last calls", function() {
                                                    expectEqual(mce.calls.slice(4), ["req_cpu_keepalive_stop " + session, "req_display_cancel_blanking_pause",
                                                                                     "req_tklock_mode_change locked-delay"],
                                                                "the keepalive ends, then the blanking pause, then the face is locked again")
                                                    expectEqual(stripped(desktop.trace).slice(6), ["ioslink Stop NOTE <time>", stopCall, "mce req_display_cancel_blanking_pause",
                                                                                                   "mce req_tklock_mode_change locked-delay"],
                                                                "after the screen: Stop was sent first, and the leases end last, then the lock")
                                                    check(mce.tklock === "locked", "mce has the touch lock locked again: " + mce.tklock)
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
                            })
                        }
                        sample()
                    })
                })
            })
        },

        // ---- the screen kept on: mce's touch lock and the blanking pause ----
        //
        // The face is mce's lockscreen. mce blanks a locked display 10 s after it
        // came on, allows a pause only with the display on and the touch lock
        // off, and refuses to unlock while the display is off: the stand-in plays
        // those rules, with its 10 s as 1.5 s. First the stand-in itself.
        function(done) {
            reset()
            mce.reset("off", "locked")
            var heard = []
            mceSignals.heard = heard
            mceRequest.call("req_tklock_mode_change", "unlocked")
            mceRequest.call("req_display_blanking_pause", undefined)
            after(300, function() {
                expectEqual({events: mce.events, tklock: mce.tklock, heard: heard}, {events: ["unlock denied: display off", "pause ignored"], tklock: "locked", heard: ["tklock locked"]},
                            "the stand-in for mce refuses to unlock with the display off, says it is still locked, and ignores a pause")
                mce.clear()
                mceRequest.call("req_display_state_on", undefined)
                waitFor(function() { return mce.display === "on" }, 3000, "it turns the display on", function() {
                    mceRequest.call("req_tklock_mode_change", "unlocked")
                    after(300, function() {
                        mceRequest.call("req_display_blanking_pause", undefined)
                        after(300, function() {
                            expectEqual({events: mce.events, tklock: mce.tklock, paused: mce.paused}, {events: ["the display is on", "unlocked", "pause held"], tklock: "unlocked", paused: true},
                                        "and with it on, unlocks and holds the pause")
                            expectEqual(heard.slice(1), ["allowed true", "tklock unlocked"], "saying so: the pause allowed, then the touch lock unlocked")
                            mceRequest.call("req_tklock_mode_change", "locked")
                            after(300, function() {
                                check(!mce.paused && mce.events[mce.events.length - 1] === "pause dropped", "locked again, it drops the pause: " + mce.events.join(", "))
                                mceSignals.heard = null
                                desktop.scene({})
                                done()
                            })
                        })
                    })
                })
            })
        },

        // From the screen off, as the user's note of 23:57 was: at 0.5 s the
        // display is woken, and the unlock waits for it; then the pause. The
        // display stays on past mce's lockscreen blank, for the whole note.
        function(done) {
            desktop.scene({displayOn: false})
            keptScreen("from the screen off", 3500, function(order) {
                expectEqual(order, ["mce req_display_state_on", "the display is on", "mce req_tklock_mode_change unlocked", "unlocked", "mce req_display_blanking_pause", "pause held"],
                            "from the screen off: the wake, the display on, only then the unlock, then the pause")
                done()
            })
        },

        // From the screen on, on the face: the unlock at 0.5 s, then the pause.
        function(done) {
            desktop.scene({})
            keptScreen("from the screen on", 2500, function(order) {
                expectEqual(order, ["mce req_tklock_mode_change unlocked", "unlocked", "mce req_display_blanking_pause", "pause held"],
                            "from the screen on: the unlock at 0.5 s, then the pause; no wake")
                done()
            })
        },

        // Locked again mid-note, by anything: the unlock again at once, and the
        // pause again.
        function(done) {
            desktop.scene({})
            mce.lockBlankMs = 1500
            reset()
            var stamp = test.bootMs()
            feeder.run(stamp)
            press(stamp)
            waitFor(function() { return mce.paused }, 5000, "the note holds the pause", function() {
                mce.clear()
                mceRequest.call("req_tklock_mode_change", "locked")
                waitFor(function() { return mce.log.indexOf("pause held") !== -1 }, 3000, "locked mid-note: unlocked again, the pause held again", function() {
                    var t = mce.times
                    check(t[t.length - 1] - t[0] < 800, "at once, not at the next retry: " + (t[t.length - 1] - t[0]) + " ms")
                    expectEqual(mce.log, ["mce req_tklock_mode_change locked", "locked", "pause dropped", "mce req_tklock_mode_change unlocked", "unlocked",
                                          "mce req_display_blanking_pause", "pause held"],
                                "mce had the lock and dropped the pause, then the hold's unlock, then its pause")
                    after(1800, function() {
                        check(mce.display === "on", "and the display stays on, past the lockscreen's blank: " + mce.display)
                        stopPress()
                        settled(function() {
                            feeder.stop()
                            mce.lockBlankMs = 0
                            check(mce.tklock === "locked", "locked again after the note")
                            done()
                        })
                    })
                })
            })
        },

        // An unlock mce refuses, though the display looked on: asked again every
        // unlockRetryMs until mce takes it.
        function(done) {
            desktop.scene({})
            mce.reset("off", "locked")
            hold.unlockRetryMs = 300
            reset()
            var stamp = test.bootMs()
            feeder.run(stamp)
            press(stamp)
            function unlocks() { return mce.calls.filter(function(c) { return c === "req_tklock_mode_change unlocked" }).length }
            waitFor(function() { return unlocks() >= 3 }, 5000, "the unlock refused is asked again", function() {
                check(mce.events.every(function(e) { return e === "unlock denied: display off" }) && !mce.paused,
                      "mce refused each, with its display off: " + mce.events.join(", "))
                mceRequest.call("req_display_state_on", undefined)
                waitFor(function() { return mce.paused }, 3000, "mce's display on: the next try unlocks, and the pause is held", function() {
                    var log = mce.log
                    check(log.indexOf("unlocked") > log.indexOf("mce req_display_state_on"),
                          "after the display began to come on, which mce takes: " + mce.events.join(", "))
                    var n = unlocks()
                    after(1000, function() {
                        expectEqual(unlocks(), n, "and no more unlocks once unlocked")
                        stopPress()
                        settled(function() {
                            feeder.stop()
                            hold.unlockRetryMs = 1000
                            done()
                        })
                    })
                })
            })
        },

        // The renewal: the touch lock asked about, and the pause renewed, every
        // blankingRenewMs, and none of it once the screen is away.
        function(done) {
            desktop.scene({})
            hold.blankingRenewMs = 400
            reset()
            var stamp = test.bootMs()
            feeder.run(stamp)
            press(stamp)
            function pauses() { return mce.calls.filter(function(c) { return c === "req_display_blanking_pause" }).length }
            function asks() { return mce.calls.filter(function(c) { return c === "get_tklock_mode" }).length }
            waitFor(function() { return pauses() >= 3 && asks() >= 2 }, 5000, "the pause is renewed, and the touch lock asked about", function() {
                stopPress()
                settled(function() {
                    feeder.stop()
                    waitFor(function() { return mce.calls.indexOf("req_tklock_mode_change locked-delay") !== -1 }, 3000, "mce has the lock", function() {
                        var n = mce.calls.length
                        after(1000, function() {
                            expectEqual(mce.calls.length, n, "and nothing more once the screen is away")
                            hold.blankingRenewMs = 20000
                            done()
                        })
                    })
                })
            })
        },

        // The panels moving meanwhile: compositor.qml leaves the lockscreen alone
        // while a note keeps the screen, and the hold locks it again after, the
        // face being in front. Moved off the face, it stays unlocked after, as
        // the compositor has it off the face.
        function(done) {
            desktop.scene({})
            reset()
            var stamp = test.bootMs()
            feeder.run(stamp)
            press(stamp)
            waitFor(function() { return mce.paused }, 5000, "the note holds the pause", function() {
                desktop.panelX = 1
                desktop.panelX = 0
                expectEqual(desktop.locks, [], "the face left and come back to, meanwhile: the lockscreen isn't touched")
                stopPress()
                settled(function() {
                    relocked("the face in front")
                    reset()
                    press(test.bootMs())
                    waitFor(function() { return mce.paused }, 5000, "another note holds the pause", function() {
                        desktop.panelY = 1
                        stopPress()
                        settled(function() {
                            feeder.stop()
                            check(mce.tklock === "unlocked" && desktop.trace.indexOf("mce req_tklock_mode_change locked-delay") === -1,
                                  "moved to the app list meanwhile: left unlocked after, as off the face")
                            expectEqual(desktop.locks, [], "and the lockscreen untouched")
                            desktop.scene({})
                            done()
                        })
                    })
                })
            })
        },

        // A launcher that dies leaves no pause (mce drops a client's when it
        // leaves the bus), and its next start locks the screen again.
        function(done) {
            var start = sh("grep -c 'LipstickSettings.lockScreen(true)' /src/src/qml/MainScreen.qml").output.trim()
            expectEqual(start, "1", "MainScreen.qml locks the screen when the launcher starts")
            done()
        },

        // A click holds neither the screen nor the touch lock.
        function(done) {
            desktop.scene({})
            reset()
            var stamp = test.bootMs()
            press(stamp)
            after(90, function() {
                release(test.bootMs())
                after(900, function() {
                    expectEqual({tklock: mce.calls.filter(function(c) { return c.indexOf("tklock") !== -1 }), kept: hold.screenKept, locks: desktop.locks},
                                {tklock: [], kept: false, locks: []}, "a click leaves the touch lock alone")
                    done()
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
                    check(!hold.blankingPaused && !hold.keepaliveHeld && !hold.screenKept && overlay.phase === "idle", "nothing is held")
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
                var refusedAt = Date.now()
                after(400, function() {
                    // The button is still down, and is never released: it fades by itself.
                    check(!hold.recording, "a refusal is no recording")
                    settled(function() {
                        var shown = Date.now() - refusedAt
                        check(shown >= 2400 && shown < 4500, "a refusal shows 2.5 s, then fades by itself, the button still down: " + shown + " ms")
                        release(test.bootMs())
                        expectEqual(stripped(desktop.trace), [startCall, "ioslink Arm <time>", "mce req_tklock_mode_change unlocked", "mce req_display_blanking_pause", stopCall,
                                                              "mce req_display_cancel_blanking_pause", "mce req_tklock_mode_change locked-delay"],
                                    "no Keep, no Stop and no Cancel for no note; the screen kept on, the leases ended with it, and the face locked again")
                        check(mce.tklock === "locked", "a refusal: locked again after")
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
            // The release, then the press that stops it before Arm's answer
            // (at 1.3 s). One timer serves after() and waitFor(): they nest.
            after(900, function() {
                release(test.bootMs())
                after(200, function() {
                    press(test.bootMs())
                    release(test.bootMs())
                    waitFor(function() { return voicenotes.calls.length >= 3 }, 5000, "ioslink has Keep and Stop, after Arm's answer", function() {
                        expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Keep NOTE", "Stop NOTE <time>"],
                                    "a stop press before Arm's answer: Keep, then Stop, when it comes")
                        expectEqual(stripped(desktop.trace).slice(0, 6), [startCall, "ioslink Arm <time>", "mce req_tklock_mode_change unlocked", "mce req_display_blanking_pause",
                                                                           "ioslink Keep NOTE", "ioslink Stop NOTE <time>"],
                                    "in the order it sent them: the screen kept on at 0.5 s, Keep and Stop with Arm's answer")
                        waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                            expectEqual(overlay.lineText, "Saved · sending", "saved: the note lasted 1.1 s")
                            voicenotes.armDelay = 0
                            overlay.farewellMs = 600
                            overlay.fadeMs = 100
                            settled(done)
                        })
                    })
                })
            })
        },

        // The display off: mce turns it on at 0.5 s.
        function(done) {
            desktop.scene({displayOn: false})
            reset()
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" && mce.paused }, 5000, "the screen shows, and mce holds the pause", function() {
                after(300, function() {
                    stopPress()
                    settled(function() {
                        expectEqual(stripped(desktop.trace), [startCall, "ioslink Arm <time>", "mce req_display_state_on", "ioslink Keep NOTE",
                                                              "mce req_tklock_mode_change unlocked", "mce req_display_blanking_pause",
                                                              "ioslink Stop NOTE <time>", stopCall, "mce req_display_cancel_blanking_pause",
                                                              "mce req_tklock_mode_change locked-delay"],
                                    "with the display off: the screen, mce's wake and Keep; the unlock once the display is on, then the pause; the lock after")
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
                    stopPress()
                    waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                        expectEqual(overlay.lineText, "Saved · 08:02 dropped", "the drop, in amber: " + overlay.lineAmber)
                        settled(function() {
                            var log = desktop.phaseLog
                            var shown = log[log.length - 1].at - log[log.length - 2].at
                            check(shown >= 2600 && shown < 4200, "a drop shows 2.5 s, and the fade is 250 ms more: " + shown + " ms")
                            relocked("a drop")
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
                            relocked("ioslink gone")
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

        // The 10:00 limit, the note latched: ioslink's own stop, at any hour.
        function(done) {
            reset()
            desktop.phaseLog = []
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                after(300, function() {
                    release(test.bootMs())
                    voicenotes.limit()
                    waitFor(function() { return overlay.phase === "ended" }, 5000, "ioslink stops the note itself", function() {
                        expectEqual({duration: overlay.durationText, line: overlay.lineText}, {duration: "10:00", line: "10 min limit · saved"}, "the limit")
                        settled(function() {
                            check(true, "the leases end with the screen")
                            relocked("the 10:00 limit")
                            expectEqual({recording: hold.recording, captured: button.captured}, {recording: false, captured: false}, "and the button is free again")
                            press(test.bootMs())
                            release(test.bootMs())
                            after(600, function() {
                                expectEqual(stripped(voicenotes.calls).slice(0, 2), ["Arm <time>", "Keep NOTE"], "the note's own calls")
                                check(stripped(voicenotes.calls).indexOf("Stop NOTE <time>") === -1, "no Stop for a note that ended itself")
                                expectEqual(voicenotes.errors, [], "and no error")
                                done()
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
                    stopPress()
                    var at = Date.now()
                    waitFor(function() { return overlay.phase === "saving" }, 3000, "the release freezes the screen", function() {
                        expectEqual(overlay.lineText, "Saving…", "the line, until ioslink says")
                        settled(function() {
                            var wait = Date.now() - at
                            check(wait >= 600 && wait < 3000, "no word in 0.7 s: the screen goes with no claim, after " + wait + " ms")
                            relocked("no word from ioslink")
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
                        expectEqual(stripped(desktop.trace), [startCall, "ioslink Arm <time>", "mce req_tklock_mode_change unlocked", "mce req_display_blanking_pause",
                                                              stopCall, "mce req_display_cancel_blanking_pause", "mce req_tklock_mode_change locked-delay"],
                                    "no Keep and no Stop for a note that never was; the hard limit locks the face again too")
                        voicenotes.answer = "id"
                        hold.capMs = 635000
                        done()
                    })
                })
            })
        },

        // A press while the "Saved" screen shows is ignored (decision 4): no new
        // note, no click, no flashlight; and once it has faded, a press is an
        // ordinary one again.
        function(done) {
            overlay.farewellMs = 2000
            overlay.fadeMs = 250
            reset()
            desktop.phaseLog = []
            press(test.bootMs())
            waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                stopPress()
                waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                    check(hold.keepaliveHeld, "the first screen holds the leases")
                    var calls = stripped(voicenotes.calls).length
                    press(test.bootMs())
                    after(90, function() {
                        release(test.bootMs())
                        after(700, function() {
                            expectEqual({phase: overlay.phase, calls: stripped(voicenotes.calls).length, opened: desktop.opened},
                                        {phase: "ended", calls: calls, opened: []}, "the press on the Saved screen did nothing: no Arm, no cut, no app")
                            check(hold.keepaliveHeld, "and the leases are held still")
                            settled(function() {
                                expectEqual(desktop.phaseLog.map(function(p) { return p.phase }), ["armed", "live", "saving", "ended", "idle"],
                                            "the phases: the first note's alone")
                                expectEqual(stripped(desktop.trace).filter(function(c) { return c === startCall || c === stopCall }), [startCall, stopCall],
                                            "one keepalive, ended once")
                                after(450, function() {
                                    desktop.phaseLog = []
                                    reset()
                                    press(test.bootMs())
                                    after(90, function() {
                                        release(test.bootMs())
                                        waitFor(function() { return voicenotes.calls.length >= 2 }, 3000, "a press once it has faded is a click again", function() {
                                            expectEqual(stripped(voicenotes.calls), ["Arm <time>", "Cancel NOTE"], "Arm, then Cancel")
                                            overlay.farewellMs = 600
                                            overlay.fadeMs = 100
                                            settled(done)
                                        })
                                    })
                                })
                            })
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
                    stopPress()
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
        // only the rings' view is read, by the single press. Ambient is lipstick's
        // own: it tells displayOff for mce's off state, which is the ambient
        // display when ambient is enabled, so displayOn is false and ambient true.
        function(done) {
            var faces = [
                {face: "the music face's cover", state: {}},
                {face: "the rings face, timers running", state: {ringsView: "timers"}},
                {face: "the rings face, stopwatches running", state: {ringsView: "stopwatches"}},
                {face: "the door glyph", state: {}},
                {face: "the plain digital face", state: {}}
            ]
            var displays = [
                {display: "on", state: {}, lit: true},
                {display: "ambient", state: {displayOn: false, ambient: true}, lit: false},
                {display: "off", state: {displayOn: false}, lit: false}
            ]
            var cases = []
            displays.forEach(function(d) {
                faces.forEach(function(f) {
                    var state = {}
                    Object.keys(f.state).forEach(function(k) { state[k] = f.state[k] })
                    Object.keys(d.state).forEach(function(k) { state[k] = d.state[k] })
                    cases.push({label: "on " + f.face + ", the display " + d.display, state: state, lit: d.lit})
                })
            })
            // The compositor can also have ambient while displayOn is true.
            cases.push({label: "on the plain digital face, ambient with displayOn true", state: {ambient: true}, lit: false})
            function next(i) {
                if (i === cases.length) {
                    desktop.scene({})
                    done()
                    return
                }
                var c = cases[i]
                desktop.scene(c.state)
                desktop.opened = []
                reset()
                press(test.bootMs())
                waitFor(function() { return overlay.phase === "live" }, 5000, "a hold records " + c.label, function() {
                    after(300, function() {
                        stopPress()
                        waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                            expectEqual({calls: stripped(voicenotes.calls), opened: desktop.opened},
                                        {calls: ["Arm <time>", "Keep NOTE", "Stop NOTE <time>"], opened: []},
                                        c.label + ": Arm, Keep, Stop, and no app")
                            expectEqual(mce.calls.indexOf("req_display_state_on") !== -1, !c.lit,
                                        c.label + (c.lit ? ": mce isn't asked to turn the display on" : ": mce turns the display on"))
                            settled(function() {
                                relocked(c.label + ", a slip of 0.8 s")
                                after(450, function() { next(i + 1) })
                            })
                        })
                    })
                })
            }
            next(0)
        },

        // With the display off a hold records wherever the watch was: an app in
        // front, the app list, the quick panel, Today, the notifications. The
        // user can't see it, so they expect a note. The screen comes up over what
        // is there, and the hold navigates nothing (its only calls are mce's and
        // ioslink's), so that what was in front is in front when the screen is gone.
        function(done) {
            var cases = [
                {where: "an app in front", state: {displayOn: false, homeActive: false}},
                {where: "an app in front, the panels left on the app list", state: {displayOn: false, homeActive: false, panelY: 1}},
                {where: "the app list", state: {displayOn: false, panelY: 1}},
                {where: "the quick panel", state: {displayOn: false, panelY: -1}},
                {where: "Today", state: {displayOn: false, panelX: 1}},
                {where: "the notifications", state: {displayOn: false, panelX: -1}}
            ]
            function next(i) {
                if (i === cases.length) {
                    desktop.scene({})
                    done()
                    return
                }
                var c = cases[i]
                desktop.scene(c.state)
                desktop.opened = []
                var before = {home: desktop.homeActive, x: desktop.panelX, y: desktop.panelY}
                reset()
                press(test.bootMs())
                waitFor(function() { return overlay.phase === "live" }, 5000, "with the display off, a hold records on " + c.where, function() {
                    check(overlay.shown, "the screen is up, over " + c.where)
                    after(300, function() {
                        stopPress()
                        waitFor(function() { return overlay.phase === "ended" }, 5000, "the note ends", function() {
                            expectEqual({calls: stripped(voicenotes.calls), opened: desktop.opened},
                                        {calls: ["Arm <time>", "Keep NOTE", "Stop NOTE <time>"], opened: []},
                                        "with the display off, on " + c.where + ": Arm, Keep, Stop, and no app")
                            check(mce.calls.indexOf("req_display_state_on") !== -1, "mce turns the display on")
                            settled(function() {
                                expectEqual({home: desktop.homeActive, x: desktop.panelX, y: desktop.panelY}, before,
                                            "and " + c.where + " is where it was, when the screen has gone")
                                check(mce.tklock === "unlocked" && desktop.trace.indexOf("mce req_tklock_mode_change locked-delay") === -1,
                                      "and, off the face, the touch lock is left unlocked: " + mce.tklock)
                                after(450, function() { next(i + 1) })
                            })
                        })
                    })
                })
            }
            next(0)
        },

        // With the display on, or ambient, never in an app nor on another panel:
        // a hold does nothing at all, and calls nothing.
        function(done) {
            var cases = [
                {where: "an app in front, the display on", state: {homeActive: false}},
                {where: "an app in front, ambient", state: {homeActive: false, displayOn: false, ambient: true}},
                {where: "an app in front, ambient with displayOn true", state: {homeActive: false, ambient: true}},
                {where: "the app list, the display on", state: {panelY: 1}},
                {where: "the app list, ambient", state: {panelY: 1, displayOn: false, ambient: true}},
                {where: "Today, the display on", state: {panelX: 1}},
                {where: "the quick panel, the display on", state: {panelY: -1}},
                {where: "the notifications, the display on", state: {panelX: -1}}
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
