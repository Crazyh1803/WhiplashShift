// Whiplash Shift - solo prototype. Glue: fixed-step sim, lap logic, gates,
// collisions, and a scripted-control hook the headless tests drive.

import { T, buildTuningPanel } from './tuning.js';
import { SID, SURFACES, preferredEnd } from './surfaces.js';
import { buildTrack } from './track.js';
import { createVehicle, stepVehicle, swapEnds, fireBoost, forwardVec } from './vehicle.js';
import { createInput } from './input.js';
import { createTouch, shouldUseTouch } from './touch.js';
import { createAudio } from './audio.js';
import { createCopilot, stepCopilot, noteSwap, noteGate, say } from './ai.js';
import { createRivals, rivalControl } from './rivals.js';
import { createOrdnance, stepOrdnance, sampleHazard, puff } from './weapons.js';
import { createRenderer } from './render.js';
import { drawHud } from './hud.js';

const DT = 1 / 120;
const TOTAL_LAPS = 3;

const canvas = document.getElementById('game');
const track = buildTrack();
const renderer = createRenderer(canvas, track);
const input = createInput(window);
const touch = shouldUseTouch() ? createTouch(document.body) : null;
if (touch) {
  canvas.style.touchAction = 'none';
  // the standfirst is a desktop nicety; on a phone it just sits over the track
  const brand = document.getElementById('brand');
  if (brand) brand.style.display = 'none';
}

// What the sim actually reads: keyboard and touch merged, so both work at once.
const liveControl = { throttle: 0, brake: 0, steer: 0, handbrake: false };
function mergeControls() {
  const k = input.state;
  if (!touch) {
    liveControl.throttle = k.throttle; liveControl.brake = k.brake;
    liveControl.steer = k.steer; liveControl.handbrake = k.handbrake;
    return;
  }
  const t = touch.state;
  liveControl.throttle = Math.max(k.throttle, t.throttle);
  liveControl.brake = Math.max(k.brake, t.brake);
  liveControl.steer = Math.max(-1, Math.min(1, k.steer + t.steer));
  liveControl.handbrake = k.handbrake || t.handbrake;
}
const tapped = (name) => input.tapped(name) || (touch ? touch.tapped(name) : false);
const audio = createAudio();
const ordnance = createOrdnance();
const copilot = createCopilot();

const gateByIdx = new Map(track.gates.map((g) => [g.idx, g]));

const player = createVehicle(track.start.x, track.start.y, track.start.ang, { name: 'YOU' });
let rivals = createRivals(track);
const all = () => [player, ...rivals];

const world = {
  sampleSurface(x, y) {
    const hz = sampleHazard(ordnance, x, y);
    return hz >= 0 ? hz : track.sampleSurface(x, y);
  },
};

const timing = { lap: 0, total: TOTAL_LAPS, lapTime: 0, best: null, laps: [] };
const game = {
  paused: false, showHelp: true, finished: false, started: false,
  scripted: null, autopilot: false, lastCheckpoint: 0, sinceLap: 0, position: 1,
};

// ---------------------------------------------------------------- lap/gates
function advance(v, onIndex) {
  const n = track.pts.length;
  const near = track.nearestIndex(v.x, v.y, v.trackIdx);
  let d = near.idx - v.trackIdx;
  if (d > n / 2) d -= n;
  if (d < -n / 2) d += n;
  if (d > 0 && d < 40) {
    for (let k = 1; k <= d; k++) onIndex((v.trackIdx + k) % n, d);
  }
  v.trackIdx = near.idx;
  v.offLine = near.dist;
  return d;
}

function onPlayerIndex(i) {
  game.sinceLap++;
  const g = gateByIdx.get(i);
  if (g) evaluateGate(g);
  const cp = track.checkpoints.find((c) => c.idx === i);
  if (cp) game.lastCheckpoint = track.checkpoints.indexOf(cp);
  if (i === 0 && game.sinceLap > track.pts.length * 0.6) crossLine();
}

function crossLine() {
  game.sinceLap = 0;
  if (!game.started) { game.started = true; timing.lapTime = 0; return; }
  timing.laps.push(timing.lapTime);
  if (timing.best == null || timing.lapTime < timing.best) timing.best = timing.lapTime;
  timing.lap++;
  say(copilot, `LAP ${timing.lap} — ${timing.lapTime.toFixed(2)}s`, 'good');
  audio.reward();
  timing.lapTime = 0;
  if (timing.lap >= timing.total) game.finished = true;
}

