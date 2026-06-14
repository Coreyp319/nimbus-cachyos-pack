/*
 * Nimbus Launchpad — a full-screen Big Sur app launcher (Plasma 6).
 *
 * We do NOT fork the whole kicker plasmoid. We reuse its installed C++ engine
 * (org.kde.plasma.private.kicker): the app/search/favourites models AND the
 * frameless full-screen DashboardWindow — which already asks KWin to blur the
 * desktop behind it (KWindowEffects::enableBlurBehind). We supply our OWN
 * content (Launchpad.qml) + open/close choreography. That keeps this a small,
 * self-contained Nimbus artifact while the heavy lifting (app DB, KRunner
 * search, drag-to-launch) stays in the maintained engine.
 *
 * The intro/outro lives entirely in QML: DashboardWindow only maps/unmaps the
 * window, so we keep it mapped through the close animation and unmap it only
 * once the outro finishes (see requestClose()).
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Shown INLINE on the panel as one icon button (mirrors the dock separator —
    // the proven sizing pattern in this dock): the root carries the panel Layout
    // hints and the representation fills the panel thickness + stays square.
    // (A custom compactRepresentation rendered nothing: the panel sizes the
    // representation by its IMPLICIT size, and a bare MouseArea is 0×0.) Clicking
    // toggles the full-screen dashboard window — never an applet popup.
    preferredRepresentation: fullRepresentation
    Layout.fillHeight: true
    Layout.fillWidth: false

    // captured so the dashboard opens on the screen that holds the panel icon.
    property Item compactItem: null

    // ---- app + search + favourites models (the installed kicker engine) ----
    Kicker.KAStatsFavoritesModel { id: globalFavorites }

    Kicker.RootModel {
        id: rootModel
        autoPopulate: true
        appNameFormat: 0            // NameOnly
        // flat + sorted + !showTopLevelItems = one flat alphabetical list of ALL
        // apps (these live on the AppsModel prototype RootModel inherits).
        // showTopLevelItems:true (or showAllApps) leaves only the categories.
        flat: true
        sorted: true
        showSeparators: false
        showTopLevelItems: false
        appletInterface: root
        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showPowerSession: false
        showFavoritesPlaceholder: false
        favoritesModel: globalFavorites
    }

    Kicker.RunnerModel {
        id: runnerModel
        appletInterface: root
        favoritesModel: globalFavorites
        mergeResults: true         // a single flat result list, not per-runner groups
        // .query is bound from the search field in Launchpad.qml
    }

    // rootModel rows: 0 = "All Applications", 1.. = categories (showAllApps on).
    // Launchpad uses it for the sidebar and pulls each category's apps via
    // rootModel.modelForRow(row).

    // ---- the full-screen window + our content ------------------------------
    Kicker.DashboardWindow {
        id: dashboard
        backgroundColor: "transparent"      // we paint our own animated scrim
        keyEventProxy: content.searchField  // typing anywhere filters the grid
        visualParent: root.compactItem

        // DashboardWindow's default property is mainItem, so this Launchpad
        // becomes the window content automatically.
        Launchpad {
            id: content
            // sized to the window explicitly (it's reparented in as mainItem)
            width: dashboard.width
            height: dashboard.height
            rootModel: rootModel
            runnerModel: runnerModel
            // config lives here, in the valid Plasmoid context
            cfgColumns: Plasmoid.configuration.columns
            cfgIconSize: Plasmoid.configuration.iconSize
            cfgLabels: Plasmoid.configuration.showLabels
            cfgDuration: Plasmoid.configuration.animationDuration
            cfgDim: Plasmoid.configuration.backdropDim
            cfgBlur: Plasmoid.configuration.introBlur
            onLaunched: dashboard.requestClose()
            onCloseRequested: dashboard.requestClose()
        }

        onKeyEscapePressed: content.handleEscape()
        onVisibleChanged: {
            if (visible) content.open()       // play the intro
            else content.resetClosed()        // baseline for the next open
        }

        // Re-entrancy guard so a second click / Esc mid-outro is ignored.
        property bool closing: false
        function requestOpen() {
            if (visible) return
            visible = true       // map the window (proven open path)
            raise()              // …above other windows
            requestActivate()    // …and focused, so it's the active overlay
        }
        function requestClose() {
            if (closing || !visible) return
            closing = true
            content.close(function() { dashboard.visible = false; dashboard.closing = false })
        }
        function toggleDashboard() {
            if (visible && !closing) requestClose()
            else if (!visible) requestOpen()
        }
    }

    // ---- panel button ------------------------------------------------------
    fullRepresentation: MouseArea {
        id: launcherButton
        // Fill the panel thickness, width follows height (square). implicitHeight
        // is a sane fallback when not on a panel. The panel sizes a representation
        // by its implicit size — without this it is 0×0 and invisible.
        Layout.fillHeight: true
        Layout.fillWidth: false
        implicitWidth: height
        implicitHeight: Kirigami.Units.iconSizes.medium
        hoverEnabled: true
        activeFocusOnTab: true
        onClicked: dashboard.toggleDashboard()
        Component.onCompleted: root.compactItem = launcherButton

        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing   // small inset, like the dock icons
            active: launcherButton.containsMouse
            source: Plasmoid.configuration.icon || Plasmoid.icon
        }
    }
}
