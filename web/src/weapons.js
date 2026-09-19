// Ordnance + dynamic hazards. Small and self-contained so the driving model
// stays readable.

import { SID } from './surfaces.js';

export function createOrdnance() {
  return { missiles: [], bullets: [], hazards: [], particles: [], shakes: 0 };
}

export function fireMissile(o, owner, target) {
  const back = owner.activeEnd === 'A' ? -1 : 1;
  const ang = owner.ang + (back < 0 ? Math.PI : 0);
  o.missiles.push({
    x: owner.x + Math.cos(ang) * 3, y: owner.y + Math.sin(ang) * 3,
    ang, speed: 58, life: 6.5, owner, target, armed: 0.25,
  });
}

export function fireBullet(o, x, y, ang, owner) {
  o.bullets.push({
    x, y,
    vx: Math.cos(ang) * 300, vy: Math.sin(ang) * 300,
    life: 0.55, owner,
  });
}

export function dropHazard(o, x, y, sid = SID.OIL, r = 6.5, life = 14) {
  o.hazards.push({ x, y, r, sid, life, maxLife: life });
}

export function puff(o, x, y, n, color, spread = 12, life = 0.6, size = 2.4) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2;
    const s = Math.random() * spread;
    o.particles.push({
      x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s,
      life: life * (0.5 + Math.random()), maxLife: life, size: size * (0.6 + Math.random()), color,
    });
  }
}

export function sampleHazard(o, x, y) {
  for (let i = o.hazards.length - 1; i >= 0; i--) {
    const h = o.hazards[i];
    const dx = x - h.x, dy = y - h.y;
    if (dx * dx + dy * dy < h.r * h.r) return h.sid;
  }
  return -1;
}

function angDelta(a, b) {
  let d = a - b;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

export function stepOrdnance(o, dt, vehicles, hooks = {}) {
  // missiles
  for (let i = o.missiles.length - 1; i >= 0; i--) {
    const m = o.missiles[i];
    m.life -= dt;
    m.armed = Math.max(0, m.armed - dt);
    if (m.target && m.armed === 0) {
      const want = Math.atan2(m.target.y - m.y, m.target.x - m.x);
      const d = angDelta(want, m.ang);
      const turn = 2.6 * dt;
      m.ang += Math.max(-turn, Math.min(turn, d));
    }
    m.x += Math.cos(m.ang) * m.speed * dt;
    m.y += Math.sin(m.ang) * m.speed * dt;
    if (Math.random() < 0.7) {
      o.particles.push({ x: m.x, y: m.y, vx: 0, vy: 0, life: 0.35, maxLife: 0.35, size: 1.8, color: '160,160,170' });
    }
    let dead = m.life <= 0;
    for (const v of vehicles) {
      if (v === m.owner) continue;
      if (Math.hypot(v.x - m.x, v.y - m.y) < 3.4) {
        dead = true;
        hooks.onMissileHit?.(v, m);
        break;
      }
    }
    if (dead) {
      puff(o, m.x, m.y, 16, '255,150,60', 22, 0.5, 3.2);
      o.shakes = Math.min(1, o.shakes + 0.7);
      o.missiles.splice(i, 1);
    }
  }

  // bullets
  for (let i = o.bullets.length - 1; i >= 0; i--) {
    const b = o.bullets[i];
    b.life -= dt;
    const nx = b.x + b.vx * dt, ny = b.y + b.vy * dt;
    let hit = false;
    for (let k = o.missiles.length - 1; k >= 0; k--) {
      const m = o.missiles[k];
      if (m.owner === b.owner) continue;
      if (segNear(b.x, b.y, nx, ny, m.x, m.y, 3.0)) {
        puff(o, m.x, m.y, 12, '255,210,120', 18, 0.4, 2.6);
        o.missiles.splice(k, 1);
        hooks.onIntercept?.(m);
        hit = true;
        break;
      }
    }
    if (!hit) {
      for (const v of vehicles) {
        if (v === b.owner) continue;
        if (segNear(b.x, b.y, nx, ny, v.x, v.y, 2.8)) {
          hooks.onBulletHit?.(v, b);
          puff(o, v.x, v.y, 4, '255,230,160', 10, 0.25, 1.6);
          hit = true;
          break;
        }
      }
    }
    b.x = nx; b.y = ny;
    if (hit || b.life <= 0) o.bullets.splice(i, 1);
  }

  // hazards + particles
  for (let i = o.hazards.length - 1; i >= 0; i--) {
    o.hazards[i].life -= dt;
    if (o.hazards[i].life <= 0) o.hazards.splice(i, 1);
  }
  for (let i = o.particles.length - 1; i >= 0; i--) {
    const p = o.particles[i];
    p.life -= dt;
    p.x += p.vx * dt; p.y += p.vy * dt;
    p.vx *= 1 - 2.2 * dt; p.vy *= 1 - 2.2 * dt;
    if (p.life <= 0) o.particles.splice(i, 1);
  }
  o.shakes = Math.max(0, o.shakes - dt * 1.8);
}

function segNear(x0, y0, x1, y1, px, py, r) {
  const dx = x1 - x0, dy = y1 - y0;
  const len2 = dx * dx + dy * dy || 1e-6;
  let t = ((px - x0) * dx + (py - y0) * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  const cx = x0 + dx * t, cy = y0 + dy * t;
  return Math.hypot(px - cx, py - cy) < r;
}
