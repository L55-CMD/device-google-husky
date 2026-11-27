/*
 * This file is part of system-settings
 *
 * Copyright (C) 2013-2016 Canonical Ltd.
 * Copyright (C) 2020 UBports Foundation
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.12
import QtSystemInfo 5.0
import SystemSettings 1.0
import SystemSettings.ListItems 1.0 as SettingsListItems
import Lomiri.Components 1.3
import Lomiri.SystemSettings.StorageAbout 1.0
import Lomiri.SystemSettings.Bluetooth 1.0
import Lomiri.SystemSettings.Usb 1.0
import QOfono 0.2

ItemPage {
    id: root
    objectName: "aboutPage"
    title: i18n.tr("System information")
    flickable: scrollWidget
    property var modemsSorted: []
    property var showImei: false

    LomiriStorageAboutPanel {
        id: backendInfos
    }

    LomiriBluetoothPanel {
        id: bluetooth
    }

    DeviceInfo {
        id: deviceInfos
    }

    OfonoManager {
        id: manager
        onModemsChanged: root.modemsSorted = modems.slice(0).sort()
    }

    NetworkInfo {
        id: wlinfo
    }

    Flickable {
        id: scrollWidget
        anchors.fill: parent
        contentHeight: contentItem.childrenRect.height
        boundsBehavior: (contentHeight > root.height) ? Flickable.DragAndOvershootBounds : Flickable.StopAtBounds
        /* Set the direction to workaround https://bugreports.qt-project.org/browse/QTBUG-31905
           otherwise the UI might end up in a situation where scrolling doesn't work */
        flickableDirection: Flickable.VerticalFlick

        Column {
            anchors.left: parent.left
            anchors.right: parent.right

            Column {
                anchors.left: parent.left
                anchors.right: parent.right

                spacing: units.gu(2)
                padding: units.gu(2)

                Image {
                    id: distroLogo
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    height: units.gu(5)
                    source: {
                        let forDarkMode = ColorUtils.luminance(
                                theme.palette.normal.background
                            ) <= 0.85;
                        return backendInfos.getDistroLogoUri(forDarkMode);
                    }
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                }
                Label {
                    id: distroLogoFallbackText
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: backendInfos.getDistroLogoFallbackText()
                    fontSize: "x-large"
                    visible: !distroLogo.visible
                }
                Label {
                    id: deviceLabel
                    objectName: "deviceLabel"
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: SystemInfo.prettyName
                }
            }

            SettingsListItems.SingleValue {
                id: serialItem
                objectName: "serialItem"
                text: i18n.tr("Serial")
                value: backendInfos.serialNumber
                visible: backendInfos.serialNumber
            }

            SettingsListItems.SingleValue {
                objectName: "imeiItem"
                text: "IMEI"
                value: i18n.tr("Press to show")
                visible: !showImei
                onClicked: showImei = true
            }
            SettingsListItems.SingleValue {
                objectName: "imeiItem"
                property string imeiNumber
                imeiNumber: deviceInfos.imei(0)
                text: "IMEI"
                value: modemsSorted.length ? (imeiNumber || i18n.tr("None")) :
                    i18n.tr("None")
                visible: modemsSorted.length == 1 && showImei
            }

            SettingsListItems.Standard {
                text: "IMEI"
                objectName: "imeiItems"
                layout.subtitle.text: {
                    var imeis = [];
                    modemsSorted.forEach(function (path, i) {
                        var imei = deviceInfos.imei(i);
                        imei ? imeis.push(imei) : imeis.push(i18n.tr("None"));
                    });
                    return imeis.join(", ");
                }
                visible: modemsSorted.length > 1 && showImei
            }

            SettingsListItems.SingleValue {
                property string address: wlinfo.macAddress(NetworkInfo.WlanMode, 0)
                text: i18n.tr("Wi-Fi address")
                value: address ? address.toUpperCase() : ""
                visible: address
                showDivider: bthwaddr.visible
            }

            SettingsListItems.SingleValue {
                id: bthwaddr
                text: i18n.tr("Bluetooth address")
                value: bluetooth.adapterAddress
                visible: bluetooth.adapterAddress
                showDivider: false
            }

            SettingsListItems.Divider {}

            SettingsListItems.SingleValueProgression {
                id: storageItem
                objectName: "storageItem"
                text: i18n.tr("Storage")
                /* TRANSLATORS: that's the free disk space, indicated in the most appropriate storage unit */
                value: i18n.tr("%1 free").arg(Utilities.formatSize(backendInfos.getFreeSpace("/home")))
                onClicked: pageStack.addPageToNextColumn(root, Qt.resolvedUrl("Storage.qml"))
            }

            SettingsItemTitle {
                id: softwareItem
                objectName: "softwareItem"
                text: i18n.tr("Software:")
            }

            SettingsListItems.SingleValueProgression {
                visible: softwareItem.visible
                property string versionIdentifier: {
                    var num = SystemImage.currentBuildNumber;
                    var ota = SystemImage.versionTag;
                    num = num ? "r%1".arg(num.toString()) : "";
                    return ota ? ota : num;
                }
                objectName: "osItem"
                text: i18n.tr("OS")
                value: "Ubuntu Touch %1%2"
                    .arg(deviceInfos.version(DeviceInfo.Os))
                    .arg(versionIdentifier ? " (%1)".arg(versionIdentifier) : "")
                onClicked: pageStack.addPageToNextColumn(root, Qt.resolvedUrl("Version.qml"), {
                    version: versionIdentifier
                })
            }

            SettingsListItems.SingleValue {
                objectName: "lastUpdatedItem"
                visible: softwareItem.visible
                text: i18n.tr("Last updated")
                value: SystemImage.lastUpdateDate && !isNaN(SystemImage.lastUpdateDate) ?
                    Qt.formatDate(SystemImage.lastUpdateDate) : i18n.tr("Never")
            }
            SettingsListItems.SingleValue {
                objectName: "kernelInfoItem"
                visible: value !== ""
                text: i18n.tr("Kernel")
                value: backendInfos.kernelVersion ? backendInfos.kernelVersion : ""
            }

            SettingsListItems.SingleValue {
                objectName: "buildInfoItem"
                visible: value !== ""
                text: i18n.tr("Build")
                value: backendInfos.deviceBuildDisplayID ? backendInfos.deviceBuildDisplayID : ""
            }

            SettingsListItems.SingleControl {
                visible: softwareItem.visible

                Button {
                    objectName: "updateButton"
                    text: i18n.tr("Check for updates")
                    width: parent.width - units.gu(4)
                    onClicked: {
                        var upPlugin = pluginManager.getByName("system-update")
                        if (upPlugin) {
                            var updatePage = upPlugin.pageComponent
                            var updatePageIncubator;
                            if (updatePage) {
                                updatePageIncubator = pageStack.addPageToNextColumn(root, updatePage, {
                                    plugin: upPlugin, pluginManager: pluginManager
                                });
                                if (updatePageIncubator && updatePageIncubator.status == Component.Loading) {
                                    updatePageIncubator.onStatusChanged = function(status) {
                                        if (status == Component.Ready) {
                                            updatePageIncubator.object.check(true);
                                        }
                                    }
                                }
                            } else {
                                console.warn("Failed to get system-update pageComponent")
                            }
                        } else {
                            console.warn("Failed to get system-update plugin instance")
                        }
                    }
                }
                showDivider: false
            }

            SettingsItemTitle {
                objectName: "legalItem"
                text: i18n.tr("Legal:")
            }

            SettingsListItems.StandardProgression {
                objectName: "licenseItem"
                text: i18n.tr("Software licenses")
                onClicked: pageStack.addPageToNextColumn(root, Qt.resolvedUrl("Software.qml"))
            }

            SettingsListItems.StandardProgression {
                property var regulatoryInfo:
                    pluginManager.getByName("regulatory-information")
                text: i18n.tr("Regulatory info")
                visible: regulatoryInfo
                onClicked: pageStack.addPageToNextColumn(root, regulatoryInfo.pageComponent)
            }

            SettingsListItems.SingleValueProgression {
                objectName: "devmodeItem"
                text: i18n.tr("Developer mode")
                visible: !isSnap && UsbConfig.developerModeCapable || showAllUI
                onClicked: pageStack.addPageToNextColumn(root, Qt.resolvedUrl("DevMode.qml"))
            }
        }
    }
}
