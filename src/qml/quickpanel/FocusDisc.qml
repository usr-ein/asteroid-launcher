/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * A Focus's disc, in the Focus picker and its confirmation: the Focus's
 * colour at 0.75 on black, as the quick panel's toggles tint theirs, or
 * their grey without a colour; and its icon in white, read from its file
 * uncached (Focus.qml's iconUrl()), or a glyph of the watch's own without
 * one.
 */
import QtQuick 2.9
import org.asteroid.controls 1.0

Item {
    id: disc

    // The Focus's colour, "#rrggbb", or "" for none.
    property string tint: ""
    // Its icon, from Focus.qml's iconUrl(), or "" for none.
    property url iconSource: ""
    // The glyph without an icon, and the icon's share of the disc.
    property string glyph: "ios-notifications-outline"
    property real glyphScale: 0.53

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: disc.tint !== "" ? disc.tint : "#2b2f36"
        opacity: disc.tint !== "" ? 0.75 : 1
    }

    Image {
        objectName: "focusIcon"
        visible: disc.iconSource != ""
        anchors.centerIn: parent
        width: parent.width * disc.glyphScale
        height: width
        source: disc.iconSource
        sourceSize: Qt.size(width, height)
        cache: false
    }

    Icon {
        visible: disc.iconSource == ""
        anchors.centerIn: parent
        width: parent.width * disc.glyphScale
        height: width
        name: disc.glyph
        color: "white"
    }
}
