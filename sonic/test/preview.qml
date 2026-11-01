/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The preview scene of sonic/test/test.sh: one sheet of the dark theme, for
 * a person to look at, from the screenshots that the other scenes saved. It
 * runs after them: test.sh runs every scene in order.
 */
import QtQuick 2.9

Scene {
    id: desktop

    ContactSheet {
        id: sheet
        x: desktop.width + 100
        columns: 4
        title: "Sonic's dark theme: the app list, its own logos and names in sentence case, the quick panel and the Today screen, on black"
    }

    readonly property var pages: [
        ["applist-hidden-01", "Check-in, first"],
        ["applist-hidden-02", "Alarm clock"],
        ["applist-hidden-03", "Heart rate"],
        ["applist-hidden-04", "Timer"],
        ["applist-hidden-05", "Stopwatch"],
        ["applist-hidden-06", "Weather"],
        ["applist-hidden-07", "Flashlight"],
        ["applist-hidden-08", "Diamonds, last"],
        ["applist-all-09", "An app without a logo"],
        ["quickpanel", "The quick panel"],
        ["quickpanel-outdoors", "The bell on outdoors"],
        ["today-1342", "The Today screen"]
    ]

    steps: [
        function(done) {
            var files = [], labels = []
            for (var i = 0; i < pages.length; i++) {
                var file = shots + "/" + pages[i][0] + ".png"
                check(test.sh("test -f " + file).status === 0, "the other scenes saved " + pages[i][0] + ".png")
                files.push(file)
                labels.push(pages[i][1])
            }
            sheet.files = files
            sheet.labels = labels
            after(300, function() { shot("preview-dark-theme", done, sheet) })
        }
    ]
}
