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
mod hero;
mod scene_cyberpunk;
mod scene_hexen;
mod scene_journey;
mod window_react;

use bevy::{
    camera::RenderTarget,
    diagnostic::FrameTimeDiagnosticsPlugin,
    prelude::*,
    render::render_resource::{TextureFormat, TextureUsages},
    render::view::screenshot::{save_to_disk, Screenshot},
    window::PresentMode,
};
use bevy_live_wallpaper::{
    LinuxBackend, LiveWallpaperPlugin, WallpaperDisplayMode, WallpaperTargetMonitor,
};
use fluid::{FluidPlugin, SIM};

fn main() {
    let capture = std::env::var("NIMBUS_FLUX_CAPTURE").is_ok();
    // NIMBUS_FLUX_WALLPAPER=1 renders onto a Wayland wlr-layer-shell *background*
    // surface (via bevy_live_wallpaper) instead of a normal window — the scene becomes
    // a live, cursor-reactive desktop wallpaper.
    let wallpaper = std::env::var("NIMBUS_FLUX_WALLPAPER").is_ok();
    // Capture renders OFFSCREEN to an image (no window, no swapchain) when not a wallpaper —
    // the tuning-loop screenshot path. A windowed capture races the live RT wallpaper for the
    // NVIDIA swapchain and intermittently panics ("Couldn't get swap chain texture ...
    // timeout"); rendering to an image sidesteps the compositor entirely.
    let headless_capture = capture && !wallpaper;
    // Explicit NIMBUS_FLUX_SCENE wins; wallpaper mode defaults to the gothic "hexen"
    // dungeon (cyberpunk stays reachable via NIMBUS_FLUX_SCENE=cyberpunk).
    let scene = std::env::var("NIMBUS_FLUX_SCENE")
        .ok()
        .unwrap_or_else(|| if wallpaper { "hexen".into() } else { String::new() });
    // bevy_solari hardware ray-traced lighting/GI for the Solari-wired scenes
    // (experimental; needs a ray-tracing GPU). The hexen wallpaper uses RT **by
    // default**; journey is opt-in RT (NIMBUS_FLUX_RT=1) until its denoiser is wired,
    // so it defaults to the cleaner raster path even as a wallpaper. NIMBUS_FLUX_RT=0
    // forces raster; =1 forces RT in a windowed run. Other scenes ignore it.
    let rt = (scene == "hexen" || scene == "journey")
        && match std::env::var("NIMBUS_FLUX_RT").ok().as_deref() {
            Some("0") | Some("false") | Some("off") => false,
            Some(_) => true,
            None => wallpaper && scene == "hexen", // hexen wallpaper RT; journey raster
        };

    // No primary window in wallpaper mode (the layer-shell surface is owned by
    // LiveWallpaperPlugin) nor in headless capture (we render to an image) — and the app
    // must not exit when "no window" closes.
    let window_plugin = if wallpaper || headless_capture {
        WindowPlugin {
            primary_window: None,
            exit_condition: bevy::window::ExitCondition::DontExit,
            ..default()
        }
    } else {
        WindowPlugin {
            primary_window: Some(Window {
                title: "Nimbus Flux".into(),
                resolution: (SIM.x, SIM.y).into(),
                present_mode: PresentMode::AutoVsync,
                ..default()
            }),
            ..default()
        }
    };

    let mut app = App::new();
    app.insert_resource(ClearColor(Color::BLACK))
        .insert_resource(scene_cyberpunk::WallpaperMode(wallpaper));
    // DLSS's init plugin (pulled in by DefaultPlugins under --features dlss) requires this
    // resource before RenderPlugin or it panics — so insert it unconditionally when the
    // feature is built. It only registers DLSS Vulkan support; actual denoising happens
    // only on the RT camera (which adds the Dlss component). Harmless for other scenes.
    #[cfg(feature = "dlss")]
    app.insert_resource(bevy::anti_alias::dlss::DlssProjectId(bevy::asset::uuid::uuid!(
        "b9e2f1a4-3c5d-4e7f-8a1b-2c3d4e5f6a7b"
    )));
    let default_plugins = DefaultPlugins.set(window_plugin).set(ImagePlugin::default_linear());
    if headless_capture {
        // With no window, winit never pumps the update loop (the app hangs at startup), so
        // run TRULY headless: drop WinitPlugin and drive the schedule with ScheduleRunnerPlugin.
        // The GPU still renders offscreen to the target image; nothing touches a surface.
        app.add_plugins(default_plugins.build().disable::<bevy::winit::WinitPlugin>())
            .add_plugins(bevy::app::ScheduleRunnerPlugin::run_loop(
                std::time::Duration::from_secs_f64(1.0 / 60.0),
            ));
    } else {
        app.add_plugins(default_plugins);
    }
    app.add_plugins(FrameTimeDiagnosticsPlugin::default());

    // Ray-traced lighting: SolariPlugins must be added early (it requests the
    // ray-tracing wgpu features before the render device is created).
    if rt {
        app.add_plugins(bevy::solari::prelude::SolariPlugins);
    }

    if wallpaper {
        app.add_plugins(LiveWallpaperPlugin {
            target_monitor: WallpaperTargetMonitor::Index(0),
            display_mode: WallpaperDisplayMode::Wallpaper,
            linux_backend: LinuxBackend::Wayland,
        });
    }

    // Scene selector: gothic dungeon or cyberpunk city showpiece, else the fluid sim.
    match scene.as_str() {
        "hexen" => {
            app.add_plugins(scene_hexen::HexenPlugin { rt });
        }
        "journey" => {
            app.add_plugins(scene_journey::JourneyPlugin { rt });
        }
        "cyberpunk" => {
            app.add_plugins(scene_cyberpunk::CyberpunkPlugin);
        }
        _ => {
            app.add_plugins(FluidPlugin).add_plugins(hero::HeroPlugin);
        }
    }

    // Headless capture: render the scene to an offscreen image and screenshot THAT, so the
    // tuning loop never opens a window or touches the compositor swapchain (the app runs
    // under ScheduleRunnerPlugin, set up above, since there's no winit to pump it).
    if headless_capture {
        app.insert_resource(HeadlessCapture {
            width: SIM.x,
            height: SIM.y,
            path: std::env::var("NIMBUS_FLUX_CAPTURE_PATH")
                .unwrap_or_else(|_| "/tmp/nimbus-flux-frame.png".into()),
        });
        app.add_systems(Startup, setup_headless_target);
        app.add_systems(Update, (redirect_camera_to_target, headless_screenshot_and_exit));
    }

    app.run();
}

