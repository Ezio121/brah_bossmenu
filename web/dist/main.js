const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'qb-management';

const state = {
  token: null,
  menuType: 'boss',
  modules: {},
  permissions: {},
  job: null,
  orgProfileHint: null,
  orgProfile: null,
  groupStyle: null,
  locale: {},
  settings: {},
  hasFinance: true,
  grades: [],
  balance: 0,
  employees: [],
  nearby: [],
  ledger: [],
  activeView: 'overview',
  cache: {}
};

const app = document.getElementById('app');
const jobLabel = document.getElementById('job-label');
const jobSub = document.getElementById('job-sub');
const navList = document.getElementById('nav-list');
const closeBtn = document.getElementById('close-btn');
const stashBtn = document.getElementById('stash-btn');
const refreshBtn = document.getElementById('refresh-btn');
const balanceEl = document.getElementById('balance');
const employeeCountEl = document.getElementById('employee-count');
const nearbyCountEl = document.getElementById('nearby-count');
const toast = document.getElementById('toast');
const cameraOverlay = document.getElementById('camera-overlay');
const cameraOverlayLabel = document.getElementById('camera-overlay-label');
const cameraOverlayTime = document.getElementById('camera-overlay-time');
const cameraOverlayProvider = document.getElementById('camera-overlay-provider');
const inFlight = new Set();
let cameraOverlayTicker = null;

function t(key, fallback, vars = {}) {
  let value = state.locale && state.locale[key] ? state.locale[key] : (fallback || key);
  value = String(value);
  Object.keys(vars || {}).forEach((name) => {
    value = value.replaceAll(`{${name}}`, String(vars[name]));
  });
  return value;
}

const VIEWS = [
  { id: 'overview', labelKey: 'nav.overview', label: 'Overview' },
  { id: 'members', labelKey: 'nav.members', label: 'Employees/Members' },
  { id: 'ranks', labelKey: 'nav.ranks', label: 'Ranks' },
  { id: 'permissions', labelKey: 'nav.permissions', label: 'Permissions' },
  { id: 'profiles', labelKey: 'nav.profiles', label: 'Profiles' },
  { id: 'inventory', labelKey: 'nav.inventory', label: 'Inventory/Stash' },
  { id: 'uniforms', labelKey: 'nav.uniforms', label: 'Uniforms' },
  { id: 'applications', labelKey: 'nav.applications', label: 'Applications' },
  { id: 'announcements', labelKey: 'nav.announcements', label: 'Announcements' },
  { id: 'cameras', labelKey: 'nav.cameras', label: 'Cameras' },
  { id: 'markers', labelKey: 'nav.markers', label: 'Markers' },
  { id: 'garage', labelKey: 'nav.garage', label: 'Garage' },
  { id: 'taxes', labelKey: 'nav.taxes', label: 'Taxes/Bills' },
  { id: 'analytics', labelKey: 'nav.analytics', label: 'Analytics' },
  { id: 'logs', labelKey: 'nav.logs', label: 'Logs' },
  { id: 'webhooks', labelKey: 'nav.webhooks', label: 'Webhooks' },
  { id: 'territories', labelKey: 'nav.territories', label: 'Gang Territories', gangOnly: true },
  { id: 'rackets', labelKey: 'nav.rackets', label: 'Gang Rackets', gangOnly: true },
  { id: 'workshop', labelKey: 'nav.workshop', label: 'Hidden Workshop', gangOnly: true },
  { id: 'contracts', labelKey: 'nav.contracts', label: 'Gang Contracts', gangOnly: true },
  { id: 'admin', labelKey: 'nav.admin', label: 'Admin Panel' }
];

const VIEW_ICONS = {
  overview: '◎',
  members: '◉',
  ranks: '▦',
  permissions: '▤',
  profiles: '◍',
  inventory: '▣',
  uniforms: '◈',
  applications: '◬',
  announcements: '⌁',
  cameras: '◌',
  markers: '⌖',
  garage: '◧',
  taxes: '◫',
  analytics: '◴',
  logs: '☰',
  territories: '◰',
  rackets: '◱',
  contracts: '◲',
  admin: '⌘'
};

const ARCHETYPE_SYMBOLS = {
  corporate: '◎',
  law: '⛨',
  medical: '✚',
  mechanic: '◈',
  dealer: '◉',
  hospitality: '◍',
  logistics: '◧',
  security: '⌖',
  gang_street: '◬',
  gang_biker: '◴',
  gang_cartel: '◲',
  gang_mafia: '◱'
};

const ORG_ARCHETYPES = {
  corporate: {
    id: 'corporate',
    title: 'Executive Operations',
    subtitle: 'Commercial command and growth orchestration',
    deck: 'Executive Command Deck',
    opsLabel: 'Commercial Operations',
    memberTabLabel: 'Workforce',
    membersLabel: 'Staff',
    nearbyLabel: 'Candidates',
    financeLabel: 'Treasury',
    ledgerLabel: 'Finance Activity Feed',
    financeInput: 'Transfer amount',
    depositLabel: 'Deposit',
    withdrawLabel: 'Withdraw',
    focus: ['Revenue Control', 'Hiring Velocity', 'Operational Risk'],
    quickHints: ['Track rank progression for retention.', 'Use applications to build a pre-vetted pipeline.', 'Audit financial variance weekly.'],
    colors: { a: '#d7b56a', b: '#345f8a', c: '#0d2740' },
    keywords: ['business', 'company', 'corp', 'executive', 'manager', 'director', 'ceo', 'retail', 'office']
  },
  law: {
    id: 'law',
    title: 'Law Enforcement Command',
    subtitle: 'Operational readiness and incident governance',
    deck: 'Tactical Command Grid',
    opsLabel: 'Public Safety Operations',
    memberTabLabel: 'Officers',
    membersLabel: 'Officers',
    nearbyLabel: 'Field Units',
    financeLabel: 'Department Budget',
    ledgerLabel: 'Budget & Action Feed',
    financeInput: 'Budget adjustment amount',
    depositLabel: 'Allocate',
    withdrawLabel: 'Consume',
    focus: ['Response Coverage', 'Rank Discipline', 'Case Logging'],
    quickHints: ['Keep command grades tightly permissioned.', 'Use logs to detect unusual rank jumps.', 'Maintain active unit coverage in peak hours.'],
    colors: { a: '#73d0ff', b: '#5f8fd8', c: '#132f59' },
    keywords: ['police', 'sheriff', 'trooper', 'state', 'lspd', 'bcso', 'sasp', 'pd', 'swat', 'officer', 'deputy', 'chief', 'captain', 'sergeant']
  },
  medical: {
    id: 'medical',
    title: 'Medical Administration',
    subtitle: 'Clinical staffing and service continuity',
    deck: 'Medical Operations Deck',
    opsLabel: 'Healthcare Operations',
    memberTabLabel: 'Medical Staff',
    membersLabel: 'Medical Staff',
    nearbyLabel: 'On-call Staff',
    financeLabel: 'Medical Budget',
    ledgerLabel: 'Funding Activity',
    financeInput: 'Allocation amount',
    depositLabel: 'Fund',
    withdrawLabel: 'Spend',
    focus: ['Staff Availability', 'Shift Stability', 'Supply Spend'],
    quickHints: ['Prioritize profile notes for recurring incidents.', 'Track payroll drift against roster size.', 'Use announcements for shift-wide updates.'],
    colors: { a: '#79e2c5', b: '#4aa7b8', c: '#124250' },
    keywords: ['ambulance', 'ems', 'hospital', 'medic', 'doctor', 'nurse', 'clinic', 'trauma']
  },
  mechanic: {
    id: 'mechanic',
    title: 'Workshop Administration',
    subtitle: 'Shop throughput and service workforce control',
    deck: 'Workshop Command Deck',
    opsLabel: 'Service Operations',
    memberTabLabel: 'Technicians',
    membersLabel: 'Technicians',
    nearbyLabel: 'Applicants Nearby',
    financeLabel: 'Shop Treasury',
    ledgerLabel: 'Service Ledger Feed',
    financeInput: 'Service fund amount',
    depositLabel: 'Add Funds',
    withdrawLabel: 'Use Funds',
    focus: ['Bay Utilization', 'Staff Capacity', 'Expense Control'],
    quickHints: ['Use rank permissions to split lead tech responsibilities.', 'Watch inventory movement for leakage.', 'Keep quick hire flow active around workshop zones.'],
    colors: { a: '#f4bf72', b: '#ca7a2c', c: '#47321a' },
    keywords: ['mechanic', 'tuner', 'auto', 'garage', 'bennys', 'repair', 'customs', 'workshop']
  },
  dealer: {
    id: 'dealer',
    title: 'Dealership Command',
    subtitle: 'Sales force coordination and revenue oversight',
    deck: 'Dealership Command Deck',
    opsLabel: 'Sales Operations',
    memberTabLabel: 'Sales Team',
    membersLabel: 'Sales Team',
    nearbyLabel: 'Prospects Nearby',
    financeLabel: 'Sales Treasury',
    ledgerLabel: 'Sales Ledger Feed',
    financeInput: 'Sales account amount',
    depositLabel: 'Deposit',
    withdrawLabel: 'Withdraw',
    focus: ['Conversion Flow', 'Sales Ranks', 'Margin Protection'],
    quickHints: ['Pair analytics with promotions for staff optimization.', 'Use payroll overrides for top performers.', 'Keep application review cycle short.'],
    colors: { a: '#f0d083', b: '#8f6ad8', c: '#2b2148' },
    keywords: ['dealer', 'dealership', 'vehicle', 'cars', 'motors', 'luxury', 'autos', 'sales']
  },
  hospitality: {
    id: 'hospitality',
    title: 'Hospitality Operations',
    subtitle: 'Guest experience and venue workforce management',
    deck: 'Venue Command Deck',
    opsLabel: 'Venue Operations',
    memberTabLabel: 'Crew',
    membersLabel: 'Crew Members',
    nearbyLabel: 'Walk-in Staff',
    financeLabel: 'Venue Treasury',
    ledgerLabel: 'Venue Finance Feed',
    financeInput: 'Venue transfer amount',
    depositLabel: 'Deposit',
    withdrawLabel: 'Withdraw',
    focus: ['Staff Coverage', 'Shift Readiness', 'Revenue Flow'],
    quickHints: ['Pin announcements for shift updates.', 'Use profile notes for reliability tracking.', 'Audit withdrawals with reasons enabled.'],
    colors: { a: '#e6a86f', b: '#be5474', c: '#4b243a' },
    keywords: ['restaurant', 'bar', 'club', 'nightclub', 'casino', 'hotel', 'lounge', 'bahama']
  },
  logistics: {
    id: 'logistics',
    title: 'Logistics Command',
    subtitle: 'Delivery network and labor coordination',
    deck: 'Dispatch Operations Deck',
    opsLabel: 'Logistics Operations',
    memberTabLabel: 'Drivers',
    membersLabel: 'Drivers & Crew',
    nearbyLabel: 'Available Drivers',
    financeLabel: 'Fleet Treasury',
    ledgerLabel: 'Dispatch Ledger Feed',
    financeInput: 'Fleet budget amount',
    depositLabel: 'Allocate',
    withdrawLabel: 'Consume',
    focus: ['Route Capacity', 'Shift Throughput', 'Cost Stability'],
    quickHints: ['Keep marker and garage data clean for dispatch flow.', 'Use payroll intervals for predictable payouts.', 'Track repeated no-show activity in profiles.'],
    colors: { a: '#8ac5ff', b: '#4c7abd', c: '#213556' },
    keywords: ['trucker', 'logistics', 'delivery', 'transport', 'dispatch', 'fleet', 'cargo']
  },
  security: {
    id: 'security',
    title: 'Security Administration',
    subtitle: 'Protective operations and guard command control',
    deck: 'Security Command Deck',
    opsLabel: 'Security Operations',
    memberTabLabel: 'Guards',
    membersLabel: 'Guard Units',
    nearbyLabel: 'Deployable Units',
    financeLabel: 'Security Budget',
    ledgerLabel: 'Security Action Feed',
    financeInput: 'Security budget amount',
    depositLabel: 'Allocate',
    withdrawLabel: 'Use',
    focus: ['Coverage Reliability', 'Duty Discipline', 'Incident Visibility'],
    quickHints: ['Harden rank permissions for promotion/fire actions.', 'Monitor suspicious action logs from admin panel.', 'Use activity feed to identify inactive commanders.'],
    colors: { a: '#9fd7f2', b: '#447693', c: '#1e3b4d' },
    keywords: ['security', 'guard', 'protection', 'watch', 'patrol', 'response']
  },
  gang_street: {
    id: 'gang_street',
    title: 'Street Command',
    subtitle: 'Territory pressure and crew orchestration',
    deck: 'Street Operations Deck',
    opsLabel: 'Gang Operations',
    memberTabLabel: 'Crew',
    membersLabel: 'Crew Members',
    nearbyLabel: 'Nearby Recruits',
    financeLabel: 'Cash Locker',
    ledgerLabel: 'Street Activity Feed',
    financeInput: 'Cash locker amount',
    depositLabel: 'Stash',
    withdrawLabel: 'Pull',
    focus: ['Territory Hold', 'Member Discipline', 'Notoriety Growth'],
    quickHints: ['Tie promotions to territory participation.', 'Use contracts to drive organized activity.', 'Keep graffiti cooldowns enforced to prevent spam.'],
    colors: { a: '#e7b86a', b: '#b24f3e', c: '#4a241f' },
    keywords: ['gang', 'street', 'hood', 'crew', 'block', 'set', 'fam', 'og']
  },
  gang_biker: {
    id: 'gang_biker',
    title: 'Motor Club Command',
    subtitle: 'Chapter leadership and club operations',
    deck: 'Chapter Operations Deck',
    opsLabel: 'Motor Club Operations',
    memberTabLabel: 'Riders',
    membersLabel: 'Club Members',
    nearbyLabel: 'Prospects Nearby',
    financeLabel: 'Club Treasury',
    ledgerLabel: 'Club Ledger Feed',
    financeInput: 'Club transfer amount',
    depositLabel: 'Deposit',
    withdrawLabel: 'Withdraw',
    focus: ['Chapter Order', 'Recruit Funnel', 'Club Economy'],
    quickHints: ['Use custom ranks for prospect progression.', 'Track cross-rank permission drift weekly.', 'Review rackets for passive income health.'],
    colors: { a: '#f0c788', b: '#8c4b36', c: '#3b261f' },
    keywords: ['mc', 'motor', 'bike', 'biker', 'chapter', 'road', 'rider', 'president', 'sergeant at arms']
  },
  gang_cartel: {
    id: 'gang_cartel',
    title: 'Cartel Operations',
    subtitle: 'Network command and expansion control',
    deck: 'Cartel Operations Deck',
    opsLabel: 'Network Operations',
    memberTabLabel: 'Operatives',
    membersLabel: 'Operatives',
    nearbyLabel: 'Runners Nearby',
    financeLabel: 'Network Treasury',
    ledgerLabel: 'Network Ledger Feed',
    financeInput: 'Network amount',
    depositLabel: 'Deposit',
    withdrawLabel: 'Withdraw',
    focus: ['Territory Network', 'Contract Throughput', 'Cashflow Stealth'],
    quickHints: ['Use notoriety costs to throttle expansion speed.', 'Audit every high-value withdrawal reason.', 'Rotate rank permissions across lieutenants cautiously.'],
    colors: { a: '#f4ca7f', b: '#3f8f5d', c: '#1f412f' },
    keywords: ['cartel', 'sinaloa', 'familia', 'sicario', 'jefe', 'narcos', 'drug', 'plaza']
  },
  gang_mafia: {
    id: 'gang_mafia',
    title: 'Syndicate Command',
    subtitle: 'Family hierarchy and enterprise control',
    deck: 'Syndicate Operations Deck',
    opsLabel: 'Syndicate Operations',
    memberTabLabel: 'Associates',
    membersLabel: 'Family Members',
    nearbyLabel: 'Associates Nearby',
    financeLabel: 'Family Treasury',
    ledgerLabel: 'Family Ledger Feed',
    financeInput: 'Family account amount',
    depositLabel: 'Deposit',
    withdrawLabel: 'Withdraw',
    focus: ['Hierarchy Integrity', 'Contract Yield', 'Capital Security'],
    quickHints: ['Use protected system ranks for immutable top roles.', 'Enforce reason-required removals for accountability.', 'Monitor suspicious actions for spoof attempts.'],
    colors: { a: '#d3b37a', b: '#915f5f', c: '#35242b' },
    keywords: ['mafia', 'mob', 'family', 'consigliere', 'underboss', 'capo', 'don', 'syndicate']
  }
};

