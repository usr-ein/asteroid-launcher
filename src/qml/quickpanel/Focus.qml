/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick panel's side of the watch's Focus, which decides every alert on
 * the watch: the alert profiles are gone (Sonic Screwdriver's
 * docs/focus/SKETCH.md, § 3 and § 5). The Focus button, its name under the
 * page dots, and the picker (FocusPicker.qml) read it here.
 *
 * ioslink's Focus interface, on its object on the session bus (the bridge's
 * PROTOCOL.md, § 6.17.3):
 * - State, a JSON, with PropertiesChanged: `current`, the watch's Focus (id,
 *   name, color, base, icon); `source`, "iphone", or "watch" for a Focus
 *   picked on the watch; `iphone`, the iPhone's Focus (id, name); `focuses`,
 *   the table's, in its order, No Focus first; `table`, false until Sonic's
 *   table has reached the watch, when `focuses` holds No Focus alone. A
 *   Focus's id "" is No Focus; its base "sound", "vibration" or "silent"; its
 *   icon a PNG file's path, 128 px, white on clear, or "" for none.
 * - Pick(id): the watch's Focus is id until the iPhone's next Focus change;
 *   the iPhone's own Focus is following it again. An id the table lacks is
 *   org.sonicscrewdriver.ioslink.Focus.Error.NotFound.
 * - Follow(): ends a pick.
 * - org.sonicscrewdriver.ioslink.Focus.Error.Failed: ioslink can't take the
 *   call now.
 * Without ioslink on the bus, or with a State that doesn't read, `available`
 * is false.
 *
 * The icons: ioslink rewrites an icon's file in place, under the same path
 * and with the same State, when only its symbol changes, so nothing tells the
 * launcher. Their images load uncached, from iconUrl(), which changes at
 * each reload(): the panel reloads them each time it becomes visible, and the
 * picker each time it opens.
 */
import QtQuick 2.9
import Nemo.DBus 2.0

Item {
    id: watchFocus

    readonly property string service: "org.sonicscrewdriver.ioslink"
    readonly property string objectPath: "/org/sonicscrewdriver/ioslink"
    readonly property string iface: "org.sonicscrewdriver.ioslink.Focus"

    // No Focus, as ioslink has it before anything is known.
    readonly property var noFocus: ({id: "", name: "No Focus", color: "", base: "vibration", icon: ""})

    // State, parsed; null without ioslink, or without a State that reads.
    readonly property var info: reader.item !== null ? parse(reader.item.state) : null
    readonly property bool available: info !== null
    // The watch's Focus.
    readonly property var current: available ? mode(info.current) : noFocus
    // Picked on the watch, not the iPhone's.
    readonly property bool picked: available && info.source === "watch"
    // The iPhone's Focus: {id, name}.
    readonly property var iphone: available && info.iphone !== null && typeof info.iphone === "object"
                                  ? {id: text(info.iphone.id), name: text(info.iphone.name)} : {id: "", name: ""}
    // Sonic's table has reached the watch.
    readonly property bool table: available && info.table === true
    // The picker's Focuses, in the table's order; No Focus alone without a
    // table.
    readonly property var focuses: {
        if (!available)
            return []
        var list = Array.isArray(info.focuses) ? info.focuses.map(mode) : []
        if (table)
            return list
        var none = list.filter(function(m) { return m.id === "" })
        return [none.length > 0 ? none[0] : (current.id === "" ? current : noFocus)]
    }

    // Bumped by reload(): every icon's URL changes, and loads its file again.
    property int iconEpoch: 0

    // A line to show for 3 s: a Pick() or Follow() that failed.
    signal notice(string text)

    function reload() {
        iconEpoch++
    }

    // A Focus's icon as an image's source, which changes at each reload(), or
    // "" without one.
    function iconUrl(path) {
        if (typeof path !== "string" || path === "")
            return ""
        return "file://" + path.split("/").map(encodeURIComponent).join("/") + "#" + iconEpoch
    }

    // A Focus of the table by its id; one the table lacks counts as No Focus.
    function modeOf(id) {
        var list = focuses
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id)
                return list[i]
        }
        if (current.id === id)
            return current
        for (var j = 0; j < list.length; j++) {
            if (list[j].id === "")
                return list[j]
        }
        return noFocus
    }

    // A base level, as the picker says it.
    function level(base) {
        return base === "sound" ? "Sound and vibration" : base === "silent" ? "Silent" : "Vibration"
    }

    // Pick(id) and Follow(). failed(name), if given, is called after the
    // notice when the call fails.
    function pick(id, failed) {
        call("Pick", [{"type": "s", "value": id}], failed)
    }

    function follow(failed) {
        call("Follow", [], failed)
    }

    function call(method, args, failed) {
        var what = method + (args.length > 0 ? " \"" + args[0].value + "\"" : "")
        if (reader.item === null) {
            fail(what, "org.freedesktop.DBus.Error.ServiceUnknown", "ioslink isn't on the bus", failed)
            return
        }
        reader.item.typedCall(method, args, function() { }, function(name, message) {
            watchFocus.fail(what, name, message, failed)
        })
    }

    function fail(what, name, message, failed) {
        console.log("focus: " + what + " failed: " + name + ": " + message)
        notice(lineFor(name))
        if (failed)
            failed(name)
    }

    // The line for a failed Pick() or Follow(): NotFound is a Focus gone from
    // the table meanwhile; Failed, the bus's NoReply and Timeout, and any
    // other error, a Focus that didn't change.
    function lineFor(error) {
        return error === "org.sonicscrewdriver.ioslink.Focus.Error.NotFound" ? "Focus not found" : "Focus didn't change"
    }

    function text(value) {
        return typeof value === "string" ? value : ""
    }

    // A Focus as State has it, with each field a string: consumers take the
    // fields they know.
    function mode(m) {
        if (m === null || typeof m !== "object")
            return noFocus
        return {id: text(m.id), name: text(m.name), color: text(m.color), base: text(m.base), icon: text(m.icon)}
    }

    function parse(json) {
        var parsed
        try {
            parsed = JSON.parse(json)
        } catch (error) {
            return null
        }
        if (parsed === null || typeof parsed !== "object" || parsed.current === null || typeof parsed.current !== "object")
            return null
        return parsed
    }

    // ioslink on the session bus, and its Focus interface read afresh each
    // time it comes back, as FindPhone.qml reads FindPhone.
    DBusInterface {
        id: onBus
        bus: DBus.SessionBus
        service: watchFocus.service
        path: watchFocus.objectPath
        iface: watchFocus.iface
        watchServiceStatus: true
    }

    Loader {
        id: reader
        active: onBus.status === DBusInterface.Available
        sourceComponent: DBusInterface {
            bus: DBus.SessionBus
            service: watchFocus.service
            path: watchFocus.objectPath
            iface: watchFocus.iface
            propertiesEnabled: true
            property string state: ""
        }
    }
}
