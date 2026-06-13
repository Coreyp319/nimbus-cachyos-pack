// Nimbus Flux — GPU compute Eulerian fluid (stable fluids, Jos Stam).
//
// One module, many entry points, ONE bind-group layout shared by all passes:
//   binding 0  srcA  read   — first input field
//   binding 1  srcB  read   — second input field (bind = srcA when a pass needs only one)
//   binding 2  dst   write  — output field
//   binding 3  cfg   uniform
// The CPU side routes different physical textures through these slots per pass
// (the game-of-life ping-pong trick, generalized to a multi-pass solver).

struct Config {
    sim:        vec2<f32>,   // simulation resolution in texels
    mouse:      vec2<f32>,   // cursor position in texel space
    mouse_vel:  vec2<f32>,   // cursor velocity (texels/step)
    dye_color:  vec4<f32>,   // rgb = injected dye colour, a = mouse_down
    palette0:   vec4<f32>,
    palette1:   vec4<f32>,
    palette2:   vec4<f32>,
    palette3:   vec4<f32>,
    params:     vec4<f32>,   // x dt · y vel_dissipation · z dye_dissipation · w time
    params2:    vec4<f32>,   // x splat_radius · y force_scale · z dark · w style
};

@group(0) @binding(0) var srcA: texture_storage_2d<rgba32float, read>;
@group(0) @binding(1) var srcB: texture_storage_2d<rgba32float, read>;
@group(0) @binding(2) var dst:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> cfg: Config;

const WG: u32 = 8u;

fn dims() -> vec2<i32> { return vec2<i32>(cfg.sim); }
fn inb(p: vec2<i32>) -> bool { let d = dims(); return p.x < d.x && p.y < d.y; }
fn clampc(c: vec2<i32>) -> vec2<i32> { return clamp(c, vec2<i32>(0), dims() - vec2<i32>(1)); }

fn loadA(c: vec2<i32>) -> vec4<f32> { return textureLoad(srcA, clampc(c)); }
fn loadB(c: vec2<i32>) -> vec4<f32> { return textureLoad(srcB, clampc(c)); }

// scalar "height"/density of the dye field (srcA) at an integer cell
fn densv(c: vec2<i32>) -> f32 { let d = loadA(c).rgb; return max(max(d.r, d.g), d.b); }

// Bilinear sample of srcB at a floating texel position (for semi-Lagrangian advection).
fn sampleB(p: vec2<f32>) -> vec4<f32> {
    let d = vec2<f32>(dims());
    let c = clamp(p, vec2<f32>(0.5), d - vec2<f32>(0.5));
    let i = floor(c - 0.5);
    let f = c - 0.5 - i;
    let bi = vec2<i32>(i);
    let a = loadB(bi);
    let b = loadB(bi + vec2<i32>(1, 0));
    let cc = loadB(bi + vec2<i32>(0, 1));
    let e = loadB(bi + vec2<i32>(1, 1));
    return mix(mix(a, b, f.x), mix(cc, e, f.x), f.y);
}

// Palette ramp across the four configured stops, t in 0..1.
fn ramp(t: f32) -> vec3<f32> {
    let x = clamp(t, 0.0, 1.0) * 3.0;
    if (x < 1.0) { return mix(cfg.palette0.rgb, cfg.palette1.rgb, x); }
    if (x < 2.0) { return mix(cfg.palette1.rgb, cfg.palette2.rgb, x - 1.0); }
    return mix(cfg.palette2.rgb, cfg.palette3.rgb, x - 2.0);
}

fn gaussian(d: vec2<f32>, r: f32) -> f32 { return exp(-dot(d, d) / max(r * r, 1.0)); }

// Two slow orbiting emitters so the fluid is alive with no cursor input.
fn emitter(idx: i32) -> vec2<f32> {
    let t = cfg.params.w;
    let phase = f32(idx) * 2.3994; // golden-ish offset
    let a = t * (0.13 + 0.05 * f32(idx)) + phase;
    let r = vec2<f32>(0.26, 0.22) * cfg.sim;
    let c = 0.5 * cfg.sim;
    return c + vec2<f32>(cos(a), sin(a * 1.3)) * r;
}

// --- advection ------------------------------------------------------------
fn advect(p: vec2<i32>, dissipation: f32) -> vec4<f32> {
    let pos = vec2<f32>(p) + 0.5;
    let vel = loadA(p).xy;                 // velocity field is always srcA
    let back = pos - cfg.params.x * vel;   // backtrace
    return sampleB(back) * dissipation;    // field being carried is srcB
}