function normalizeWords(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

function inferOrgProfile(menuType, job, grades, hint) {
  if (hint && typeof hint === 'object' && hint.id && ORG_ARCHETYPES[hint.id]) {
    return { ...ORG_ARCHETYPES[hint.id], ...hint };
  }
  const gradeNames = (Array.isArray(grades) ? grades : []).map((g) => g?.name || '').join(' ');
  const corpus = `${job?.name || ''} ${job?.label || ''} ${gradeNames}`.toLowerCase();
  const words = normalizeWords(corpus);
  const menu = menuType === 'gang' ? 'gang' : 'boss';

  const candidates = menu === 'gang'
    ? ['gang_street', 'gang_biker', 'gang_cartel', 'gang_mafia']
    : ['law', 'medical', 'mechanic', 'dealer', 'hospitality', 'logistics', 'security', 'corporate'];

  let bestId = menu === 'gang' ? 'gang_street' : 'corporate';
  let bestScore = -1;
  for (const id of candidates) {
    const def = ORG_ARCHETYPES[id];
    const keys = def?.keywords || [];
    let score = 0;
    for (const key of keys) {
      if (corpus.includes(String(key).toLowerCase())) score += 3;
      if (words.includes(String(key).toLowerCase())) score += 2;
    }
    if (menu === 'gang' && id.startsWith('gang_')) score += 1;
    if (score > bestScore) {
      bestScore = score;
      bestId = id;
    }
  }

  return { ...ORG_ARCHETYPES[bestId] };
}

function applyTheme(profile) {
  const colors = profile?.colors || {};
  const a = colors.a || '#d7b56a';
  const b = colors.b || '#345f8a';
  const c = colors.c || '#0d2740';
  app.style.setProperty('--org-a', a);
  app.style.setProperty('--org-b', b);
  app.style.setProperty('--org-c', c);
  app.style.setProperty('--org-a-soft', toRgba(a, 0.24));
  app.style.setProperty('--org-b-soft', toRgba(b, 0.26));
  app.style.setProperty('--org-c-soft', toRgba(c, 0.32));
}

function toRgba(hex, alpha) {
  const raw = String(hex || '').replace('#', '').trim();
  if (!/^[0-9a-fA-F]{6}$/.test(raw)) return `rgba(215,181,106,${Number(alpha) || 0.2})`;
  const r = parseInt(raw.slice(0, 2), 16);
  const g = parseInt(raw.slice(2, 4), 16);
  const b = parseInt(raw.slice(4, 6), 16);
  return `rgba(${r},${g},${b},${Number(alpha) || 0.2})`;
}

function formatMoney(value) {
  const n = Number(value) || 0;
  return `$${n.toLocaleString()}`;
}

function compactNumber(value) {
  const n = Number(value) || 0;
  if (Math.abs(n) >= 1000000) return `${(n / 1000000).toFixed(1)}M`;
  if (Math.abs(n) >= 1000) return `${(n / 1000).toFixed(1)}K`;
  return String(Math.round(n));
}

function sparklineSvg(values, opts = {}) {
  const points = Array.isArray(values) ? values.map((v) => Number(v) || 0) : [];
  if (points.length < 2) {
    return `<svg class="sparkline" viewBox="0 0 300 120" preserveAspectRatio="none"><text x="12" y="62" fill="#7f92ab" font-size="12">No trend data</text></svg>`;
  }
  const width = 300;
  const height = 120;
  const min = Math.min(...points);
  const max = Math.max(...points);
  const span = Math.max(1, max - min);
  const coords = points.map((v, i) => {
    const x = (i / (points.length - 1)) * width;
    const y = height - (((v - min) / span) * (height - 16) + 8);
    return `${x.toFixed(2)},${y.toFixed(2)}`;
  }).join(' ');
  const stroke = opts.stroke || '#e2bf6a';
  const fill = opts.fill || 'rgba(226,191,106,0.16)';
  return `
    <svg class="sparkline" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
      <polyline points="0,${height - 1} ${coords} ${width},${height - 1}" fill="${fill}" stroke="none"></polyline>
      <polyline points="${coords}" fill="none" stroke="${stroke}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"></polyline>
      <line x1="0" y1="${height - 1}" x2="${width}" y2="${height - 1}" stroke="rgba(120,146,177,0.34)" stroke-width="1"></line>
    </svg>
  `;
}

function ledgerSeries(limit = 14) {
  const rows = (state.ledger || []).slice(0, limit).reverse();
  return rows.map((r) => {
    const action = String(r.action || '').toLowerCase();
    const amount = Number(r.amount || 0);
    if (action.includes('withdraw') || action.includes('remove')) return -Math.abs(amount);
    if (action.includes('deposit') || action.includes('add')) return Math.abs(amount);
    return amount;
  });
}

function styleToText(styleObj) {
  if (!styleObj || typeof styleObj !== 'object') return '';
  return Object.entries(styleObj)
    .filter(([, v]) => v !== undefined && v !== null && String(v) !== '')
    .map(([k, v]) => `${k.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase())}:${String(v)}`)
    .join(';');
}

function showToast(message, bad = false) {
  toast.textContent = String(message || '');
  toast.style.borderLeftColor = bad ? '#a44d4d' : '#c8a24f';
  toast.classList.remove('hidden');
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => toast.classList.add('hidden'), 2600);
}

let dialogRoot = null;
function ensureDialog() {
  if (dialogRoot) return dialogRoot;
  dialogRoot = document.createElement('div');
  dialogRoot.id = 'bm-dialog';
  dialogRoot.className = 'bm-dialog hidden';
  dialogRoot.innerHTML = `
    <div class="bm-dialog-card">
      <h3 id="bm-dialog-title">${escapeHtml(t('dialog.input', 'Input'))}</h3>
      <p id="bm-dialog-text" class="muted"></p>
      <input id="bm-dialog-input" />
      <div class="row" style="justify-content:flex-end; margin-top:10px;">
        <button id="bm-dialog-cancel" class="btn ghost">${escapeHtml(t('button.cancel', 'Cancel'))}</button>
        <button id="bm-dialog-ok" class="btn">${escapeHtml(t('button.confirm', 'Confirm'))}</button>
      </div>
    </div>
  `;
  document.body.appendChild(dialogRoot);
  return dialogRoot;
}

function askInput(opts = {}) {
  const root = ensureDialog();
  const title = root.querySelector('#bm-dialog-title');
  const text = root.querySelector('#bm-dialog-text');
  const input = root.querySelector('#bm-dialog-input');
  const btnCancel = root.querySelector('#bm-dialog-cancel');
  const btnOk = root.querySelector('#bm-dialog-ok');
  title.textContent = String(opts.title || t('dialog.input', 'Input'));
  text.textContent = String(opts.text || '');
  input.type = opts.type === 'number' ? 'number' : 'text';
  input.placeholder = String(opts.placeholder || '');
  input.value = opts.value !== undefined && opts.value !== null ? String(opts.value) : '';
  if (opts.type === 'number' && opts.min !== undefined) input.min = String(opts.min);
  else input.removeAttribute('min');
  if (opts.type === 'number' && opts.max !== undefined) input.max = String(opts.max);
  else input.removeAttribute('max');
  btnOk.textContent = String(opts.confirmLabel || t('button.confirm', 'Confirm'));
  btnCancel.textContent = String(opts.cancelLabel || t('button.cancel', 'Cancel'));
  root.classList.remove('hidden');
  input.focus();
  input.select();

  return new Promise((resolve) => {
    const done = (ok) => {
      root.classList.add('hidden');
      btnCancel.removeEventListener('click', onCancel);
      btnOk.removeEventListener('click', onOk);
      input.removeEventListener('keydown', onKey);
      if (!ok) return resolve(null);
      resolve(String(input.value || ''));
    };
    const onCancel = () => done(false);
    const onOk = () => done(true);
    const onKey = (ev) => {
      if (ev.key === 'Escape') done(false);
      if (ev.key === 'Enter') done(true);
    };
    btnCancel.addEventListener('click', onCancel);
    btnOk.addEventListener('click', onOk);
    input.addEventListener('keydown', onKey);
  });
}

