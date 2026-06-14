/*
 * ConfigGeneral.qml — the Launchpad settings page.
 *
 * Plain Kirigami.FormLayout + standard controls (the launcher itself is the
 * expressive surface; the config dialog stays conventional and instantiable —
 * the repo's QML test constructs this in a real engine to catch blank dialogs).
 * cfg_* aliases bind to the main.xml entries.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_columns: columnsSpin.value
    property alias cfg_iconSize: iconSizeSpin.value
    property alias cfg_showLabels: labelsCheck.checked
    property alias cfg_animationDuration: durationSpin.value
    property alias cfg_backdropDim: dimSlider.value
    property alias cfg_introBlur: blurCheck.checked

    QQC2.SpinBox {
        id: columnsSpin
        Kirigami.FormData.label: i18n("Apps per row:")
        from: 4; to: 12; stepSize: 1
    }

    QQC2.SpinBox {
        id: iconSizeSpin
        Kirigami.FormData.label: i18n("Icon size:")
        from: 32; to: 128; stepSize: 8
    }

    QQC2.CheckBox {
        id: labelsCheck
        Kirigami.FormData.label: i18n("Labels:")
        text: i18n("Show application names")
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.SpinBox {
        id: durationSpin
        Kirigami.FormData.label: i18n("Open animation:")
        from: 80; to: 600; stepSize: 10
        textFromValue: function(value) { return value + " ms" }
        valueFromText: function(text) { return parseInt(text) }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Backdrop dim:")
        QQC2.Slider {
            id: dimSlider
            from: 0.0; to: 0.8; stepSize: 0.05
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
        }
        QQC2.Label { text: Math.round(dimSlider.value * 100) + "%" }
    }

    QQC2.CheckBox {
        id: blurCheck
        Kirigami.FormData.label: i18n("Effects:")
        text: i18n("Blur the grid as it zooms in/out")
    }
}