function evaluateGate(g) {
  if (player.activeEnd !== g.forcedEnd) {
    swapEnds(player, 'gate');
    player.powerCut = 0.45;
    player.damage = Math.min(T.damage.max, player.damage + T.damage.gateMiss);
    renderer.cam.shake = Math.min(1, renderer.cam.shake + 0.55);
    puff(ordnance, player.x, player.y, 14, '120,140,160', 14, 0.5, 2.2);
    noteGate(copilot, player, g, true, audio);
  } else {
    noteGate(copilot, player, g, false, audio);
  }
}

/** Rivals that end up in the scenery get put back on the ribbon, facing forward,
 *  keeping whatever speed they had left. A prototype demo should not stall
 *  because one AI car understeered into a field. */
function rescue(v, dt) {
  const width = track.pts[v.trackIdx].w;
  if ((v.offLine || 0) > width * 2.2) v.lost = (v.lost || 0) + dt;
  else v.lost = 0;
  if ((v.lost || 0) < 2.5) return;
  const p = track.pts[v.trackIdx];
  v.lost = 0;
  v.activeEnd = preferredEnd(p.s);
  v.x = p.x; v.y = p.y;
  v.ang = p.ang + (v.activeEnd === 'B' ? Math.PI : 0);
  const keep = Math.min(v.speed, 18);
  v.vx = Math.cos(p.ang) * keep;
  v.vy = Math.sin(p.ang) * keep;
  v.av = 0; v.engage = 1; v.cooldown = 0;
}

// ---------------------------------------------------------------- collisions
function collide(a, b) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const d = Math.hypot(dx, dy);
  const min = 3.9;
  if (d > min || d < 1e-4) return;
  const nx = dx / d, ny = dy / d;
  const push = (min - d) * 0.5;
  a.x -= nx * push; a.y -= ny * push;
  b.x += nx * push; b.y += ny * push;
  const rel = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
  if (rel > 0) return;
  const imp = -rel * 0.7;
  a.vx -= nx * imp; a.vy -= ny * imp;
  b.vx += nx * imp; b.vy += ny * imp;
  a.av += (Math.random() - 0.5) * 0.4;
  b.av += (Math.random() - 0.5) * 0.4;
  puff(ordnance, (a.x + b.x) / 2, (a.y + b.y) / 2, 5, '220,220,230', 9, 0.3, 1.6);
  renderer.cam.shake = Math.min(1, renderer.cam.shake + 0.25);
}

