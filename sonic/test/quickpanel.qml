/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick panel scene of sonic/test/test.sh: the launcher's own QuickPanel,
 * compiled in, on the dark theme's black, which MainScreen's darkener makes
 * opaque behind every panel but the watch face. The system services that it
 * reads are stand-ins (stubs/), with the alert profile on "general".
 * - The Find phone button, against `ioslink`, the harness's stand-in for
 *   ioslink's FindPhone interface on the test bus: first in the sliding row;
 *   "Phone not connected" without ioslink or without the iPhone; lit while
 *   the iPhone rings, from the tap on; dark again at a tap, or when the
 *   iPhone stops; "Allow alarms in Sonic" for CODE_DENIED; dark again
 *   without an answer; an old problem not shown again after a restart of
 *   ioslink.
 * - The bell: general, silent, outdoors.
 * - sonic/watch/quickpanel-findphone, against the SDK's own dconf service:
 *   with the watch's settings, which list the toggles, the button isn't
 *   there; the script puts it first, --status shows it, --undo takes it out,
 *   and the panel follows each change.
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
                check(button.checked, "a tap lights the button at once")
                expectEqual(panel.notice, "", "and clears that line")
                after(300, function() {
                    check(ioslink.rings === 1 && ioslink.ringing, "and calls Ring(): ioslink's Ringing at once")
                    after(300, function() {
                        check(button.checked, "lit while the iPhone rings")
                        keep("quickpanel-ringing", "The iPhone rings: lit", function() {
                            button.clicked(null)
                            check(!button.checked, "a tap while it rings: dark at once")
                            after(300, function() {
                                check(ioslink.stops === 1 && !ioslink.ringing, "and Stop()")
                                check(!button.checked, "and dark")
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

        // CODE_DENIED: AlarmKit not allowed in Sonic.
        function(done) {
            ioslink.answer = "denied"
            named("findPhoneButton").clicked(null)
            waitFor(function() { return panel.notice !== "" }, 3000, "an answer", function() {
                expectEqual(panel.notice, "Allow alarms in Sonic", "AlarmKit not allowed: \"Allow alarms in Sonic\"")
                check(!named("findPhoneButton").checked, "and dark")
                keep("quickpanel-denied", "Not allowed: \"Allow alarms in Sonic\"", done)
            })
        },

        // The other problems of PROTOCOL.md § 6.10, each in its turn.
        function(done) {
            var problems = [["unavailable", "Unlock your iPhone first"], ["timeout", "Phone didn't answer"],
                            ["notconnected", "Phone not connected"]]
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
                        expectEqual(panel.notice, p[1], p[0] + ": \"" + p[1] + "\"")
                        check(!named("findPhoneButton").checked, "and dark")
                        one()
                    })
                })
            }
            one()
        },

        // No answer: dark again after 5 s.
        function(done) {
            waitFor(function() { return panel.notice === "" }, 5000, "the line gone", function() {
                ioslink.answer = "none"
                var button = named("findPhoneButton")
                button.clicked(null)
                check(button.checked, "a tap that gets no answer: lit")
                waitFor(function() { return !button.checked }, 7000, "dark again without an answer", done)
            })
        },

        // ioslink restarts: its last problem, old by then, isn't shown again.
        function(done) {
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

        function(done) {
            sheet.title = "The quick panel's Find phone button, and the bell"
            sheet.files = files
            sheet.labels = labels
            after(300, function() { shot("quickpanel-sheet", done, sheet) })
        }
    ]
}
