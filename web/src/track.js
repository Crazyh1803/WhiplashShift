// Track authoring + bake.
//
// The circuit is authored as an ordered list of primitives (straights and arcs)
// carrying a surface and a width. At load we bake two rasters from that data:
//
//   surfaceMap  - one byte per pixel holding a surface id. Wheel lookup is a
//                 single array index, so every wheel can sample independently
//                 and half-on/half-off transitions come out for free.
//   visual      - the pretty version, drawn once and blitted under the camera.
//
// Layout: tarmac start/finish -> rumble warning -> GATE -> mud sweeper ->
// water -> boulders -> ice -> tight 180 hairpin (the backwards branch) ->
// gravel loop back -> rumble warning -> GATE -> tarmac.

import { SID, SURFACES, KEY_STEP } from './surfaces.js';

// Phones get a coarser visual raster: the full-size bake is ~31 MB of canvas and
// the extra detail is invisible on a small screen anyway.
const LOW_SPEC = typeof window !== 'undefined'
  && (window.innerWidth < 900 || (navigator.maxTouchPoints || 0) > 1);
export const PPM = LOW_SPEC ? 3 : 4;   // pixels per metre in the baked VISUAL raster
export const MAP_PPM = 3;              // pixels per metre in the surface-id raster
export const ORIGIN = { x: 80, y: 130 };
export const WORLD = { w: 820, h: 590 };

const STEP = 3.5;                // metres between centreline samples

function pushStraight(out, x0, y0, x1, y1, width, surface) {
  const dx = x1 - x0, dy = y1 - y0;
  const len = Math.hypot(dx, dy);
  const n = Math.max(1, Math.round(len / STEP));
  for (let i = out.length ? 1 : 0; i <= n; i++) {
    const t = i / n;
    out.push({ x: x0 + dx * t, y: y0 + dy * t, w: width, s: surface });
  }
}

function pushArc(out, cx, cy, r, a0, a1, width, surface) {
  const sweep = a1 - a0;
  const len = Math.abs(sweep) * r;
  const n = Math.max(2, Math.round(len / STEP));
  for (let i = out.length ? 1 : 0; i <= n; i++) {
    const a = a0 + sweep * (i / n);
    out.push({ x: cx + Math.cos(a) * r, y: cy + Math.sin(a) * r, w: width, s: surface });
  }
}

const R = Math.PI / 180;

// Each entry appends to a single continuous, closed centreline.
function authorCentreline() {
  const p = [];
  pushStraight(p, 220, 180, 650, 180, 26, SID.TARMAC);    // start / finish straight
  pushStraight(p, 650, 180, 722, 180, 26, SID.RUMBLE);    // "tarmac ends ahead"
  pushArc(p, 730, 280, 100, 270 * R, 360 * R, 24, SID.MUD);   // gate 1 is on this entry
  pushStraight(p, 830, 280, 830, 355, 24, SID.MUD);
  pushStraight(p, 830, 355, 830, 420, 24, SID.WATER);     // water hazard
  pushStraight(p, 830, 420, 830, 560, 24, SID.BOULDER);
  pushArc(p, 730, 560, 100, 0, 90 * R, 24, SID.BOULDER);
  pushStraight(p, 730, 660, 560, 660, 24, SID.GRAVEL);
  pushStraight(p, 560, 660, 470, 660, 24, SID.ICE);       // ice patch before the hairpin
  pushStraight(p, 470, 660, 400, 660, 24, SID.GRAVEL);
  pushArc(p, 400, 600, 60, 90 * R, 270 * R, 22, SID.MUD); // the hairpin: doubles straight back
  pushStraight(p, 400, 540, 520, 540, 22, SID.MUD);       // the backwards branch
  pushArc(p, 520, 460, 80, 90 * R, -90 * R, 24, SID.GRAVEL);
  pushStraight(p, 520, 380, 330, 380, 24, SID.GRAVEL);
  pushStraight(p, 330, 380, 260, 380, 26, SID.RUMBLE);    // "tarmac resumes"
  pushStraight(p, 260, 380, 220, 380, 26, SID.TARMAC);    // gate 2
  pushArc(p, 220, 280, 100, 90 * R, 270 * R, 26, SID.TARMAC);
  p.pop(); // last point coincides with the first: keep the loop clean
  return p;
}

