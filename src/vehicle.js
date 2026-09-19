// The two-ended chassis: one rigid body, four wheels, two of which drive.
//
// The whole prototype exists to test one line, in swapEnds(): the active end
// changes and the body's linear and angular velocity are NOT touched. Everything
// else here is in service of making that moment readable and tunable.

import { T } from './tuning.js';
import { SURFACES, SID, endMod, preferredEnd } from './surfaces.js';

export const otherEnd = (e) => (e === 'A' ? 'B' : 'A');

export function createVehicle(x, y, ang, opts = {}) {
  const c = T.chassis;
  const v = {
    // rigid body state
    x, y, ang,
    vx: 0, vy: 0, av: 0,

    activeEnd: opts.activeEnd || 'A',
    steerAngle: 0,
    engage: 1,          // transmission ramp after a swap, 0..1
    cooldown: 0,
    powerCut: 0,        // seconds of forced zero drive (gate penalty)

    damage: 0,
    boost: 0,           // 0..1 charge
    boostTimer: 0,

    // whiplash scoring window
    pending: null,
    lastSwap: null,
    lastWhiplash: null,

    wheels: [
      { end: 'A', ox: +c.halfBase, oy: -c.halfTrack },
      { end: 'A', ox: +c.halfBase, oy: +c.halfTrack },
      { end: 'B', ox: -c.halfBase, oy: -c.halfTrack },
      { end: 'B', ox: -c.halfBase, oy: +c.halfTrack },
    ].map((w) => ({ ...w, wx: 0, wy: 0, slip: 0, spin: 0, surface: SID.TARMAC, steered: false })),

    isRival: !!opts.isRival,
    color: opts.color || '#e8eef5',
    name: opts.name || 'PLAYER',

    // read-only-ish telemetry the HUD and AI consume
    speed: 0, fwdSpeed: 0, surfaceUnder: SID.TARMAC, wrongEnd: false,
    trackIdx: 0, lap: 0, progress: 0,
  };
  return v;
}

export const cfgOf = (v) => T[v.activeEnd];
export const forwardSign = (v) => (v.activeEnd === 'A' ? 1 : -1);

export function forwardVec(v) {
  const s = forwardSign(v);
  return { x: Math.cos(v.ang) * s, y: Math.sin(v.ang) * s };
}

export function swapEnds(v, reason = 'manual') {
  const preSpeed = Math.hypot(v.vx, v.vy);
  const preAv = v.av;
  const preAng = v.ang;

  // ---- the thesis ----
  v.activeEnd = otherEnd(v.activeEnd);
  // vx, vy, av and ang are deliberately left alone. Inertia carries through.
  // --------------------

  v.engage = 0;
  v.cooldown = T.swap.cooldown;
  v.steerAngle *= 0.35;

  v.lastSwap = {
    reason,
    preSpeed, postSpeed: Math.hypot(v.vx, v.vy),
    preAv, postAv: v.av,
    preAng, postAng: v.ang,
    t: 0,
  };

  if (preSpeed >= T.swap.whiplashMinSpeed) {
    v.pending = { t: 0, entrySpeed: preSpeed, entryAng: preAng, entryDir: Math.atan2(v.vy, v.vx) };
  } else {
    v.pending = null;
  }
  return v.lastSwap;
}

