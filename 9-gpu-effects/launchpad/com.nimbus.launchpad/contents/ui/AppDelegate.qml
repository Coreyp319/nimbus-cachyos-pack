/*
 * AppDelegate.qml — one app cell (icon + label) for the grid, the favourites
 * strip and search results.
 *
 * Reads the kicker model roles from its delegate context (model.decoration,
 * model.display, model.favoriteId). Styling matches the pack's expressive idiom:
 * a hover/selected spring-scale (OutBack) and a GPU drop shadow under the icon
 * (QtQuick.Effects.MultiEffect), so it reads as a tactile "lift" — and the white
 * label carries its own soft shadow so it stays legible over any wallpaper.
 */
import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Item {
    id: del

    // set by whoever instantiates the delegate
    property int iconSize: 64
    property bool labeled: true
    property bool selected: false
    // the pack's one accent — used for the keyboard-current highlight
    property color accentColor: Kirigami.Theme.highlightColor

    signal activated()
    signal contextRequested()

    readonly property bool engaged: hover.hovered || del.selected

    // soft rounded backing that fades in when engaged. Hover = neutral white;
    // keyboard-selected = the accent tint, so the focused app reads clearly.
    Rectangle {
        anchors.centerIn: column
        width: column.width + Kirigami.Units.largeSpacing
        height: column.height + Kirigami.Units.smallSpacing
        radius: Kirigami.Units.cornerRadius > 0 ? Kirigami.Units.cornerRadius * 1.5 : 12
        color: del.selected ? del.accentColor : "white"
        opacity: del.engaged ? (tap.pressed ? 0.32 : (del.selected ? 0.42 : 0.14)) : 0.0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on color   { ColorAnimation  { duration: 140 } }
    }

    Column {
        id: column
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing
        width: del.width - Kirigami.Units.largeSpacing

        Item {
            id: iconWrap
            width: del.iconSize
            height: del.iconSize
            anchors.horizontalCenter: parent.horizontalCenter

            // Calm, zero-overshoot lift — Big Sur personality is premium, not
            // playful (no spring/bounce here, unlike the config controls).
            scale: tap.pressed ? 0.92 : (del.engaged ? 1.08 : 1.0)
            Behavior on scale {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Kirigami.Icon {
                id: icon
                anchors.fill: parent
                active: del.engaged
                source: model.decoration
                // GPU drop shadow — soft and dark at rest, lifts a little when engaged
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                    autoPaddingEnabled: true
                    blurMax: 24
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.45)
                    shadowBlur: del.engaged ? 0.7 : 0.45
                    shadowVerticalOffset: del.engaged ? 6 : 4
                    shadowOpacity: 0.6
                    Behavior on shadowBlur           { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on shadowVerticalOffset { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
            }
        }

        PC3.Label {
            visible: del.labeled
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            text: model.display ? model.display : ""
            color: "white"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            // dark outline = legible over any wallpaper (Text.style has no
            // "Shadow"; Outline gives a readable halo).
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.7)
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        onTapped: del.activated()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: del.contextRequested()
    }
}
