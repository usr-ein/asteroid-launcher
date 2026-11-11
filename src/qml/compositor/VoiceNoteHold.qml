/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * A long press of the bottom button, as a voice note (the main repo's
 * docs/prd/voice_notes.md § 8.2): what compositor.qml does at each step of
 * ButtonDoubleClick's hold, and at the press that stops the note. Like Flashlight.qml, it is a piece of the
 * compositor that the tests run with stand-ins: mce and ioslink are functions
 * it is given.
 *
 * - start(pressedAt), at the press, where voicebutton.js allows a note:
 *   mce's CPU keepalive first, as the watch may suspend within 150 ms of the
 *   press, then ioslink's Arm(pressedAt), without waiting for its answer.
 *   With no ioslink on the bus, nothing: a hold does nothing.
 * - confirm(), 0.5 s into the hold: the recording screen shows at once, the
 *   display comes on if it wasn't, the screen is kept on (below), and Keep(id)
 *   tells ioslink that the note is real.
 * - end(releasedAt, confirmed), at the release: Cancel(id) for a click. For a
 *   note nothing: it is latched, and goes on recording (`recording`).
 * - stop(pressedAt), at the next press of the bottom button, which
 *   ButtonDoubleClick gives as capturedPressed while `recording` or the screen
 *   is up: Stop(id, pressedAt), at that press, and that press means nothing
 *   else.
 * Arm's answer comes when it comes, and holds the id, which Keep, Stop and
 * Cancel need: they wait for it, in that order. An answer of "" is a refusal
 * (State says why: no microphone, no room), which the screen shows; an error
 * (ioslink busy, or without VoiceNotes) shows nothing.
 *
 * What it holds, it holds as leases that end by themselves: mce's keepalive
 * and its blanking pause, which it renews for as long as the hold or the note
 * lasts, and lets go when the screen has finished, 2 s after the note ended.
 * A hard limit ends them too, if nothing else does. mce drops a client's
 * keepalive and pause when the client leaves the bus, so that a launcher that
 * crashes or is killed leaves neither behind.
 *
 * The screen stays on for the whole note, from confirm() until the screen is
 * away (`screenKept`), and that takes the touch lock as well as the pause. The
 * watch face is mce's lockscreen: mce blanks a locked display 10 s after it
 * came on, and allows a blanking pause only with the display on and the touch
 * lock off; a pause asked otherwise is ignored, and a pause held is dropped as
 * soon as it stops being allowed (mce's display.c). And mce refuses to unlock
 * unless the display is on or going on ("tkunlock denied due to display=OFF",
 * its tklock.c): an unlock asked with the display off, at the press of a hold
 * that woke the watch, does nothing. So, while the screen is kept:
 *  - once the display is on (displayLit), the touch lock is asked to unlock,
 *    never before, whatever mce said of it before the note;
 *  - mce's touch lock mode is followed (its tklock_mode_ind, which mce sends
 *    after every request too, and get_tklock_mode at every renewal), and until
 *    it says unlocked the unlock is asked again every unlockRetryMs, and at
 *    every renewal; locked again mid-note, it is asked again at once;
 *  - the pause is asked once the touch lock is unlocked, or mce says a pause is
 *    allowed (display_blanking_pause_allowed_ind), and renewed every
 *    blankingRenewMs, well inside mce's 60 s;
 *  - at the end, after the leases, the touch lock is locked again if the note
 *    asked to unlock it and the face is in front (lockWanted): the save, a slip
 *    too short to keep, the 10:00 limit, a refusal, ioslink gone and the hard
 *    limit all end there. compositor.qml leaves the lockscreen alone meanwhile.
 * mce drops a client's pause when the client leaves the bus, so a launcher that
 * crashes or is killed leaves no pause behind, and its next start locks the
 * screen again (MainScreen.qml's LipstickSettings.lockScreen).
 */
import QtQuick 2.15
import Nemo.DBus 2.0

Item {
    id: hold

    // VoiceNoteOverlay.qml's item.
    property Item overlay: null
    // Whether ioslink is on the session bus.
    property bool ioslinkUp: false
    // Whether the display is fully on: neither off nor ambient.
    property bool displayLit: true
    // Whether the face is in front, the lockscreen: compositor.qml's
    // longTimeout. The touch lock is locked again after a note only then.
    property bool lockWanted: true
    // function(method, args, callback): a call to mce's request interface;
    // args a string, or undefined; callback optional, given the answer.
    property var callMce
    // function(method, typedArgs, callback, errback): a call to ioslink's
    // VoiceNotes, with Nemo.DBus' typed arguments; the callbacks optional.
    property var callIoslink

    // mce ends a keepalive that isn't renewed within 75 s, and a blanking
    // pause within 60 s. The keepalive is renewed at half of mce's own period,
    // once it says; the pause three times a minute.
    property int keepaliveRenewMs: 30000
    property int blankingRenewMs: 20000
    // While the display is on and the touch lock still locked, the unlock is
    // asked again this often.
    property int unlockRetryMs: 1000
    // The longest the leases are held, whatever happens: a note is at most
    // 10:00, and ioslink says so within its margin.
    property int capMs: 635000

    readonly property string session: "sonic-launcher-voicenote"

    // The latest hold: {pressedAt, id, replied, refused, failed, confirmed,
    // ended, stopped, stoppedAt, kept, sent, over}. Arm's answer comes to its own.
    property var current: null
    // Whether a press that start() took is still down.
    property bool holding: false
    // Whether a note is latched and records: from confirm() until the press that
    // stops it, or until the note is over some other way (a refusal, a failure,
    // ioslink gone, the 10:00 limit, the hard limit), which the screen's phase
    // says. compositor.qml captures the button's presses while it is true, and
    // while the screen is up.
    property bool recording: false
    property bool keepaliveHeld: false
    property bool blankingPaused: false
    property bool periodAsked: false
    // Whether the note keeps the screen on: from confirm() until the screen is
    // away. compositor.qml leaves the lockscreen alone while it is true.
    property bool screenKept: false
    // mce's touch lock, as its tklock_mode_ind and get_tklock_mode say:
    // locked until it says otherwise, as the face is. And whether a blanking
    // pause is allowed, as its display_blanking_pause_allowed_ind says.
    property bool tklockLocked: true
    property bool pauseAllowed: false
    // Whether the pause was asked while mce allowed it, so that mce holds it:
    // it is asked again once mce has dropped it, and at each renewal.
    property bool pauseHeld: false
    // Whether this note asked the touch lock to unlock: it locks it again. And
    // whether mce has said since that it is unlocked: until it has, what the
    // hold believed before isn't trusted, and the unlock is asked anyway.
    property bool unlockAsked: false
    property bool unlockSeen: false

    visible: false

    function start(pressedAt) {
        if (!ioslinkUp || overlay === null)
            return
        var h = {pressedAt: pressedAt, id: "", replied: false, refused: false, failed: false,
                 confirmed: false, ended: false, stopped: false, stoppedAt: 0, kept: false, sent: false, over: false,
                 refusalShown: false}
        current = h
        holding = true
        lease()
        overlay.arm()
        callIoslink("Arm", [{type: "x", value: pressedAt}],
                    function(id) { armed(h, id) },
                    function(name, message) { armFailed(h, name, message) })
    }

    function confirm() {
        var h = current
        if (!holding || h === null || h.confirmed || h.over)
            return
        h.confirmed = true
        if (h.failed || !ioslinkUp) {
            // Nothing records, and nothing to say.
            over(h)
            return
        }
        screenKept = true
        if (h.replied && h.refused) {
            h.refusalShown = true
            overlay.refused()
        } else {
            overlay.show()
        }
        // The display first, if it was off: the unlock waits for it.
        if (!displayLit)
            callMce("req_display_state_on", undefined)
        keepScreen()
        recording = overlay.phase === "live"
        advance(h)
    }

    // The screen kept on, with the display on: the touch lock asked to unlock
    // until mce says it is unlocked, and while it says it is locked; else the
    // pause. See the header.
    function keepScreen() {
        if (!screenKept || !displayLit)
            return
        if (tklockLocked || !unlockSeen) {
            unlockAsked = true
            callMce("req_tklock_mode_change", "unlocked")
        } else if (!pauseHeld) {
            pause()
        }
    }

    function pause() {
        if (!screenKept || !displayLit)
            return
        blankingPaused = true
        pauseHeld = pauseAllowed
        callMce("req_display_blanking_pause", undefined)
    }

    // What mce says of its touch lock, in its signal, which it sends after every
    // request too, or in get_tklock_mode's answer: "locked" (also "locked-dim"
    // and "locked-delay") or "unlocked". Unlocked: the pause. Locked again
    // mid-note: the unlock again, at once. Still locked, an unlock refused: the
    // retry asks again, not this, which would ask as fast as mce answers.
    function tklockMode(mode) {
        if (typeof mode !== "string" || mode === "")
            return
        var was = tklockLocked
        tklockLocked = mode !== "unlocked"
        if (!screenKept)
            return
        if (!tklockLocked) {
            unlockSeen = true
            keepScreen()
        } else if (!was) {
            keepScreen()
        }
    }

    // The press is up. A note goes on recording; a click is Cancelled.
    function end(releasedAt, confirmed) {
        var h = current
        if (!holding || h === null)
            return
        holding = false
        if (h.confirmed)
            return
        h.ended = true
        advance(h)
    }

    // The press that stops the note, at its own boot-time stamp. Nothing if no
    // note records: a refusal, a failure or the screen of an ended note.
    function stop(pressedAt) {
        var h = current
        if (!recording || h === null || !h.confirmed || h.stopped || h.over || h.refused || h.failed)
            return
        recording = false
        h.stopped = true
        h.stoppedAt = pressedAt
        overlay.stopPressed(Math.max(0, pressedAt - h.pressedAt))
        advance(h)
    }

    // Arm's answer: the note's id, or "" for a refusal.
    function armed(h, id) {
        h.replied = true
        h.id = id === undefined || id === null ? "" : String(id)
        h.refused = h.id === ""
        if (!h.refused && h === current)
            overlay.begin(h.id)
        advance(h)
    }

    function armFailed(h, name, message) {
        console.log("voicenote: Arm failed: " + name + ": " + message)
        h.replied = true
        h.failed = true
        advance(h)
    }

    // Whatever Arm's answer lets a hold do now, in order: Keep, then Stop or
    // Cancel; and the end of what only a click holds.
    function advance(h) {
        if (h.replied && h.id !== "") {
            if (h.confirmed && !h.kept) {
                h.kept = true
                fire("Keep", [{type: "s", value: h.id}])
            }
            if ((h.stopped || h.ended) && !h.sent) {
                h.sent = true
                if (h.stopped)
                    fire("Stop", [{type: "s", value: h.id}, {type: "x", value: h.stoppedAt}])
                else
                    fire("Cancel", [{type: "s", value: h.id}])
            }
        }
        if (h !== current || h.over)
            return
        if (h.replied && h.confirmed && h.refused && !h.refusalShown) {
            // The answer came after the screen did.
            h.refusalShown = true
            overlay.refused()
        }
        if (h.replied && h.confirmed && h.failed)
            over(h)
        // A click has no screen to wait for, and no answer to wait for either.
        if (h.ended && !h.confirmed)
            over(h)
    }

    // A call to ioslink that nobody waits for, but the journal hears of.
    function fire(method, args) {
        callIoslink(method, args, function() { }, function(name, message) {
            console.log("voicenote: " + method + " failed: " + name + ": " + message)
        })
    }

    // The hold's part is done: nothing more is to be shown or kept.
    function over(h) {
        h.over = true
        if (h !== current)
            return
        // A screen that was never shown has nothing to wait for; one that was
        // shown for a note that never was goes now, as nothing will stop it.
        overlay.disarm()
        if (overlay.phase === "live")
            overlay.hide()
        settle()
    }

    // The screen is away: for a note, that is the end of the hold.
    function overlayFinished() {
        if (current !== null && overlay.phase !== "armed")
            current.over = true
        settle()
    }

    // mce's keepalive, first of all, for as long as a hold or a note lasts.
    function lease() {
        capTimer.restart()
        if (keepaliveHeld)
            return
        keepaliveHeld = true
        callMce("req_cpu_keepalive_start", session)
        if (!periodAsked) {
            // Under a session of its own: a period query renews its session to
            // 2 s, which would cut this one's short.
            periodAsked = true
            callMce("req_cpu_keepalive_period", session + "-period", function(seconds) {
                if (seconds > 0)
                    hold.keepaliveRenewMs = Math.max(5000, Math.min(60000, seconds * 500))
            })
        }
    }

    // Lets go of what it holds, once no hold is under way and the screen is
    // away.
    function settle() {
        if (current !== null && !current.over)
            return
        if (overlay !== null && overlay.shown)
            return
        capTimer.stop()
        if (keepaliveHeld) {
            keepaliveHeld = false
            callMce("req_cpu_keepalive_stop", session)
        }
        if (blankingPaused) {
            blankingPaused = false
            callMce("req_display_cancel_blanking_pause", undefined)
        }
        // The touch lock last, locked again if the note unlocked it and the
        // face is in front: mce's display timeouts are the face's once more.
        // The way the compositor locks it, as lipstick's lockScreen() does.
        if (unlockAsked && lockWanted)
            callMce("req_tklock_mode_change", "locked-delay")
        unlockAsked = false
        unlockSeen = false
        pauseHeld = false
        screenKept = false
    }

    // The display came on: the unlock, or the pause, now. A pause allowed: the
    // pause, which mce now holds; not allowed: mce dropped it.
    onDisplayLitChanged: keepScreen()
    onPauseAllowedChanged: {
        if (pauseAllowed)
            pause()
        else
            pauseHeld = false
    }

    // mce's signals: its touch lock's mode, and whether a pause is allowed.
    DBusInterface {
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/signal"
        iface: "com.nokia.mce.signal"
        signalsEnabled: true
        // Connected once mce is on the bus, which it introspects.
        watchServiceStatus: true
        function tklock_mode_ind(mode) { hold.tklockMode(mode) }
        function display_blanking_pause_allowed_ind(allowed) { hold.pauseAllowed = allowed === true }
    }

    Connections {
        target: hold.overlay
        ignoreUnknownSignals: true
        function onFinished() { hold.overlayFinished() }
        // Anything but live is the end of the recording, whatever ended it.
        function onPhaseChanged() {
            if (hold.overlay.phase !== "live")
                hold.recording = false
        }
    }

    Timer {
        interval: hold.keepaliveRenewMs
        repeat: true
        running: hold.keepaliveHeld
        onTriggered: hold.callMce("req_cpu_keepalive_start", hold.session)
    }

    // The renewal: mce asked again what its touch lock is, and the unlock or
    // the pause, so that a signal missed costs one renewal at the most.
    Timer {
        interval: hold.blankingRenewMs
        repeat: true
        running: hold.screenKept
        onTriggered: {
            hold.callMce("get_tklock_mode", undefined, function(mode) { hold.tklockMode(mode) })
            hold.pauseHeld = false
            hold.keepScreen()
        }
    }

    // The unlock again, while the display is on and mce still says locked, or
    // hasn't said yet.
    Timer {
        interval: hold.unlockRetryMs
        repeat: true
        running: hold.screenKept && hold.displayLit && (hold.tklockLocked || !hold.unlockSeen)
        onTriggered: hold.keepScreen()
    }

    // The hard limit on what is held.
    Timer {
        id: capTimer
        interval: hold.capMs
        onTriggered: {
            console.log("voicenote: the hold outlived its limit of " + hold.capMs + " ms; letting go")
            if (hold.overlay !== null)
                hold.overlay.hide()
            if (hold.current !== null)
                hold.current.over = true
            hold.recording = false
            hold.settle()
        }
    }
}
