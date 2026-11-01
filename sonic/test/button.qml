/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The button scene of sonic/test/test.sh: the bottom button's double-click
 * and the flashlight it toggles.
 * - ButtonDoubleClick, the launcher's own, reads invented input events from a
 *   FIFO, as it reads the kernel's event devices on the watch: one press,
 *   two within and beyond 400 ms, three and four in a row, a held button,
 *   another key, and presses that arrive late, timed by their events.
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

Scene {
    id: desktop

    readonly property string fifo: "/tmp/sonic-button"
    readonly property int keyVolumeDown: 114
    readonly property int keyPower: 116
    readonly property int evKey: 1
    readonly property int evSyn: 0

    ButtonDoubleClick {
        id: button
        property int clicks: 0
        onDoubleClicked: {
            clicks++
            if (wired)
                flashlight.toggle()
        }
        // The flashlight follows the button only at the end.
        property bool wired: false
    }

    AppLauncher {
        id: appLauncher
    }

    // A press and its release, as the kernel sends them, at msec.
    function press(msec, code) {
        var key = code === undefined ? keyVolumeDown : code
        return [[msec, evKey, key, 1], [msec, evSyn, 0, 0],
                [msec + 90, evKey, key, 0], [msec + 90, evSyn, 0, 0]]
    }

    function send(events) {
        check(test.inputEvents(fifo, events), "write " + events.length + " input events")
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
            expectClicks([[25000, evKey, keyVolumeDown, 1], [25150, evKey, keyVolumeDown, 2],
                          [25300, evKey, keyVolumeDown, 2], [25350, evKey, keyVolumeDown, 0]], 0,
                         "a held button's repeats don't count", done)
        },
        function(done) {
            expectClicks(press(29000, keyPower).concat(press(29200, keyPower)), 0,
                         "the power button doesn't count", done)
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
