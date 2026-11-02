/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick panel's "Find phone" button's side of ioslink, Sonic
 * Screwdriver's bridge to the iPhone (its find_phone.md, § 3 and § 5): the
 * iPhone rings, through silent mode and Focus, until it's stopped there or
 * here. Never a sound or a vibration on the watch: the button's light is the
 * feedback.
 *
 * ioslink's FindPhone interface, on its object on the session bus:
 * - Ring() and Stop();
 * - Ringing: the iPhone rings;
 * - Available: the iPhone is connected and can ring;
 * - Problem, from ProblemAt in Unix seconds: a line to show for 3 s, such as
 *   "Allow alarms in Sonic".
 *
 * tap(): rings when idle, stops when ringing, and says "Phone not connected"
 * when the iPhone can't ring, without asking anything. The button lights at
 * a tap that rings, before ioslink's answer, and goes dark at a tap that
 * stops; then it follows Ringing.
 */
import QtQuick 2.9
import Nemo.DBus 2.0

Item {
    id: findPhone

    readonly property string service: "org.sonicscrewdriver.ioslink"
    readonly property string objectPath: "/org/sonicscrewdriver/ioslink"
    readonly property string iface: "org.sonicscrewdriver.ioslink.FindPhone"

    readonly property bool available: reader.item !== null && reader.item.available
    // Lit: ringing, or asked to ring and waiting for the answer, unless asked
    // to stop.
    readonly property bool lit: !stopping && (asking || (reader.item !== null && reader.item.ringing))

    // The line to show for 3 s.
    signal notice(string text)

    property bool asking: false
    property bool stopping: false

    function tap() {
        if (lit) {
            asking = false
            stopping = true
            settle.restart()
            call("Stop")
        } else if (!available) {
            notice("Phone not connected")
        } else {
            stopping = false
            asking = true
            settle.restart()
            call("Ring")
        }
    }

    function call(method) {
        reader.item.typedCall(method, [], function() { }, function(error) {
            findPhone.asking = false
            findPhone.stopping = false
            findPhone.notice("Phone not connected")
            console.log("findphone: " + method + " failed: " + error)
        })
    }

    // At most 5 s of light, or dark, of its own, without ioslink's answer.
    Timer {
        id: settle
        interval: 5000
        onTriggered: {
            findPhone.asking = false
            findPhone.stopping = false
        }
    }

    // ioslink on the session bus, and its FindPhone interface read afresh
    // each time it comes back, as the music face reads its Like.
    DBusInterface {
        id: onBus
        bus: DBus.SessionBus
        service: findPhone.service
        path: findPhone.objectPath
        iface: findPhone.iface
        watchServiceStatus: true
    }

    Loader {
        id: reader
        active: onBus.status === DBusInterface.Available
        sourceComponent: DBusInterface {
            bus: DBus.SessionBus
            service: findPhone.service
            path: findPhone.objectPath
            iface: findPhone.iface
            propertiesEnabled: true
            property bool ringing: false
            property bool available: false
            property string problem: ""
            property real problemAt: 0
        }
    }

    Connections {
        target: reader.item
        ignoreUnknownSignals: true
        function onRingingChanged() {
            findPhone.asking = false
            findPhone.stopping = false
        }
        // A problem is new for 3 s from its time: one read afresh, older,
        // doesn't show.
        function onProblemAtChanged() {
            var r = reader.item
            if (r.problem !== "" && Math.abs(Date.now() / 1000 - r.problemAt) < 3) {
                findPhone.asking = false
                findPhone.notice(r.problem)
            }
        }
    }
}
