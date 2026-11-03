/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The app list scene of sonic/test/test.sh: the fork's horizontal app list,
 * compiled in, over lipstick's real LauncherModel and the watch's apps
 * (run.sh), set up as MainScreen sets it up (AppList.qml). It checks:
 *   - the order: Check-in first, then the PRD's apps, then the others by
 *     title;
 *   - that lipstick itself honours no override, in ~/.local/share/applications
 *     or in /usr/local/share/applications, and that AppListModel honours both;
 *   - sonic/watch/hide-apps: hiding the four apps, --status, --show and --undo,
 *     each seen by the list at once, and an override it didn't write left
 *     alone;
 *   - that the list goes back to its first app once left for the watch face,
 *     and keeps its page when brought back at once;
 *   - the look: each of the eight apps shows its own logo (sonic/icons/), read
 *     back from the screenshot by its colours, any other app the stock
 *     drawing in the dark theme's grey, and the names in sentence case.
 * Screenshots: each page, with every app and with the four hidden, and a
 * contact sheet of each.
 */
import QtQuick 2.9
import org.asteroid.controls 1.0
import org.asteroid.launcher 1.0
import "qrc:/qml/"

Scene {
    id: desktop

    // What the app list reads from MainScreen.
    AppLauncherBackground { id: alb }
    property color launcherCenterColor
    property color launcherOuterColor
    property bool launcherColorOverride
    property bool toTopAllowed
    property bool toBottomAllowed
    property bool toLeftAllowed
    property bool toRightAllowed
    property bool forbidTop
    property bool forbidBottom
    property bool forbidLeft
    property bool forbidRight
    QtObject {
        id: localeManager
        property string changesObserver: ""
    }
    QtObject {
        id: grid
        property int currentVerticalPos: 1
        function changeAllowedDirections() { }
    }
    QtObject { id: rightIndicator; function animate() { } }
    QtObject { id: leftIndicator; function animate() { } }
    QtObject { id: topIndicator; function animate() { } }
    QtObject { id: bottomIndicator; function animate() { } }

    AppList { id: launcherModel }
    // lipstick's own model, under AppListModel.
    readonly property var allApps: launcherModel.sourceModel

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Loader {
        id: appLauncher
        anchors.fill: parent
        source: "qrc:/qml/applauncher/000-default-horizontal.qml"
    }

    ContactSheet {
        id: sheet
        x: desktop.width + 100
    }

    // Heart Rate, Timer, Stopwatch and Weather in the order are
    // sonic-heartrate, sonic-timer, sonic-stopwatch and sonic-weather; the
    // stock asteroid-hrm, asteroid-stopwatch, asteroid-timer and
    // asteroid-weather follow the others by title.
    readonly property var everyApp: [
        "Check-in", "Alarm Clock", "Heart Rate", "Timer", "Stopwatch", "Weather",
        "Flashlight", "Diamonds", "Agenda", "Calculator", "Heart Rate", "Music", "Settings", "Stopwatch", "Timer", "Weather"
    ]
    readonly property var everyName: [
        "Check-in", "Alarm clock", "Heart rate", "Timer", "Stopwatch", "Weather",
        "Flashlight", "Diamonds", "Agenda", "Calculator", "Heart rate", "Music", "Settings", "Stopwatch", "Timer", "Weather"
    ]
    // Each logo's main colours, which its page must show; the stock drawing's
    // grey for the apps without one.
    readonly property var logoColours: {
        "sonic-checkin": ["#2fd3b8"],
        "asteroid-alarmclock": ["#ff9f0a"],
        "sonic-heartrate": ["#ff453a", "#0a84ff"],
        "asteroid-hrm": ["#ff453a"],
        "sonic-timer": ["#ffd60a"],
        "sonic-stopwatch": ["#30d158"],
        "asteroid-timer": ["#ffd60a"],
        "asteroid-stopwatch": ["#30d158"],
        "sonic-weather": ["#1460c8"],
        "asteroid-weather": ["#1460c8"],
        "asteroid-flashlight": ["#2a2d33"],
        // the gem's facets
        "asteroid-diamonds": ["#bf5af2", "#a447d6", "#8a35bb", "#d68cff", "#e8b8ff", "#c172ee"]
    }
    readonly property var stockGrey: ["#262a31"]
    readonly property int logoRole: 256 + 64  // AppListModel::LogoRole, Qt::UserRole + 64
    readonly property string hideApps: "sh /src/sonic/watch/hide-apps"
    readonly property string userApps: "/home/ceres/.local/share/applications"

    function titles(model) {
        var list = []
        for (var i = 0; i < model.itemCount; i++)
            list.push(model.get(i).title)
        return list
    }

    function lipstickPaths() {
        var list = []
        for (var i = 0; i < allApps.itemCount; i++)
            list.push(allApps.get(i).filePath)
        return list.sort()
    }

    function listView() {
        var item = appLauncher.item
        for (var i = 0; i < item.children.length; i++) {
            if (item.children[i].orientation === ListView.Horizontal)
                return item.children[i]
        }
        return null
    }

    function desktopId(row) {
        var path = launcherModel.get(row).filePath
        return path.substring(path.lastIndexOf("/") + 1).replace(/\.desktop$/, "")
    }

    // The name a page shows, from its delegate's label.
    function shownName(view) {
        var page = view.itemAt(view.contentX + view.width / 2, view.height / 2)
        for (var i = 0; page && i < page.children.length; i++) {
            if (page.children[i].text !== undefined)
                return page.children[i].text
        }
        return null
    }

    // Every page of the list, then their contact sheet. Each page's logo is
    // read back from its screenshot: its main colour, or the stock grey,
    // covers a good part of the logo's middle.
    function pages(prefix, title, done) {
        var view = listView()
        var files = [], labels = [], names = []
        var page = 0
        function one() {
            if (page === launcherModel.itemCount) {
                expectEqual(names, everyName.slice(0, names.length), prefix + ": the names, in sentence case")
                view.contentX = 0
                sheet.title = title
                sheet.files = files
                sheet.labels = labels
                after(300, function() { shot(prefix, done, sheet) })
                return
            }
            view.contentX = page * view.width
            after(250, function() {
                var name = prefix + "-" + (page < 9 ? "0" : "") + (page + 1)
                var file = shots + "/" + name + ".png"
                files.push(file)
                labels.push((page + 1) + ". " + launcherModel.get(page).title)
                names.push(shownName(view))
                shot(name, function() {
                    var id = desktopId(page)
                    var colours = logoColours[id] || stockGrey
                    var share = 0
                    for (var c = 0; c < colours.length; c++)
                        share += test.share(file, 100, 80, 254, 254, colours[c], 12)
                    check(share > 0.04, name + ": " + (logoColours[id] ? "the logo of " + id : "the stock drawing")
                          + " shows, " + colours.join(" ") + " on " + Math.round(share * 100) + " % of its middle")
                    page++
                    one()
                })
            })
        }
        one()
    }

    steps: [
        function(done) {
            check(listView() !== null, "the compiled-in horizontal list loads")
            expectEqual(titles(launcherModel), everyApp, "the order: Check-in, the PRD's apps, then the others by title")
            check(allApps.itemCount === 16, "lipstick lists the 16 apps; sonic-health has NoDisplay=true")
            expectEqual(launcherModel.hiddenApps, [], "no override yet")
            var logos = []
            for (var i = 0; i < launcherModel.itemCount; i++)
                logos.push(launcherModel.data(launcherModel.index(i, 0), logoRole))
            expectEqual(logos, [
                "qrc:/sonic/icons/sonic-checkin.svg", "qrc:/sonic/icons/asteroid-alarmclock.svg",
                "qrc:/sonic/icons/sonic-heartrate.svg", "qrc:/sonic/icons/sonic-timer.svg",
                "qrc:/sonic/icons/sonic-stopwatch.svg", "qrc:/sonic/icons/sonic-weather.svg",
                "qrc:/sonic/icons/asteroid-flashlight.svg", "qrc:/sonic/icons/asteroid-diamonds.svg",
                "", "", "qrc:/sonic/icons/asteroid-hrm.svg", "", "", "qrc:/sonic/icons/asteroid-stopwatch.svg",
                "qrc:/sonic/icons/asteroid-timer.svg", "qrc:/sonic/icons/asteroid-weather.svg"
            ], "the logo role: the eight apps' own logos, the stock Heart Rate's, Stopwatch's, Timer's and Weather's too, none for the others")
            done()
        },
        function(done) { pages("applist-all", "The app list, every app: Check-in first; Agenda, Calculator, Music and Settings have no logo of their own", done) },

        // lipstick ignores an override in ~/.local/share/applications; AppListModel doesn't.
        function(done) {
            sh("mkdir -p " + userApps + " && printf '[Desktop Entry]\\nType=Application\\nName=Music\\n"
               + "Exec=asteroid-music\\nNoDisplay=true\\n' > " + userApps + "/asteroid-music.desktop")
            waitFor(function() { return launcherModel.itemCount === 15 }, 5000,
                    "an override in ~/.local/share/applications hides Music from the list", done)
        },
        // lipstick's monitor reports changes after 2 s.
        function(done) { after(3000, done) },
        function(done) {
            check(lipstickPaths().indexOf("/usr/share/applications/asteroid-music.desktop") >= 0
                  && allApps.itemCount === 16,
                  "lipstick's own model still lists /usr/share/applications/asteroid-music.desktop")
            sh("rm " + userApps + "/asteroid-music.desktop")
            waitFor(function() { return launcherModel.itemCount === 16 }, 5000,
                    "deleting it brings Music back", done)
        },

        // sonic/watch/hide-apps, with the default eight.
        function(done) {
            var result = sh(hideApps)
            check(result.status === 0, "hide-apps exits 0")
            expectEqual(result.output.trim().split("\n"), [
                "hidden: asteroid-music (Music)",
                "hidden: asteroid-calculator (Calculator)",
                "hidden: asteroid-calendar (Agenda)",
                "hidden: asteroid-settings (Settings)",
                "hidden: asteroid-weather (Weather)",
                "hidden: asteroid-timer (Timer)",
                "hidden: asteroid-stopwatch (Stopwatch)",
                "hidden: asteroid-hrm (Heart Rate)"
            ], "hide-apps says what it hid")
            waitFor(function() { return launcherModel.itemCount === 8 }, 5000,
                    "the list drops the eight at once", done)
        },
        function(done) { after(3000, done) },
        function(done) {
            expectEqual(titles(launcherModel), everyApp.slice(0, 8), "the list: the PRD's eight, in order")
            expectEqual(launcherModel.hiddenApps,
                        ["asteroid-calculator", "asteroid-calendar", "asteroid-hrm", "asteroid-music", "asteroid-settings",
                         "asteroid-stopwatch", "asteroid-timer", "asteroid-weather"],
                        "AppListModel reads the eight overrides")
            check(allApps.itemCount === 16, "lipstick's own model still lists all 16: it ignores /usr/local/share/applications")
            var status = sh(hideApps + " --status")
            expectEqual(status.output.trim().split("\n"), [
                "hidden: asteroid-calculator",
                "hidden: asteroid-calendar",
                "hidden: asteroid-hrm",
                "hidden: asteroid-music",
                "hidden: asteroid-settings",
                "hidden: asteroid-stopwatch",
                "hidden: asteroid-timer",
                "hidden: asteroid-weather"
            ], "hide-apps --status lists them")
            check(sh("grep -c . /usr/share/applications/asteroid-music.desktop").status === 0
                  && sh("! grep -q NoDisplay /usr/share/applications/asteroid-music.desktop").status === 0,
                  "the stock .desktop files are untouched")
            done()
        },
        function(done) { pages("applist-hidden", "The app list with Music, Calculator, Agenda, Settings, and the stock Weather, Timer, Stopwatch and Heart Rate hidden", done) },

        function(done) {
            var result = sh(hideApps + " --show asteroid-settings")
            expectEqual(result.output.trim(), "shown: asteroid-settings", "hide-apps --show says so")
            waitFor(function() { return launcherModel.itemCount === 9 }, 5000,
                    "--show brings Settings back", done)
        },
        function(done) {
            expectEqual(titles(launcherModel), everyApp.slice(0, 8).concat(["Settings"]),
                        "Settings comes back after the PRD's eight")
            // An override that hide-apps didn't write: --undo leaves it.
            sh("printf '[Desktop Entry]\\nType=Application\\nName=Diamonds\\nExec=asteroid-diamonds\\n"
               + "NoDisplay=true\\n' > /usr/local/share/applications/asteroid-diamonds.desktop")
            waitFor(function() { return launcherModel.itemCount === 8 }, 5000,
                    "a hand-written override hides Diamonds", done)
        },
        function(done) {
            var refused = sh(hideApps + " --show asteroid-diamonds")
            check(refused.status !== 0, "hide-apps --show refuses an override it didn't write")
            var result = sh(hideApps + " --undo")
            expectEqual(result.output.trim().split("\n").sort(),
                        ["shown: asteroid-calculator", "shown: asteroid-calendar", "shown: asteroid-hrm", "shown: asteroid-music",
                         "shown: asteroid-stopwatch", "shown: asteroid-timer", "shown: asteroid-weather"],
                        "hide-apps --undo removes its own overrides")
            waitFor(function() { return launcherModel.itemCount === 15 }, 5000,
                    "--undo brings back all but Diamonds", done)
        },
        function(done) {
            check(sh("test -f /usr/local/share/applications/asteroid-diamonds.desktop").status === 0,
                  "--undo left the hand-written override")
            sh("rm /usr/local/share/applications/asteroid-diamonds.desktop")
            waitFor(function() { return launcherModel.itemCount === 16 }, 5000,
                    "every app is back", done)
        },
        function(done) {
            sh(hideApps + " --undo")
            check(sh("test -e /usr/local/share/applications").status !== 0,
                  "--undo removes the empty override directory")
            // The directory comes back: the model must watch it again.
            sh(hideApps + " asteroid-music")
            waitFor(function() { return launcherModel.itemCount === 15 }, 5000,
                    "an override in a re-created directory still hides", done)
        },
        function(done) {
            var bad = sh(hideApps + " ../../etc/passwd")
            check(bad.status !== 0 && sh("test -e /usr/local/share/etc").status !== 0,
                  "hide-apps refuses a path for an app")
            check(sh(hideApps + " asteroid-nothing").status !== 0, "hide-apps refuses an app that isn't installed")
            sh(hideApps + " --undo")
            waitFor(function() { return launcherModel.itemCount === 16 }, 5000, "and --undo again", done)
        },

        // Back to the first app once the list is left for the watch face.
        function(done) {
            var view = listView()
            grid.currentVerticalPos = 1
            view.contentX = 3 * view.width
            grid.currentVerticalPos = 0
            after(150, function() {
                check(view.contentX === 3 * view.width, "the page stays while the list slides away")
                waitFor(function() { return view.contentX === 0 }, 2000,
                        "left for the watch face, the list goes back to Check-in", done)
            })
        },
        function(done) {
            var view = listView()
            grid.currentVerticalPos = 1
            view.contentX = 2 * view.width
            grid.currentVerticalPos = 0
            after(100, function() {
                grid.currentVerticalPos = 1
                after(1000, function() {
                    check(view.contentX === 2 * view.width, "brought back at once, the list keeps its page")
                    done()
                })
            })
        }
    ]
}
