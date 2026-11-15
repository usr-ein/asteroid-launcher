/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The focus-fake scene of sonic/test/test.sh, run on request, not with the
 * others: the quick panel's Focus button and picker against the main repo's
 * contract fake, `fakeioslink focus` (ioslink/cmd/fakeioslink/focus.go),
 * which serves the Focus interface through godbus and busapi, as ioslink
 * does, where the quickpanel scene's stand-in is Qt's. It checks what a
 * stand-in of the same hand can't: that Nemo.DBus reads what godbus exports
 * (State, through Properties.GetAll, and its PropertiesChanged after Pick and
 * Follow), and that NotFound comes back for an id the table lacks; and the
 * fake's four scenarios on the panel: work, picked, notable and nothing.
 *
 * The fork can't build the fake, which is the main repo's Go. Build it for
 * the test container, a 32-bit ARM Linux, and put it where the container sees
 * the test's output folder:
 *
 *   (cd <main repo>/ioslink && GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
 *       go build -o <fork>/sonic/out/test/fakeioslink ./cmd/fakeioslink)
 *   sonic/test/test.sh focus-fake
 *
 * Without it the scene says so, and passes.
 */
import QtQuick 2.9
import org.asteroid.controls 1.0
import "qrc:/qml/"
import "stubs/missing/Nemo/Ngf/plays.js" as Plays

