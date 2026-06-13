#!/usr/bin/env python3
"""Nimbus Aurora — window-reactivity bridge daemon.

KWin scripts can see live window geometry but cannot write files; the wallpaper
can read files but cannot see other windows. This tiny daemon is the hinge: it
owns the D-Bus name org.nimbus.Aurora, receives UpdateWindows(json) from the
KWin script, and writes the payload atomically to a state file the wallpaper
polls ($XDG_RUNTIME_DIR/nimbus-aurora/windows.json).

Deps: dbus-python + PyGObject (GLib). Run as a systemd --user service.
"""
import os
import sys
import tempfile

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

BUS_NAME = "org.nimbus.Aurora"
OBJ_PATH = "/"

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
OUT_DIR = os.path.join(RUNTIME, "nimbus-aurora")
OUT_FILE = os.path.join(OUT_DIR, "windows.json")


class Bridge(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, OBJ_PATH)

    @dbus.service.method(BUS_NAME, in_signature="s", out_signature="")
    def UpdateWindows(self, payload):
        try:
            os.makedirs(OUT_DIR, exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=OUT_DIR, prefix=".windows-", suffix=".json")
            with os.fdopen(fd, "w") as f:
                f.write(payload)
            os.replace(tmp, OUT_FILE)   # atomic: the wallpaper never sees a half-written file
        except Exception as exc:                       # never let one bad write kill the loop
            sys.stderr.write("aurora-bridge: write failed: %s\n" % exc)


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    # IMPORTANT: keep references to BOTH the BusName and the Object alive for the
    # life of the loop. If the BusName is GC'd, dbus-python releases the well-known
    # name (its __del__ calls ReleaseName) — the daemon then runs but owns no name,
    # so KWin's callDBus silently goes nowhere. These locals live as long as main().
    bus_name = dbus.service.BusName(BUS_NAME, bus)      # claim the well-known name
    bridge = Bridge(bus)                                # export the object at "/"
    os.makedirs(OUT_DIR, exist_ok=True)
    _keep_alive = (bus_name, bridge)                    # explicit: do not let these GC
    GLib.MainLoop().run()
    del _keep_alive


if __name__ == "__main__":
    main()
