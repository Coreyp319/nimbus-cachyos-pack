/*
 * Nimbus Aurora — cursor-reactive wallpaper (Plasma 6).
 *
 * Renders contents/shaders/aurora.frag.qsb full-screen via a ShaderEffect on the
 * QtQuick scene graph. Time is frame-synced; the pointer is tracked hover-only so
 * desktop clicks / the right-click menu still pass through. Config lives in
 * contents/config/main.xml and is read through `root.configuration`.
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

WallpaperItem {
    id: root

    // --- config (with safe fallbacks) --------------------------------------
    readonly property real cfgSpeed:         configuration.Speed         ?? 1.0
    readonly property real cfgInteractivity: configuration.Interactivity ?? 0.0
    readonly property real cfgWinReact:      configuration.WindowReact   ?? 0.0
    readonly property real cfgMusicReact:    configuration.MusicReact    ?? 0.30
    readonly property real cfgIntensity:     configuration.Intensity     ?? 1.0
    readonly property int  cfgTheme:         configuration.Theme         ?? 0
    readonly property int  cfgStyle:         configuration.Style         ?? 0
    readonly property int  cfgAppearance:    configuration.Appearance    ?? 0  // 0 auto · 1 light · 2 dark

    // Light/dark. In auto mode we follow the Plasma colour scheme by polling its
    // canonical value (Kirigami.Theme does NOT track it in a wallpaper context).
    // The dock's light/dark toggle changes ColorScheme, so this picks it up.
    property bool schemeDark: true
    readonly property real uDark: cfgAppearance === 1 ? 0.0
                                : cfgAppearance === 2 ? 1.0
                                : (schemeDark ? 1.0 : 0.0)

    P5Support.DataSource {
        id: schemeProbe
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const s = (data["stdout"] || "").trim()
            if (s.length > 0) root.schemeDark = s.indexOf("Dark") !== -1
            disconnectSource(source)
        }
        function probe() { connectSource("kreadconfig6 --file kdeglobals --group General --key ColorScheme") }
    }
    // Reduce-motion: honour KDE's "Animation speed = Instant"
    // (AnimationDurationFactor 0) by freezing the drift. Same cheap poll cadence.
    property bool reduceMotion: false
    P5Support.DataSource {
        id: motionProbe
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const s = (data["stdout"] || "").trim()
            if (s.length > 0) root.reduceMotion = parseFloat(s) === 0.0
            disconnectSource(source)
        }
        function probe() { connectSource("kreadconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor") }
    }
    // 1 s so the dock light/dark toggle is picked up quickly (was 2 s, which read
    // as "the toggle does nothing" — there's an extra 700 ms uDark ease on top).
    Timer { interval: 1000; repeat: true; running: true; triggeredOnStart: true
            onTriggered: { schemeProbe.probe(); motionProbe.probe() } }

    // --- window reactivity -------------------------------------------------
    // The KWin script + bridge daemon write live window geometry to a state file
    // in the runtime dir (see interactive-bg/README.md). We poll it here, map the
    // global-pixel rects to THIS screen's 0..1 space, and feed the shader. Costs
    // nothing when cfgWinReact == 0 (the timer stops, the shader skips the work).
    property string statePath: ""        // file:// URL, resolved once via $XDG_RUNTIME_DIR
    property string audioPath: ""        // file:// URL for the music bridge's state file
    property real   _velX: 0.0           // EMA-smoothed active-window velocity (p-space)
    property real   _velY: 0.0

    P5Support.DataSource {
        id: runtimeProbe
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const dir = (data["stdout"] || "").trim()
            if (dir.length > 0) {
                root.statePath = "file://" + dir + "/nimbus-aurora/windows.json"
                root.audioPath = "file://" + dir + "/nimbus-aurora/audio.json"
            }
            disconnectSource(source)
        }
        Component.onCompleted: connectSource("printf %s \"$XDG_RUNTIME_DIR\"")
    }

    // Reads the window state file via the executable engine (a `cat`). This is the
    // ONLY mechanism we use: XHR on a file:// URL never reaches DONE in this Plasma
    // build, so it silently delivered nothing. The exec engine is the same path the
    // scheme/motion probes use and is reliable. connectSource runs the command,
    // onNewData disconnects so the next read re-runs it.
    P5Support.DataSource {
        id: winFileProbe
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const txt = (data["stdout"] || "")
            disconnectSource(source)
            if (txt.length > 0) root.applyWindows(txt)
        }
        function read(path) { connectSource("cat " + path + " 2>/dev/null") }
    }

    function pollWindows() {
        if (root.statePath.length === 0 || root.cfgWinReact <= 0.0) return
        winFileProbe.read(root.statePath.substring(7))   // statePath is "file://…" — strip the scheme for `cat`
    }

    // Map global-pixel window rects onto this wallpaper's screen and push to the shader.
    function applyWindows(text) {
        var d
        try { d = JSON.parse(text) } catch (e) { return }   // ignore a half-written read
        var sx = Screen.virtualX, sy = Screen.virtualY
        var sw = Screen.width,    sh = Screen.height
        if (sw <= 0 || sh <= 0) return

        var zero = Qt.vector4d(0, 0, 0, 0)
        var slots = [zero, zero, zero, zero, zero, zero]
        var n = 0
        var wins = d.wins || []
        for (var i = 0; i < wins.length && n < 6; i++) {
            var w = wins[i]
            var nx = (w.x - sx) / sw, ny = (w.y - sy) / sh
            var nw = w.w / sw,        nh = w.h / sh
            if (nx + nw <= 0 || nx >= 1 || ny + nh <= 0 || ny >= 1) continue  // not on this screen
            slots[n++] = Qt.vector4d(nx, ny, nw, nh)
        }
        aurora.uWin0 = slots[0]; aurora.uWin1 = slots[1]; aurora.uWin2 = slots[2]
        aurora.uWin3 = slots[3]; aurora.uWin4 = slots[4]; aurora.uWin5 = slots[5]
        aurora.uWinCount = n

        if (d.move) {
            aurora.uActiveWin = Qt.vector4d((d.move.x - sx) / sw, (d.move.y - sy) / sh,
                                            d.move.w / sw, d.move.h / sh)
            // velocity in the shader's aspect-corrected p-space (1 unit = screen
            // HEIGHT on both axes), so speed and direction are isotropic — a
            // diagonal drag wakes like a horizontal one of equal pixel speed.
            var rvx = d.move.vx / sh, rvy = d.move.vy / sh
            // EMA-smooth it: the bridge's velocity is a raw finite difference with a
            // jittery per-event dt, so unsmoothed it spiked frame to frame and made
            // the wake brightness FLASH during drags. Smoothing de-flickers it.
            root._velX = 0.35 * rvx + 0.65 * root._velX
            root._velY = 0.35 * rvy + 0.65 * root._velY
            aurora.uActiveVel = Qt.vector2d(root._velX, root._velY)
            aurora.uActiveMove = 1.0
        } else {
            // keep the LAST velocity and let the eased uActiveMove fade the whole
            // wake (ring + trail + flow-shove) out together. Zeroing vel here
            // snapped the directional trail off the instant you released, leaving
            // only the symmetric ring — the motion lost its sense of momentum.
            aurora.uActiveMove = 0.0
        }
    }

    Timer {
        interval: 33; repeat: true            // ~30 Hz; the shader's own motion fills gaps
        running: root.cfgWinReact > 0.0 && root.statePath.length > 0
        onTriggered: root.pollWindows()
    }

    // --- music reactivity --------------------------------------------------
    // The audio bridge (pw-cat → FFT, a systemd --user service) writes
    // bass/mid/treble/level/beat to audio.json in the runtime dir. Read via the
    // executable engine, same as the window state (file:// XHR is unusable here).
    P5Support.DataSource {
        id: audioFileProbe
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            const txt = (data["stdout"] || "")
            disconnectSource(source)
            if (txt.length > 0) root.applyAudio(txt)
        }
        function read(path) { connectSource("cat " + path + " 2>/dev/null") }
    }

    function pollAudio() {
        if (root.audioPath.length === 0 || root.cfgMusicReact <= 0.0) return
        audioFileProbe.read(root.audioPath.substring(7))   // audioPath is "file://…" — strip the scheme for `cat`
    }

    function applyAudio(text) {
        var a
        try { a = JSON.parse(text) } catch (e) { return }
        aurora.uBass   = a.bass   ?? 0.0
        aurora.uMid    = a.mid    ?? 0.0
        aurora.uTreble = a.treble ?? 0.0
        aurora.uLevel  = a.level  ?? 0.0
        aurora.uBeat   = a.beat   ?? 0.0     // snappy: not eased, so the ripple stays crisp
    }

    Timer {
        interval: 33; repeat: true            // ~30 Hz, matches the bridge's write cadence
        running: root.cfgMusicReact > 0.0 && root.audioPath.length > 0
        onTriggered: root.pollAudio()
    }

    // frame-synced clock for iTime
    FrameAnimation {
        id: clock
        running: true
    }

    ShaderEffect {
        id: aurora
        anchors.fill: parent
        // re-evaluated every frame via the iTime binding -> continuous repaint
        fragmentShader: Qt.resolvedUrl("../shaders/aurora.frag.qsb")

        property real     iTime: clock.elapsedTime
        property vector2d iResolution: Qt.vector2d(width, height)
        property real     uSpeed: root.reduceMotion ? 0.0 : root.cfgSpeed
        property real     uInteractivity: root.cfgInteractivity
        property real     uIntensity: root.cfgIntensity
        property int      uTheme: root.cfgTheme
        property int      uStyle: root.cfgStyle
        // eased so the dock light/dark toggle cross-fades instead of snapping
        property real     uDark: root.uDark
        Behavior on uDark { NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } }

        // custom palette (consumed by the shader only when uTheme == 3)
        property color    uColor0: root.configuration.Color0 ?? "#0d0f29"
        property color    uColor1: root.configuration.Color1 ?? "#1c2e73"
        property color    uColor2: root.configuration.Color2 ?? "#4552b8"
        property color    uColor3: root.configuration.Color3 ?? "#8f5cb8"
        property color    uColor4: root.configuration.Color4 ?? "#fa8c73"

        // window reactivity (fed by pollWindows/applyWindows above). Rects are
        // normalised to this screen; the wake fades via the eased uActiveMove so
        // letting go of a window doesn't snap the glow off.
        property real     uWinReact: root.cfgWinReact
        property int      uWinCount: 0
        property vector4d uWin0: Qt.vector4d(0, 0, 0, 0)
        property vector4d uWin1: Qt.vector4d(0, 0, 0, 0)
        property vector4d uWin2: Qt.vector4d(0, 0, 0, 0)
        property vector4d uWin3: Qt.vector4d(0, 0, 0, 0)
        property vector4d uWin4: Qt.vector4d(0, 0, 0, 0)
        property vector4d uWin5: Qt.vector4d(0, 0, 0, 0)
        property vector4d uActiveWin: Qt.vector4d(0, 0, 0, 0)
        property vector2d uActiveVel: Qt.vector2d(0, 0)
        property real     uActiveMove: 0.0
        Behavior on uActiveMove { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        // music reactivity (fed by pollAudio/applyAudio). Bands eased so they
        // glide; uBeat is left un-eased so the ripple fires crisply.
        property real     uMusicReact: root.cfgMusicReact
        property real     uBass: 0.0
        property real     uMid: 0.0
        property real     uTreble: 0.0
        property real     uLevel: 0.0
        property real     uBeat: 0.0
        Behavior on uBass   { NumberAnimation { duration: 90;  easing.type: Easing.OutQuad } }
        Behavior on uMid    { NumberAnimation { duration: 90;  easing.type: Easing.OutQuad } }
        Behavior on uTreble { NumberAnimation { duration: 70;  easing.type: Easing.OutQuad } }
        Behavior on uLevel  { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

        // pointer, eased component-wise so motion feels liquid, not twitchy
        property real     iMouseX: 0.5
        property real     iMouseY: 0.5
        property vector2d iMouse: Qt.vector2d(iMouseX, iMouseY)
        property real     iMouseActive: 0.0
        Behavior on iMouseX      { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on iMouseY      { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on iMouseActive { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    }

    // hover-only tracking: NoButton => presses fall through to the desktop
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: (m) => {
            aurora.iMouseX = m.x / width
            aurora.iMouseY = m.y / height
            aurora.iMouseActive = 1.0
        }
        onEntered: aurora.iMouseActive = 1.0
        onExited:  aurora.iMouseActive = 0.0
    }
}
