// Touch controls.
//
// Builds its own DOM and styles so the two host pages (index.html and the
// published artifact) stay in sync automatically. Exposes the same control
// shape as src/input.js, plus tapped() for one-shot actions, so main.js can
// merge the two without caring which one the player is using.
//
// Layout is built around the whiplash sequence: hold GO with the right thumb,
// tap SWAP, then slide onto H-BRK while the left thumb holds full steering lock.

const HOLDS = { throttle: 'throttle', brake: 'brake', handbrake: 'handbrake' };

const CSS = `
.ws-touch { position: fixed; inset: 0; z-index: 4; pointer-events: none;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
.ws-touch * { pointer-events: auto; touch-action: none; -webkit-user-select: none; user-select: none;
  -webkit-tap-highlight-color: transparent; }
.ws-touch button { font-family: inherit; color: inherit; background: none; border: 0; padding: 0; }

.ws-steer {
  position: absolute; left: 0; bottom: 0;
  width: min(40vw, 280px); height: min(38vh, 168px);
  padding-left: env(safe-area-inset-left, 0px); padding-bottom: env(safe-area-inset-bottom, 0px);
  display: grid; place-items: center;
}
.ws-steer-rail {
  width: 82%; height: 13px; border-radius: 7px;
  background: rgba(10,14,18,0.6); border: 1px solid rgba(150,170,190,0.22);
  position: relative;
}
.ws-steer-rail::before, .ws-steer-rail::after {
  content: ''; position: absolute; top: 50%; width: 1px; height: 22px;
  background: rgba(150,170,190,0.3); transform: translateY(-50%);
}
.ws-steer-rail::before { left: 50%; }
.ws-knob {
  position: absolute; top: 50%; left: 50%; width: 62px; height: 62px; border-radius: 50%;
  transform: translate(-50%, -50%); background: rgba(24,32,40,0.82);
  border: 2px solid rgba(79,210,255,0.55); box-shadow: 0 0 18px rgba(79,210,255,0.18);
  display: grid; place-items: center; font-size: 10px; letter-spacing: 0.12em;
  color: rgba(200,215,230,0.8); transition: border-color 120ms ease;
}
.ws-steer.on .ws-knob { border-color: #4fd2ff; background: rgba(30,46,58,0.9); }

.ws-cluster {
  position: absolute; right: 0; bottom: 0;
  padding-right: max(10px, env(safe-area-inset-right, 0px));
  padding-bottom: max(10px, env(safe-area-inset-bottom, 0px));
  display: grid; gap: 8px;
  grid-template-columns: auto auto auto;
  /* SWAP spans the brake and throttle columns so it sits directly under the
     thumb that was just holding GO, and never overflows its track. */
  grid-template-areas: "boost swap swap" "hbrk brake go";
  align-items: end;
}
.ws-btn {
  display: grid; place-items: center; text-align: center;
  border-radius: 50%; border: 2px solid rgba(170,190,210,0.55);
  background: rgba(10,14,18,0.82); color: #e2eaf2;
  font-size: 10px; letter-spacing: 0.08em; line-height: 1.15;
  box-shadow: 0 2px 10px rgba(0,0,0,0.45), inset 0 0 0 1px rgba(255,255,255,0.05);
  transition: transform 90ms ease, background 90ms ease, border-color 90ms ease;
}
.ws-btn:active, .ws-btn.on { transform: scale(0.93); }
.ws-go   { grid-area: go;   width: min(19vh, 86px); height: min(19vh, 86px); font-size: 14px;
           border-color: rgba(143,217,79,0.85); background: rgba(24,40,18,0.82); }
.ws-go.on { background: rgba(143,217,79,0.34); border-color: #8fd94f; }
.ws-brake{ grid-area: brake; width: min(15vh, 68px); height: min(15vh, 68px);
           border-color: rgba(255,120,100,0.8); background: rgba(40,18,16,0.82); }
.ws-brake.on { background: rgba(255,120,100,0.34); border-color: #ff7864; }
.ws-hbrk { grid-area: hbrk; width: min(15vh, 68px); height: min(15vh, 68px);
           border-color: rgba(255,166,61,0.8); background: rgba(42,30,12,0.82); }
.ws-hbrk.on { background: rgba(255,166,61,0.36); border-color: #ffa63d; }
.ws-boost{ grid-area: boost; width: min(12vh, 56px); height: min(12vh, 56px); font-size: 9px;
           border-color: rgba(79,210,255,0.7); background: rgba(14,32,42,0.82); }
.ws-swap {
  grid-area: swap; width: auto; min-width: 0; height: min(12vh, 54px); border-radius: 27px;
  font-size: clamp(12px, 3.2vw, 16px); letter-spacing: 0.16em; font-weight: 600;
  border: 2px solid #4fd2ff; background: rgba(20,48,64,0.86); color: #dff4ff;
  box-shadow: 0 0 22px rgba(79,210,255,0.28), 0 2px 10px rgba(0,0,0,0.45);
}
.ws-swap.end-b { border-color: #ffa63d; background: rgba(58,38,16,0.78); color: #ffe6c4;
                 box-shadow: 0 0 22px rgba(255,166,61,0.22); }
.ws-swap.locked { opacity: 0.4; }

/* Collapsed to a single MENU tap by default: the secondary controls are not
   worth the screen they would take beside the steering pad and the cluster. */
.ws-util {
  position: absolute; left: 46%; bottom: max(6px, env(safe-area-inset-bottom, 0px));
  transform: translateX(-50%);
  display: flex; flex-direction: column; align-items: center; gap: 6px;
}
.ws-util-row { display: none; gap: 5px; }
.ws-util.open .ws-util-row { display: flex; }
.ws-util button {
  min-width: 40px; height: 34px; padding: 0 7px; border-radius: 17px;
  border: 1px solid rgba(170,190,210,0.4); background: rgba(10,14,18,0.78);
  color: rgba(205,218,232,0.92); font-size: 9px; letter-spacing: 0.1em;
}
.ws-util button:active { background: rgba(79,210,255,0.26); }
.ws-util-toggle { min-width: 52px !important; }
.ws-util.open .ws-util-toggle { border-color: #4fd2ff; color: #dff4ff; }

.ws-rotate {
  position: absolute; inset: 0; display: none; place-items: center; text-align: center;
  background: rgba(7,9,11,0.92); color: rgba(210,222,235,0.9); font-size: 13px;
  letter-spacing: 0.1em; padding: 24px; line-height: 1.7;
}
@media (orientation: portrait) and (max-height: 760px) { .ws-rotate { display: grid; } }
@media (prefers-reduced-motion: reduce) { .ws-btn { transition: none; } }
`;

