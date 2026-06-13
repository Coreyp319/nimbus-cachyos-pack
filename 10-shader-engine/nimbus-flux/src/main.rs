//! Nimbus Flux — standalone GPU shader engine (Nimbus pack, Layer 10).
//!
//! A bevy/wgpu app running a real GPU compute-shader fluid simulation, separate
//! from the KDE desktop. See `fluid.rs` for the solver.
//!
//! Controls: move/drag the cursor to push the fluid and inject dye.
//!   1 / 2 / 3  switch style (ink / mercury / water)   ·   D  toggle light/dark
//!
//! Setting `NIMBUS_FLUX_CAPTURE=1` runs a headless-style check: save a frame to
//! /tmp/nimbus-flux-frame.png at ~4s, log average FPS, then exit at ~6s.

mod fluid;

use bevy::{
    diagnostic::{DiagnosticsStore, FrameTimeDiagnosticsPlugin},
    prelude::*,
    render::view::screenshot::{save_to_disk, Screenshot},
    window::PresentMode,
};
use fluid::{FluidPlugin, SIM};

fn main() {
    let capture = std::env::var("NIMBUS_FLUX_CAPTURE").is_ok();

    let mut app = App::new();
    app.insert_resource(ClearColor(Color::BLACK))
        .add_plugins(
            DefaultPlugins
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        title: "Nimbus Flux".into(),
                        resolution: (SIM.x, SIM.y).into(),
                        present_mode: PresentMode::AutoVsync,
                        ..default()
                    }),
                    ..default()
                })
                .set(ImagePlugin::default_linear()),
        )
        .add_plugins(FrameTimeDiagnosticsPlugin::default())
        .add_plugins(FluidPlugin);

    if capture {
        app.add_systems(Update, capture_and_exit);
    }

    app.run();
}

/// Capture-mode lifecycle: snapshot a frame, log FPS, exit. Gated on the env var.
fn capture_and_exit(
    time: Res<Time>,
    diagnostics: Res<DiagnosticsStore>,
    mut commands: Commands,
    mut state: Local<u8>,
) {
    let t = time.elapsed_secs();
    if *state == 0 && t > 4.0 {
        commands
            .spawn(Screenshot::primary_window())
            .observe(save_to_disk("/tmp/nimbus-flux-frame.png"));
        *state = 1;
    }
    if *state == 1 && t > 6.0 {
        if let Some(fps) = diagnostics.get(&FrameTimeDiagnosticsPlugin::FPS) {
            if let Some(avg) = fps.average() {
                info!("NIMBUS_FLUX_FPS avg={avg:.1}");
            }
        }
        // Capture mode is a one-shot check; the snapshot was saved ~2s ago and is
        // flushed by now, so a hard exit is safe and avoids the event-writer API.
        std::process::exit(0);
    }
}