function finalise(pts) {
  let total = 0;
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i];
    const b = pts[(i + 1) % pts.length];
    a.dist = Math.hypot(b.x - a.x, b.y - a.y);
    a.sd = total;
    total += a.dist;
  }
  for (let i = 0; i < pts.length; i++) {
    const a = pts[(i - 1 + pts.length) % pts.length];
    const b = pts[(i + 1) % pts.length];
    const ang = Math.atan2(b.y - a.y, b.x - a.x);
    pts[i].ang = ang;
    pts[i].dx = Math.cos(ang);
    pts[i].dy = Math.sin(ang);
  }
  return total;
}

function strokeRibbon(ctx, pts, styleFor, widthBias = 0) {
  // Stroke run-by-run so each surface keeps a hard boundary.
  let i = 0;
  while (i < pts.length) {
    let j = i;
    while (j + 1 < pts.length && pts[j + 1].s === pts[i].s) j++;
    ctx.beginPath();
    ctx.moveTo(pts[i].x, pts[i].y);
    for (let k = i + 1; k <= Math.min(j + 1, pts.length - 1); k++) ctx.lineTo(pts[k].x, pts[k].y);
    if (j + 1 >= pts.length) ctx.lineTo(pts[0].x, pts[0].y);
    ctx.lineWidth = pts[i].w + widthBias;
    // Butt caps, not round: a round cap on a 22 m ribbon bulges a 10 m blob out
    // past every surface boundary, in the physics map as well as the picture.
    // Each run already extends one node into the next, so the joins stay sealed.
    ctx.lineCap = 'butt';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = styleFor(pts[i].s);
    ctx.stroke();
    i = j + 1;
  }
}

function makeCanvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return c;
}

function bakeSurfaceMap(pts) {
  const W = Math.round(WORLD.w * MAP_PPM), H = Math.round(WORLD.h * MAP_PPM);
  const c = makeCanvas(W, H);
  const ctx = c.getContext('2d', { willReadFrequently: true });
  ctx.fillStyle = `rgb(${SID.OFF * KEY_STEP},0,0)`;
  ctx.fillRect(0, 0, W, H);
  ctx.save();
  ctx.scale(MAP_PPM, MAP_PPM);
  ctx.translate(-ORIGIN.x, -ORIGIN.y);
  strokeRibbon(ctx, pts, (s) => `rgb(${s * KEY_STEP},0,0)`);
  ctx.restore();

  const raw = ctx.getImageData(0, 0, W, H).data;
  const map = new Uint8Array(W * H);
  for (let i = 0, p = 0; i < map.length; i++, p += 4) {
    const r = raw[p];
    const id = Math.round(r / KEY_STEP);
    // Anti-aliased boundary pixels land between two keys; reject them to the
    // off-track shoulder rather than letting them read as some third surface.
    map[i] = (id >= 0 && id < SURFACES.length && Math.abs(r - id * KEY_STEP) <= 8) ? id : SID.OFF;
  }
  return { map, W, H };
}

