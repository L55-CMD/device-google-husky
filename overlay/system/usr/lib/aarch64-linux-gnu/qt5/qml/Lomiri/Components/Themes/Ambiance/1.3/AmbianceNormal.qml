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

import QtQuick 2.4
import Lomiri.Components 1.3
import Lomiri.Components.Themes 1.3

PaletteValues {
    background: "#FAF9F7"
    backgroundText: "#2C252B"
    backgroundSecondaryText: LomiriColors.inkstone
    backgroundTertiaryText: "#6E6259"
    base: "#D9D3CC"
    baseText: LomiriColors.inkstone
    foreground: "#F4F1EE"
    foregroundText: "#2C252B"
    raised: "#FFFFFF"
    raisedText: LomiriColors.slate
    raisedSecondaryText: LomiriColors.silk
    overlay: "#FFFFFF"
    overlayText: LomiriColors.inkstone
    overlaySecondaryText: LomiriColors.slate
    field: "#FFFFFF"
    fieldText: "#2C252B"
    focus: "#C7430F"
    focusText: "#FFFFFF"
    selection: Qt.rgba(LomiriColors.orange.r, LomiriColors.orange.g, LomiriColors.orange.b, 0.18)
    selectionText: "#2C252B"
    positive: LomiriColors.green
    positiveText: "#FFFFFF"
    negative: LomiriColors.red
    negativeText: "#FFFFFF"
    activity: LomiriColors.orange
    activityText: "#FFFFFF"
    position: "#00000000"
    positionText: "#C7430F"
}
