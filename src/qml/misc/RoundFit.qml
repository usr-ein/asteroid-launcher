/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The round fit: the launcher's one way to scroll a lot on the round screen,
 * as the round-fit reader that Sam approved in P-019 draws its text (Sonic
 * Screwdriver's docs/prd/watch_ui.md, "The round-fit reader"; its maths is
 * ai/watch/RoundText.qml's).
 *
 * What scrolls is drawn full size at the middle of the screen, `zoom` times
 * its own size; above and below, each row is scaled to the circle's chord at
 * its height, down to minScale, and fades out at the rim. Nothing overlaps:
 * the content is squeezed toward the rim, not cut, since the map from the
 * content to the screen grows by the scale where it is (dY = scale(Y) dy),
 * from the middle outward.
 *
 * It's a Flickable's press and drag, and the maths; the caller draws. Give it
 * `contentHeight` (the content's height at its own size) and `rowWidth` (a
 * full-size row's width, at its own size), then place each piece with:
 *   mapY(y)        the screen y of the content's y (both in this item's px)
 *   scaleAt(Y)     the scale of a row at the screen's Y, zoom included
 *   opacityAt(Y)   its opacity, which fades at the rim
 *   mapX(x, s)     the screen x of a row's x, scaled by s about originX
 * A row: an Item at y: mapY(its y), with a Scale transform (origin.x originX,
 * xScale and yScale scaleAt(y)) and opacity opacityAt(y). A block that spans
 * the content from top to bottom: mapY each end apart, so blocks that touch
 * keep touching.
 * position is the content's y at the middle; positionTo(y) moves it there.
 * With more than a few pieces, place them all in one pass on
 * positionChanged (and tableChanged), assigning y, scale and opacity, rather
 * than a binding each: on the watch, a binding per piece halved the frame
 * rate of the Today screen (P-031). Today.qml's layout() is the example.
 *
 * Rows that keep their own height, such as buttons among lines of text,
 * can't follow mapY: it squeezes all the content toward the rim, and a row
 * that keeps its height would overlap its neighbours there. walk(rows) places
 * them instead, as the reader does: the opened notification's lines and
 * pills (NotificationView.qml, P-032).
 *
 * The pieces are drawn above the Flickable that scrolls them, which then
 * never sees a press on a piece that takes it: a MouseArea on one would stop
 * the scroll from there. Such pieces go in `tappable` instead: a layer inside
 * the Flickable that stays put on the screen, placed in the screen's
 * coordinates like the others. The Flickable sees their press first, and
 * takes it over when it turns into a drag; a MouseArea there gets its click
 * otherwise (NotificationView.qml's pills, P-032). A TapHandler there took
 * mouse taps in the harness, but not the watch's touches.
 *
 * Its shape is the constants below, the reader's own; a screen's sizes are
 * its own constants (the Today screen's: timeline.js).
 */
import QtQuick 2.9

Item {
    id: fit

    // ---- the shape: change it here ----
    // The share of the circle's chord that a row may fill at its height.
    property real chordMargin: 0.88
    // The smallest a row gets, near the top and the bottom, as a share of the
    // middle's size.
    property real minScale: 0.42
    // A row fades out between fadeStart and fadeStart - fadeWidth of the
    // radius from the middle.
    property real fadeStart: 0.97
    property real fadeWidth: 0.22

    // ---- what it shows ----
    // The middle's size, as a multiple of the content's own.
    property real zoom: 1
    // A full-size row's width, at the content's own size, and the x that rows
    // shrink about.
    property real rowWidth: width * 0.84
    property real originX: width / 2
    property real contentHeight: 0
    // The content's y at the middle of the screen.
    readonly property real position: (flick.contentY + flick.topMargin) / zoom
    readonly property alias moving: flick.moving
    readonly property real radius: Math.min(width, height) / 2
    // The layer for pieces that take taps (see above): the screen's size and
    // coordinates, inside the Flickable.
    readonly property alias tappable: screenLayer

    function positionTo(y) {
        flick.cancelFlick()
        flick.contentY = Math.max(0, Math.min(contentHeight, y)) * zoom - flick.topMargin
    }

    // The scale of a row whose middle is at the screen's Y (a line's own y; a
    // taller piece's centre, or it overlaps its neighbour): the circle's
    // chord there, less the margin, over the row's full width, between
    // minScale and 1; times zoom.
    function scaleAt(Y) {
        var d = Y - height / 2
        var chord = 2 * Math.sqrt(Math.max(0, radius * radius - d * d)) * chordMargin
        return zoom * Math.max(minScale, Math.min(1, chord / (rowWidth * zoom)))
    }

    function opacityAt(Y) {
        return Math.max(0, Math.min(1, (radius * fadeStart - Math.abs(Y - height / 2)) / (radius * fadeWidth)))
    }

    function mapX(x, s) {
        return originX + (x - originX) * s
    }

    // The screen y of the content's y. The map from a distance from the middle
    // in the content (at the middle's size) to one on the screen doesn't
    // depend on the position, so it's a table, made once per shape: one entry
    // a pixel, out to past the rim.
    property var table: [0]

    function makeTable() {
        var t = [0]
        var Y = 0
        var limit = radius + 4
        var unit = zoom
        // one pixel of the content, at the middle's size, a step (midpoint rule)
        while (Y < limit && t.length < 8000 && radius > 0) {
            var k1 = scaleAt(height / 2 + Y) / unit
            Y += scaleAt(height / 2 + Y + k1 / 2) / unit
            t.push(Y)
        }
        table = t
    }

    function mapY(y) {
        var d = (y - position) * zoom
        var a = Math.abs(d)
        var i = Math.floor(a)
        var t = table
        // Past the rim, off the screen: on at the smallest scale, so that the
        // map keeps rising.
        var n = t.length - 1
        var Y = i >= n ? t[n] + (a - n) * minScale : t[i] + (t[i + 1] - t[i]) * (a - i)
        return height / 2 + (d < 0 ? -Y : Y)
    }

    // The reader's placement (Sonic Screwdriver's ai/watch/RoundText.qml,
    // place()), for rows of their own heights: from the row nearest the
    // middle outward, each step the two rows' half heights and the gap
    // between them, each at its own scale, so that none overlap. A row is
    // { y, h, gap, fixed }: y its middle in the content, h its height and gap
    // the space before it, at the content's own size; fixed for a row whose
    // height doesn't zoom, such as a button, which then counts at its own
    // size. A row's scale is scaleAt at its middle, not its top, or a tall row
    // would overlap its neighbour below the middle. It returns each row's
    // screen y, its middle, with the content's `at` at the middle (the
    // position when left out).
    function walk(rows, at) {
        var pos = at === undefined ? position : at
        var n = rows.length
        var Y = new Array(n)
        if (n === 0)
            return Y
        var c = 0
        for (var i = 1; i < n; i++) {
            if (Math.abs(rows[i].y - pos) < Math.abs(rows[c].y - pos))
                c = i
        }
        Y[c] = height / 2 + (rows[c].y - pos) * zoom
        var a, b, sa, sb
        for (var j = c + 1; j < n; j++) {
            a = rows[j - 1]
            b = rows[j]
            sa = a.fixed ? 1 : scaleAt(Y[j - 1])
            sb = b.fixed ? 1 : scaleAt(Y[j - 1] + (a.h / 2 + b.gap + b.h / 2) * sa)
            Y[j] = Y[j - 1] + a.h / 2 * sa + b.gap * (sa + sb) / 2 + b.h / 2 * sb
        }
        for (var k = c - 1; k >= 0; k--) {
            a = rows[k + 1]
            b = rows[k]
            sa = a.fixed ? 1 : scaleAt(Y[k + 1])
            sb = b.fixed ? 1 : scaleAt(Y[k + 1] - (a.h / 2 + a.gap + b.h / 2) * sa)
            Y[k] = Y[k + 1] - a.h / 2 * sa - a.gap * (sa + sb) / 2 - b.h / 2 * sb
        }
        return Y
    }

    onWidthChanged: Qt.callLater(makeTable)
    onHeightChanged: Qt.callLater(makeTable)
    onZoomChanged: Qt.callLater(makeTable)
    onRowWidthChanged: Qt.callLater(makeTable)
    onChordMarginChanged: Qt.callLater(makeTable)
    onMinScaleChanged: Qt.callLater(makeTable)
    Component.onCompleted: makeTable()

    // The press and the drag: under the finger, the middle moves one to one.
    Flickable {
        id: flick
        objectName: "roundFitFlick"
        anchors.fill: parent
        contentWidth: width
        contentHeight: fit.contentHeight * fit.zoom
        // The content's start and its end can each reach the middle.
        topMargin: height / 2
        bottomMargin: height / 2
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        // In the content, at the content's y that's at the top of the
        // screen: so it stays put while the content moves.
        Item {
            id: screenLayer
            y: flick.contentY
            width: flick.width
            height: flick.height
        }
    }
}
