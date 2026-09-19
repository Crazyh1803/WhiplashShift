// Surface table + the GDD's per-end performance modifiers, in one editable place.

export const SID = {
  TARMAC: 0,
  RUMBLE: 1,
  GRAVEL: 2,
  MUD: 3,
  BOULDER: 4,
  ICE: 5,
  WATER: 6,
  OIL: 7,
  OFF: 8,
};

// `grip`  multiplies the tyre friction coefficient.
// `roll`  rolling-resistance coefficient (x normal load, opposing wheel travel).
// `dmg`   chassis damage per second at speed when the wrong end is driving.
export const SURFACES = [
  { id: SID.TARMAC,  key: 'tarmac',  name: 'TARMAC',  grip: 1.00, roll: 0.016, dmg: 0, fill: '#484e5b', edge: '#5d6474', grain: '#525969' },
  { id: SID.RUMBLE,  key: 'rumble',  name: 'RUMBLE',  grip: 0.86, roll: 0.060, dmg: 0, fill: '#6d5536', edge: '#8d6e46', grain: '#7b603d' },
  { id: SID.GRAVEL,  key: 'gravel',  name: 'GRAVEL',  grip: 0.62, roll: 0.115, dmg: 1, fill: '#6f6855', edge: '#867c66', grain: '#7c745e' },
  { id: SID.MUD,     key: 'mud',     name: 'MUD BOG', grip: 0.40, roll: 0.430, dmg: 4, fill: '#55402a', edge: '#6d5235', grain: '#5f4830' },
  { id: SID.BOULDER, key: 'boulder', name: 'BOULDERS',grip: 0.55, roll: 0.190, dmg: 5, fill: '#5f5f6b', edge: '#767682', grain: '#6a6a76' },
  { id: SID.ICE,     key: 'ice',     name: 'ICE',     grip: 0.20, roll: 0.012, dmg: 0, fill: '#5d8194', edge: '#7ba3b8', grain: '#6b91a6' },
  { id: SID.WATER,   key: 'water',   name: 'WATER',   grip: 0.44, roll: 0.520, dmg: 6, fill: '#2f5a69', edge: '#3f7488', grain: '#376578' },
  { id: SID.OIL,     key: 'oil',     name: 'OIL',     grip: 0.13, roll: 0.010, dmg: 0, fill: '#191921', edge: '#26262f', grain: '#1f1f28' },
  { id: SID.OFF,     key: 'off',     name: 'OFF TRACK',grip: 0.50, roll: 0.330, dmg: 2, fill: '#2c3726', edge: '#36432e', grain: '#313d2a' },
];

// Encoded into the red channel of the baked surface map. 25 apart so blended
// edge pixels can be detected and rejected rather than mis-read as a third id.
export const KEY_STEP = 25;

const D = { top: 1, accel: 1, grip: 1 };

// End A: built for tarmac, helpless in the soft stuff.
// End B: built for the soft stuff, hopeless on tarmac.
// The GDD's headline numbers (A +30% top speed on tarmac / -70% accel on mud,
// B +40% traction on mud / -40% top speed on tarmac) are the anchors here.
export const END_MOD = {
  A: {
    tarmac:  { top: 1.30, accel: 1.00, grip: 1.00 },
    rumble:  { top: 1.05, accel: 0.85, grip: 0.90 },
    gravel:  { top: 0.74, accel: 0.52, grip: 0.68 },
    mud:     { top: 0.52, accel: 0.30, grip: 0.52 },
    boulder: { top: 0.48, accel: 0.34, grip: 0.58 },
    ice:     { top: 0.92, accel: 0.48, grip: 0.86 },
    water:   { top: 0.44, accel: 0.26, grip: 0.50 },
    oil:     { top: 1.00, accel: 0.40, grip: 0.70 },
    off:     { top: 0.58, accel: 0.40, grip: 0.62 },
  },
  B: {
    tarmac:  { top: 0.60, accel: 0.88, grip: 0.84 },
    rumble:  { top: 0.80, accel: 1.00, grip: 1.05 },
    gravel:  { top: 0.96, accel: 1.14, grip: 1.28 },
    mud:     { top: 1.00, accel: 1.20, grip: 1.40 },
    boulder: { top: 0.92, accel: 1.18, grip: 1.32 },
    ice:     { top: 0.78, accel: 0.86, grip: 1.10 },
    water:   { top: 0.90, accel: 1.05, grip: 1.25 },
    oil:     { top: 0.85, accel: 0.55, grip: 0.80 },
    off:     { top: 0.94, accel: 1.10, grip: 1.22 },
  },
};

export function endMod(end, sid) {
  const s = SURFACES[sid];
  return (END_MOD[end] && END_MOD[end][s.key]) || D;
}

// Which end the track wants you on, used for gates, copilot callouts and damage.
export const PREFERRED_END = {
  tarmac: 'A', rumble: 'A', ice: 'A', oil: 'A',
  gravel: 'B', mud: 'B', boulder: 'B', water: 'B', off: 'B',
};

export function preferredEnd(sid) {
  return PREFERRED_END[SURFACES[sid].key] || 'A';
}
