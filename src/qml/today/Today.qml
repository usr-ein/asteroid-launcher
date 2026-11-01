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


/*
 * The Today screen, right of the watch face: the day as a timeline, as the
 * approved mockup draws it (Sonic Screwdriver's watch UI PRD, § 4).
 * - A vertical day, 00:00 to 24:00, that scrolls: hour labels on the left,
 *   faint hour lines across, a red line at now with its time.
 * - Each timed event is a block from its start to its end, in its calendar's
 *   colour: the notebook's colour, which the iPhone sync sets. Events that
 *   overlap share the width (TodayEvent.qml, timeline.js).
 * - The date and the weather on top, with the all-day events as chips under
 *   them, in a band that stays.
 * - While it scrolls, a bubble on the right edge shows the time at the middle
 *   of the screen, and fades out a second after it stops.
 * - It centres on now whenever it comes into view. Nothing moves while it
 *   is out of view: the clock stops and the titles stand still.
 * The events come from the same AgendaModel as before.
 */

import QtQuick 2.9
import org.asteroid.controls 1.0
import org.asteroid.utils 1.0
import org.nemomobile.calendar 1.0
import Nemo.Configuration 1.0
import Nemo.Time 1.0
import 'weathericons.js' as IconTools
import 'timeline.js' as Timeline

