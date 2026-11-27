/*
 * Copyright 2013-2016 Canonical Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.12
import SystemSettings 1.0
import SystemSettings.ListItems 1.0 as SettingsListItems
import Lomiri.Components 1.3
import Lomiri.Components.Popups 1.3
import Lomiri.SystemSettings.Wifi 1.0
import QMenuModel 1.0

ItemPage {
    id: wifibase
    objectName: "wifiPage"
    title: i18n.tr("Wi-Fi")
    flickable: pageFlickable

    property bool wifiEnabled: actionGroup.actionObject.valid ?
                               actionGroup.actionObject.state : false

    AyatanaMenuModel {
        id: menuModel
        busName: "com.lomiri.indicator.network"
        actions: { "indicator": "/com/lomiri/indicator/network" }
        menuObjectPath: "/com/lomiri/indicator/network/phone_wifi_settings"
        Component.onCompleted: {
            menuStack.head = menuModel;
        }
    }
    UnityMenuModelStack {
        id: menuStack
    }
    MenuItemFactory {
        id: menuFactory
        model: mainMenu.model
    }

    QDBusActionGroup {
        id: actionGroup
        busType: 1
        busName: "com.lomiri.indicator.network"
        objectPath: "/com/lomiri/indicator/network"
        property variant actionObject: action("wifi.enable")
        Component.onCompleted: {
            start()
        }
    }

    Flickable {
        id: pageFlickable
        anchors.fill: parent
        contentWidth: parent.width
        contentHeight: contentItem.childrenRect.height

        Column {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }

            // Ubuntu Plus: mockup 13 hero status card (display-only; the
            // functional switch stays in the list below — no duplicate control)
            Rectangle {
                objectName: "wifiHeroCard"
                width: parent.width - units.gu(2)
                anchors.horizontalCenter: parent.horizontalCenter
                height: units.gu(9)
                radius: units.gu(1.5)
                color: theme.palette.normal.base

                Rectangle {
                    id: heroChip
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: units.gu(1.5)
                    }
                    width: units.gu(5.5); height: width
                    radius: units.gu(1.5)
                    color: wifibase.wifiEnabled ? "#5BC9E8" : "#3A3540"

                    Behavior on color { ColorAnimation { duration: 200 } }

                    Icon {
                        anchors.centerIn: parent
                        name: wifibase.wifiEnabled ? "wifi-full" : "wifi-none"
                        width: units.gu(3); height: units.gu(3)
                        color: "#FFFFFF"
                    }
                }

                Column {
                    anchors {
                        left: heroChip.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: units.gu(1.5)
                    }
                    spacing: units.gu(0.2)

                    Label {
                        text: wifibase.wifiEnabled ? i18n.tr("Wi-Fi on") : i18n.tr("Wi-Fi off")
                        fontSize: "large"
                        font.weight: Font.DemiBold
                        color: wifibase.wifiEnabled ? "#4CAF7D"
                                                    : theme.palette.normal.backgroundSecondaryText
                    }

                    Label {
                        text: i18n.tr("Wireless network")
                        fontSize: "small"
                        color: theme.palette.normal.backgroundSecondaryText
                    }
                }
            }

            Repeater {
                id: mainMenu
                model: menuStack.tail ? menuStack.tail : null
                delegate: Item {
                    id: menuDelegate
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    height: loader.height

                    Loader {
                        id: loader
                        asynchronous: true

                        property int modelIndex: index

                        anchors {
                            left: parent.left
                            right: parent.right
                        }

                        sourceComponent: menuFactory.load(model)

                        onLoaded: {
                            if (model.type === "org.ayatana.indicator.root") {
                                menuStack.push(mainMenu.model.submenu(index));
                            }

                            if (item.hasOwnProperty("menuActivated")) {
                                item.menuActivated = Qt.binding(function() {
                                    return ListView.isCurrentItem;
                                });
                                item.selectMenu.connect(function() {
                                    ListView.view.currentIndex = index;
                                });
                                item.deselectMenu.connect(function() {
                                    ListView.view.currentIndex = -1;
                                });
                            }

                            if (item.hasOwnProperty("menu")) {
                                item.menu = Qt.binding(function() { return model; });
                            }
                            if (item.hasOwnProperty("menuIndex")) {
                                item.menuIndex = Qt.binding(function() { return modelIndex; });
                            }
                        }
                    }
                }
            }

            SettingsListItems.Standard {
                objectName: "connectToHiddenNetwork"
                text: i18n.tr("Connect to hidden network…")
                visible : wifibase.wifiEnabled
                onClicked: {
                    otherNetworLoader.source = "OtherNetwork.qml";
                    PopupUtils.open(otherNetworLoader.item);
                }
            }

            SettingsListItems.StandardProgression {
                objectName: "previousNetwork"
                text: i18n.tr("Previous networks")
                onClicked: pageStack.addPageToNextColumn(wifibase,
                    Qt.resolvedUrl("PreviousNetworks.qml"))
            }

            Loader {
                id: otherNetworLoader
                asynchronous: false
            }
        }

        // Only allow flicking if the content doesn't fit on the page
        boundsBehavior: (contentHeight > wifibase.height) ?
                            Flickable.DragAndOvershootBounds :
                            Flickable.StopAtBounds
    }

    Connections {
        target: wifibase

        function invokeWiFiConfigurationDialog () {
            if (wifiEnabled && pluginOptions && pluginOptions['ssid']) {
                otherNetworLoader.source = "OtherNetwork.qml";
                PopupUtils.open(otherNetworLoader.item, wifibase, {
                    'ssid': pluginOptions['ssid'],
                    'bssid': pluginOptions['bssid'],
                    'pass': pluginOptions['password'],
                    'securityType': pluginOptions['securityType']
                });
            }
        }

        function onWifiEnabledChanged() { invokeWiFiConfigurationDialog() }
        function onPluginOptionsChanged() { invokeWiFiConfigurationDialog() }
    }
}
