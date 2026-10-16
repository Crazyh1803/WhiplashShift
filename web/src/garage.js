export const VEHICLES = [
  {
    id: 'blackjack', name: 'BLACKJACK X-17', className: 'INTERCEPTOR', origin: 'REDLINE DIVISION',
    description: 'Balanced twin-vector hardware. Fast enough to hunt, armored enough to finish.',
    image: './assets/vehicles/spy-hunter.jpg', color: '#ff4d2e',
    stats: { speed: 78, accel: 76, handling: 82, armor: 72 },
    physics: { topSpeed: 1, drive: 1, grip: 1, mass: 1, brake: 1 },
  },
  {
    id: 'boilerfang', name: 'BOILERFANG 88', className: 'DREADNOUGHT', origin: 'FOUNDRY NINE',
    description: 'Brutal traction and plate steel. It arrives late, then refuses to leave.',
    image: './assets/vehicles/steam-punk.jpg', color: '#ffb238',
    stats: { speed: 58, accel: 84, handling: 60, armor: 96 },
    physics: { topSpeed: .88, drive: 1.12, grip: 1.04, mass: 1.14, brake: .94 },
  },
  {
    id: 'helix', name: 'HELIX WRAITH', className: 'BIO-RACER', origin: 'NULL LABS',
    description: 'Living aero wraps a surgical chassis. Unstable-looking. Disturbingly precise.',
    image: './assets/vehicles/r-type.jpg', color: '#ef3c67',
    stats: { speed: 94, accel: 88, handling: 72, armor: 48 },
    physics: { topSpeed: 1.10, drive: 1.08, grip: .94, mass: .88, brake: .96 },
  },
  {
    id: 'ramjet', name: 'RAMJET K-6', className: 'BRAWLER', origin: 'MOTOR CULT',
    description: 'A street-fight drivetrain in a split-body shell. Point it through the problem.',
    image: './assets/vehicles/dodge.jpg', color: '#b9ef45',
    stats: { speed: 72, accel: 91, handling: 65, armor: 82 },
    physics: { topSpeed: .96, drive: 1.11, grip: .96, mass: 1.08, brake: .92 },
  },
  {
    id: 'knifeedge', name: 'KNIFEEDGE XR', className: 'RAZORBUG', origin: 'APEX WORKS',
    description: 'Half sand rail, half supercar. Changes direction before the driver finishes thinking.',
    image: './assets/vehicles/hot-wheels.jpg', color: '#27d7ff',
    stats: { speed: 86, accel: 80, handling: 96, armor: 42 },
    physics: { topSpeed: 1.04, drive: 1.02, grip: 1.10, mass: .90, brake: 1.08 },
  },
  {
    id: 'deadbolt', name: 'DEADBOLT RS', className: 'ROAD WARDEN', origin: 'BLACK COUNTY',
    description: 'Old-world iron, new-world violence. Calm on entry and merciless under braking.',
    image: './assets/vehicles/80s-ford.jpg', color: '#8cb6ff',
    stats: { speed: 74, accel: 68, handling: 86, armor: 78 },
    physics: { topSpeed: .98, drive: .96, grip: 1.07, mass: 1.05, brake: 1.08 },
  },
  {
    id: 'nightshift', name: 'NIGHTSHIFT 84', className: 'OUTRUNNER', origin: 'GHOST MOTOR CO.',
    description: 'High-speed contraband geometry. Light, eager, and allergic to straight lines.',
    image: './assets/vehicles/80s.jpg', color: '#c378ff',
    stats: { speed: 90, accel: 82, handling: 88, armor: 52 },
    physics: { topSpeed: 1.08, drive: 1.04, grip: 1.05, mass: .92, brake: 1.02 },
  },
];

const statLabels = { speed: 'TOP SPEED', accel: 'LAUNCH', handling: 'CONTROL', armor: 'CHASSIS' };

