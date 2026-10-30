// Read-only CoreX physical switch inspection over its USB Vial interface.
export const COREX_FILTER = {vendorId:0x4c4b,productId:0x4643,usagePage:0xff60,usage:0x61};
const UID = '436f726558525931';
const DEFINITION_HASH = 'c07519690d5c9ae5d41496d3b2f4046962259de8b169f5bacb3e755245f26a49';
const hex = bytes => [...bytes].map(n=>n.toString(16).padStart(2,'0')).join('');
const delay = ms => new Promise(resolve=>setTimeout(resolve,ms));
const view = bytes => new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);

export function matchesCoreX(device) {
  const visit = list => list.some(c=>c.usagePage===0xff60 && c.usage===0x61 &&
    c.inputReports?.some(r=>r.reportId===0) && c.outputReports?.some(r=>r.reportId===0) || visit(c.children??[]));
  return device.vendorId===0x4c4b && device.productId===0x4643 && visit(device.collections??[]);
}

export function readOnlyRequest(bytes) {
  return bytes.length===1 && [1,0x11].includes(bytes[0]) ||
    bytes.length===2 && bytes[0]===2 && [3,4].includes(bytes[1]) ||
    bytes.length===2 && bytes[0]===0xfe && [0,1].includes(bytes[1]) ||
    bytes.length===4 && bytes[0]===0xfe && bytes[1]===2;
}

export class CoreXTransport {
  constructor(device, timeout=2000) {
    this.device=device;this.timeout=timeout;this.pending=null;this.failed=false;
    this.onReport=event=>{
      if(event.reportId!==0)return;
      if(!this.pending || event.data.byteLength!==32) {
        this.abort(new Error('通信が競合しました。StudioやVialを閉じて、再接続してください。'));return;
      }
      const pending=this.pending;this.pending=null;clearTimeout(pending.timer);
      pending.resolve(new Uint8Array(event.data.buffer,event.data.byteOffset,32).slice());
    };
    device.addEventListener('inputreport',this.onReport);
  }
  exchange(bytes) {
    if(!readOnlyRequest(bytes))return Promise.reject(new Error('点検では設定変更を送信できません。'));
    if(this.failed || !this.device.opened)return Promise.reject(new Error('USB接続が切れました。'));
    if(this.pending)return Promise.reject(new Error('通信中です。'));
    const packet=new Uint8Array(32);packet.set(bytes);
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>this.abort(new Error('本体から応答がありません。USBをつなぎ直してください。')),this.timeout);
      this.pending={resolve,reject,timer};
      this.device.sendReport(0,packet).catch(error=>this.abort(error));
    });
  }
  abort(error=new Error('USB接続を終了しました。')) {
    this.failed=true;
    if(this.pending){clearTimeout(this.pending.timer);this.pending.reject(error);this.pending=null;}
  }
  async close() {
    this.abort();this.device.removeEventListener('inputreport',this.onReport);
    if(this.device.opened)await this.device.close();
  }
}

export async function identifyCoreX(transport, digest=bytes=>crypto.subtle.digest('SHA-256',bytes)) {
  const command=async(bytes,echo=0)=>{
    const reply=await transport.exchange(bytes);
    if(reply.length!==32 || bytes.slice(0,echo).some((n,i)=>reply[i]!==n))throw new Error('本体の応答を確認できません。');
    return reply;
  };
  const protocol=await command([1],1),id=await command([0xfe,0]);
  if(view(protocol).getUint16(1)!==9 || view(id).getUint32(0,true)!==6 || hex(id.slice(4,12))!==UID)
    throw new Error('この点検はCoreX rev1.0用です。');
  const firmware=view(await command([2,4],2)).getUint32(2);
  if(firmware<2821)throw Object.assign(new Error('右側ファームを更新すると、レイヤーキーも点検できます。'),{needsUpdate:true});
  if(![2821,2822,2823,2824].includes(firmware) || (await command([0x11],1))[1]!==7)
    throw new Error('このファームのキー位置を確認できません。');
  const size=view(await command([0xfe,1])).getUint32(0,true);
  if(size!==2116)throw new Error('本体のキー配列が一致しません。');
  const definition=new Uint8Array(size);
  for(let page=0;page<Math.ceil(size/32);page++) {
    const reply=await command([0xfe,2,page&255,page>>8]);
    definition.set(reply.slice(0,Math.min(32,size-page*32)),page*32);
  }
  if(hex(new Uint8Array(await digest(definition)))!==DEFINITION_HASH)throw new Error('本体のキー配列が一致しません。');
  return {firmware,uid:UID};
}

// Device coordinates, not KLE/canonical coordinates. Labels identify the
// standard key position; custom assignments never affect physical detection.
const LABELS = [
  ['Backspace','P','O','I','U','Y',null],
  ['Enter','\\','L','K','J','H',null],
  ['/','↑','.', ',','M','N','右ダイヤル押込み'],
  ['→','↓','←','トラボ裏','L6','右Space',null],
  ['Tab','Q','W','E','R','T',null],
  ['Caps','A','S','D','F','G',null],
  ['Shift','Z','X','C','V','B','左ダイヤル押込み'],
  ['Ctrl','Command','Alt','L1','L4','左Space',null],
];
export const physicalLabel=(row,col)=>LABELS[row]?.[col]??`行${row+1}・列${col+1}`;

export function decodeMatrix(reply) {
  if(reply.length!==32 || reply[0]!==2 || reply[1]!==3)throw new Error('キー状態を読み取れません。StudioやVialを閉じて再接続してください。');
  const pressed=new Set();
  for(let row=0;row<8;row++)for(let col=0;col<7;col++)if(reply[2+row]&(1<<col))pressed.add(row*7+col);
  return pressed;
}

export class PhysicalEdges {
  constructor(){this.pressed=new Map();}
  update(pressed,time) {
    const events=[];
    for(const [id,start] of this.pressed)if(!pressed.has(id)) {
      events.push({id,direction:'up',holdMs:Math.max(0,Math.round(time-start))});this.pressed.delete(id);
    }
    for(const id of pressed)if(!this.pressed.has(id)) {
      this.pressed.set(id,time);events.push({id,direction:'down',holdMs:null});
    }
    return events;
  }
}

export class CoreXSession {
  constructor(device,{onEvent=()=>{},onReady=()=>{},delayMs=10,now=()=>performance.now(),digest}={}) {
    Object.assign(this,{device,onEvent,onReady,delayMs,now,digest});this.stopped=false;this.transport=null;
  }
  async run() {
    try {
      await this.device.open();
      if(this.stopped)return;
      this.transport=new CoreXTransport(this.device);
      await identifyCoreX(this.transport,this.digest);
      if(this.stopped)return;
      const edges=new PhysicalEdges();
      // Validate the first matrix reply before claiming the board is ready.
      let pressed=decodeMatrix(await this.transport.exchange([2,3]));
      if(this.stopped)return;
      this.onReady();
      while(!this.stopped) {
        for(const event of edges.update(pressed,this.now()))this.onEvent(event);
        await delay(this.delayMs);
        if(this.stopped)break;
        pressed=decodeMatrix(await this.transport.exchange([2,3]));
      }
    } catch(error) { if(!this.stopped)throw error; }
    finally {
      if(this.transport)await this.transport.close().catch(()=>{});
      else if(this.device.opened)await this.device.close().catch(()=>{});
    }
  }
  stop(){this.stopped=true;this.transport?.abort();}
}
