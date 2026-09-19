// Headless checks for the Whiplash Shift prototype.
//
//   node tests/headless.mjs [--url http://127.0.0.1:8137/index.html] [--shots]
//
// Uses the pre-installed Chromium (PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers).
// The page exposes window.__WS, which steps the same fixed-timestep sim the
// game loop runs, so these are deterministic and do not depend on frame rate.

import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  const globalRoot = execSync('npm root -g').toString().trim();
  ({ chromium } = require(path.join(globalRoot, 'playwright')));
}

const args = process.argv.slice(2);
const flag = (n, d) => {
  const i = args.indexOf(n);
  return i >= 0 ? args[i + 1] : d;
};
const PORT = Number(flag('--port', 8137));
const URL = flag('--url', `http://127.0.0.1:${PORT}/index.html`);
const SHOTS = args.includes('--shots');
const SHOT_DIR = flag('--shot-dir', 'shots');
const ROOT = path.resolve(path.dirname(new URL_(import.meta.url).pathname), '..');
function URL_(u) { return new globalThis.URL(u); }

let pass = 0, fail = 0;
const results = [];
function check(name, ok, detail = '') {
  if (ok) { pass++; console.log(`  ✓ ${name}${detail ? '  ' + detail : ''}`); }
  else { fail++; console.log(`  ✗ ${name}${detail ? '  ' + detail : ''}`); }
  results.push({ name, ok, detail });
}
const near = (a, b, eps) => Math.abs(a - b) <= eps;

let server;
async function ensureServer() {
  try {
    const r = await fetch(URL);
    if (r.ok) return false;
  } catch { /* not running */ }
  server = spawn('python3', ['-m', 'http.server', String(PORT)], { cwd: ROOT, stdio: 'ignore' });
  for (let i = 0; i < 40; i++) {
    await new Promise((r) => setTimeout(r, 150));
    try { if ((await fetch(URL)).ok) return true; } catch { /* keep waiting */ }
  }
  throw new Error(`could not serve ${URL}`);
}