function bakeVisual(pts, gates) {
  const W = Math.round(WORLD.w * PPM), H = Math.round(WORLD.h * PPM);
  const c = makeCanvas(W, H);
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#26301f';
  ctx.fillRect(0, 0, W, H);

  // scrubby ground: dense, low-contrast, so it reads as terrain rather than noise
  let seed = 1337;
  const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
  for (let i = 0; i < 42000; i++) {
    const x = rnd() * W, y = rnd() * H;
    const v = rnd();
    ctx.fillStyle = v > 0.66 ? 'rgba(60,76,48,0.5)'
      : v > 0.33 ? 'rgba(30,40,26,0.45)'
        : 'rgba(46,58,38,0.4)';
    ctx.fillRect(x, y, 1 + rnd() * 4, 1 + rnd() * 4);
  }

  ctx.save();
  ctx.scale(PPM, PPM);
  ctx.translate(-ORIGIN.x, -ORIGIN.y);

  strokeRibbon(ctx, pts, () => 'rgba(8,11,9,0.85)', 10);             // shoulder shadow
  strokeRibbon(ctx, pts, (s) => SURFACES[s].edge, 4);               // verge
  strokeRibbon(ctx, pts, (s) => SURFACES[s].fill, 0);               // surface

  // per-surface grain, drawn inside the ribbon
  for (let i = 0; i < pts.length; i += 2) {
    const p = pts[i];
    const surf = SURFACES[p.s];
    const nx = -p.dy, ny = p.dx;
    if (p.s === SID.MUD || p.s === SID.WATER) {
      for (let k = 0; k < 6; k++) {
        const o = (rnd() - 0.5) * p.w * 0.9;
        const along = (rnd() - 0.5) * 3;
        ctx.fillStyle = p.s === SID.MUD
          ? (rnd() > 0.5 ? 'rgba(30,21,12,0.32)' : 'rgba(118,92,60,0.22)')
          : 'rgba(150,215,235,0.12)';
        ctx.beginPath();
        ctx.ellipse(p.x + nx * o + p.dx * along, p.y + ny * o + p.dy * along,
          0.5 + rnd() * 1.1, 0.3 + rnd() * 0.6, p.ang, 0, 6.3);
        ctx.fill();
      }
    } else if (p.s === SID.BOULDER) {
      for (let k = 0; k < 2; k++) {
        const o = (rnd() - 0.5) * p.w * 0.8;
        const bx = p.x + nx * o, by = p.y + ny * o;
        const r = 0.8 + rnd() * 1.3;
        ctx.fillStyle = 'rgba(24,24,30,0.5)';        // shadow first...
        ctx.beginPath();
        ctx.arc(bx + 0.45, by + 0.55, r, 0, 6.3);
        ctx.fill();
        ctx.fillStyle = 'rgba(126,126,138,0.92)';    // ...then the rock on top
        ctx.beginPath();
        ctx.arc(bx, by, r, 0, 6.3);
        ctx.fill();
        ctx.fillStyle = 'rgba(170,172,184,0.5)';     // lit edge
        ctx.beginPath();
        ctx.arc(bx - r * 0.25, by - r * 0.3, r * 0.5, 0, 6.3);
        ctx.fill();
      }
    } else if (p.s === SID.ICE) {
      ctx.strokeStyle = 'rgba(190,230,245,0.16)';
      ctx.lineWidth = 0.5;
      const o = (rnd() - 0.5) * p.w * 0.8;
      ctx.beginPath();
      ctx.moveTo(p.x + nx * o, p.y + ny * o);
      ctx.lineTo(p.x + nx * o + p.dx * 5, p.y + ny * o + p.dy * 5);
      ctx.stroke();
    } else if (p.s === SID.GRAVEL) {
      ctx.fillStyle = 'rgba(120,112,92,0.4)';
      const o = (rnd() - 0.5) * p.w * 0.85;
      ctx.fillRect(p.x + nx * o, p.y + ny * o, 0.8, 0.8);
    } else if (p.s === SID.RUMBLE) {
      // alternating edge ticks: the GDD's "the tarmac ends ahead" cue, kept to
      // the verges so the racing line stays readable
      ctx.strokeStyle = (i >> 1) % 2 ? '#c8452f' : '#e6e2d6';
      ctx.lineWidth = 2.6;
      const outer = p.w * 0.5 - 0.5, inner = p.w * 0.5 - 3.6;
      for (const sgn of [-1, 1]) {
        ctx.beginPath();
        ctx.moveTo(p.x + nx * outer * sgn, p.y + ny * outer * sgn);
        ctx.lineTo(p.x + nx * inner * sgn, p.y + ny * inner * sgn);
        ctx.stroke();
      }
    }
  }

  // lane dashes on tarmac only
  ctx.setLineDash([6, 8]);
  ctx.lineWidth = 0.6;
  ctx.strokeStyle = 'rgba(210,210,200,0.25)';
  ctx.beginPath();
  for (let i = 0; i < pts.length - 1; i++) {
    if (pts[i].s !== SID.TARMAC) continue;
    ctx.moveTo(pts[i].x, pts[i].y);
    ctx.lineTo(pts[i + 1].x, pts[i + 1].y);
  }
  ctx.stroke();
  ctx.setLineDash([]);

  // induction gates
  for (const g of gates) {
    const nx = -Math.sin(g.ang), ny = Math.cos(g.ang);
    const h = g.halfWidth;
    ctx.strokeStyle = g.forcedEnd === 'A' ? 'rgba(79,210,255,0.85)' : 'rgba(255,166,61,0.85)';
    ctx.lineWidth = 2.4;
    ctx.setLineDash([3, 3]);
    ctx.beginPath();
    ctx.moveTo(g.x + nx * h, g.y + ny * h);
    ctx.lineTo(g.x - nx * h, g.y - ny * h);
    ctx.stroke();
    ctx.setLineDash([]);
    for (const sgn of [-1, 1]) {
      ctx.fillStyle = g.forcedEnd === 'A' ? '#4fd2ff' : '#ffa63d';
      ctx.beginPath();
      ctx.arc(g.x + nx * h * sgn, g.y + ny * h * sgn, 2.2, 0, 6.3);
      ctx.fill();
    }
  }

  // start / finish
  const sp = pts[0];
  const snx = -sp.dy, sny = sp.dx;
  ctx.lineWidth = 2;
  for (let k = -6; k <= 6; k++) {
    ctx.fillStyle = (k & 1) ? '#e8e8e0' : '#1a1a1a';
    ctx.save();
    ctx.translate(sp.x + snx * k * 2, sp.y + sny * k * 2);
    ctx.rotate(sp.ang);
    ctx.fillRect(-1.5, -2, 3, 4);
    ctx.restore();
  }

  ctx.restore();
  return c;
}

