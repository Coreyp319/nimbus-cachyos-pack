/*
 * AuroraColorButton — KQuickControls.ColorButton with a hover micro-interaction.
 *
 * ColorButton is a C++ control that paints its own swatch, so we can't restyle
 * its internals — but it's an Item, so a hover spring-scale reads as a tactile
 * "lift" consistent with AuroraSlider/AuroraComboBox. Subclassing keeps `color`
 * (and showAlphaChannel) intact, so the cfg_Color* aliases keep working.
 */
import QtQuick
import org.kde.kquickcontrols as KQuickControls

KQuickControls.ColorButton {
    id: root

    scale: hover.hovered ? 1.06 : 1.0
    Behavior on scale {
        NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
}
