import {COREX_FILTER,matchesCoreX,CoreXSession,physicalLabel} from './corex-hid.mjs';

const connect=document.getElementById('corexConnect'),status=document.getElementById('corexStatus');
const update=document.getElementById('corexUpdate');
let session=null,task=null,active=false,choosing=false,allowed=true,epoch=0;
const failed=new WeakSet();
const setActive=value=>{active=value;window.dispatchEvent(new CustomEvent('corex-inspection',{detail:{active:value}}));};
function paint(message){status.textContent=message;connect.disabled=choosing;connect.textContent=session?'別のCoreXを接続':'CoreXを接続';}
async function stop() {
  const current=++epoch;setActive(false);
  const old=session,oldTask=task;session=null;task=null;old?.stop();await oldTask?.catch(()=>{});
  return current;
}
async function attach(device) {
  if(!allowed || document.hidden || !matchesCoreX(device) || device===session?.device)return;
  const current=await stop();
  if(current!==epoch || !allowed || document.hidden)return;
  update.hidden=true;paint('CoreXを確認しています…');
  session=new CoreXSession(device,{
    onReady(){if(current!==epoch)return;setActive(true);paint('CoreX接続済み · L1・L4・L6も、そのまま押して点検できます');},
    onEvent(event){
      if(current!==epoch)return;
      const row=Math.floor(event.id/7),col=event.id%7;
      window.dispatchEvent(new CustomEvent('corex-key',{detail:{
        direction:event.direction,label:JSON.stringify({physical_key:physicalLabel(row,col)}),
        flagsText:'',usagePage:row,usage:col,physical:true,
        extra:'CoreXの物理キー（標準配列の位置名）',holdMs:event.holdMs,isChatter:false,
      }}));
    },
  });
  task=session.run().catch(error=>{
    if(current!==epoch)return;
    failed.add(device);setActive(false);session=null;task=null;
    update.hidden=!error.needsUpdate;paint(error.message);
  });
}
async function reconnect() {
  if(!allowed || document.hidden || session || choosing)return;
  const scanEpoch=epoch;
  try {
    const devices=(await navigator.hid.getDevices()).filter(d=>matchesCoreX(d)&&!failed.has(d));
    if(scanEpoch!==epoch || !allowed || document.hidden || session || choosing)return;
    // Never guess which board to inspect when several are connected.
    if(devices.length===1)await attach(devices[0]);
    else if(devices.length>1)paint('複数のCoreXが接続されています。点検する本体を選んでください。');
  } catch(error){paint(error.message);}
}
if(!navigator.hid) {
  connect.disabled=true;paint('CoreXの物理キー点検はChromeまたはEdgeで開いてください。');connect.disabled=true;
} else {
  connect.addEventListener('click',async()=>{
    // RequestDevice must run directly in this user gesture, before awaiting I/O.
    choosing=true;connect.disabled=true;allowed=true;
    try {
      const [device]=await navigator.hid.requestDevice({filters:[COREX_FILTER]});
      if(device){failed.delete(device);await attach(device);}
    } catch(error){if(error.name!=='NotFoundError')paint(error.message);}
    finally{choosing=false;connect.disabled=false;}
  });
  navigator.hid.addEventListener('connect',event=>{
    failed.delete(event.device);void reconnect();
  });
  navigator.hid.addEventListener('disconnect',async event=>{
    if(event.device!==session?.device)return;
    await stop();paint('次のCoreXをUSBでつないでください。');void reconnect();
  });
  document.addEventListener('visibilitychange',async()=>{
    if(document.hidden){await stop();paint('点検を一時停止しています。');}
    else {paint('許可済みのCoreXを待っています。');void reconnect();}
  });
  window.addEventListener('pagehide',()=>{allowed=false;void stop();});
  window.addEventListener('pageshow',()=>{allowed=true;void reconnect();});
  void reconnect();
}
