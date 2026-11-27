/*
 * Ubuntu Plus — Settings hub: More connections (v3, mockup 13 cards)
 *
 * Stacked row-cards with coloured icon chips, subtitles and live status
 * values where a truthful backend exists (Hotspot On/Off via the network
 * indicator action). Pushes the stock plugins' pages — no behavior change.
 *
 * Copyright (C) 2026 Ubuntu Plus (husky port)
 * GPL-3.0 (same terms as the surrounding lomiri-system-settings files)
 */

import QtQuick 2.15
import QMenuModel 1.0
import SystemSettings 1.0
import SystemSettings.ListItems 1.0 as SettingsListItems
import Lomiri.Components 1.3

ItemPage {
    id: root
    objectName: "hubConnectionsPage"

    title: i18n.tr("More connections")
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
            console.warn("hub-connections: plugin unavailable:", name);
        }
    }

    QDBusActionGroup {
        id: networkGroup
        busType: DBus.SessionBus
        busName: "com.lomiri.indicator.network"
        objectPath: "/com/lomiri/indicator/network"
        property var hotspot: action("hotspot.enable")
        Component.onCompleted: start()
    }

    component HubRow: Rectangle {
        id: row
        property string iconSource: ""
        property color chip: "#5BC9E8"
        property string text: ""
        property string subtitle: ""
        property string value: ""
        signal activated()

        width: parent ? parent.width : 0
        height: units.gu(8.5)
        radius: units.gu(1.5)
        color: theme.palette.normal.base

        Rectangle {
            id: chipRect
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
                leftMargin: units.gu(1.5)
            }
            width: units.gu(4.5); height: width
            radius: units.gu(1.2)
            color: chip

            Icon {
                anchors.centerIn: parent
                source: iconSource
                width: units.gu(2.5); height: units.gu(2.5)
                color: "#FFFFFF"
            }
        }

        Column {
            anchors {
                left: chipRect.right
                right: valueLabel.left
                verticalCenter: parent.verticalCenter
                leftMargin: units.gu(1.5)
                rightMargin: units.gu(1)
            }
            spacing: units.gu(0.2)

            Label {
                width: parent.width
                text: row.text
                fontSize: "medium"
                font.weight: Font.DemiBold
                color: theme.palette.normal.backgroundText
                elide: Text.ElideRight
            }
            Label {
                visible: text !== ""
                width: parent.width
                text: row.subtitle
                fontSize: "small"
                color: theme.palette.normal.backgroundSecondaryText
                elide: Text.ElideRight
            }
        }

        Label {
            id: valueLabel
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
                rightMargin: units.gu(1.5)
            }
            visible: text !== ""
            text: row.value
            fontSize: "small"
            color: theme.palette.normal.activity
        }

        MouseArea {
            anchors.fill: parent
            onClicked: row.activated()
        }
    }

    Flickable {
        id: scrollWidget
        anchors.fill: parent
        contentHeight: contentColumn.height + units.gu(2)
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: contentColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: units.gu(1)
            }
            spacing: units.gu(1)

            HubRow {
                iconSource: "image://theme/preferences-network-hotspot-symbolic"
                chip: "#E8B54B"
                text: i18n.tr("Hotspot")
                subtitle: i18n.tr("Share your connection")
                value: (networkGroup.hotspot && networkGroup.hotspot.state !== undefined)
                       ? (networkGroup.hotspot.state === true ? i18n.tr("On") : i18n.tr("Off"))
                       : ""
                onActivated: root.pushPlugin("hotspot")
            }

            HubRow {
                iconSource: "image://theme/network-vpn"
                chip: "#7387E8"
                text: i18n.tr("VPN")
                subtitle: i18n.tr("Tunnels and remote networks")
                onActivated: root.pushPlugin("vpn")
            }

            HubRow {
                iconSource: "image://theme/nfc"
                chip: "#F08A4B"
                text: i18n.tr("NFC")
                subtitle: i18n.tr("Contactless tags and accessories")
                onActivated: root.pushPlugin("nfc")
            }
        }
    }
}
