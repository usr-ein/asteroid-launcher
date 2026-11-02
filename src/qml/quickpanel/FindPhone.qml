/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick panel's "Find phone" button's side of ioslink, Sonic
 * Screwdriver's bridge to the iPhone (its find_phone.md, § 3 and § 5): the
 * iPhone rings, through silent mode and Focus, until it's stopped there or
 * here. Never a sound or a vibration on the watch: the button's light is the
 * feedback.
 *
 * ioslink's FindPhone interface, on its object on the session bus (the
 * bridge's PROTOCOL.md, § 6.10):
 * - Ringing: the iPhone rings, as far as the watch knows. It is the button's
 *   light, which has no state of its own.
 * - Ring() and Stop() turn Ringing true or false at once, before the iPhone
 *   answers, and return. A tap that doesn't take puts Ringing back, and sets
 *   Problem.
 * - Available: a session with Sonic that can ring.
 * - Problem, from ProblemAt in Unix seconds: a line to show for 3 s: "Phone
 *   not connected", "Allow alarms in Sonic", "Unlock your iPhone first" or
 *   "Phone didn't answer".
 * - Ring() and Stop() fail with org.sonicscrewdriver.ioslink.FindPhone.
 *   NotConnected without a session, and with org.freedesktop.DBus.Error.
 *   Failed when ioslink was busy or couldn't send; Problem says so too. The
 *   bus's own errors aren't in Problem: no ioslink, or none that answers.
 *
 * tap(): says "Phone not connected" when the iPhone can't ring, without
 * asking anything; otherwise rings, or stops the ring.
 */
import QtQuick 2.9
import Nemo.DBus 2.0

Item {
    id: findPhone

    readonly property string service: "org.sonicscrewdriver.ioslink"
    readonly property string objectPath: "/org/sonicscrewdriver/ioslink"
    readonly property string iface: "org.sonicscrewdriver.ioslink.FindPhone"

    readonly property bool available: reader.item !== null && reader.item.available
    readonly property bool lit: reader.item !== null && reader.item.ringing

    // The line to show for 3 s.
    signal notice(string text)

    function tap() {
        if (!available) {
            notice("Phone not connected")
            return
        }
        var method = lit ? "Stop" : "Ring"
        reader.item.typedCall(method, [], function() { }, function(name, message) {
            findPhone.notice(findPhone.lineFor(name))
            console.log("findphone: " + method + " failed: " + name + ": " + message)
        })
    }

    // The line for a failed Ring() or Stop(), the same as Problem's when
    // ioslink sets it: ioslink busy, or stuck, is no answer; no session, or
    // no ioslink, is no phone.
    function lineFor(error) {
        if (error === "org.freedesktop.DBus.Error.Failed" || error === "org.freedesktop.DBus.Error.NoReply"
                || error === "org.freedesktop.DBus.Error.Timeout")
            return "Phone didn't answer"
        return "Phone not connected"
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

    // A problem is new for 3 s from its time: one read afresh, older, doesn't
    // show. ioslink sets Problem before ProblemAt.
    Connections {
        target: reader.item
        ignoreUnknownSignals: true
        function onProblemAtChanged() {
            var r = reader.item
            if (r.problem !== "" && Math.abs(Date.now() / 1000 - r.problemAt) < 3)
                findPhone.notice(r.problem)
        }
    }
}
