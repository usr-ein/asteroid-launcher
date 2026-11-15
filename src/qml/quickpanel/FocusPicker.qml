/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The Focus picker, full screen over the quick panel, and the confirmation
 * after a tap (Sonic Screwdriver's docs/focus/SKETCH.md § 3; its mockup,
 * docs/focus/watch-focus.html, draws them in picker() and toast()).
 * - show() opens the picker, its icons read again, scrolled so that the
 *   watch's Focus is centred. Under its title, FOCUS: "Follow iPhone" first
 *   while a Focus picked on the watch holds, with the iPhone's Focus under
 *   it; then each Focus of the table, in order: its icon on its colour, its
 *   name, and its base level, "No Focus · " before No Focus's; the watch's
 *   Focus has the tick. Without Sonic's table, No Focus alone, and a note;
 *   without ioslink, why there's no Focus.
 * - A tap on a Focus calls Pick(id), on Follow iPhone Follow(), at once; the
 *   picker closes, and the confirmation shows the new Focus for 1.9 s, with
 *   what it holds until. 125 ms after the tap, buzz() plays the panel's press,
 *   as the bell did, unless the new Focus's base is silent. A call that fails
 *   takes the confirmation and the buzz back, and Focus.qml's notice says why.
 * - Closing without a pick: AsteroidOS's back, a right swipe from the left
 *   edge, which the picker follows as the launcher's LayerStack does; a right
 *   swipe anywhere else; and a tap on the title, or on the line without
 *   ioslink. Only a tap picks: a swipe across a Focus doesn't. dismiss(), when
 *   the panel is left or hidden, as the display going off does, closes the
 *   picker and the confirmation at once.
 */
import QtQuick 2.9
import org.asteroid.controls 1.0