/// Offscreen capture config: the render-target size + where to write the PNG.
#[derive(Resource)]
struct HeadlessCapture {
    width: u32,
    height: u32,
    path: String,
}

/// Handle of the image the scene camera is redirected to render into.
#[derive(Resource)]
struct HeadlessTarget(Handle<Image>);

/// Create the offscreen render-target image (RGBA8 sRGB; +COPY_SRC so the screenshot can
/// read it back). `new_target_texture` sets RENDER_ATTACHMENT|TEXTURE_BINDING|COPY_DST.
fn setup_headless_target(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>,
    cfg: Res<HeadlessCapture>,
) {
    let mut image = Image::new_target_texture(cfg.width, cfg.height, TextureFormat::Rgba8UnormSrgb, None);
    image.texture_descriptor.usage |= TextureUsages::COPY_SRC;
    commands.insert_resource(HeadlessTarget(images.add(image)));
}

/// Point the scene's camera at the offscreen image instead of a window. Runs every frame
/// until a camera exists (so it's independent of Startup ordering), then idles.
fn redirect_camera_to_target(
    target: Option<Res<HeadlessTarget>>,
    mut targets: Query<&mut RenderTarget, With<Camera>>,
    mut done: Local<bool>,
) {
    if *done {
        return;
    }
    let Some(target) = target else { return };
    let mut redirected = false;
    for mut render_target in &mut targets {
        *render_target = target.0.clone().into();
        redirected = true;
    }
    if redirected {
        *done = true;
    }
}

/// Snapshot the offscreen image ~4s in (after props/textures have streamed in), then exit —
/// mirrors the old windowed capture's timing.
fn headless_screenshot_and_exit(
    time: Res<Time>,
    cfg: Res<HeadlessCapture>,
    target: Option<Res<HeadlessTarget>>,
    mut commands: Commands,
    mut state: Local<u8>,
) {
    let t = time.elapsed_secs();
    if *state == 0 && t > 4.0 {
        if let Some(target) = target {
            commands
                .spawn(Screenshot::image(target.0.clone()))
                .observe(save_to_disk(cfg.path.clone()));
            *state = 1;
        }
    }
    if *state == 1 && t > 6.0 {
        // One-shot: the snapshot was saved ~2s ago and is flushed by now, so a hard exit is
        // safe and avoids the event-writer API.
        std::process::exit(0);
    }
}