export function shouldUseTouch() {
  const q = new URLSearchParams(location.search).get('touch');
  if (q === '1') return true;
  if (q === '0') return false;
  // (pointer: coarse) reports the PRIMARY pointer, so a touchscreen laptop with
  // a mouse attached correctly stays on the keyboard build. ?touch=1 forces it.
  return window.matchMedia('(pointer: coarse)').matches
    || window.matchMedia('(hover: none)').matches;
}

export function createTouch(host = document.body) {
  const state = { throttle: 0, brake: 0, steer: 0, handbrake: false, active: false };
  const want = { throttle: 0, brake: 0, handbrake: false };
  const taps = new Set();
  const api = {
    state,
    enabled: false,
    tapped(name) {
      if (taps.has(name)) { taps.delete(name); return true; }
      return false;
    },
    update(dt) {
      const rise = dt * 6.5, fall = dt * 8.0;
      state.throttle = approach(state.throttle, want.throttle, rise, fall);
      state.brake = approach(state.brake, want.brake, rise * 1.6, fall * 1.6);
      state.handbrake = want.handbrake;
      return state;
    },
    setEnd(end, locked) {
      if (!swapBtn) return;
      swapBtn.classList.toggle('end-b', end === 'B');
      swapBtn.classList.toggle('locked', !!locked);
      swapBtn.textContent = `SWAP → ${end === 'A' ? 'B' : 'A'}`;
    },
    destroy() { root.remove(); style.remove(); },
  };

  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);

  const root = document.createElement('div');
  root.className = 'ws-touch';
  root.innerHTML = `
    <div class="ws-steer" aria-label="steering"><div class="ws-steer-rail"><div class="ws-knob">STEER</div></div></div>
    <div class="ws-cluster">
      <button class="ws-swap" data-tap="swap" aria-label="swap ends">SWAP → B</button>
      <button class="ws-btn ws-boost" data-tap="boost" aria-label="boost">BOOST</button>
      <button class="ws-btn ws-hbrk" data-hold="handbrake" aria-label="handbrake">H&#8209;BRK</button>
      <button class="ws-btn ws-brake" data-hold="brake" aria-label="brake">BRAKE</button>
      <button class="ws-btn ws-go" data-hold="throttle" aria-label="throttle">GO</button>
    </div>
    <div class="ws-util">
      <div class="ws-util-row">
        <button data-tap="recover">RESET</button>
        <button data-tap="camera">CAM</button>
        <button data-tap="assist">AI</button>
        <button data-tap="tune">TUNE</button>
        <button data-tap="pause">II</button>
      </div>
      <button class="ws-util-toggle" aria-expanded="false">MENU</button>
    </div>
    <div class="ws-rotate">ROTATE TO LANDSCAPE<br>Whiplash Shift wants the wide view.</div>`;
  host.appendChild(root);

  const swapBtn = root.querySelector('.ws-swap');

  // --- hold buttons -------------------------------------------------------
  for (const btn of root.querySelectorAll('[data-hold]')) {
    const key = HOLDS[btn.dataset.hold];
    const set = (on) => {
      if (key === 'handbrake') want.handbrake = on;
      else want[key] = on ? 1 : 0;
      btn.classList.toggle('on', on);
    };
    btn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      // Capture keeps the button held when the thumb slides off it. Synthetic
      // events (tests) have no active pointer, so this is allowed to fail.
      try { btn.setPointerCapture(e.pointerId); } catch { /* no active pointer */ }
      set(true);
    });
    const release = (e) => { e.preventDefault(); set(false); };
    btn.addEventListener('pointerup', release);
    btn.addEventListener('pointercancel', release);
    btn.addEventListener('lostpointercapture', () => set(false));
  }

  // --- secondary menu -----------------------------------------------------
  const util = root.querySelector('.ws-util');
  const utilToggle = root.querySelector('.ws-util-toggle');
  utilToggle.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    const open = util.classList.toggle('open');
    utilToggle.setAttribute('aria-expanded', String(open));
  });

  // --- tap buttons --------------------------------------------------------
  for (const btn of root.querySelectorAll('[data-tap]')) {
    btn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      taps.add(btn.dataset.tap);
      btn.classList.add('on');
    });
    const off = () => btn.classList.remove('on');
    btn.addEventListener('pointerup', off);
    btn.addEventListener('pointercancel', off);
  }

  // --- steering -----------------------------------------------------------
  // Relative stick: steering is measured from wherever the thumb lands, so
  // putting a thumb down never snaps the wheel to full lock.
  const zone = root.querySelector('.ws-steer');
  const knob = root.querySelector('.ws-knob');
  let steerId = null, originX = 0;
  const TRAVEL = 68;

  zone.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    steerId = e.pointerId;
    originX = e.clientX;
    try { zone.setPointerCapture(e.pointerId); } catch { /* no active pointer */ }
    zone.classList.add('on');
  });
  zone.addEventListener('pointermove', (e) => {
    if (e.pointerId !== steerId) return;
    e.preventDefault();
    const raw = (e.clientX - originX) / TRAVEL;
    state.steer = Math.max(-1, Math.min(1, raw));
    knob.style.transform = `translate(calc(-50% + ${state.steer * 46}px), -50%)`;
  });
  const endSteer = (e) => {
    if (e && e.pointerId !== steerId) return;
    steerId = null;
    state.steer = 0;
    knob.style.transform = 'translate(-50%, -50%)';
    zone.classList.remove('on');
  };
  zone.addEventListener('pointerup', endSteer);
  zone.addEventListener('pointercancel', endSteer);
  zone.addEventListener('lostpointercapture', () => endSteer());

  state.active = true;
  api.enabled = true;
  return api;
}

function approach(cur, target, rise, fall) {
  if (target > cur) return Math.min(target, cur + rise);
  if (target < cur) return Math.max(target, cur - fall);
  return cur;
}
