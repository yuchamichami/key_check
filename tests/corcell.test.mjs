import test from 'node:test';
import assert from 'node:assert/strict';
import { bytes, uint, message, fields, one, frame, Framer, subsystemIndex, keyEvent, Coverage } from '../docs/corcell-protocol.mjs';
test('framing escapes all delimiters across arbitrary USB chunks', () => {
  const raw = Uint8Array.from([0,171,172,173,255]);
  const parser = new Framer();
  const results = [...frame(raw)].flatMap(b => parser.push([b]));
  assert.deepEqual(results, [raw]);
  assert.deepEqual(parser.push(bytes(frame(raw), frame(raw))), [raw,raw]);
});
test('malformed protobuf and oversized frames are rejected', () => {
  for (const raw of [[10,5,1], [8,128], [0], [15]]) assert.throws(() => fields(Uint8Array.from(raw)));
  assert.throws(() => new Framer().push([171,...new Array(65537).fill(1)]));
});
test('discovers actual input-stream index including zero', () => {
  for (const index of [0,3,200]) {
    const info = bytes(uint(1,index), message(2,new TextEncoder().encode('zmk__input_stream')));
    assert.equal(subsystemIndex(message(100,message(1,message(1,info)))),index);
  }
  assert.throws(() => subsystemIndex(message(100,message(1))));
});
test('position zero and release false use protobuf defaults; other subsystems ignored', () => {
  const notification = (index, payload) => message(100,message(1,bytes(uint(1,index),message(2,message(1,payload)))));
  assert.deepEqual(keyEvent(notification(0, uint(2,1)),0), {position:0,pressed:true});
  assert.deepEqual(keyEvent(notification(0, new Uint8Array()),0), {position:0,pressed:false});
  assert.equal(keyEvent(notification(1,uint(2,1)),0),null);
  assert.equal(keyEvent(message(100,message(1,message(2,message(2,uint(1,4))))),0),null);
});
test('pass requires 50 matched press/release pairs; reset clears previous unit', () => {
  const c = new Coverage();
  for (let i=0;i<50;i++) { c.event(i,true); if(i<49)c.event(i,false); }
  assert.equal(c.complete,false); c.event(49,false); assert.equal(c.complete,true);
  c.reset(); assert.equal(c.complete,false); assert.equal(c.done.size,0);
});
test('unmatched releases, duplicate presses and unexpected positions invalidate result', () => {
  for (const events of [[[0,false]],[[0,true],[0,true]],[[50,true]]]) {
    const c = new Coverage(); events.forEach(args => c.event(...args));
    assert.equal(c.error,true); assert.equal(c.complete,false);
  }
});
test('request fixture matches upstream protobuf field numbers', () => {
  assert.deepEqual([...bytes(uint(1,1),message(100,message(1)))],[8,1,162,6,2,10,0]);
  assert.deepEqual([...one(message(100,message(2,bytes(uint(1,3),message(2,message(1))))),100)],[18,6,8,3,18,2,10,0]);
});

import { StudioSession } from '../docs/corcell-session.mjs';
class FakePort {
  constructor({ name = 'Corcell', rejectEnable = false } = {}) {
    this.name = name; this.rejectEnable = rejectEnable; this.writes = [];
    this.readable = new ReadableStream({start: controller => {this.controller = controller;}});
    this.writable = new WritableStream({write: data => this.respond(data)});
  }
  async open(options) { assert.equal(options.baudRate,12500); this.opened = true; }
  async close() { this.opened = false; }
  send(payload) { this.controller.enqueue(frame(payload)); }
  respond(data) {
    const request = new Framer().push(data)[0]; this.writes.push(request);
    const id = one(request,1); let response;
    if (one(request,3)) response = message(3,message(1,message(1,new TextEncoder().encode(this.name))));
    else if (one(one(request,100),1)) response = message(100,message(1,message(1,bytes(uint(1,7),message(2,new TextEncoder().encode('zmk__input_stream'))))));
    else {
      const call = one(one(request,100),2);
      assert.equal(one(call,1),7);
      const enable = !!one(one(call,2),1);
      this.streamEnabled = enable;
      response = this.rejectEnable ? message(2,uint(1,1)) : message(100,message(2,bytes(uint(1,7),message(2,message(2)))));
    }
    this.send(message(1,bytes(uint(1,id),response)));
  }
  key(position,pressed) {
    this.send(message(2,message(100,message(1,bytes(uint(1,7),message(2,message(1,bytes(uint(1,position),uint(2,Number(pressed))))))))));
  }
}
test('serial session identifies Corcell, enables discovered stream and disables cleanly', async () => {
  const port = new FakePort(), events = [];
  const session = new StudioSession(port, event => events.push(event));
  await session.open(); assert.equal(session.enabled,true); assert.equal(port.streamEnabled,true);
  port.key(41,true); port.key(41,false);
  await new Promise(resolve => setTimeout(resolve,0));
  assert.deepEqual(events,[{position:41,pressed:true},{position:41,pressed:false}]);
  await session.close(); assert.equal(port.streamEnabled,false); assert.equal(port.opened,false);
  assert.equal(port.readable.locked,false); assert.equal(port.writable.locked,false);
});
test('other keyboards and locked streams cannot start a test', async () => {
  for (const options of [{name:'Other keyboard'},{rejectEnable:true}]) {
    const session = new StudioSession(new FakePort(options));
    await assert.rejects(session.open()); assert.equal(session.enabled,false); await session.close();
  }
});
test('cable loss is reported and read locks released', async () => {
  const port = new FakePort(); let lost;
  const session = new StudioSession(port,()=>{}, value=> { lost = value; });
  await session.open(); port.controller.error(new Error('unplugged'));
  await session.readTask; assert.equal(lost,session);
  await session.close(); assert.equal(port.readable.locked,false); assert.equal(port.writable.locked,false);
});
