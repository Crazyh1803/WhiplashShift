// World rendering + the camera that sells the swap.
//
// The camera tracks the ACTIVE end's forward vector. Because it interpolates by
// shortest angle, a swap makes it sweep 180 degrees around the car on its own -
// no special case. 'snap' mode cuts instantly instead, for comparison.

import { T } from './tuning.js';
import { SURFACES, SID } from './surfaces.js';
import { ORIGIN, WORLD, PPM } from './track.js';
import { forwardVec } from './vehicle.js';

function shortest(a, b) {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

export function createRenderer(canvas, track) {
  const ctx = canvas.getContext('2d');
  const marks = document.createElement('canvas');
  marks.width = Math.round(WORLD.w * PPM);
  marks.height = Math.round(WORLD.h * PPM);
  const mctx = marks.getContext('2d');
  mctx.scale(PPM, PPM);
  mctx.translate(-ORIGIN.x, -ORIGIN.y);

  const mini = document.createElement('canvas');
  mini.width = 190; mini.height = Math.round(190 * WORLD.h / WORLD.w);
  mini.getContext('2d').drawImage(track.visual, 0, 0, mini.width, mini.height);

  const cam = { x: 0, y: 0, ang: 0, zoom: 12, mode: 'swing', shake: 0 };

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.floor(canvas.clientWidth * dpr);
    canvas.height = Math.floor(canvas.clientHeight * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { w: canvas.clientWidth, h: canvas.clientHeight, dpr };
  }

  function updateCamera(v, dt) {
    const f = forwardVec(v);
    const wantAng = Math.atan2(f.y, f.x);
    if (cam.mode === 'snap') {
      cam.ang = wantAng;
    } else {
      const d = shortest(cam.ang, wantAng);
      const rate = (3.6 + Math.abs(d) * 2.2) * dt;
      cam.ang += Math.abs(d) < rate ? d : Math.sign(d) * rate;
    }
    // lead the car slightly in the direction of travel
    const lead = Math.min(18, v.speed * 0.45);
    const tx = v.x + f.x * lead;
    const ty = v.y + f.y * lead;
    const k = 1 - Math.exp(-7 * dt);
    cam.x += (tx - cam.x) * k;
    cam.y += (ty - cam.y) * k;
    const h = canvas.clientHeight || 800;
    const wantZoom = h / (52 + v.speed * 1.05);
    cam.zoom += (wantZoom - cam.zoom) * (1 - Math.exp(-3 * dt));
    cam.shake = Math.max(0, cam.shake - dt * 2.4);
  }

  function addSkid(x, y, ang, alpha, wide) {
    mctx.save();
    mctx.translate(x, y);
    mctx.rotate(ang);
    mctx.fillStyle = `rgba(18,15,14,${Math.min(0.16, alpha * 0.4)})`;
    mctx.fillRect(-0.35, -(wide ? 0.26 : 0.14), 0.7, wide ? 0.52 : 0.28);
    mctx.restore();
  }

  function addSpray(x, y, sid, ordnance) {
    const s = SURFACES[sid];
    if (sid === SID.MUD || sid === SID.WATER || sid === SID.GRAVEL || sid === SID.OFF) {
      ordnance.particles.push({
        x, y,
        vx: (Math.random() - 0.5) * 9, vy: (Math.random() - 0.5) * 9,
        life: 0.45, maxLife: 0.45, size: 1.1 + Math.random() * 1.4,
        color: sid === SID.WATER ? '150,205,225' : (sid === SID.GRAVEL ? '150,140,115' : '92,66,40'),
      });
    } else if (sid === SID.TARMAC || sid === SID.RUMBLE) {
      ordnance.particles.push({
        x, y, vx: (Math.random() - 0.5) * 3, vy: (Math.random() - 0.5) * 3,
        life: 0.5, maxLife: 0.5, size: 1.3 + Math.random(), color: '190,190,195',
      });
    }
  }

  function drawWheel(c, w, end, steerAngle, veh) {
    c.save();
    c.translate(w.ox, w.oy);
    if (w.steered) c.rotate(steerAngle);
    const long = end === 'A' ? 0.82 : 1.02;
    const wide = end === 'A' ? 0.30 : 0.58;
    c.fillStyle = w.slip > 0.92 ? '#5a5a62' : '#17171c';
    c.fillRect(-long / 2, -wide / 2, long, wide);
    if (end === 'B') {
      c.fillStyle = '#2c2c34';
      for (let i = -1; i <= 1; i++) c.fillRect(-long / 2 + (i + 1.2) * 0.26, -wide / 2, 0.14, wide);
    }
    c.restore();
  }

  function drawCar(c, v, copilot) {
    const cfgA = T.A, cfgB = T.B;
    c.save();
    c.translate(v.x, v.y);
    c.rotate(v.ang);

    // a soft halo under the driving end, so which end has power is readable
    // at a glance even when the car is small on screen
    const glowX = v.activeEnd === 'A' ? 1.5 : -1.5;
    const g = c.createRadialGradient(glowX, 0, 0.2, glowX, 0, 4.2);
    const gc = v.activeEnd === 'A' ? '79,210,255' : '255,166,61';
    g.addColorStop(0, `rgba(${gc},0.34)`);
    g.addColorStop(1, `rgba(${gc},0)`);
    c.fillStyle = g;
    c.beginPath();
    c.arc(glowX, 0, 4.2, 0, 6.3);
    c.fill();

    // shadow
    c.fillStyle = 'rgba(0,0,0,0.45)';
    c.beginPath();
    c.ellipse(0.25, 0.35, 2.6, 1.3, 0, 0, 6.3);
    c.fill();

    for (const w of v.wheels) drawWheel(c, w, w.end, v.steerAngle, v);

    // chassis spine
    c.fillStyle = v.isRival ? '#2a2c33' : '#343842';
    c.beginPath();
    c.roundRect(-2.0, -0.78, 4.0, 1.56, 0.4);
    c.fill();
    c.strokeStyle = 'rgba(0,0,0,0.6)';
    c.lineWidth = 0.09;
    c.stroke();

    const outline = 'rgba(8,10,12,0.85)';

    // End A: low wedge
    c.fillStyle = v.activeEnd === 'A' ? cfgA.color : '#5c717c';
    c.beginPath();
    c.moveTo(2.30, 0);
    c.lineTo(1.35, -0.86);
    c.lineTo(0.55, -0.70);
    c.lineTo(0.55, 0.70);
    c.lineTo(1.35, 0.86);
    c.closePath();
    c.fill();
    c.strokeStyle = outline;
    c.lineWidth = 0.1;
    c.stroke();

    // End B: blunt, raised, roll bar
    c.fillStyle = v.activeEnd === 'B' ? cfgB.color : '#7a6750';
    c.beginPath();
    c.roundRect(-2.35, -0.95, 1.85, 1.90, 0.28);
    c.fill();
    c.strokeStyle = outline;
    c.stroke();
    c.fillStyle = 'rgba(0,0,0,0.3)';
    c.fillRect(-1.75, -0.95, 0.22, 1.90);
    c.fillRect(-1.12, -0.95, 0.22, 1.90);

    // livery stripe / rival tint
    c.fillStyle = v.isRival ? v.color : 'rgba(230,238,245,0.9)';
    c.fillRect(-0.45, -0.22, 0.95, 0.44);

    // active-end arrow
    const fs = v.activeEnd === 'A' ? 1 : -1;
    c.fillStyle = 'rgba(255,255,255,0.85)';
    c.beginPath();
    c.moveTo(fs * 2.95, 0);
    c.lineTo(fs * 2.25, -0.42);
    c.lineTo(fs * 2.25, 0.42);
    c.closePath();
    c.fill();

    // tailgun on the inactive end
    if (copilot) {
      c.save();
      c.rotate(-v.ang);
      c.rotate(copilot.turretAng);
      c.fillStyle = '#9aa4b0';
      c.fillRect(-0.3, -0.16, 1.9, 0.32);
      c.fillStyle = '#c8d2dc';
      c.fillRect(1.4, -0.1, 0.5, 0.2);
      c.restore();
    }

    c.restore();

    // engage ramp + power-cut tell
    if (v.engage < 1 || v.powerCut > 0) {
      c.save();
      c.translate(v.x, v.y);
      c.strokeStyle = v.powerCut > 0 ? 'rgba(255,90,70,0.9)' : 'rgba(255,255,255,0.55)';
      c.lineWidth = 0.22;
      c.beginPath();
      c.arc(0, 0, 3.4, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * (v.powerCut > 0 ? 1 : v.engage));
      c.stroke();
      c.restore();
    }
  }

  function draw(state, dt) {
    const { w, h } = { w: canvas.clientWidth, h: canvas.clientHeight };
    const { player, rivals, ordnance, copilot } = state;

    ctx.fillStyle = '#0b0d0c';
    ctx.fillRect(0, 0, w, h);

    ctx.save();
    const sh = cam.shake;
    ctx.translate(w / 2 + (Math.random() - 0.5) * sh * 22, h * 0.62 + (Math.random() - 0.5) * sh * 22);
    ctx.rotate(-Math.PI / 2 - cam.ang);
    ctx.scale(cam.zoom, cam.zoom);
    ctx.translate(-cam.x, -cam.y);

    ctx.drawImage(track.visual, ORIGIN.x, ORIGIN.y, WORLD.w, WORLD.h);
    ctx.drawImage(marks, ORIGIN.x, ORIGIN.y, WORLD.w, WORLD.h);

    // dynamic hazards
    for (const hz of ordnance.hazards) {
      const a = Math.min(1, hz.life / 3) * 0.85;
      ctx.fillStyle = `rgba(10,10,14,${a})`;
      ctx.beginPath();
      ctx.ellipse(hz.x, hz.y, hz.r, hz.r * 0.78, 0.4, 0, 6.3);
      ctx.fill();
      ctx.strokeStyle = `rgba(120,110,190,${a * 0.5})`;
      ctx.lineWidth = 0.2;
      ctx.stroke();
    }

    // particles
    for (const p of ordnance.particles) {
      const a = Math.max(0, p.life / p.maxLife);
      ctx.fillStyle = `rgba(${p.color},${a * 0.8})`;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.size * (0.4 + a), 0, 6.3);
      ctx.fill();
    }

    // gate posts pulse when they are the next thing you have to deal with
    for (const g of track.gates) {
      const live = state.nextGate === g;
      const nx = -Math.sin(g.ang), ny = Math.cos(g.ang);
      ctx.strokeStyle = g.forcedEnd === 'A'
        ? `rgba(79,210,255,${live ? 0.9 : 0.35})`
        : `rgba(255,166,61,${live ? 0.9 : 0.35})`;
      ctx.lineWidth = live ? 0.7 : 0.35;
      ctx.beginPath();
      ctx.moveTo(g.x + nx * g.halfWidth, g.y + ny * g.halfWidth);
      ctx.lineTo(g.x - nx * g.halfWidth, g.y - ny * g.halfWidth);
      ctx.stroke();
    }

    for (const r of rivals) drawCar(ctx, r, null);
    drawCar(ctx, player, copilot);

    // turret arc
    if (copilot && copilot.target) {
      ctx.strokeStyle = 'rgba(255,90,90,0.5)';
      ctx.lineWidth = 0.14;
      ctx.beginPath();
      ctx.moveTo(player.x, player.y);
      ctx.lineTo(copilot.target.x, copilot.target.y);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(copilot.target.x, copilot.target.y, 2.6, 0, 6.3);
      ctx.stroke();
    }

    for (const m of ordnance.missiles) {
      ctx.save();
      ctx.translate(m.x, m.y);
      ctx.rotate(m.ang);
      ctx.fillStyle = '#ffd27a';
      ctx.fillRect(-0.9, -0.22, 1.8, 0.44);
      ctx.fillStyle = '#ff7a3d';
      ctx.fillRect(-1.5, -0.16, 0.6, 0.32);
      ctx.restore();
    }
    ctx.strokeStyle = 'rgba(255,240,180,0.85)';
    ctx.lineWidth = 0.13;
    ctx.beginPath();
    for (const b of ordnance.bullets) {
      ctx.moveTo(b.x, b.y);
      ctx.lineTo(b.x - b.vx * 0.012, b.y - b.vy * 0.012);
    }
    ctx.stroke();

    ctx.restore();
    return { w, h };
  }

  return { ctx, cam, resize, updateCamera, draw, addSkid, addSpray, mini, drawCar };
}
