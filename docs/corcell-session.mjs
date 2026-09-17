import { bytes, uint, message, one, text, frame, Framer, subsystemIndex, keyEvent } from './corcell-protocol.mjs';
export class StudioSession {
  constructor(port, onKey = () => {}, onLost = () => {}) { this.onKey = onKey; this.onLost = onLost; this.port = port; this.pending = new Map(); this.next = 1; this.enabled = false; this.closed = false; }
  async open() {
    await this.port.open({ baudRate: 12500 });
    this.writer = this.port.writable.getWriter();
    this.reader = this.port.readable.getReader();
    this.readTask = this.read();
    const reply = await this.request(3, uint(1, 1));
    this.name = text(one(one(one(reply, 3), 1), 1));
    if (!/^corcell$/i.test(this.name)) throw new Error(`Corcell用の検査です（接続機器: ${this.name || '不明'}）。`);
    this.index = subsystemIndex(await this.request(100, message(1)));
    await this.stream(true);
    this.enabled = true;
  }
  async read() {
    const parser = new Framer();
    try {
      while (!this.closed) {
        const { value, done } = await this.reader.read(); if (done) break;
        for (const packet of parser.push(value)) {
          const response = one(packet, 1), notification = one(packet, 2);
          if (response) {
            const pending = this.pending.get(one(response, 1) ?? 0);
            if (pending) { this.pending.delete(one(response, 1) ?? 0); pending.resolve(response); }
          }
          if (notification && this.enabled) { const event = keyEvent(notification, this.index); if (event) this.onKey(event); }
        }
      }
    } catch (error) { this.readError = error; }
    finally {
      this.reader.releaseLock();
      for (const pending of this.pending.values()) pending.reject(new Error('USB接続が切れました。'));
      this.pending.clear();
      if (!this.closed) this.onLost(this);
    }
  }
  request(tag, payload) {
    const id = this.next++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error('Studioから応答がありません。右側USB・別のポート・USB出力（L3+U）を確認してください。')); }, 2500);
      const settle = fn => value => { clearTimeout(timer); fn(value); };
      this.pending.set(id, { resolve: settle(resolve), reject: settle(reject) });
      this.writer.write(frame(bytes(uint(1, id), message(tag, payload)))).catch(error => {
        this.pending.delete(id); clearTimeout(timer); reject(error);
      });
    });
  }
  async stream(enable) {
    const reply = await this.request(100, message(2, bytes(uint(1, this.index), message(2, message(enable ? 1 : 2)))));
    const custom = one(reply, 100);
    if (!custom) throw new Error('ストリームを開始できません。Studioアンロックとファームを確認してください。');
    const call = one(custom, 2);
    if (!call || (one(call, 1) ?? 0) !== this.index) throw new Error('Studioから想定外の応答です。');
    const payload = one(call, 2), error = one(payload, 1);
    if (error) throw new Error(text(one(error, 1)) || 'ストリームエラー');
    if (!one(payload, 2)) throw new Error('ストリームの応答を確認できません。');
  }
  close() {
    if (!this.closeTask) this.closeTask = this.cleanup();
    return this.closeTask;
  }
  async cleanup() {
    if (this.enabled && !this.readError) { try { await this.stream(false); } catch {} }
    this.enabled = false;
    this.closed = true;
    try { await this.reader?.cancel(); } catch {}
    await this.readTask;
    for (const pending of this.pending.values()) pending.reject(new Error('切断しました。'));
    this.pending.clear();
    try { this.writer?.releaseLock(); await this.port.close(); } catch {}
  }
}
