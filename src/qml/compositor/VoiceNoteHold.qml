/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * A hold of the bottom button, as a voice note (the main repo's
 * docs/prd/voice_notes.md § 8.2): what compositor.qml does at each step of
 * ButtonDoubleClick's hold. Like Flashlight.qml, it is a piece of the
 * compositor that the tests run with stand-ins: mce and ioslink are functions
 * it is given.
 *
 * - start(pressedAt), at the press, where voicebutton.js allows a note:
 *   mce's CPU keepalive first, as the watch may suspend within 150 ms of the
 *   press, then ioslink's Arm(pressedAt), without waiting for its answer.
 *   With no ioslink on the bus, nothing: a hold does nothing.
 * - confirm(), 0.5 s into the hold: the recording screen shows at once, the
 *   lockscreen is let go (screenKept), the display comes on if it wasn't, mce's
 *   blanking pause starts, and Keep(id) tells ioslink that the note is real.
 * - end(releasedAt, confirmed), at the release: Stop(id, releasedAt) for a
 *   note, Cancel(id) for a click.
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
 * The screen stays on for the whole note because of the lockscreen, not only
 * the pause. The watch face is the lockscreen for mce (compositor.qml's
 * lockscreenWanted): mce blanks a locked display 10 s after it came on, and
 * allows no blanking pause while the lockscreen is locked ("blanking pause
 * allowed" follows its tklock mode: unlocked, true; locked, false). A pause
 * asked on the face was received and did nothing, and the display went off
 * 10 s into the note. So `screenKept` is true from confirm() until the screen
 * is away, and compositor.qml unlocks the lockscreen for as long as it is.
 * Nothing needs undoing if the launcher dies: its next start locks the screen
 * again (MainScreen.qml's LipstickSettings.lockScreen).
 */
import QtQuick 2.15

Item {
    id: hold

    // VoiceNoteOverlay.qml's item.
    property Item overlay: null
    // Whether ioslink is on the session bus.
    property bool ioslinkUp: false
    // Whether the display is fully on: neither off nor ambient.
    property bool displayLit: true
    // function(method, args, callback): a call to mce's request interface;
    // args a string, or undefined; callback optional, given the answer.
    property var callMce
    // function(method, typedArgs, callback, errback): a call to ioslink's
    // VoiceNotes, with Nemo.DBus' typed arguments; the callbacks optional.
    property var callIoslink

    // mce ends a keepalive that isn't renewed within 75 s, and a blanking
    // pause within 60 s. This is half of mce's own period, once it says.
    property int keepaliveRenewMs: 30000
    property int blankingRenewMs: 30000
    // The pause is asked once more this long after it began.
    property int pauseAgainMs: 1500
    // The longest the leases are held, whatever happens: a note is at most
    // 10:00, and ioslink says so within its margin.
    property int capMs: 635000

    readonly property string session: "sonic-launcher-voicenote"

    // The latest hold: {pressedAt, id, replied, refused, failed, confirmed,
    // ended, releasedAt, kept, sent, over}. Arm's answer comes to its own.
    property var current: null
    // Whether a press that start() took is still down.
    property bool holding: false
    property bool keepaliveHeld: false
    property bool blankingPaused: false
    property bool periodAsked: false
    // Whether the note keeps the screen on: from confirm() until the screen is
    // away. compositor.qml lets go of the lockscreen while it is true.
    property bool screenKept: false

    visible: false

    function start(pressedAt) {
        if (!ioslinkUp || overlay === null)
            return
        var h = {pressedAt: pressedAt, id: "", replied: false, refused: false, failed: false,
                 confirmed: false, ended: false, releasedAt: 0, kept: false, sent: false, over: false,
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
        // The lockscreen first: mce allows the pause only once it is unlocked.
        screenKept = true
        if (h.replied && h.refused) {
            h.refusalShown = true
            overlay.refused()
        } else {
            overlay.show()
        }
        if (!displayLit)
            callMce("req_display_state_on", undefined)
        callMce("req_display_blanking_pause", undefined)
        blankingPaused = true
        // Once more, in a moment: a pause asked while the display was still
        // coming on, or before mce had the unlock, is ignored.
        pauseAgain.restart()
        advance(h)
    }

    function end(releasedAt, confirmed) {
        var h = current
        if (!holding || h === null)
            return
        holding = false
        h.ended = true
        h.releasedAt = releasedAt
        if (h.confirmed && !h.refused && !h.failed && !h.over)
            overlay.released(releasedAt - h.pressedAt)
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
            if (h.ended && !h.sent) {
                h.sent = true
                if (h.confirmed)
                    fire("Stop", [{type: "s", value: h.id}, {type: "x", value: h.releasedAt}])
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
        // A screen that was never shown has nothing to wait for.
        overlay.disarm()
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
            pauseAgain.stop()
            callMce("req_display_cancel_blanking_pause", undefined)
        }
        // The lockscreen last: compositor.qml locks it again if the face is in
        // front, and mce's display timeouts are the face's once more.
        screenKept = false
    }

    // The display came on while the pause was held: ask for it again.
    onDisplayLitChanged: {
        if (blankingPaused && displayLit)
            callMce("req_display_blanking_pause", undefined)
    }

    Connections {
        target: hold.overlay
        ignoreUnknownSignals: true
        function onFinished() { hold.overlayFinished() }
    }

    Timer {
        interval: hold.keepaliveRenewMs
        repeat: true
        running: hold.keepaliveHeld
        onTriggered: hold.callMce("req_cpu_keepalive_start", hold.session)
    }

    Timer {
        interval: hold.blankingRenewMs
        repeat: true
        running: hold.blankingPaused
        onTriggered: hold.callMce("req_display_blanking_pause", undefined)
    }

    Timer {
        id: pauseAgain
        interval: hold.pauseAgainMs
        onTriggered: {
            if (hold.blankingPaused)
                hold.callMce("req_display_blanking_pause", undefined)
        }
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
            hold.settle()
        }
    }
}
