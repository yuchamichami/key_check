import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {COREX_FILTER,matchesCoreX,CoreXTransport,identifyCoreX,decodeMatrix,PhysicalEdges,CoreXSession,readOnlyRequest,physicalLabel} from '../docs/corex-hid.mjs';

const definition=new Uint8Array(await readFile(new URL('./fixtures/corex-rev1.0.xz',import.meta.url)));
const wait=ms=>new Promise(r=>setTimeout(r,ms));
class Device extends EventTarget {
  vendorId=COREX_FILTER.vendorId;productId=COREX_FILTER.productId;opened=false;firmware=2821;requests=[];
  collections=[{usagePage:0xff60,usage:0x61,inputReports:[{reportId:0}],outputReports:[{reportId:0}]}];
  rows=new Uint8Array(8);silent=false;
  async open(){this.opened=true;}
  async close(){this.opened=false;}
  async sendReport(id,packet) {
    assert.equal(id,0);assert.equal(packet.length,32);this.requests.push([...packet]);
    if(this.silent)return;
    const reply=new Uint8Array(32),v=new DataView(reply.buffer);reply.set(packet);
    if(packet[0]===1)v.setUint16(1,9);
    else if(packet[0]===2 && packet[1]===4)v.setUint32(2,this.firmware);
    else if(packet[0]===2 && packet[1]===3)reply.set(this.rows,2);
    else if(packet[0]===0x11)reply[1]=7;
    else if(packet[1]===0){reply.fill(0);v.setUint32(0,6,true);reply.set(new TextEncoder().encode('CoreXRY1'),4);}
    else if(packet[1]===1){reply.fill(0);v.setUint32(0,definition.length,true);}
    else if(packet[1]===2){reply.fill(0);const offset=(packet[2]+256*packet[3])*32;reply.set(definition.slice(offset,offset+32));}
    if(this.mutate)this.mutate(reply,packet);
    queueMicrotask(()=>this.report(reply));
  }
  report(reply) {
    const event=new Event('inputreport');event.reportId=0;
    // A nonzero byteOffset catches accidental decoding of the entire buffer.
    const padded=new Uint8Array(reply.length+4);padded.set(reply,4);
    event.data=new DataView(padded.buffer,4,reply.length);this.dispatchEvent(event);
  }
}

