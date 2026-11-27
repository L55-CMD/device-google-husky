/*
 * Ubuntu Plus — Settings hub (v3, mockup 13 cards)
 *
 * Stacked row-cards with coloured icon chips and subtitles.
 * Pushes the stock plugins' pages — no behavior change.
 *
 * Copyright (C) 2026 Ubuntu Plus (husky port)
 * GPL-3.0 (same terms as the surrounding lomiri-system-settings files)
 */

import QtQuick 2.15
import SystemSettings 1.0
import SystemSettings.ListItems 1.0 as SettingsListItems
import Lomiri.Components 1.3

ItemPage {
    id: root
    objectName: "hubPersonalizationPage"

    title: i18n.tr("Personalization")
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
            console.warn("hubPersonalizationPage: plugin unavailable:", name);
        }
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
                iconSource: "image://theme/preferences-desktop-wallpaper-symbolic"
                chip: "#E85D3A"
                text: i18n.tr("Background & Appearance")
                subtitle: i18n.tr("Wallpaper and theme")
                onActivated: root.pushPlugin("background")
            }

            HubRow {
                iconSource: "image://theme/preferences-desktop-launcher-symbolic"
                chip: "#9B8CE8"
                text: i18n.tr("Desktop & Launcher")
                subtitle: i18n.tr("Launcher behaviour and layout")
                onActivated: root.pushPlugin("launcher")
            }

            HubRow {
                iconSource: "image://theme/gestures"
                chip: "#5BC9E8"
                text: i18n.tr("Gestures")
                subtitle: i18n.tr("Edge and touch gestures")
                onActivated: root.pushPlugin("gestures")
            }
        }
    }
}