// ---------------------------------------------------------------- sim step
function simulate(dt) {
  if (game.autopilot) {
    // Same controller the rivals use, pointed at the player's chassis. Handy for
    // demos and for the headless lap check.
    player.ai = player.ai || { missileCd: 999, lane: 0, skill: T.rivals.skill };
    player.ai.missileCd = 999;
    game.scripted = rivalControl(player, track, rivals[0] || player, ordnance, dt);
  }
  const raw = game.scripted || liveControl;
  const ctrl = {
    throttle: raw.throttle, brake: raw.brake, steer: raw.steer,
    handbrake: !!raw.handbrake, assistSteer: copilot.assistSteer,
  };

  stepCopilot(copilot, player, { track, ordnance, rivals, audio, humanSteer: raw.steer }, dt);
  stepVehicle(player, ctrl, dt, world);

  for (const r of rivals) {
    const rc = rivalControl(r, track, player, ordnance, dt);
    stepVehicle(r, { ...rc, assistSteer: 0 }, dt, world);
    advance(r, () => {});
    rescue(r, dt);
  }

  advance(player, onPlayerIndex);

  const list = all();
  for (let i = 0; i < list.length; i++) {
    for (let j = i + 1; j < list.length; j++) collide(list[i], list[j]);
  }

  stepOrdnance(ordnance, dt, list, {
    onMissileHit(v) {
      v.damage = Math.min(T.damage.max, v.damage + T.damage.missile);
      v.av += (Math.random() - 0.5) * 2.4;
      if (v === player) { renderer.cam.shake = 1; audio.hit(); say(copilot, 'WE ARE HIT — CHASSIS DAMAGE', 'alert'); }
    },
    onIntercept() { say(copilot, 'MISSILE SPLASHED', 'good'); },
    onBulletHit(v) { v.damage = Math.min(T.damage.max, v.damage + 0.8); },
  });

  // limp mode instead of a hard fail, so a prototype run never dead-ends
  if (player.damage >= T.damage.max) {
    player.damage = 62;
    player.powerCut = 1.8;
    renderer.cam.shake = 1;
    say(copilot, 'DRIVETRAIN OVERLOAD — LIMP MODE', 'alert');
    puff(ordnance, player.x, player.y, 24, '255,140,70', 20, 0.7, 3.0);
  }

  // marks + spray
  for (const v of list) {
    for (const wl of v.wheels) {
      if (wl.slip > 0.78 && v.speed > 4) {
        renderer.addSkid(wl.wx, wl.wy, v.ang, (wl.slip - 0.78) * 1.6, wl.end === 'B');
      }
      if (wl.spin > 0.3 && v.speed > 2 && Math.random() < 0.35) {
        renderer.addSpray(wl.wx, wl.wy, wl.surface, ordnance);
      }
    }
  }
  if (player.damage > 55 && Math.random() < 0.25) {
    puff(ordnance, player.x, player.y, 1, '90,90,95', 3, 1.2, 2.2);
  }

  if (game.started && !game.finished) timing.lapTime += dt;

  // running order, by how far round the lap each car is
  game.position = 1 + rivals.filter((r) => r.trackIdx > player.trackIdx).length;
}

// ---------------------------------------------------------------- actions
function doSwap(reason = 'manual') {
  if (player.cooldown > 0) return false;
  swapEnds(player, reason);
  noteSwap(copilot, player, audio);
  audio.swapClunk();
  renderer.cam.shake = Math.min(1, renderer.cam.shake + 0.2);
  return true;
}

function recover() {
  if (game.finished) return restart();
  const cp = track.checkpoints[game.lastCheckpoint];
  const end = preferredEnd(track.pts[cp.idx].s);
  player.x = cp.x; player.y = cp.y;
  player.ang = cp.ang + (end === 'B' ? Math.PI : 0);
  player.vx = 0; player.vy = 0; player.av = 0;
  player.activeEnd = end;
  player.engage = 1; player.cooldown = 0; player.powerCut = 0;
  player.trackIdx = cp.idx;
  say(copilot, 'RECOVERED TO CHECKPOINT', 'info');
}

function restart() {
  player.x = track.start.x; player.y = track.start.y; player.ang = track.start.ang;
  player.vx = player.vy = player.av = 0;
  player.activeEnd = 'A'; player.damage = 0; player.boost = 0;
  player.trackIdx = 0; player.engage = 1; player.cooldown = 0; player.powerCut = 0;
  timing.lap = 0; timing.lapTime = 0; timing.laps.length = 0;
  game.finished = false; game.started = false; game.sinceLap = 0; game.lastCheckpoint = 0;
  ordnance.missiles.length = 0; ordnance.bullets.length = 0; ordnance.hazards.length = 0;
  rivals = createRivals(track);
  say(copilot, 'GRID RESET', 'info');
}

// ---------------------------------------------------------------- main loop
let acc = 0, last = performance.now();
let size = renderer.resize();
window.addEventListener('resize', () => { size = renderer.resize(); });

const tunePanel = document.getElementById('tuner');
buildTuningPanel(tunePanel);

window.addEventListener('keydown', (e) => {
  if (e.code === 'KeyM') audio.toggle();
}, { passive: true });

// First touch anywhere unlocks audio and clears the controls card.
window.addEventListener('pointerdown', () => {
  audio.start();
  game.showHelp = false;
}, { passive: true });

