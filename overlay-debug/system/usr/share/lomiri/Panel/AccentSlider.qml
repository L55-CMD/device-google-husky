/*
 * Ubuntu Plus — accent slider (Stage 4B polish, mockup 06)
 *
 * Minimal slider with a per-instance accent colour (the stock Slider's
 * colours come from the theme style and cannot be overridden per use).
 * State-honest: displays `value` (bind it to the backend action state);
 * while dragged it shows the drag position and emits moved() — the owner
 * writes to the backend; on release the display returns to the bound
 * backend value (a rejected write visibly snaps back).
 *
 * Copyright (C) 2026 Ubuntu Plus (husky port)
 * GPL-3.0 (same terms as the surrounding Lomiri shell files)
 */

import QtQuick 2.15
import Lomiri.Components 1.3

Item {
    id: slider

    property real minimumValue: 0.0
    property real maximumValue: 1.0
    property real value: 0.0
    property color accent: "#E8B54B"

    signal moved(real newValue)

    readonly property real _span: Math.max(0.0001, maximumValue - minimumValue)
    readonly property real _frac: Math.max(0.0, Math.min(1.0,
        ((touch.pressed ? _dragValue : value) - minimumValue) / _span))
    property real _dragValue: 0.0

    height: units.gu(4)

    function _valueAt(x) {
        var f = Math.max(0.0, Math.min(1.0, x / width));
        return minimumValue + f * _span;
    }

    // track
    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: units.gu(0.6)
        radius: height / 2
        color: theme.palette.normal.base

        Rectangle {
            width: parent.width * slider._frac
            height: parent.height
            radius: parent.radius
            color: slider.accent
        }
    }

    // knob
    Rectangle {
        width: units.gu(2.2)
        height: width
        radius: width / 2
        color: "#FFFFFF"
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(slider.width - width,
                                slider.width * slider._frac - width / 2))
    }

    MouseArea {
        id: touch
        anchors.fill: parent
        onPressed: {
            slider._dragValue = slider._valueAt(mouse.x);
            slider.moved(slider._dragValue);
        }
        onPositionChanged: {
            if (pressed) {
                slider._dragValue = slider._valueAt(mouse.x);
                slider.moved(slider._dragValue);
            }
        }
    }
}
