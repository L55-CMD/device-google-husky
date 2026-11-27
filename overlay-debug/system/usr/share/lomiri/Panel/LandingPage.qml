/*
 * Ubuntu Plus — Quick Controls landing (Stage 4B v5, mockup 06)
 *
 * The pull-down panel's landing page per the approved v4.1 design:
 *  - "Controls" header + device · battery subtitle (upower via BatteryMonitor)
 *  - coloured state tiles (tap = toggle, long-press = indicator submenu)
 *  - brightness + volume sliders (same backend actions as the
 *    indicator pages / BrightnessControl.qml)
 *
 * No new backends: every control binds to existing GMenu actions.
 * No torch tile: no flashlight backend exists on this image (spec rule).
 *
 * Copyright (C) 2026 Ubuntu Plus (husky port)
 * GPL-3.0 (same terms as the surrounding Lomiri shell files)
 */

import QtQuick 2.15
import Lomiri.Components 1.3
import QMenuModel 1.0 as QMenuModel
import BatteryMonitor 1.0

Item {
    id: root
    objectName: "indicatorLandingPage"

    // Deep link into an indicator page shown as overlay submenu.
    signal submenuRequested(var descriptor)

    // Indicator connection descriptors (same bus objects as the groups).
    QtObject {
        id: desc
        property var network: ({
            "identifier": "lomiri-indicator-network",
            "busName": "com.lomiri.indicator.network",
            "actionsObjectPath": "/com/lomiri/indicator/network",
            "menuObjectPath": "/com/lomiri/indicator/network/phone",
            "title": i18n.tr("Network")
        })
        property var bluetooth: ({
            "identifier": "ayatana-indicator-bluetooth",
            "busName": "org.ayatana.indicator.bluetooth",
            "actionsObjectPath": "/org/ayatana/indicator/bluetooth",
            "menuObjectPath": "/org/ayatana/indicator/bluetooth/phone",
            "title": i18n.tr("Bluetooth")
        })
        property var sound: ({
            "identifier": "ayatana-indicator-sound",
            "busName": "org.ayatana.indicator.sound",
            "actionsObjectPath": "/org/ayatana/indicator/sound",
            "menuObjectPath": "/org/ayatana/indicator/sound/phone",
            "title": i18n.tr("Sound")
        })
        property var display: ({
            "identifier": "ayatana-indicator-display",
            "busName": "org.ayatana.indicator.display",
            "actionsObjectPath": "/org/ayatana/indicator/display",
            "menuObjectPath": "/org/ayatana/indicator/display/phone",
            "title": i18n.tr("Display")
        })
        property var location: ({
            "identifier": "lomiri-indicator-location",
            "busName": "com.lomiri.indicator.location",
            "actionsObjectPath": "/com/lomiri/indicator/location",
            "menuObjectPath": "/com/lomiri/indicator/location/phone",
            "title": i18n.tr("Location")
        })
    }

    // ----- action groups (same bus objects the indicator pages drive) -----

    QMenuModel.QDBusActionGroup {
        id: networkGroup
        busType: QMenuModel.DBus.SessionBus
        busName: "com.lomiri.indicator.network"
        objectPath: "/com/lomiri/indicator/network"
        property var airplane: action("airplane.enabled")
        property var wifi: action("wifi.enable")
        property var cellular: action("mobiledata.enabled")
        property var cellularLabel: action("modem.1::status-label")
        property var hotspot: action("hotspot.enable")
        Component.onCompleted: start()
    }

    QMenuModel.QDBusActionGroup {
        id: bluetoothGroup
        busType: QMenuModel.DBus.SessionBus
        busName: "org.ayatana.indicator.bluetooth"
        objectPath: "/org/ayatana/indicator/bluetooth"
        property var bt: action("bluetooth-enabled")
        Component.onCompleted: start()
    }

    QMenuModel.QDBusActionGroup {
        id: soundGroup
        busType: QMenuModel.DBus.SessionBus
        busName: "org.ayatana.indicator.sound"
        objectPath: "/org/ayatana/indicator/sound"
        property var silent: action("silent-mode")
        property var volume: action("volume")
        Component.onCompleted: start()
    }

    QMenuModel.QDBusActionGroup {
        id: displayGroup
        busType: QMenuModel.DBus.SessionBus
        busName: "org.ayatana.indicator.display"
        objectPath: "/org/ayatana/indicator/display"
        property var rotationLock: action("rotation-lock")
        Component.onCompleted: start()
    }

    QMenuModel.QDBusActionGroup {
        id: locationGroup
        busType: QMenuModel.DBus.SessionBus
        busName: "com.lomiri.indicator.location"
        objectPath: "/com/lomiri/indicator/location"
        property var locationDetection: action("location-detection-enabled")
        Component.onCompleted: start()
    }

    // Brightness: same action BrightnessControl.qml drives.
    QMenuModel.QDBusActionGroup {
        id: powerGroup
        busType: QMenuModel.DBus.SessionBus
        busName: "org.ayatana.indicator.power"
        objectPath: "/org/ayatana/indicator/power"
        property var brightness: action("brightness")
        Component.onCompleted: start()
    }

    readonly property bool brightnessAvailable: powerGroup.brightness !== null &&
                                                powerGroup.brightness !== undefined &&
                                                powerGroup.brightness.state !== undefined
    readonly property bool volumeAvailable: soundGroup.volume !== null &&
                                            soundGroup.volume !== undefined &&
                                            soundGroup.volume.state !== undefined

    function onOff(state) {
        return state === true ? i18n.tr("On") : i18n.tr("Off");
    }

    // ----- layout -----

    Flickable {
        anchors.fill: parent
        contentHeight: contentColumn.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: contentColumn
            anchors {
                left: parent.left
                right: parent.right
                margins: units.gu(2)
            }
            spacing: units.gu(1.5)

            // ----- header: Controls + device · battery -----
            Item {
                width: parent.width
                height: headerColumn.height

                Column {
                    id: headerColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    spacing: units.gu(0.25)

                    Label {
                        text: i18n.tr("Controls")
                        fontSize: "x-large"
                        font.weight: Font.DemiBold
                        color: theme.palette.normal.backgroundText
                    }

                    Label {
                        // Battery % from BatteryMonitor (shell plugin, upower-backed);
                        // hidden honestly if the level is unavailable.
                        text: BatteryMonitor.chargeLevel > 0
                              ? i18n.tr("Pixel 8 Pro · %1% battery").arg(BatteryMonitor.chargeLevel)
                              : i18n.tr("Pixel 8 Pro")
                        fontSize: "medium"
                        color: theme.palette.normal.backgroundSecondaryText
                    }
                }

                Icon {
                    name: "display-brightness-symbolic"
                    anchors {
                        right: parent.right
                        top: parent.top
                    }
                    width: units.gu(3); height: units.gu(3)
                    color: theme.palette.normal.backgroundSecondaryText
                    visible: false // reserved slot (mockup 06); no action yet
                }
            }

            // ----- tile grid -----
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 4
                columnSpacing: units.gu(1)
                rowSpacing: units.gu(1)

                LandingTile {
                    action: networkGroup.wifi
                    accent: "#5BC9E8"
                    iconName: "wifi-none"
                    iconNameActive: "wifi-full"
                    label: i18n.tr("Wi-Fi")
                    stateText: root.onOff(networkGroup.wifi ? networkGroup.wifi.state : undefined)
                    onPageRequested: root.submenuRequested(desc.network)
                }

                LandingTile {
                    action: bluetoothGroup.bt
                    accent: "#9B8CE8"
                    iconName: "bluetooth-disabled"
                    iconNameActive: "bluetooth-active"
                    label: i18n.tr("Bluetooth")
                    stateText: root.onOff(bluetoothGroup.bt ? bluetoothGroup.bt.state : undefined)
                    onPageRequested: root.submenuRequested(desc.bluetooth)
                }

                LandingTile {
                    action: networkGroup.cellular
                    accent: "#4CAF7D"
                    iconName: "network-cellular-none"
                    iconNameActive: "network-cellular-4g"
                    label: i18n.tr("Mobile")
                    stateText: (networkGroup.cellularLabel &&
                                networkGroup.cellularLabel.state !== undefined &&
                                networkGroup.cellularLabel.state !== "")
                               ? networkGroup.cellularLabel.state
                               : root.onOff(networkGroup.cellular ? networkGroup.cellular.state : undefined)
                    onPageRequested: root.submenuRequested(desc.network)
                }

                LandingTile {
                    action: displayGroup.rotationLock
                    accent: "#F08A4B"
                    iconName: "orientation-lock-disabled"
                    iconNameActive: "orientation-lock"
                    label: i18n.tr("Rotation")
                    stateText: displayGroup.rotationLock && displayGroup.rotationLock.state === true
                               ? i18n.tr("Locked") : i18n.tr("Auto")
                    onPageRequested: root.submenuRequested(desc.display)
                }

                LandingTile {
                    action: soundGroup.silent
                    accent: "#E86A8A"
                    iconName: "audio-volume-high"
                    iconNameActive: "audio-volume-muted"
                    label: i18n.tr("Silent")
                    stateText: root.onOff(soundGroup.silent ? soundGroup.silent.state : undefined)
                    onPageRequested: root.submenuRequested(desc.sound)
                }

                LandingTile {
                    action: locationGroup.locationDetection
                    accent: "#7B9BD4"
                    iconName: "location-disabled"
                    iconNameActive: "location-active"
                    label: i18n.tr("Location")
                    stateText: root.onOff(locationGroup.locationDetection ?
                                          locationGroup.locationDetection.state : undefined)
                    onPageRequested: root.submenuRequested(desc.location)
                }

                LandingTile {
                    action: networkGroup.hotspot
                    accent: "#E8B54B"
                    iconName: "hotspot-disabled"
                    iconNameActive: "hotspot-active"
                    label: i18n.tr("Hotspot")
                    stateText: root.onOff(networkGroup.hotspot ? networkGroup.hotspot.state : undefined)
                    onPageRequested: root.submenuRequested(desc.network)
                }
            }

            // ----- brightness -----
            Column {
                width: parent.width
                spacing: units.gu(0.5)
                visible: root.brightnessAvailable
                height: visible ? implicitHeight : 0

                Label {
                    text: i18n.tr("Brightness")
                    fontSize: "small"
                    color: theme.palette.normal.backgroundSecondaryText
                }

                Slider {
                    id: brightnessSlider
                    width: parent.width
                    minimumValue: 0.01
                    maximumValue: 1.0
                    value: root.brightnessAvailable ? powerGroup.brightness.state : 0.5

                    onValueChanged: {
                        if (pressed && root.brightnessAvailable) {
                            powerGroup.brightness.updateState(value);
                        }
                    }
                    // Dragging rewrites `value` (binding destroyed); restore it
                    // on release so the slider tracks the real backend value.
                    onPressedChanged: {
                        if (!pressed) {
                            value = Qt.binding(function() {
                                return root.brightnessAvailable ? powerGroup.brightness.state : 0.5;
                            });
                        }
                    }
                }
            }

            // ----- volume -----
            Column {
                width: parent.width
                spacing: units.gu(0.5)
                visible: root.volumeAvailable
                height: visible ? implicitHeight : 0

                Label {
                    text: i18n.tr("Volume")
                    fontSize: "small"
                    color: theme.palette.normal.backgroundSecondaryText
                }

                Slider {
                    id: volumeSlider
                    width: parent.width
                    minimumValue: 0.0
                    maximumValue: 1.0
                    value: root.volumeAvailable ? soundGroup.volume.state : 0.0

                    onValueChanged: {
                        if (pressed && root.volumeAvailable) {
                            soundGroup.volume.updateState(value);
                        }
                    }
                    onPressedChanged: {
                        if (!pressed) {
                            value = Qt.binding(function() {
                                return root.volumeAvailable ? soundGroup.volume.state : 0.0;
                            });
                        }
                    }
                }
            }
        }
    }
}
