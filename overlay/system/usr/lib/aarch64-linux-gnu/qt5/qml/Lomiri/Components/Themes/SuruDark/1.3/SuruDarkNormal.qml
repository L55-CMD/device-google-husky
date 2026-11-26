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
    background: "#0D0B0C"
    backgroundText: "#F4F1EE"
    backgroundSecondaryText: "#CFC8C2"
    backgroundTertiaryText: "#A89B92"
    base: "#7E737A"
    baseText: "#F4F1EE"
    foreground: "#1F1C1D"
    foregroundText: "#F4F1EE"
    raised: "#FFFFFF"
    raisedText: LomiriColors.slate
    raisedSecondaryText: LomiriColors.silk
    overlay: "#1F1C1D"
    overlayText: "#F4F1EE"
    overlaySecondaryText: "#CFC8C2"
    field: "#080707"
    fieldText: "#F4F1EE"
    focus: LomiriColors.orange
    focusText: "#000000"
    selection: Qt.rgba(LomiriColors.orange.r, LomiriColors.orange.g, LomiriColors.orange.b, 0.4)
    selectionText: "#F4F1EE"
    positive: LomiriColors.lightGreen
    positiveText: "#000000"
    negative: LomiriColors.lightRed
    negativeText: "#000000"
    activity: LomiriColors.orange
    activityText: "#000000"
    position: "#00000000"
    positionText: "#F4743B"
}
