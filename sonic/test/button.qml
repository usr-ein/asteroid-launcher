/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The button scene of sonic/test/test.sh: the bottom button's double-click
 * and the flashlight it toggles.
 * - ButtonDoubleClick, the launcher's own, with compositor.qml's own key
 *   code, which must be the bottom button's: KEY_MENU (139), from gpio-keys.
 *   It reads invented input events from a FIFO, as it reads the kernel's
 *   event devices on the watch: one press, two within and beyond 400 ms,
 *   three and four in a row, a held button, the power key, KEY_VOLUMEDOWN
 *   (114, the PMIC's RESIN key, which has no button on this watch), and
 *   presses that arrive late, timed by their events.
 * - Its single press, after the double-click's window, and ringsbutton.js,
 *   which compositor.qml asks which app a single press opens: the rings
 *   face's app, only there (the main repo's docs/prd/clock.md § 8.9).
 * - Its hold (the main repo's docs/prd/voice_notes.md § 8.2), which reads the
 *   releases too, with events stamped on the real boot-time clock, as the
 *   kernel stamps them: a click, which confirms no hold and ends in a single
 *   press once 400 ms have passed, or at the release if that's later; a
 *   double-click, whose second press starts no hold, even held for longer
 *   than 0.5 s; a hold of 0.5 s, confirmed, with no single press and no
 *   double-click; a release at 0.45 s, a single press at the release; a press
 *   and its release read together after a stall, at 0.55 s, which still
 *   confirm; a press that woke the watch, read late, timed from when it was
 *   pressed, and one with a stamp that isn't on the boot-time clock, timed
 *   from when it arrives; a press while the last one's release never came; a
 *   device that goes away mid-hold. And voicebutton.js, which compositor.qml
 *   asks where a hold records a note: each condition in turn.
 * - Flashlight.qml, the launcher's own, with a stand-in for compositor.qml's
 *   windows (its window functions as they are) and processes of this
 *   container: the flashlight's window is the one whose process's command
 *   line names asteroid-flashlight, read by the launcher's AppLauncher. It
 *   checks the flashlight on and off from the home, over an app that stays,
 *   with the display off, the display going off, another app opening, a
 *   swipe, and from the quick panel.
 * No screenshot: nothing here draws.
 */
import QtQuick 2.9
import org.asteroid.launcher 1.0
import "qrc:/qml/compositor"
import "qrc:/qml/ringsbutton.js" as RingsButton
import "qrc:/qml/voicebutton.js" as VoiceButton

Scene {
    id: desktop

    readonly property string fifo: "/tmp/sonic-button"
    // The bottom button: gpio-keys' KEY_MENU.
    readonly property int keyMenu: 139
    readonly property int keyPower: 116
    readonly property int keyVolumeDown: 114
    readonly property int evKey: 1
    readonly property int evSyn: 0

    ButtonDoubleClick {
        id: button
        property int clicks: 0
        property int singles: 0
        // What the button reported, in order, with the real time of each:
        // {name, at, detail}.
        property var events: []
        function note(name, detail) {
            events.push({name: name, at: Date.now(), detail: detail})
        }
        onSingleClicked: {
            singles++
            note("single")
        }
        onDoubleClicked: {
            clicks++
            note("double")
            if (wired)
                flashlight.toggle()
        }
        onHoldStarted: note("started", pressedAt)
        onHoldConfirmed: note("confirmed")
        onHoldEnded: note("ended", {releasedAt: releasedAt, confirmed: confirmed})
        // The flashlight follows the button only at the end.
        property bool wired: false
    }

    AppLauncher {
        id: appLauncher
    }

    // A press and its release, as the kernel sends them, at msec.
    function press(msec, code) {
        var key = code === undefined ? keyMenu : code
        return [[msec, evKey, key, 1], [msec, evSyn, 0, 0],
                [msec + 90, evKey, key, 0], [msec + 90, evSyn, 0, 0]]
    }

    function send(events) {
        check(test.inputEvents(fifo, events), "write " + events.length + " input events")
    }

    // A press or a release at a time on the boot-time clock.
    function key(value, stamp) {
        return [[stamp, evKey, keyMenu, value], [stamp, evSyn, 0, 0]]
    }

    // The names of what the button reported since `from`, in order.
    function reported(from) {
        return button.events.slice(from).map(function(e) { return e.name })
    }

    function lastOf(name, from) {
        var found = button.events.slice(from).filter(function(e) { return e.name === name })
        return found.length > 0 ? found[found.length - 1] : null
    }

    function hasEvent(name, from) {
        return lastOf(name, from) !== null
    }

    // Sends the events, waits for them to be read, and checks the count.
    function expectClicks(events, clicks, what, done) {
        var before = button.clicks
        send(events)
        after(700, function() {
            expectEqual(button.clicks - before, clicks, what)
            done()
        })
    }

    // A stand-in for compositor.qml's Compositor: the window functions that
    // Flashlight.qml uses, as they are there, without the animations.
    QtObject { id: home; property string name: "home"; property bool visible: true }
    QtObject {
        id: comp
        property QtObject homeWindow: home
        property QtObject topmostWindow: home
        property QtObject topmostApplicationWindow: null
        property bool displayOn: true

        function setCurrentWindow(w, skipAnimation) {
            if (w == null)
                w = homeWindow
            topmostWindow = w
            if (topmostWindow != homeWindow && topmostWindow != null) {
                if (topmostApplicationWindow) topmostApplicationWindow.visible = false
                topmostApplicationWindow = topmostWindow
                topmostApplicationWindow.visible = true
            }
        }
    }

    Component {
        id: windowComponent
        QtObject {
            property string name
            property var window
            property bool visible: false
        }
    }

    // Processes of this container: one that is a flashlight, one that isn't.
    property int flashlightPid: 0
    property int otherPid: 0
    property int nextWindowId: 1
    property var closedNames: []
    property var quitting: []
    property int launched: 0
    property int woken: 0

    function names(list) {
        return list.map(function(w) { return w.name })
    }

    // compositor.qml's onWindowAdded, for an app window.
    function open(name, isFlashlightApp) {
        var w = windowComponent.createObject(desktop, {
            name: name,
            window: { processId: isFlashlightApp ? flashlightPid : otherPid, windowId: nextWindowId++ }
        })
        if (!flashlight.opened(w)) {
            if (comp.topmostApplicationWindow != null)
                flashlight.closeWindow(comp.topmostApplicationWindow)
            flashlight.closeBelow()
        }
        comp.setCurrentWindow(w)
        return w
    }

    // compositor.qml's onWindowRemoved.
    function removed(w) {
        var below = flashlight.closed(w)
        if (below !== null)
            comp.setCurrentWindow(below, true)
        else if (comp.topmostWindow == w)
            comp.setCurrentWindow(comp.homeWindow)
        w.destroy()
    }

    // The apps quit some time after they're asked to, as clients do.
    function settle(done) {
        after(50, function() {
            var now = quitting
            quitting = []
            now.forEach(removed)
            if (quitting.length > 0)
                settle(done)
            else
                after(50, done)
        })
    }

    // The flashlight app's window appears a moment after it starts.
    Timer {
        id: appStart
        interval: 50
        onTriggered: open("flashlight", true)
    }

    Flashlight {
        id: flashlight
        comp: comp
        displayOn: comp.displayOn
        isFlashlight: function(window) {
            return appLauncher.commandLine(window.processId).indexOf("asteroid-flashlight") !== -1
        }
        closeWindow: function(wrapper) {
            desktop.closedNames = desktop.closedNames.concat([wrapper.name])
            desktop.quitting = desktop.quitting.concat([wrapper])
        }
        launch: function() {
            desktop.launched++
            appStart.restart()
        }
        wake: function() {
            desktop.woken++
            comp.displayOn = true
        }
    }

    function reset() {
        closedNames = []
        launched = 0
        woken = 0
    }

    steps: [
        // The button.
        function(done) {
            expectEqual(button.keyCode, keyMenu, "its default key: KEY_MENU, the bottom button")
            var configured = sh("sed -n 's/.*keyCode: *\\([0-9][0-9]*\\).*/\\1/p' /src/src/qml/compositor/compositor.qml").output.trim()
            expectEqual(configured, String(keyMenu), "compositor.qml's: KEY_MENU, the bottom button")
            button.keyCode = parseInt(configured)
            expectEqual(button.openDevices, [], "no input device in the container: it opens none")
            check(sh("rm -f " + fifo + " && mkfifo " + fifo).status === 0, "make the FIFO")
            send([])
            button.devices = [fifo]
            expectEqual(button.openDevices, [fifo], "it reads the FIFO it's given")
            expectClicks(press(1000), 0, "one press: no double-click", done)
        },
        function(done) {
            expectClicks(press(5000).concat(press(5300)), 1, "two presses 300 ms apart: a double-click", done)
        },
        function(done) {
            expectClicks(press(9000).concat(press(9500)), 0, "500 ms apart: two single presses", done)
        },
        function(done) {
            expectClicks(press(13000).concat(press(13400)), 1, "400 ms apart, the limit: a double-click", done)
        },
        function(done) {
            expectClicks(press(17000).concat(press(17200), press(17400)), 1,
                         "three in a row: one double-click, the third starts again", done)
        },
        function(done) {
            expectClicks(press(21000).concat(press(21200), press(21400), press(21550)), 2,
                         "four in a row: two double-clicks", done)
        },
        function(done) {
            expectClicks([[25000, evKey, keyMenu, 1], [25150, evKey, keyMenu, 2],
                          [25300, evKey, keyMenu, 2], [25350, evKey, keyMenu, 0]], 0,
                         "a held button's repeats don't count", done)
        },
        function(done) {
            expectClicks(press(29000, keyPower).concat(press(29200, keyPower)), 0,
                         "the power button doesn't count", done)
        },
        function(done) {
            expectClicks(press(31000, keyVolumeDown).concat(press(31200, keyVolumeDown)), 0,
                         "nor KEY_VOLUMEDOWN, the PMIC's RESIN key, which has no button here", done)
        },
        function(done) {
            // The events' own times count, not when they arrive: after a wake,
            // the kernel hands over presses late, together or apart.
            var before = button.clicks
            send(press(33000))
            after(1200, function() {
                send(press(33250))
                after(700, function() {
                    expectEqual(button.clicks - before, 1, "two presses 250 ms apart that arrive 1.2 s apart: a double-click")
                    expectClicks(press(37000).concat(press(37900)), 0,
                                 "two presses 900 ms apart that arrive together: none", done)
                })
            })
        },

        // The single press, and what it opens.
        function(done) {
            var singles = button.singles, clicks = button.clicks
            send(press(41000))
            after(200, function() {
                expectEqual(button.singles - singles, 0, "a single press waits out the double-click's window")
                after(500, function() {
                    expectEqual(button.singles - singles, 1, "then it's a single press")
                    send(press(45000).concat(press(45300)))
                    after(700, function() {
                        expectEqual(button.singles - singles, 1, "a double-click is no single press")
                        expectEqual(button.clicks - clicks, 1, "but a double-click")
                        send(press(49000).concat(press(49500)))
                        after(700, function() {
                            expectEqual(button.singles - singles, 3, "two presses 500 ms apart: two single presses")
                            send(press(53000))
                            after(700, function() {
                                send(press(53900).concat(press(54100)))
                                after(700, function() {
                                    expectEqual([button.singles - singles, button.clicks - clicks], [4, 2],
                                                "a single press, then a double-click: one of each")
                                    done()
                                })
                            })
                        })
                    })
                })
            })
        },
        function(done) {
            expectEqual(RingsButton.app(true, false, true, 0, 0, "stopwatches"), "sonic-stopwatch",
                        "on the stopwatches' rings: the Stopwatch app")
            expectEqual(RingsButton.app(true, false, true, 0, 0, "timers"), "sonic-timer",
                        "on the timers' rings: the Timer app")
            expectEqual(RingsButton.app(true, false, true, 0, 0, ""), "", "the face without rings: nothing")
            expectEqual(RingsButton.app(false, false, true, 0, 0, "timers"), "", "the display off: nothing")
            expectEqual(RingsButton.app(true, true, true, 0, 0, "timers"), "", "ambient: nothing")
            expectEqual(RingsButton.app(true, false, false, 0, 0, "timers"), "", "an app in front: nothing")
            expectEqual(RingsButton.app(true, false, true, 1, 0, "timers"), "", "the Today panel: nothing")
            expectEqual(RingsButton.app(true, false, true, 0, 1, "timers"), "", "the app list: nothing")
            var wiring = sh("grep -c 'onSingleClicked' /src/src/qml/compositor/compositor.qml;"
                            + " grep -c 'RingsButton.app' /src/src/qml/compositor/compositor.qml;"
                            + " grep -c 'sonicRingsView' /src/src/qml/MainScreen.qml").output.trim().split("\n")
            check(wiring[0] === "1" && wiring[1] === "1" && parseInt(wiring[2]) > 0,
                  "compositor.qml asks it on a single press, and MainScreen reads the face's view: " + wiring)
            done()
        },

        // The hold, with events stamped on the boot-time clock as the kernel
        // stamps them.
        function(done) {
            // A click: a press, and its release 90 ms later.
            var from = button.events.length, t0 = Date.now()
            var pressed = test.bootMs()
            send(key(1, pressed))
            after(90, function() {
                var released = test.bootMs()
                send(key(0, released))
                waitFor(function() { return hasEvent("single", from) }, 3000, "a click ends in a single press", function() {
                    expectEqual(reported(from), ["started", "ended", "single"],
                                "a click: a hold starts and ends, and none is confirmed")
                    expectEqual(lastOf("started", from).detail, pressed, "the hold starts with the press' own time")
                    expectEqual(lastOf("ended", from).detail, {releasedAt: released, confirmed: false},
                                "it ends with the release's time, unconfirmed: a click")
                    var wait = lastOf("single", from).at - t0
                    check(wait >= 380 && wait < 1500, "the single press comes 400 ms after the press: " + wait + " ms")
                    after(600, function() {
                        expectEqual(reported(from), ["started", "ended", "single"], "and nothing after it")
                        done()
                    })
                })
            })
        },
        function(done) {
            // A double-click, with its second press held for 0.7 s: it starts
            // no hold, so nothing confirms at 0.5 s, and its release is no end.
            var from = button.events.length
            var first = test.bootMs()
            send(key(1, first))
            after(50, function() {
                send(key(0, test.bootMs()))
                after(50, function() {
                    var second = test.bootMs()
                    send(key(1, second))
                    expectEqual(second - first < 400, true, "the second press is within 400 ms of the first: " + (second - first) + " ms")
                    after(700, function() {
                        send(key(0, test.bootMs()))
                        after(600, function() {
                            expectEqual(reported(from), ["started", "ended", "double"],
                                        "a double-click: one hold for the first press, ended; no hold from the second, though held 0.7 s; no single press")
                            done()
                        })
                    })
                })
            })
        },
        function(done) {
            // A hold of 0.5 s: confirmed, and neither a single press nor a
            // double-click, then or after its release.
            var from = button.events.length, t0 = Date.now()
            expectEqual(button.longInterval, 500, "a hold is 0.5 s by default")
            var pressed = test.bootMs()
            send(key(1, pressed))
            waitFor(function() { return hasEvent("confirmed", from) }, 3000, "a hold is confirmed", function() {
                var wait = lastOf("confirmed", from).at - t0
                check(wait >= 480 && wait < 1500, "0.5 s after the press: " + wait + " ms")
                expectEqual(reported(from), ["started", "confirmed"], "a hold: started and confirmed, still down")
                after(300, function() {
                    var released = test.bootMs()
                    send(key(0, released))
                    waitFor(function() { return hasEvent("ended", from) }, 3000, "its release ends it", function() {
                        expectEqual(lastOf("ended", from).detail, {releasedAt: released, confirmed: true},
                                    "ended with the release's time, confirmed")
                        after(700, function() {
                            expectEqual(reported(from), ["started", "confirmed", "ended"],
                                        "no single press and no double-click, at its end or after")
                            done()
                        })
                    })
                })
            })
        },
        function(done) {
            // A release at 0.45 s: a single press, at the release. The press
            // and its release are read together, so that the times are the
            // events' own, not the test's.
            var from = button.events.length, t0 = Date.now()
            var now = test.bootMs()
            send(key(1, now - 450).concat(key(0, now)))
            waitFor(function() { return hasEvent("single", from) }, 3000, "a release at 0.45 s ends in a single press", function() {
                expectEqual(reported(from), ["started", "ended", "single"], "started, ended as a click, then the single press")
                expectEqual(lastOf("ended", from).detail, {releasedAt: now, confirmed: false}, "a click, at 0.45 s")
                var wait = lastOf("single", from).at - t0
                check(wait < 300, "the single press comes at the release, not 400 ms after the press: " + wait + " ms")
                after(600, function() {
                    expectEqual(reported(from).length, 3, "and nothing confirms")
                    done()
                })
            })
        },
        function(done) {
            // A press and its release read together after a stall, 0.55 s
            // apart: it was held long enough all the same.
            var from = button.events.length
            var now = test.bootMs()
            send(key(1, now - 550).concat(key(0, now)))
            waitFor(function() { return hasEvent("ended", from) }, 3000, "a hold read after the fact", function() {
                expectEqual(reported(from), ["started", "confirmed", "ended"], "confirmed before it ends, though nothing was down 0.5 s")
                expectEqual(lastOf("ended", from).detail, {releasedAt: now, confirmed: true}, "a hold")
                after(700, function() {
                    expectEqual(reported(from).length, 3, "no single press")
                    done()
                })
            })
        },
        function(done) {
            // A press that woke the watch reaches the button late, by 400 ms:
            // its hold is timed from when it was pressed, so it confirms 100 ms
            // after it arrives, not 500.
            var from = button.events.length, t0 = Date.now()
            var pressed = test.bootMs() - 400
            send(key(1, pressed))
            waitFor(function() { return hasEvent("confirmed", from) }, 3000, "a late press is confirmed", function() {
                var wait = lastOf("confirmed", from).at - t0
                check(wait >= 90 && wait < 420, "100 ms after it was read, 0.5 s after it was pressed: " + wait + " ms")
                send(key(0, test.bootMs()))
                waitFor(function() { return hasEvent("ended", from) }, 3000, "its release", function() { after(500, done) })
            })
        },
        function(done) {
            // One that was down for 0.7 s when it arrived: confirmed at once.
            var from = button.events.length, t0 = Date.now()
            send(key(1, test.bootMs() - 700))
            waitFor(function() { return hasEvent("confirmed", from) }, 3000, "a press that arrives 0.7 s old is confirmed", function() {
                var wait = lastOf("confirmed", from).at - t0
                check(wait < 300, "at once: " + wait + " ms")
                send(key(0, test.bootMs()))
                waitFor(function() { return hasEvent("ended", from) }, 3000, "its release", function() { after(500, done) })
            })
        },
        function(done) {
            // A stamp that isn't on the boot-time clock, as the other cases here
            // send: no age to count, so it's timed from when it arrives.
            var from = button.events.length, t0 = Date.now()
            send(key(1, 33000))
            waitFor(function() { return hasEvent("confirmed", from) }, 3000, "an old stamp is confirmed", function() {
                var wait = lastOf("confirmed", from).at - t0
                check(wait >= 480 && wait < 1500, "0.5 s after it arrives: " + wait + " ms")
                send(key(0, 33900))
                waitFor(function() { return hasEvent("ended", from) }, 3000, "its release", function() { after(500, done) })
            })
        },
        function(done) {
            // A press while the last one is still down: its release never came.
            // The first ends at the second, as released then, and it was held
            // 0.8 s by the stamps; the second starts, and is a click.
            var from = button.events.length
            var now = test.bootMs()
            send(key(1, now - 800).concat(key(1, now)))
            waitFor(function() { return reported(from).length >= 4 }, 3000, "the second press starts a hold", function() {
                expectEqual(reported(from), ["started", "confirmed", "ended", "started"],
                            "the first hold is confirmed and ended; a second starts: no double-click, 0.8 s apart")
                expectEqual(button.events[from + 2].detail, {releasedAt: now, confirmed: true}, "the first ended at the second's time")
                var released = test.bootMs()
                send(key(0, released))
                waitFor(function() { return hasEvent("single", from) }, 3000, "the second, released, is a click", function() {
                    expectEqual(reported(from), ["started", "confirmed", "ended", "started", "ended", "single"],
                                "which ends in a single press")
                    done()
                })
            })
        },
        function(done) {
            // A device that goes away mid-hold: the hold ends, as no click.
            var from = button.events.length
            send(key(1, test.bootMs()))
            after(100, function() {
                expectEqual(reported(from), ["started"], "a hold is down")
                button.devices = [fifo, "/nonexistent"]
                expectEqual(reported(from), ["started", "ended"], "the devices are read afresh: it ends at once")
                expectEqual(button.events[from + 1].detail.confirmed, false, "unconfirmed")
                button.devices = [fifo]
                after(700, function() {
                    expectEqual(reported(from), ["started", "ended"], "and no single press follows: it was no click")
                    expectEqual(button.openDevices, [fifo], "the FIFO is read again")
                    done()
                })
            })
        },
        function(done) {
            // The guard: where a hold records a note, each condition in turn.
            expectEqual(VoiceButton.canRecord(true, false, true, 0, 0), true, "on the face, the display on: a note")
            expectEqual(VoiceButton.canRecord(false, false, true, 0, 0), true, "the display off: a note")
            expectEqual(VoiceButton.canRecord(false, false, false, 1, 1), true, "the display off, wherever the panels are and an app in front: a note")
            expectEqual(VoiceButton.canRecord(true, true, true, 0, 0), true, "ambient: a note")
            expectEqual(VoiceButton.canRecord(true, true, false, 0, 1), true, "ambient, wherever the panels are: a note")
            expectEqual(VoiceButton.canRecord(true, false, false, 0, 0), false, "an app in front: none")
            expectEqual(VoiceButton.canRecord(true, false, true, 1, 0), false, "the Today panel: none")
            expectEqual(VoiceButton.canRecord(true, false, true, 0, 1), false, "the app list: none")
            expectEqual(VoiceButton.canRecord(true, false, true, 0, -1), false, "the quick panel: none")
            expectEqual(VoiceButton.canRecord(true, false, true, -1, -1), false, "the panels not there yet: none")
            expectEqual(VoiceButton.canRecord(true, false, undefined, 0, 0), false, "the home not known: none")
            var wiring = sh("grep -c 'onHoldStarted' /src/src/qml/compositor/compositor.qml;"
                            + " grep -c 'VoiceButton.canRecord' /src/src/qml/compositor/compositor.qml;"
                            + " grep -c 'voiceNote.start(pressedAt)' /src/src/qml/compositor/compositor.qml;"
                            + " grep -c 'onHoldConfirmed: voiceNote.confirm()' /src/src/qml/compositor/compositor.qml;"
                            + " grep -c 'onHoldEnded: voiceNote.end(releasedAt, confirmed)' /src/src/qml/compositor/compositor.qml;"
                            + " grep -c 'z: 5$' /src/src/qml/compositor/compositor.qml;"
                            + " grep -c 'z: 6$' /src/src/qml/compositor/compositor.qml;"
                            + " grep -c 'z: 5.5$' /src/src/qml/compositor/VoiceNoteOverlay.qml").output.trim().split("\n")
            expectEqual(wiring, ["1", "1", "1", "1", "1", "1", "1", "1"],
                        "compositor.qml wires the hold to the guard and to voiceNote, and the recording screen is between the gesture area (z 5) and the round mask (z 6)")
            done()
        },

        // The processes that the windows belong to.
        function(done) {
            var flashlightRun = sh("mkdir -p /tmp/bin && printf '#!/bin/sh\\nsleep 600\\n' > /tmp/bin/asteroid-flashlight"
                                   + " && chmod +x /tmp/bin/asteroid-flashlight"
                                   + " && (/tmp/bin/asteroid-flashlight >/dev/null 2>&1 & echo $!)")
            var otherRun = sh("sleep 600 >/dev/null 2>&1 & echo $!")
            flashlightPid = parseInt(flashlightRun.output)
            otherPid = parseInt(otherRun.output)
            after(200, function() {
                // Under emulation, QEMU's own arguments come first.
                var light = appLauncher.commandLine(flashlightPid)
                var other = appLauncher.commandLine(otherPid)
                check(/\/bin\/sh \/tmp\/bin\/asteroid-flashlight$/.test(light),
                      "AppLauncher reads a process's command line: " + light)
                check(/ sleep 600$/.test(other) && other.indexOf("asteroid-flashlight") === -1,
                      "and another's: " + other)
                expectEqual(appLauncher.commandLine(999999), "", "and \"\" for no process")
                done()
            })
        },

        // From the home: on, then off.
        function(done) {
            reset()
            flashlight.toggle()
            expectEqual([launched, woken], [1, 0], "from the home, the display on: it starts the flashlight app")
            after(200, function() {
                check(comp.topmostWindow.name === "flashlight" && flashlight.lit, "the flashlight shines")
                flashlight.toggle()
                settle(function() {
                    expectEqual(closedNames, ["flashlight"], "again: it closes the flashlight, and nothing else")
                    check(comp.topmostWindow === home && !flashlight.lit, "back to the home")
                    done()
                })
            })
        },

        // Over an app, which stays and comes back.
        function(done) {
            reset()
            var timer = open("timer", false)
            flashlight.toggle()
            after(200, function() {
                check(comp.topmostWindow.name === "flashlight" && flashlight.lit, "over the timer app, it shines")
                expectEqual(closedNames, [], "the timer app isn't closed")
                check(!timer.visible && flashlight.below === timer, "the timer waits below, hidden")
                flashlight.toggle()
                settle(function() {
                    expectEqual(closedNames, ["flashlight"], "off: only the flashlight closes")
                    check(comp.topmostWindow === timer && timer.visible, "and the timer app is back on the screen")
                    flashlight.closeWindow(timer)
                    settle(done)
                })
            })
        },

        // With the display off.
        function(done) {
            reset()
            comp.displayOn = false
            flashlight.toggle()
            expectEqual([woken, launched], [1, 1], "with the display off: it turns the display on and starts the flashlight")
            after(200, function() {
                check(flashlight.lit, "it shines")
                // The power button: off, but the flashlight still open.
                comp.displayOn = false
                check(!flashlight.lit, "with the display off, it doesn't shine")
                flashlight.toggle()
                expectEqual([woken, launched], [2, 1], "again: the display comes back on, the same flashlight")
                check(flashlight.lit, "and it shines again")
                flashlight.toggle()
                settle(done)
            })
        },

        // The display goes off over an app: both close, as any app would.
        function(done) {
            reset()
            var timer = open("timer", false)
            flashlight.toggle()
            after(200, function() {
                comp.displayOn = false
                // compositor.qml's display-off timer closes the topmost app.
                flashlight.closeWindow(comp.topmostWindow)
                settle(function() {
                    expectEqual(closedNames.sort(), ["flashlight", "timer"],
                                "the display off closes the flashlight, and the timer app below it")
                    check(comp.topmostWindow === home, "the home is left")
                    comp.displayOn = true
                    done()
                })
            })
        },

        // Another app opens over the flashlight: the app below it goes too.
        function(done) {
            reset()
            open("timer", false)
            flashlight.toggle()
            after(200, function() {
                var weather = open("weather", false)
                settle(function() {
                    expectEqual(closedNames.sort(), ["flashlight", "timer"],
                                "another app replaces the flashlight and the app below it")
                    check(comp.topmostWindow === weather && flashlight.window === null && flashlight.below === null,
                          "the other app is on the screen, the flashlight forgotten")
                    flashlight.closeWindow(weather)
                    settle(done)
                })
            })
        },

        // From the quick panel, closed by a swipe.
        function(done) {
            reset()
            var timer = open("timer", false)
            comp.setCurrentWindow(home)
            var light = open("flashlight", true)
            check(flashlight.window === light && flashlight.below === timer,
                  "opened from the quick panel, it is the flashlight too, and the timer app stays")
            // compositor.qml's swipe: the home first, then the app closes.
            comp.topmostWindow = home
            flashlight.closeWindow(light)
            settle(function() {
                expectEqual(closedNames, ["flashlight"], "a swipe closes only the flashlight")
                check(comp.topmostWindow === home && comp.topmostApplicationWindow === timer,
                      "it leaves the home, and the timer app in the background, the app that the next replaces")
                flashlight.closeWindow(timer)
                settle(done)
            })
        },

        // The button and the flashlight together.
        function(done) {
            reset()
            button.wired = true
            send(press(41000).concat(press(41250)))
            after(800, function() {
                expectEqual(launched, 1, "a double-click of the button turns the flashlight on")
                check(flashlight.lit, "it shines")
                send(press(45000).concat(press(45250)))
                after(800, function() {
                    settle(function() {
                        expectEqual(closedNames, ["flashlight"], "another double-click turns it off")
                        sh("kill " + flashlightPid + " " + otherPid)
                        done()
                    })
                })
            })
        }
    ]
}