Item {
    id: today
    clip: true

    // The mockup's pixel: it is drawn for the watch's 454 × 454.
    readonly property real px: width / 454
    readonly property real ppm: Timeline.PPH / 60 * px
    readonly property real centreY: Timeline.CENTRE_Y * px

    // The current time, from a clock that only runs while the screen shows.
    property date now: nowClock.time
    readonly property real nowMinute: now.getHours() * 60 + now.getMinutes() + now.getSeconds() / 60
    // The time at the middle of the screen, which the bubble shows.
    readonly property real centreMinute: (timeline.contentY + centreY) / ppm

    // The day's events: timed ones laid out as blocks, all-day ones as chips.
    property var blocks: []
    property var chips: []

    property bool peeking: false
    // Whether the agenda has been read once: "No events today" waits for it.
    property bool loaded: false

    WallClock {
        id: todayClock
        enabled: true
        updateFrequency: WallClock.Day
    }

    WallClock {
        id: nowClock
        enabled: today.visible
        updateFrequency: WallClock.Minute
    }

    property int year: todayClock.time.getFullYear()
    property int month: todayClock.time.getMonth()
    property int day: todayClock.time.getDate()

    ConfigurationValue {
        id: timestampDay0
        key: "/org/asteroidos/weather/timestamp-day0"
        defaultValue: 0
    }

    ConfigurationValue {
        id: use12H
        key: "/org/asteroidos/settings/use-12h-format"
        defaultValue: false
        onValueChanged: Qt.callLater(today.relayout)
    }

    ConfigurationValue {
        id: useFahrenheit
        key: "/org/asteroidos/settings/use-fahrenheit"
        defaultValue: false
    }

    property bool weatherAvailable: {
        var day0Date = new Date(timestampDay0.value*1000);
        var daysDiff = Math.round((todayClock.time-day0Date)/(1000*60*60*24));
        return daysDiff < 5 && daysDiff >= 0
    }

    property int dayNb: {
        var day0Date    = new Date(timestampDay0.value*1000);
        var daysDiff = Math.round((todayClock.time-day0Date)/(1000*60*60*24));
        if(daysDiff > 5) daysDiff = 5;
        return daysDiff;
    }

    // "12°", from the weather's Kelvin.
    function convertTemp(val) {
        var celsius = (val-273);
        if(!useFahrenheit.value)
            return celsius + "°";
        else
            return Math.round(((celsius)*9/5) + 32) + "°";
    }

    ConfigurationValue {
        id: owmId
        key: "/org/asteroidos/weather/day" + dayNb + "/id"
        defaultValue: ""
    }
    ConfigurationValue {
        id: minTemp
        key: "/org/asteroidos/weather/day" + dayNb + "/min-temp"
        defaultValue: 273
    }
    ConfigurationValue {
        id: maxTemp
        key: "/org/asteroidos/weather/day" + dayNb + "/max-temp"
        defaultValue: 273
    }

    AgendaModel {
        id: agenda
        startDate: new Date(year, month, day, 0, 0, 0)
        endDate: new Date(year, month, day, 23, 59, 59)
        onUpdated: {
            today.loaded = true
            Qt.callLater(today.relayout)
        }
        onCountChanged: Qt.callLater(today.relayout)
    }

    function relayout() {
        var dayStart = new Date(year, month, day, 0, 0, 0)
        var dayEnd = new Date(year, month, day + 1, 0, 0, 0)
        var timed = [], allDay = []
        for (var i = 0; i < agenda.count; i++) {
            var event = agenda.get(i, AgendaModel.EventObjectRole)
            var occurrence = agenda.get(i, AgendaModel.OccurrenceObjectRole)
            if (!event || !occurrence)
                continue
            var colour = Timeline.calendarColour(event.color)
            if (event.allDay) {
                allDay.push({ title: event.displayLabel, colour: colour })
                continue
            }
            timed.push({
                title: event.displayLabel,
                colour: colour,
                startMin: Timeline.minuteOfDay(occurrence.startTime, dayStart, dayEnd),
                endMin: Timeline.minuteOfDay(occurrence.endTime, dayStart, dayEnd),
                timeText: Timeline.timeRange(occurrence.startTime, occurrence.endTime, use12H.value)
            })
        }
        blocks = Timeline.layout(timed)
        chips = allDay
    }

    function centreOnNow() {
        timeline.cancelFlick()
        timeline.contentY = nowMinute * ppm - centreY
    }

    onVisibleChanged: if (visible) centreOnNow()
    onWidthChanged: centreOnNow()

    Timer {
        id: peekTimeout
        interval: 1000
        onTriggered: today.peeking = false
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Flickable {
        id: timeline
        anchors.fill: parent
        contentWidth: width
        contentHeight: 24 * Timeline.PPH * px
        // 00:00 and 24:00 can each reach the middle of the screen.
        topMargin: centreY
        bottomMargin: height - centreY
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        onMovingChanged: {
            if (moving) {
                peekTimeout.stop()
                today.peeking = true
            } else {
                peekTimeout.restart()
            }
        }

        Repeater {
            model: 25

            Item {
                readonly property int minute: index * 60
                y: index * Timeline.PPH * today.px
                width: timeline.width

                Rectangle {
                    x: Timeline.X0 * today.px
                    width: (454 - Timeline.X0 - 76) * today.px
                    height: Math.max(1, today.px)
                    color: "#1b1f26"
                }

                Text {
                    x: 102 * today.px - width
                    anchors.verticalCenter: parent.top
                    anchors.verticalCenterOffset: 2 * today.px
                    text: Timeline.hourLabel(index, use12H.value)
                    color: "#7d8592"
                    opacity: Math.abs(minute - today.nowMinute) < 14 ? 0 : 1
                    font.pixelSize: 15 * today.px
                    font.weight: Font.Medium

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }
        }

        Repeater {
            model: today.blocks

            TodayEvent {
                block: modelData
                px: today.px
                // Only while the screen shows, and the block is in view.
                active: today.visible && y + height > timeline.contentY
                        && y < timeline.contentY + timeline.height
            }
        }

        Item {
            id: nowLine
            z: 2
            y: today.nowMinute * today.ppm
            width: timeline.width

            Rectangle {
                x: 104 * today.px
                width: (454 - 104 - 76) * today.px
                height: 2 * today.px
                color: "#ff453a"
            }
            Rectangle {
                x: 99 * today.px
                y: -6 * today.px
                width: 10 * today.px
                height: width
                radius: width / 2
                color: "#ff453a"
            }
            Text {
                x: 94 * today.px - width
                anchors.verticalCenter: parent.top
                anchors.verticalCenterOffset: 1 * today.px
                text: Timeline.formatTime(today.now, use12H.value)
                color: "#ff453a"
                font.pixelSize: 15 * today.px
                font.weight: Font.Bold
            }
        }
    }

    Label {
        visible: today.loaded && today.blocks.length === 0
        z: 2
        y: 250 * px
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        //% "No events today"
        text: qsTrId("id-no-events-today") + localeManager.changesObserver
        color: "#8a929e"
        font.pixelSize: 17 * px
    }

    // The date, the weather and the all-day events, over the timeline.
    Item {
        id: band
        z: 3
        width: parent.width
        height: 118 * px

        Rectangle {
            width: parent.width
            height: parent.height * 0.86
            color: "black"
        }
        Rectangle {
            y: parent.height * 0.86
            width: parent.width
            height: parent.height - y
            gradient: Gradient {
                GradientStop { position: 0; color: "black" }
                GradientStop { position: 1; color: "transparent" }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 30 * px
            spacing: 6 * px

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10 * px

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(todayClock.time, "ddd d MMM") + localeManager.changesObserver
                    color: "white"
                    font.pixelSize: 19 * px
                    font.weight: Font.DemiBold
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: weatherAvailable
                    spacing: 4 * px

                    Icon {
                        readonly property string glyph: IconTools.getIconName(owmId.value).replace("-outline", "")
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20 * px
                        height: width
                        name: glyph
                        color: Timeline.weatherColour(glyph)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: convertTemp(maxTemp.value)
                        color: "#c9cfd8"
                        font.pixelSize: 16 * px
                        font.weight: Font.Medium
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: convertTemp(minTemp.value)
                        color: "#7d8592"
                        font.pixelSize: 16 * px
                        font.weight: Font.Medium
                    }
                }
            }

            // Two chips, then "+n" for the rest.
            Row {
                id: chipRow
                readonly property int shown: Math.min(2, today.chips.length)
                readonly property int more: today.chips.length - shown
                readonly property real chipWidth: Math.min(158 * px,
                    (330 * px - (more > 0 ? moreChip.width + spacing : 0) - spacing * (shown - 1)) / Math.max(1, shown))
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6 * px

                Repeater {
                    model: today.chips.slice(0, chipRow.shown)

                    Rectangle {
                        readonly property color colour: modelData.colour
                        width: Math.min(chipRow.chipWidth, chipText.implicitWidth + 31 * px)
                        height: 26 * px
                        radius: height / 2
                        color: Qt.rgba(colour.r * 0.3, colour.g * 0.3, colour.b * 0.3, 1)

                        Rectangle {
                            x: 8 * px
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7 * px
                            height: width
                            radius: width / 2
                            color: parent.colour
                        }
                        Text {
                            id: chipText
                            x: 21 * px
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 31 * px
                            text: modelData.title
                            elide: Text.ElideRight
                            color: Qt.rgba(parent.colour.r * 0.28 + 0.72, parent.colour.g * 0.28 + 0.72,
                                           parent.colour.b * 0.28 + 0.72, 1)
                            font.pixelSize: 14 * px
                            font.weight: Font.Medium
                        }
                    }
                }

                Rectangle {
                    id: moreChip
                    visible: chipRow.more > 0
                    width: moreText.implicitWidth + 18 * px
                    height: 26 * px
                    radius: height / 2
                    color: "#292c2f"

                    Text {
                        id: moreText
                        anchors.centerIn: parent
                        text: "+" + chipRow.more
                        color: "#dee0e4"
                        font.pixelSize: 14 * px
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    // The time at the middle of the screen, while it scrolls: a dashed line
    // across, and the bubble on the right edge.
    Item {
        id: peek
        z: 4
        anchors.fill: parent
        opacity: today.peeking ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: today.peeking ? 100 : 350 } }

        Repeater {
            model: Math.floor((454 - Timeline.X0 - 70) / 8)

            Rectangle {
                x: (Timeline.X0 + index * 8) * today.px
                y: today.centreY
                width: 4 * today.px
                height: Math.max(1, today.px)
                color: Qt.rgba(1, 1, 1, 0.35)
            }
        }

        Rectangle {
            id: bubble
            x: parent.width - 12 * today.px - width
            y: 212 * today.px
            width: Math.max(62 * today.px, bubbleText.implicitWidth + 20 * today.px)
            height: 30 * today.px
            radius: height / 2
            color: "#f2f4f7"

            // The arrow that points at the line.
            Rectangle {
                x: -4.2 * today.px
                anchors.verticalCenter: parent.verticalCenter
                width: 8.5 * today.px
                height: width
                rotation: 45
                color: parent.color
            }
            Text {
                id: bubbleText
                anchors.centerIn: parent
                text: Timeline.formatMinutes(Math.round(today.centreMinute / 5) * 5, use12H.value)
                color: "#0b0d11"
                font.pixelSize: 16 * today.px
                font.weight: Font.Bold
            }
        }
    }
}