function frame(now) {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  input.update(dt);
  if (touch) touch.update(dt);
  mergeControls();

  if (tapped('help')) game.showHelp = !game.showHelp;
  if (tapped('pause')) game.paused = !game.paused;
  if (tapped('camera')) renderer.cam.mode = renderer.cam.mode === 'swing' ? 'snap' : 'swing';
  if (tapped('assist')) {
    copilot.enabled = !copilot.enabled;
    say(copilot, copilot.enabled ? 'COPILOT ACTIVE' : 'COPILOT STOOD DOWN', 'info');
  }
  if (tapped('tune')) tunePanel.classList.toggle('open');
  if (tapped('recover')) recover();
  if (tapped('swap')) { audio.start(); game.showHelp = false; doSwap(); }
  if (tapped('boost')) { if (fireBoost(player)) audio.reward(); }
  if (liveControl.throttle > 0.01 && !audio.ready) { audio.start(); game.showHelp = false; }
  if (touch) touch.setEnd(player.activeEnd, player.cooldown > 0);

  const running = !game.paused && !game.finished && !game.showHelp;
  if (running) {
    acc += dt;
    let guard = 0;
    while (acc >= DT && guard++ < 8) { simulate(DT); acc -= DT; }
  }

  renderer.updateCamera(player, dt);
  renderer.cam.shake = Math.max(renderer.cam.shake, ordnance.shakes);
  const { w, h } = renderer.draw({ player, rivals, ordnance, copilot, nextGate: nextGate() }, dt);

  const cfg = T[player.activeEnd];
  audio.update(
    Math.min(1, Math.abs(player.fwdSpeed) / Math.max(4, cfg.topSpeed)),
    Math.max(liveControl.throttle, player.boostTimer > 0 ? 1 : 0),
    Math.min(1, player.slip * 0.6 + player.spin * 0.8),
    player.activeEnd === 'B',
  );

  drawHud(renderer.ctx, w, h, {
    player, rivals, copilot, timing, track, renderer, audio, touch: !!touch,
    paused: game.paused, showHelp: game.showHelp, finished: game.finished,
    position: game.position, fieldSize: 1 + rivals.length,
  });

  requestAnimationFrame(frame);
}

function nextGate() {
  const n = track.pts.length;
  let best = null, bestD = Infinity;
  for (const g of track.gates) {
    let d = g.idx - player.trackIdx;
    if (d < 0) d += n;
    if (d < bestD) { bestD = d; best = g; }
  }
  return best;
}

requestAnimationFrame(frame);

// ---------------------------------------------------------------- test hook
window.__WS = {
  T, track, player, copilot, ordnance, renderer, timing, game, touch,
  get rivals() { return rivals; },
  setControl(c) { game.autopilot = false; game.scripted = { throttle: 0, brake: 0, steer: 0, handbrake: false, ...c }; },
  releaseControl() { game.autopilot = false; game.scripted = null; },
  autopilot(on = true) { game.autopilot = on; if (!on) game.scripted = null; },
  swap: doSwap,
  rawSwap: (r) => swapEnds(player, r || 'test'),
  recover, restart,
  place(x, y, ang, speed = 0, end = 'A') {
    player.x = x; player.y = y; player.ang = ang;
    player.vx = Math.cos(ang) * speed; player.vy = Math.sin(ang) * speed;
    player.av = 0; player.activeEnd = end; player.engage = 1;
    player.cooldown = 0; player.powerCut = 0; player.damage = 0;
    player.trackIdx = track.nearestIndex(x, y, 0).idx;
  },
  /** Deterministic stepping for the headless checks. */
  run(seconds) {
    const steps = Math.round(seconds / DT);
    for (let i = 0; i < steps; i++) simulate(DT);
    return this.sample();
  },
  sample() {
    return {
      x: player.x, y: player.y, ang: player.ang,
      vx: player.vx, vy: player.vy, av: player.av,
      speed: player.speed, fwdSpeed: player.fwdSpeed,
      end: player.activeEnd, surface: SURFACES[player.surfaceUnder].key,
      wrongEnd: player.wrongEnd, damage: player.damage, boost: player.boost,
      lap: timing.lap, lapTime: timing.lapTime, trackIdx: player.trackIdx,
      whiplash: player.lastWhiplash, lastSwap: player.lastSwap,
      copilot: { state: copilot.state, next: copilot.nextChange, callouts: copilot.callouts.map((c) => c.text) },
      finished: game.finished,
    };
  },
  surfaceAt: (x, y) => SURFACES[track.sampleSurface(x, y)].key,
  begin() { game.showHelp = false; game.paused = false; },
};
