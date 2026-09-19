// Tiny WebAudio layer: engine tone, tyre slip noise, swap clunk, callout blips.
// Everything is synthesised, so there are no assets to load.

export function createAudio() {
  let ctx = null, master = null;
  let engine = null, engineGain = null, sub = null, subGain = null;
  let noiseGain = null;
  let enabled = true, started = false;

  function start() {
    if (started) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) { enabled = false; return; }
    ctx = new AC();
    master = ctx.createGain();
    master.gain.value = 0.32;
    master.connect(ctx.destination);

    engine = ctx.createOscillator();
    engine.type = 'sawtooth';
    engine.frequency.value = 60;
    engineGain = ctx.createGain();
    engineGain.gain.value = 0;
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 1400;
    engine.connect(engineGain).connect(lp).connect(master);
    engine.start();

    sub = ctx.createOscillator();
    sub.type = 'square';
    sub.frequency.value = 30;
    subGain = ctx.createGain();
    subGain.gain.value = 0;
    sub.connect(subGain).connect(master);
    sub.start();

    // tyre-slip noise bed
    const len = ctx.sampleRate * 2;
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    const src = ctx.createBufferSource();
    src.buffer = buf; src.loop = true;
    const bp = ctx.createBiquadFilter();
    bp.type = 'bandpass'; bp.frequency.value = 900; bp.Q.value = 0.8;
    noiseGain = ctx.createGain();
    noiseGain.gain.value = 0;
    src.connect(bp).connect(noiseGain).connect(master);
    src.start();

    started = true;
  }

  function blip(freq, dur, type = 'square', vol = 0.16) {
    if (!started || !enabled) return;
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, ctx.currentTime);
    g.gain.setValueAtTime(vol, ctx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0008, ctx.currentTime + dur);
    o.connect(g).connect(master);
    o.start();
    o.stop(ctx.currentTime + dur + 0.02);
  }

  return {
    start,
    get ready() { return started; },
    toggle() { enabled = !enabled; if (master) master.gain.value = enabled ? 0.32 : 0; return enabled; },
    get enabled() { return enabled; },
    /** rpmish 0..1, load 0..1, slip 0..1, endB flips the timbre lower/rougher */
    update(rpmish, load, slip, endB) {
      if (!started || !enabled) return;
      const base = endB ? 42 : 68;
      const top = endB ? 190 : 340;
      engine.frequency.setTargetAtTime(base + (top - base) * rpmish, ctx.currentTime, 0.05);
      engineGain.gain.setTargetAtTime(0.05 + 0.13 * load, ctx.currentTime, 0.08);
      sub.frequency.setTargetAtTime((base + (top - base) * rpmish) * 0.5, ctx.currentTime, 0.05);
      subGain.gain.setTargetAtTime(endB ? 0.05 + 0.07 * load : 0.02, ctx.currentTime, 0.1);
      noiseGain.gain.setTargetAtTime(0.014 + 0.1 * slip, ctx.currentTime, 0.05);
    },
    swapClunk() { blip(150, 0.13, 'square', 0.22); blip(74, 0.26, 'sawtooth', 0.18); },
    callout() { blip(880, 0.06, 'square', 0.09); },
    warn() { blip(420, 0.1, 'square', 0.13); },
    reward() { blip(660, 0.07); setTimeout(() => blip(990, 0.12), 70); },
    hit() { blip(110, 0.3, 'sawtooth', 0.22); },
    shot() { blip(1500 + Math.random() * 300, 0.03, 'square', 0.05); },
  };
}
