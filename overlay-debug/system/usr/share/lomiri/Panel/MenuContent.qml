/*
 * Copyright (C) 2013-2014 Canonical Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.1
import Lomiri.Components 1.3
import Lomiri.Indicators 0.1 as Indicators
import Utils 0.1
import "../Components"
import "Indicators"

Item {
    id: content

    property QtObject model: null
    property int currentMenuIndex: -1
    property Component pageDelegate

    // Ubuntu Plus Stage 4B (v4 rework): when a landing page is installed
    // the old per-indicator pager is REPLACED by:
    //   page 0: landing page (tiles + brightness)
    //   page 1: calendar (datetime indicator page)
    // Indicator pages themselves are reachable only as an overlay submenu
    // (tile long-press). No model/index mapping to the indicators model.
    property Component landingDelegate: null
    // Opaque background for the submenu overlay (set by PanelMenu).
    property color backgroundColor: "#0D0B0C"

    // Emitted when the user swipes the landing pager (-1 = landing page).
    signal pageSwiped(int index)

    width: units.gu(40)
    height: units.gu(42)

    readonly property bool landingMode: landingDelegate !== null

    onCurrentMenuIndexChanged: {
        if (content.landingMode) {
            return; // bar index has no meaning in landing mode
        }
        listViewContent.currentIndex = currentMenuIndex;
    }

    // Ubuntu Plus Stage 4B: scroll to the landing page (panel open).
    function showLanding() {
        if (content.landingMode) {
            submenuOverlay.active = false;
            listViewContent.positionViewAtBeginning();
        }
    }

    // Ubuntu Plus Stage 4B: open an indicator page as an overlay submenu.
    // descriptor: {identifier, busName, actionsObjectPath, menuObjectPath, title}
    function openSubmenu(descriptor) {
        submenuOverlay.descriptor = descriptor;
        submenuOverlay.active = true;
    }

    // ------------------------------------------------------------------
    // Landing-mode pager model: fixed two pages.
    ListModel {
        id: landingPagerModel
        ListElement { landingPage: true }
        ListElement { landingPage: false }
    }

    Component {
        id: landingPagerDelegate
        Loader {
            width: ListView.view.width
            height: ListView.view.height
            sourceComponent: model.landingPage ? content.landingDelegate : calendarPage

            onLoaded: {
                if (item && item.hasOwnProperty("submenuRequested")) {
                    item.submenuRequested.connect(function(descriptor) {
                        content.openSubmenu(descriptor);
                    });
                }
            }
        }
    }

    // Page 1: calendar (datetime indicator page, stock components).
    Component {
        id: calendarPage
        PanelMenuPage {
            submenuIndex: 0

            menuModel: calendarIndicator.menuModel

            factory: IndicatorMenuItemFactory {
                indicator: "ayatana-indicator-datetime"
                rootModel: calendarIndicator.menuModel
            }

            IndicatorDelegate {
                id: calendarIndicator
                identifier: "ayatana-indicator-datetime"
                busName: "org.ayatana.indicator.datetime"
                actionsObjectPath: "/org/ayatana/indicator/datetime"
                menuObjectPath: "/org/ayatana/indicator/datetime/phone"
            }
        }
    }

    // Overlay: one indicator page on demand (tile long-press), with a
    // back affordance. Covers the pager; landing state is preserved.
    Loader {
        id: submenuOverlay
        property var descriptor: null

        anchors.fill: parent
        active: false
        visible: active
        z: 10
        asynchronous: true
        sourceComponent: submenuPageComponent
    }

    Component {
        id: submenuPageComponent
        Item {
            Rectangle {
                anchors.fill: parent
                color: content.backgroundColor
            }

            Row {
                id: submenuBackRow
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: units.gu(1)
                }
                height: units.gu(5)
                spacing: units.gu(1)

                Icon {
                    name: "back"
                    width: units.gu(2.5)
                    height: units.gu(2.5)
                    anchors.verticalCenter: parent.verticalCenter
                    color: theme.palette.normal.backgroundText
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: submenuOverlay.descriptor ? submenuOverlay.descriptor.title : ""
                    fontSize: "medium"
                    color: theme.palette.normal.backgroundText
                }
            }

            MouseArea {
                anchors.fill: submenuBackRow
                onClicked: submenuOverlay.active = false
            }

            PanelMenuPage {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: submenuBackRow.bottom
                    bottom: parent.bottom
                }

                submenuIndex: 0

                menuModel: submenuIndicator.menuModel

                factory: IndicatorMenuItemFactory {
                    indicator: submenuOverlay.descriptor ? submenuOverlay.descriptor.identifier : ""
                    rootModel: submenuIndicator.menuModel
                }

                IndicatorDelegate {
                    id: submenuIndicator
                    identifier: submenuOverlay.descriptor ? submenuOverlay.descriptor.identifier : ""
                    busName: submenuOverlay.descriptor ? submenuOverlay.descriptor.busName : ""
                    actionsObjectPath: submenuOverlay.descriptor ? submenuOverlay.descriptor.actionsObjectPath : ""
                    menuObjectPath: submenuOverlay.descriptor ? submenuOverlay.descriptor.menuObjectPath : ""
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Stock per-indicator page delegate (used when no landing page).
    Component {
        id: indicatorPagerDelegate
        Loader {
            id: loader

            width: ListView.view.width
            height: ListView.view.height
            asynchronous: true
            visible: ListView.isCurrentItem

            property var modelData: model
            property var modelIndex: index

            sourceComponent: content.pageDelegate

            onVisibleChanged: {
                // Reset the indicator states
                if (!visible && status == Loader.Ready) {
                    item.reset();
                }
            }
        }
    }

    ListView {
        id: listViewContent
        objectName: "indicatorsContentListView"
        anchors.fill: parent
        model: content.landingMode ? landingPagerModel : content.model
        delegate: content.landingMode ? landingPagerDelegate : indicatorPagerDelegate

        highlightFollowsCurrentItem: false
        // Ubuntu Plus Stage 4B: content is a horizontal pager (landing <->
        // calendar) in landing mode only; stock behavior otherwise.
        interactive: content.landingMode
        snapMode: ListView.SnapToItem
        orientation: ListView.Horizontal
        // Load all the indicator menus (a big number)
        cacheBuffer: 1073741823

        // for additions/removals.
        onCountChanged: {
            if (!content.landingMode) {
                listViewContent.currentIndex = content.currentMenuIndex;
            }
        }

        onCurrentIndexChanged: {
            if (content.landingMode) {
                return;
            }
            // Do not fight the user's own flicking; bar-driven changes
            // (not moving) still reposition as before.
            if (!moving) {
                positionViewAtIndex(currentIndex, ListView.Beginning);
            }
        }

        // Ubuntu Plus Stage 4B: after a user swipe, tell the owner which
        // page landed (-1 = landing page) so the bar can clear selection.
        onMovementEnded: {
            if (!content.landingMode) {
                return;
            }
            if (contentX <= (originX + width / 2)) {
                content.pageSwiped(-1);
            } else {
                content.pageSwiped(0);
            }
        }
    }
}
