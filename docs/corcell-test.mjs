import { Coverage } from './corcell-protocol.mjs';
import { StudioSession } from './corcell-session.mjs';
const panel = document.getElementById('corcellTest');
const status = panel.querySelector('[data-status]');
const progress = panel.querySelector('[data-progress]');
const connect = panel.querySelector('[data-connect]');
const disconnect = panel.querySelector('[data-disconnect]');
const coverage = new Coverage();
const labels = 'ESC Q W E R T Y U I O P BS TAB A S D F G H J K L : ENTER SHIFT Z X C V B 9 8 N M , . ↑ / CTRL GUI ALT L1 L2 SPACE SPACE L3 A ← ↓ →'.split(' ');
const cells = labels.map((label, position) => {
  const cell = document.createElement('div');
  cell.className = 'physical-key'; cell.textContent = label;
  cell.title = `位置 ${position}（初期配列: ${label}）`;
  panel.querySelector('[data-keys]').append(cell); return cell;
});
let session = null, busy = false, reconnectPort = null;
window.corcellPhysicalMode = false;
function setStatus(value) { status.textContent = value; }
function render() {
  cells.forEach((cell, i) => { cell.classList.toggle('held', coverage.held.has(i)); cell.classList.toggle('done', coverage.done.has(i)); });
  progress.textContent = coverage.error ? 'イベントの欠落・不整合を検出しました。「検査をやり直す」で再検査してください。' : `${coverage.done.size} / 50 キー確認済み${coverage.complete ? ' ✓ 全キーの押下・解放を確認' : ` ・押下中 ${coverage.held.size}`}`;
  progress.classList.toggle('passed', coverage.complete);
}
function reset() { coverage.reset(); window.dispatchEvent(new Event('corcell-silence')); render(); }
function physical(event) {
  if (!session?.enabled) return;
  if (coverage.event(event.position, event.pressed)) window.dispatchEvent(new CustomEvent('corcell-key', { detail: event }));
  render();
}

async function lost(target) {
  window.corcellPhysicalMode = false;
  reset(); setStatus('USB切断・検査結果をクリアしました。同じポートの再接続を待っています。');
  await target.close();
  if (session === target) session = null;
  connect.disabled = false;
  disconnect.disabled = true;
}
async function start(port) {
  if (busy || session) return;
  busy = true; connect.disabled = true; reset(); setStatus('Corcellを確認しています…');
  const candidate = new StudioSession(port, physical, target => { if (session === target) void lost(target); }); session = candidate;
  try {
    await candidate.open();
    reconnectPort = port; window.corcellPhysicalMode = true;
    setStatus('Corcell 接続中 — 各キーを1つずつ押して、離してください。');
    disconnect.disabled = false;
  } catch (error) {
    await candidate.close(); if (session === candidate) session = null;
    setStatus(`${error.message} DYA Studioなど、同じポートを使うタブは閉じてください。`);
  } finally { busy = false; connect.disabled = !!session; }
}
connect.addEventListener('click', async () => {
  window.dispatchEvent(new Event('corcell-audio'));
  if (session || busy) return;
  try { await start(await navigator.serial.requestPort({ filters: [{ usbVendorId: 0x1d50, usbProductId: 0x615e }] })); }
  catch (error) { if (error.name !== 'NotFoundError') setStatus(error.message); }
});
disconnect.addEventListener('click', async () => {
  reconnectPort = null; window.corcellPhysicalMode = false;
  const target = session; if (!target) return;
  busy = true; connect.disabled = true; disconnect.disabled = true;
  await target.close(); session = null; reset(); setStatus('切断しました。通常のキー検査に戻りました。');
  busy = false; connect.disabled = false;
});
panel.querySelector('[data-reset]').addEventListener('click', reset);
panel.querySelector('[data-report]').addEventListener('click', () => {
  const report = { date: new Date().toISOString(), device: session?.name || null, connected: !!session?.enabled,
    result: session?.enabled && coverage.complete ? 'ALL_KEYS_OBSERVED' : 'INCOMPLETE',
    checkedPositions: [...coverage.done].sort((a,b) => a-b), heldPositions: [...coverage.held], eventError: coverage.error,
    note: '物理キー50個の押下・解放のみ。チャタリング、無線、ポインタ、電池などの出荷検査は別途必要。' };
  const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' }));
  const a = document.createElement('a'); a.href = url; a.download = 'corcell-key-test.json'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
});
if (!navigator.serial || !window.isSecureContext) {
  connect.disabled = true; setStatus('USB物理キー検査はPC版Chrome / EdgeのHTTPSまたはlocalhostで利用できます。');
} else {
  navigator.serial.addEventListener('connect', event => { if (event.target === reconnectPort && !session) void start(reconnectPort); });

}
render();
