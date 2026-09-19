// Whiplash Shift - central tuning block.
// Every number that affects feel lives here so it can be moved from the in-game panel.

export const T = {
  chassis: {
    mass: 1400,
    length: 4.6,
    width: 2.0,
    halfBase: 1.6,      // wheel pair offset from centre of mass, along body X
    halfTrack: 0.9,     // wheel offset from centreline, along body Y
    yawDamp: 0.9,
    aeroDrag: 0.82,
  },

  // End A lives at +X in body space. End B lives at -X.
  A: {
    key: 'A',
    name: 'ASPHALT RACER',
    blurb: 'slicks \u00b7 low aero',
    maxDrive: 9800,
    topSpeed: 58,
    tireGrip: 1.38,
    maxSteer: 0.50,
    steerRate: 3.6,
    steerFalloff: 0.62,
    downforce: 0.80,
    brake: 15000,
    color: '#4fd2ff',
  },
  B: {
    key: 'B',
    name: 'MUD BRAWLER',
    blurb: 'treads \u00b7 raised 4WD',
    maxDrive: 17500,
    topSpeed: 34,
    tireGrip: 1.02,
    maxSteer: 0.64,
    steerRate: 2.9,
    steerFalloff: 0.42,
    downforce: 0.0,
    brake: 11500,
    color: '#ffa63d',
  },

  swap: {
    engage: 0.26,          // transmission ramp: drive torque 0 -> 1
    cooldown: 0.60,
    whiplashMinSpeed: 22,  // m/s to qualify as a tactical swap
    whiplashWindow: 1.8,   // s to resolve the slide / reversal
    boostReward: 0.34,
  },

  grip: {
    slipK: 1.15,           // lateral saturation sharpness
    handbrakeGrip: 0.44,   // inactive pair lateral grip under handbrake
    handbrakeLock: 0.85,   // inactive pair longitudinal lock under handbrake
  },

  boost: { force: 7600, duration: 1.4 },

  ai: {
    lookahead: 3.2,        // seconds of centreline the copilot reads ahead
    assist: 0.55,          // counter-steer authority during SLIDE_ASSIST (additive only)
    turretTraverse: 3.4,   // rad/s
    turretRange: 150,
    turretArc: Math.PI / 2, // half-arc, so 180 deg total off the inactive end
    fireInterval: 0.085,
    oilCooldown: 6.0,
  },

  damage: {
    gateMiss: 9,
    mismatchRate: 9,       // per second, wrong end at speed on a hostile surface
    missile: 16,
    max: 100,
  },

  rivals: {
    count: 2,
    skill: 0.86,
    missileInterval: 7.5,
  },
};

// Slider spec for the live tuning panel: [path, label, min, max, step]
export const TUNABLE = [
  ['A.maxDrive', 'End A drive (N)', 2000, 20000, 100],
  ['A.topSpeed', 'End A top speed (m/s)', 20, 90, 1],
  ['A.tireGrip', 'End A tyre grip', 0.4, 2.0, 0.01],
  ['A.maxSteer', 'End A steer lock (rad)', 0.2, 0.9, 0.01],
  ['A.downforce', 'End A downforce', 0, 2, 0.05],
  ['B.maxDrive', 'End B drive (N)', 4000, 32000, 100],
  ['B.topSpeed', 'End B top speed (m/s)', 15, 70, 1],
  ['B.tireGrip', 'End B tyre grip', 0.4, 2.0, 0.01],
  ['B.maxSteer', 'End B steer lock (rad)', 0.2, 0.9, 0.01],
  ['swap.engage', 'Swap engage ramp (s)', 0, 1.2, 0.01],
  ['swap.cooldown', 'Swap cooldown (s)', 0, 2.0, 0.05],
  ['grip.slipK', 'Lateral slip sharpness', 0.2, 4, 0.05],
  ['grip.handbrakeGrip', 'Handbrake lat. grip', 0.05, 1, 0.01],
  ['grip.handbrakeLock', 'Handbrake long. lock', 0, 1.5, 0.01],
  ['chassis.aeroDrag', 'Aero drag', 0, 3, 0.02],
  ['chassis.yawDamp', 'Yaw damping', 0, 4, 0.05],
  ['ai.assist', 'Copilot assist strength', 0, 1, 0.02],
];

function get(path) { return path.split('.').reduce((o, k) => o[k], T); }
function set(path, val) {
  const parts = path.split('.');
  const last = parts.pop();
  parts.reduce((o, k) => o[k], T)[last] = val;
}

export function buildTuningPanel(root) {
  const body = document.createElement('div');
  body.className = 'tune-body';
  for (const [path, label, min, max, step] of TUNABLE) {
    const row = document.createElement('label');
    row.className = 'tune-row';
    const name = document.createElement('span');
    name.className = 'tune-name';
    name.textContent = label;
    const val = document.createElement('span');
    val.className = 'tune-val';
    val.textContent = get(path);
    const input = document.createElement('input');
    input.type = 'range';
    input.min = min; input.max = max; input.step = step;
    input.value = get(path);
    input.addEventListener('input', () => {
      const n = parseFloat(input.value);
      set(path, n);
      val.textContent = n;
    });
    row.append(name, val, input);
    body.appendChild(row);
  }
  const reset = document.createElement('button');
  reset.className = 'tune-reset';
  reset.textContent = 'reload defaults';
  reset.addEventListener('click', () => location.reload());
  body.appendChild(reset);
  root.appendChild(body);
  return body;
}
