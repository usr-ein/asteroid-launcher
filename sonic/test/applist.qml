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
 *     and keeps its page when brought back at once.
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

    readonly property var everyApp: [
        "Check-in", "Alarm Clock", "Heart Rate", "Timer", "Stopwatch", "Weather",
        "Flashlight", "Diamonds", "Agenda", "Calculator", "Music", "Settings"
    ]
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

    // Every page of the list, then their contact sheet.
    function pages(prefix, title, done) {
        var view = listView()
        var files = [], labels = []
        var page = 0
        function one() {
            if (page === launcherModel.itemCount) {
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
                files.push(shots + "/" + name + ".png")
                labels.push((page + 1) + ". " + launcherModel.get(page).title)
                shot(name, function() { page++; one() })
            })
        }
        one()
    }

    steps: [
        function(done) {
            check(listView() !== null, "the compiled-in horizontal list loads")
            expectEqual(titles(launcherModel), everyApp, "the order: Check-in, the PRD's apps, then the others by title")
            check(allApps.itemCount === 12, "lipstick lists the 12 apps; sonic-health has NoDisplay=true")
            expectEqual(launcherModel.hiddenApps, [], "no override yet")
            done()
        },
        function(done) { pages("applist-all", "The app list, every app: Check-in first", done) },

        // lipstick ignores an override in ~/.local/share/applications; AppListModel doesn't.
        function(done) {
            sh("mkdir -p " + userApps + " && printf '[Desktop Entry]\\nType=Application\\nName=Music\\n"
               + "Exec=asteroid-music\\nNoDisplay=true\\n' > " + userApps + "/asteroid-music.desktop")
            waitFor(function() { return launcherModel.itemCount === 11 }, 5000,
                    "an override in ~/.local/share/applications hides Music from the list", done)
        },
        // lipstick's monitor reports changes after 2 s.
        function(done) { after(3000, done) },
        function(done) {
            check(lipstickPaths().indexOf("/usr/share/applications/asteroid-music.desktop") >= 0
                  && allApps.itemCount === 12,
                  "lipstick's own model still lists /usr/share/applications/asteroid-music.desktop")
            sh("rm " + userApps + "/asteroid-music.desktop")
            waitFor(function() { return launcherModel.itemCount === 12 }, 5000,
                    "deleting it brings Music back", done)
        },

        // sonic/watch/hide-apps, with the default four.
        function(done) {
            var result = sh(hideApps)
            check(result.status === 0, "hide-apps exits 0")
            expectEqual(result.output.trim().split("\n"), [
                "hidden: asteroid-music (Music)",
                "hidden: asteroid-calculator (Calculator)",
                "hidden: asteroid-calendar (Agenda)",
                "hidden: asteroid-settings (Settings)"
            ], "hide-apps says what it hid")
            waitFor(function() { return launcherModel.itemCount === 8 }, 5000,
                    "the list drops the four at once", done)
        },
        function(done) { after(3000, done) },
        function(done) {
            expectEqual(titles(launcherModel), everyApp.slice(0, 8), "the list: the PRD's eight, in order")
            expectEqual(launcherModel.hiddenApps,
                        ["asteroid-calculator", "asteroid-calendar", "asteroid-music", "asteroid-settings"],
                        "AppListModel reads the four overrides")
            check(allApps.itemCount === 12, "lipstick's own model still lists all 12: it ignores /usr/local/share/applications")
            var status = sh(hideApps + " --status")
            expectEqual(status.output.trim().split("\n"), [
                "hidden: asteroid-calculator",
                "hidden: asteroid-calendar",
                "hidden: asteroid-music",
                "hidden: asteroid-settings"
            ], "hide-apps --status lists them")
            check(sh("grep -c . /usr/share/applications/asteroid-music.desktop").status === 0
                  && sh("! grep -q NoDisplay /usr/share/applications/asteroid-music.desktop").status === 0,
                  "the stock .desktop files are untouched")
            done()
        },
        function(done) { pages("applist-hidden", "The app list with Music, Calculator, Agenda and Settings hidden", done) },

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
            sh("printf '[Desktop Entry]\\nType=Application\\nName=Weather\\nExec=asteroid-weather\\n"
               + "NoDisplay=true\\n' > /usr/local/share/applications/asteroid-weather.desktop")
            waitFor(function() { return launcherModel.itemCount === 8 }, 5000,
                    "a hand-written override hides Weather", done)
        },
        function(done) {
            var refused = sh(hideApps + " --show asteroid-weather")
            check(refused.status !== 0, "hide-apps --show refuses an override it didn't write")
            var result = sh(hideApps + " --undo")
            expectEqual(result.output.trim().split("\n").sort(),
                        ["shown: asteroid-calculator", "shown: asteroid-calendar", "shown: asteroid-music"],
                        "hide-apps --undo removes its own overrides")
            waitFor(function() { return launcherModel.itemCount === 11 }, 5000,
                    "--undo brings back all but Weather", done)
        },
        function(done) {
            check(sh("test -f /usr/local/share/applications/asteroid-weather.desktop").status === 0,
                  "--undo left the hand-written override")
            sh("rm /usr/local/share/applications/asteroid-weather.desktop")
            waitFor(function() { return launcherModel.itemCount === 12 }, 5000,
                    "every app is back", done)
        },
        function(done) {
            sh(hideApps + " --undo")
            check(sh("test -e /usr/local/share/applications").status !== 0,
                  "--undo removes the empty override directory")
            // The directory comes back: the model must watch it again.
            sh(hideApps + " asteroid-music")
            waitFor(function() { return launcherModel.itemCount === 11 }, 5000,
                    "an override in a re-created directory still hides", done)
        },
        function(done) {
            var bad = sh(hideApps + " ../../etc/passwd")
            check(bad.status !== 0 && sh("test -e /usr/local/share/etc").status !== 0,
                  "hide-apps refuses a path for an app")
            check(sh(hideApps + " asteroid-nothing").status !== 0, "hide-apps refuses an app that isn't installed")
            sh(hideApps + " --undo")
            waitFor(function() { return launcherModel.itemCount === 12 }, 5000, "and --undo again", done)
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
