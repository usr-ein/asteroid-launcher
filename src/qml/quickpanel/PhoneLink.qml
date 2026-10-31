/*
 * Copyright (C) 2026 Samuel Prevost <usr_ein@pm.me>
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
import Nemo.DBus 2.0

// The phone's links.
// - le: whether the phone's LE link is up, as ioslink publishes it on the
//   session bus (org.sonicscrewdriver.ioslink.Phone, Connected). BlueZ alone
//   can't tell for a dual-mode phone. Battery1 may never appear for a bond,
//   and Device1.Connected and ServicesResolved follow either link. ioslink
//   uses Battery1 when it is there, and otherwise checks the link with a
//   GATT read every 30 s. leKnown is false while ioslink isn't running; le is
//   false then.
// - connected: whether any link to the phone is up, from BlueZ's
//   Device1.Connected on the system bus.
// - path: the phone's device object in BlueZ. It is the device behind
//   connman's hotspot service, whose name is bluetooth_<adapter>_<device>.
//   Without that service, it is the first paired device whose icon is
//   "phone"; with none, it is "".
//
// The launcher's quick panel and the Settings app share this file. Keep the
// copies in usr-ein/asteroid-launcher (src/qml/quickpanel/PhoneLink.qml)
// and usr-ein/asteroid-settings (src/qml/PhoneLink.qml) identical below the
// licence header.
Item {
    id: phoneLink

    visible: false

    // connman's hotspot service, to find the phone by its address.
    property string hotspotServicePath: ""
    readonly property string adapterPath: "/org/bluez/hci0"
    property string path: ""
    readonly property bool leKnown: ioslinkPhone.status === DBusInterface.Available
    readonly property bool le: leKnown && ioslinkPhone.connected
    readonly property bool connected: path !== "" && device.connected
    readonly property bool adapterPowered: adapter.powered

    function refresh() {
        var m = /bluetooth_[0-9A-Fa-f]{12}_([0-9A-Fa-f]{12})$/.exec(hotspotServicePath)
        var wanted = m ? m[1].toUpperCase() : ""
        bluez.typedCall("GetManagedObjects", [], function (objects) {
            var byAddress = ""
            var firstPhone = ""
            for (var objectPath in objects) {
                var properties = objects[objectPath]["org.bluez.Device1"]
                if (!properties || !properties.Paired || objectPath.indexOf(adapterPath + "/") !== 0)
                    continue
                if (wanted !== "" && String(properties.Address).replace(/:/g, "") === wanted)
                    byAddress = objectPath
                if (firstPhone === "" && properties.Icon === "phone")
                    firstPhone = objectPath
            }
            phoneLink.path = byAddress !== "" ? byAddress : firstPhone
        }, function (error, message) {
            console.warn("PhoneLink: BlueZ GetManagedObjects failed: " + message)
        })
    }

    onHotspotServicePathChanged: refresh()
    Component.onCompleted: refresh()

    // ioslink's view of the phone's LE link.
    DBusInterface {
        id: ioslinkPhone
        bus: DBus.SessionBus
        service: "org.sonicscrewdriver.ioslink"
        path: "/org/sonicscrewdriver/ioslink"
        iface: "org.sonicscrewdriver.ioslink.Phone"
        watchServiceStatus: true
        propertiesEnabled: true
        property bool connected: false
    }

    DBusInterface {
        id: adapter
        bus: DBus.SystemBus
        service: "org.bluez"
        path: phoneLink.adapterPath
        iface: "org.bluez.Adapter1"
        propertiesEnabled: true
        property bool powered: false
    }

    DBusInterface {
        id: device
        bus: DBus.SystemBus
        service: "org.bluez"
        path: phoneLink.path
        iface: "org.bluez.Device1"
        propertiesEnabled: true
        property bool connected: false
    }

    // Devices come and go as they are paired or removed; GATT objects, which
    // come and go with the LE link, don't matter here.
    DBusInterface {
        id: bluez
        bus: DBus.SystemBus
        service: "org.bluez"
        path: "/"
        iface: "org.freedesktop.DBus.ObjectManager"
        signalsEnabled: true

        function interfacesAdded(objectPath, interfaces) { changed(objectPath) }
        function interfacesRemoved(objectPath, interfaces) { changed(objectPath) }
        function changed(objectPath) {
            if (/^\/org\/bluez\/hci\d+\/dev_[0-9A-F_]+$/.test(objectPath))
                phoneLink.refresh()
        }
    }
}