export function createGarage({ root, onStart }) {
  if (!root) throw new Error('Garage root is required');
  const element = document.createElement('section');
  element.className = 'garage-shell';
  element.setAttribute('aria-label', 'Whiplash Shift vehicle selection');
  element.innerHTML = `
    <div class="garage-noise" aria-hidden="true"></div>
    <header class="garage-brand">
      <span class="garage-eyebrow">REDLINE AUTHORITY // GRID ACCESS</span>
      <h1 class="garage-title"><span>WHIPLASH</span> SHIFT</h1>
      <p class="garage-tagline">DRIVE BOTH WAYS. SURVIVE EITHER ONE.</p>
    </header>
    <div class="garage-layout">
      <div class="garage-stage">
        <div class="garage-image-frame">
          <div class="garage-scan" aria-hidden="true"></div>
          <img class="garage-image" alt="">
          <span class="garage-stamp">CHASSIS // CLEARED</span>
          <span class="garage-model-no"></span>
        </div>
        <button class="garage-nav garage-prev" type="button" aria-label="Previous vehicle">&#8592;</button>
        <button class="garage-nav garage-next" type="button" aria-label="Next vehicle">&#8594;</button>
        <div class="garage-roster" role="tablist" aria-label="Vehicle roster"></div>
      </div>
      <div class="garage-dossier">
        <div class="garage-kicker">SELECT CHASSIS</div>
        <h2 class="garage-name"></h2>
        <div class="garage-class"></div>
        <p class="garage-description"></p>
        <div class="garage-rule"></div>
        <div class="garage-stats" aria-label="Vehicle statistics"></div>
        <div class="garage-cpu"><i></i><span>CPU ROSTER</span><b>RANDOMIZED ON IGNITION</b></div>
        <label class="garage-field" for="garage-callsign">
          <span>PILOT CALLSIGN</span>
          <input id="garage-callsign" autocomplete="nickname" maxlength="16" spellcheck="false">
        </label>
        <div class="garage-validation" role="alert" aria-live="polite"></div>
        <button class="garage-start" type="button"><span>IGNITE</span><b>ENTER GRID</b><i>&#9654;</i></button>
        <div class="garage-hints"><span>&larr; &rarr; SELECT</span><span>ENTER CONFIRM</span><span>BUILD 0.9.7 // NO MERCY</span></div>
      </div>
    </div>`;
  root.appendChild(element);

  const $ = (s) => element.querySelector(s);
  const image = $('.garage-image');
  const name = $('.garage-name');
  const klass = $('.garage-class');
  const description = $('.garage-description');
  const modelNo = $('.garage-model-no');
  const roster = $('.garage-roster');
  const stats = $('.garage-stats');
  const input = $('#garage-callsign');
  const validation = $('.garage-validation');
  const prev = $('.garage-prev');
  const next = $('.garage-next');
  const startButton = $('.garage-start');
  let index = 0;
  let launched = false;
  const rosterButtons = VEHICLES.map((vehicle, i) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'garage-roster-dot';
    button.setAttribute('role', 'tab');
    button.setAttribute('aria-label', `Select ${vehicle.name}`);
    button.addEventListener('click', () => select(i));
    roster.appendChild(button);
    return button;
  });

  function select(nextIndex) {
    if (launched) return;
    index = (nextIndex + VEHICLES.length) % VEHICLES.length;
    const vehicle = VEHICLES[index];
    element.style.setProperty('--vehicle-accent', vehicle.color);
    image.src = vehicle.image;
    image.alt = `${vehicle.name} technical blueprint`;
    name.textContent = vehicle.name;
    klass.textContent = `${vehicle.className} // ${vehicle.origin}`;
    description.textContent = vehicle.description;
    modelNo.textContent = `${String(index + 1).padStart(2, '0')} / ${String(VEHICLES.length).padStart(2, '0')}`;
    rosterButtons.forEach((button, i) => {
      button.classList.toggle('is-active', i === index);
      button.setAttribute('aria-selected', i === index ? 'true' : 'false');
      button.tabIndex = i === index ? 0 : -1;
    });
    stats.replaceChildren(...Object.entries(vehicle.stats).map(([key, value]) => {
      const row = document.createElement('div');
      row.className = 'garage-stat';
      row.innerHTML = `<div><span>${statLabels[key]}</span><b>${value}</b></div><div class="garage-stat-track"><i class="garage-stat-fill"></i></div>`;
      requestAnimationFrame(() => row.querySelector('.garage-stat-fill').style.width = `${value}%`);
      return row;
    }));
  }

  function finish(callsign, vehicle, delay) {
    if (launched) return;
    launched = true;
    element.classList.add('is-launching');
    element.querySelectorAll('button,input').forEach((control) => { control.disabled = true; });
    setTimeout(() => {
      element.classList.add('is-hidden');
      onStart({ callsign, vehicle });
    }, delay);
  }

  function start() {
    const callsign = input.value.trim().toUpperCase();
    if (!callsign) {
      validation.textContent = 'CALLSIGN REQUIRED // ACCESS DENIED';
      input.focus();
      element.classList.remove('garage-shake');
      requestAnimationFrame(() => element.classList.add('garage-shake'));
      return;
    }
    localStorage.setItem('ws.callsign', callsign);
    validation.textContent = '';
    finish(callsign, VEHICLES[index], 550);
  }

  function startForTests() {
    if (launched) return;
    launched = true;
    element.classList.add('is-hidden');
    onStart({ callsign: 'TEST', vehicle: VEHICLES[0] });
  }
  function onKey(event) {
    if (launched) return;
    if (event.key === 'ArrowLeft') { event.preventDefault(); select(index - 1); }
    if (event.key === 'ArrowRight') { event.preventDefault(); select(index + 1); }
    if (event.key === 'Enter') { event.preventDefault(); start(); }
  }
  function onInput() { input.value = input.value.toUpperCase(); validation.textContent = ''; }
  prev.addEventListener('click', () => select(index - 1));
  next.addEventListener('click', () => select(index + 1));
  startButton.addEventListener('click', start);
  input.addEventListener('input', onInput);
  window.addEventListener('keydown', onKey);
  input.value = (localStorage.getItem('ws.callsign') || 'ROADGHOST').slice(0, 16).toUpperCase();
  select(0);

  return {
    element,
    get selected() { return VEHICLES[index]; },
    start,
    startForTests,
    destroy() { window.removeEventListener('keydown', onKey); element.remove(); },
  };
}
