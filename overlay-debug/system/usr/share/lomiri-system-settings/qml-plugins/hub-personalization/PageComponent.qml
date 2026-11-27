/*
 * Ubuntu Plus — Settings hub: Personalization (v2 cards)
 *
 * Submenu page grouping the stock Background & Appearance /
 * Desktop & Launcher / Gestures panels.
 * Pushes the stock plugins' own page components — no behavior change.
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
            console.warn("hub-personalization: plugin unavailable:", name);
        }
    }

    Flickable {
        id: scrollWidget
        anchors.fill: parent
        contentHeight: contentItem.childrenRect.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

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
                    objectName: "hubBackground"
                    text: i18n.tr("Background & Appearance")
                    iconSource: "image://theme/preferences-desktop-wallpaper-symbolic"
                    onClicked: root.pushPlugin("background")
                }

                SettingsListItems.IconProgression {
                    objectName: "hubLauncher"
                    text: i18n.tr("Desktop & Launcher")
                    iconSource: "image://theme/preferences-desktop-launcher-symbolic"
                    onClicked: root.pushPlugin("launcher")
                }

                SettingsListItems.IconProgression {
                    objectName: "hubGestures"
                    text: i18n.tr("Gestures")
                    iconSource: "image://theme/gestures"
                    showDivider: false
                    onClicked: root.pushPlugin("gestures")
                }
            }
        }
    }
}