@compute @workgroup_size(8, 8, 1)
fn advect_vel(@builtin(global_invocation_id) gid: vec3<u32>) {
    let p = vec2<i32>(gid.xy);
    if (!inb(p)) { return; }
    let r = advect(p, cfg.params.y);
    textureStore(dst, p, vec4<f32>(r.xy, 0.0, 1.0));
}

@compute @workgroup_size(8, 8, 1)
fn advect_dye(@builtin(global_invocation_id) gid: vec3<u32>) {
    let p = vec2<i32>(gid.xy);
    if (!inb(p)) { return; }
    let r = advect(p, cfg.params.z);
    textureStore(dst, p, vec4<f32>(r.rgb, 1.0));
}

// --- force / dye injection ------------------------------------------------
@compute @workgroup_size(8, 8, 1)
fn splat_vel(@builtin(global_invocation_id) gid: vec3<u32>) {
    let p = vec2<i32>(gid.xy);
    if (!inb(p)) { return; }
    let pos = vec2<f32>(p) + 0.5;
    var v = loadA(p).xy;                    // current velocity is srcA

    let radius = cfg.params2.x;
    let fscale = cfg.params2.y;

    // cursor push: force along cursor travel, weighted by a gaussian footprint
    let speed = length(cfg.mouse_vel);
    let g = gaussian(pos - cfg.mouse, radius) * (0.4 + cfg.dye_color.a);
    v += cfg.mouse_vel * fscale * g * smoothstep(0.0, 1.5, speed);

    // ambient emitters: gentle curl so it breathes on its own
    for (var i = 0; i < 2; i = i + 1) {
        let e = emitter(i);
        let d = pos - e;
        let ge = gaussian(d, radius * 1.3);
        let curl = vec2<f32>(-d.y, d.x) / max(length(d), 1.0);
        v += curl * fscale * 0.12 * ge;
    }
    textureStore(dst, p, vec4<f32>(v, 0.0, 1.0));
}

@compute @workgroup_size(8, 8, 1)
fn splat_dye(@builtin(global_invocation_id) gid: vec3<u32>) {
    let p = vec2<i32>(gid.xy);
    if (!inb(p)) { return; }
    let pos = vec2<f32>(p) + 0.5;
    var c = loadA(p).rgb;                   // current dye is srcA

    let radius = cfg.params2.x;
    let speed = length(cfg.mouse_vel);

    // cursor dye: the configured colour, only where the cursor actually moves
    let g = gaussian(pos - cfg.mouse, radius) * (0.4 + cfg.dye_color.a);
    c += cfg.dye_color.rgb * g * smoothstep(0.0, 1.0, speed) * 0.8;

    // ambient emitters drop slowly-cycling palette colour
    for (var i = 0; i < 2; i = i + 1) {
        let e = emitter(i);
        let ge = gaussian(pos - e, radius * 1.1);
        let hue = fract(cfg.params.w * 0.05 + f32(i) * 0.5);
        c += ramp(hue) * ge * 0.12;
    }
    textureStore(dst, p, vec4<f32>(min(c, vec3<f32>(4.0)), 1.0));
}

// --- projection (make velocity divergence-free) ---------------------------
@compute @workgroup_size(8, 8, 1)
fn divergence(@builtin(global_invocation_id) gid: vec3<u32>) {
    let p = vec2<i32>(gid.xy);
    if (!inb(p)) { return; }
    let l = loadA(p - vec2<i32>(1, 0)).x;
    let r = loadA(p + vec2<i32>(1, 0)).x;
    let b = loadA(p - vec2<i32>(0, 1)).y;
    let t = loadA(p + vec2<i32>(0, 1)).y;
    let div = 0.5 * ((r - l) + (t - b));
    textureStore(dst, p, vec4<f32>(div, 0.0, 0.0, 1.0));
}

// srcA = pressure (previous iterate), srcB = divergence
@compute @workgroup_size(8, 8, 1)
fn jacobi(@builtin(global_invocation_id) gid: vec3<u32>) {
    let p = vec2<i32>(gid.xy);
    if (!inb(p)) { return; }
    let l = loadA(p - vec2<i32>(1, 0)).x;
    let r = loadA(p + vec2<i32>(1, 0)).x;
    let b = loadA(p - vec2<i32>(0, 1)).x;
    let t = loadA(p + vec2<i32>(0, 1)).x;
    let div = loadB(p).x;
    let pn = (l + r + b + t - div) * 0.25;
    textureStore(dst, p, vec4<f32>(pn, 0.0, 0.0, 1.0));
}

