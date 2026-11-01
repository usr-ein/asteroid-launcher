/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * One timed event of the Today timeline (Today.qml): a block from its start
 * to its end, in its calendar's colour, as the approved mockup draws it.
 * - Its calendar's colour makes a 4 px border on the left, and darkened, the
 *   block itself.
 * - A block taller than Timeline.NORMAL_MIN has its title, on two lines at
 *   most, above its time. A longer title rolls up, slowly, with a pause at
 *   each end.
 * - A shorter one is a single line, the time first, and a longer title slides
 *   sideways.
 * - The title moves only while `active`: Today.qml sets it while the screen
 *   shows and the block is in view.
 */
import QtQuick 2.9
import 'timeline.js' as Timeline

Item {
    id: event

    // A block of Timeline.layout(), with title, colour and timeText.
    property var block
    // The mockup's pixel, on this screen.
    property real px: 1
    property bool active: false
    // Whether the title is moving, for the tests.
    readonly property bool animating: roll.running || slide.running

    readonly property color colour: block.colour
    readonly property color fill: mix(colour, 0.27, 0)

    // The CSS color-mix() of the mockup: share of c, the rest black (0) or white (1).
    function mix(c, share, base) {
        return Qt.rgba(c.r * share + base * (1 - share), c.g * share + base * (1 - share),
                       c.b * share + base * (1 - share), 1)
    }

    x: block.x * px
    y: (block.top + 1) * px
    width: block.width * px
    height: (block.height - 2) * px

    Rectangle {
        anchors.fill: parent
        radius: 7 * px
        color: event.colour
    }
    Rectangle {
        x: 4 * px
        width: parent.width - 11 * px
        height: parent.height
        color: event.fill
    }
    Rectangle {
        x: parent.width - 14 * px
        width: 14 * px
        height: parent.height
        radius: 7 * px
        color: event.fill
    }

    // Normal: the title above the time.
    Item {
        visible: !block.compact
        x: 13 * px
        y: 6 * px
        width: parent.width - 21 * px
        height: parent.height - 6 * px
        clip: true

        // As many lines as the title takes, up to block.lines.
        Item {
            id: titleWindow
            width: parent.width
            height: Math.max(1, Math.min(block.lines, title.lineCount)) * Timeline.LINE * px
            clip: true

            Text {
                id: title
                readonly property real overflow: Math.max(0, contentHeight - titleWindow.height)
                width: parent.width
                text: block.title
                wrapMode: Text.Wrap
                lineHeightMode: Text.FixedHeight
                lineHeight: Timeline.LINE * px
                color: event.mix(event.colour, 0.22, 1)
                font.pixelSize: 20 * px
                font.weight: Font.DemiBold
            }
        }

        Text {
            y: titleWindow.height + 2 * px
            width: parent.width
            text: block.timeText
            elide: Text.ElideRight
            color: event.mix(event.colour, 0.52, 1)
            font.pixelSize: 15 * px
            font.weight: Font.Medium
        }
    }

    // Short: one line, the time first.
    Item {
        visible: block.compact
        x: 13 * px
        width: parent.width - 21 * px
        height: Timeline.LINE * px
        anchors.verticalCenter: parent.verticalCenter
        clip: true

        // On the title's baseline.
        Text {
            id: compactTime
            y: slideWindow.y + compactTitle.y + compactTitle.baselineOffset - baselineOffset
            text: block.timeText
            color: event.mix(event.colour, 0.52, 1)
            font.pixelSize: 15 * px
            font.weight: Font.Medium
        }

        Item {
            id: slideWindow
            x: compactTime.width + 7 * px
            width: Math.max(0, parent.width - x)
            height: parent.height
            clip: true

            Text {
                id: compactTitle
                readonly property real overflow: Math.max(0, contentWidth - slideWindow.width)
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: block.title
                color: event.mix(event.colour, 0.22, 1)
                font.pixelSize: 18 * px
                font.weight: Font.DemiBold
            }
        }
    }

    // A pause at the start, the move, a pause at the end, then again from the
    // start, as the mockup's keyframes: 18 %, 64 %, 18 % of a cycle.
    SequentialAnimation {
        id: roll
        readonly property int cycle: (3.4 + title.overflow / (Timeline.LINE * px) * 1.7) * 1000
        running: event.active && !block.compact && title.overflow > 2 * px
        loops: Animation.Infinite
        onRunningChanged: if (!running) title.y = 0

        PropertyAction { target: title; property: "y"; value: 0 }
        PauseAnimation { duration: roll.cycle * 0.18 }
        NumberAnimation { target: title; property: "y"; to: -title.overflow; duration: roll.cycle * 0.64 }
        PauseAnimation { duration: roll.cycle * 0.18 }
    }

    SequentialAnimation {
        id: slide
        readonly property int cycle: (3.2 + compactTitle.overflow / px / 28) * 1000
        running: event.active && block.compact && compactTitle.overflow > 2 * px
        loops: Animation.Infinite
        onRunningChanged: if (!running) compactTitle.x = 0

        PropertyAction { target: compactTitle; property: "x"; value: 0 }
        PauseAnimation { duration: slide.cycle * 0.18 }
        NumberAnimation { target: compactTitle; property: "x"; to: -compactTitle.overflow - 6 * px; duration: slide.cycle * 0.64 }
        PauseAnimation { duration: slide.cycle * 0.18 }
    }
}
