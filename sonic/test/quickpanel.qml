/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick panel scene of sonic/test/test.sh: the launcher's own QuickPanel,
 * compiled in, on the dark theme's black, which MainScreen's darkener makes
 * opaque behind every panel but the watch face. The system services that it
 * reads are stand-ins (stubs/), with the alert profile on "general".
 * - The Find phone button, against `ioslink`, the harness's stand-in for
 *   ioslink's FindPhone interface on the test bus: first in the sliding row;
 *   "Phone not connected", and nothing called, without ioslink, without the
 *   iPhone, or without a session while it rings; lit as ioslink's Ringing,
 *   which a tap turns, with no light of its own; dark again at a tap, or
 *   when the iPhone stops; a tap that doesn't take, ring or stop, with
 *   Ringing back as it was; each of PROTOCOL.md § 6.10's lines, from Problem
 *   and from Ring()'s errors, the bus's NoReply included; an old problem not
 *   shown again after a restart of ioslink.
 * - The bell: general, silent, outdoors.
 * - sonic/watch/quickpanel-findphone, against the SDK's own dconf service:
 *   with the watch's settings, which list the toggles, the button isn't
 *   there; the script puts it first, --status shows it, --undo takes it out,
 *   and the panel follows each change.
 * - The sound toggle's unmute sound, a SoundEffect, which opens an audio
 *   stream as soon as it's created: none with the watch's settings, which
 *   don't have the toggle; one with the toggle in the sliding row, and none
 *   again without it.
 * Screenshots: the panel; "Phone not connected"; ringing; "Allow alarms in
 * Sonic"; the bell on outdoors; and a contact sheet of them.
 */
import QtQuick 2.9
import org.asteroid.controls 1.0
import "qrc:/qml/"