function post(endpoint, payload = {}) {
  return fetch(`https://${resource}/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload)
  }).then((r) => r.json());
}

async function lockRun(name, fn) {
  const key = String(name || '');
  if (inFlight.has(key)) return { ok: false, error: 'busy' };
  inFlight.add(key);
  try {
    return await fn();
  } finally {
    inFlight.delete(key);
  }
}

function moduleAction(action, payload = {}) {
  return post('moduleAction', { action, payload });
}

function patchCore(data) {
  if (!data || typeof data !== 'object') return;
  if ('balance' in data) state.balance = Number(data.balance) || 0;
  if ('employees' in data && Array.isArray(data.employees)) state.employees = data.employees;
  if ('nearby' in data && Array.isArray(data.nearby)) state.nearby = data.nearby;
  if ('ledger' in data && Array.isArray(data.ledger)) state.ledger = data.ledger;
  if ('grades' in data && Array.isArray(data.grades)) state.grades = data.grades;
  if ('permissions' in data && data.permissions && typeof data.permissions === 'object') state.permissions = data.permissions;
  state.orgProfile = inferOrgProfile(state.menuType, state.job, state.grades, state.orgProfileHint);
  applyTheme(state.orgProfile);
}

function viewEl(id) {
  return document.getElementById(`view-${id}`);
}

async function setView(id) {
  state.activeView = id;
  VIEWS.forEach((v) => {
    const el = viewEl(v.id);
    if (!el) return;
    el.classList.toggle('hidden', v.id !== id);
  });
  navList.querySelectorAll('.nav-btn').forEach((btn) => btn.classList.toggle('active', btn.dataset.view === id));
  await ensureViewData(id);
  renderCurrentView();
}

function allowedView(v) {
  if (v.gangOnly && state.menuType !== 'gang') return false;
  if (v.id === 'profiles' && state.modules.EmployeeProfiles !== true) return false;
  if (v.id === 'inventory' && state.modules.BusinessInventory !== true) return false;
  if (v.id === 'uniforms' && state.modules.Uniforms !== true) return false;
  if (v.id === 'applications' && state.modules.Applications !== true) return false;
  if (v.id === 'announcements' && state.modules.Announcements !== true) return false;
  if (v.id === 'cameras' && state.modules.Cameras !== true) return false;
  if (v.id === 'garage' && state.menuType === 'gang' && state.modules.GangGarages !== true) return false;
  if (v.id === 'taxes' && state.modules.Taxes !== true && state.modules.BillsInvoices !== true) return false;
  if (v.id === 'analytics' && state.modules.Analytics !== true) return false;
  if (v.id === 'webhooks' && (state.modules.Webhooks !== true || state.permissions.manage_webhooks !== true)) return false;
  if (v.id === 'territories' && state.modules.GangTerritories !== true) return false;
  if (v.id === 'rackets' && state.modules.GangRackets !== true) return false;
  if (v.id === 'workshop' && state.modules.HiddenWorkshop !== true) return false;
  if (v.id === 'contracts' && state.modules.GangContracts !== true) return false;
  if (v.id === 'admin' && state.modules.AdminPanel !== true) return false;
  return true;
}

function renderNav() {
  const items = VIEWS.filter(allowedView);
  const symbol = ARCHETYPE_SYMBOLS[state.orgProfile?.id] || '◎';
  navList.innerHTML = items.map((v) => {
    let label = t(v.labelKey || `nav.${v.id}`, v.label);
    if (v.id === 'members' && state.orgProfile?.memberTabLabel) label = state.orgProfile.memberTabLabel;
    if (v.id === 'overview') label = t('nav.overview', 'Command Deck');
    if (v.id === 'cameras' && state.menuType === 'boss' && state.orgProfile?.id === 'law') label = t('nav.dispatch_cams', 'Dispatch Cams');
    const icon = VIEW_ICONS[v.id] || symbol;
    return `<button class="nav-btn ${state.activeView === v.id ? 'active' : ''}" data-view="${v.id}"><span class="nav-ico">${icon}</span><span class="nav-label">${label}</span></button>`;
  }).join('');
  navList.querySelectorAll('.nav-btn').forEach((btn) => {
    btn.addEventListener('click', () => setView(btn.dataset.view));
  });
  if (!items.some((x) => x.id === state.activeView)) {
    state.activeView = items[0] ? items[0].id : 'overview';
  }
}

function renderTop() {
  const p = state.orgProfile || inferOrgProfile(state.menuType, state.job, state.grades, state.orgProfileHint);
  state.orgProfile = p;
  applyTheme(p);
  const symbol = ARCHETYPE_SYMBOLS[p?.id] || '◎';
  const title = state.menuType === 'gang' ? 'Gang Suite' : 'Boss Suite';
  jobLabel.textContent = `${symbol} ${state.job?.label || state.job?.name || 'Organization'} ${title}`;
  jobSub.textContent = `${symbol} ${p.subtitle || (state.menuType === 'gang' ? t('app.subtitle.gang', 'Gang command and ecosystem panel') : t('app.subtitle.boss', 'Business command and administration panel'))}`;
  balanceEl.textContent = formatMoney(state.balance);
  employeeCountEl.textContent = String(state.employees.length);
  nearbyCountEl.textContent = String(state.nearby.length);
  const cards = document.querySelectorAll('.content-top .stat span');
  if (cards[0]) cards[0].textContent = p.financeLabel || t('label.balance', 'Balance');
  if (cards[1]) cards[1].textContent = p.membersLabel || t('label.members', 'Members');
  if (cards[2]) cards[2].textContent = p.nearbyLabel || t('label.nearby', 'Nearby');
  closeBtn.textContent = t('button.close', 'Close');
  refreshBtn.textContent = t('button.refresh', 'Refresh');
  stashBtn.textContent = t('button.boss_stash', 'Boss Stash');
  const hasStashPerm = state.permissions?.view_inventory === true
    || state.permissions?.deposit_items === true
    || state.permissions?.withdraw_items === true
    || state.permissions?.lock_inventory === true;
  const canStash = state.menuType === 'boss' && state.settings?.stashAvailable === true && hasStashPerm;
  if (stashBtn) {
    stashBtn.classList.toggle('hidden', !canStash);
  }
  const style = styleToText(state.groupStyle);
  if (style) {
    app.querySelector('.content').style.cssText = style;
  } else {
    app.querySelector('.content').style.cssText = '';
  }
}

function memberRow(emp) {
  const badgeStyle = styleToText(emp.grade?.style || {});
  return `
    <div class="list-item" data-emp="${emp.identifier}">
      <div class="list-main">
        <strong>${emp.online ? t('label.online', 'Online') : t('label.offline', 'Offline')} | ${emp.name}</strong>
        <small>${emp.identifier} | <span class="badge" style="${badgeStyle}">${emp.grade?.name || t('label.members', 'Member')}</span></small>
      </div>
      <div class="row">
        <select class="grade-select">
          ${state.grades.map((g) => `<option value="${g.level}" ${Number(g.level) === Number(emp.grade?.level) ? 'selected' : ''}>${g.name}</option>`).join('')}
        </select>
        <button class="btn small set-grade">${escapeHtml(t('button.set', 'Set'))}</button>
        <button class="btn small danger fire-member">${escapeHtml(t('button.fire', 'Fire'))}</button>
      </div>
    </div>
  `;
}

function nearbyRow(row) {
  return `
    <div class="list-item" data-src="${row.source}">
      <div class="list-main">
        <strong>${row.name}</strong>
        <small>${row.identifier} | ${Number(row.distance || 0).toFixed(2)}m</small>
      </div>
      <button class="btn small hire-member">${escapeHtml(t('button.hire', 'Hire'))}</button>
    </div>
  `;
}

function renderOverview() {
  const el = viewEl('overview');
  const profile = state.orgProfile || inferOrgProfile(state.menuType, state.job, state.grades, state.orgProfileHint);
  const symbol = ARCHETYPE_SYMBOLS[profile?.id] || '◎';
  const canFinance = state.hasFinance && state.menuType === 'boss';
  const online = (state.employees || []).filter((x) => x.online).length;
  const offline = Math.max(0, (state.employees || []).length - online);
  const ledger = (state.ledger || []).slice(0, 18);
  const ledgerTrend = ledgerSeries(16);
  const nearbyTop = (state.nearby || []).slice(0, 6);
  const totalIn = ledger.filter((x) => String(x.action || '').toLowerCase().includes('deposit')).reduce((a, b) => a + (Number(b.amount) || 0), 0);
  const totalOut = ledger.filter((x) => String(x.action || '').toLowerCase().includes('withdraw')).reduce((a, b) => a + (Number(b.amount) || 0), 0);
  const net = totalIn - totalOut;

  el.innerHTML = `
    <div class="command-grid">
      <article class="card hero-panel command-hero">
        <div class="hero-title">
          <h2><span class="nav-ico">${symbol}</span> ${escapeHtml(state.job?.label || state.job?.name || 'Organization')} - ${escapeHtml(profile.deck || 'Command Deck')}</h2>
          <span class="pill">${escapeHtml(profile.opsLabel || t('label.operations', state.menuType === 'gang' ? 'Gang Operations' : 'Business Operations'))}</span>
        </div>
        <div class="row">
          <span class="pill">${escapeHtml(profile.focus?.[0] || t('label.operations', 'Operations'))}</span>
          <span class="pill">${escapeHtml(profile.focus?.[1] || t('label.workforce', 'Workforce'))}</span>
          <span class="pill">${escapeHtml(profile.focus?.[2] || t('label.finance', 'Finance'))}</span>
        </div>
        ${canFinance ? `
          <div class="row">
            <input id="ov-amount" type="number" min="1" placeholder="${escapeHtml(profile.financeInput || t('placeholder.transaction_amount', 'Transaction amount'))}" />
            <button id="ov-deposit" class="btn">${escapeHtml(profile.depositLabel || t('button.deposit', 'Deposit'))}</button>
            <button id="ov-withdraw" class="btn danger">${escapeHtml(profile.withdrawLabel || t('button.withdraw', 'Withdraw'))}</button>
            <span class="pill">${escapeHtml(t('label.max', 'Max'))}: ${formatMoney(state.settings.maxAmount || 0)}</span>
          </div>
        ` : `
          <div class="row">
            <span class="pill">${escapeHtml(t('msg.finance_disabled', 'Finance disabled for this menu mode'))}</span>
          </div>
        `}
        <div class="hero-chart">
          ${sparklineSvg(ledgerTrend.length > 1 ? ledgerTrend : [0, 0], { stroke: 'var(--org-a)', fill: 'var(--org-a-soft)' })}
          <div class="row" style="justify-content:space-between; margin-top:6px;">
            <span class="pill">In: ${formatMoney(totalIn)}</span>
            <span class="pill">Out: ${formatMoney(totalOut)}</span>
            <span class="pill">Net: ${formatMoney(net)}</span>
          </div>
        </div>
      </article>

      <article class="card command-side">
        <h3>${escapeHtml(profile.title || 'Operations Brief')}</h3>
        <p class="muted">${escapeHtml(profile.subtitle || '')}</p>
        <div class="kpi-wall">
          <div class="kpi-card">
            <div class="kpi-label">${escapeHtml(t('label.active', 'Active'))} ${escapeHtml(profile.membersLabel || t('label.members', 'Members'))}</div>
            <div class="kpi-value">${compactNumber(online)}</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-label">${escapeHtml(t('label.offline', 'Offline'))} ${escapeHtml(profile.membersLabel || t('label.members', 'Members'))}</div>
            <div class="kpi-value">${compactNumber(offline)}</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-label">${escapeHtml(profile.nearbyLabel || t('label.nearby', 'Nearby'))}</div>
            <div class="kpi-value">${compactNumber((state.nearby || []).length)}</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-label">${escapeHtml(profile.financeLabel || t('label.current_balance', 'Current Balance'))}</div>
            <div class="kpi-value">${compactNumber(state.balance)}</div>
          </div>
        </div>
      </article>

      <article class="card span-8 dense-list">
        <h3>${escapeHtml(profile.ledgerLabel || 'Live Ledger Feed')}</h3>
        <div class="list">${ledger.map((row) => `
          <div class="list-item">
            <div class="list-main">
              <strong>${String(row.action || '').toUpperCase()} ${formatMoney(row.amount)}</strong>
              <small>${row.actor_identifier || 'unknown'} | ${row.created_at || ''}</small>
            </div>
          </div>
        `).join('') || `<p class="muted">${escapeHtml(t('empty.no_ledger', 'No ledger entries yet.'))}</p>`}</div>
      </article>

      <article class="card span-4">
        <h3>${escapeHtml(profile.nearbyLabel || 'Nearby Quick Actions')}</h3>
        <div class="list">${nearbyTop.map((row) => `
          <div class="list-item" data-src="${row.source}">
            <div class="list-main">
              <strong>${escapeHtml(row.name || 'Unknown')}</strong>
              <small>${escapeHtml(row.identifier || '')} | ${Number(row.distance || 0).toFixed(1)}m</small>
            </div>
            <button class="btn small hire-member">${escapeHtml(t('button.hire', 'Hire'))}</button>
          </div>
        `).join('') || `<p class="muted">${escapeHtml(t('empty.no_nearby', 'No nearby players.'))}</p>`}</div>
      </article>

      <article class="card span-12 intel-strip">
        <h3>${escapeHtml(t('section.strategic_notes', 'Strategic Notes'))}</h3>
        <div class="intel-list">
          ${(profile.quickHints || []).map((hint) => `<div class="intel-item">${escapeHtml(hint)}</div>`).join('')}
        </div>
      </article>
    </div>
  `;
  el.querySelectorAll('.hire-member').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const src = Number(btn.closest('.list-item').dataset.src);
      const res = await lockRun(`hire:${src}`, () => post('hire', { source: src }));
      if (!res.ok) return showToast(res.error || t('toast.hire_failed', 'Hire failed'), true);
      patchCore(res.data);
      renderTop();
      renderCurrentView();
      showToast(t('toast.player_hired', 'Player hired'));
    });
  });
  if (canFinance) {
    const depositBtn = document.getElementById('ov-deposit');
    const withdrawBtn = document.getElementById('ov-withdraw');
    const amountInput = document.getElementById('ov-amount');
    depositBtn.addEventListener('click', async () => {
      const amount = Number(amountInput.value);
      const res = await lockRun('deposit', () => post('deposit', { amount }));
      if (!res.ok) return showToast(res.error || t('toast.deposit_failed', 'Deposit failed'), true);
      patchCore(res.data);
      renderTop();
      renderCurrentView();
      showToast(t('toast.deposit_complete', 'Deposit complete'));
    });
    withdrawBtn.addEventListener('click', async () => {
      const amount = Number(amountInput.value);
      const reason = (await askInput({ title: t('dialog.withdraw_reason', 'Withdraw Reason'), text: t('dialog.withdraw_reason_text', 'Optional reason for this withdrawal'), value: '' })) || '';
      const res = await lockRun('withdraw', () => post('withdraw', { amount, reason }));
      if (!res.ok) return showToast(res.error || t('toast.withdraw_failed', 'Withdraw failed'), true);
      patchCore(res.data);
      renderTop();
      renderCurrentView();
      showToast(t('toast.withdraw_complete', 'Withdraw complete'));
    });
  }
}

function renderMembers() {
  const el = viewEl('members');
  const active = Array.isArray(state.cache.memberSearch) ? state.cache.memberSearch : state.employees;
  el.innerHTML = `
    <div class="grid-2">
      <article class="card">
        <h3>${escapeHtml(t('section.members', 'Members'))}</h3>
        <div class="row" style="margin-bottom:8px;">
          <input id="member-search" placeholder="${escapeHtml(t('placeholder.search_member', 'Search name / id / rank'))}" />
          <select id="member-online">
            <option value="">${escapeHtml(t('label.all', 'All'))}</option>
            <option value="1">${escapeHtml(t('label.online', 'Online'))}</option>
            <option value="0">${escapeHtml(t('label.offline', 'Offline'))}</option>
          </select>
          <select id="member-sort">
            <option value="rank">Sort: Rank</option>
            <option value="name">Sort: Name</option>
            <option value="join_date">Sort: Join Date</option>
            <option value="last_seen">Sort: Last Seen</option>
          </select>
          <button id="member-search-btn" class="btn small">${escapeHtml(t('button.apply', 'Apply'))}</button>
        </div>
        <div class="list" id="members-list">${active.map((emp) => `
          ${memberRow(emp)}
          <div class="row" style="margin-top:-5px; margin-bottom:8px; justify-content:flex-end;">
            <button class="btn small ghost profile-open" data-id="${emp.identifier}">${escapeHtml(t('button.profile', 'Profile'))}</button>
          </div>
        `).join('') || `<p class="muted">${escapeHtml(t('empty.no_members', 'No members found.'))}</p>`}</div>
      </article>
      <article class="card">
        <h3>${escapeHtml(t('section.nearby_players', 'Nearby Players'))}</h3>
        <div class="list" id="nearby-list">${state.nearby.map(nearbyRow).join('') || `<p class="muted">${escapeHtml(t('empty.no_nearby', 'No nearby players.'))}</p>`}</div>
      </article>
    </div>
  `;
  el.querySelectorAll('.set-grade').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const root = btn.closest('.list-item');
      const identifier = root.dataset.emp;
      const grade = Number(root.querySelector('.grade-select').value);
      const res = await lockRun(`set:${identifier}`, () => post('setGrade', { identifier, grade }));
      if (!res.ok) return showToast(res.error || t('toast.grade_failed', 'Grade update failed'), true);
      patchCore(res.data);
      renderTop();
      renderCurrentView();
      showToast(t('toast.grade_updated', 'Grade updated'));
    });
  });
  el.querySelectorAll('.fire-member').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const root = btn.closest('.list-item');
      const identifier = root.dataset.emp;
      const reason = (await askInput({ title: t('dialog.removal_reason', 'Removal Reason'), text: t('dialog.removal_reason_text', 'Optional reason for removal'), value: '' })) || '';
      const res = await lockRun(`fire:${identifier}`, () => post('fire', { identifier, reason }));
      if (!res.ok) return showToast(res.error || t('toast.removal_failed', 'Removal failed'), true);
      patchCore(res.data);
      renderTop();
      renderCurrentView();
      showToast(t('toast.member_removed', 'Member removed'));
    });
  });
  el.querySelectorAll('.hire-member').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const src = Number(btn.closest('.list-item').dataset.src);
      const res = await lockRun(`hire:${src}`, () => post('hire', { source: src }));
      if (!res.ok) return showToast(res.error || t('toast.hire_failed', 'Hire failed'), true);
      patchCore(res.data);
      renderTop();
      renderCurrentView();
      showToast(t('toast.player_hired', 'Player hired'));
    });
  });
  el.querySelectorAll('.profile-open').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const identifier = btn.dataset.id;
      state.cache.profileSelected = identifier;
      await setView('profiles');
    });
  });
  const searchBtn = document.getElementById('member-search-btn');
  if (searchBtn) {
    searchBtn.addEventListener('click', async () => {
      const search = document.getElementById('member-search').value || '';
      const onlineRaw = document.getElementById('member-online').value;
      const sortBy = document.getElementById('member-sort').value || 'rank';
      const payload = { search, sortBy, sortDir: 'desc' };
      if (onlineRaw === '1') payload.online = true;
      if (onlineRaw === '0') payload.online = false;
      const res = await moduleAction('search_members', payload);
      if (!res.ok) return showToast(res.error || t('toast.search_failed', 'Search failed'), true);
      state.cache.memberSearch = res.data?.employees || [];
      renderCurrentView();
    });
  }
}

function renderRankView() {
  const el = viewEl('ranks');
  const rows = state.cache.ranks || [];
  el.innerHTML = `
    <article class="card">
      <h3>Rank Management</h3>
      <div class="row">
        <input id="new-rank-name" placeholder="Rank Name" />
        <input id="new-rank-grade" type="number" placeholder="Grade" min="0" />
        <select id="new-rank-salary-type">
          <option value="framework">Framework</option>
          <option value="custom">Custom</option>
          <option value="unpaid">Unpaid</option>
        </select>
        <input id="new-rank-salary" type="number" min="0" placeholder="Salary" />
        <button id="create-rank-btn" class="btn">Create Rank</button>
      </div>
      <div class="row" style="margin:8px 0;">
        <input id="rank-from" type="number" min="0" placeholder="From grade" />
        <input id="rank-to" type="number" min="0" placeholder="To grade" />
        <button id="rank-reassign-btn" class="btn small">Reassign Members</button>
      </div>
      <div class="table-wrap" style="margin-top:8px;">
        <table>
          <thead><tr><th>Grade</th><th>Name</th><th>Boss</th><th>Custom</th><th>Assigned</th><th>Actions</th></tr></thead>
          <tbody>
            ${rows.map((r) => `
              <tr>
                <td>${r.level}</td>
                <td>${r.name}</td>
                <td>${r.isBoss ? 'Yes' : 'No'}</td>
                <td>${r.custom ? 'Yes' : 'No'}</td>
                <td>${r.assigned || 0}</td>
                <td>
                  <button class="btn small rank-edit" data-grade="${r.level}" data-name="${escapeHtml(r.name || '')}">Edit</button>
                  ${r.custom ? `<button class="btn small danger rank-del" data-grade="${r.level}">Delete</button>` : ''}
                </td>
              </tr>`).join('')}
          </tbody>
        </table>
      </div>
    </article>
  `;
  const createBtn = document.getElementById('create-rank-btn');
  createBtn.addEventListener('click', async () => {
    const name = document.getElementById('new-rank-name').value;
    const grade = Number(document.getElementById('new-rank-grade').value);
    const salaryType = document.getElementById('new-rank-salary-type').value;
    const salaryAmount = Number(document.getElementById('new-rank-salary').value || 0);
    const res = await moduleAction('create_rank', { name, grade, salaryType, salaryAmount });
    if (!res.ok) return showToast(res.error || 'Rank creation failed', true);
    state.cache.ranks = res.data?.ranks || [];
    renderCurrentView();
    showToast('Rank created');
  });
  document.getElementById('rank-reassign-btn')?.addEventListener('click', async () => {
    const fromGrade = Number(document.getElementById('rank-from').value);
    const toGrade = Number(document.getElementById('rank-to').value);
    const res = await moduleAction('reassign_rank', { fromGrade, toGrade });
    if (!res.ok) return showToast(res.error || 'Reassign failed', true);
    state.cache.ranks = res.data?.ranks || [];
    renderCurrentView();
    showToast('Members reassigned');
  });
  el.querySelectorAll('.rank-edit').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const grade = Number(btn.dataset.grade);
      const currentName = btn.dataset.name || '';
      const name = (await askInput({ title: 'Rank Name', text: 'Updated rank label', value: currentName })) || currentName;
      const newGradeRaw = (await askInput({ title: 'Rank Grade', text: 'Grade number', value: String(grade), type: 'number', min: 0 })) || String(grade);
      const newGrade = Number(newGradeRaw);
      const salaryType = (await askInput({ title: 'Salary Type', text: 'framework / custom / unpaid', value: 'framework' })) || 'framework';
      const salaryAmount = Number((await askInput({ title: 'Salary Amount', value: '0', type: 'number', min: 0 })) || 0);
      const res = await moduleAction('update_rank', { grade, newGrade, name, salaryType, salaryAmount });
      if (!res.ok) return showToast(res.error || 'Rank update failed', true);
      state.cache.ranks = res.data?.ranks || [];
      renderCurrentView();
      showToast('Rank updated');
    });
  });
  el.querySelectorAll('.rank-del').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const grade = Number(btn.dataset.grade);
      const reassignTo = Number((await askInput({ title: 'Reassign Grade', text: 'Target grade for reassignment (0 allowed)', value: '0', type: 'number', min: 0 })) || 0);
      const res = await moduleAction('delete_rank', { grade, reassignTo });
      if (!res.ok) return showToast(res.error || 'Rank delete failed', true);
      state.cache.ranks = res.data?.ranks || [];
      renderCurrentView();
      showToast('Rank deleted');
    });
  });
}

function renderPermissionView() {
  const el = viewEl('permissions');
  const map = state.cache.rankPermissions?.permissions || {};
  const selectedGrade = state.cache.rankPermissions?.grade ?? (state.job?.grade ?? 0);
  el.innerHTML = `
    <article class="card">
      <h3>Rank Permissions</h3>
      <div class="row">
        <span class="pill">Current Grade: ${selectedGrade}</span>
        <select id="perm-grade-select">
          ${state.grades.map((g) => `<option value="${g.level}" ${Number(g.level) === Number(selectedGrade) ? 'selected' : ''}>${g.name} (${g.level})</option>`).join('')}
        </select>
        <button id="perm-load" class="btn small">Load</button>
      </div>
      <div class="table-wrap">
        <table>
          <thead><tr><th>Permission</th><th>Allowed</th><th>Action</th></tr></thead>
          <tbody>
            ${Object.keys(map).map((k) => `
              <tr>
                <td>${k}</td>
                <td>${map[k] ? 'Yes' : 'No'}</td>
                <td><button class="btn small perm-toggle" data-key="${k}" data-val="${map[k] ? '0' : '1'}">${map[k] ? 'Disable' : 'Enable'}</button></td>
              </tr>`).join('')}
          </tbody>
        </table>
      </div>
    </article>
  `;
  document.getElementById('perm-load')?.addEventListener('click', async () => {
    const grade = Number(document.getElementById('perm-grade-select').value);
    const res = await moduleAction('get_rank_permissions', { grade });
    if (!res.ok) return showToast(res.error || 'Failed to load permissions', true);
    state.cache.rankPermissions = res.data || {};
    renderCurrentView();
  });
  el.querySelectorAll('.perm-toggle').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const permission = btn.dataset.key;
      const allowed = btn.dataset.val === '1';
      const grade = Number(document.getElementById('perm-grade-select')?.value ?? selectedGrade);
      const res = await moduleAction('set_rank_permission', { grade, permission, allowed });
      if (!res.ok) return showToast(res.error || 'Permission update failed', true);
      state.cache.rankPermissions = res.data;
      renderCurrentView();
      showToast('Permission updated');
    });
  });
}

function renderJsonView(targetId, title, key, emptyText) {
  const el = viewEl(targetId);
  const rows = state.cache[key] || [];
  el.innerHTML = `
    <article class="card">
      <h3>${title}</h3>
      <div class="table-wrap">
        <table>
          <thead><tr><th>#</th><th>Data</th></tr></thead>
          <tbody>
            ${rows.length ? rows.map((r, i) => `<tr><td>${i + 1}</td><td><pre>${escapeHtml(JSON.stringify(r, null, 2))}</pre></td></tr>`).join('') : `<tr><td colspan="2">${emptyText}</td></tr>`}
          </tbody>
        </table>
      </div>
    </article>
  `;
}

function escapeHtml(text) {
  return String(text || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function localizeDom(root) {
  if (!root || !state.locale) return;
  root.querySelectorAll('input[placeholder], textarea[placeholder]').forEach((el) => {
    const raw = el.getAttribute('placeholder') || '';
    if (raw) el.setAttribute('placeholder', t(`text.${raw}`, raw));
  });
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  nodes.forEach((node) => {
    const raw = String(node.nodeValue || '');
    const trimmed = raw.trim();
    if (!trimmed) return;
    const translated = t(`text.${trimmed}`, trimmed);
    if (translated === trimmed) return;
    node.nodeValue = raw.replace(trimmed, translated);
  });
}

function renderProfiles() {
  const el = viewEl('profiles');
  const p = state.cache.profileData;
  const activity = state.cache.profileActivity || [];
  const selected = state.cache.profileSelected || '';
  const rows = Array.isArray(state.cache.memberSearch) && state.cache.memberSearch.length
    ? state.cache.memberSearch
    : (Array.isArray(state.employees) ? state.employees : []);
  const selectedMember = rows.find((row) => String(row.identifier) === String(selected)) || null;
  const character = state.cache.profileCharacter || p?.metadata?.character || {};
  const initials = (selectedMember?.name || p?.identifier || '?')
    .split(' ')
    .filter(Boolean)
    .map((x) => x[0])
    .join('')
    .slice(0, 2)
    .toUpperCase() || '??';
  const profilePhoto = p?.photoUrl
    ? `<img src="${escapeHtml(p.photoUrl)}" class="profile-photo" alt="Profile photo" />`
    : `<div class="profile-photo-fallback">${escapeHtml(initials)}</div>`;
  const characterRows = [
    ['Name', character.fullName || selectedMember?.name || 'n/a'],
    ['Identifier', p?.identifier || selected || 'n/a'],
    ['Online', selectedMember ? (selectedMember.online ? 'Yes' : 'No') : 'n/a'],
    ['Source', character.source ?? selectedMember?.source ?? 'n/a'],
    ['Ping', character.ping ?? 'n/a'],
    ['DOB', character.dateOfBirth || 'n/a'],
    ['Gender', character.gender || 'n/a'],
    ['Phone', character.phone || 'n/a'],
    ['Nationality', character.nationality || 'n/a'],
    ['Job', character.jobLabel || state.job?.label || state.job?.name || 'n/a'],
    ['Job Grade', character.jobGradeLabel || character.jobGrade || (selectedMember?.grade?.name || 'n/a')],
    ['Gang', character.gangLabel || character.gangName || 'n/a'],
    ['Gang Grade', character.gangGradeLabel || character.gangGrade || 'n/a']
  ];

  el.innerHTML = `
    <div class="grid-2 profile-grid">
      <article class="card">
        <h3>Profile Roster</h3>
        <p class="muted">Select any member to open their profile.</p>
        <div class="list profile-roster">
          ${rows.map((row) => `
            <div class="list-item profile-roster-item ${String(row.identifier) === String(selected) ? 'active' : ''}">
              <div class="list-main">
                <strong>${escapeHtml(row.online ? 'Online' : 'Offline')} | ${escapeHtml(row.name || row.identifier)}</strong>
                <small>${escapeHtml(row.identifier)} | ${escapeHtml(row.grade?.name || `Grade ${row.grade?.level ?? 0}`)}</small>
              </div>
              <div class="list-actions">
                <button class="btn small profile-member-open" data-id="${escapeHtml(row.identifier)}">Open</button>
              </div>
            </div>
          `).join('') || '<p class="muted">No members available.</p>'}
        </div>
      </article>
      <article class="card">
        <h3>Member Profile</h3>
        ${p ? `
          <div class="profile-hero">
            <div class="profile-photo-wrap">${profilePhoto}</div>
            <div class="profile-hero-meta">
              <strong>${escapeHtml(selectedMember?.name || character.fullName || p.identifier || 'Member')}</strong>
              <span class="pill">${escapeHtml(selectedMember?.grade?.name || character.jobGradeLabel || 'Rank')}</span>
              <span class="pill">Strikes: ${Number(p.strikes || 0)}</span>
              <span class="pill">${selectedMember?.online ? 'Online' : 'Offline'}</span>
            </div>
          </div>
          <div class="row" style="margin-top:8px;">
            <input id="profile-photo" placeholder="Photo URL" value="${escapeHtml(p.photoUrl || '')}" />
            <button id="profile-gen-image" class="btn small">Generate Profile Image</button>
          </div>
          <textarea id="profile-notes" placeholder="Notes">${escapeHtml(p.notes || '')}</textarea>
          <div class="row">
            <button id="profile-save" class="btn">Save Profile</button>
            <button id="profile-strike-add" class="btn small danger">+ Strike</button>
            <button id="profile-strike-rem" class="btn small ghost">- Strike</button>
          </div>
          <div class="table-wrap" style="margin-top:8px;">
            <table>
              <thead><tr><th>Field</th><th>Value</th></tr></thead>
              <tbody>
                ${characterRows.map(([k, v]) => `<tr><td>${escapeHtml(k)}</td><td>${escapeHtml(String(v ?? 'n/a'))}</td></tr>`).join('')}
              </tbody>
            </table>
          </div>
          <p class="muted">Joined: ${p.joinedAt || 'n/a'} | Hired By: ${p.hiredBy || 'n/a'} | Updated: ${p.updatedAt || 'n/a'}</p>
        ` : '<p class="muted">Select a member from the roster to load profile details.</p>'}
      </article>
      <article class="card">
        <h3>Recent Activity</h3>
        <div class="list">${activity.map((row) => `
          <div class="list-item">
            <div class="list-main">
              <strong>${escapeHtml(row.action || 'action')}</strong>
              <small>${escapeHtml(JSON.stringify(row.details || {}))} | ${row.created_at || ''}</small>
            </div>
          </div>
        `).join('') || '<p class="muted">No activity rows.</p>'}</div>
      </article>
    </div>
  `;
  el.querySelectorAll('.profile-member-open').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const identifier = btn.dataset.id;
      if (!identifier) return;
      state.cache.profileSelected = identifier;
      await ensureViewData('profiles');
      renderCurrentView();
    });
  });

  const saveBtn = document.getElementById('profile-save');
  if (saveBtn) {
    saveBtn.addEventListener('click', async () => {
      const identifier = state.cache.profileSelected;
      if (!identifier) return showToast('Select a member first', true);
      const notes = document.getElementById('profile-notes').value;
      const photoUrl = document.getElementById('profile-photo').value;
      const res = await moduleAction('update_member_profile', { identifier, notes, photoUrl });
      if (!res.ok) return showToast(res.error || 'Profile save failed', true);
      showToast('Profile updated');
      await ensureViewData('profiles');
      renderCurrentView();
    });
  }
  const strikeAdd = document.getElementById('profile-strike-add');
  const strikeRem = document.getElementById('profile-strike-rem');
  [strikeAdd, strikeRem].forEach((btn, idx) => {
    if (!btn) return;
    btn.addEventListener('click', async () => {
      const identifier = state.cache.profileSelected;
      if (!identifier) return showToast('Select a member first', true);
      const reason = (await askInput({ title: 'Strike Reason', text: 'Optional reason', value: '' })) || '';
      const amount = idx === 0 ? 1 : -1;
      const res = await moduleAction('update_member_strikes', { identifier, amount, reason });
      if (!res.ok) return showToast(res.error || 'Strike update failed', true);
      showToast('Strike updated');
      const refresh = await moduleAction('get_member_profile', { identifier });
      if (refresh.ok) {
        state.cache.profileData = refresh.data?.profile || null;
        state.cache.profileActivity = refresh.data?.activity || [];
        renderCurrentView();
      }
    });
  });

  const genBtn = document.getElementById('profile-gen-image');
  if (genBtn) {
    genBtn.addEventListener('click', async () => {
      const identifier = state.cache.profileSelected;
      if (!identifier) return showToast('Select a member first', true);
      const res = await lockRun(`profilegen:${identifier}`, () => moduleAction('generate_member_profile_image', { identifier }));
      if (!res.ok) return showToast(res.error || 'Image generation failed', true);
      showToast('Generating profile image...');
    });
  }
}

function renderInventory() {
  const el = viewEl('inventory');
  const items = state.cache.inventory || [];
  const logs = state.cache.inventoryLogs || [];
  el.innerHTML = `
    <div class="grid-2">
      <article class="card">
        <h3>Inventory Items</h3>
        <div class="row" style="margin-bottom:8px;">
          <input id="inv-item" placeholder="Item name" />
          <input id="inv-amount" type="number" min="1" placeholder="Amount" />
          <button id="inv-deposit" class="btn small">Deposit</button>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Item</th><th>Amount</th><th>Action</th></tr></thead>
            <tbody>
              ${items.map((row) => `<tr>
                <td>${escapeHtml(row.item_name || '')}</td>
                <td>${Number(row.amount || 0)}</td>
                <td><button class="btn small danger inv-wd" data-item="${escapeHtml(row.item_name || '')}">Withdraw</button></td>
              </tr>`).join('') || '<tr><td colspan="3">No inventory items.</td></tr>'}
            </tbody>
          </table>
        </div>
      </article>
      <article class="card">
        <h3>Inventory Logs</h3>
        <div class="list">${logs.map((row) => `
          <div class="list-item"><div class="list-main">
            <strong>${escapeHtml(row.action || '')} ${escapeHtml(row.item_name || '')} x${Number(row.amount || 0)}</strong>
            <small>${row.actor_identifier || 'unknown'} | ${row.created_at || ''}</small>
          </div></div>
        `).join('') || '<p class="muted">No inventory logs.</p>'}</div>
      </article>
    </div>
  `;
  const depBtn = document.getElementById('inv-deposit');
  if (depBtn) {
    depBtn.addEventListener('click', async () => {
      const item = document.getElementById('inv-item').value.trim();
      const amount = Number(document.getElementById('inv-amount').value || 0);
      const res = await moduleAction('inventory_deposit', { item, amount });
      if (!res.ok) return showToast(res.error || 'Deposit failed', true);
      showToast('Item deposited');
      await ensureViewData('inventory');
      renderCurrentView();
    });
  }
  el.querySelectorAll('.inv-wd').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const amount = Number((await askInput({ title: 'Withdraw Amount', value: '1', type: 'number', min: 1 })) || 0);
      if (!amount || amount < 1) return;
      const item = btn.dataset.item;
      const res = await moduleAction('inventory_withdraw', { item, amount });
      if (!res.ok) return showToast(res.error || 'Withdraw failed', true);
      showToast('Item withdrawn');
      await ensureViewData('inventory');
      renderCurrentView();
    });
  });
}

function renderUniforms() {
  const el = viewEl('uniforms');
  const uniforms = state.cache.uniforms || [];
  el.innerHTML = `
    <article class="card">
      <h3>Uniform Presets</h3>
      <div class="row" style="margin-bottom:8px;">
        <input id="uni-name" placeholder="Uniform name" />
        <button id="uni-create" class="btn small">Save</button>
        <button id="uni-restore" class="btn small ghost">Restore Outfit</button>
      </div>
      <p class="muted">Use JSON payloads for male/female/rank maps for appearance integrations.</p>
      <div class="table-wrap"><table>
        <thead><tr><th>ID</th><th>Name</th><th>Ranks</th><th>Action</th></tr></thead>
        <tbody>
          ${uniforms.map((u) => `<tr>
            <td>${u.id}</td>
            <td>${escapeHtml(u.uniform_name || '')}</td>
            <td>${escapeHtml(JSON.stringify(u.rank_map || {}))}</td>
            <td>
              <button class="btn small uni-preview" data-id="${u.id}">Preview</button>
              <button class="btn small uni-apply" data-id="${u.id}">Apply</button>
              <button class="btn small danger uni-del" data-id="${u.id}">Delete</button>
            </td>
          </tr>`).join('') || '<tr><td colspan="4">No uniforms.</td></tr>'}
        </tbody>
      </table></div>
    </article>
  `;
  const create = document.getElementById('uni-create');
  if (create) {
    create.addEventListener('click', async () => {
      const name = document.getElementById('uni-name').value.trim();
      const maleRaw = (await askInput({ title: 'Male Variant JSON', value: '{}' })) || '{}';
      const femaleRaw = (await askInput({ title: 'Female Variant JSON', value: '{}' })) || '{}';
      const rankRaw = (await askInput({ title: 'Rank Map JSON', value: '{}' })) || '{}';
      let maleData = {}; let femaleData = {}; let rankMap = {};
      try { maleData = JSON.parse(maleRaw); } catch (e) {}
      try { femaleData = JSON.parse(femaleRaw); } catch (e) {}
      try { rankMap = JSON.parse(rankRaw); } catch (e) {}
      const res = await moduleAction('uniforms_save', { name, maleData, femaleData, rankMap });
      if (!res.ok) return showToast(res.error || 'Uniform save failed', true);
      showToast('Uniform saved');
      await ensureViewData('uniforms');
      renderCurrentView();
    });
  }
  document.getElementById('uni-restore')?.addEventListener('click', async () => {
    const res = await moduleAction('uniforms_restore', {});
    if (!res.ok) return showToast(res.error || 'Restore failed', true);
    showToast('Outfit restored');
  });
  el.querySelectorAll('.uni-preview').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const res = await moduleAction('uniforms_preview', { id });
      if (!res.ok) return showToast(res.error || 'Preview failed', true);
      showToast('Uniform previewed');
    });
  });
  el.querySelectorAll('.uni-apply').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const res = await moduleAction('uniforms_apply', { id });
      if (!res.ok) return showToast(res.error || 'Apply failed', true);
      showToast('Uniform applied');
    });
  });
  el.querySelectorAll('.uni-del').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const res = await moduleAction('uniforms_delete', { id });
      if (!res.ok) return showToast(res.error || 'Uniform delete failed', true);
      showToast('Uniform deleted');
      await ensureViewData('uniforms');
      renderCurrentView();
    });
  });
}

function renderApplications() {
  const el = viewEl('applications');
  const rows = state.cache.applications || [];
  el.innerHTML = `
    <article class="card">
      <h3>Applications</h3>
      <div class="row" style="margin-bottom:8px;">
        <select id="app-status-filter">
          <option value="all">All</option>
          <option value="pending">Pending</option>
          <option value="accepted">Accepted</option>
          <option value="rejected">Rejected</option>
        </select>
        <input id="app-search" placeholder="Search name/identifier" />
        <button id="app-filter-btn" class="btn small">Filter</button>
      </div>
      <div class="table-wrap"><table>
        <thead><tr><th>ID</th><th>Applicant</th><th>Status</th><th>Actions</th></tr></thead>
        <tbody>
          ${rows.map((r) => `<tr>
            <td>${r.id}</td>
            <td>${escapeHtml(r.applicant_name || '')}<br/><small>${escapeHtml(r.applicant_identifier || '')}</small></td>
            <td>${escapeHtml(r.status || '')}</td>
            <td>
              <button class="btn small app-accept" data-id="${r.id}">Accept</button>
              <button class="btn small danger app-reject" data-id="${r.id}">Reject</button>
            </td>
          </tr>`).join('') || '<tr><td colspan="4">No applications.</td></tr>'}
        </tbody>
      </table></div>
    </article>
  `;
  const filterBtn = document.getElementById('app-filter-btn');
  if (filterBtn) {
    filterBtn.addEventListener('click', async () => {
      const status = document.getElementById('app-status-filter').value;
      const search = document.getElementById('app-search').value.trim();
      const res = await moduleAction('applications_list', { status, search });
      if (!res.ok) return showToast(res.error || 'Failed to fetch applications', true);
      state.cache.applications = res.data?.applications || [];
      renderCurrentView();
    });
  }
  el.querySelectorAll('.app-accept,.app-reject').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const status = btn.classList.contains('app-accept') ? 'accepted' : 'rejected';
      const reason = status === 'rejected' ? ((await askInput({ title: 'Rejection Reason', text: 'Reason is recommended for rejected applications', value: '' })) || '') : '';
      const res = await moduleAction('applications_decide', { id, status, reason });
      if (!res.ok) return showToast(res.error || 'Application update failed', true);
      await ensureViewData('applications');
      renderCurrentView();
      showToast(`Application ${status}`);
    });
  });
}

function renderAnnouncements() {
  const el = viewEl('announcements');
  const rows = state.cache.announcements || [];
  el.innerHTML = `
    <article class="card">
      <h3>Announcements</h3>
      <div class="row">
        <input id="ann-title" placeholder="Title" />
        <input id="ann-expiry" placeholder="Expiry (YYYY-MM-DD HH:mm:ss optional)" />
      </div>
      <textarea id="ann-body" placeholder="Announcement text"></textarea>
      <div class="row">
        <button id="ann-create" class="btn">Create</button>
      </div>
      <div class="list" style="margin-top:8px;">${rows.map((r) => `
        <div class="list-item"><div class="list-main">
          <strong>${escapeHtml(r.title || '')} ${r.pinned ? '<span class="pill">Pinned</span>' : ''}</strong>
          <small>${escapeHtml(r.body || '')}<br/>${r.created_at || ''}${r.expires_at ? ` | Expires: ${r.expires_at}` : ''}</small>
        </div></div>
      `).join('') || '<p class="muted">No announcements.</p>'}</div>
    </article>
  `;
  const create = document.getElementById('ann-create');
  if (create) {
    create.addEventListener('click', async () => {
      const title = document.getElementById('ann-title').value.trim();
      const body = document.getElementById('ann-body').value.trim();
      const expiresAt = document.getElementById('ann-expiry').value.trim();
      const res = await moduleAction('announcements_create', { title, body, expiresAt, pinned: false });
      if (!res.ok) return showToast(res.error || 'Announcement create failed', true);
      await ensureViewData('announcements');
      renderCurrentView();
      showToast('Announcement created');
    });
  }
}

function parseCoords(text) {
  const raw = String(text || '').split(',').map((x) => Number(x.trim()));
  if (raw.length < 3 || raw.some((n) => Number.isNaN(n))) return null;
  return { x: raw[0], y: raw[1], z: raw[2] };
}

function renderMarkers() {
  const el = viewEl('markers');
  const rows = state.cache.markers || [];
  const gangPath = state.menuType === 'gang' && state.modules.GangMarkers === true;
  el.innerHTML = `
    <article class="card">
      <h3>${gangPath ? 'Gang Markers' : 'Organization Markers'}</h3>
      <div class="row">
        <input id="marker-type" placeholder="marker type (boss_menu/stash/etc)" />
        <input id="marker-coords" placeholder="x, y, z" />
        <button id="marker-save" class="btn small">Save Marker</button>
      </div>
      <div class="table-wrap" style="margin-top:8px;"><table>
        <thead><tr><th>ID</th><th>Type</th><th>Coords</th><th>Action</th></tr></thead>
        <tbody>
          ${rows.map((r) => `<tr>
            <td>${r.id}</td>
            <td>${escapeHtml(r.marker_type || '')}</td>
            <td>${escapeHtml(JSON.stringify(r.coords || {}))}</td>
            <td><button class="btn small danger marker-del" data-id="${r.id}">Delete</button></td>
          </tr>`).join('') || '<tr><td colspan="4">No markers.</td></tr>'}
        </tbody>
      </table></div>
    </article>
  `;
  const save = document.getElementById('marker-save');
  if (save) {
    save.addEventListener('click', async () => {
      const markerType = document.getElementById('marker-type').value.trim();
      const coords = parseCoords(document.getElementById('marker-coords').value);
      if (!coords) return showToast('Invalid coords', true);
      const action = gangPath ? 'gang_marker_upsert' : 'org_markers_upsert';
      const payload = gangPath ? { markerType, coords, data: {} } : { markerType, coords, data: {} };
      const res = await moduleAction(action, payload);
      if (!res.ok) return showToast(res.error || 'Marker save failed', true);
      await ensureViewData('markers');
      renderCurrentView();
      showToast('Marker saved');
    });
  }
  el.querySelectorAll('.marker-del').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const action = gangPath ? 'gang_marker_delete' : 'org_markers_delete';
      const res = await moduleAction(action, { id });
      if (!res.ok) return showToast(res.error || 'Marker delete failed', true);
      await ensureViewData('markers');
      renderCurrentView();
      showToast('Marker deleted');
    });
  });
}

function renderGarage() {
  const el = viewEl('garage');
  const rows = state.cache.garages || [];
  el.innerHTML = `
    <article class="card">
      <h3>Garages</h3>
      <div class="row">
        <input id="garage-name" placeholder="Garage name" />
        <input id="garage-coords" placeholder="x, y, z" />
        <button id="garage-save" class="btn small">Save Garage</button>
      </div>
      <div class="table-wrap" style="margin-top:8px;"><table>
        <thead><tr><th>ID</th><th>Name</th><th>Coords</th><th>Action</th></tr></thead>
        <tbody>
          ${rows.map((r) => `<tr>
            <td>${r.id}</td>
            <td>${escapeHtml(r.name || '')}</td>
            <td>${escapeHtml(JSON.stringify(r.coords || {}))}</td>
            <td><button class="btn small danger garage-del" data-id="${r.id}">Delete</button></td>
          </tr>`).join('') || '<tr><td colspan="4">No garages.</td></tr>'}
        </tbody>
      </table></div>
    </article>
  `;
  const save = document.getElementById('garage-save');
  if (save) {
    save.addEventListener('click', async () => {
      const name = document.getElementById('garage-name').value.trim();
      const coords = parseCoords(document.getElementById('garage-coords').value);
      if (!coords || !name) return showToast('Name and coords required', true);
      const res = await moduleAction('org_garages_upsert', { name, coords, options: {} });
      if (!res.ok) return showToast(res.error || 'Garage save failed', true);
      await ensureViewData('garage');
      renderCurrentView();
      showToast('Garage saved');
    });
  }
  el.querySelectorAll('.garage-del').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const res = await moduleAction('org_garages_delete', { id });
      if (!res.ok) return showToast(res.error || 'Garage delete failed', true);
      await ensureViewData('garage');
      renderCurrentView();
      showToast('Garage deleted');
    });
  });
}

function renderTaxes() {
  const el = viewEl('taxes');
  const tax = state.cache.taxAccount || {};
  const invoices = state.cache.invoices || [];
  el.innerHTML = `
    <div class="grid-2">
      <article class="card">
        <h3>Tax Account</h3>
        <p class="muted">Due: ${formatMoney(tax.balance_due || 0)} | Next Due: ${tax.next_due_at || 'n/a'}</p>
        <div class="row">
          <input id="tax-amount-due" type="number" min="0" placeholder="Set due amount" />
          <button id="tax-set" class="btn small">Set</button>
          <button id="tax-pay" class="btn small danger">Pay Due</button>
        </div>
      </article>
      <article class="card">
        <h3>Invoices</h3>
        <div class="row">
          <select id="inv-target-type"><option value="player">Player</option><option value="organization">Organization</option></select>
          <input id="inv-target" placeholder="Identifier / Org Name" />
          <input id="inv-amount-create" type="number" min="1" placeholder="Amount" />
        </div>
        <div class="row">
          <input id="inv-reason" placeholder="Reason" />
          <button id="inv-create" class="btn small">Create Invoice</button>
        </div>
        <div class="list" style="margin-top:8px;">${invoices.map((r) => `
          <div class="list-item">
            <div class="list-main">
              <strong>Invoice #${r.id || '?'} - ${escapeHtml(r.status || '')} - ${formatMoney(r.amount || 0)}</strong>
              <small>${escapeHtml(r.reason || '')}</small>
            </div>
            <div class="row">
              <button class="btn small invoice-paid" data-id="${r.id}">Mark Paid</button>
              <button class="btn small danger invoice-cancel" data-id="${r.id}">Cancel</button>
            </div>
          </div>
        `).join('') || '<p class="muted">No invoice actions in this session.</p>'}</div>
      </article>
    </div>
  `;
  document.getElementById('tax-set')?.addEventListener('click', async () => {
    const amountDue = Number(document.getElementById('tax-amount-due').value || 0);
    const res = await moduleAction('taxes_set', { amountDue });
    if (!res.ok) return showToast(res.error || 'Tax set failed', true);
    await ensureViewData('taxes');
    renderCurrentView();
    showToast('Tax account updated');
  });
  document.getElementById('tax-pay')?.addEventListener('click', async () => {
    const due = Number(tax.balance_due || 0);
    if (due <= 0) return showToast('No due taxes', true);
    const amount = Number((await askInput({ title: 'Tax Payment', value: String(due), type: 'number', min: 1 })) || due);
    const res = await moduleAction('taxes_pay', { amount });
    if (!res.ok) return showToast(res.error || 'Tax payment failed', true);
    await ensureViewData('taxes');
    renderCurrentView();
    showToast('Tax payment submitted');
  });
  document.getElementById('inv-create')?.addEventListener('click', async () => {
    const targetType = document.getElementById('inv-target-type').value;
    const targetRaw = document.getElementById('inv-target').value.trim();
    const amount = Number(document.getElementById('inv-amount-create').value || 0);
    const reason = document.getElementById('inv-reason').value.trim();
    const payload = { targetType, amount, reason };
    if (targetType === 'player') payload.targetIdentifier = targetRaw;
    else payload.targetOrg = targetRaw;
    const res = await moduleAction('invoice_create', payload);
    if (!res.ok) return showToast(res.error || 'Invoice create failed', true);
    state.cache.invoices = [{ id: res.data?.invoiceId, status: 'created', note: `${targetType} ${targetRaw}` }, ...invoices].slice(0, 50);
    renderCurrentView();
    showToast('Invoice created');
  });
  el.querySelectorAll('.invoice-paid,.invoice-cancel').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const status = btn.classList.contains('invoice-paid') ? 'paid' : 'cancelled';
      const note = (await askInput({ title: 'Invoice Note', text: 'Optional note for this status update', value: '' })) || '';
      const res = await moduleAction('invoice_status', { id, status, note });
      if (!res.ok) return showToast(res.error || 'Invoice update failed', true);
      await ensureViewData('taxes');
      renderCurrentView();
      showToast(`Invoice ${status}`);
    });
  });
}

function renderAnalytics() {
  const el = viewEl('analytics');
  const data = (state.cache.analytics && state.cache.analytics[0]) || {};
  const employees = data.employees || {};
  const finance = data.finance || {};
  const actions = data.actions || [];
  const payroll = data.payroll || {};
  const trends = data.trends || {};
  const topActive = data.topActive || [];
  const suspicious = data.suspicious || [];
  const gang = data.gang || null;
  const financeTrendRows = Array.isArray(trends.finance) ? trends.finance : [];
  const netSeries = financeTrendRows.map((x) => (Number(x.deposits || 0) - Number(x.withdrawals || 0)));
  const actionRows = Array.isArray(actions) ? actions : [];
  const maxAction = Math.max(1, ...actionRows.map((x) => Number(x.total || 0)));
  el.innerHTML = `
    <div class="analytics-grid">
      <article class="card span-8">
        <h3>People</h3>
        <div class="row">
          <span class="pill">Total: ${Number(employees.total || 0)}</span>
          <span class="pill">Online: ${Number(employees.online || 0)}</span>
          <span class="pill">Offline: ${Number(employees.offline || 0)}</span>
        </div>
        <h4 style="margin-top:10px;">Finance Summary</h4>
        <div class="row">
          <span class="pill">Deposits: ${formatMoney(finance.deposits || 0)}</span>
          <span class="pill">Withdrawals: ${formatMoney(finance.withdrawals || 0)}</span>
          <span class="pill">Net: ${formatMoney(finance.net || 0)}</span>
        </div>
        <div class="hero-chart" style="margin-top:8px;">
          ${sparklineSvg(netSeries.length > 1 ? netSeries : [0, 0], { stroke: '#8ac2ff', fill: 'rgba(121,175,237,0.18)' })}
        </div>
        <h4 style="margin-top:10px;">Payroll</h4>
        <div class="row">
          <span class="pill">Total: ${formatMoney(payroll.total || 0)}</span>
          <span class="pill">Paid: ${Number(payroll.paidCount || 0)}</span>
          <span class="pill">Failed: ${Number(payroll.failedCount || 0)}</span>
        </div>
        ${gang ? `
          <h4 style="margin-top:10px;">Gang</h4>
          <div class="row">
            <span class="pill">Notoriety: ${Number(gang.notoriety?.points || 0)}</span>
            <span class="pill">Territories: ${Number(gang.territoryCount || 0)}</span>
            <span class="pill">Racket Stored: ${formatMoney(gang.racketIncome || 0)}</span>
            <span class="pill">Graffiti: ${Number(gang.graffitiCount || 0)}</span>
            <span class="pill">Contracts Done: ${Number(gang.contractCompletions || 0)}</span>
            ${gang.hiddenWorkshop ? `<span class="pill">Workshop Lv: ${Number(gang.hiddenWorkshop.level || 1)}</span>` : ''}
            ${gang.hiddenWorkshop ? `<span class="pill">Workshop Rep: ${Number(gang.hiddenWorkshop.reputation || 0)}</span>` : ''}
            ${gang.hiddenWorkshop ? `<span class="pill">Workshop Heat: ${Number(gang.hiddenWorkshop.heat || 0)}</span>` : ''}
          </div>` : ''}
      </article>

      <article class="card span-4">
        <h3>Action Intensity</h3>
        <div class="bar-list">${actionRows.map((a) => {
          const value = Number(a.total || 0);
          const width = Math.max(8, Math.round((value / maxAction) * 100));
          return `
            <div class="bar-row">
              <div class="bar-fill" style="width:${width}%;">
                <small>${escapeHtml(a.action || '')}</small>
                <small>${value}</small>
              </div>
            </div>
          `;
        }).join('') || '<p class="muted">No analytics rows.</p>'}</div>
      </article>

      <article class="card span-4">
        <h3>Top Active Members</h3>
        <div class="list">${topActive.map((row) => `
          <div class="list-item"><div class="list-main">
            <strong>${escapeHtml(row.identifier || '')}</strong>
            <small>${Number(row.actions || 0)} tracked actions</small>
          </div></div>
        `).join('') || '<p class="muted">No member activity yet.</p>'}</div>
      </article>

      <article class="card span-8">
        <h3>Suspicious Actions</h3>
        <div class="list">${suspicious.map((row) => `
          <div class="list-item"><div class="list-main">
            <strong>${escapeHtml(row.action || '')}</strong>
            <small>${escapeHtml(row.actor_identifier || '')} | ${row.created_at || ''}</small>
          </div></div>
        `).join('') || '<p class="muted">No suspicious actions in range.</p>'}</div>
      </article>

      <article class="card span-6">
        <h3>Action Trend (14d)</h3>
        <div class="list">${(trends.actions || []).map((t) => `
          <div class="list-item"><div class="list-main">
            <strong>${escapeHtml(t.day || '')}</strong>
            <small>${escapeHtml(t.action || '')}: ${Number(t.total || 0)}</small>
          </div></div>
        `).join('') || '<p class="muted">No trend data.</p>'}</div>
      </article>

      <article class="card span-6">
        <h3>Finance Trend (14d)</h3>
        <div class="list">${(trends.finance || []).map((t) => `
          <div class="list-item"><div class="list-main">
            <strong>${escapeHtml(t.day || '')}</strong>
            <small>+${formatMoney(t.deposits || 0)} / -${formatMoney(t.withdrawals || 0)}</small>
          </div></div>
        `).join('') || '<p class="muted">No finance trend data.</p>'}</div>
      </article>
    </div>
  `;
}

function renderLogs() {
  const el = viewEl('logs');
  const rows = state.cache.logs || [];
  el.innerHTML = `
    <article class="card">
      <h3>${escapeHtml(t('section.audit_logs', 'Audit Logs'))}</h3>
      <div class="row" style="margin-bottom:8px;">
        <input id="log-action" placeholder="Action filter" />
        <input id="log-actor" placeholder="Actor filter" />
        <input id="log-target" placeholder="Target filter" />
      </div>
      <div class="row" style="margin-bottom:8px;">
        <input id="log-from" placeholder="From date (YYYY-MM-DD)" />
        <input id="log-to" placeholder="To date (YYYY-MM-DD)" />
        <select id="log-category">
          <option value="">All categories</option>
          <option value="employee">Employee</option>
          <option value="gang">Gang</option>
          <option value="contracts">Contracts</option>
          <option value="territories">Territories</option>
        </select>
        <button id="log-filter-btn" class="btn small">${escapeHtml(t('button.apply', 'Apply'))}</button>
      </div>
      <div class="table-wrap"><table>
        <thead><tr><th>ID</th><th>${escapeHtml(t('label.action', 'Action'))}</th><th>${escapeHtml(t('label.actor', 'Actor'))}</th><th>${escapeHtml(t('label.target', 'Target'))}</th><th>${escapeHtml(t('label.when', 'When'))}</th></tr></thead>
        <tbody>
          ${rows.map((r) => `<tr>
            <td>${r.id}</td>
            <td>${escapeHtml(r.action || '')}</td>
            <td>${escapeHtml(r.actor_identifier || '')}</td>
            <td>${escapeHtml(r.target_identifier || '')}</td>
            <td>${r.created_at || ''}</td>
          </tr>`).join('') || `<tr><td colspan="5">${escapeHtml(t('empty.no_logs', 'No logs loaded.'))}</td></tr>`}
        </tbody>
      </table></div>
    </article>
  `;
  document.getElementById('log-filter-btn')?.addEventListener('click', async () => {
    const payload = {
      action: document.getElementById('log-action').value.trim(),
      actor: document.getElementById('log-actor').value.trim(),
      target: document.getElementById('log-target').value.trim(),
      dateFrom: document.getElementById('log-from').value.trim(),
      dateTo: document.getElementById('log-to').value.trim(),
      category: document.getElementById('log-category').value,
      limit: 200
    };
    const res = await moduleAction('audit_logs', payload);
    if (!res.ok) return showToast(res.error || 'Log load failed', true);
    state.cache.logs = res.data?.logs || [];
    renderCurrentView();
  });
}

function webhookTypeLabel(category) {
  const labels = {
    employee: 'Employee / Member',
    gang: 'Gang',
    finance: 'Finance',
    inventory: 'Inventory / Stash',
    admin: 'Admin',
    security: 'Security',
    applications: 'Applications',
    territories: 'Territories',
    contracts: 'Contracts'
  };
  return t(`webhook.${category}`, labels[category] || String(category || '').replaceAll('_', ' '));
}

function renderWebhookRows(rows, prefix) {
  return (rows || []).map((row) => {
    const category = row.category || '';
    const enabled = row.enabled === true || row.enabled === 1;
    return `
      <div class="list-item webhook-row" data-category="${escapeHtml(category)}">
        <div class="list-main">
          <strong>${escapeHtml(webhookTypeLabel(category))}</strong>
          <small>${escapeHtml(category)} logs${row.updated_at ? ` | Updated ${escapeHtml(row.updated_at)}` : ''}</small>
        </div>
        <label class="checkline">
          <input id="${prefix}-enabled-${escapeHtml(category)}" type="checkbox" ${enabled ? 'checked' : ''} />
          <span>${escapeHtml(t('label.enabled', 'Enabled'))}</span>
        </label>
        <input id="${prefix}-url-${escapeHtml(category)}" class="webhook-url" value="${escapeHtml(row.webhook_url || '')}" placeholder="${escapeHtml(t('placeholder.webhook_url', 'https://discord.com/api/webhooks/...'))}" />
        <button class="btn small" data-webhook-save="${escapeHtml(category)}" data-prefix="${escapeHtml(prefix)}">${escapeHtml(t('button.save', 'Save'))}</button>
      </div>
    `;
  }).join('') || `<p class="muted">${escapeHtml(t('empty.no_webhook_categories', 'No webhook categories configured.'))}</p>`;
}

function bindWebhookSaves(prefix, action, cacheKey) {
  document.querySelectorAll(`[data-prefix="${prefix}"][data-webhook-save]`).forEach((btn) => {
    btn.addEventListener('click', async () => {
      const category = btn.dataset.webhookSave;
      const webhookUrl = document.getElementById(`${prefix}-url-${category}`)?.value.trim() || '';
      const enabled = document.getElementById(`${prefix}-enabled-${category}`)?.checked === true;
      const res = await lockRun(`${action}:${category}`, () => moduleAction(action, { category, webhookUrl, enabled }));
      if (!res.ok) return showToast(res.error || t('toast.webhook_failed', 'Webhook save failed'), true);
      state.cache[cacheKey] = res.data?.settings || [];
      showToast(t('toast.webhook_saved', 'Webhook settings saved'));
      renderCurrentView();
    });
  });
}

function renderWebhooks() {
  const el = viewEl('webhooks');
  const rows = state.cache.webhooks || [];
  el.innerHTML = `
    <article class="card">
      <h3>${escapeHtml(t('section.business_webhooks', 'Business Webhooks'))}</h3>
      <p class="muted">${escapeHtml(t('msg.business_webhooks_help', 'One Discord webhook per log type for this organization. Empty URLs are stored disabled.'))}</p>
      <div class="list webhook-list">
        ${renderWebhookRows(rows, 'org-wh')}
      </div>
    </article>
  `;
  bindWebhookSaves('org-wh', 'webhook_settings_save', 'webhooks');
}

function renderTerritories() {
  const el = viewEl('territories');
  const rows = state.cache.territories || [];
  const leaderboard = state.cache.territoryLeaderboard || [];
  el.innerHTML = `
    <div class="grid-2">
      <article class="card">
        <h3>Gang Territories</h3>
        <div class="row">
          <input id="terr-name" placeholder="Territory name" />
          <input id="terr-type" placeholder="Type (basic/stash/...)" />
          <input id="terr-coords" placeholder="x, y, z" />
        </div>
        <div class="row">
          <button id="terr-begin" class="btn small">Begin Capture</button>
          <button id="terr-complete" class="btn small danger">Complete Capture</button>
        </div>
        <div class="row" style="margin-top:8px;">
          <input id="terr-path" placeholder="Tag Path ID (e.g. block_a1)" />
          <input id="terr-tag-style" placeholder="Tag style" value="territory" />
          <input id="terr-tag-text" placeholder="Tag label text" value="TERRITORY POINT" />
        </div>
        <div class="row">
          <button id="terr-tag-point" class="btn small">Tag Point At My Position</button>
          <button id="terr-tag-close" class="btn small">Close Polygon Point</button>
          <button id="terr-tag-clean" class="btn small danger">Clean Nearest Tag</button>
        </div>
        <p class="muted">Place tag points around a block, then place a close point near the first point to auto-claim.</p>
        <div class="table-wrap" style="margin-top:8px;"><table>
          <thead><tr><th>Name</th><th>Owner</th><th>Type</th><th>Status</th><th>Updated</th></tr></thead>
          <tbody>
            ${rows.map((r) => `<tr>
              <td>${escapeHtml(r.territory_name || '')}</td>
              <td>${escapeHtml(r.owner_gang || '-')}</td>
              <td>${escapeHtml(r.territory_type || '')}</td>
              <td>${escapeHtml(r.metadata?.contestedBy ? `Contested by ${r.metadata.contestedBy}` : 'Stable')}</td>
              <td>${r.updated_at || ''}</td>
            </tr>`).join('') || '<tr><td colspan="5">No territories loaded.</td></tr>'}
          </tbody>
        </table></div>
      </article>
      <article class="card">
        <h3>Leaderboard</h3>
        <div class="list">${leaderboard.map((r) => `
          <div class="list-item"><div class="list-main">
            <strong>${escapeHtml(r.gang || '')}</strong>
            <small>Captures: ${Number(r.captures || 0)}</small>
          </div></div>
        `).join('') || '<p class="muted">No leaderboard entries.</p>'}</div>
      </article>
    </div>
  `;
  document.getElementById('terr-begin')?.addEventListener('click', async () => {
    const territory = document.getElementById('terr-name').value.trim();
    const territoryType = document.getElementById('terr-type').value.trim() || 'basic';
    const coords = parseCoords(document.getElementById('terr-coords').value) || { x: 0, y: 0, z: 0 };
    const res = await moduleAction('territory_begin', { territory, territoryType, coords });
    if (!res.ok) return showToast(res.error || 'Capture start failed', true);
    await ensureViewData('territories');
    renderCurrentView();
    showToast('Capture started');
  });
  document.getElementById('terr-complete')?.addEventListener('click', async () => {
    const territory = document.getElementById('terr-name').value.trim();
    const res = await moduleAction('territory_complete', { territory });
    if (!res.ok) return showToast(res.error || 'Capture complete failed', true);
    await ensureViewData('territories');
    renderCurrentView();
    showToast('Capture completed');
  });
  const collectTagPayload = (closePoint) => ({
    pathId: document.getElementById('terr-path').value.trim(),
    style: document.getElementById('terr-tag-style').value.trim() || 'territory',
    text: document.getElementById('terr-tag-text').value.trim() || (closePoint ? 'CLOSE POINT' : 'TERRITORY POINT'),
    metadata: { closePoint: closePoint === true }
  });
  document.getElementById('terr-tag-point')?.addEventListener('click', async () => {
    const payload = collectTagPayload(false);
    const res = await lockRun('terr_tag_point', () => post('territoryTagPoint', payload));
    if (!res.ok) return showToast(res.error || 'Tag point failed', true);
    await ensureViewData('territories');
    renderCurrentView();
    showToast(res.data?.territoryAuto ? 'Tag point placed and territory claimed' : 'Tag point placed');
  });
  document.getElementById('terr-tag-close')?.addEventListener('click', async () => {
    const payload = collectTagPayload(true);
    payload.text = payload.text || 'CLOSE POINT';
    const res = await lockRun('terr_tag_close', () => post('territoryTagPoint', payload));
    if (!res.ok) return showToast(res.error || 'Close point failed', true);
    await ensureViewData('territories');
    renderCurrentView();
    showToast(res.data?.territoryAuto ? 'Polygon closed and territory claimed' : 'Close point placed');
  });
  document.getElementById('terr-tag-clean')?.addEventListener('click', async () => {
    const res = await lockRun('terr_tag_clean', () => post('territoryCleanNearest', {}));
    if (!res.ok) return showToast(res.error || 'Clean failed', true);
    showToast('Nearest tag cleaned');
  });
}

function renderRackets() {
  const el = viewEl('rackets');
  const rows = state.cache.rackets || [];
  el.innerHTML = `
    <article class="card">
      <h3>Gang Rackets</h3>
      <div class="row">
        <input id="racket-territory" placeholder="Territory" />
        <input id="racket-level" type="number" min="1" placeholder="Level" />
        <select id="racket-upgrade-type">
          <option value="income_rate">income_rate</option>
          <option value="storage_capacity">storage_capacity</option>
          <option value="security">security</option>
          <option value="cooldown_reduction">cooldown_reduction</option>
        </select>
        <button id="racket-upsert" class="btn small">Save</button>
      </div>
      <div class="table-wrap" style="margin-top:8px;"><table>
        <thead><tr><th>ID</th><th>Territory</th><th>Level</th><th>Stored</th><th>Actions</th></tr></thead>
        <tbody>
          ${rows.map((r) => `<tr>
            <td>${r.id}</td><td>${escapeHtml(r.territory_name || '')}</td><td>${Number(r.level || 1)}</td><td>${formatMoney(r.stored_income || 0)}</td>
            <td>
              <button class="btn small rack-upg" data-id="${r.id}">Upgrade</button>
              <button class="btn small rack-claim" data-id="${r.id}">Claim</button>
            </td>
          </tr>`).join('') || '<tr><td colspan="5">No rackets.</td></tr>'}
        </tbody>
      </table></div>
    </article>
  `;
  document.getElementById('racket-upsert')?.addEventListener('click', async () => {
    const territory = document.getElementById('racket-territory').value.trim();
    const level = Number(document.getElementById('racket-level').value || 1);
    const res = await moduleAction('rackets_upsert', { territory, level, upgrades: {} });
    if (!res.ok) return showToast(res.error || 'Racket save failed', true);
    await ensureViewData('rackets');
    renderCurrentView();
    showToast('Racket saved');
  });
  el.querySelectorAll('.rack-upg').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const upgradeType = document.getElementById('racket-upgrade-type').value;
      const res = await moduleAction('rackets_upgrade', { id, upgradeType, moneyCost: 0, notorietyCost: 0 });
      if (!res.ok) return showToast(res.error || 'Upgrade failed', true);
      await ensureViewData('rackets');
      renderCurrentView();
      showToast('Racket upgraded');
    });
  });
  el.querySelectorAll('.rack-claim').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const res = await moduleAction('rackets_claim', { id });
      if (!res.ok) return showToast(res.error || 'Claim failed', true);
      patchCore(res.data || {});
      renderTop();
      await ensureViewData('rackets');
      renderCurrentView();
      showToast('Income claimed');
    });
  });
}

function renderWorkshop() {
  const el = viewEl('workshop');
  const data = state.cache.workshop || {};
  const profile = data.profile || {};
  const contracts = Array.isArray(data.contracts) ? data.contracts : [];
  const contractTypes = Array.isArray(data.contractTypes) ? data.contractTypes : [];
  const partsCatalog = Array.isArray(data.partsCatalog) ? data.partsCatalog : [];
  const vehicleClasses = [...new Set(contractTypes.flatMap((entry) => Array.isArray(entry.classes) ? entry.classes : []))];
  const payoutMode = String(data.payoutMode || 'dirty_item');

  el.innerHTML = `
    <div class="grid-2">
      <article class="card">
        <h3>Hidden Workshop</h3>
        <div class="row">
          <span class="pill">Level ${Number(profile.level || 1)}</span>
          <span class="pill">Reputation ${Number(profile.reputation || 0)}</span>
          <span class="pill">Heat ${Number(profile.heat || 0)}</span>
        </div>
        <div class="row" style="margin-top:8px;">
          <span class="pill">Jobs Done ${Number(profile.jobs_completed || 0)}</span>
          <span class="pill">Failed ${Number(profile.jobs_failed || 0)}</span>
          <span class="pill">Early Cashouts ${Number(profile.early_cashouts || 0)}</span>
        </div>
        <div class="row" style="margin-top:8px;">
          <span class="pill">Cars Stripped ${Number(profile.cars_stripped || 0)}</span>
          <span class="pill">Parts Yield ${Number(profile.total_parts_earned || 0)}</span>
          <span class="pill">Cash Generated ${formatMoney(profile.total_cash_earned || 0)}</span>
        </div>
        <div class="row" style="margin-top:12px;">
          <select id="workshop-contract-type">
            ${contractTypes.map((entry) => `<option value="${escapeHtml(entry.id)}">${escapeHtml(entry.label || entry.id)}</option>`).join('')}
          </select>
          <select id="workshop-vehicle-class">
            <option value="">Auto class</option>
            ${vehicleClasses.map((entry) => `<option value="${escapeHtml(entry)}">${escapeHtml(entry)}</option>`).join('')}
          </select>
          <button id="workshop-create" class="btn small">Post Job</button>
        </div>
        <p style="margin-top:10px; opacity:0.8;">
          Early cashout keeps stripped parts and pays through ${payoutMode === 'account' ? 'the gang account' : 'dirty cash in stash'}.
        </p>
        <div class="row">
          <span class="pill">Cash Bonus ${Number(profile.benefits?.cashBonusPercent || 0)}%</span>
          <span class="pill">Rep Bonus ${Number(profile.benefits?.repBonusPercent || 0)}%</span>
          <span class="pill">Extra Parts ${Number(profile.benefits?.extraPartChancePercent || 0)}%</span>
        </div>
      </article>
      <article class="card">
        <h3>Parts Catalog</h3>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Part</th><th>Item</th><th>Guide Value</th></tr></thead>
            <tbody>
              ${partsCatalog.map((part) => `<tr>
                <td>${escapeHtml(part.label || part.key || '')}</td>
                <td>${escapeHtml(part.item || '')}</td>
                <td>${formatMoney(part.unitValue || 0)}</td>
              </tr>`).join('') || '<tr><td colspan="3">No parts configured.</td></tr>'}
            </tbody>
          </table>
        </div>
      </article>
    </div>
    <article class="card" style="margin-top:12px;">
      <h3>Workshop Jobs</h3>
      <div class="table-wrap">
        <table>
          <thead><tr><th>ID</th><th>Type</th><th>Vehicle</th><th>Status</th><th>Progress</th><th>Actions</th></tr></thead>
          <tbody>
            ${contracts.map((row) => {
              const parts = Array.isArray(row.payload?.parts) ? row.payload.parts : [];
              const buttons = [];
              if (row.status === 'available') {
                buttons.push(`<button class="btn small workshop-accept" data-id="${row.id}">Accept</button>`);
              }
              if (row.status === 'active') {
                for (const part of parts) {
                  const stripped = Number(part.stripped || 0);
                  const required = Number(part.required || 0);
                  if (stripped < required) {
                    buttons.push(`<button class="btn small ghost workshop-strip" data-id="${row.id}" data-part="${escapeHtml(part.key || '')}">Strip ${escapeHtml(part.label || part.key || '')}</button>`);
                  }
                }
                buttons.push(`<button class="btn small workshop-cashout" data-id="${row.id}">Early Cashout</button>`);
                buttons.push(`<button class="btn small danger workshop-fail" data-id="${row.id}">Abort</button>`);
                if (Number(row.progress?.stripped || 0) >= Number(row.progress?.required || 0) && Number(row.progress?.required || 0) > 0) {
                  buttons.push(`<button class="btn small workshop-complete" data-id="${row.id}">Finish</button>`);
                }
              }
              const partText = parts.map((part) => `${part.label || part.key}: ${Number(part.stripped || 0)}/${Number(part.required || 0)}`).join(' | ');
              return `<tr>
                <td>${row.id}</td>
                <td>${escapeHtml(row.payload?.contractLabel || row.contractType || '')}</td>
                <td>${escapeHtml(row.payload?.targetModel || row.payload?.vehicleLabel || '')}</td>
                <td>${escapeHtml(row.status || '')}</td>
                <td>
                  ${Number(row.progress?.stripped || 0)}/${Number(row.progress?.required || 0)}
                  <div style="opacity:0.78; margin-top:4px;">${escapeHtml(partText || 'No parts')}</div>
                </td>
                <td>${buttons.join(' ') || '<span class="pill">Closed</span>'}</td>
              </tr>`;
            }).join('') || '<tr><td colspan="6">No workshop jobs.</td></tr>'}
          </tbody>
        </table>
      </div>
    </article>
  `;

  document.getElementById('workshop-create')?.addEventListener('click', async () => {
    const contractType = document.getElementById('workshop-contract-type').value;
    const vehicleClass = document.getElementById('workshop-vehicle-class').value;
    const res = await moduleAction('workshop_create', { contractType, vehicleClass });
    if (!res.ok) return showToast(res.error || 'Workshop job creation failed', true);
    state.cache.workshop = res.data || {};
    renderCurrentView();
    showToast('Workshop job posted');
  });
  el.querySelectorAll('.workshop-accept').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const res = await moduleAction('workshop_accept', { id });
      if (!res.ok) return showToast(res.error || 'Accept failed', true);
      state.cache.workshop = res.data || {};
      renderCurrentView();
      showToast('Workshop job accepted');
    });
  });
  el.querySelectorAll('.workshop-strip').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const partKey = btn.dataset.part || '';
      const res = await moduleAction('workshop_progress', { id, partKey, amount: 1 });
      if (!res.ok) return showToast(res.error || 'Strip action failed', true);
      state.cache.workshop = res.data || {};
      await ensureViewData('overview');
      renderCurrentView();
      showToast('Part stripped into stash');
    });
  });
  el.querySelectorAll('.workshop-cashout').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const res = await moduleAction('workshop_cashout', { id });
      if (!res.ok) return showToast(res.error || 'Early cashout failed', true);
      await ensureViewData('workshop');
      await ensureViewData('overview');
      renderCurrentView();
      showToast('Workshop cashed out early');
    });
  });
  el.querySelectorAll('.workshop-complete').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const res = await moduleAction('workshop_complete', { id });
      if (!res.ok) return showToast(res.error || 'Workshop finish failed', true);
      await ensureViewData('workshop');
      await ensureViewData('overview');
      renderCurrentView();
      showToast('Workshop payout completed');
    });
  });
  el.querySelectorAll('.workshop-fail').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const reason = (await askInput({ title: 'Abort Reason', value: '' })) || '';
      const res = await moduleAction('workshop_fail', { id, reason });
      if (!res.ok) return showToast(res.error || 'Abort failed', true);
      state.cache.workshop = res.data || {};
      await ensureViewData('overview');
      renderCurrentView();
      showToast('Workshop job aborted cleanly');
    });
  });
}

function renderContracts() {
  const el = viewEl('contracts');
  const rows = state.cache.contracts || [];
  el.innerHTML = `
    <article class="card">
      <h3>Gang Contracts</h3>
      <div class="row">
        <select id="contract-type">
          <option value="delivery">delivery</option>
          <option value="collection">collection</option>
          <option value="robbery_setup">robbery_setup</option>
          <option value="dealer_task">dealer_task</option>
          <option value="territory_disruption">territory_disruption</option>
          <option value="item_sourcing">item_sourcing</option>
        </select>
        <button id="contract-create" class="btn small">Create</button>
      </div>
      <div class="table-wrap" style="margin-top:8px;"><table>
        <thead><tr><th>ID</th><th>Type</th><th>Status</th><th>Actions</th></tr></thead>
        <tbody>
          ${rows.map((r) => `<tr>
            <td>${r.id}</td><td>${escapeHtml(r.contract_type || '')}</td><td>${escapeHtml(r.status || '')}</td>
            <td>
              <button class="btn small contract-accept" data-id="${r.id}">Accept</button>
              <button class="btn small danger contract-complete" data-id="${r.id}">Complete</button>
              <button class="btn small ghost contract-fail" data-id="${r.id}">Fail</button>
            </td>
          </tr>`).join('') || '<tr><td colspan="4">No contracts.</td></tr>'}
        </tbody>
      </table></div>
    </article>
  `;
  document.getElementById('contract-create')?.addEventListener('click', async () => {
    const contractType = document.getElementById('contract-type').value;
    const res = await moduleAction('contracts_create', { contractType, payload: {} });
    if (!res.ok) return showToast(res.error || 'Contract create failed', true);
    await ensureViewData('contracts');
    renderCurrentView();
    showToast('Contract created');
  });
  el.querySelectorAll('.contract-accept').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const res = await moduleAction('contracts_accept', { id });
      if (!res.ok) return showToast(res.error || 'Accept failed', true);
      await ensureViewData('contracts');
      renderCurrentView();
      showToast('Contract accepted');
    });
  });
  el.querySelectorAll('.contract-complete,.contract-fail').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = Number(btn.dataset.id);
      const success = btn.classList.contains('contract-complete');
      const res = await moduleAction('contracts_complete', { id, success });
      if (!res.ok) return showToast(res.error || 'Contract update failed', true);
      await ensureViewData('contracts');
      renderCurrentView();
      showToast(success ? 'Contract completed' : 'Contract failed');
    });
  });
}

function cameraFeedSymbol(iconName) {
  const key = String(iconName || '').toLowerCase();
  if (key === 'shield') return '⛨';
  if (key === 'medical') return '✚';
  if (key === 'garage') return '◧';
  if (key === 'city') return '◬';
  if (key === 'watch') return '⌖';
  return '◌';
}

function renderCameras() {
  const el = viewEl('cameras');
  const data = state.cache.cameras || {};
  const feeds = Array.isArray(data.feeds) ? data.feeds : [];
  const provider = String(data.provider || state.settings?.cameraProvider || 'none');
  const profile = state.orgProfile || {};
  const providerTitle = provider === 'none' ? 'No Provider' : provider;

  el.innerHTML = `
    <div class="grid-2">
      <article class="card">
        <h3>${profile.id === 'law' ? 'City Surveillance Network' : 'Organization Cameras'}</h3>
        <p class="muted">Provider: ${escapeHtml(providerTitle)} | Feeds: ${feeds.length}</p>
        <div class="list">
          ${feeds.map((cam) => `
            <div class="list-item cam-item" data-cam="${escapeHtml(cam.id || '')}">
              <div class="list-main">
                <strong><span class="nav-ico">${cameraFeedSymbol(cam.icon)}</span> ${escapeHtml(cam.label || cam.id || 'Camera')}</strong>
                <small>ID: ${escapeHtml(cam.id || '')}</small>
              </div>
              <button class="btn small cam-open">Open Feed</button>
            </div>
          `).join('') || '<p class="muted">No camera feeds configured for this organization/archetype.</p>'}
        </div>
      </article>
      <article class="card">
        <h3>Integration Notes</h3>
        <div class="list">
          <div class="list-item"><div class="list-main"><strong>Auto Provider</strong><small>Set in Config.Integrations.camera = auto</small></div></div>
          <div class="list-item"><div class="list-main"><strong>Per-Org Feeds</strong><small>Configure Config.Cameras.feedsByOrg[orgName]</small></div></div>
          <div class="list-item"><div class="list-main"><strong>Archetype Feeds</strong><small>Configure Config.Cameras.feedsByArchetype[archetypeId]</small></div></div>
          <div class="list-item"><div class="list-main"><strong>Custom Provider</strong><small>Configure Config.Cameras.providers.custom</small></div></div>
        </div>
      </article>
    </div>
  `;

  el.querySelectorAll('.cam-open').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const id = btn.closest('.cam-item')?.dataset?.cam;
      const res = await moduleAction('camera_open', { id });
      if (!res.ok) return showToast(res.error || 'Camera open failed', true);
      showToast('Camera feed opened');
      if (state.settings?.cameraCloseMenuOnOpen === true) {
        await post('close', {});
      }
    });
  });
}

function renderAdmin() {
  const el = viewEl('admin');
  const data = state.cache.admin || {};
  const jobs = data.jobs || [];
  const gangs = data.gangs || [];
  const actions = state.cache.adminActions || [];
  const adminWebhooks = state.cache.adminWebhooks || [];
  el.innerHTML = `
    <div class="grid-2">
      <article class="card">
        <h3>Organizations</h3>
        <div class="row">
          <input id="admin-org-name" placeholder="Org name" />
          <select id="admin-org-type"><option value="boss">Job</option><option value="gang">Gang</option></select>
          <input id="admin-org-amount" type="number" min="1" placeholder="Amount" />
        </div>
        <div class="row" style="margin-top:8px;">
          <input id="admin-target-id" placeholder="Target identifier/source" />
          <input id="admin-grade" type="number" min="0" placeholder="Grade" />
        </div>
        <div class="row">
          <button id="admin-add-funds" class="btn small">Add Funds</button>
          <button id="admin-rem-funds" class="btn small danger">Remove Funds</button>
          <button id="admin-load-actions" class="btn small ghost">Load Admin Actions</button>
        </div>
        <div class="row" style="margin-top:8px; flex-wrap:wrap;">
          <button id="admin-disable-org" class="btn small danger">Disable Org</button>
          <button id="admin-enable-org" class="btn small">Enable Org</button>
          <button id="admin-force-add" class="btn small">Force Add</button>
          <button id="admin-force-rem" class="btn small danger">Force Remove</button>
          <button id="admin-force-grade" class="btn small">Force Grade</button>
          <button id="admin-change-leader" class="btn small">Change Leader</button>
          <button id="admin-del-gang" class="btn small danger">Delete Internal Gang</button>
          <button id="admin-suspicious" class="btn small ghost">Suspicious</button>
        </div>
        <p class="muted">Jobs: ${jobs.length} | Gangs: ${gangs.length}</p>
      </article>
      <article class="card">
        <h3>Recent Admin Actions</h3>
        <div class="list">${actions.map((a) => `
          <div class="list-item"><div class="list-main">
            <strong>${escapeHtml(a.action || '')}</strong>
            <small>${escapeHtml(a.admin_identifier || a.actor_identifier || '')} | ${a.created_at || ''}</small>
          </div></div>
        `).join('') || '<p class="muted">No actions loaded.</p>'}</div>
      </article>
      <article class="card span-2">
        <h3>${escapeHtml(t('section.admin_webhooks', 'Admin Webhooks'))}</h3>
        <p class="muted">${escapeHtml(t('msg.admin_webhooks_help', 'Global catch-all Discord webhooks. Each type receives logs from every business and gang.'))}</p>
        <div class="list webhook-list">
          ${renderWebhookRows(adminWebhooks, 'admin-wh')}
        </div>
      </article>
    </div>
  `;
  const runAdmin = async (action) => {
    const orgType = document.getElementById('admin-org-type').value;
    const orgName = document.getElementById('admin-org-name').value.trim();
    const amount = Number(document.getElementById('admin-org-amount').value || 0);
    if (!orgName) return showToast('Org name required', true);
    const res = await moduleAction(action, { orgType, orgName, amount });
    if (!res.ok) return showToast(res.error || 'Admin action failed', true);
    showToast('Admin action complete');
    await ensureViewData('admin');
    renderCurrentView();
  };
  document.getElementById('admin-add-funds')?.addEventListener('click', () => runAdmin('admin_add_funds'));
  document.getElementById('admin-rem-funds')?.addEventListener('click', () => runAdmin('admin_remove_funds'));
  const runAdminTargeted = async (action, extra = {}) => {
    const orgType = document.getElementById('admin-org-type').value;
    const orgName = document.getElementById('admin-org-name').value.trim();
    const amount = Number(document.getElementById('admin-org-amount').value || 0);
    const identifierRaw = document.getElementById('admin-target-id').value.trim();
    const grade = Number(document.getElementById('admin-grade').value || 0);
    if (!orgName) return showToast('Org name required', true);
    const payload = { orgType, orgName, amount, grade, ...extra };
    if (identifierRaw) {
      if (/^\d+$/.test(identifierRaw)) payload.source = Number(identifierRaw);
      else payload.identifier = identifierRaw;
    }
    const res = await moduleAction(action, payload);
    if (!res.ok) return showToast(res.error || 'Admin action failed', true);
    showToast('Admin action complete');
    await ensureViewData('admin');
    renderCurrentView();
  };
  document.getElementById('admin-disable-org')?.addEventListener('click', async () => {
    const reason = (await askInput({ title: 'Disable Reason', value: '' })) || '';
    await runAdminTargeted('admin_disable_org', { reason });
  });
  document.getElementById('admin-enable-org')?.addEventListener('click', () => runAdminTargeted('admin_enable_org'));
  document.getElementById('admin-force-add')?.addEventListener('click', () => runAdminTargeted('admin_force_add_member'));
  document.getElementById('admin-force-rem')?.addEventListener('click', async () => {
    const reason = (await askInput({ title: 'Removal Reason', value: '' })) || '';
    await runAdminTargeted('admin_force_remove_member', { reason });
  });
  document.getElementById('admin-force-grade')?.addEventListener('click', () => runAdminTargeted('admin_force_set_grade'));
  document.getElementById('admin-change-leader')?.addEventListener('click', () => runAdminTargeted('admin_change_leader'));
  document.getElementById('admin-del-gang')?.addEventListener('click', async () => {
    const confirm = await askInput({ title: 'Confirm Deletion', text: 'Type DELETE to confirm internal gang deletion', value: '' });
    if (confirm !== 'DELETE') return showToast('Deletion cancelled', true);
    await runAdminTargeted('admin_delete_internal_gang', { confirm: 'DELETE' });
  });
  document.getElementById('admin-suspicious')?.addEventListener('click', async () => {
    const res = await moduleAction('admin_suspicious', { limit: 100 });
    if (!res.ok) return showToast(res.error || 'Failed to load suspicious actions', true);
    state.cache.adminActions = res.data?.suspicious || [];
    renderCurrentView();
  });
  document.getElementById('admin-load-actions')?.addEventListener('click', async () => {
    const res = await moduleAction('admin_actions', { limit: 120 });
    if (!res.ok) return showToast(res.error || 'Failed loading admin actions', true);
    state.cache.adminActions = res.data?.actions || [];
    renderCurrentView();
  });
  bindWebhookSaves('admin-wh', 'admin_webhooks_save', 'adminWebhooks');
}

async function ensureViewData(view) {
  const calls = {
    profiles: async () => {
      const rows = Array.isArray(state.cache.memberSearch) && state.cache.memberSearch.length
        ? state.cache.memberSearch
        : (Array.isArray(state.employees) ? state.employees : []);
      let identifier = state.cache.profileSelected;
      if (!identifier && rows.length) {
        identifier = rows[0].identifier;
      }
      if (!identifier) {
        state.cache.profileData = null;
        state.cache.profileActivity = [];
        state.cache.profileCharacter = null;
        return;
      }
      const res = await moduleAction('get_member_profile', { identifier });
      if (res.ok) {
        state.cache.profileSelected = identifier;
        state.cache.profileData = res.data?.profile || null;
        state.cache.profileActivity = res.data?.activity || [];
        state.cache.profileCharacter = res.data?.character || null;
      } else {
        showToast(res.error || 'Failed to load profile', true);
      }
    },
    ranks: async () => {
      const res = await moduleAction('get_ranks', {});
      if (res.ok) state.cache.ranks = res.data?.ranks || [];
      else showToast(res.error || 'Failed to load ranks', true);
    },
    permissions: async () => {
      const res = await moduleAction('get_rank_permissions', { grade: state.job?.grade || 0 });
      if (res.ok) state.cache.rankPermissions = res.data || {};
      else showToast(res.error || 'Failed to load permissions', true);
    },
    inventory: async () => {
      const res = await moduleAction('inventory_list', {});
      if (res.ok) {
        state.cache.inventory = res.data?.items || [];
        state.cache.inventoryLogs = res.data?.logs || [];
      }
      else showToast(res.error || 'Failed to load inventory', true);
    },
    uniforms: async () => {
      const res = await moduleAction('uniforms_list', {});
      if (res.ok) state.cache.uniforms = res.data?.uniforms || [];
      else showToast(res.error || 'Failed to load uniforms', true);
    },
    applications: async () => {
      const res = await moduleAction('applications_list', { status: 'all' });
      if (res.ok) state.cache.applications = res.data?.applications || [];
      else showToast(res.error || 'Failed to load applications', true);
    },
    announcements: async () => {
      const res = await moduleAction('announcements_list', {});
      if (res.ok) state.cache.announcements = res.data?.announcements || [];
      else showToast(res.error || 'Failed to load announcements', true);
    },
    cameras: async () => {
      const res = await moduleAction('camera_list', {});
      if (res.ok) state.cache.cameras = res.data || {};
      else showToast(res.error || 'Failed to load camera feeds', true);
    },
    markers: async () => {
      const action = state.menuType === 'gang' && state.modules.GangMarkers === true ? 'gang_marker_list' : 'org_markers_list';
      const res = await moduleAction(action, {});
      if (res.ok) state.cache.markers = res.data?.markers || [];
      else showToast(res.error || 'Failed to load markers', true);
    },
    garage: async () => {
      const res = await moduleAction('org_garages_list', {});
      if (res.ok) state.cache.garages = res.data?.garages || [];
      else showToast(res.error || 'Failed to load garages', true);
    },
    taxes: async () => {
      const res = await moduleAction('taxes_get', {});
      if (res.ok) state.cache.taxAccount = res.data?.tax || {};
      else showToast(res.error || 'Failed to load tax account', true);
      const inv = await moduleAction('invoice_list', { status: 'all', limit: 200 });
      if (inv.ok) state.cache.invoices = inv.data?.invoices || [];
    },
    analytics: async () => {
      const res = await moduleAction('analytics', {});
      if (res.ok) state.cache.analytics = [res.data || {}];
      else showToast(res.error || 'Failed to load analytics', true);
    },
    logs: async () => {
      const res = await moduleAction('audit_logs', { limit: 200 });
      if (res.ok) state.cache.logs = res.data?.logs || [];
      else showToast(res.error || 'Failed to load logs', true);
    },
    webhooks: async () => {
      const res = await moduleAction('webhook_settings_get', {});
      if (res.ok) state.cache.webhooks = res.data?.settings || [];
      else showToast(res.error || 'Failed to load webhooks', true);
    },
    territories: async () => {
      const res = await moduleAction('territory_list', {});
      if (res.ok) {
        state.cache.territories = res.data?.territories || [];
        state.cache.territoryLeaderboard = res.data?.leaderboard || [];
      }
      else showToast(res.error || 'Failed to load territories', true);
    },
    rackets: async () => {
      const res = await moduleAction('rackets_list', {});
      if (res.ok) state.cache.rackets = res.data?.rackets || [];
      else showToast(res.error || 'Failed to load rackets', true);
    },
    workshop: async () => {
      const res = await moduleAction('workshop_overview', {});
      if (res.ok) state.cache.workshop = res.data || {};
      else showToast(res.error || 'Failed to load hidden workshop', true);
    },
    contracts: async () => {
      const res = await moduleAction('contracts_list', {});
      if (res.ok) state.cache.contracts = res.data?.contracts || [];
      else showToast(res.error || 'Failed to load contracts', true);
    },
    admin: async () => {
      const res = await moduleAction('admin_list_orgs', {});
      if (res.ok) {
        state.cache.admin = res.data || {};
        if (Array.isArray(res.data?.latestActions)) {
          state.cache.adminActions = res.data.latestActions;
        }
      }
      else showToast(res.error || 'Failed to load admin data', true);
      const hooks = await moduleAction('admin_webhooks_get', {});
      if (hooks.ok) state.cache.adminWebhooks = hooks.data?.settings || [];
    }
  };
  if (calls[view]) {
    await calls[view]();
  }
}

function renderCurrentView() {
  const view = state.activeView;
  if (view === 'overview') renderOverview();
  else if (view === 'members') renderMembers();
  else if (view === 'ranks') renderRankView();
  else if (view === 'permissions') renderPermissionView();
  else if (view === 'profiles') renderProfiles();
  else if (view === 'inventory') renderInventory();
  else if (view === 'uniforms') renderUniforms();
  else if (view === 'applications') renderApplications();
  else if (view === 'announcements') renderAnnouncements();
  else if (view === 'cameras') renderCameras();
  else if (view === 'markers') renderMarkers();
  else if (view === 'garage') renderGarage();
  else if (view === 'taxes') renderTaxes();
  else if (view === 'analytics') renderAnalytics();
  else if (view === 'logs') renderLogs();
  else if (view === 'webhooks') renderWebhooks();
  else if (view === 'territories') renderTerritories();
  else if (view === 'rackets') renderRackets();
  else if (view === 'workshop') renderWorkshop();
  else if (view === 'contracts') renderContracts();
  else if (view === 'admin') renderAdmin();
  localizeDom(viewEl(view));
}

async function openUi(payload) {
  state.token = payload.token || null;
  state.menuType = String(payload.menuType || 'boss');
  state.job = payload.job || null;
  state.orgProfileHint = payload.orgProfile || null;
  state.groupStyle = payload.groupStyle || null;
  state.locale = payload.locale || {};
  state.settings = payload.settings || {};
  state.modules = payload.modules || {};
  state.permissions = payload.permissions || {};
  state.hasFinance = payload.hasFinance !== false;
  state.grades = Array.isArray(payload.grades) ? payload.grades : [];
  state.balance = Number(payload.balance) || 0;
  state.employees = Array.isArray(payload.employees) ? payload.employees : [];
  state.nearby = Array.isArray(payload.nearby) ? payload.nearby : [];
  state.ledger = Array.isArray(payload.ledger) ? payload.ledger : [];
  state.orgProfile = inferOrgProfile(state.menuType, state.job, state.grades, state.orgProfileHint);
  applyTheme(state.orgProfile);
  state.cache = {};
  renderNav();
  renderTop();
  app.classList.remove('hidden');
  await ensureViewData(state.activeView);
  renderCurrentView();
}

function closeUi() {
  app.classList.add('hidden');
  state.token = null;
}

function formatClock() {
  const d = new Date();
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  const ss = String(d.getSeconds()).padStart(2, '0');
  return `${hh}:${mm}:${ss}`;
}

function setCameraOverlay(show, payload = {}) {
  if (!cameraOverlay) return;
  if (!show) {
    cameraOverlay.classList.add('hidden');
    if (cameraOverlayTicker) {
      clearInterval(cameraOverlayTicker);
      cameraOverlayTicker = null;
    }
    return;
  }
  cameraOverlayLabel.textContent = String(payload.label || 'CCTV FEED');
  cameraOverlayProvider.textContent = String(payload.provider || 'SYSTEM').toUpperCase();
  cameraOverlayTime.textContent = formatClock();
  cameraOverlay.classList.remove('hidden');
  if (cameraOverlayTicker) clearInterval(cameraOverlayTicker);
  cameraOverlayTicker = setInterval(() => {
    cameraOverlayTime.textContent = formatClock();
  }, 1000);
}

window.addEventListener('message', async (event) => {
  const { action, payload } = event.data || {};
  if (action === 'open') await openUi(payload || {});
  if (action === 'close') closeUi();
  if (action === 'cameraOverlay') setCameraOverlay(payload?.show === true, payload || {});
  if (action === 'captureVisibility') {
    app.classList.toggle('capture-hidden', payload?.show === false);
  }
  if (action === 'profileCaptureResult') {
    if (payload?.ok) {
      state.cache.profileSelected = payload.identifier || state.cache.profileSelected;
      state.cache.profileData = payload.profile || state.cache.profileData;
      showToast('Profile image updated');
      if (state.activeView === 'profiles') {
        await ensureViewData('profiles');
        renderCurrentView();
      }
    } else {
      showToast(payload?.error || 'Profile image generation failed', true);
    }
  }
});

closeBtn.addEventListener('click', () => post('close', {}));

stashBtn?.addEventListener('click', async () => {
  const res = await lockRun('stash_open', () => moduleAction('stash_open', {}));
  if (!res.ok) return showToast(res.error || 'Failed to open stash', true);
  showToast('Opening boss stash');
});

refreshBtn.addEventListener('click', async () => {
  const res = await lockRun('refresh', () => post('refresh', {}));
  if (!res.ok) return showToast(res.error || 'Refresh failed', true);
  patchCore(res.data);
  renderTop();
  await ensureViewData(state.activeView);
  renderCurrentView();
  showToast('Refreshed');
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') post('escape', {});
});
