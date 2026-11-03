/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The voicenote-fake scene of sonic/test/test.sh, run on request, not with the
 * others: the launcher's recording screen and hold against the main repo's
 * contract fake, `fakeioslink voicenotes` (ioslink/cmd/fakeioslink), which
 * serves the VoiceNotes interface through godbus and busapi, as ioslink does,
 * where the harness' own stand-in is Qt's. It checks what a stand-in of the
 * same hand can't: that Nemo.DBus reads what godbus exports (State and its
 * PropertiesChanged, Levels' `ai`, Arm's `x`), and each way a note ends, as
 * the fake is told to end it.
 *
 * The fork can't build the fake, which is the main repo's Go. Build it for
 * the test container, a 32-bit ARM Linux, and put it where the container sees
 * the test's output folder:
 *
 *   (cd <main repo>/ioslink && GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
 *       go build -o <fork>/sonic/out/test/fakeioslink ./cmd/fakeioslink)
 *   sonic/test/test.sh voicenote-fake
 *
 * Without it the scene says so, and passes.
 */
import QtQuick 2.15
import Nemo.DBus 2.0
import org.asteroid.launcher 1.0
import "qrc:/qml/compositor"

Scene {
    id: desktop

    readonly property string fifo: "/tmp/sonic-voicenote-fake"
    readonly property int keyMenu: 139
    readonly property int evKey: 1
    readonly property int evSyn: 0
    readonly property string fakeId: "A1000000-0000-4000-8000-00000000F4CE"
    // Whether the fake is in the container, at /out.
    readonly property bool available: test.sh("test -x /out/fakeioslink").status === 0

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

    property var trace: []
    property var failures: []
    property var phaseLog: []

    VoiceNoteOverlay {
        id: overlay
        width: 454
        height: 454
    }

    VoiceNoteHold {
        id: hold
        overlay: overlay
        ioslinkUp: voiceNotesBus.status === DBusInterface.Available
        displayLit: true
        callMce: function(method, args, callback) {
            mceRequest.call(method, args, callback)
        }
        callIoslink: function(method, args, callback, errback) {
            desktop.trace.push(method + args.map(function(a) { return " " + a.value }).join(""))
            voiceNotesBus.typedCall(method, args, callback, function(name, message) {
                desktop.failures.push(method + ": " + name)
                errback(name, message)
            })
        }
    }

    ButtonDoubleClick {
        id: button
        onHoldStarted: hold.start(pressedAt)
        onHoldConfirmed: hold.confirm()
        onHoldEnded: hold.end(releasedAt, confirmed)
    }

    Connections {
        target: overlay
        function onPhaseChanged() { desktop.phaseLog.push(overlay.phase) }
    }

    ContactSheet {
        id: sheet
        x: desktop.width + 100
        columns: 3
        title: "The launcher's screen against the real fakeioslink voicenotes"
    }

    property var files: []
    property var labels: []

    function keep(name, label, done) {
        files.push(shots + "/" + name + ".png")
        labels.push(label)
        shot(name, done, overlay)
    }

    function press(stamp) {
        test.inputEvents(fifo, [[stamp, evKey, keyMenu, 1], [stamp, evSyn, 0, 0]])
    }

    function release(stamp) {
        test.inputEvents(fifo, [[stamp, evKey, keyMenu, 0], [stamp, evSyn, 0, 0]])
    }

    // The fake, started with these flags; the old one goes first. Each fake has
    // an onWatch of its own, so that its State isn't taken for the last one's.
    property int fakes: 0

    function startFake(flags, then) {
        var onWatch = 10 + ++desktop.fakes
        var wasUp = hold.ioslinkUp
        sh("[ -f /tmp/fake.pid ] && kill $(cat /tmp/fake.pid) 2>/dev/null; rm -f /tmp/fake.out /tmp/fake.err /tmp/fake.pid; true")
        function launch() {
            sh("(/out/fakeioslink voicenotes -onwatch " + onWatch + " " + flags + " >/tmp/fake.out 2>/tmp/fake.err </dev/null & echo $! >/tmp/fake.pid); true")
            waitFor(function() { return sh("grep -c ready /tmp/fake.err 2>/dev/null || true").output.trim() === "1" }, 30000, "the fake says it's ready", function() {
                waitFor(function() { return hold.ioslinkUp && overlay.info.onWatch === onWatch }, 30000,
                        "the launcher sees it on the bus and reads its State", then)
            })
        }
        if (wasUp)
            waitFor(function() { return !hold.ioslinkUp }, 10000, "the old fake leaves the bus", launch)
        else
            launch()
    }

    function fakeLog() {
        return sh("cat /tmp/fake.out").output.trim().split("\n").filter(function(l) { return l.indexOf("GetAll") !== 0 })
    }

    function reset() {
        desktop.trace = []
        desktop.failures = []
        desktop.phaseLog = []
        mce.clear()
    }

    // One hold of `ms`, and what the screen says in the end.
    function holdFor(ms, expectedLine, then) {
        reset()
        var stamp = test.bootMs()
        press(stamp)
        waitFor(function() { return overlay.phase === "live" || overlay.phase === "refused" }, 5000, "the screen shows", function() {
            after(ms, function() {
                release(test.bootMs())
                waitFor(function() { return overlay.phase === "ended" || overlay.phase === "refused" }, 8000, "the screen has the outcome", function() {
                    expectEqual(overlay.lineText, expectedLine, "the line against the fake's State")
                    then(stamp)
                })
            })
        })
    }

    // A hold that Arm refuses: the screen says why at 0.5 s, and goes by itself.
    function refusal(line, then) {
        reset()
        press(test.bootMs())
        waitFor(function() { return overlay.phase === "refused" }, 5000, "a refusal shows at 0.5 s", function() {
            expectEqual({line: overlay.lineText, amber: overlay.lineAmber}, {line: line, amber: true}, "the line against the fake's State, in amber")
            after(200, function() {
                release(test.bootMs())
                gone(function() {
                    expectEqual(fakeLog().length, 1, "the fake only heard Arm: " + fakeLog())
                    then()
                })
            })
        })
    }

    function gone(then) {
        waitFor(function() { return overlay.phase === "idle" && !hold.keepaliveHeld && !hold.blankingPaused }, 8000, "the screen is away and nothing is held", then)
    }

    function spaced(list) {
        return list.map(function(step) {
            return function(done) { step(function() { after(450, done) }) }
        })
    }

    steps: !available ? [function(done) {
        check(true, "skipped: no /out/fakeioslink, the main repo's fakeioslink built for 32-bit ARM Linux (see this file's head)")
        done()
    }] : spaced([
        function(done) {
            sh("rm -f " + fifo + " && mkfifo " + fifo)
            test.inputEvents(fifo, [])
            button.devices = [fifo]
            overlay.farewellMs = 600
            overlay.dropFarewellMs = 600
            overlay.fadeMs = 100
            check(mce.start(), "the stand-in for mce comes on the bus")
            startFake("-outcome saved", function() {
                expectEqual(sh("grep -c 'GetAll org.sonicscrewdriver.ioslink.VoiceNotes' /tmp/fake.out").output.trim(), "1",
                            "the screen read State, once, through Properties.GetAll")
                done()
            })
        },

        // A long hold: Arm, Keep, Stop; the levels and the outcome from the fake.
        function(done) {
            holdFor(1400, "Saved · sending", function(stamp) {
                expectEqual(overlay.noteId, desktop.fakeId, "the screen has the fake's id")
                var drawn = overlay.heights.filter(function(h) { return h > 0 }).length
                check(drawn >= 8, "the fake's Levels, 'ai' through godbus, draw the bars: " + drawn + " of them")
                expectEqual(fakeLog(), ["Arm " + stamp, "Keep " + desktop.fakeId, fakeLog()[2]],
                            "the fake heard Arm with the stamp, then Keep with the id")
                check(/^Stop A1000000-0000-4000-8000-00000000F4CE \d+$/.test(fakeLog()[2]), "and Stop with the id and a time: " + fakeLog()[2])
                expectEqual(desktop.failures, [], "no call failed")
                keep("voicenote-fake-saved", "A hold against the fake: saved", function() {
                    gone(function() {
                        expectEqual(desktop.phaseLog, ["armed", "live", "saving", "ended", "idle"], "the screen's phases")
                        done()
                    })
                })
            })
        },

        // A late Stop for the note that ended last is no error.
        function(done) {
            reset()
            hold.fire("Stop", [{type: "s", value: desktop.fakeId}, {type: "x", value: 1}])
            after(500, function() {
                expectEqual(desktop.failures, [], "a late Stop for the note that ended last: no error")
                hold.fire("Keep", [{type: "s", value: "NOBODY"}])
                waitFor(function() { return desktop.failures.length > 0 }, 5000, "an id that no note had fails", function() {
                    expectEqual(desktop.failures, ["Keep: org.sonicscrewdriver.ioslink.VoiceNotes.Error.NotFound"], "with NotFound")
                    done()
                })
            })
        },

        // A click: Arm and Cancel.
        function(done) {
            reset()
            var before = fakeLog().length
            var stamp = test.bootMs()
            press(stamp)
            after(90, function() {
                release(test.bootMs())
                waitFor(function() { return fakeLog().length >= before + 2 && !hold.keepaliveHeld }, 5000, "the fake has Arm and Cancel", function() {
                    expectEqual(fakeLog().slice(-2), ["Arm " + stamp, "Cancel " + desktop.fakeId], "a click Arms and Cancels")
                    expectEqual(desktop.phaseLog, ["armed", "idle"], "and shows nothing")
                    expectEqual(desktop.failures, [], "no call failed")
                    done()
                })
            })
        },

        // How a note ends, as the fake is told.
        function(done) {
            startFake("-outcome dropped -dropped 2", function() {
                holdFor(1200, "Saved · 2 dropped", function() { gone(done) })
            })
        },
        function(done) {
            startFake("-outcome dropped -dropped 1", function() {
                holdFor(1200, "Saved · " + viewTimeOfDay(1793718120000) + " dropped", function() { gone(done) })
            })
        },
        function(done) {
            startFake("-outcome limit", function() {
                holdFor(1200, "10 min limit · saved", function() { gone(done) })
            })
        },
        function(done) {
            startFake("-outcome limit -reason storage", function() {
                holdFor(1200, "Storage full · saved", function() { gone(done) })
            })
        },
        function(done) {
            startFake("-outcome saved -reason microphone", function() {
                holdFor(1200, "Microphone lost · saved", function() { gone(done) })
            })
        },
        function(done) {
            startFake("-outcome saved -reason encoder", function() {
                holdFor(1200, "Encoder failed · saved", function() { gone(done) })
            })
        },
        function(done) {
            startFake("-outcome failed -reason microphone", function() {
                holdFor(1200, "Microphone unavailable", function() { gone(done) })
            })
        },
        function(done) {
            startFake("-outcome failed -reason encoder", function() {
                holdFor(1200, "Couldn't record", function() { gone(done) })
            })
        },
        function(done) {
            startFake("-outcome tooShort", function() {
                holdFor(1200, "Too short", function() { gone(done) })
            })
        },

        // A refusal: Arm answers "", and State says why, which shows at 0.5 s.
        function(done) {
            startFake("-refuse storage", function() {
                refusal("Watch storage full", done)
            })
        },
        function(done) {
            startFake("-refuse microphone", function() {
                refusal("Microphone unavailable", done)
            })
        },

        // The fake goes away mid-note.
        function(done) {
            startFake("-outcome saved", function() {
                reset()
                press(test.bootMs())
                waitFor(function() { return overlay.phase === "live" }, 5000, "the screen shows", function() {
                    after(300, function() {
                        sh("kill $(cat /tmp/fake.pid)")
                        waitFor(function() { return overlay.phase === "stopped" }, 8000, "ioslink goes: the screen says so", function() {
                            expectEqual(overlay.lineText, "Recorder stopped", "the line")
                            release(test.bootMs())
                            gone(done)
                        })
                    })
                })
            })
        },

        function(done) {
            sh("[ -f /tmp/fake.pid ] && kill $(cat /tmp/fake.pid) 2>/dev/null; true")
            sheet.files = files
            sheet.labels = labels
            after(300, function() { shot("voicenote-fake-sheet", done, sheet) })
        }
    ])

    // voicenoteview.js' time of day, for the fake's dropped note.
    function viewTimeOfDay(ms) {
        var d = new Date(ms)
        return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
    }
}
