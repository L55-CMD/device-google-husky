/*
 * Copyright 2016 Canonical Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.15
import Lomiri.Components 1.3

Rectangle {
    id: root
    height: units.gu(4)
    radius: height / 2 // Ubuntu Plus: mockup 07 action pill

    // to be read from outside
    readonly property alias containsMouse: mouseArea.containsMouse

    // to be set from outside
    property bool outline: true
    property alias text: label.text
    property alias iconName: icon.name
    property bool hoverEnabled: false

    signal clicked()

    Label {
        id: label
        fontSize: "medium"
        font.weight: Font.Normal // Ubuntu Plus: pill legibility
        anchors.centerIn: root
        color: theme.name == "Lomiri.Components.Themes.SuruDark" ? "#111"
                                                                 : "white"
        visible: text !== ""
    }

    Icon {
        id: icon
        height: root.height * 2 / 3
        width: height
        anchors.centerIn: root
        color: "white"
        visible: !label.visible
    }

    MouseArea {
        id: mouseArea
        anchors.fill: root
        hoverEnabled: root.hoverEnabled
        onClicked: {
            Haptics.play();
            root.clicked();
        }
    }

    transformOrigin: Item.Top
    scale: mouseArea.pressed ? 0.98 : 1.0
    Behavior on scale {
        ScaleAnimator {
            duration: LomiriAnimation.SnapDuration
            easing.type: Easing.Linear
        }
    }
}