const run = async () => {
  const spawned = await ensureServer();
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });

  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForFunction(() => !!window.__WS, null, { timeout: 15000 });
  await page.evaluate(() => window.__WS.begin());
  if (SHOTS) mkdirSync(path.resolve(ROOT, SHOT_DIR), { recursive: true });

  console.log('\nboot');
  check('page loads with no errors', errors.length === 0, errors.slice(0, 2).join(' | '));

  const geo = await page.evaluate(() => {
    const t = window.__WS.track;
    return {
      points: t.pts.length,
      length: t.length,
      gates: t.gates.map((g) => g.forcedEnd),
      checkpoints: t.checkpoints.length,
      startSurface: window.__WS.surfaceAt(t.start.x, t.start.y),
      mudSurface: window.__WS.surfaceAt(830, 300),
      iceSurface: window.__WS.surfaceAt(500, 660),
      offSurface: window.__WS.surfaceAt(150, 600),
    };
  });
  check('track baked as a closed circuit', geo.points > 400 && geo.length > 1200,
    `${geo.points} nodes, ${geo.length.toFixed(0)} m`);
  check('two induction gates, one per spec', geo.gates.length === 2 && new Set(geo.gates).size === 2,
    geo.gates.join('/'));
  check('surface map reads back correctly',
    geo.startSurface === 'tarmac' && geo.mudSurface === 'mud' && geo.iceSurface === 'ice' && geo.offSurface === 'off',
    `${geo.startSurface}/${geo.mudSurface}/${geo.iceSurface}/${geo.offSurface}`);

  console.log('\nthe thesis: a swap must not touch the body state');
  const swap = await page.evaluate(() => {
    const W = window.__WS;
    W.place(300, 180, 0, 38, 'A');
    W.setControl({ throttle: 1 });
    W.run(1.4);
    const before = W.sample();
    const rec = W.rawSwap('test');
    const after = W.sample();
    return { before, after, rec };
  });
  check('linear velocity preserved exactly',
    swap.rec.preSpeed === swap.rec.postSpeed && swap.before.vx === swap.after.vx && swap.before.vy === swap.after.vy,
    `${swap.rec.preSpeed.toFixed(6)} -> ${swap.rec.postSpeed.toFixed(6)} m/s`);
  check('angular velocity preserved exactly', swap.rec.preAv === swap.rec.postAv,
    `${swap.rec.preAv.toFixed(6)} rad/s`);
  check('heading untouched (the body does not rotate on a swap)',
    swap.rec.preAng === swap.rec.postAng);
  check('active end actually changed', swap.before.end !== swap.after.end,
    `${swap.before.end} -> ${swap.after.end}`);

  console.log('\ndrivetrain asymmetry');
  const perf = await page.evaluate(() => {
    const W = window.__WS;
    const top = (end, x, y, ang, secs) => {
      W.place(x, y, ang, 0, end);
      W.setControl({ throttle: 1 });
      return W.run(secs).speed;
    };
    const accel = (end, x, y, ang) => {
      W.place(x, y, ang, 0, end);
      W.setControl({ throttle: 1 });
      return W.run(2.0).speed;
    };
    // body angle is flipped for End B runs so the active end faces down the road
    return {
      aTarmacTop: top('A', 300, 180, 0, 12),
      bTarmacTop: top('B', 300, 180, Math.PI, 12),
      aTarmacAccel: accel('A', 300, 180, 0),
      aMudAccel: accel('A', 830, 300, Math.PI / 2),
      bMudAccel: accel('B', 830, 300, -Math.PI / 2),
    };
  });
  check('End A out-tops End B on tarmac by >35%',
    perf.aTarmacTop > perf.bTarmacTop * 1.35,
    `${(perf.aTarmacTop * 3.6).toFixed(0)} vs ${(perf.bTarmacTop * 3.6).toFixed(0)} km/h`);
  check('End A loses >=60% of its acceleration in mud',
    perf.aMudAccel < perf.aTarmacAccel * 0.4,
    `${perf.aTarmacAccel.toFixed(1)} -> ${perf.aMudAccel.toFixed(1)} m/s after 2 s`);
  check('End B out-accelerates End A in mud by >2x',
    perf.bMudAccel > perf.aMudAccel * 2,
    `${perf.bMudAccel.toFixed(1)} vs ${perf.aMudAccel.toFixed(1)} m/s`);

  console.log('\nwhiplash resolutions');
  const slide = await page.evaluate(() => {
    const W = window.__WS;
    W.place(300, 180, 0, 40, 'A');
    const entry = W.sample();
    W.rawSwap('test');
    W.setControl({ steer: 1, handbrake: true, brake: 0.25 });
    let best = 0, sample = null;
    for (let i = 0; i < 90; i++) {
      const s = W.run(0.05);
      let d = Math.abs(s.ang - entry.ang) % (Math.PI * 2);
      if (d > Math.PI) d = Math.PI * 2 - d;
      if (d > best) { best = d; sample = s; }
      if (s.whiplash && s.whiplash.age < 0.2) return { deg: d * 180 / Math.PI, s, entry, tagged: s.whiplash };
    }
    return { deg: best * 180 / Math.PI, s: sample, entry, tagged: sample && sample.whiplash };
  });
  check('handbrake + swap rotates the chassis past 120 deg',
    slide.deg > 120, `${slide.deg.toFixed(0)} deg`);
  check('the slide is scored as a whiplash and retains momentum',
    !!slide.tagged && slide.tagged.retained > 0.4,
    slide.tagged ? `${slide.tagged.kind}, ${(slide.tagged.retained * 100).toFixed(0)}% retained` : 'not scored');

  const reversal = await page.evaluate(() => {
    const W = window.__WS;
    // Roll west into the hairpin on End A, swap, then kill the inherited vector
    // and drive End B out the opposite way WITHOUT rotating the chassis.
    W.place(430, 660, Math.PI, 20, 'A');
    const entry = W.sample();
    W.rawSwap('test');
    W.setControl({ brake: 1 });          // scrub the momentum we inherited
    W.run(2.0);
    W.setControl({ throttle: 1 });       // End B pulls away down the new vector
    const out = W.run(4.0);
    let spun = Math.abs(out.ang - entry.ang) % (Math.PI * 2);
    if (spun > Math.PI) spun = Math.PI * 2 - spun;
    // is the car now travelling along End B's forward axis?
    const fx = Math.cos(out.ang) * -1, fy = Math.sin(out.ang) * -1;
    const sp = Math.hypot(out.vx, out.vy) || 1;
    const align = (out.vx / sp) * fx + (out.vy / sp) * fy;
    return { entry, out, spunDeg: spun * 180 / Math.PI, align };
  });
  check('End B ends up driving down the opposite vector',
    reversal.out.fwdSpeed > 2 && reversal.align > 0.5,
    `${reversal.out.fwdSpeed.toFixed(1)} m/s, alignment ${reversal.align.toFixed(2)}`);
  check('chassis stays broadly un-rotated (pure reversal, not a spin)',
    reversal.spunDeg < 100, `${reversal.spunDeg.toFixed(0)} deg of rotation`);

  console.log('\ncopilot');
  const callouts = await page.evaluate(() => {
    const W = window.__WS;
    W.place(560, 180, 0, 44, 'A');   // tarmac, closing on the rumble strip + mud gate
    W.setControl({ throttle: 1 });
    const seen = [];
    for (let i = 0; i < 40; i++) {
      const s = W.run(0.1);
      for (const c of s.copilot.callouts) if (!seen.includes(c)) seen.push(c);
      if (s.end === 'B') break;
    }
    return { seen, sample: W.sample() };
  });
  check('copilot calls the surface change before it arrives',
    callouts.seen.some((c) => /PREP END B/.test(c)), callouts.seen.find((c) => /PREP END/.test(c)) || '');
  check('the induction gate force-swaps a car on the wrong end',
    callouts.sample.end === 'B' || callouts.seen.some((c) => /FORCED TO END B/.test(c)),
    callouts.seen.find((c) => /FORCED/.test(c)) || `end=${callouts.sample.end}`);

  console.log('\nfull lap');
  if (SHOTS) {
    await page.evaluate(() => { window.__WS.restart(); window.__WS.autopilot(true); window.__WS.run(6); });
    await page.waitForTimeout(1100);
    await page.screenshot({ path: path.join(path.resolve(ROOT, SHOT_DIR), '01-start-tarmac.png') });
    await page.evaluate(() => window.__WS.run(9));
    await page.waitForTimeout(1100);
    await page.screenshot({ path: path.join(path.resolve(ROOT, SHOT_DIR), '02-gate-and-mud.png') });
    await page.evaluate(() => window.__WS.run(22));
    await page.waitForTimeout(1100);
    await page.screenshot({ path: path.join(path.resolve(ROOT, SHOT_DIR), '03-terrain-section.png') });
    await page.evaluate(() => { window.__WS.autopilot(false); window.__WS.place(430, 660, Math.PI, 30, 'A'); window.__WS.rawSwap('shot'); window.__WS.setControl({ steer: 1, handbrake: true }); window.__WS.run(0.7); });
    await page.waitForTimeout(1100);
    await page.screenshot({ path: path.join(path.resolve(ROOT, SHOT_DIR), '04-hairpin-slide.png') });
    await page.evaluate(() => { window.__WS.releaseControl(); window.__WS.restart(); });
  }

  const lap = await page.evaluate(() => {
    const W = window.__WS;
    W.restart();
    W.autopilot(true);
    let s = null;
    for (let i = 0; i < 300; i++) {
      s = W.run(1);
      if (s.lap >= 1) break;
      if (!isFinite(s.x) || !isFinite(s.speed)) return { nan: true, s, i };
    }
    return { nan: false, s, laps: W.timing.laps.slice(), best: W.timing.best };
  });
  check('autopilot completes a lap of the circuit', lap.s.lap >= 1,
    lap.best ? `best ${lap.best.toFixed(1)} s` : `stalled at idx ${lap.s.trackIdx}`);
  check('no NaN anywhere in the body state after a lap',
    !lap.nan && isFinite(lap.s.x) && isFinite(lap.s.y) && isFinite(lap.s.speed) && isFinite(lap.s.av));

  check('still no runtime errors at the end of the run', errors.length === 0, errors.slice(0, 2).join(' | '));

  await browser.close();
  if (server) server.kill();

  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
};

run().catch((e) => {
  console.error(e);
  if (server) server.kill();
  process.exit(1);
});