Scene {
    id: desktop

    // What the quick panel reads from MainScreen.
    QtObject {
        id: grid
        property int currentVerticalPos: -1
        function changeAllowedDirections() { }
    }
    QtObject {
        id: alwaysOnDisplay
        property bool value: true
    }
    property var volumeControl: null

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    QuickPanel {
        id: panel
    }

    ContactSheet {
        id: sheet
        x: desktop.width + 100
        columns: 3
    }

    property var files: []
    property var labels: []

    function keep(name, label, done) {
        files.push(shots + "/" + name + ".png")
        labels.push(label)
        shot(name, done)
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

    function named(name) {
        return find(panel, function(item) { return item.objectName === name })
    }

    function slidingRow() {
        return find(panel, function(item) { return item.orientation === ListView.Horizontal && item.interactive === true })
    }

    // The SoundEffects in the panel, visual items' or not.
    function soundEffects() {
        var found = []
        function walk(o) {
            if (String(o).indexOf("SoundEffect") !== -1)
                found.push(o)
            var lists = [o.resources, o.children]
            for (var l = 0; l < lists.length; l++)
                for (var i = 0; lists[l] !== undefined && i < lists[l].length; i++)
                    walk(lists[l][i])
        }
        walk(panel)
        return found
    }

    function bell() {
        return find(panel, function(item) { return item.profile !== undefined && item.tint !== undefined })
    }

    readonly property string script: "SONIC_DCONF_USER= sh /src/sonic/watch/quickpanel-findphone"

    steps: [
        // The Find phone button, ioslink not on the bus yet.
        function(done) {
            var button = named("findPhoneButton")
            check(button !== null, "the Find phone button is on the sliding row's first page")
            var row = slidingRow()
            var at = row.mapFromItem(button, button.width / 2, button.height / 2)
            check(at.x > 0 && at.x < row.width / 3, "first on it")
            keep("quickpanel", "The quick panel: Find phone first", function() {
                button.clicked(null)
                after(400, function() {
                    expectEqual(panel.notice, "Phone not connected", "without ioslink, a tap says \"Phone not connected\"")
                    check(!button.checked && ioslink.rings === 0, "and doesn't light or ring")
                    keep("quickpanel-not-connected", "No phone: \"Phone not connected\"", done)
                })
            })
        },
        function(done) {
            check(ioslink.start(), "the stand-in ioslink comes on the bus")
            waitFor(function() { return named("findPhone").available === false && panel.notice === "" }, 5000,
                    "ioslink without the iPhone; the line gone after 3 s", function() {
                named("findPhoneButton").clicked(null)
                after(300, function() {
                    expectEqual(panel.notice, "Phone not connected", "the iPhone not connected: \"Phone not connected\"")
                    check(ioslink.rings === 0, "and no Ring()")
                    done()
                })
            })
        },

        // Ringing, and stopped from the watch.
        function(done) {
            ioslink.available = true
            waitFor(function() { return named("findPhone").available }, 5000, "the iPhone connected", function() {
                ioslink.answer = "ring"
                var button = named("findPhoneButton")
                check(panel.notice === "Phone not connected", "the last tap's line still shows")
                button.clicked(null)
                expectEqual(panel.notice, "", "a tap clears it")
                check(!button.checked, "the button has no light of its own")
                waitFor(function() { return button.checked }, 2000, "lit as soon as ioslink's Ringing turns", function() {
                    check(ioslink.rings === 1 && ioslink.ringing, "which Ring() turned")
                    after(300, function() {
                        check(button.checked, "lit while the iPhone rings")
                        keep("quickpanel-ringing", "The iPhone rings: lit", function() {
                            button.clicked(null)
                            check(button.checked, "a tap while it rings: lit until ioslink's Ringing turns")
                            waitFor(function() { return !button.checked }, 2000, "then dark", function() {
                                check(ioslink.stops === 1 && !ioslink.ringing, "which Stop() turned")
                                done()
                            })
                        })
                    })
                })
            })
        },

        // Stopped on the iPhone, "Found It".
        function(done) {
            ioslink.ringing = true
            after(300, function() {
                check(named("findPhoneButton").checked, "the iPhone rings: lit")
                ioslink.ringing = false
                after(300, function() {
                    check(!named("findPhoneButton").checked, "stopped on the iPhone: dark")
                    done()
                })
            })
        },

        // Ringing as far as the watch knows, and the session gone: nothing
        // to stop the ring with.
        function(done) {
            ioslink.ringing = true
            ioslink.available = false
            waitFor(function() { return !named("findPhone").available && named("findPhoneButton").checked }, 3000,
                    "ringing, without a session", function() {
                var stops = ioslink.stops
                named("findPhoneButton").clicked(null)
                after(300, function() {
                    expectEqual(panel.notice, "Phone not connected", "a tap: \"Phone not connected\"")
                    check(ioslink.stops === stops, "and no Stop()")
                    check(named("findPhoneButton").checked, "still lit, as ioslink's Ringing")
                    ioslink.ringing = false
                    ioslink.available = true
                    waitFor(function() { return named("findPhone").available && !named("findPhoneButton").checked }, 3000,
                            "the session back, the ring over", done)
                })
            })
        },

        // CODE_DENIED: AlarmKit not allowed in Sonic. Lit at the tap, as
        // ioslink's Ringing, then dark again with the line.
        function(done) {
            waitFor(function() { return panel.notice === "" }, 5000, "the line gone", function() {
                ioslink.answer = "denied"
                var findPhone = named("findPhone")
                var lit = false
                function seen() { lit = lit || findPhone.lit }
                findPhone.litChanged.connect(seen)
                named("findPhoneButton").clicked(null)
                waitFor(function() { return panel.notice !== "" }, 3000, "an answer", function() {
                    findPhone.litChanged.disconnect(seen)
                    check(lit, "lit at the tap")
                    expectEqual(panel.notice, "Allow alarms in Sonic", "AlarmKit not allowed: \"Allow alarms in Sonic\"")
                    check(!named("findPhoneButton").checked, "and dark again, as ioslink puts Ringing back")
                    keep("quickpanel-denied", "Not allowed: \"Allow alarms in Sonic\"", done)
                })
            })
        },

        // The other problems of PROTOCOL.md § 6.10, each in its turn: from
        // Problem, and from Ring()'s error behind it for "notconnected" and
        // "failed", which must leave the same line.
        function(done) {
            var problems = [["unavailable", "Unlock your iPhone first"], ["timeout", "Phone didn't answer"],
                            ["notconnected", "Phone not connected"], ["failed", "Phone didn't answer"]]
            function one() {
                if (problems.length === 0) {
                    done()
                    return
                }
                var p = problems.shift()
                waitFor(function() { return panel.notice === "" }, 5000, "the line gone", function() {
                    ioslink.answer = p[0]
                    named("findPhoneButton").clicked(null)
                    waitFor(function() { return panel.notice !== "" }, 3000, "an answer", function() {
                        after(500, function() {
                            expectEqual(panel.notice, p[1], p[0] + ": \"" + p[1] + "\"")
                            check(!named("findPhoneButton").checked, "and dark")
                            one()
                        })
                    })
                })
            }
            one()
        },

        // A stop that doesn't take: lit again, as ioslink puts Ringing back.
        function(done) {
            waitFor(function() { return panel.notice === "" }, 5000, "the line gone", function() {
                ioslink.answer = "ring"
                ioslink.stopAnswer = "timeout"
                var button = named("findPhoneButton")
                button.clicked(null)
                waitFor(function() { return button.checked }, 2000, "ringing", function() {
                    button.clicked(null)
                    waitFor(function() { return !button.checked }, 2000, "a tap: dark, as Stop() turns Ringing", function() {
                        waitFor(function() { return panel.notice !== "" }, 3000, "an answer", function() {
                            expectEqual(panel.notice, "Phone didn't answer", "a stop that doesn't take: \"Phone didn't answer\"")
                            check(button.checked, "and lit again: the iPhone still rings")
                            ioslink.stopAnswer = "stop"
                            ioslink.ringing = false
                            waitFor(function() { return !button.checked }, 2000, "then stopped on the iPhone", done)
                        })
                    })
                })
            })
        },

        // An ioslink that never replies: the bus's NoReply, after its 25 s.
        function(done) {
            waitFor(function() { return panel.notice === "" }, 5000, "the line gone", function() {
                ioslink.answer = "hang"
                var button = named("findPhoneButton")
                button.clicked(null)
                waitFor(function() { return panel.notice !== "" }, 40000, "the bus's NoReply", function() {
                    expectEqual(panel.notice, "Phone didn't answer", "no reply: \"Phone didn't answer\"")
                    check(!button.checked, "and dark")
                    ioslink.answer = "ring"
                    done()
                })
            })
        },

        // ioslink restarts: its last problem, old by then, isn't shown again.
        function(done) {
            waitFor(function() { return panel.notice === "" }, 5000, "the line gone", function() {
                ioslink.stop()
                waitFor(function() { return !named("findPhone").available }, 5000, "ioslink gone", function() {
                    check(ioslink.start(), "ioslink back")
                    waitFor(function() { return named("findPhone").available }, 5000, "and the iPhone with it", function() {
                        after(500, function() {
                            expectEqual(panel.notice, "", "the old problem isn't shown again")
                            done()
                        })
                    })
                })
            })
        },

        // The bell, on the second page.
        function(done) {
            var row = slidingRow()
            row.positionViewAtIndex(1, ListView.Beginning)
            after(300, function() {
                var toggle = bell()
                check(toggle !== null, "the bell toggle shows, on the second page")
                toggle.clicked(null)
                after(300, function() {
                    check(toggle.profile === "silent", "a tap on the bell goes from general to silent")
                    toggle.clicked(null)
                    after(300, function() {
                        check(toggle.profile === "outdoors", "and from silent to outdoors")
                        keep("quickpanel-outdoors", "The bell on outdoors", function() {
                            row.positionViewAtIndex(0, ListView.Beginning)
                            done()
                        })
                    })
                })
            })
        },

        // The watch's settings, which list the toggles: the script.
        function(done) {
            check(sh("dconf load /desktop/asteroid/quickpanel/ < /src/sonic/test/quickpanel-user.ini").status === 0,
                  "the watch's quick panel settings")
            waitFor(function() { return named("findPhoneButton") === null }, 5000,
                    "with them, no Find phone button", function() {
                var added = sh(script)
                check(added.status === 0 && added.output.indexOf("slider: [<'findPhoneButton'>, <'brightnessToggle'>") !== -1,
                      "quickpanel-findphone puts it first: " + added.output.split("\n")[0])
                check(added.output.indexOf("'findPhoneButton': <true>") !== -1, "and enables it")
                waitFor(function() { return named("findPhoneButton") !== null }, 5000,
                        "the panel shows it at once", done)
            })
        },
        function(done) {
            expectEqual(sh(script).output.trim(), "nothing to change", "again: nothing to change")
            var status = sh(script + " --status").output
            check(status.indexOf("slider: [<'findPhoneButton'>") === 0, "--status shows where it is")
            var undone = sh(script + " --undo")
            check(undone.status === 0 && undone.output.indexOf("findPhoneButton") === -1, "--undo takes it out")
            var slider = sh("dconf read /desktop/asteroid/quickpanel/slider").output.trim()
            expectEqual(slider, "[<'brightnessToggle'>, <'bluetoothToggle'>, <'hapticsToggle'>, <'wifiToggle'>, "
                        + "<'cinemaToggle'>, <'aodToggle'>, <'powerOffToggle'>, <'rebootToggle'>, <'musicButton'>, "
                        + "<'flashlightButton'>]", "as it was")
            waitFor(function() { return named("findPhoneButton") === null }, 5000, "and the panel follows", done)
        },

        // The unmute sound, only where the sound toggle is.
        function(done) {
            expectEqual(soundEffects().length, 0, "the watch's settings, without the sound toggle: no SoundEffect")
            check(sh("dconf write /desktop/asteroid/quickpanel/slider \"['soundToggle', 'brightnessToggle', 'bluetoothToggle']\"").status === 0,
                  "the sound toggle first in the sliding row")
            waitFor(function() { return soundEffects().length === 1 }, 5000, "with it, one SoundEffect", function() {
                var effect = soundEffects()[0]
                expectEqual(String(effect.source), "file:///usr/share/sounds/notification.wav", "the unmute sound, as it was")
                expectEqual(effect.volume, 0.8, "at 0.8")
                check(sh("dconf load /desktop/asteroid/quickpanel/ < /src/sonic/test/quickpanel-user.ini").status === 0,
                      "the watch's settings again")
                waitFor(function() { return soundEffects().length === 0 }, 5000, "and none again", done)
            })
        },

        function(done) {
            sheet.title = "The quick panel's Find phone button, and the bell"
            sheet.files = files
            sheet.labels = labels
            after(300, function() { shot("quickpanel-sheet", done, sheet) })
        }
    ]
}
