// Keyboard state. Analogue-ish ramps so keys don't feel like on/off switches.

const MAP = {
  throttle: ['KeyW', 'ArrowUp'],
  brake: ['KeyS', 'ArrowDown'],
  left: ['KeyA', 'ArrowLeft'],
  right: ['KeyD', 'ArrowRight'],
  handbrake: ['ShiftLeft', 'ShiftRight'],
};

const TAP = {
  swap: 'Space',
  boost: 'KeyE',
  recover: 'KeyR',
  camera: 'KeyC',
  assist: 'KeyF',
  pause: 'KeyP',
  tune: 'KeyT',
  help: 'KeyH',
};

export function createInput(target = window) {
  const down = new Set();
  const taps = new Set();
  const state = { throttle: 0, brake: 0, steer: 0, handbrake: false, anyKey: false };

  const held = (action) => MAP[action].some((c) => down.has(c));

  target.addEventListener('keydown', (e) => {
    if (e.repeat) { e.preventDefault(); return; }
    down.add(e.code);
    state.anyKey = true;
    for (const [name, code] of Object.entries(TAP)) if (e.code === code) taps.add(name);
    if (Object.values(MAP).flat().includes(e.code) || Object.values(TAP).includes(e.code)) e.preventDefault();
  });
  target.addEventListener('keyup', (e) => down.delete(e.code));
  target.addEventListener('blur', () => down.clear());

  return {
    state,
    down,
    /** Advance the analogue ramps. Call once per frame. */
    update(dt) {
      const rise = dt * 5.5, fall = dt * 7.0;
      state.throttle = approach(state.throttle, held('throttle') ? 1 : 0, rise, fall);
      state.brake = approach(state.brake, held('brake') ? 1 : 0, rise * 1.6, fall * 1.6);
      const want = (held('right') ? 1 : 0) - (held('left') ? 1 : 0);
      state.steer = approach(state.steer, want, dt * 4.2, dt * 6.5);
      state.handbrake = held('handbrake');
      return state;
    },
    /** True once per press. */
    tapped(name) {
      if (taps.has(name)) { taps.delete(name); return true; }
      return false;
    },
    clearTaps() { taps.clear(); },
  };
}

function approach(cur, want, rise, fall) {
  if (want > cur) return Math.min(want, cur + rise);
  if (want < cur) return Math.max(want, cur - fall);
  return cur;
}

export const CONTROLS = [
  ['W / ↑', 'throttle'],
  ['S / ↓', 'brake · reverse'],
  ['A D / ← →', 'steer'],
  ['SPACE', 'SWAP ENDS'],
  ['SHIFT', 'handbrake'],
  ['E', 'boost'],
  ['R', 'recover'],
  ['C', 'camera swing / snap'],
  ['F', 'copilot assist'],
  ['T', 'tuning panel'],
  ['P', 'pause'],
];