export function buildTrack() {
  const pts = authorCentreline();
  const length = finalise(pts);

  // Gates sit on the centreline; crossing is evaluated on lap progress so it
  // cannot be missed by tunnelling at speed. One is placed just past each
  // rumble-strip warning run.
  const gates = [];
  {
    // find the two rumble runs and place a gate just past each
    let run = null;
    for (let i = 0; i < pts.length; i++) {
      if (pts[i].s === SID.RUMBLE) { if (!run) run = { start: i }; run.end = i; }
      else if (run) {
        const p = pts[Math.min(run.end + 1, pts.length - 1)];
        gates.push({
          idx: Math.min(run.end + 1, pts.length - 1),
          x: p.x, y: p.y, ang: p.ang, halfWidth: p.w * 0.5 + 2,
          forcedEnd: p.s === SID.TARMAC ? 'A' : 'B',
          label: p.s === SID.TARMAC ? 'ASPHALT SPEC' : 'TERRAIN SPEC',
        });
        run = null;
      }
    }
  }

  const checkpoints = [];
  for (let i = 0; i < pts.length; i++) {
    if (!checkpoints.length || pts[i].sd - checkpoints[checkpoints.length - 1].dist > 110) {
      checkpoints.push({ idx: i, x: pts[i].x, y: pts[i].y, ang: pts[i].ang, dist: pts[i].sd });
    }
  }

  const { map, W, H } = bakeSurfaceMap(pts);
  const visual = bakeVisual(pts, gates);

  const sampleSurface = (x, y) => {
    const px = ((x - ORIGIN.x) * MAP_PPM) | 0;
    const py = ((y - ORIGIN.y) * MAP_PPM) | 0;
    if (px < 0 || py < 0 || px >= W || py >= H) return SID.OFF;
    return map[py * W + px];
  };

  const nearestIndex = (x, y, hint = 0) => {
    const n = pts.length;
    let best = hint, bestD = Infinity;
    const span = 90;
    for (let k = -span; k <= span; k++) {
      const i = ((hint + k) % n + n) % n;
      const dx = pts[i].x - x, dy = pts[i].y - y;
      const d = dx * dx + dy * dy;
      if (d < bestD) { bestD = d; best = i; }
    }
    // hint may be stale (recover / big off): fall back to a full scan
    if (bestD > 90 * 90) {
      for (let i = 0; i < n; i++) {
        const dx = pts[i].x - x, dy = pts[i].y - y;
        const d = dx * dx + dy * dy;
        if (d < bestD) { bestD = d; best = i; }
      }
    }
    return { idx: best, dist: Math.sqrt(bestD) };
  };

  const ahead = (idx, metres) => {
    const n = pts.length;
    let i = idx, travelled = 0;
    while (travelled < metres) {
      travelled += pts[i].dist;
      i = (i + 1) % n;
      if (i === idx) break;
    }
    return pts[i];
  };

  return {
    pts, length, gates, checkpoints, visual, surfaceMap: map, mapW: W, mapH: H,
    sampleSurface, nearestIndex, ahead,
    start: { x: pts[0].x, y: pts[0].y, ang: pts[0].ang },
  };
}
