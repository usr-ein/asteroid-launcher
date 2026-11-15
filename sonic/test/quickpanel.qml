/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick panel scene of sonic/test/test.sh: the launcher's own QuickPanel,
 * compiled in, on the dark theme's black, which MainScreen's darkener makes
 * opaque behind every panel but the watch face. The system services that it
 * reads are stand-ins (stubs/); the press feedback's plays are recorded.
 * - The Find phone button, against `ioslink`, the harness's stand-in for
 *   ioslink's FindPhone interface on the test bus: first in the sliding row;
 *   "Phone not connected", and nothing called, without ioslink, without the
 *   iPhone, or without a session while it rings; lit as ioslink's Ringing,
 *   which a tap turns, with no light of its own; dark again at a tap, or
 *   when the iPhone stops; a tap that doesn't take, ring or stop, with
 *   Ringing back as it was; each of PROTOCOL.md § 6.10's lines, from Problem
 *   and from Ring()'s errors, the bus's NoReply included; an old problem not
 *   shown again after a restart of ioslink.
 * - The Focus button, in the bell's place, against the same `ioslink`'s Focus
 *   interface, with Sam's table and the five icons of focus-icons/: the
 *   iPhone's Focus (its icon file, its colour, its name under the page dots);
 *   the picker, its rows and their levels, the tick, centred; a pick (Pick
 *   called with the id; the confirmation, its line, for 1.9 s; the badge and
 *   "· on the watch" from ioslink's State; the press 125 ms later only for a
 *   base that vibrates); Follow iPhone; the iPhone's own Focus picked; No
 *   Focus with Sam's icon; closing without a pick (a right swipe, the edge's
 *   back, the title, the panel left or hidden), a scroll that picks nothing;
 *   no table; NotFound and Failed; an icon rewritten in place, read again
 *   only when the panel shows again and the picker opens; no ioslink.
 * - sonic/watch/quickpanel-findphone, against the SDK's own dconf service:
 *   with the watch's settings, which list the toggles, the button isn't
 *   there; the script puts it first, --status shows it, --undo takes it out,
 *   and the panel follows each change. The Focus button is where the bell was
 *   in the watch's lists, which stay as they are.
 * - The sound toggle's unmute sound, a SoundEffect, which opens an audio
 *   stream as soon as it's created: none with the watch's settings, which
 *   don't have the toggle; one with the toggle in the sliding row, and none
 *   again without it.
 * Screenshots: the panel; "Phone not connected"; ringing; "Allow alarms in
 * Sonic"; the Focus's states, quickpanel-focus-<state>.png; and a contact
 * sheet of them.
 */
