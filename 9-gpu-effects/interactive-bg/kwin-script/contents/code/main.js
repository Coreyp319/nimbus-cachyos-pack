/*
 * WhiteSur Aurora — window-reactivity bridge (KWin script).
 *
 * KWin scripts are the ONLY thing that can see live window geometry on Wayland,
 * but they are sandboxed: no filesystem. So this script watches windows and
 * pushes their geometry (+ the moving window's velocity) OUT over D-Bus to the
 * aurora bridge daemon (org.whitesur.Aurora), which writes the state file the
 * wallpaper polls. See interactive-bg/README.md.
 *
 * Geometry is sent in GLOBAL screen pixels (frameGeometry is global); the
 * wallpaper normalises to its own screen. We send up to MAXWINS rects + the
 * actively-moving one with a computed velocity, throttled to ~MIN_DT ms.
 */
const SERVICE = "org.whitesur.Aurora";
const OBJPATH = "/";
const IFACE   = "org.whitesur.Aurora";
const METHOD  = "UpdateWindows";
const MAXWINS = 6;
const MIN_DT  = 30;          // ms between sends (~33 Hz); drags fire much faster

let lastSent = 0;
let moveRect = null;         // {x,y,w,h} px of the window being dragged, else null
let moveVel  = { x: 0, y: 0 };
let prevRect = null;         // previous sample of the moving window
let prevTime = 0;
const hooked = {};           // internalId -> true, so we attach signals once

function windows() {
    // API drifts across KWin releases; windowList() is current, stackingOrder is the fallback.
    if (typeof workspace.windowList === "function") return workspace.windowList();
    if (workspace.stackingOrder) return workspace.stackingOrder;
    return [];
}

function eligible(w) {
    return w && w.normalWindow === true && w.minimized !== true
             && w.skipTaskbar !== true && w.deleted !== true;
}

function rectOf(w) {
    const g = w.frameGeometry;
    return { x: g.x, y: g.y, w: g.width, h: g.height,
             active: w.active === true,
             moving: (w.move === true || w.resize === true) };
}

function build() {
    const all = windows();
    const wins = [];
    for (let i = 0; i < all.length && wins.length < MAXWINS; i++) {
        if (eligible(all[i])) wins.push(rectOf(all[i]));
    }
    const move = moveRect
        ? { x: moveRect.x, y: moveRect.y, w: moveRect.w, h: moveRect.h,
            vx: moveVel.x, vy: moveVel.y }
        : null;
    return JSON.stringify({ t: Date.now(), wins: wins, move: move });
}

function send(force) {
    const now = Date.now();
    if (!force && now - lastSent < MIN_DT) return;   // throttle the firehose
    lastSent = now;
    callDBus(SERVICE, OBJPATH, IFACE, METHOD, build());
}

function onStep(w) {
    const g = w.frameGeometry;
    const now = Date.now();
    const r = { x: g.x, y: g.y, w: g.width, h: g.height };
    if (prevRect && now > prevTime) {
        const dt = (now - prevTime) / 1000.0;        // px/s
        moveVel = { x: (r.x - prevRect.x) / dt, y: (r.y - prevRect.y) / dt };
    }
    prevRect = r; prevTime = now;
    moveRect = r;
    send(false);
}

function onFinish() {
    moveRect = null; prevRect = null; moveVel = { x: 0, y: 0 };
    send(true);                                      // resting state, move=null
}

function attach(w) {
    if (!w || !w.internalId) return;
    const id = "" + w.internalId;
    if (hooked[id]) return;
    hooked[id] = true;

    if (w.interactiveMoveResizeStepped)
        w.interactiveMoveResizeStepped.connect(function () { onStep(w); });
    if (w.interactiveMoveResizeFinished)
        w.interactiveMoveResizeFinished.connect(onFinish);
    if (w.frameGeometryChanged)
        w.frameGeometryChanged.connect(function () {
            if (w.move === true || w.resize === true) onStep(w);
            else send(false);                        // tiling / programmatic moves
        });
}

// hook everything present now, and anything that appears later
const initial = windows();
for (let i = 0; i < initial.length; i++) attach(initial[i]);

workspace.windowAdded.connect(function (w) { attach(w); send(true); });
workspace.windowRemoved.connect(function () { send(true); });
if (workspace.windowActivated) workspace.windowActivated.connect(function () { send(true); });

send(true);   // prime the state file so the wallpaper has data immediately
