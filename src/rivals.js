// Rival racers. Same chassis, same physics, same swap rule - they just get
// their control inputs from a pure-pursuit controller instead of a keyboard.

import { T } from './tuning.js';
import { SURFACES, preferredEnd } from './surfaces.js';
import { createVehicle, swapEnds, forwardVec } from './vehicle.js';
import { fireMissile } from './weapons.js';

function angDelta(a, b) {
  let d = a - b;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

export function createRivals(track, count = T.rivals.count) {
  const out = [];
  const palette = ['#d94f6a', '#8fd94f'];
  for (let i = 0; i < count; i++) {
    const idx = (track.pts.length - 18 * (i + 1)) % track.pts.length;
    const p = track.pts[idx];
    const off = (i % 2 ? 1 : -1) * 5;
    const end = preferredEnd(p.s);
    // body angle is flipped for End B so the ACTIVE end points down the track
    const v = createVehicle(
      p.x - Math.sin(p.ang) * off,
      p.y + Math.cos(p.ang) * off,
      p.ang + (end === 'B' ? Math.PI : 0),
      { isRival: true, color: palette[i % palette.length], name: `RIVAL ${i + 1}`, activeEnd: end },
    );
    v.trackIdx = idx;
    v.ai = { missileCd: 3 + i * 2.5, lane: off, skill: T.rivals.skill - i * 0.05 };
    out.push(v);
  }
  return out;
}

/** Look ahead along the centreline and work out a safe corner speed. */
function cornerLimit(track, idx, aheadM, gripRef) {
  const pts = track.pts;
  const n = pts.length;
  let i = idx, travelled = 0;
  let worst = Infinity;
  let a0 = pts[idx].ang;
  let segStart = 0;
  while (travelled < aheadM) {
    travelled += pts[i].dist;
    i = (i + 1) % n;
    if (i === idx) break;
    const span = travelled - segStart;
    if (span > 14) {
      const turn = Math.abs(angDelta(pts[i].ang, a0));
      const curv = turn / Math.max(1, span);
      if (curv > 1e-4) {
        const r = 1 / curv;
        const surf = SURFACES[pts[i].s];
        const vmax = Math.sqrt(gripRef * surf.grip * 9.81 * r);
        if (vmax < worst) worst = vmax;
      }
      a0 = pts[i].ang;
      segStart = travelled;
    }
  }
  return worst;
}

export function rivalControl(v, track, player, ordnance, dt) {
  const pts = track.pts;
  const n = pts.length;
  const cfg = T[v.activeEnd];
  const skill = v.ai.skill;

  // pure pursuit toward a point down the centreline, offset to its lane
  const aheadM = 11 + v.speed * 0.85;
  let i = v.trackIdx, travelled = 0;
  while (travelled < aheadM) {
    travelled += pts[i].dist;
    i = (i + 1) % n;
    if (i === v.trackIdx) break;
  }
  const tp = pts[i];
  const tx = tp.x - Math.sin(tp.ang) * v.ai.lane;
  const ty = tp.y + Math.cos(tp.ang) * v.ai.lane;

  const f = forwardVec(v);
  const fwdAng = Math.atan2(f.y, f.x);
  const want = Math.atan2(ty - v.y, tx - v.x);
  const err = angDelta(want, fwdAng);
  const steer = Math.max(-1, Math.min(1, err * 2.4));

  // swap when the surface ahead wants the other end
  let sIdx = v.trackIdx, s = 0;
  while (s < 28) { s += pts[sIdx].dist; sIdx = (sIdx + 1) % n; }
  const wantEnd = preferredEnd(pts[sIdx].s);
  if (wantEnd !== v.activeEnd && v.cooldown === 0) swapEnds(v, 'ai');

  // speed control: look far enough ahead to actually shed the speed. At 45 m/s
  // a 55 m horizon is barely a second, which is how the AI used to arrive at the
  // mud sweeper at 150 km/h and leave the circuit entirely.
  const horizon = 40 + v.speed * 2.8;
  const limit = Math.min(
    cfg.topSpeed * skill,
    cornerLimit(track, v.trackIdx, horizon, T[v.activeEnd].tireGrip) * skill,
  );
  let throttle = 0, brake = 0;
  if (v.speed < limit - 1.5) throttle = 1;
  else if (v.speed > limit + 1.0) brake = Math.min(1, (v.speed - limit) / 5);
  else throttle = 0.45;

  // off the line: stop chasing a distant lookahead point and aim at the track
  const near = track.nearestIndex(v.x, v.y, v.trackIdx);
  const width = pts[near.idx].w;
  let steerOut = steer;
  if (near.dist > width * 0.75) {
    const home = pts[near.idx];
    const back = Math.atan2(home.y - v.y, home.x - v.x);
    const blend = Math.min(1, (near.dist - width * 0.75) / width);
    const rescue = Math.max(-1, Math.min(1, angDelta(back, fwdAng) * 2.4));
    steerOut = steer * (1 - blend) + rescue * blend;
    throttle = Math.min(throttle, 0.45);
    brake = Math.max(brake, v.speed > limit ? 0.6 : 0);
  }

  // ordnance
  v.ai.missileCd -= dt;
  const dPlayer = Math.hypot(player.x - v.x, player.y - v.y);
  if (v.ai.missileCd <= 0 && dPlayer < 110 && dPlayer > 14) {
    fireMissile(ordnance, v, player);
    v.ai.missileCd = T.rivals.missileInterval * (0.8 + Math.random() * 0.6);
  }

  return {
    throttle, brake, steer: steerOut,
    handbrake: Math.abs(err) > 0.9 && v.speed > 20 && v.activeEnd === 'B',
  };
}
