/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick panel scene of sonic/test/test.sh: the launcher's own QuickPanel,
 * compiled in, on the dark theme's black, which MainScreen's darkener makes
 * opaque behind every panel but the watch face. The system services that it
 * reads are stand-ins (stubs/), with the alert profile on "general".
 * Screenshots: the panel, and with the bell on "outdoors".
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

    steps: [
        function(done) {
            var bell = find(panel, function(item) { return item.profile !== undefined && item.tint !== undefined })
            check(bell !== null, "the bell toggle shows")
            shot("quickpanel", done)
        },
        function(done) {
            var bell = find(panel, function(item) { return item.profile !== undefined && item.tint !== undefined })
            bell.clicked(null)
            after(300, function() {
                check(bell.profile === "silent", "a tap on the bell goes from general to silent")
                bell.clicked(null)
                after(300, function() {
                    check(bell.profile === "outdoors", "and from silent to outdoors")
                    shot("quickpanel-outdoors", done)
                })
            })
        }
    ]
}
