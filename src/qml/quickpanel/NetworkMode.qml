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
import Connman 0.2
import Nemo.DBus 2.0

// The watch's network mode: how it reaches the internet. Each mode is a state
// of connman, so it survives a reboot:
// - "wifi": Wi-Fi is powered. The hotspot doesn't auto-connect and is
//   disconnected.
// - "hotspot": Wi-Fi is off. The hotspot auto-connects and is connected.
// - "none": Wi-Fi is off. The hotspot doesn't auto-connect and is
//   disconnected.
// The hotspot is the phone's Personal Hotspot over classic Bluetooth (PAN):
// connman's service of type "bluetooth". There is no automatic fallback, so
// losing Wi-Fi never brings up the hotspot.
//
// Classic Bluetooth is ioslink's ClassicBluetooth setting. Bluetooth LE, which
// carries notifications and music control, always stays on. With classic off,
// the watch doesn't use classic Bluetooth at all, so there is no hotspot:
// switching classic off in hotspot mode leaves no internet.
//
// The launcher's quick panel and the Settings app share this file. Keep the
// copies in usr-ein/asteroid-launcher (src/qml/quickpanel/NetworkMode.qml)
// and usr-ein/asteroid-settings (src/qml/NetworkMode.qml) identical below the
// licence header.
Item {
    id: networkMode

    visible: false

    // "wifi", "hotspot" or "none", read back from connman.
    readonly property string mode: wifiTechnology.powered ? "wifi" :
                                   hotspotAvailable && hotspotService.autoConnect ? "hotspot" : "none"
    property alias wifi: wifiTechnology
    property alias hotspot: hotspotService
    // Whether connman has the phone's Bluetooth service. It hasn't when the
    // phone isn't paired over classic Bluetooth, or Bluetooth is off.
    readonly property bool hotspotPresent: hotspotService.path !== "" && hotspotService.valid
    // Whether the hotspot can be used: it is present and classic Bluetooth is on.
    readonly property bool hotspotAvailable: hotspotPresent && classicBluetooth

    // Classic Bluetooth on or off. Until ioslink answers, or without ioslink,
    // this reads on, ioslink's own default.
    readonly property bool classicBluetooth: ioslinkSettings.classicBluetooth
    // Whether ioslink runs, so that classic Bluetooth can be switched.
    readonly property bool classicSwitchable: ioslinkSettings.status === DBusInterface.Available

    // The mode after this one in the cycle Wi-Fi, hotspot, none. The hotspot is
    // skipped when it can't be used.
    function nextMode() {
        if (mode === "wifi")
            return hotspotAvailable ? "hotspot" : "none"
        if (mode === "hotspot")
            return "none"
        return "wifi"
    }

    // Puts connman in the given mode. Every setting is written, so this also
    // repairs a mixed state. Returns false if the mode is "hotspot" and the
    // hotspot can't be used.
    function setMode(newMode) {
        if (newMode !== "wifi" && newMode !== "hotspot" && newMode !== "none")
            return false
        if (newMode === "hotspot" && !hotspotAvailable)
            return false

        // Wi-Fi is switched on first and off last, so that mode never reads
        // "none" in between.
        if (newMode === "wifi" && !wifiTechnology.powered)
            wifiTechnology.powered = true

        if (newMode === "hotspot") {
            if (!hotspotService.autoConnect)
                hotspotService.autoConnect = true
            if (!hotspotService.connected && !hotspotService.connecting)
                hotspotService.requestConnect()
        } else {
            stopHotspot()
        }

        if (newMode !== "wifi" && wifiTechnology.powered)
            wifiTechnology.powered = false
        return true
    }

    // Switches classic Bluetooth on or off through ioslink. Before switching it
    // off, the hotspot stops, so that hotspot mode ends as "none".
    function setClassicBluetooth(on) {
        if (!on)
            stopHotspot()
        ioslinkSettings.setProperty("ClassicBluetooth", on)
    }

    // The hotspot stops auto-connecting and disconnects. This applies even
    // while it can't be used, so that connman doesn't connect it on its own
    // once classic Bluetooth is back.
    function stopHotspot() {
        if (!hotspotPresent)
            return
        if (hotspotService.autoConnect)
            hotspotService.autoConnect = false
        if (hotspotService.state !== "idle")
            hotspotService.requestDisconnect()
    }

    // The first Bluetooth service in connman's order. With one phone paired
    // over classic Bluetooth, that is its hotspot.
    function findHotspot() {
        var manager = managerFactory.instance
        var services = manager && manager.available ? manager.servicesList("bluetooth") : []
        hotspotService.path = services.length > 0 ? services[0] : ""
    }

    // Classic Bluetooth can also be switched off elsewhere, for example by the
    // other user interface. The hotspot then stops here too.
    readonly property bool hotspotWithoutClassic: !classicBluetooth && hotspotPresent &&
                                                  (hotspotService.autoConnect || hotspotService.connected ||
                                                   hotspotService.connecting)
    onHotspotWithoutClassicChanged: if (hotspotWithoutClassic) stopHotspot()

    NetworkTechnology {
        id: wifiTechnology
        path: "/net/connman/technology/wifi"
    }

    NetworkService { id: hotspotService }

    NetworkManagerFactory { id: managerFactory }

    Connections {
        target: managerFactory.instance
        function onServicesChanged() { networkMode.findHotspot() }
        function onAvailabilityChanged() { networkMode.findHotspot() }
    }

    // ioslink's settings, on the session bus.
    DBusInterface {
        id: ioslinkSettings
        bus: DBus.SessionBus
        service: "org.sonicscrewdriver.ioslink"
        path: "/org/sonicscrewdriver/ioslink"
        iface: "org.sonicscrewdriver.ioslink.Settings"
        watchServiceStatus: true
        propertiesEnabled: true
        property bool classicBluetooth: true
    }

    Component.onCompleted: findHotspot()
}
