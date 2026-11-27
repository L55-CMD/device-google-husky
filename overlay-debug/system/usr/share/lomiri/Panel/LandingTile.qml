/*
 * Ubuntu Plus — Quick Controls tile (Stage 4B, mockup 06 language)
 *
 * Colored state tile: squircle card, function icon + label + state text,
 * status dot top-right. Colored fill when ON, dark neutral when OFF.
 *   tap        -> toggle (activate(<new bool>))
 *   long-press -> open the owning indicator's page (submenu deep link)
 *
 * State honesty (verified on-device 2026-11-26): fill/dot follow
 * action.state only; a rejected activation changes nothing. Tiles hide
 * when the action is unavailable (state undefined / service absent).
 *
 * Copyright (C) 2026 Ubuntu Plus (husky port)
 * GPL-3.0 (same terms as the surrounding Lomiri shell files)
 */

import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: tile

    // The QDBusActionGroup action object (.state, .activate(bool))
    property var action: null
    // Accent colour while ON (mockup 06 per-function palette)
    property color accent: "#5BC9E8"
    // Icon; iconNameActive used while ON (defaults to iconName)
    property string iconName: ""
    property string iconNameActive: iconName
    // Visible label + state text (state text hidden when empty)
    property string label: ""
    property string stateText: ""

    signal pageRequested()

    readonly property bool actionAvailable: action !== null && action !== undefined &&
                                            action.state !== undefined
    readonly property bool actionOn: actionAvailable && action.state === true

    visible: actionAvailable
    width: units.gu(11.5)
    height: units.gu(11.5)
    radius: units.gu(1.5)
    color: actionOn ? accent : "#3A3540"

    Behavior on color { ColorAnimation { duration: LomiriAnimation.FastDuration } }

    // Status dot (top-right): white when ON, dim when OFF
    Rectangle {
        anchors {
            top: parent.top
            right: parent.right
            margins: units.gu(1)
        }
        width: units.gu(1); height: width
        radius: width / 2
        color: tile.actionOn ? "#FFFFFF" : "#6A6472"
    }

    Column {
        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: units.gu(1.2)
        }
        spacing: units.gu(0.3)

        Icon {
            name: tile.actionOn ? tile.iconNameActive : tile.iconName
            width: units.gu(3); height: units.gu(3)
            color: tile.actionOn ? "#FFFFFF" : theme.palette.normal.backgroundText

            Behavior on color { ColorAnimation { duration: LomiriAnimation.FastDuration } }
        }

        Label {
            text: tile.label
            fontSize: "small"
            font.weight: Font.DemiBold
            color: tile.actionOn ? "#FFFFFF" : theme.palette.normal.backgroundText
            elide: Text.ElideRight
        }

        Label {
            visible: text !== ""
            text: tile.stateText
            fontSize: "x-small"
            color: tile.actionOn ? "#E6FFFFFF" : theme.palette.normal.backgroundSecondaryText
            elide: Text.ElideRight
        }
    }

    // Subtle pressed feedback
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "#000000"
        opacity: touch.pressed ? 0.15 : 0.0
        Behavior on opacity { NumberAnimation { duration: LomiriAnimation.SnapDuration } }
    }

    MouseArea {
        id: touch
        anchors.fill: parent
        onClicked: {
            if (tile.actionAvailable) {
                tile.action.activate(!tile.actionOn);
            }
        }
        onPressAndHold: tile.pageRequested()
    }
}