test('selects the vendor interface, never ordinary keyboard collections',()=>{
  assert.ok(matchesCoreX(new Device()));
  const d=new Device();d.collections[0].usagePage=1;assert.equal(matchesCoreX(d),false);
});
test('transport rejects every write/unlock/reset request before USB',async()=>{
  const d=new Device();await d.open();const t=new CoreXTransport(d);
  for(const request of [[5,0,0,0,0,4],[0xa],[0xb],[0xfe,6],[0xfe,7],[0xfe,8],[0xf],[0x10],[0x13]]) {
    assert.equal(readOnlyRequest(request),false);await assert.rejects(t.exchange(request),/設定変更/);
  }
  assert.equal(d.requests.length,0);await t.close();
});
for(const firmware of [2821,2822,2823,2824])test(`checks UID, version ${firmware} and complete definition hash before accepting CoreX`,async()=>{
  const d=new Device();d.firmware=firmware;await d.open();const t=new CoreXTransport(d);
  assert.equal((await identifyCoreX(t)).firmware,firmware);
  assert.equal(d.requests.filter(r=>r[0]===0xfe&&r[1]===2).length,67);
  assert.equal(d.requests.some(r=>r[0]===2&&r[1]===3),false);await t.close();
});
test('old firmware explains update without starting an unlock challenge',async()=>{
  const d=new Device();d.firmware=2820;await d.open();const t=new CoreXTransport(d);
  await assert.rejects(identifyCoreX(t),e=>e.needsUpdate===true);
  assert.equal(d.requests.length,3);assert.equal(d.requests.some(r=>r[0]===0xfe&&r[1]>=5),false);await t.close();
});
test('mismatched definition and unsupported UID stop inspection',async()=>{
  for(const kind of ['uid','hash']) {
    const d=new Device();d.mutate=(reply,request)=>{
      if(request[0]===0xfe&&request[1]===(kind==='uid'?0:2))reply[kind==='uid'?4:0]^=1;
    };
    await d.open();const t=new CoreXTransport(d);await assert.rejects(identifyCoreX(t));await t.close();
  }
});
test('L1 L4 L6 and unassigned positions produce independent down/up events',()=>{
  const reply=new Uint8Array(32);reply.set([2,3]);reply[5]=24;reply[9]=24;
  const edges=new PhysicalEdges(),down=edges.update(decodeMatrix(reply),10);
  assert.deepEqual(down.map(e=>e.id),[24,25,52,53]);
  assert.deepEqual(down.map(e=>physicalLabel(Math.floor(e.id/7),e.id%7)),['トラボ裏','L6','L1','L4']);
  assert.deepEqual(edges.update(decodeMatrix(reply),15),[]);
  reply.fill(0,2);const up=edges.update(decodeMatrix(reply),110);
  assert.equal(up.length,4);assert.ok(up.every(e=>e.direction==='up'&&e.holdMs===100));
  assert.equal(physicalLabel(0,5),'Y');assert.equal(physicalLabel(2,6),'右ダイヤル押込み');
});
test('matrix replies cannot be mistaken for other command replies',()=>{
  assert.throws(()=>decodeMatrix(new Uint8Array(32)));
  assert.throws(()=>decodeMatrix(Uint8Array.from([2,3])));
});
test('session starts on connection, records held keys and closes without a lock/write',async()=>{
  const d=new Device();d.rows[7]=24;const events=[];let ready=0;
  const session=new CoreXSession(d,{delayMs:0,onReady:()=>ready++,onEvent:e=>{
    events.push(e);if(events.length===2)d.rows.fill(0);if(events.length===4)session.stop();
  }});
  await session.run();assert.equal(ready,1);assert.deepEqual(events.map(e=>e.direction),['down','down','up','up']);
  assert.equal(d.opened,false);assert.ok(d.requests.every(r=>[1,2,0x11].includes(r[0])||r[0]===0xfe&&r[1]<=2));
});
test('timeout fails once; subsequent reads are not retried',async()=>{
  const d=new Device();d.silent=true;await d.open();const t=new CoreXTransport(d,5);
  await assert.rejects(t.exchange([2,3]),/応答/);
  await assert.rejects(t.exchange([2,3]),/切れました/);assert.equal(d.requests.length,1);await t.close();
});
test('pending reads are cancelled and malformed reports poison the session',async()=>{
  const d=new Device();d.silent=true;await d.open();const t=new CoreXTransport(d);
  const pending=t.exchange([2,3]);await assert.rejects(t.exchange([2,3]),/通信中/);
  d.report(new Uint8Array(31));await assert.rejects(pending,/競合/);assert.equal(t.failed,true);await t.close();
});

test('browser lifecycle auto-connects, reconnects next boards and pauses hidden pages',async()=>{
  const window=new EventTarget(),document=new EventTarget(),hid=new EventTarget();
  const elements=Object.fromEntries(['corexConnect','corexStatus','corexUpdate'].map(id=>[id,new EventTarget()]));
  document.hidden=false;document.getElementById=id=>elements[id];
  let devices=[new Device()],chosen=null;hid.getDevices=async()=>devices;hid.requestDevice=async()=>chosen?[chosen]:[];
  Object.defineProperty(globalThis,'navigator',{value:{hid},configurable:true});globalThis.window=window;globalThis.document=document;
  const states=[],events=[];window.addEventListener('corex-inspection',e=>states.push(e.detail.active));window.addEventListener('corex-key',e=>events.push(e.detail));
  const until=async predicate=>{for(let i=0;i<100&&!predicate();i++)await wait(5);assert.ok(predicate());};
  await import('../docs/corex-check.mjs');await until(()=>states.at(-1)===true);
  devices[0].rows[7]=8;await until(()=>events.some(e=>e.label.includes('L1')));
  const first=devices[0];devices=[];const lost=new Event('disconnect');lost.device=first;hid.dispatchEvent(lost);
  await until(()=>!first.opened);assert.equal(states.at(-1),false);
  const next=new Device();devices=[next];const plugged=new Event('connect');plugged.device=next;hid.dispatchEvent(plugged);
  await until(()=>next.opened&&states.at(-1)===true);
  document.hidden=true;document.dispatchEvent(new Event('visibilitychange'));await until(()=>!next.opened);
  document.hidden=false;document.dispatchEvent(new Event('visibilitychange'));await until(()=>next.opened&&states.at(-1)===true);
  chosen=new Device();devices=[chosen];elements.corexConnect.dispatchEvent(new Event('click'));
  await until(()=>chosen.opened&&states.at(-1)===true);assert.equal(next.opened,false);
  window.dispatchEvent(new Event('pagehide'));await until(()=>!chosen.opened);
  delete globalThis.window;delete globalThis.document;delete globalThis.navigator;
});