function angDelta(a, b) {
  let d = a - b;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

// Smooth sign: avoids rolling-resistance and brake forces chattering around v=0.
const soft = (x, k = 2.5) => Math.tanh(x * k);

export function stepVehicle(v, ctrl, dt, world) {
  const c = T.chassis;
  const cfg = cfgOf(v);
  const fs = forwardSign(v);
  const mass = c.mass;
  const inertia = mass * (c.length * c.length + c.width * c.width) / 12;
  const baseLoad = (mass * 9.81) / 4;

  const cosA = Math.cos(v.ang), sinA = Math.sin(v.ang);

  // world -> body
  const lvx = v.vx * cosA + v.vy * sinA;
  const lvy = -v.vx * sinA + v.vy * cosA;
  v.speed = Math.hypot(v.vx, v.vy);
  v.fwdSpeed = lvx * fs;

  // --- timers ---
  if (v.cooldown > 0) v.cooldown = Math.max(0, v.cooldown - dt);
  if (v.powerCut > 0) v.powerCut = Math.max(0, v.powerCut - dt);
  v.engage = T.swap.engage > 0 ? Math.min(1, v.engage + dt / T.swap.engage) : 1;
  if (v.boostTimer > 0) v.boostTimer = Math.max(0, v.boostTimer - dt);
  if (v.lastSwap) v.lastSwap.t += dt;

  // --- steering ---
  const topRef = Math.max(1, cfg.topSpeed);
  const lock = cfg.maxSteer * (1 - cfg.steerFalloff * Math.min(1, v.speed / topRef));
  let steerCmd = ctrl.steer;
  if (ctrl.assistSteer) steerCmd = Math.max(-1, Math.min(1, steerCmd + ctrl.assistSteer));
  const target = steerCmd * lock;
  const rate = cfg.steerRate * dt;
  v.steerAngle += Math.max(-rate, Math.min(rate, target - v.steerAngle));
  const delta = v.steerAngle;
  const cd = Math.cos(delta), sd = Math.sin(delta);

  // --- drive command ---
  // Reverse: holding brake once the active end is no longer moving forward
  // drives backwards down the new vector. That is the Pure Reversal.
  // Reverse engages only from near-standstill. Holding brake while the chassis
  // is still carrying an inherited 70 km/h backwards has to mean BRAKE, or the
  // swap hands the driver a throttle that fires the wrong way.
  const reversing = ctrl.brake > 0.05 && ctrl.throttle < 0.05
    && v.fwdSpeed < 0.6 && v.speed < 2.5;
  let throttle = ctrl.throttle;
  let brake = ctrl.brake;
  if (reversing) { throttle = -ctrl.brake * 0.62; brake = 0; }

  // average the active pair's surface modifiers before working out drive
  let accelMod = 0, topMod = 0, n = 0;
  for (const w of v.wheels) {
    if (w.end !== v.activeEnd) continue;
    const em = endMod(w.end, w.surface);
    accelMod += em.accel; topMod += em.top; n++;
  }
  accelMod = n ? accelMod / n : 1;
  topMod = n ? topMod / n : 1;

  const topSpeed = cfg.topSpeed * topMod;
  // Taper against speed IN THE DIRECTION WE ARE DRIVING, not raw speed. This is
  // what lets End B pull full torque against the momentum it inherited from the
  // swap - the Pure Reversal depends on it.
  const driveDir = throttle >= 0 ? 1 : -1;
  const dirTop = Math.max(4, topSpeed * (driveDir > 0 ? 1 : 0.45));
  const taper = Math.max(0, Math.min(1, 1 - (v.fwdSpeed * driveDir) / dirTop));
  const gateOpen = v.powerCut > 0 ? 0 : v.engage;
  const drivePerWheel = (throttle * cfg.maxDrive * accelMod * taper * gateOpen) / 2;

  // The handbrake locks the pair TRAILING the velocity vector, not the inactive
  // pair. In normal driving those are the same thing. Straight after a high-speed
  // swap they are not: the newly active end is the one at the back, and locking
  // it is exactly what snaps the chassis round. That is the Vector Slide.
  const hbEnd = lvx >= 0 ? 'B' : 'A';

  let Fx = 0, Fy = 0, Tq = 0;
  let maxSlip = 0, maxSpin = 0;
  let activeSurface = SID.OFF;

  for (const w of v.wheels) {
    // wheel position in world, for the surface sample and for rendering
    w.wx = v.x + w.ox * cosA - w.oy * sinA;
    w.wy = v.y + w.ox * sinA + w.oy * cosA;
    w.surface = world.sampleSurface(w.wx, w.wy);
    const surf = SURFACES[w.surface];
    const em = endMod(w.end, w.surface);
    const steered = w.end === v.activeEnd;
    w.steered = steered;
    if (steered) activeSurface = w.surface;

    // wheel velocity in body frame: v + omega x r
    const wvx = lvx - v.av * w.oy;
    const wvy = lvy + v.av * w.ox;

    const d = steered ? delta : 0;
    const wc = steered ? cd : 1, ws = steered ? sd : 0;
    const lon = wvx * wc + wvy * ws;
    const lat = -wvx * ws + wvy * wc;

    // normal load, with End A's aero downforce
    let load = baseLoad;
    if (w.end === 'A' && cfg.downforce > 0 && v.activeEnd === 'A') {
      load *= 1 + cfg.downforce * Math.pow(Math.min(v.speed, 80) / 60, 2);
    }
    const hb = ctrl.handbrake && w.end === hbEnd;
    let mu = T[w.end].tireGrip * surf.grip * em.grip;
    if (hb) mu *= T.grip.handbrakeGrip;
    const maxF = mu * load;

    let fx = 0;
    // fs points the drive at the ACTIVE end's forward axis: +X body for End A,
    // -X body for End B. A locked wheel puts no power down.
    if (steered && !hb) fx += drivePerWheel * fs;
    const requested = Math.abs(fx);
    // Rolling/bogging resistance eases off at a crawl, so a car caught in the
    // bog on the wrong end is crippled rather than welded to the spot.
    const bog = 0.4 + 0.6 * Math.min(1, Math.abs(lon) / 8);
    fx -= surf.roll * load * soft(lon) * bog;
    fx -= brake * cfg.brake * 0.25 * soft(lon);
    if (hb) fx -= maxF * T.grip.handbrakeLock * soft(lon, 6);
    let fy = -maxF * Math.tanh(lat * T.grip.slipK);

    const mag = Math.hypot(fx, fy);
    if (mag > maxF && mag > 1e-6) {
      const k = maxF / mag;
      fx *= k; fy *= k;
      w.slip = 1;
    } else {
      w.slip = maxF > 1e-6 ? mag / maxF : 0;
    }
    // how much of the requested drive the surface refused to accept
    w.spin = requested > 1 ? Math.max(0, (requested - Math.abs(fx)) / requested) : 0;
    if (w.slip > maxSlip) maxSlip = w.slip;
    if (steered && w.spin > maxSpin) maxSpin = w.spin;

    // wheel frame -> body frame
    const bfx = fx * wc - fy * ws;
    const bfy = fx * ws + fy * wc;
    Fx += bfx; Fy += bfy;
    Tq += w.ox * bfy - w.oy * bfx;
  }

  // boost surges along the active end's forward vector
  if (v.boostTimer > 0) Fx += T.boost.force * fs;

  // aero
  Fx -= c.aeroDrag * v.speed * lvx;
  Fy -= c.aeroDrag * v.speed * lvy;

  // body -> world, integrate
  const ax = (Fx * cosA - Fy * sinA) / mass;
  const ay = (Fx * sinA + Fy * cosA) / mass;
  v.vx += ax * dt;
  v.vy += ay * dt;
  v.av += (Tq / inertia) * dt;
  v.av *= Math.exp(-c.yawDamp * dt);
  v.ang += v.av * dt;
  v.x += v.vx * dt;
  v.y += v.vy * dt;

  v.speed = Math.hypot(v.vx, v.vy);
  v.slip = maxSlip;
  v.spin = maxSpin;
  v.surfaceUnder = activeSurface;
  v.reversing = reversing;

  // --- wrong-end punishment ---
  v.wrongEnd = preferredEnd(activeSurface) !== v.activeEnd;
  const dmgRate = SURFACES[activeSurface].dmg;
  if (v.wrongEnd && dmgRate > 0 && v.speed > 11) {
    v.damage = Math.min(T.damage.max, v.damage + dmgRate * (T.damage.mismatchRate / 9) * dt);
  }

  // --- whiplash resolution ---
  if (v.pending) {
    v.pending.t += dt;
    const f = forwardVec(v);
    const velDir = v.speed > 3 ? { x: v.vx / v.speed, y: v.vy / v.speed } : null;
    const aligned = velDir ? f.x * velDir.x + f.y * velDir.y : -1;
    if (aligned > 0.55 && v.speed > v.pending.entrySpeed * 0.45) {
      const spun = Math.abs(angDelta(v.ang, v.pending.entryAng));
      v.lastWhiplash = {
        kind: spun > 2.1 ? 'VECTOR SLIDE' : 'PURE REVERSAL',
        retained: v.speed / v.pending.entrySpeed,
        time: v.pending.t,
        age: 0,
      };
      v.boost = Math.min(1, v.boost + T.swap.boostReward);
      v.pending = null;
    } else if (v.pending.t > T.swap.whiplashWindow) {
      v.pending = null;
    }
  }
  if (v.lastWhiplash) v.lastWhiplash.age += dt;

  return v;
}

export function fireBoost(v) {
  if (v.boost < 0.33 || v.boostTimer > 0) return false;
  v.boost = Math.max(0, v.boost - 0.33);
  v.boostTimer = T.boost.duration;
  return true;
}
