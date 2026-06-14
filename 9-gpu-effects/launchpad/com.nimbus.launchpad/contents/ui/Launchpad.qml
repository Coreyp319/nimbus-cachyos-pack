/*
 * Launchpad.qml — the full-screen content + the Big Sur blur-and-zoom motion.
 *
 * Layout: a centred search field, a category sidebar (kickerdash-style: "All
 * Applications" + the app categories), and the app grid for the selected
 * category. Typing searches across everything (KRunner) and hides the sidebar.
 * The KWin blur-behind the DashboardWindow frosts the desktop; we paint an
 * animated dark scrim on top.
 *
 * Motion: intro — scrim fades in, the content zooms 0.92 → 1.0 + fades, a GPU
 * MultiEffect blur rolls off as it lands (OutCubic). Outro — the reverse at 0.7×
 * (InCubic), then a ScriptAction calls back so main.qml unmaps the window only
 * after the animation is seen. DashboardWindow itself only maps/unmaps.
 */
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Item {
    id: launchpad
    // width/height set by main.qml (to the DashboardWindow size).

    // models from main.qml. rootModel row 0 = "All Applications", rows 1.. = the
    // categories; each category's apps are rootModel.modelForRow(thatRow).
    property var rootModel
    property var runnerModel

    // config — bound from main.qml (reparented out of the applet, so no plasmoid.*)
    property int  cfgColumns:  7
    property int  cfgIconSize: 64
    property bool cfgLabels:   true
    property int  cfgDuration: 300
    property real cfgDim:      0.45
    property bool cfgBlur:     true

    readonly property bool animate: Kirigami.Units.longDuration > 1
    readonly property int  introMs: animate ? cfgDuration : 1
    readonly property int  outroMs: animate ? Math.round(cfgDuration * 0.7) : 1

    // The pack threads ONE accent (focus rings, scrollbar grab, reactive glow) —
    // reuse it for selection here too (design-ux.md §5), not a new hue.
    readonly property color accentColor: Kirigami.Theme.highlightColor

    signal launched()
    signal closeRequested()

    property alias searchField: searchField
    readonly property bool searching: searchField.text.length > 0

    // which sidebar row is selected (0 = All Applications)
    property int selectedCategory: 0

    // KRunner results when searching; otherwise the selected category's apps.
    readonly property var searchResults: (runnerModel && runnerModel.count > 0)
                                         ? runnerModel.modelForRow(0) : null
    readonly property var gridModel: searching ? searchResults
        : (rootModel && rootModel.count > selectedCategory
           ? rootModel.modelForRow(selectedCategory) : null)

    // ---- grid cell geometry (capped so cells don't stretch on ultrawide) ----
    readonly property int columns: Math.max(1, cfgColumns)
    readonly property int maxCellW: cfgIconSize + Kirigami.Units.gridUnit * 6
    readonly property int sidebarW: Kirigami.Units.gridUnit * 13
    readonly property int gridW: cellW * columns
    readonly property int cellW: Math.max(cfgIconSize + Kirigami.Units.gridUnit * 2, maxCellW)
    readonly property int cellH: cfgIconSize + (cfgLabels ? Kirigami.Units.gridUnit * 3
                                                          : Kirigami.Units.gridUnit * 1.5)

    // ---- open/close state machine -----------------------------------------
    property bool shown: false
    property real fxBlur: 0.0
    property var _onClosed: null

    function open() {
        searchField.text = ""
        selectedCategory = 0   // "All Applications"
        appGrid.currentIndex = 0
        shown = true
        searchField.forceActiveFocus()
    }
    function close(done) { _onClosed = done || null; shown = false }
    function resetClosed() { shown = false }
    function handleEscape() { if (searching) searchField.text = ""; else closeRequested() }
    function _fireClosed() { if (_onClosed) { var cb = _onClosed; _onClosed = null; cb() } }

    function activateIndex(i) {
        var m = gridModel
        if (m && i >= 0 && i < m.count) { m.trigger(i, "", null); launched() }
    }

    // ---- backdrop scrim ---------------------------------------------------
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: "black"
        opacity: 0
        TapHandler { onTapped: launchpad.closeRequested() }
    }

    // ---- everything that zooms -------------------------------------------
    Item {
        id: stage
        anchors.fill: parent
        opacity: 0
        scale: 0.92
        transformOrigin: Item.Center

        layer.enabled: launchpad.cfgBlur && launchpad.fxBlur > 0.001
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 40
            blur: launchpad.fxBlur
        }

        // search box — top centre
        PC3.TextField {
            id: searchField
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Kirigami.Units.gridUnit * 3
            width: Kirigami.Units.gridUnit * 24
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 3
            placeholderText: i18n("Search")
            onTextChanged: {
                if (launchpad.runnerModel) launchpad.runnerModel.query = text
                appGrid.currentIndex = 0
            }
            Keys.onReturnPressed: launchpad.activateIndex(appGrid.currentIndex)
            Keys.onEnterPressed: launchpad.activateIndex(appGrid.currentIndex)
            Keys.onDownPressed: appGrid.moveCurrentIndexDown()
            Keys.onUpPressed: appGrid.moveCurrentIndexUp()
        }

        // category sidebar + app grid, centred as a block
        RowLayout {
            id: body
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: searchField.bottom
            anchors.topMargin: Kirigami.Units.gridUnit * 2
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Kirigami.Units.gridUnit * 3
            width: (launchpad.searching ? 0 : launchpad.sidebarW + spacing) + launchpad.gridW
            spacing: Kirigami.Units.gridUnit * 2

            // category sidebar (hidden while searching)
            ListView {
                id: sidebar
                visible: !launchpad.searching
                Layout.preferredWidth: launchpad.sidebarW
                Layout.fillHeight: true
                clip: true
                model: launchpad.rootModel
                currentIndex: launchpad.selectedCategory
                spacing: Kirigami.Units.smallSpacing
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: catRow
                    width: ListView.view.width
                    height: Kirigami.Units.gridUnit * 2.6
                    radius: Kirigami.Units.cornerRadius > 0 ? Kirigami.Units.cornerRadius * 1.5 : 10
                    readonly property bool current: index === launchpad.selectedCategory
                    readonly property color accent: launchpad.accentColor
                    color: current ? Qt.rgba(accent.r, accent.g, accent.b, 0.45)
                                   : (catMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Kirigami.Icon {
                        id: catIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        source: model.decoration
                        // category icons are symbolic (monochrome) — render them
                        // as a white mask so they're visible on the dark sidebar.
                        isMask: true
                        color: "white"
                        opacity: catRow.current ? 1.0 : 0.82
                    }
                    PC3.Label {
                        anchors.left: catIcon.right
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.right: parent.right
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: model.display ? model.display : ""
                        elide: Text.ElideRight
                        color: "white"
                        opacity: catRow.current ? 1.0 : 0.82
                        font.bold: catRow.current
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.6)
                    }

                    MouseArea {
                        id: catMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { launchpad.selectedCategory = index; appGrid.currentIndex = 0 }
                    }
                }
            }

            // the app grid
            GridView {
                id: appGrid
                Layout.preferredWidth: launchpad.gridW
                Layout.fillWidth: launchpad.searching
                Layout.fillHeight: true
                clip: true
                cacheBuffer: Math.max(0, height) * 2
                keyNavigationEnabled: true
                highlightMoveDuration: 140
                model: launchpad.gridModel
                cellWidth: launchpad.cellW
                cellHeight: launchpad.cellH

                // Delegates MUST be sized to the cell — GridView does not size
                // them, and a 0×0 delegate renders its icon but is NOT clickable.
                delegate: AppDelegate {
                    width: appGrid.cellWidth
                    height: appGrid.cellHeight
                    iconSize: launchpad.cfgIconSize
                    labeled: launchpad.cfgLabels
                    selected: GridView.isCurrentItem
                    onActivated: launchpad.activateIndex(index)
                }

                QQC2.ScrollBar.vertical: QQC2.ScrollBar { }
            }
        }
    }

    // ---- the choreography -------------------------------------------------
    states: [
        State {
            name: "shown"; when: launchpad.shown
            PropertyChanges { target: scrim; opacity: launchpad.cfgDim }
            PropertyChanges { target: stage; opacity: 1.0; scale: 1.0 }
            PropertyChanges { target: launchpad; fxBlur: 0.0 }
        },
        State {
            name: "hidden"; when: !launchpad.shown
            PropertyChanges { target: scrim; opacity: 0.0 }
            PropertyChanges { target: stage; opacity: 0.0; scale: 0.92 }
            PropertyChanges { target: launchpad; fxBlur: launchpad.cfgBlur ? 0.6 : 0.0 }
        }
    ]
    transitions: [
        Transition {
            to: "shown"
            ParallelAnimation {
                NumberAnimation { target: scrim; property: "opacity"; duration: launchpad.introMs; easing.type: Easing.OutCubic }
                NumberAnimation { target: stage; properties: "opacity,scale"; duration: launchpad.introMs; easing.type: Easing.OutCubic }
                NumberAnimation { target: launchpad; property: "fxBlur"; duration: launchpad.introMs; easing.type: Easing.OutCubic }
            }
        },
        Transition {
            to: "hidden"
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { target: scrim; property: "opacity"; duration: launchpad.outroMs; easing.type: Easing.InCubic }
                    NumberAnimation { target: stage; properties: "opacity,scale"; duration: launchpad.outroMs; easing.type: Easing.InCubic }
                    NumberAnimation { target: launchpad; property: "fxBlur"; duration: launchpad.outroMs; easing.type: Easing.InCubic }
                }
                ScriptAction { script: launchpad._fireClosed() }
            }
        }
    ]
}
