// Solo-mode AI copilot.
//
// Two jobs, per the GDD: read the track ahead and call the swap, and man the
// tailgun on the newly vacated end. The assist rule is structural rather than
// promised: assistSteer is only ever ADDED to the human's input, and is zeroed
// the moment the human steers against it, so there is nothing to hand back and
// no input lag on a swap.

import { T } from './tuning.js';
import { SURFACES, preferredEnd } from './surfaces.js';
import { fireBullet, dropHazard, sampleHazard } from './weapons.js';
import { forwardVec, otherEnd } from './vehicle.js';
import { SID } from './surfaces.js';

export const COPILOT_STATES = ['IDLE', 'WARN', 'SWAP PREP', 'SLIDE ASSIST', 'GUNNER'];

export function createCopilot() {
  return {
    state: 'IDLE',
    assistSteer: 0,
    assistTimer: 0,
    turretAng: 0,
    fireCd: 0,
    oilCd: 0,
    warnedIdx: -1,
    nextChange: null,   // { sid, dist, eta, end }
    target: null,
    targetKind: null,
    callouts: [],
    enabled: true,
  };
}

function angDelta(a, b) {
  let d = a - b;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

export function say(cp, text, level = 'info') {
  const last = cp.callouts[cp.callouts.length - 1];
  if (last && last.text === text && last.age < 2.5) return false;
  cp.callouts.push({ text, level, age: 0 });
  if (cp.callouts.length > 4) cp.callouts.shift();
  return true;
}

/** Walk the centreline forward and find the next surface that wants the other end. */
export function scanAhead(track, idx, activeEnd, metres) {
  const pts = track.pts;
  const n = pts.length;
  let i = idx, travelled = 0;
  while (travelled < metres) {
    travelled += pts[i].dist;
    i = (i + 1) % n;
    if (i === idx) break;
    if (preferredEnd(pts[i].s) !== activeEnd) {
      return { sid: pts[i].s, dist: travelled, end: preferredEnd(pts[i].s), idx: i };
    }
  }
  return null;
}

export function stepCopilot(cp, v, ctx, dt) {
  for (const c of cp.callouts) c.age += dt;
  while (cp.callouts.length && cp.callouts[0].age > 6) cp.callouts.shift();

  cp.fireCd = Math.max(0, cp.fireCd - dt);
  cp.oilCd = Math.max(0, cp.oilCd - dt);
  cp.assistTimer = Math.max(0, cp.assistTimer - dt);

  const { track, ordnance, rivals, audio } = ctx;
  const speed = Math.max(4, v.speed);
  let state = 'IDLE';

  // ---- 1. read the track ahead ----
  const horizon = Math.max(45, speed * T.ai.lookahead);
  const change = scanAhead(track, v.trackIdx, v.activeEnd, horizon);
  cp.nextChange = change ? { ...change, eta: change.dist / speed } : null;

  if (cp.nextChange) {
    const eta = cp.nextChange.eta;
    state = eta < 1.3 ? 'SWAP PREP' : 'WARN';
    if (cp.warnedIdx !== cp.nextChange.idx && eta < T.ai.lookahead) {
      const name = SURFACES[cp.nextChange.sid].name;
      const secs = Math.max(1, Math.round(eta));
      if (say(cp, `${name} IN ${secs} — PREP END ${cp.nextChange.end}`, 'warn')) audio?.warn();
      cp.warnedIdx = cp.nextChange.idx;
    }
  } else {
    cp.warnedIdx = -1;
  }

  // ---- 2. slide assist ----
  cp.assistSteer = 0;
  if (cp.enabled && cp.assistTimer > 0 && v.speed > 6) {
    const f = forwardVec(v);
    const velAng = Math.atan2(v.vy, v.vx);
    const fwdAng = Math.atan2(f.y, f.x);
    const err = angDelta(velAng, fwdAng);
    // Steer into the slide to bring the newly active end round to the vector.
    let assist = Math.max(-1, Math.min(1, err * 1.4)) * T.ai.assist;
    const human = ctx.humanSteer || 0;
    // Never fight the driver: if they are steering the other way, stand down.
    if (human !== 0 && Math.sign(human) !== Math.sign(assist)) assist = 0;
    cp.assistSteer = assist;
    if (assist !== 0) state = 'SLIDE ASSIST';
  }

  // ---- 3. tailgun on the inactive end ----
  const f = forwardVec(v);
  const rearAng = Math.atan2(-f.y, -f.x);
  const gun = {
    x: v.x + Math.cos(rearAng) * 1.7,
    y: v.y + Math.sin(rearAng) * 1.7,
  };

  let target = null, kind = null, bestScore = Infinity;
  if (cp.enabled) {
    // priority 1: incoming missiles aimed at us
    for (const m of ordnance.missiles) {
      if (m.owner === v) continue;
      const d = Math.hypot(m.x - v.x, m.y - v.y);
      if (d > T.ai.turretRange) continue;
      if (Math.abs(angDelta(Math.atan2(m.y - gun.y, m.x - gun.x), rearAng)) > T.ai.turretArc) continue;
      if (d < bestScore) { bestScore = d; target = m; kind = 'MISSILE'; }
    }
    // priority 2: rivals in the rear arc
    if (!target) {
      for (const r of rivals) {
        const d = Math.hypot(r.x - v.x, r.y - v.y);
        if (d > T.ai.turretRange) continue;
        if (Math.abs(angDelta(Math.atan2(r.y - gun.y, r.x - gun.x), rearAng)) > T.ai.turretArc) continue;
        if (d < bestScore) { bestScore = d; target = r; kind = 'RIVAL'; }
      }
    }
  }
  cp.target = target;
  cp.targetKind = kind;

  // traverse: finite rate, so the turret cannot snap onto a target
  const want = target ? Math.atan2(target.y - gun.y, target.x - gun.x) : rearAng;
  const dTraverse = angDelta(want, cp.turretAng);
  const maxT = T.ai.turretTraverse * dt;
  cp.turretAng += Math.max(-maxT, Math.min(maxT, dTraverse));
  // keep the barrel inside the 180 degree arc off the inactive end
  const offRear = angDelta(cp.turretAng, rearAng);
  if (Math.abs(offRear) > T.ai.turretArc) {
    cp.turretAng = rearAng + Math.sign(offRear) * T.ai.turretArc;
  }

  if (target && cp.fireCd === 0 && Math.abs(angDelta(cp.turretAng, want)) < 0.14) {
    fireBullet(ordnance, gun.x, gun.y, cp.turretAng, v);
    cp.fireCd = T.ai.fireInterval;
    audio?.shot();
    state = state === 'IDLE' ? 'GUNNER' : state;
    if (kind === 'MISSILE') say(cp, 'MISSILE INBOUND — ENGAGING', 'alert');
  }

  // ---- 4. counter-hazards ----
  if (cp.enabled && cp.oilCd === 0) {
    const chase = rivals.find((r) => {
      const d = Math.hypot(r.x - v.x, r.y - v.y);
      if (d > 34) return false;
      return Math.abs(angDelta(Math.atan2(r.y - v.y, r.x - v.x), rearAng)) < 0.9;
    });
    const narrow = track.pts[v.trackIdx].w <= 23;
    if (chase && narrow && sampleHazard(ordnance, v.x, v.y) === -1) {
      dropHazard(ordnance, gun.x, gun.y, SID.OIL, 7, 13);
      cp.oilCd = T.ai.oilCooldown;
      say(cp, 'OIL DOWN ON THE CHOKEPOINT', 'info');
      audio?.callout();
    }
  }

  cp.state = state;
  return cp;
}

/** Called by main on every swap so the copilot can brace the slide. */
export function noteSwap(cp, v, audio) {
  if (v.speed > T.swap.whiplashMinSpeed) {
    cp.assistTimer = 0.75;
    say(cp, `HAND-OFF — END ${v.activeEnd} HAS IT, CATCH THE SLIDE`, 'alert');
  } else {
    say(cp, `END ${v.activeEnd} ENGAGED`, 'info');
  }
  audio?.callout();
}

export function noteGate(cp, v, gate, forced, audio) {
  if (forced) {
    say(cp, `INDUCTION STRIP CUT POWER — FORCED TO END ${gate.forcedEnd}`, 'alert');
    audio?.hit();
  } else {
    say(cp, `GATE CLEAN — ${gate.label}`, 'good');
  }
}

export { otherEnd };
