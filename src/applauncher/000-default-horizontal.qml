/*
 * Copyright (C) 2022 Timo Könnecke <github.com/eLtMosen>
 *               2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 *               2012 Timur Kristóf <venemo@fedoraproject.org>
 *               2011 Tom Swindell <t.swindell@rubyx.co.uk>
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

Item {
    property alias currentIndex: appsListView.currentIndex
    property alias count: appsListView.count
    property real tutorialScroll:  0.0
    property bool fakePressed: false

    // "Alarm Clock" to "Alarm clock": each word after the first that is only
    // capitalised goes lower case. An acronym, such as "GPS", stays.
    function sentenceCase(title) {
        var words = title.split(" ")
        for (var i = 1; i < words.length; i++) {
            var word = words[i]
            if (word.length > 1 && word.charAt(0) !== word.charAt(0).toLowerCase()
                    && word.slice(1) === word.slice(1).toLowerCase())
                words[i] = word.toLowerCase()
        }
        return words.join(" ")
    }

    anchors.fill: parent
    ListView {
        id: appsListView

        orientation: ListView.Horizontal
        snapMode: ListView.SnapToItem
        width: parent.width
	height: parent.width > parent.height ? parent.height : parent.width
	contentX: tutorialScroll
        anchors.centerIn: parent
        clip: true

        property int currentPos: 0

        onCurrentPosChanged: {
            if (grid.currentVerticalPos !== 1)
                return
            rightIndicator.animate()
            leftIndicator.animate()
            topIndicator.animate()
            bottomIndicator.animate()
        }

        // The list opens on its first app. Once it has been left for the
        // watch face, by a swipe, an app closing or the display going off, it
        // goes back to the start, out of sight. Coming back from a minimised
        // app keeps the page.
        Timer {
            id: backToStart
            interval: 400
            onTriggered: appsListView.positionViewAtBeginning()
        }

        Connections {
            target: grid
            function onCurrentVerticalPosChanged() {
                if (grid.currentVerticalPos === 1) {
                    backToStart.stop()
                    grid.changeAllowedDirections()
                } else {
                    backToStart.restart()
                }
            }
        }

        model: launcherModel

        delegate: MouseArea {
            id: launcherItem

            readonly property bool down: launcherItem.pressed || fakePressed

            width: appsListView.width > appsListView.height ? appsListView.height : appsListView.width
            height: width
            enabled: !appsListView.dragging

            onClicked: model.object.launchApplication()

            // The app's logo, the size of the stock icon circle, and its name
            // under it, centred together on the page.
            Item {
                id: badge

                width: launcherItem.width * .65
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                y: (launcherItem.height - height - iconText.anchors.topMargin - iconText.height) / 2
                scale: launcherItem.down ? .94 : 1
                opacity: launcherItem.down ? .7 : 1

                Behavior on scale { NumberAnimation { duration: 100 } }
                Behavior on opacity { NumberAnimation { duration: 100 } }

                // Sonic's own logo, compiled in from sonic/icons/.
                Image {
                    anchors.fill: parent
                    visible: model.logo !== ""
                    source: model.logo
                    sourceSize.width: width
                    sourceSize.height: height
                }

                // Any other app: the stock drawing, its icon on a circle, in
                // the dark theme's greys.
                Rectangle {
                    anchors.fill: parent
                    visible: model.logo === ""
                    radius: width / 2
                    color: "#262a31"

                    Icon {
                        anchors.centerIn: parent
                        width: parent.width * .46
                        height: width
                        name: model.object.iconId === "" ? "ios-help" : model.object.iconId
                        color: "#d5dae1"
                    }
                }
            }

            Label {
                id: iconText

                text: sentenceCase(model.object.title) + localeManager.changesObserver
                anchors {
                    top: badge.bottom
                    topMargin: launcherItem.height * .03
                    horizontalCenter: parent.horizontalCenter
                }
                width: parent.width * .7
                horizontalAlignment: Text.AlignHCenter
                color: launcherItem.down ? "#8a929e" : "#c9cfd8"
                font {
                    pixelSize: launcherItem.height * .044
                    styleName: "Medium"
                }
            }
        }

        Component.onCompleted: {
            launcherCenterColor = alb.centerColor(launcherModel.get(0).filePath);
            launcherOuterColor = alb.outerColor(launcherModel.get(0).filePath);

            toLeftAllowed = Qt.binding(function() { return !atXEnd })
            toRightAllowed = Qt.binding(function() { return !atXBeginning })

            toTopAllowed = false
            toBottomAllowed = true
            forbidTop = false
            forbidBottom = false
            forbidLeft = false
            forbidRight = false
            launcherColorOverride = false
            if (grid.currentVerticalPos === 1) {
                grid.changeAllowedDirections()
            }
        }

        onContentXChanged: {
            var lowerStop = Math.floor(contentX/appsListView.width)
            var upperStop = lowerStop+1
            var ratio = (contentX%appsListView.width)/appsListView.width

            if(upperStop + 1 > launcherModel.itemCount || ratio === 0) {
                launcherCenterColor = alb.centerColor(launcherModel.get(lowerStop).filePath);
                launcherOuterColor = alb.outerColor(launcherModel.get(lowerStop).filePath);
                return;
            }

            if(lowerStop < 0) {
                launcherCenterColor = alb.centerColor(launcherModel.get(0).filePath);
                launcherOuterColor = alb.outerColor(launcherModel.get(0).filePath);
                return;
            }

            var upperCenterColor = alb.centerColor(launcherModel.get(upperStop).filePath);
            var lowerCenterColor = alb.centerColor(launcherModel.get(lowerStop).filePath);

            launcherCenterColor = Qt.rgba(
                        upperCenterColor.r * ratio + lowerCenterColor.r * (1-ratio),
                        upperCenterColor.g * ratio + lowerCenterColor.g * (1-ratio),
                        upperCenterColor.b * ratio + lowerCenterColor.b * (1-ratio)
                    );

            var upperOuterColor = alb.outerColor(launcherModel.get(upperStop).filePath);
            var lowerOuterColor = alb.outerColor(launcherModel.get(lowerStop).filePath);

            launcherOuterColor = Qt.rgba(
                        upperOuterColor.r * ratio + lowerOuterColor.r * (1-ratio),
                        upperOuterColor.g * ratio + lowerOuterColor.g * (1-ratio),
                        upperOuterColor.b * ratio + lowerOuterColor.b * (1-ratio)
                    );

            currentPos = Math.round(lowerStop+ratio)
        }
    }
}