Scene {
    id: desktop

    // Whether the fake is in the container, at /out.
    readonly property bool available: test.sh("test -x /out/fakeioslink").status === 0
    readonly property string icons: "/tmp/focus-icons"

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
        title: "The quick panel's Focus against the real fakeioslink focus"
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

    function findAll(item, predicate, found) {
        found = found || []
        if (predicate(item))
            found.push(item)
        for (var i = 0; i < item.children.length; i++)
            findAll(item.children[i], predicate, found)
        return found
    }

    function named(name) {
        return find(panel, function(item) { return item.objectName === name })
    }

    function watchFocus() { return named("focus") }
    function picker() { return named("focusPicker") }
    function rows() {
        return findAll(panel, function(item) { return item.objectName === "focusRow" })
    }
    function row(name) {
        return rows().filter(function(r) { return r.name === name })[0]
    }

    function slidingRow() {
        return find(panel, function(item) { return item.orientation === ListView.Horizontal && item.interactive === true })
    }

    function middle(item) {
        return item.mapToItem(null, item.width / 2, item.height / 2)
    }

    function tap(item) {
        var at = middle(item)
        test.touch("press", at.x, at.y)
        test.touch("release", at.x, at.y)
    }

    function openPicker(then) {
        tap(named("focusButton"))
        waitFor(function() { return picker().open }, 3000, "the picker opens", then)
    }

    function closePicker(then) {
        tap(named("focusPickerTitle"))
        waitFor(function() { return !picker().open }, 3000, "the picker closes", then)
    }

    // The fake, started with these flags; the old one goes first.
    function startFake(flags, ready, then) {
        var wasUp = watchFocus().available
        sh("[ -f /tmp/fake.pid ] && kill $(cat /tmp/fake.pid) 2>/dev/null; rm -f /tmp/fake.out /tmp/fake.err /tmp/fake.pid; true")
        function launch() {
            sh("(/out/fakeioslink focus " + flags + " >/tmp/fake.out 2>/tmp/fake.err </dev/null & echo $! >/tmp/fake.pid); true")
            waitFor(function() { return sh("grep -c ready /tmp/fake.err 2>/dev/null || true").output.trim() === "1" }, 30000, "the fake says it's ready", function() {
                waitFor(function() { return watchFocus().available && ready() }, 30000,
                        "the launcher sees it on the bus and reads its State: fakeioslink focus " + flags, then)
            })
        }
        if (wasUp)
            waitFor(function() { return !watchFocus().available }, 10000, "the old fake leaves the bus", launch)
        else
            launch()
    }

    // The fake's calls, without the reads.
    function fakeLog() {
        return sh("cat /tmp/fake.out").output.split("\n").filter(function(l) { return l !== "" && l.indexOf("GetAll") !== 0 })
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
        // The iPhone in Work, as State says it through godbus.
        function(done) {
            sh("rm -rf " + icons + " && mkdir -p " + icons + " && cp /src/sonic/test/focus-icons/*.png " + icons + "/")
            slidingRow().positionViewAtIndex(1, ListView.Beginning)
            startFake("-scenario work -icons " + icons, function() { return watchFocus().current.id === "work" }, function() {
                expectEqual(sh("grep -c 'GetAll org.sonicscrewdriver.ioslink.Focus' /tmp/fake.out").output.trim(), "1",
                            "the panel read State, once, through Properties.GetAll")
                var f = watchFocus()
                expectEqual(f.current, {id: "work", name: "Work", color: "#30b0c7", base: "vibration", icon: icons + "/work.png"},
                            "current: Work, with its colour, base and icon file")
                check(!f.picked, "source: the iPhone")
                expectEqual(f.iphone, {id: "work", name: "Work"}, "iphone: Work")
                check(f.table, "table: true")
                expectEqual(f.focuses.map(function(m) { return [m.id, m.name, m.color, m.base, m.icon] }), [
                    ["", "Nothing", "#ff9f0a", "vibration", icons + "/none.png"],
                    ["dnd", "Do Not Disturb", "#5e5ce6", "silent", icons + "/dnd.png"],
                    ["work", "Work", "#30b0c7", "vibration", icons + "/work.png"],
                    ["sleep", "Sleep", "#00c7be", "silent", icons + "/sleep.png"],
                    ["antisocial", "Antisocial", "#ff453a", "vibration", icons + "/antisocial.png"]
                ], "focuses: Sam's five, in the table's order")
                expectEqual(named("focusLabel").text, "Work", "the name under the page dots")
                after(300, function() { keep("focus-fake-work", "fakeioslink focus -scenario work", done) })
            })
        },

        // A pick through the picker: Pick, and State's PropertiesChanged.
        function(done) {
            openPicker(function() {
                var before = Plays.plays.length
                tap(row("Sleep"))
                waitFor(function() { return watchFocus().picked && watchFocus().current.id === "sleep" }, 5000,
                        "State's PropertiesChanged after Pick: Sleep, picked on the watch", function() {
                    expectEqual(fakeLog(), ["Pick sleep"], "the fake heard Pick(\"sleep\")")
                    check(named("focusBadge").visible, "the watch badge")
                    expectEqual(named("focusLabel").text, "Sleep · on the watch", "\"Sleep · on the watch\"")
                    after(400, function() {
                        expectEqual(Plays.plays.length, before, "Sleep is silent: no press")
                        waitFor(function() { return !named("focusConfirmation").visible }, 4000, "the confirmation gone", function() {
                            after(300, function() { keep("focus-fake-picked", "Pick(\"sleep\"): the badge", done) })
                        })
                    })
                })
            })
        },

        // Follow, through the picker.
        function(done) {
            openPicker(function() {
                expectEqual(rows()[0].name, "Follow iPhone", "Follow iPhone first")
                expectEqual(rows()[0].detail, "Work", "with the iPhone's Work")
                tap(row("Follow iPhone"))
                waitFor(function() { return !watchFocus().picked && watchFocus().current.id === "work" }, 5000,
                        "State's PropertiesChanged after Follow: the iPhone's Work", function() {
                    expectEqual(fakeLog().slice(-1), ["Follow"], "the fake heard Follow()")
                    check(!named("focusBadge").visible, "no badge")
                    done()
                })
            })
        },

        // No Focus picked: "" through godbus.
        function(done) {
            waitFor(function() { return !named("focusConfirmation").visible }, 4000, "the confirmation gone", function() {
                openPicker(function() {
                    tap(row("Nothing"))
                    waitFor(function() { return watchFocus().picked && watchFocus().current.id === "" }, 5000,
                            "No Focus picked: Nothing", function() {
                        expectEqual(fakeLog().slice(-1), ["Pick "], "the fake heard Pick(\"\")")
                        expectEqual(named("focusLabel").text, "Nothing · on the watch", "\"Nothing · on the watch\"")
                        check(String(named("focusButton").iconSource).indexOf("file://" + icons + "/none.png#") === 0,
                              "with No Focus's icon, none.png")
                        done()
                    })
                })
            })
        },

        // An id the table lacks: NotFound, through godbus.
        function(done) {
            var name = ""
            watchFocus().pick("nobody", function(error) { name = error })
            waitFor(function() { return name !== "" }, 5000, "Pick(\"nobody\") answered", function() {
                expectEqual(name, "org.sonicscrewdriver.ioslink.Focus.Error.NotFound", "with NotFound")
                expectEqual(panel.notice, "Focus not found", "\"Focus not found\"")
                expectEqual(fakeLog().slice(-1), ["Pick nobody"], "the fake heard it")
                expectEqual(watchFocus().current.id, "", "the Focus as it was")
                done()
            })
        },

        // The other scenarios.
        function(done) {
            waitFor(function() { return panel.notice === "" }, 5000, "the line gone", function() {
                startFake("-scenario picked -icons " + icons, function() { return watchFocus().picked }, function() {
                    expectEqual([watchFocus().current.id, watchFocus().iphone.id], ["sleep", "work"], "picked: Sleep over the iPhone's Work")
                    openPicker(function() {
                        expectEqual(rows().map(function(r) { return r.name }),
                                    ["Follow iPhone", "Nothing", "Do Not Disturb", "Work", "Sleep", "Antisocial"], "Follow iPhone first")
                        after(300, function() {
                            keep("focus-fake-picker", "-scenario picked: the picker", function() { closePicker(done) })
                        })
                    })
                })
            })
        },
        function(done) {
            startFake("-scenario notable -icons " + icons, function() { return !watchFocus().table }, function() {
                expectEqual(watchFocus().current, {id: "", name: "No Focus", color: "", base: "vibration", icon: ""},
                            "notable: No Focus, at vibration, no icon")
                expectEqual(named("focusButton").icon, "ios-notifications-outline", "the outline bell")
                openPicker(function() {
                    expectEqual(rows().map(function(r) { return [r.name, r.detail] }), [["No Focus", "No Focus · Vibration"]],
                                "No Focus alone")
                    check(named("focusPickerNote").visible, "and the note")
                    after(300, function() {
                        keep("focus-fake-notable", "-scenario notable: no table", function() { closePicker(done) })
                    })
                })
            })
        },
        function(done) {
            startFake("-scenario nothing -icons " + icons, function() { return watchFocus().table && watchFocus().iphone.name === "Nothing" }, function() {
                expectEqual([watchFocus().current.id, watchFocus().current.name], ["", "Nothing"], "nothing: the iPhone in No Focus, Nothing")
                expectEqual(named("focusLabel").text, "Nothing", "\"Nothing\"")
                after(300, function() { keep("focus-fake-nothing", "-scenario nothing", done) })
            })
        },

        // The fake goes away.
        function(done) {
            sh("kill $(cat /tmp/fake.pid)")
            waitFor(function() { return !watchFocus().available }, 10000, "ioslink gone", function() {
                expectEqual(named("focusLabel").text, "Focus unavailable", "\"Focus unavailable\"")
                after(300, function() { keep("focus-fake-gone", "The fake gone: unavailable", done) })
            })
        },

        function(done) {
            sheet.files = files
            sheet.labels = labels
            after(300, function() { shot("focus-fake-sheet", done, sheet) })
        }
    ])
}
