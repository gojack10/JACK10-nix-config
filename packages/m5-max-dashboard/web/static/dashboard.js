const $ = (id) => document.getElementById(id);
const valid = (n) => typeof n === 'number' && Number.isFinite(n);
const fmt = (n, places = 1, width = 0, unit = '') =>
  (valid(n) ? n.toFixed(places) : '-').padStart(width) + unit;
const gb = (n) => fmt(n, 1, 6, 'G');
const pct = (n, d) => valid(n) && valid(d) && d > 0 ? n * 100 / d : null;
const clean = (s) => String(s ?? '-').replace(/[\r\n\t\x1b]/g, ' ').replaceAll('·', '-');
const tone = (n) => !valid(n) ? '' : n <= 50 ? 'success' : n <= 80 ? 'warning' : 'urgent';
const row = (label, text) => '  ' + label.padEnd(14) + text;

function bar(label, percent, detail) {
  const count = valid(percent) ? Math.round(Math.max(0, Math.min(100, percent)) / 10) : 0;
  return [row(label, ''), { text: '█'.repeat(count) + '░'.repeat(10 - count), tone: tone(percent) },
    ' ' + fmt(percent, 0, 3, '%') + ' | ' + detail];
}

function group(id, title, lines) {
  const section = $(id);
  section.querySelector('h2').textContent = title;
  const pre = section.querySelector('pre');
  const fragment = document.createDocumentFragment();
  lines.forEach((line, index) => {
    if (index) fragment.append('\n');
    for (const piece of Array.isArray(line) ? line : [line]) {
      if (typeof piece === 'string') fragment.append(piece);
      else {
        const span = document.createElement('span');
        span.className = piece.tone;
        span.textContent = piece.text;
        fragment.append(span);
      }
    }
  });
  pre.replaceChildren(fragment);
}

function render(s) {
  const m = s.memory ?? {}, c = s.cpu ?? {}, g = s.gpu ?? {}, swap = s.swap ?? {};
  const t = s.thermals ?? {}, f = s.fans ?? {}, p = s.power ?? {}, w = m.wired_context ?? {};
  const total = fmt(m.total_gb, 0, 0, 'G');
  const uptime = valid(s.uptime_seconds)
    ? Math.floor(s.uptime_seconds / 3600) + 'h ' + Math.floor(s.uptime_seconds % 3600 / 60) + 'm' : '-';
  $('sample').textContent = clean(c.model) + ' | uptime ' + uptime + '\n'
    + new Date(s.sampled_at * 1000).toLocaleTimeString();
  $('sample').className = 'sample';
  group('gpu', 'GPU - ' + clean(g.model) + ' | ' + fmt(g.core_count, 0) + ' cores', [
    bar('util', g.utilization, 'render ' + fmt(g.renderer_util, 0, 3, '%') + ' | tiler ' + fmt(g.tiler_util, 0, 3, '%')),
    bar('alloc', pct(g.alloc_sys_mem_gb, m.total_gb), gb(g.alloc_sys_mem_gb) + ' of ' + total + ' shared'),
    bar('in use', pct(g.in_use_sys_mem_gb, m.total_gb), gb(g.in_use_sys_mem_gb) + ' of ' + total + ' shared'),
  ]);
  group('cpu', 'CPU - ' + fmt(c.count, 0) + ' cores', [
    bar('util', c.utilization, 'busy since previous sample'),
    row('load 1m', fmt(c.load_avg, 2, 6)),
  ]);
  group('memory', 'MEMORY - ' + total, [
    bar('in use', pct(m.in_use_gb, m.total_gb), gb(m.in_use_gb) + ' | reclaimable ~' + gb(m.reclaimable_gb).trim()),
    row('free', gb(m.free_gb)), row('active', gb(m.active_gb)), row('wired', gb(m.wired_gb)),
    row('├── kernel', gb(w.kernel_baseline_gb) + ' | estimate'),
    row('└── other', gb(w.other_wired_estimate_gb) + ' | estimate'),
    row('inactive', gb(m.inactive_gb)), row('speculative', gb(m.speculative_gb)),
    row('purgeable', gb(m.purgeable_gb)), row('compressor', gb(m.compressor_gb)),
  ]);
  group('swap', 'SWAP - ' + fmt(swap.total_mb, 0, 0, 'M'), [
    bar('used', pct(swap.used_mb, swap.total_mb), fmt(swap.used_mb, 0, 6, 'M')),
  ]);
  const pressure = s.memory_pressure ?? '-';
  group('pressure', 'PRESSURE', [[{ text: '  ' + pressure,
    tone: pressure === 'OK' ? 'success' : pressure === 'MODERATE' ? 'warning' : pressure === 'CRITICAL' ? 'urgent' : '' }]]);
  group('thermals', 'THERMALS - current hottest | max observed', [
    ...[['cpu', 'cpu'], ['gpu', 'gpu'], ['memory', 'mem'], ['soc', 'soc']].map(([label, key]) => {
      const current = key === 'soc' ? t.soc : t[key + '_max'];
      const count = key === 'soc' ? (valid(current) ? 1 : null) : t[key + '_count'];
      return row(label, fmt(current, 1, 6, 'C') + ' | max ' + fmt(t[key + '_peak'], 1, 6, 'C')
        + ' | ' + fmt(count, 0, 3) + ' sensors');
    }),
  ]);
  const fanCount = f.count ?? 0;
  group('fans', 'FANS - ' + fanCount, fanCount ? Array.from({ length: fanCount }, (_, i) => {
    const fan = f['F' + i] ?? {};
    return row((i === fanCount - 1 ? '└──' : '├──') + ' F' + i, fmt(fan.rpm, 0, 5, ' RPM')
      + ' | min ' + fmt(fan.min, 0, 5) + ' | max ' + fmt(fan.max, 0, 5));
  }) : [row('', '-')]);
  const processes = c.top ?? [];
  group('processes', 'TOP CPU - ps %CPU', [row('PID', ' CPU % | PROCESS'), ...processes.map((process, i) =>
    row((i === processes.length - 1 ? '└──' : '├──') + ' ' + process.pid,
      fmt(process.cpu, 1, 6, '%') + ' | ' + clean(process.name))),
  ]);
  group('power', 'POWER', [
    row('battery', fmt(p.battery_pct, 0, 6, '%')),
    row('adapter', fmt(p.adapter_watts, 1, 6, 'W')), row('system', fmt(p.system_watts, 1, 6, 'W')),
    row('net', (valid(p.net_watts) ? (p.net_watts >= 0 ? '+' : '') + p.net_watts.toFixed(1) : '-').padStart(6) + 'W'),
  ]);
}

let timer = null;
let loading = false;
async function refresh() {
  clearTimeout(timer);
  if (document.hidden || loading) return;
  loading = true;
  try {
    const response = await fetch('/api/stats', { cache: 'no-store' });
    if (!response.ok) throw new Error('HTTP ' + response.status);
    const snapshot = await response.json();
    if (snapshot.error) throw new Error(snapshot.error);
    render(snapshot);
  } catch (error) {
    $('sample').className = 'sample urgent';
    $('sample').textContent = 'DISCONNECTED - last displayed reading is stale\n' + error.message;
  } finally {
    loading = false;
    if (!document.hidden) timer = setTimeout(refresh, 1500);
  }
}
document.addEventListener('visibilitychange', () => {
  if (document.hidden) clearTimeout(timer);
  else refresh();
});
refresh();
