/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * A contact sheet of screenshots for sonic/test/test.sh, to look at a whole
 * app list, or a few states of a screen, at once. A scene puts one aside,
 * off the screen, and grabs it with Scene.shot().
 */
import QtQuick 2.9

Rectangle {
    id: sheet

    property string title
    property var files: []
    property var labels: []
    property int columns: 4
    property int cell: 227

    color: "#16181d"
    width: columns * (cell + 16) + 16
    height: header.height + 16 + Math.ceil(files.length / columns) * (cell + 40) + 8

    Text {
        id: header
        x: 16
        y: 12
        width: sheet.width - 32
        text: sheet.title
        color: "#e8ecf2"
        font.pixelSize: 20
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }

    Grid {
        x: 16
        y: header.y + header.height + 16
        columns: sheet.columns
        spacing: 16

        Repeater {
            model: sheet.files

            Column {
                spacing: 6

                Item {
                    width: sheet.cell
                    height: sheet.cell
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: "file://" + modelData
                        sourceSize: Qt.size(454, 454)
                        asynchronous: false
                        cache: false
                        smooth: true
                        mipmap: true
                    }

                    // The watch's round screen, against the sheet.
                    Rectangle {
                        x: -sheet.cell / 4
                        y: x
                        width: sheet.cell * 1.5
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: sheet.cell / 4
                        border.color: sheet.color
                    }
                }

                Text {
                    width: sheet.cell
                    height: 18
                    text: sheet.labels[index] !== undefined ? sheet.labels[index] : ""
                    color: "#98a2b0"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
