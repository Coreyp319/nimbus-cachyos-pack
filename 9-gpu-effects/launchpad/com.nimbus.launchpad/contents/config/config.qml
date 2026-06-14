/*
 * Config categories for Nimbus Launchpad. One page; `source` resolves against
 * contents/ui/. See ConfigGeneral.qml for the actual form.
 */
import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "view-app-grid"
        source: "ConfigGeneral.qml"
    }
}