// srcA = velocity, srcB = pressure
@compute @workgroup_size(8, 8, 1)
fn gradient_subtract(@builtin(global_invocation_id) gid: vec3<u32>) {
    let p = vec2<i32>(gid.xy);
    if (!inb(p)) { return; }
    let l = loadB(p - vec2<i32>(1, 0)).x;
    let r = loadB(p + vec2<i32>(1, 0)).x;
    let b = loadB(p - vec2<i32>(0, 1)).x;
    let t = loadB(p + vec2<i32>(0, 1)).x;
    var v = loadA(p).xy;
    v -= 0.5 * vec2<f32>(r - l, t - b);
    textureStore(dst, p, vec4<f32>(v, 0.0, 1.0));
}

// straight copy srcA -> dst (frame-boundary persistence without wgpu copy APIs)
@compute @workgroup_size(8, 8, 1)
fn copy(@builtin(global_invocation_id) gid: vec3<u32>) {
    let p = vec2<i32>(gid.xy);
    if (!inb(p)) { return; }
    textureStore(dst, p, loadA(p));
}

// --- present: dye (srcA) + velocity (srcB) -> styled colour ---------------
@compute @workgroup_size(8, 8, 1)
fn render(@builtin(global_invocation_id) gid: vec3<u32>) {
    let p = vec2<i32>(gid.xy);
    if (!inb(p)) { return; }
    let dye = loadA(p).rgb;
    let vel = loadB(p).xy;
    let dark = cfg.params2.z;
    let style = i32(cfg.params2.w + 0.5);

    // dark -> deep palette base, light -> bright wash
    let bg = mix(cfg.palette0.rgb * 2.4 + 0.62, cfg.palette0.rgb, dark);
    let density = clamp(max(max(dye.r, dye.g), dye.b), 0.0, 1.0);

    // surface normal from the dye "height" gradient (used by mercury + water)
    let dl = densv(p - vec2<i32>(1, 0));
    let dr = densv(p + vec2<i32>(1, 0));
    let db = densv(p - vec2<i32>(0, 1));
    let dt = densv(p + vec2<i32>(0, 1));
    let grad = vec2<f32>(dr - dl, dt - db);

    var col: vec3<f32>;
    if (style == 1) {
        // mercury: full-bodied metallic blobs, Blinn-Phong off the height normal
        let n = normalize(vec3<f32>(-grad, 0.16));
        let L = normalize(vec3<f32>(0.45, -0.55, 0.75));
        let H = normalize(L + vec3<f32>(0.0, 0.0, 1.0));
        let diff = clamp(dot(n, L), 0.0, 1.0);
        let spec = pow(clamp(dot(n, H), 0.0, 1.0), 48.0);
        let fres = pow(1.0 - clamp(n.z, 0.0, 1.0), 3.0);
        let m = smoothstep(0.12, 0.4, density);
        let metal = vec3<f32>(0.5, 0.52, 0.58) * (0.22 + 0.78 * diff) + spec * 1.5 + fres * 0.45;
        col = mix(bg, metal, m);
    } else if (style == 2) {
        // water: depth-tinted pools, specular + caustic glints at the ripple edges
        let n = normalize(vec3<f32>(-grad * 2.0, 1.0));
        let L = normalize(vec3<f32>(0.4, -0.5, 0.8));
        let depth = smoothstep(0.0, 0.7, density);
        let deep = mix(cfg.palette2.rgb, cfg.palette1.rgb * 0.35, depth);
        let caustic = pow(clamp(length(grad) * 3.0, 0.0, 1.0), 1.5); // bright where the surface bends
        let spec = pow(clamp(dot(n, L), 0.0, 1.0), 24.0);
        col = mix(bg, deep, depth * 0.85) + caustic * 0.4 + spec * 0.5;
    } else {
        // ink (default): dye glows over the backdrop, Reinhard-tonemapped
        let ink = dye / (1.0 + dye);
        col = bg + ink * (0.9 + 0.6 * dark);
    }
    textureStore(dst, p, vec4<f32>(col, 1.0));
}