import QtQuick 2.9
import org.asteroid.controls 1.0
import org.asteroid.utils 1.0
import "qrc:/qml/"
import "stubs/missing/Nemo/Ngf/plays.js" as Plays

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

    function findAll(item, predicate, found) {
        found = found || []
        if (predicate(item))
            found.push(item)
        for (var i = 0; i < item.children.length; i++)
            findAll(item.children[i], predicate, found)
        return found
    }

    // The Focus's parts.
    function watchFocus() { return named("focus") }
    function focusButton() { return named("focusButton") }
    function badge() { return named("focusBadge") }
    function picker() { return named("focusPicker") }
    function rows() {
        return findAll(panel, function(item) { return item.objectName === "focusRow" })
    }
    function row(name) {
        return rows().filter(function(r) { return r.name === name })[0]
    }
    function confirmation() { return named("focusConfirmation") }
    function rowDisc(name) {
        return find(row(name), function(item) { return item.objectName === "focusRowDisc" })
    }

    function hideConfirmationThen(then) {
        waitFor(function() { return !confirmation().visible }, 4000, "the confirmation gone", then)
    }
    function meter() {
        return find(panel, function(item) { return item.particleDesign !== undefined && item.valueUpperBound !== undefined })
    }

    // Sam's table, as Sonic sends it, with the icons where the scene copies
    // them: focus-icons/, which a step rewrites.
    readonly property string icons: "/tmp/focus-icons"
    readonly property var samsTable: [
        {id: "", name: "Nothing", color: "#ff9f0a", base: "vibration", icon: icons + "/none.png"},
        {id: "dnd", name: "Do Not Disturb", color: "#5e5ce6", base: "silent", icon: icons + "/dnd.png"},
        {id: "work", name: "Work", color: "#30b0c7", base: "vibration", icon: icons + "/work.png"},
        {id: "sleep", name: "Sleep", color: "#00c7be", base: "silent", icon: icons + "/sleep.png"},
        {id: "antisocial", name: "Antisocial", color: "#ff453a", base: "vibration", icon: icons + "/antisocial.png"}
    ]

    // Work's glyph in the picker, centred, before its file is rewritten.
    property real workGlyph: -1

    function presses() {
        return Plays.plays.filter(function(p) { return p.event === "press" }).length
    }

    // An item's middle, on the screen.
    function middle(item) {
        return item.mapToItem(null, item.width / 2, item.height / 2)
    }

    // A finger's tap on an item, and a swipe, through the view.
    function tap(item) {
        var at = middle(item)
        test.touch("press", at.x, at.y)
        test.touch("release", at.x, at.y)
    }

    function swipe(x0, y0, x1, y1) {
        test.touch("press", x0, y0)
        for (var i = 1; i <= 10; i++)
            test.touch("move", x0 + (x1 - x0) * i / 10, y0 + (y1 - y0) * i / 10)
        test.touch("release", x1, y1)
    }

    // The share of white in a square around a point of a screenshot: an icon.
    function whiteAround(file, at, half) {
        return test.share(file, Math.round(at.x - half), Math.round(at.y - half), Math.round(2 * half), Math.round(2 * half), "#ffffff", 60)
    }

    // An icon's glyph on its disc: the share of a square around the disc's
    // middle that isn't the disc's own colour, whatever that colour is.
    function glyphOn(file, disc, colour) {
        var at = middle(disc)
        return 1 - test.share(file, Math.round(at.x - 17), Math.round(at.y - 17), 34, 34, colour, 30)
    }

    // A disc's colour at the toggles' 0.75 on black, a little left of its
    // icon.
    function ringColour(file, item, colour) {
        var at = middle(item)
        return test.share(file, Math.round(at.x - item.width * 0.41), Math.round(at.y - 4), 8, 8, colour, 6)
    }

    function openPicker(then) {
        tap(focusButton())
        waitFor(function() { return picker().open }, 3000, "a tap on the Focus button opens the picker", then)
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

        // The Focus button, on the second page: the iPhone's Focus, Work.
        function(done) {
            sh("rm -rf " + icons + " && mkdir -p " + icons + " && cp /src/sonic/test/focus-icons/*.png " + icons + "/")
            ioslink.focusTable = samsTable
            ioslink.focusTableSent = true
            ioslink.focusIphone = "work"
            slidingRow().positionViewAtIndex(1, ListView.Beginning)
            waitFor(function() { return watchFocus().current.id === "work" && focusButton() !== null }, 5000,
                    "ioslink's State read: the iPhone in Work", function() {
                var button = focusButton()
                check(String(button.iconSource).indexOf("file://" + icons + "/work.png#") === 0,
                      "the Focus button shows Work's icon, from its file: " + button.iconSource)
                expectEqual(String(button.tint), "#30b0c7", "on Work's colour")
                check(button.checkable && button.checked, "at the toggles' 0.75")
                check(!badge().visible, "no watch badge: the iPhone's Focus")
                var label = named("focusLabel")
                expectEqual(label.text, "Work", "its name under the page dots")
                check(label.y + label.height <= meter().y, "above the battery: " + Math.round(label.y + label.height)
                      + " over " + Math.round(meter().y))
                after(300, function() {
                    keep("quickpanel-focus-iphone", "Focus: the iPhone's, Work", function() {
                        var file = shots + "/quickpanel-focus-iphone.png"
                        check(ringColour(file, button, "#248495") > 0.9, "the disc: Work's #30b0c7 at 0.75 on black")
                        check(whiteAround(file, middle(button), button.width * 0.2) > 0.2, "and its icon, white")
                        done()
                    })
                })
            })
        },

        // The picker: the table, the levels, Work ticked and centred.
        function(done) {
            openPicker(function() {
                expectEqual(rows().map(function(r) { return r.name }), ["Nothing", "Do Not Disturb", "Work", "Sleep", "Antisocial"],
                            "the table's Focuses, in its order; no Follow iPhone without a pick")
                expectEqual(rows().map(function(r) { return r.detail }),
                            ["No Focus · Vibration", "Silent", "Vibration", "Silent", "Vibration"], "each with its base level")
                expectEqual(rows().filter(function(r) { return r.ticked }).map(function(r) { return r.name }), ["Work"],
                            "the watch's Focus ticked")
                check(Math.abs(middle(row("Work")).y - desktop.height / 2) <= 2, "and centred: " + middle(row("Work")).y)
                expectEqual(named("focusPickerTitle").text, "FOCUS", "the title")
                check(panel.forbidBottom, "no swipe back to the face while it's open: the list scrolls")
                after(300, function() {
                    keep("quickpanel-focus-picker", "The picker: Work ticked, centred", function() {
                        desktop.workGlyph = glyphOn(shots + "/quickpanel-focus-picker.png", rowDisc("Work"), "#248495")
                        done()
                    })
                })
            })
        },

        // A pick: Sleep, silent.
        function(done) {
            var before = presses()
            var at = Date.now()
            tap(row("Sleep"))
            check(!picker().open, "a tap on Sleep closes the picker")
            check(confirmation().visible, "the confirmation shows")
            expectEqual(named("focusConfirmationName").text, "Sleep", "Sleep")
            expectEqual(named("focusConfirmationLine").text, "until the iPhone’s next Focus change", "until the iPhone's next change")
            keep("quickpanel-focus-confirm", "A pick: Sleep, until the iPhone's next change", function() {
                waitFor(function() { return watchFocus().picked && watchFocus().current.id === "sleep" }, 3000,
                        "ioslink's State: Sleep, picked on the watch", function() {
                    expectEqual(ioslink.focusCalls, ["Pick sleep"], "the tap called Pick(\"sleep\")")
                    check(badge().visible, "the watch badge")
                    expectEqual(named("focusLabel").text, "Sleep · on the watch", "\"Sleep · on the watch\"")
                    expectEqual(String(focusButton().tint), "#00c7be", "on Sleep's colour")
                    after(400, function() {
                        expectEqual(presses(), before, "Sleep is silent: no press")
                        waitFor(function() { return !confirmation().visible }, 4000, "the confirmation goes", function() {
                            var shown = Date.now() - at
                            check(shown >= 1800 && shown < 3500, "after about 1.9 s: " + shown + " ms")
                            after(300, function() {
                                keep("quickpanel-focus-picked", "Sleep picked on the watch: the badge", function() {
                                    var file = shots + "/quickpanel-focus-picked.png"
                                    check(ringColour(file, focusButton(), "#00958f") > 0.9, "the disc: Sleep's #00c7be at 0.75")
                                    var b = badge().mapToItem(null, badge().width / 2, badge().height / 2)
                                    check(test.share(file, Math.round(b.x - 3), Math.round(b.y - 12), 6, 3, "#e8ecf2", 8) > 0.5,
                                          "the badge's light disc, bottom right")
                                    done()
                                })
                            })
                        })
                    })
                })
            })
        },

        // A pick that vibrates, from a pick: Follow iPhone first.
        function(done) {
            openPicker(function() {
                expectEqual(rows().map(function(r) { return r.name }),
                            ["Follow iPhone", "Nothing", "Do Not Disturb", "Work", "Sleep", "Antisocial"], "Follow iPhone first, while a pick holds")
                expectEqual(rows()[0].detail, "Work", "with the iPhone's Focus under it")
                expectEqual(rows().filter(function(r) { return r.ticked }).map(function(r) { return r.name }), ["Sleep"], "Sleep ticked")
                check(Math.abs(middle(row("Sleep")).y - desktop.height / 2) <= 2, "and centred: " + middle(row("Sleep")).y)
                after(300, function() {
                    keep("quickpanel-focus-picker-picked", "The picker over a pick: Follow iPhone", function() {
                        var before = presses()
                        var at = Date.now()
                        tap(row("Antisocial"))
                        waitFor(function() { return presses() === before + 1 }, 3000, "Antisocial vibrates: the press", function() {
                            var played = Plays.plays[Plays.plays.length - 1].at - at
                            check(played >= 110 && played < 1500, "played 125 ms after the tap: " + played + " ms")
                            waitFor(function() { return watchFocus().current.id === "antisocial" }, 3000, "Antisocial, picked", function() {
                                expectEqual(ioslink.focusCalls.slice(-1), ["Pick antisocial"], "the tap on Antisocial called Pick(\"antisocial\")")
                                expectEqual(named("focusLabel").text, "Antisocial · on the watch", "\"Antisocial · on the watch\"")
                                after(500, function() {
                                    expectEqual(presses(), before + 1, "one press")
                                    done()
                                })
                            })
                        })
                    })
                })
            })
        },

        // The iPhone's own Focus, picked: following the iPhone again.
        function(done) {
            waitFor(function() { return !confirmation().visible }, 4000, "the confirmation gone", function() {
                openPicker(function() {
                    var before = presses()
                    tap(row("Work"))
                    expectEqual(named("focusConfirmationLine").text, "the iPhone’s Focus", "\"the iPhone's Focus\"")
                    waitFor(function() { return !watchFocus().picked && watchFocus().current.id === "work" }, 3000,
                            "ioslink follows the iPhone again", function() {
                        expectEqual(ioslink.focusCalls.slice(-1), ["Pick work"], "the tap on Work, the iPhone's, called Pick(\"work\")")
                        check(!badge().visible, "no badge")
                        expectEqual(named("focusLabel").text, "Work", "\"Work\"")
                        waitFor(function() { return presses() === before + 1 }, 3000, "Work vibrates: the press", done)
                    })
                })
            })
        },

        // Follow iPhone, after a silent pick.
        function(done) {
            waitFor(function() { return !confirmation().visible }, 4000, "the confirmation gone", function() {
                openPicker(function() {
                    var before = presses()
                    tap(row("Do Not Disturb"))
                    waitFor(function() { return watchFocus().picked && watchFocus().current.id === "dnd" }, 3000,
                            "Do Not Disturb picked", function() {
                        after(400, function() {
                            expectEqual(presses(), before, "silent: no press")
                            hideConfirmationThen(function() {
                                openPicker(function() {
                                    tap(row("Follow iPhone"))
                                    expectEqual(named("focusConfirmationName").text, "Work", "the confirmation: the iPhone's Work")
                                    expectEqual(named("focusConfirmationLine").text, "following the iPhone again", "\"following the iPhone again\"")
                                    keep("quickpanel-focus-follow", "Follow iPhone: Work again", function() {
                                        waitFor(function() { return !watchFocus().picked && watchFocus().current.id === "work" }, 3000,
                                                "ioslink's State: the iPhone's Work", function() {
                                            expectEqual(ioslink.focusCalls.slice(-1), ["Follow"], "the tap on Follow iPhone called Follow()")
                                            check(!badge().visible, "no badge")
                                            expectEqual(named("focusLabel").text, "Work", "\"Work\"")
                                            waitFor(function() { return presses() === before + 1 }, 3000,
                                                    "Work vibrates: the press, after Follow too", done)
                                        })
                                    })
                                })
                            })
                        })
                    })
                })
            })
        },

        // The iPhone in No Focus: Sam's Nothing, with its own icon and colour.
        function(done) {
            hideConfirmationThen(function() {
                ioslink.focusIphone = ""
                waitFor(function() { return watchFocus().current.name === "Nothing" }, 3000, "the iPhone in No Focus", function() {
                    check(String(focusButton().iconSource).indexOf("file://" + icons + "/none.png#") === 0, "No Focus's icon from Sonic")
                    expectEqual(String(focusButton().tint), "#ff9f0a", "and colour")
                    expectEqual(named("focusLabel").text, "Nothing", "Sam's name for it")
                    after(300, function() {
                        keep("quickpanel-focus-nothing", "No Focus, as Sam named it: Nothing", function() {
                            ioslink.focusIphone = "work"
                            waitFor(function() { return watchFocus().current.id === "work" }, 3000, "the iPhone in Work again", done)
                        })
                    })
                })
            })
        },

        // Closing without a pick.
        function(done) {
            var calls = ioslink.focusCalls.length
            var before = presses()
            test.log("     DeviceSpecs.borderGestureWidth: " + DeviceSpecs.borderGestureWidth)
            var ways = [
                ["a right swipe across the list", function() { swipe(200, 300, 420, 310) }],
                ["a right swipe over a Focus", function() { var at = middle(row("Work")); swipe(at.x - 60, at.y, at.x + 140, at.y + 4) }],
                ["AsteroidOS's back, from the left edge", function() { swipe(2, 227, 300, 232) }],
                ["a tap on the title", function() { tap(named("focusPickerTitle")) }],
                ["the panel left", function() { grid.currentVerticalPos = 0 }],
                ["the panel hidden", function() { panel.visible = false }]
            ]
            function one() {
                if (ways.length === 0) {
                    expectEqual(ioslink.focusCalls.length, calls, "none of them called ioslink")
                    expectEqual(presses(), before, "or played a press")
                    done()
                    return
                }
                var way = ways.shift()
                openPicker(function() {
                    way[1]()
                    waitFor(function() { return !picker().open }, 3000, way[0] + " closes the picker", function() {
                        check(!panel.forbidBottom, "and the panel's swipes are back")
                        // Back on the panel, which shows its first page then.
                        grid.currentVerticalPos = -1
                        panel.visible = true
                        slidingRow().positionViewAtIndex(1, ListView.Beginning)
                        after(300, one)
                    })
                })
            }
            // A scroll first: it neither closes nor picks.
            openPicker(function() {
                swipe(227, 400, 232, 150)
                after(500, function() {
                    check(picker().open, "a scroll of the list leaves the picker open")
                    expectEqual(ioslink.focusCalls.length, calls, "and picks nothing")
                    tap(named("focusPickerTitle"))
                    waitFor(function() { return !picker().open }, 3000, "closed", function() { after(300, one) })
                })
            })
        },

        // No table from Sonic yet: No Focus alone, at the bell's level.
        function(done) {
            ioslink.focusTableSent = false
            waitFor(function() { return watchFocus().available && !watchFocus().table }, 3000, "no table", function() {
                var button = focusButton()
                expectEqual(String(button.iconSource), "", "the button: no icon")
                expectEqual(button.icon, "ios-notifications-outline", "the outline bell")
                check(!button.checkable && String(button.tint) === "#2b2f36", "on the toggles' grey")
                expectEqual(named("focusLabel").text, "No Focus", "\"No Focus\"")
                openPicker(function() {
                    expectEqual(rows().map(function(r) { return [r.name, r.detail, r.ticked] }),
                                [["No Focus", "No Focus · Vibration", true]], "the picker: No Focus alone, ticked")
                    var note = named("focusPickerNote")
                    check(note.visible, "with the note")
                    expectEqual(note.text, "Set up Focus in Sonic, on the iPhone.", "\"Set up Focus in Sonic, on the iPhone.\"")
                    after(300, function() {
                        keep("quickpanel-focus-notable", "No table yet: No Focus alone", function() {
                            tap(named("focusPickerTitle"))
                            ioslink.focusTableSent = true
                            waitFor(function() { return !picker().open && watchFocus().table && watchFocus().current.id === "work" }, 3000,
                                    "the table again", done)
                        })
                    })
                })
            })
        },

        // A Focus gone from the table meanwhile: NotFound; and Failed.
        function(done) {
            ioslink.focusAnswer = "notfound"
            openPicker(function() {
                var before = presses()
                tap(row("Antisocial"))
                waitFor(function() { return panel.notice !== "" }, 3000, "an answer", function() {
                    expectEqual(panel.notice, "Focus not found", "NotFound: \"Focus not found\"")
                    check(!confirmation().visible, "the confirmation taken back")
                    after(400, function() {
                        expectEqual(presses(), before, "and no press")
                        expectEqual(watchFocus().current.id, "work", "the Focus as it was")
                        keep("quickpanel-focus-notfound", "NotFound: \"Focus not found\"", function() {
                            ioslink.focusAnswer = "failed"
                            waitFor(function() { return panel.notice === "" }, 5000, "the line gone", function() {
                                openPicker(function() {
                                    tap(row("Sleep"))
                                    waitFor(function() { return panel.notice !== "" }, 3000, "an answer", function() {
                                        expectEqual(panel.notice, "Focus didn't change", "Failed: \"Focus didn't change\"")
                                        ioslink.focusAnswer = "ok"
                                        waitFor(function() { return panel.notice === "" }, 5000, "the line gone", done)
                                    })
                                })
                            })
                        })
                    })
                })
            })
        },

        // An icon rewritten in place, under the same path, with the same State.
        function(done) {
            var button = focusButton()
            var at = middle(button)
            var half = Math.round(button.width * 0.27)
            var area = [Math.round(at.x - half), Math.round(at.y - half), 2 * half, 2 * half]
            function differs(a, b) {
                return test.difference(shots + "/" + a + ".png", shots + "/" + b + ".png", area[0], area[1], area[2], area[3])
            }
            shot("quickpanel-focus-reload-before", function() {
                check(sh("cp /src/sonic/test/focus-icons/antisocial.png " + icons + "/work.png").status === 0,
                      "Work's icon file rewritten with Antisocial's")
                after(500, function() {
                    shot("quickpanel-focus-reload-stale", function() {
                        check(differs("quickpanel-focus-reload-before", "quickpanel-focus-reload-stale") < 1,
                              "nothing tells the launcher: the old icon stays")
                        panel.visible = false
                        panel.visible = true
                        after(500, function() {
                            keep("quickpanel-focus-reloaded", "An icon rewritten: read again", function() {
                                var d = differs("quickpanel-focus-reload-before", "quickpanel-focus-reloaded")
                                check(d > 8, "the panel shown again reads it again: the new icon (" + d.toFixed(1) + " apart)")
                                openPicker(function() {
                                    after(300, function() {
                                        shot("quickpanel-focus-reload-picker", function() {
                                            // Work's row centred, then Antisocial's, away from the round edge.
                                            var work = glyphOn(shots + "/quickpanel-focus-reload-picker.png", rowDisc("Work"), "#248495")
                                            var list = named("focusPickerList")
                                            list.contentY += middle(rowDisc("Antisocial")).y - desktop.height / 2
                                            after(300, function() {
                                                shot("quickpanel-focus-reload-antisocial", function() {
                                                    var antisocial = glyphOn(shots + "/quickpanel-focus-reload-antisocial.png",
                                                                             rowDisc("Antisocial"), "#bf342c")
                                                    check(Math.abs(work - antisocial) < 0.05 && Math.abs(desktop.workGlyph - antisocial) > 0.15,
                                                          "and the picker, opened: Work's row has the new icon, its glyph " + work.toFixed(3)
                                                          + " of the disc as Antisocial's " + antisocial.toFixed(3) + "; it was "
                                                          + desktop.workGlyph.toFixed(3))
                                                    tap(named("focusPickerTitle"))
                                                    sh("cp /src/sonic/test/focus-icons/work.png " + icons + "/work.png")
                                                    panel.visible = false
                                                    panel.visible = true
                                                    done()
                                                })
                                            })
                                        })
                                    })
                                })
                            })
                        })
                    })
                })
            })
        },

        // No ioslink: dimmed, the outline bell, and the picker says why.
        function(done) {
            ioslink.stop()
            waitFor(function() { return !watchFocus().available }, 5000, "ioslink gone", function() {
                var button = focusButton()
                expectEqual(String(button.iconSource), "", "the button: no icon")
                expectEqual(button.icon, "ios-notifications-outline", "the outline bell")
                check(button.checkable && !button.checked && String(button.tint) === "#2b2f36", "dimmed, on the toggles' grey")
                check(!badge().visible, "no badge")
                expectEqual(named("focusLabel").text, "Focus unavailable", "\"Focus unavailable\"")
                after(300, function() {
                    keep("quickpanel-focus-unavailable", "No ioslink: dimmed", function() {
                        check(ringColour(shots + "/quickpanel-focus-unavailable.png", button, "#16181b") > 0.9, "the disc: grey at 0.5")
                        openPicker(function() {
                            check(named("focusPickerAway").visible && !named("focusPickerList").visible, "the picker says why")
                            expectEqual(named("focusPickerAwayLine").text, "Focus needs ioslink, which isn't running.",
                                        "\"Focus needs ioslink, which isn't running.\"")
                            after(300, function() {
                                keep("quickpanel-focus-away", "No ioslink: the picker", function() {
                                    tap(named("focusPickerAwayLine"))
                                    waitFor(function() { return !picker().open }, 3000, "a tap closes it", function() {
                                        check(ioslink.start(), "ioslink back")
                                        waitFor(function() { return watchFocus().available && watchFocus().current.id === "work" }, 5000,
                                                "and its Focus with it", function() {
                                            slidingRow().positionViewAtIndex(0, ListView.Beginning)
                                            done()
                                        })
                                    })
                                })
                            })
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
                var button = focusButton()
                check(button !== null, "the Focus button is in the watch's lists, under the bell's key")
                var row = slidingRow()
                row.positionViewAtBeginning()
                var at = row.mapFromItem(button, button.width / 2, button.height / 2)
                check(at.x > row.width / 3 && at.x < 2 * row.width / 3, "where the bell was: the middle of the first page")
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
            sheet.title = "The quick panel's Find phone button, and its Focus button and picker"
            sheet.files = files
            sheet.labels = labels
            after(300, function() { shot("quickpanel-sheet", done, sheet) })
        }
    ]
}
