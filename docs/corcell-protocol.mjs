// Minimal read-only Studio protocol: device info, custom subsystem discovery,
// input-stream enable/disable. No keymap writes or settings reset commands.
export const bytes = (...parts) => Uint8Array.from(parts.flatMap(p => [...p]));
export function varint(n) {
  const out = [];
  do { const b = n % 128; n = Math.floor(n / 128); out.push(b | (n ? 128 : 0)); } while (n);
  return out;
}
export const uint = (tag, n) => bytes(varint(tag * 8), varint(n));
export const message = (tag, data = []) => bytes(varint(tag * 8 + 2), varint(data.length), data);
export function fields(data) {
  if (!(data instanceof Uint8Array)) throw new Error('Missing protobuf message');
  let i = 0;
  function read() {
    let n = 0, scale = 1;
    for (let count = 0; count < 8; count++) {
      if (i >= data.length) throw new Error('Truncated protobuf');
      const b = data[i++]; n += (b & 127) * scale;
      if (!Number.isSafeInteger(n)) throw new Error('Invalid varint');
      if (!(b & 128)) return n;
      scale *= 128;
    }
    throw new Error('Invalid varint');
  }
  const result = new Map();
  while (i < data.length) {
    const key = read(), tag = Math.floor(key / 8), wire = key % 8;
    if (!tag) throw new Error('Invalid protobuf tag');
    let value;
    if (wire === 0) value = read();
    else if (wire === 2 || wire === 1 || wire === 5) {
      const size = wire === 2 ? read() : wire === 1 ? 8 : 4;
      if (i + size > data.length) throw new Error('Truncated protobuf field');
      value = data.slice(i, i + size); i += size;
    } else throw new Error('Unsupported protobuf wire type');
    if (!result.has(tag)) result.set(tag, []);
    result.get(tag).push(value);
  }
  return result;
}
export const one = (data, tag) => fields(data).get(tag)?.[0];
export const text = data => new TextDecoder().decode(data);
export function frame(data) {
  return Uint8Array.from([171, ...[...data].flatMap(b => b >= 171 && b <= 173 ? [172, b] : [b]), 173]);
}
export class Framer {
  constructor() { this.active = false; this.escape = false; this.data = []; }
  push(chunk) {
    const out = [];
    for (const b of chunk) {
      if (!this.active) { if (b === 171) { this.active = true; this.data = []; } continue; }
      if (this.escape) { this.data.push(b); this.escape = false; }
      else if (b === 172) this.escape = true;
      else if (b === 171) this.data = [];
      else if (b === 173) { out.push(Uint8Array.from(this.data)); this.active = false; }
      else this.data.push(b);
      if (this.data.length > 65536) throw new Error('Studio frame too large');
    }
    return out;
  }
}
export function subsystemIndex(response) {
  const listing = one(one(response, 100), 1);
  for (const item of fields(listing).get(1) || []) {
    if (text(one(item, 2)) === 'zmk__input_stream') return one(item, 1) ?? 0;
  }
  throw new Error('入力ストリーム非対応です。Corcellのdya-studio版ファームを確認してください。');
}
export function keyEvent(notification, index) {
  const custom = one(notification, 100);
  if (!custom) return null;
  const envelope = one(custom, 1);
  if (!envelope || (one(envelope, 1) ?? 0) !== index) return null;
  const key = one(one(envelope, 2), 1);
  if (!key) return null;
  return { position: one(key, 1) ?? 0, pressed: (one(key, 2) ?? 0) !== 0 };
}
export class Coverage {
  constructor(size = 50) { this.size = size; this.reset(); }
  reset() { this.held = new Set(); this.done = new Set(); this.error = false; }
  event(position, pressed) {
    if (!Number.isInteger(position) || position < 0 || position >= this.size) { this.error = true; return false; }
    if (pressed) {
      if (this.held.has(position)) { this.error = true; return false; }
      this.held.add(position);
    } else {
      if (!this.held.delete(position)) { this.error = true; return false; }
      this.done.add(position);
    }
    return true;
  }
  get complete() { return !this.error && this.done.size === this.size && this.held.size === 0; }
}
