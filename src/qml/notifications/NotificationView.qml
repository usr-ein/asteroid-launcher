/*
 * Copyright (C) 2017 Florent Revest <revestflo@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick 2.9
import org.asteroid.controls 1.0

/*
 * One notification, opened (P-032; Sonic Screwdriver's
 * docs/notifications/actions-sketch.md, and docs/mockups/P-032-mockup.html,
 * round 4, which Sam approved). It scrolls with the round fit (RoundFit.qml).
 *  - The text: "App · time" small and grey, the title purple and bold, then
 *    the body, one paragraph per line break. The line at the middle is full
 *    size; each line is scaled to the circle at its height and fades at the
 *    rim. It opens with the title at the middle.
 *  - The actions: while you read, the main one is pinned at the bottom. Once
 *    the text has gone past, it leaves its pin and scrolls up, with the others
 *    below it, all the same size; with more than fit, the list keeps
 *    scrolling until the last one reaches the pin. A pill is as wide as the
 *    circle allows, up to pillWidth near the middle, and fades at the rim like
 *    the text; the pinned one doesn't.
 *  - Which actions: lipstick's pairs, [key, label, ...]. The main one is
 *    "default" when it's listed, else Dismiss. The list: the main action
 *    when it's the default, the notification's other actions in their
 *    order, Dismiss all, and Dismiss last (Sam: "Dismiss all first-safe"):
 *    so at the end, the pin's place holds Dismiss, never Dismiss all. When
 *    Dismiss is the main one, it stays at the pin, and the others rise above
 *    it, fading in as they clear it. A key's tap invokes it: lipstick runs
 *    its remote action, sends ActionInvoked to its owner, and closes the
 *    notification. Dismiss closes it, which ioslink takes as the iPhone's
 *    Clear (Sam: "Dismiss == Clear").
 * The lines and the pills are in the round fit's `tappable` layer, inside its
 * Flickable: a pill's MouseArea gets a tap, and the Flickable takes a drag
 * that starts on a pill over from it, so it scrolls: Qt 5's own pattern for
 * taps in a Flickable, with the watch's touches as with the harness's mouse.
 * The view plays no sound: lipstick plays each notification's own
 * x-nemo-feedback event through ngfd once, and the active profile decides
 * whether it sounds or vibrates.
 */
