/*
 * Ubuntu Plus — Settings hub: System & updates (v2 cards)
 *
 * Submenu page grouping the stock Updates / Phone / USB / Libertine /
 * Reset panels. Pushes the stock plugins' own page components —
 * no behavior change.
 *
 * Copyright (C) 2026 Ubuntu Plus (husky port)
 * GPL-3.0 (same terms as the surrounding lomiri-system-settings files)
 */

import QtQuick 2.12
import SystemSettings 1.0
import SystemSettings.ListItems 1.0 as SettingsListItems
import Lomiri.Components 1.3

ItemPage {
    id: root
    objectName: "hubSystemPage"

    title: i18n.tr("System & updates")
    flickable: scrollWidget

    function pushPlugin(name, opts) {
        var p = pluginManager.getByName(name);
        if (p && p.pageComponent) {
            var props = { plugin: p, pluginManager: pluginManager };
            if (opts) {
                for (var k in opts) props[k] = opts[k];
            }
            pageStack.addPageToNextColumn(root, p.pageComponent, props);
        } else {
            console.warn("hub-system: plugin unavailable:", name);
        }
    }

    Flickable {
        id: scrollWidget
        anchors.fill: parent
        contentHeight: contentItem.childrenRect.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: units.gu(1)

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: units.gu(1)
                anchors.rightMargin: units.gu(1)
                anchors.topMargin: units.gu(1)
                height: card.implicitHeight
                radius: units.gu(1.5)
                color: theme.palette.normal.base
                clip: true

                Column {
                    id: card
                    width: parent.width

                    SettingsListItems.IconProgression {
                        objectName: "hubUpdates"
                        text: i18n.tr("Updates")
                        iconSource: "image://theme/preferences-system-updates-symbolic"
                        onClicked: root.pushPlugin("system-update")
                    }

                    SettingsListItems.IconProgression {
                        objectName: "hubPhone"
                        text: i18n.tr("Phone")
                        iconSource: "image://theme/preferences-system-phone-symbolic"
                        onClicked: root.pushPlugin("phone")
                    }

                    SettingsListItems.IconProgression {
                        objectName: "hubUsb"
                        text: i18n.tr("USB")
                        iconSource: "image://theme/stock_usb"
                        onClicked: root.pushPlugin("usb")
                    }

                    SettingsListItems.IconProgression {
                        objectName: "hubLibertine"
                        text: i18n.tr("Libertine")
                        iconSource: "file:///usr/share/lomiri-system-settings/icons/libertine-plugin.svg"
                        showDivider: false
                        onClicked: root.pushPlugin("libertine")
                    }
                }
            }

            SettingsItemTitle {
                text: i18n.tr("Danger zone")
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: units.gu(1)
                anchors.rightMargin: units.gu(1)
                height: dangerCard.implicitHeight
                radius: units.gu(1.5)
                color: theme.palette.normal.base
                clip: true

                Column {
                    id: dangerCard
                    width: parent.width

                    SettingsListItems.IconProgression {
                        objectName: "hubReset"
                        text: i18n.tr("Reset")
                        iconSource: "image://theme/reset"
                        showDivider: false
                        onClicked: root.pushPlugin("reset")
                    }
                }
            }
        }
    }
}
