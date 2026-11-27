/*
 * Ubuntu Plus — Settings landing (Stage 5, full IA rework, v2 cards)
 *
 * A single uncategorized-top entry whose entry-component renders the
 * entire modern landing: grouped card sections with list rows and live
 * current values, replacing the stock icon grid (all stock entries are
 * demoted to the unrendered "hub-internal" category but stay loaded,
 * deep-linkable and pushable — no stock page is modified).
 *
 * Navigation: rows call the shell root's loadPluginByName() (same code
 * path as stock grid clicks); fallback is the supported settings://
 * deep link. Search: binds pluginManager.filter (set by the stock
 * search header) and filters rows in place.
 *
 * State honesty: every value binds to a live backend (QMenuModel
 * indicator actions, upower via LomiriBatteryPanel). A value that is
 * unavailable renders as an empty string — never a placeholder.
 *
 * Copyright (C) 2026 Ubuntu Plus (husky port)
 * GPL-3.0 (same terms as the surrounding lomiri-system-settings files)
 */

import QtQuick 2.15
import QMenuModel 1.0
import SystemSettings 1.0
import SystemSettings.ListItems 1.0 as SettingsListItems
import Lomiri.Components 1.3
import Lomiri.SystemSettings.Battery 1.0

Item {
    id: root
    objectName: "ubuntuPlusLanding"

    // Required by UncategorizedItemsView's highlight Binding.
    property color color: "transparent"

    // Shell root (MainView) + its PluginManager, found by parent walk.
    property var view: null
    property var mgr: null

    readonly property string searchText: (mgr && mgr.filter) ? mgr.filter.toLowerCase() : ""

    Component.onCompleted: {
        var p = root;
        while (p.parent) {
            p = p.parent;
        }
        if (p && p.loadPluginByName !== undefined && p.pluginManager !== undefined) {
            view = p;
            mgr = p.pluginManager;
        } else {
            console.warn("ubuntu-plus landing: shell root not found, deep-link fallback active");
        }
    }

    function nav(name) {
        if (view) {
            view.loadPluginByName(name);
        } else {
            Qt.openUrlExternally("settings:///system/" + name);
        }
    }

    function pluginVisible(name) {
        if (!mgr) {
            return true;
        }
        var p = mgr.getByName(name);
        return p ? p.visible : false;
    }

    // Row filter for the stock search header: matches row title and
    // extra keywords against pluginManager.filter.
    function matches(title) {
        if (!searchText) {
            return true;
        }
        for (var i = 0; i < arguments.length; i++) {
            if (arguments[i].toLowerCase().indexOf(searchText) !== -1) {
                return true;
            }
        }
        return false;
    }

    function boolText(state) {
        if (state === undefined || state === null) {
            return "";
        }
        return state === true ? i18n.tr("On") : i18n.tr("Off");
    }

    function percentText(fraction) {
        if (fraction === undefined || fraction === null || isNaN(fraction)) {
            return "";
        }
        return Math.round(fraction * 100) + "%";
    }

    // ----- live backends (same bus objects the indicator pages drive) -----

    QDBusActionGroup {
        id: networkGroup
        busType: DBus.SessionBus
        busName: "com.lomiri.indicator.network"
        objectPath: "/com/lomiri/indicator/network"
        property var wifi: action("wifi.enable")
        property var cellularLabel: action("modem.1::status-label")
        Component.onCompleted: start()
    }

    QDBusActionGroup {
        id: bluetoothGroup
        busType: DBus.SessionBus
        busName: "org.ayatana.indicator.bluetooth"
        objectPath: "/org/ayatana/indicator/bluetooth"
        property var bt: action("bluetooth-enabled")
        Component.onCompleted: start()
    }

    QDBusActionGroup {
        id: soundGroup
        busType: DBus.SessionBus
        busName: "org.ayatana.indicator.sound"
        objectPath: "/org/ayatana/indicator/sound"
        property var silent: action("silent-mode")
        property var volume: action("volume")
        Component.onCompleted: start()
    }

    QDBusActionGroup {
        id: displayGroup
        busType: DBus.SessionBus
        busName: "org.ayatana.indicator.display"
        objectPath: "/org/ayatana/indicator/display"
        property var brightness: action("brightness")
        Component.onCompleted: start()
    }

    LomiriBatteryPanel {
        id: batteryPanel
    }

    readonly property string batteryValue: {
        var b = batteryPanel.primaryBattery;
        if (!b || isNaN(b.batteryLevel)) {
            return "";
        }
        var text = Math.round(b.batteryLevel) + "%";
        if (b.state === 1) {
            text += " · " + i18n.tr("Charging");
        } else if (b.state === 4) {
            text += " · " + i18n.tr("Charged");
        }
        return text;
    }

    readonly property string soundValue: {
        if (soundGroup.silent && soundGroup.silent.state === true) {
            return i18n.tr("Silent");
        }
        return percentText(soundGroup.volume ? soundGroup.volume.state : undefined);
    }

    // ----- layout -----

    height: mainColumn.height

    component RowIcon: Icon {
        width: height
        height: units.gu(2.5)
        SlotsLayout.position: SlotsLayout.First
    }

    Column {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: units.gu(1)

        // ================= NETWORK =================
        SettingsItemTitle {
            text: i18n.tr("Network")
            visible: wifiRow.visible || cellularRow.visible ||
                     bluetoothRow.visible || moreConnectionsRow.visible
        }

        Rectangle {
            visible: wifiRow.visible || cellularRow.visible ||
                     bluetoothRow.visible || moreConnectionsRow.visible
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: units.gu(1)
            anchors.rightMargin: units.gu(1)
            height: networkCard.implicitHeight
            radius: units.gu(1.5)
            color: theme.palette.normal.base
            clip: true

            Column {
                id: networkCard
                width: parent.width

                SettingsListItems.SingleValueProgression {
                    id: wifiRow
                    objectName: "landingWifi"
                    text: i18n.tr("Wi-Fi")
                    RowIcon { source: "image://theme/wifi-high" }
                    value: root.boolText(networkGroup.wifi ? networkGroup.wifi.state : undefined)
                    visible: root.matches(text, "wifi", "wireless", "internet")
                    onClicked: root.nav("wifi")
                }

                SettingsListItems.SingleValueProgression {
                    id: cellularRow
                    objectName: "landingCellular"
                    text: i18n.tr("Cellular")
                    RowIcon { source: "image://theme/gsm-3g-high" }
                    value: (networkGroup.cellularLabel &&
                            networkGroup.cellularLabel.state !== undefined &&
                            networkGroup.cellularLabel.state !== "")
                           ? networkGroup.cellularLabel.state : ""
                    visible: root.pluginVisible("cellular") &&
                             root.matches(text, "mobile", "data", "sim", "operator")
                    onClicked: root.nav("cellular")
                }

                SettingsListItems.SingleValueProgression {
                    id: bluetoothRow
                    objectName: "landingBluetooth"
                    text: i18n.tr("Bluetooth")
                    RowIcon { source: "image://theme/bluetooth-active" }
                    value: root.boolText(bluetoothGroup.bt ? bluetoothGroup.bt.state : undefined)
                    visible: root.matches(text, "bt", "pairing", "devices")
                    onClicked: root.nav("bluetooth")
                }

                SettingsListItems.IconProgression {
                    id: moreConnectionsRow
                    objectName: "landingMoreConnections"
                    text: i18n.tr("More connections")
                    iconSource: "image://theme/preferences-network-hotspot-symbolic"
                    showDivider: false
                    visible: root.matches(text, "hotspot", "tethering", "vpn", "nfc")
                    onClicked: root.nav("hub-connections")
                }
            }
        }

        // ================= PERSONAL =================
        SettingsItemTitle {
            text: i18n.tr("Personal")
            visible: personalizationRow.visible || soundRow.visible ||
                     notificationsRow.visible || accountsRow.visible ||
                     languageRow.visible
        }

        Rectangle {
            visible: personalizationRow.visible || soundRow.visible ||
                     notificationsRow.visible || accountsRow.visible ||
                     languageRow.visible
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: units.gu(1)
            anchors.rightMargin: units.gu(1)
            height: personalCard.implicitHeight
            radius: units.gu(1.5)
            color: theme.palette.normal.base
            clip: true

            Column {
                id: personalCard
                width: parent.width

                SettingsListItems.IconProgression {
                    id: personalizationRow
                    objectName: "landingPersonalization"
                    text: i18n.tr("Personalization")
                    iconSource: "image://theme/preferences-desktop-wallpaper-symbolic"
                    visible: root.matches(text, "wallpaper", "background", "appearance",
                                          "theme", "launcher", "gestures")
                    onClicked: root.nav("hub-personalization")
                }

                SettingsListItems.SingleValueProgression {
                    id: soundRow
                    objectName: "landingSound"
                    text: i18n.tr("Sound & haptics")
                    RowIcon { source: "image://theme/preferences-desktop-sounds-symbolic" }
                    value: root.soundValue
                    visible: root.matches(text, "sound", "volume", "ringtone",
                                          "vibrate", "silent", "haptics")
                    onClicked: root.nav("sound")
                }

                SettingsListItems.IconProgression {
                    id: notificationsRow
                    objectName: "landingNotifications"
                    text: i18n.tr("Notifications")
                    iconSource: "image://theme/preferences-desktop-notifications-symbolic"
                    visible: root.matches(text, "alerts", "banners")
                    onClicked: root.nav("notifications")
                }

                SettingsListItems.IconProgression {
                    id: accountsRow
                    objectName: "landingAccounts"
                    text: i18n.tr("Accounts")
                    iconSource: "image://theme/preferences-desktop-accounts-symbolic"
                    visible: root.matches(text, "online", "login", "sync")
                    onClicked: root.nav("online-accounts")
                }

                SettingsListItems.IconProgression {
                    id: languageRow
                    objectName: "landingLanguage"
                    text: i18n.tr("Language & Text")
                    iconSource: "image://theme/preferences-desktop-locale-symbolic"
                    showDivider: false
                    visible: root.matches(text, "keyboard", "layouts", "input",
                                          "region", "spelling")
                    onClicked: root.nav("language")
                }
            }
        }

        // ================= SYSTEM =================
        SettingsItemTitle {
            text: i18n.tr("System")
            visible: batteryRow.visible || brightnessRow.visible ||
                     timeDateRow.visible || securityRow.visible ||
                     systemHubRow.visible
        }

        Rectangle {
            visible: batteryRow.visible || brightnessRow.visible ||
                     timeDateRow.visible || securityRow.visible ||
                     systemHubRow.visible
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: units.gu(1)
            anchors.rightMargin: units.gu(1)
            height: systemCard.implicitHeight
            radius: units.gu(1.5)
            color: theme.palette.normal.base
            clip: true

            Column {
                id: systemCard
                width: parent.width

                SettingsListItems.SingleValueProgression {
                    id: batteryRow
                    objectName: "landingBattery"
                    text: i18n.tr("Battery")
                    RowIcon { source: "image://theme/battery-080" }
                    value: root.batteryValue
                    visible: root.matches(text, "power", "charging", "suspend",
                                          "sleep", "standby")
                    onClicked: root.nav("battery")
                }

                SettingsListItems.SingleValueProgression {
                    id: brightnessRow
                    objectName: "landingBrightness"
                    text: i18n.tr("Brightness")
                    RowIcon { source: "image://theme/display-brightness-symbolic" }
                    value: root.percentText(displayGroup.brightness ?
                                            displayGroup.brightness.state : undefined)
                    visible: root.matches(text, "display", "screen", "auto")
                    onClicked: root.nav("brightness")
                }

                SettingsListItems.IconProgression {
                    id: timeDateRow
                    objectName: "landingTimeDate"
                    text: i18n.tr("Time and Date")
                    iconSource: "image://theme/preferences-system-time-symbolic"
                    visible: root.matches(text, "clock", "timezone", "alarm")
                    onClicked: root.nav("time-date")
                }

                SettingsListItems.IconProgression {
                    id: securityRow
                    objectName: "landingSecurity"
                    text: i18n.tr("Security & Privacy")
                    iconSource: "image://theme/preferences-system-privacy-symbolic"
                    visible: root.matches(text, "lock", "pin", "password", "encryption",
                                          "permissions", "location", "fingerprint")
                    onClicked: root.nav("security-privacy")
                }

                SettingsListItems.IconProgression {
                    id: systemHubRow
                    objectName: "landingSystemHub"
                    text: i18n.tr("System & updates")
                    iconSource: "image://theme/preferences-system-updates-symbolic"
                    showDivider: false
                    visible: root.matches(text, "updates", "usb", "phone", "libertine",
                                          "reset", "factory")
                    onClicked: root.nav("hub-system")
                }
            }
        }

        // ================= BOTTOM =================
        Rectangle {
            visible: aboutRow.visible
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: units.gu(1)
            anchors.rightMargin: units.gu(1)
            height: aboutCard.implicitHeight
            radius: units.gu(1.5)
            color: theme.palette.normal.base
            clip: true

            Column {
                id: aboutCard
                width: parent.width

                SettingsListItems.IconProgression {
                    id: aboutRow
                    objectName: "landingAbout"
                    text: i18n.tr("About phone")
                    iconSource: "image://theme/info"
                    showDivider: false
                    visible: root.matches(text, "about", "device", "version", "kernel",
                                          "build", "storage", "developer", "imei")
                    onClicked: root.nav("about")
                }
            }
        }

        // Empty search result hint
        Label {
            objectName: "landingNoResults"
            visible: root.searchText !== "" &&
                     !(wifiRow.visible || cellularRow.visible || bluetoothRow.visible ||
                       moreConnectionsRow.visible || personalizationRow.visible ||
                       soundRow.visible || notificationsRow.visible || accountsRow.visible ||
                       languageRow.visible || batteryRow.visible || brightnessRow.visible ||
                       timeDateRow.visible || securityRow.visible || systemHubRow.visible ||
                       aboutRow.visible)
            height: visible ? units.gu(6) : 0
            anchors.horizontalCenter: parent.horizontalCenter
            verticalAlignment: Text.AlignVCenter
            text: i18n.tr("No matching settings")
            color: theme.palette.normal.backgroundSecondaryText
            fontSize: "medium"
        }
    }
}
