// Screen-space HUD. Everything the driver needs to read the swap at 180 km/h.

import { T } from './tuning.js';
import { SURFACES } from './surfaces.js';
import { ORIGIN, WORLD } from './track.js';
import { CONTROLS } from './input.js';

const MONO = 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace';

export function fmtTime(t) {
  if (t == null || !isFinite(t)) return '--:--.---';
  const m = Math.floor(t / 60);
  const s = Math.floor(t % 60);
  const ms = Math.floor((t % 1) * 1000);
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}.${String(ms).padStart(3, '0')}`;
}

function panel(c, x, y, w, h, a = 0.62) {
  c.fillStyle = `rgba(8,11,14,${a})`;
  c.strokeStyle = 'rgba(150,170,190,0.18)';
  c.lineWidth = 1;
  c.beginPath();
  c.roundRect(x, y, w, h, 6);
  c.fill();
  c.stroke();
}

function bar(c, x, y, w, h, frac, color, bg = 'rgba(255,255,255,0.10)') {
  c.fillStyle = bg;
  c.fillRect(x, y, w, h);
  c.fillStyle = color;
  c.fillRect(x, y, w * Math.max(0, Math.min(1, frac)), h);
}

function label(c, text, x, y, size = 11, color = 'rgba(170,185,200,0.75)', align = 'left') {
  c.font = `${size}px ${MONO}`;
  c.fillStyle = color;
  c.textAlign = align;
  c.textBaseline = 'alphabetic';
  c.fillText(text, x, y);
}

export function drawHud(c, w, h, state) {
  const { player: v, copilot: cp, timing, track, renderer, paused, showHelp, finished, audio } = state;
  const cfg = T[v.activeEnd];
  const other = v.activeEnd === 'A' ? 'B' : 'A';
  const now = performance.now() / 1000;

  // ---------- top-left: timing ----------
  panel(c, 16, 16, 212, 86);
  label(c, 'LAP', 28, 38, 11);
  label(c, `${Math.min(timing.lap + 1, timing.total)} / ${timing.total}`, 220, 38, 15, '#e8eef5', 'right');
  label(c, 'CURRENT', 28, 60, 11);
  label(c, fmtTime(timing.lapTime), 220, 60, 14, '#e8eef5', 'right');
  label(c, 'BEST', 28, 82, 11);
  label(c, fmtTime(timing.best), 220, 82, 14, timing.best ? '#8fd94f' : 'rgba(170,185,200,0.5)', 'right');
  label(c, `POS ${state.position} / ${state.fieldSize}`, 28, 96, 10, 'rgba(170,185,200,0.6)');

  // ---------- top-right: minimap ----------
  const mw = renderer.mini.width, mh = renderer.mini.height;
  const mx = w - mw - 16, my = 16;
  panel(c, mx - 6, my - 6, mw + 12, mh + 12, 0.7);
  c.globalAlpha = 0.85;
  c.drawImage(renderer.mini, mx, my);
  c.globalAlpha = 1;
  const toMini = (x, y) => [mx + ((x - ORIGIN.x) / WORLD.w) * mw, my + ((y - ORIGIN.y) / WORLD.h) * mh];
  for (const r of state.rivals) {
    const [px, py] = toMini(r.x, r.y);
    c.fillStyle = r.color;
    c.beginPath(); c.arc(px, py, 3, 0, 6.3); c.fill();
  }
  {
    const [px, py] = toMini(v.x, v.y);
    c.fillStyle = cfg.color;
    c.beginPath(); c.arc(px, py, 4, 0, 6.3); c.fill();
    c.strokeStyle = '#fff'; c.lineWidth = 1.2; c.stroke();
  }

  // ---------- top-centre: surface transition warning ----------
  if (cp.nextChange) {
    const eta = cp.nextChange.eta;
    const urgency = Math.max(0, Math.min(1, 1 - eta / T.ai.lookahead));
    const nx = w / 2 - 190, ny = 16;
    const flash = eta < 1.4 ? 0.55 + 0.45 * Math.sin(now * 18) : 1;
    panel(c, nx, ny, 380, 56, 0.55 + 0.25 * urgency);
    const endCol = T[cp.nextChange.end].color;
    label(c, `${SURFACES[cp.nextChange.sid].name} IN ${cp.nextChange.dist.toFixed(0)} M`, nx + 14, ny + 24, 13, '#e8eef5');
    c.globalAlpha = flash;
    label(c, `PREP END ${cp.nextChange.end}`, nx + 366, ny + 24, 15, endCol, 'right');
    c.globalAlpha = 1;
    bar(c, nx + 14, ny + 34, 352, 8, urgency, endCol);
  }

  // ---------- bottom-left: speed + active end ----------
  const by = h - 128;
  panel(c, 16, by, 268, 112);
  c.font = `52px ${MONO}`;
  c.fillStyle = '#e8eef5';
  c.textAlign = 'left';
  c.fillText(String(Math.round(v.speed * 3.6)).padStart(3, ' '), 28, by + 58);
  label(c, 'KM/H', 178, by + 58, 14, 'rgba(170,185,200,0.7)');
  label(c, v.reversing ? 'REVERSE' : (v.fwdSpeed < -0.5 ? 'BACKWARD VECTOR' : 'FORWARD'), 28, by + 76, 11,
    v.reversing ? '#ffa63d' : 'rgba(170,185,200,0.6)');

  // engage / cooldown readout
  label(c, 'TRANSMISSION', 28, by + 94, 10);
  bar(c, 128, by + 86, 140, 8, v.powerCut > 0 ? 0 : v.engage, v.powerCut > 0 ? '#ff5a46' : cfg.color);
  label(c, v.cooldown > 0 ? `SWAP LOCK ${v.cooldown.toFixed(2)}s` : 'SWAP READY', 28, by + 108, 10,
    v.cooldown > 0 ? '#ff9a6a' : '#8fd94f');

  // ---------- bottom-centre: chassis schematic ----------
  const cw = 420, cx = w / 2 - cw / 2, cy = h - 96;
  panel(c, cx, cy, cw, 80);
  drawChassis(c, cx, cy, cw, 80, v);

  // ---------- bottom-right: damage / boost / copilot ----------
  const rx = w - 244, ry = h - 128;
  panel(c, rx, ry, 228, 112);
  label(c, 'CHASSIS', rx + 12, ry + 24, 11);
  bar(c, rx + 82, ry + 15, 132, 10, 1 - v.damage / T.damage.max,
    v.damage > 70 ? '#ff5a46' : v.damage > 40 ? '#ffa63d' : '#8fd94f');
  label(c, 'BOOST', rx + 12, ry + 46, 11);
  bar(c, rx + 82, ry + 37, 132, 10, v.boost, v.boostTimer > 0 ? '#fff2a0' : '#4fd2ff');
  label(c, 'COPILOT', rx + 12, ry + 70, 11);
  label(c, cp.enabled ? cp.state : 'STOOD DOWN', rx + 216, ry + 70, 12,
    cp.enabled ? (cp.state === 'IDLE' ? 'rgba(170,185,200,0.7)' : '#4fd2ff') : 'rgba(255,120,100,0.8)', 'right');
  label(c, 'TAILGUN', rx + 12, ry + 92, 11);
  label(c, cp.targetKind ? `TRACKING ${cp.targetKind}` : 'SCANNING', rx + 216, ry + 92, 12,
    cp.targetKind === 'MISSILE' ? '#ff5a46' : cp.targetKind ? '#ffa63d' : 'rgba(170,185,200,0.55)', 'right');

  // ---------- copilot callouts ----------
  let cyy = h * 0.38;
  for (let i = cp.callouts.length - 1; i >= 0; i--) {
    const co = cp.callouts[i];
    const a = Math.max(0, 1 - co.age / 6);
    if (a <= 0) continue;
    const col = co.level === 'alert' ? `rgba(255,120,100,${a})`
      : co.level === 'warn' ? `rgba(255,190,90,${a})`
        : co.level === 'good' ? `rgba(143,217,79,${a})`
          : `rgba(200,215,230,${a})`;
    label(c, `▸ ${co.text}`, 22, cyy, 13, col);
    cyy -= 20;
  }

  // ---------- whiplash banner ----------
  if (v.lastWhiplash && v.lastWhiplash.age < 2.2) {
    const a = Math.max(0, 1 - v.lastWhiplash.age / 2.2);
    c.textAlign = 'center';
    c.font = `30px ${MONO}`;
    c.fillStyle = `rgba(255,242,160,${a})`;
    c.fillText(v.lastWhiplash.kind, w / 2, h * 0.3);
    c.font = `14px ${MONO}`;
    c.fillStyle = `rgba(230,238,245,${a * 0.85})`;
    c.fillText(`${Math.round(v.lastWhiplash.retained * 100)}% MOMENTUM RETAINED · ${v.lastWhiplash.time.toFixed(2)}s · +BOOST`,
      w / 2, h * 0.3 + 22);
  }

  // ---------- wrong-end warning ----------
  if (v.wrongEnd && v.speed > 11 && SURFACES[v.surfaceUnder].dmg > 0) {
    const a = 0.55 + 0.45 * Math.sin(now * 14);
    c.textAlign = 'center';
    c.font = `18px ${MONO}`;
    c.fillStyle = `rgba(255,90,70,${a})`;
    c.fillText(`END ${v.activeEnd} ON ${SURFACES[v.surfaceUnder].name} — SWAP`, w / 2, h * 0.22);
  }

  // ---------- overlays ----------
  if (showHelp) drawHelp(c, w, h, audio);
  if (paused && !finished) centreCard(c, w, h, 'PAUSED', 'P to resume · H for controls');
  if (finished) {
    centreCard(c, w, h, 'RUN COMPLETE',
      `${timing.total} laps · best ${fmtTime(timing.best)} · R to run it again`);
  }

  c.textAlign = 'left';
}

function drawChassis(c, x, y, w, h, v) {
  const midY = y + h * 0.42;
  const pad = 16;
  const boxW = 128, boxH = 34;

  const ends = [
    { key: 'A', bx: x + pad, dir: -1 },
    { key: 'B', bx: x + w - pad - boxW, dir: 1 },
  ];

  // spine
  c.strokeStyle = 'rgba(160,175,190,0.45)';
  c.lineWidth = 2;
  c.beginPath();
  c.moveTo(x + pad + boxW, midY);
  c.lineTo(x + w - pad - boxW, midY);
  c.stroke();
  c.font = `9px ${MONO}`;
  c.fillStyle = 'rgba(160,175,190,0.55)';
  c.textAlign = 'center';
  c.fillText('CHASSIS', x + w / 2, midY - 6);

  for (const e of ends) {
    const cfg = T[e.key];
    const active = v.activeEnd === e.key;
    c.fillStyle = active ? cfg.color : 'rgba(255,255,255,0.06)';
    c.strokeStyle = active ? cfg.color : 'rgba(160,175,190,0.3)';
    c.lineWidth = active ? 2 : 1;
    c.beginPath();
    c.roundRect(e.bx, midY - boxH / 2, boxW, boxH, 4);
    c.fill();
    c.stroke();

    c.textAlign = 'center';
    c.font = `13px ${MONO}`;
    c.fillStyle = active ? '#0b0d0c' : 'rgba(210,222,235,0.75)';
    c.fillText(`END ${e.key}`, e.bx + boxW / 2, midY - 1);
    c.font = `8px ${MONO}`;
    c.fillStyle = active ? 'rgba(11,13,12,0.75)' : 'rgba(170,185,200,0.5)';
    c.fillText(cfg.blurb.toUpperCase(), e.bx + boxW / 2, midY + 11);

    // surface under this pair
    const wheel = v.wheels.find((wl) => wl.end === e.key);
    const surf = SURFACES[wheel.surface];
    c.font = `10px ${MONO}`;
    c.fillStyle = 'rgba(190,205,220,0.8)';
    c.fillText(surf.name, e.bx + boxW / 2, y + h - 10);

    // active direction arrow
    if (active) {
      const ax = e.key === 'A' ? e.bx - 10 : e.bx + boxW + 10;
      c.fillStyle = cfg.color;
      c.beginPath();
      c.moveTo(ax + (e.key === 'A' ? -8 : 8), midY);
      c.lineTo(ax, midY - 6);
      c.lineTo(ax, midY + 6);
      c.closePath();
      c.fill();
    }
  }
  c.textAlign = 'left';
}

function centreCard(c, w, h, title, sub) {
  c.fillStyle = 'rgba(6,8,10,0.72)';
  c.fillRect(0, 0, w, h);
  c.textAlign = 'center';
  c.font = `36px ${MONO}`;
  c.fillStyle = '#e8eef5';
  c.fillText(title, w / 2, h / 2 - 8);
  c.font = `14px ${MONO}`;
  c.fillStyle = 'rgba(180,196,212,0.85)';
  c.fillText(sub, w / 2, h / 2 + 22);
  c.textAlign = 'left';
}

function drawHelp(c, w, h, audio) {
  const bw = 420, bh = 60 + CONTROLS.length * 22;
  const x = w / 2 - bw / 2, y = h / 2 - bh / 2;
  c.fillStyle = 'rgba(6,8,10,0.86)';
  c.fillRect(0, 0, w, h);
  panel(c, x, y, bw, bh, 0.9);
  label(c, 'WHIPLASH SHIFT — CONTROLS', x + 20, y + 30, 15, '#e8eef5');
  let yy = y + 56;
  for (const [k, d] of CONTROLS) {
    label(c, k, x + 20, yy, 12, '#4fd2ff');
    label(c, d, x + 150, yy, 12, 'rgba(200,215,230,0.85)');
    yy += 22;
  }
  label(c, `M mutes audio (${audio && audio.enabled ? 'on' : 'off'}) · H closes this`, x + 20, y + bh - 14, 11);
}