Item {
    id: picker

    // Focus.qml.
    property QtObject link
    // The picker shows.
    readonly property bool open: shown
    property bool shown: false
    // The confirmation shows. A property of the picker's own, not the
    // confirmation's visible, which reads false while the picker is hidden.
    property bool confirming: false
    // The confirmation's length, the mockup's 1.9 s, and its fade at the end.
    property int confirmMs: 1900
    property int fadeMs: 420

    // The press, 125 ms after a tap that changes the Focus to one that
    // vibrates.
    signal buzz()

    // How far up a label's glyphs move for a line height of `factor` times
    // its size, as the mockup's CSS sets them: CSS centres the glyphs in the
    // line, Qt's fixed line height puts them at its top, and Noto Sans's own
    // line is 1.362 of its size.
    function lift(factor, size) {
        return (1.362 - factor) / 2 * size
    }

    // The rows: Follow iPhone while a pick holds, then the table's Focuses.
    readonly property var rows: {
        if (link === null || !link.available)
            return []
        var list = link.picked ? [{follow: true, mode: link.modeOf(link.iphone.id)}] : []
        return list.concat(link.focuses.map(function(m) { return {follow: false, mode: m} }))
    }

    visible: shown || confirming

    function show() {
        link.reload()
        shown = true
        centre()
    }

    function close() {
        shown = false
    }

    function dismiss() {
        shown = false
        hideConfirmation()
    }

    // The watch's Focus in the middle of the screen, as AsteroidOS's lists
    // open on their current item.
    function centre() {
        list.forceLayout()
        content.forceLayout()
        var ticked = null
        for (var i = 0; i < repeater.count; i++) {
            var item = repeater.itemAt(i)
            if (item !== null && item.ticked) {
                ticked = item
                break
            }
        }
        if (ticked === null) {
            flick.contentY = 0
            return
        }
        var y = ticked.mapToItem(flick.contentItem, 0, 0).y + ticked.height / 2 - flick.height / 2
        flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height))
    }

    property int serial: 0

    // A tap on a row.
    function choose(row) {
        var target, line
        var mine = ++serial
        var failed = function() {
            if (mine !== picker.serial)
                return
            buzzDelay.stop()
            hideConfirmation()
        }
        if (row.follow) {
            target = link.modeOf(link.iphone.id)
            line = "following the iPhone again"
            link.follow(failed)
        } else {
            target = row.mode
            line = target.id === link.iphone.id ? "the iPhone’s Focus" : "until the iPhone’s next Focus change"
            link.pick(target.id, failed)
        }
        close()
        confirm(target, line)
        if (target.base !== "silent")
            buzzDelay.restart()
        else
            buzzDelay.stop()
    }

    function confirm(mode, line) {
        confirmation.mode = mode
        confirmation.line = line
        confirmation.opacity = 1
        confirming = true
        confirmAnimation.restart()
    }

    function hideConfirmation() {
        confirmAnimation.stop()
        confirming = false
    }

    // A release: a right swipe closes the picker; a tap, with no more than a
    // finger's slip, is tap(), if given.
    function released(from, to, tap) {
        var dx = to.x - from.x, dy = to.y - from.y
        if (dx > Dims.l(15) && dx > 2 * Math.abs(dy))
            close()
        else if (Math.abs(dx) < Dims.l(4) && Math.abs(dy) < Dims.l(4) && tap)
            tap()
    }

    Timer {
        id: buzzDelay
        interval: 125
        onTriggered: picker.buzz()
    }

    Item {
        id: sheet
        objectName: "focusPickerSheet"
        width: parent.width
        height: parent.height
        visible: picker.shown
        x: back.active && back.gesture === "right" ? back.value : 0
        opacity: (width - x) / width

        Behavior on x {
            enabled: !back.active
            NumberAnimation { duration: 200; easing.type: Easing.OutQuint }
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
        }

        Flickable {
            id: flick
            objectName: "focusPickerList"
            anchors.fill: parent
            visible: picker.link !== null && picker.link.available
            contentWidth: width
            contentHeight: content.height
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            // A press on no row: only a right swipe closes.
            MouseArea {
                width: flick.width
                height: Math.max(content.height, flick.height)
                property point from
                onPressed: from = mapToItem(null, mouse.x, mouse.y)
                onReleased: picker.released(from, mapToItem(null, mouse.x, mouse.y), null)
            }

            Column {
                id: content
                width: flick.width

                Item { width: 1; height: Dims.l(11.9) }

                Label {
                    objectName: "focusPickerTitle"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "FOCUS"
                    color: "#8a929e"
                    font.family: "Noto Sans"
                    font.styleName: "Condensed Medium"
                    font.pixelSize: Dims.l(5.7)
                    font.letterSpacing: Dims.l(5.7) * 0.04

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Dims.l(3)
                        property point from
                        onPressed: from = mapToItem(null, mouse.x, mouse.y)
                        onReleased: picker.released(from, mapToItem(null, mouse.x, mouse.y), function() { picker.close() })
                    }
                }

                Item { width: 1; height: Dims.l(4) }

                Column {
                    id: list
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Dims.l(1.3)

                    Repeater {
                        id: repeater
                        model: picker.rows

                        Item {
                            id: row
                            objectName: "focusRow"
                            readonly property bool follow: modelData.follow
                            readonly property var mode: modelData.mode
                            readonly property bool ticked: !follow && mode.id === picker.link.current.id
                            readonly property string name: follow ? "Follow iPhone" : mode.name
                            readonly property string detail: follow ? picker.link.iphone.name
                                                                    : (mode.id === "" ? "No Focus · " : "") + picker.link.level(mode.base)
                            // For the tests: a tap, as a release in place.
                            function tap() { picker.choose(modelData) }

                            width: Dims.l(70)
                            height: Math.max(Dims.l(18.5), texts.height + 2 * Dims.l(1.75))

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: "#15181d"
                                visible: area.pressed
                            }

                            FocusDisc {
                                objectName: "focusRowDisc"
                                x: Dims.l(3.1)
                                anchors.verticalCenter: parent.verticalCenter
                                width: Dims.l(14.1)
                                height: width
                                tint: row.follow ? "" : row.mode.color
                                iconSource: row.follow ? "" : picker.link.iconUrl(row.mode.icon)
                                glyph: row.follow ? "ios-phone-portrait" : "ios-notifications-outline"
                            }

                            // Placed by bindings, not a Column, so that the row's
                            // height is right as soon as it exists, for centre().
                            Item {
                                id: texts
                                x: Dims.l(3.1 + 14.1 + 3.5)
                                width: parent.width - x - Dims.l(3.5 + 7.5 + 3.1)
                                height: nameLabel.height + Dims.l(0.44) + detailLabel.height
                                anchors.verticalCenter: parent.verticalCenter

                                Label {
                                    id: nameLabel
                                    width: parent.width
                                    text: row.name
                                    color: "white"
                                    wrapMode: Text.WordWrap
                                    lineHeightMode: Text.FixedHeight
                                    lineHeight: font.pixelSize * 1.1
                                    topPadding: -picker.lift(1.1, font.pixelSize)
                                    bottomPadding: picker.lift(1.1, font.pixelSize)
                                    font.family: "Noto Sans"
                                    font.styleName: "Condensed Medium"
                                    font.pixelSize: row.follow ? Dims.l(5.7) : Dims.l(6.6)
                                }

                                Label {
                                    id: detailLabel
                                    y: nameLabel.height + Dims.l(0.44)
                                    width: parent.width
                                    text: row.detail
                                    color: "#8a929e"
                                    wrapMode: Text.WordWrap
                                    lineHeightMode: Text.FixedHeight
                                    lineHeight: font.pixelSize * 1.2
                                    topPadding: -picker.lift(1.2, font.pixelSize)
                                    bottomPadding: picker.lift(1.2, font.pixelSize)
                                    font.family: "Noto Sans"
                                    font.styleName: "Regular"
                                    font.pixelSize: Dims.l(4.2)
                                }
                            }

                            Icon {
                                objectName: "focusTick"
                                visible: row.ticked
                                anchors.right: parent.right
                                anchors.rightMargin: Dims.l(3.1)
                                anchors.verticalCenter: parent.verticalCenter
                                width: Dims.l(7.5)
                                height: width
                                name: "ios-checkmark"
                                color: "white"
                            }

                            MouseArea {
                                id: area
                                anchors.fill: parent
                                property point from
                                onPressed: from = mapToItem(null, mouse.x, mouse.y)
                                onReleased: picker.released(from, mapToItem(null, mouse.x, mouse.y), row.tap)
                            }
                        }
                    }
                }

                Item {
                    width: 1
                    height: Dims.l(2.2)
                    visible: note.visible
                }

                Label {
                    id: note
                    objectName: "focusPickerNote"
                    visible: picker.link !== null && picker.link.available && !picker.link.table
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Dims.l(66)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: font.pixelSize * 1.3
                    text: "Set up Focus in Sonic, on the iPhone."
                    color: "#8a929e"
                    font.family: "Noto Sans"
                    font.styleName: "Regular"
                    font.pixelSize: Dims.l(4.6)
                }

                Item { width: 1; height: Dims.l(41.9) }
            }
        }

        // Without ioslink: why there's no Focus. A tap closes.
        Item {
            objectName: "focusPickerAway"
            anchors.fill: parent
            visible: picker.link === null || !picker.link.available

            Column {
                anchors.centerIn: parent
                width: Dims.l(69.2)
                spacing: Dims.l(3.1)

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Dims.l(15.4)
                    height: width
                    name: "ios-notifications-off"
                    color: "#8a929e"
                }

                Label {
                    objectName: "focusPickerAwayLine"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    lineHeightMode: Text.FixedHeight
                    lineHeight: font.pixelSize * 1.3
                    text: "Focus needs ioslink, which isn't running."
                    color: "#c9cfd8"
                    font.family: "Noto Sans"
                    font.styleName: "Regular"
                    font.pixelSize: Dims.l(5.5)
                }
            }

            MouseArea {
                anchors.fill: parent
                property point from
                onPressed: from = mapToItem(null, mouse.x, mouse.y)
                onReleased: picker.released(from, mapToItem(null, mouse.x, mouse.y), function() { picker.close() })
            }
        }

        // AsteroidOS's back: a right swipe from the left edge, followed.
        BorderGestureArea {
            id: back
            anchors.fill: parent
            enabled: picker.shown
            acceptsRight: true
            onGestureFinished: {
                if (gesture === "right" && progress >= 0.15)
                    picker.close()
            }
        }
    }

    // The confirmation: the new Focus, and what it holds until.
    Rectangle {
        id: confirmation
        objectName: "focusConfirmation"
        anchors.fill: parent
        color: "black"
        visible: picker.confirming

        property var mode: ({id: "", name: "", color: "", base: "", icon: ""})
        property string line: ""

        // Taps stay off the panel's toggles under it.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.centerIn: parent
            width: Dims.l(64)

            FocusDisc {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Dims.l(25.6)
                height: width
                glyphScale: 0.52
                tint: confirmation.mode.color
                iconSource: picker.link !== null ? picker.link.iconUrl(confirmation.mode.icon) : ""
            }

            Item { width: 1; height: Dims.l(4) }

            Label {
                objectName: "focusConfirmationName"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                lineHeightMode: Text.FixedHeight
                lineHeight: font.pixelSize * 1.1
                text: confirmation.mode.name
                color: "white"
                topPadding: -picker.lift(1.1, font.pixelSize)
                bottomPadding: picker.lift(1.1, font.pixelSize)
                font.family: "Noto Sans"
                font.styleName: "Condensed Medium"
                font.pixelSize: Dims.l(8.4)
            }

            Item { width: 1; height: Dims.l(1.75) }

            Label {
                objectName: "focusConfirmationLine"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                lineHeightMode: Text.FixedHeight
                lineHeight: font.pixelSize * 1.3
                text: confirmation.line
                color: "#8a929e"
                font.family: "Noto Sans"
                font.styleName: "Regular"
                font.pixelSize: Dims.l(4.85)
            }
        }

        SequentialAnimation {
            id: confirmAnimation
            PauseAnimation { duration: picker.confirmMs - picker.fadeMs }
            NumberAnimation { target: confirmation; property: "opacity"; to: 0; duration: picker.fadeMs; easing.type: Easing.InOutQuad }
            PropertyAction { target: picker; property: "confirming"; value: false }
        }
    }
}