Item {
    id: view

    property QtObject panelsGrid
    property QtObject notification
    // NotificationsPanel's model, for Dismiss all.
    property QtObject notificationModel

    // ---- the sizes, in watch px (the watch is 454 px round): change them here ----
    // The middle line's font size, and a line's height as a multiple of it.
    readonly property real fontPx: 30
    readonly property real lineHeight: 1.32
    // The middle line's width before it wraps, as a share of the screen.
    readonly property real lineWidth: 0.84
    // The space between two paragraphs, in lines.
    readonly property real paragraphGap: 0.5
    // A pill's width at the middle, as a share of the screen; every pill's
    // height, which doesn't zoom; its label's size, which shrinks only when a
    // narrow pill can't hold it; and the label's inset at each end.
    readonly property real pillWidth: 0.80
    readonly property real pillHeight: 76
    readonly property real pillFontPx: 36
    readonly property real pillPadding: 22
    // A label too long for the widest pill shrinks down to labelMinPx, then
    // is cut with "…". It's laid out once, at the widest pill's width, and
    // scaled with its pill: never laid out again while it scrolls.
    readonly property real labelMinPx: 12
    // The space between two pills, and between the text and the main pill.
    readonly property real pillGap: 20
    readonly property real textGap: 40
    // A pill's rounded ends stay rimInset inside the circle. As the rim
    // squeezes it, it fades out while its width falls from
    // squeezeFrom + squeezeOver heights to squeezeFrom.
    readonly property real rimInset: 8
    readonly property real squeezeFrom: 1.6
    readonly property real squeezeOver: 0.8
    // The main pill's centre while you read, as a share of the screen from
    // the top.
    readonly property real pinAt: 0.852
    // The pinned pill's tap area: a band bandWidth of the screen wide, from
    // bandTop of the height (or just above the pill) down to the rim. A
    // listed pill's reaches tapMargin around it, so two meet half way.
    readonly property real bandWidth: 0.60
    readonly property real bandTop: 0.79
    // The band reaches at least bandAbove px above the pinned pill.
    readonly property real bandAbove: 6
    readonly property real tapMargin: pillGap / 2
    // The notification's own actions shown at most, the main one included.
    readonly property int maxOwnActions: 3
    // The top of the screen kept clear for the launcher's row of
    // notification icons (MainScreen's NotificationIndicator: Dims.h(5) down,
    // Dims.h(8) high), as a share of the screen. A line fades out as its
    // middle comes within clearFade px of it; a pill as its top goes past it,
    // by clearFade px at most.
    readonly property real topClear: 0.13
    readonly property real clearFade: 24
    // Text fades out above the main pill: gone within pillClearance px of
    // its top, whole pillClearance + pillFade px above it.
    readonly property real pillClearance: 6
    readonly property real pillFade: 24
    // Each kind of line: its size, as a multiple of fontPx, its weight and its colour.
    readonly property var kinds: ({
            "caption": { size: 0.6, weight: Font.Normal, color: "#8a929e" },
            "title": { size: 1, weight: Font.Bold, color: "#c9a7ff" },
            "body": { size: 1, weight: Font.Normal, color: "#f2f0f7" }
        })
    readonly property color pillColor: "#eb303036"
    readonly property color mainColor: "#f53e3e46"
    readonly property color pressedColor: "#fa62626e"

    // ---- the layout ----
    // Watch pixels to the item's.
    readonly property real px: Math.min(width, height) / 454
    readonly property real lineStep: fontPx * lineHeight * px
    property string timestampStr: ""
    // In order, the text's lines and the pills, each { kind, h, gap, fixed,
    // y }: y its middle in the content, h its height and gap the space before
    // it (RoundFit.walk); a line's also { text, size, weight, color }, a
    // pill's { label, action, launcher }.
    property var rows: []
    property var lines: []
    property var pills: []
    property int firstPill: 0
    // The main pill's index among the pills: the first, or the last when it's
    // Dismiss.
    property int mainPill: 0

    onNotificationChanged: rebuild()
    onWidthChanged: Qt.callLater(rebuild)
    onHeightChanged: Qt.callLater(rebuild)

    function updateTimestamp() {
        if (notification === null || notification === undefined || !notification.timestamp)
            return
        var delta = new Date().getTime() - notification.timestamp.getTime()
        if (delta < 60 * 1000) {
            //% "Now"
            timestampStr = qsTrId("id-now") + localeManager.changesObserver
        } else {
            delta = parseInt(delta / (1000 * 60))
            if (delta < 60) {
                //% "m"
                timestampStr = delta + qsTrId("id-minute-abbrev") + localeManager.changesObserver
            } else {
                delta = parseInt(delta / 60)
                if (delta < 60) {
                    //% "h"
                    timestampStr = delta + qsTrId("id-hour-abbrev") + localeManager.changesObserver
                } else {
                    delta = parseInt(delta / 24)
                    //% "d"
                    timestampStr = delta + qsTrId("id-day-abbrev") + localeManager.changesObserver
                }
            }
        }
    }

    function caption() {
        var app = notification && notification.appName ? notification.appName : ""
        return app !== "" ? app + " · " + timestampStr : timestampStr
    }

    // The pills, in order: { label, action } for one of the notification's
    // own actions, { label, launcher } for Dismiss and Dismiss all; the main
    // one has main: true. Dismiss is always last, and Dismiss all just before
    // it.
    function actionList() {
        var listed = notification && notification.actions ? notification.actions : []
        var main = null
        var own = []
        for (var i = 0; i + 1 < listed.length; i += 2) {
            if (listed[i] === "default")
                main = { label: listed[i + 1], action: "default" }
            else
                own.push({ label: listed[i + 1], action: listed[i] })
        }
        var room = maxOwnActions - (main ? 1 : 0)
        if (own.length > room) {
            console.log("notification: " + own.length + " actions, " + room + " shown")
            own = own.slice(0, room)
        }
        //% "Dismiss"
        var dismiss = { label: qsTrId("id-dismiss") + localeManager.changesObserver, launcher: "dismiss" }
        //% "Dismiss all"
        var dismissAll = { label: qsTrId("id-dismiss-all") + localeManager.changesObserver, launcher: "dismiss-all" }
        if (main)
            main.main = true
        else
            dismiss.main = true
        return (main ? [main] : []).concat(own, [dismissAll, dismiss])
    }

    // Greedy word wrap at width, measured by metrics; a word wider than the
    // line (a link, a hash) is cut into pieces that fit. As the round-fit
    // reader does (ai/watch/RoundText.qml).
    function wrap(text, metrics, width) {
        var out = []
        var words = []
        var raw = String(text).split(/\s+/)
        for (var w = 0; w < raw.length; w++) {
            var word = raw[w]
            while (word.length > 1 && metrics.advanceWidth(word) > width) {
                var n = word.length - 1
                while (n > 1 && metrics.advanceWidth(word.slice(0, n)) > width)
                    n--
                words.push(word.slice(0, n))
                word = word.slice(n)
            }
            words.push(word)
        }
        var cur = ""
        for (var i = 0; i < words.length; i++) {
            if (words[i] === "")
                continue
            var t = cur ? cur + " " + words[i] : words[i]
            if (!cur || metrics.advanceWidth(t) <= width) {
                cur = t
            } else {
                out.push(cur)
                cur = words[i]
            }
        }
        if (cur)
            out.push(cur)
        return out
    }

    function rebuild() {
        if (!notification || width <= 0 || height <= 0) {
            rows = []
            lines = []
            pills = []
            return
        }
        updateTimestamp()
        var all = []
        var addText = function(text, kind) {
            var k = kinds[kind]
            var metrics = k.weight >= Font.Bold ? boldMetrics : plainMetrics
            var wrapped = wrap(text, metrics, lineWidth * width / k.size)
            for (var i = 0; i < wrapped.length; i++)
                all.push({ kind: "line", text: wrapped[i], size: k.size, weight: k.weight, color: k.color,
                           h: lineStep * k.size, gap: all.length > 0 && i === 0 ? lineStep * paragraphGap : 0, fixed: false })
        }
        addText(caption(), "caption")
        addText(notification.summary || "", "title")
        var paragraphs = String(notification.body || "").split("\n")
        for (var p = 0; p < paragraphs.length; p++)
            addText(paragraphs[p], "body")
        var first = all.length
        var acts = actionList()
        for (var a = 0; a < acts.length; a++) {
            acts[a].kind = "pill"
            acts[a].h = pillHeight * px
            acts[a].gap = (a === 0 ? textGap : pillGap) * px
            acts[a].fixed = true
            all.push(acts[a])
        }
        for (var j = 0; j < all.length; j++)
            all[j].y = j === 0 ? 0 : all[j - 1].y + all[j - 1].h / 2 + all[j].gap + all[j].h / 2
        var titleY = all.length > 1 ? all[1].y : 0
        firstPill = first
        mainPill = 0
        for (var m = 0; m < acts.length; m++) {
            if (acts[m].main)
                mainPill = m
        }
        lines = all.slice(0, first)
        pills = all.slice(first)
        rows = all
        // The end: the last pill where the main one is pinned.
        var pinY = pinAt * height
        var lo = 0, hi = all[all.length - 1].y + height
        for (var b = 0; b < 40; b++) {
            var mid = (lo + hi) / 2
            if (fit.walk(all, mid)[all.length - 1] > pinY)
                lo = mid
            else
                hi = mid
        }
        fit.contentHeight = hi
        fit.positionTo(Math.min(hi, titleY))
        Qt.callLater(layout)
    }

    // The width of a pill of height h whose middle is at the screen's y: as
    // wide as pillWidth, or as its rounded ends allow, rimInset inside the
    // circle.
    function widthAt(y, h) {
        var d = y - height / 2
        var r = Math.min(width, height) / 2 - rimInset * px - h / 2
        return Math.max(h, Math.min(pillWidth * width, h + 2 * Math.sqrt(Math.max(0, r * r - d * d))))
    }

    // Everything in one pass, at each position: on the watch, a binding per
    // piece halves the frame rate (RoundFit.qml).
    function layout() {
        if (rows.length === 0 || lineItems.count !== lines.length || pillItems.count !== pills.length)
            return
        var Y = fit.walk(rows)
        var pinY = pinAt * height
        var mainRow = firstPill + mainPill
        var mainFlow = Y[mainRow]
        var pinned = mainFlow > pinY
        var mainY = pinned ? pinY : mainFlow
        var mainTop = mainY - rows[mainRow].h / 2
        var clear = topClear * height
        for (var i = 0; i < lines.length; i++) {
            var line = lineItems.itemAt(i)
            var s = fit.scaleAt(Y[i])
            // Text fades out just above the main pill, so nothing reads behind
            // it, and below the row of notification icons at the top.
            var bottom = Y[i] + lines[i].h / 2 * s
            var o = fit.opacityAt(Y[i]) * Math.max(0, Math.min(1, (mainTop - bottom - pillClearance * px) / (pillFade * px)))
                    * Math.max(0, Math.min(1, (Y[i] - clear) / (clearFade * px)))
            line.visible = o > 0
            if (o > 0) {
                line.y = Y[i] - line.height / 2
                line.k = s
                line.opacity = o
            }
        }
        for (var j = 0; j < pills.length; j++) {
            var row = pills[j]
            var main = j === mainPill
            var y = main ? mainY : Y[firstPill + j]
            var w = widthAt(y, row.h)
            var op = main && pinned ? 1 : fit.opacityAt(y) * Math.max(0, Math.min(1, (w / row.h - squeezeFrom) / squeezeOver))
                     * Math.max(0, Math.min(1, (y - row.h / 2 - clear + clearFade * px) / (clearFade * px)))
            // A pill above the pinned one fades out as it nears it, gone where
            // it would touch it, whole a gap away, as it is at the end.
            if (pinned && j < mainPill)
                op *= Math.max(0, Math.min(1, (mainTop - (y + row.h / 2)) / (pillGap * px)))
            pillItems.itemAt(j).place(y, w, op, main && pinned)
        }
    }

    function invoke(row) {
        if (!notification)
            return
        if (row.launcher === "dismiss") {
            if (notification.userRemovable)
                notification.removeRequested()
        } else if (row.launcher === "dismiss-all") {
            if (!notificationModel)
                return
            for (var i = 0; i < notificationModel.itemCount; i++) {
                var other = notificationModel.get(i)
                if (other && other.userRemovable)
                    other.removeRequested()
            }
        } else {
            notification.actionInvoked(row.action)
        }
    }

    Connections {
        target: view.panelsGrid
        function onCurrentHorizontalPosChanged() {
            view.updateTimestamp()
            if (view.lines.length > 0)
                view.captionText = view.caption()
        }
    }
    // The caption's text, kept up to date without moving the text.
    property string captionText: ""
    onLinesChanged: captionText = lines.length > 0 ? lines[0].text : ""

    FontMetrics {
        id: plainMetrics
        font.pixelSize: view.fontPx * view.px
        font.weight: Font.Normal
    }
    FontMetrics {
        id: boldMetrics
        font.pixelSize: view.fontPx * view.px
        font.weight: Font.Bold
    }

    RoundFit {
        id: fit
        objectName: "notificationFit"
        anchors.fill: parent
        rowWidth: view.lineWidth * width

        onPositionChanged: view.layout()
        onTableChanged: view.layout()
    }

    // The pieces, placed by layout() in the screen's coordinates.
    Item {
        parent: fit.tappable
        anchors.fill: parent

        Repeater {
            id: lineItems
            model: view.lines.length
            onItemAdded: Qt.callLater(view.layout)

            Text {
                id: line
                objectName: "notificationLine"
                readonly property var row: view.lines[index] || ({})
                property real k: 1
                x: (view.width - width) / 2
                visible: false
                transform: Scale { origin.x: line.width / 2; origin.y: line.height / 2; xScale: line.k; yScale: line.k }
                text: index === 0 ? view.captionText : (row.text || "")
                color: row.color || "#ffffff"
                font.pixelSize: view.fontPx * view.px * (row.size || 1)
                font.weight: row.weight === undefined ? Font.Normal : row.weight
                textFormat: Text.PlainText
            }
        }

        Repeater {
            id: pillItems
            model: view.pills.length
            onItemAdded: Qt.callLater(view.layout)

            Item {
                id: pill
                objectName: "notificationPill"
                readonly property var row: view.pills[index] || ({})
                readonly property int order: index
                readonly property string label: row.label || ""
                readonly property real pillHeight: view.pillHeight * view.px
                property real pillWidth: 0
                property real centreY: 0
                property bool pinned: false
                property bool shown: false
                visible: shown
                readonly property bool main: row.main === true
                z: main ? 2 : 1

                // Its place at the screen's y, its width w and its opacity;
                // its tap area around it, or the band under it when pinned.
                function place(y, w, op, isPinned) {
                    centreY = y
                    pillWidth = w
                    pinned = isPinned
                    shown = op > 0
                    opacity = op
                    if (!shown)
                        return
                    var top = y - pillHeight / 2
                    if (isPinned) {
                        x = (view.width - view.bandWidth * view.width) / 2
                        width = view.bandWidth * view.width
                        pill.y = Math.min(view.bandTop * view.height, top - view.bandAbove * view.px)
                        height = view.height - pill.y
                    } else {
                        var m = view.tapMargin * view.px
                        x = (view.width - w) / 2 - m
                        width = w + 2 * m
                        pill.y = top - m
                        height = pillHeight + 2 * m
                    }
                    shape.x = (view.width - w) / 2 - x
                    shape.y = top - pill.y
                    label.scale = Math.min(1, (w - 2 * view.pillPadding * view.px) / Math.max(1, label.contentWidth))
                }

                function activate() {
                    view.invoke(row)
                }

                Rectangle {
                    id: shape
                    width: pill.pillWidth
                    height: pill.pillHeight
                    radius: height / 2
                    color: tap.pressed ? view.pressedColor : (pill.main ? view.mainColor : view.pillColor)

                    // Laid out once, at the widest pill's width; place() scales it
                    // with its pill.
                    Text {
                        id: label
                        anchors.centerIn: parent
                        width: view.pillWidth * view.width - 2 * view.pillPadding * view.px
                        horizontalAlignment: Text.AlignHCenter
                        text: pill.label
                        color: "#ffffff"
                        font.pixelSize: view.pillFontPx * view.px
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: view.labelMinPx * view.px
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }

                MouseArea {
                    id: tap
                    anchors.fill: parent
                    onClicked: pill.activate()
                }
            }
        }
    }
}
