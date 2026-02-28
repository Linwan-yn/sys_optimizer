import { exec, toast } from './kernelsu.js';

const BASE = '/data/adb/modules/sys_optimizer_webui';
const OIFACE_SCRIPT = `${BASE}/common/oiface_ctl.sh`;

const getConfigValue = (c, k, d) => c.hasOwnProperty(k) ? c[k] : d;
const execWithTimeout = (c, t=10000) => exec(c,{timeout:t}).catch(()=>({errno:1,stdout:'',stderr:'Timeout'}));

const API={
 async initUptime(){const r=await execWithTimeout('cat /proc/uptime|awk \'{print int($1)}\'');return parseInt(r.stdout.trim())||0},
 async getSystemStatus(){const r=await execWithTimeout('echo "model=$(getprop ro.product.model)\\nandroid=$(getprop ro.build.version.release)\\nsdk=$(getprop ro.build.version.sdk)"');const o={};r.stdout.trim().split('\n').forEach(l=>{const[k,v]=l.split('=');if(k)o[k]=v||'Unknown'});return o},
 async getStorageStatus(){const r=await execWithTimeout('df -h /data|tail -1');const p=r.stdout.trim().split(/\s+/);return{total:p[1]||'',used:p[2]||'',free:p[3]||'',percent:p[4]||''}},
 async getModuleStatus(){const c=`
 if [ -f ${BASE}/.service.pid ]; then
  pid=$(cat ${BASE}/.service.pid 2>/dev/null)
  if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then echo "running"
   if [ -f ${BASE}/.service.start_time ]; then start=$(cat ${BASE}/.service.start_time); now=$(date +%s); echo $((now-start))
   else echo 0; fi
  else echo "stopped"; echo 0; fi
 else echo "stopped"; echo 0; fi`;const r=await execWithTimeout(c);const l=r.stdout.trim().split('\n');const s=l[0]||'stopped';const u=parseInt(l[1])||0;const d=Math.floor(u/86400),h=Math.floor((u%86400)/3600),m=Math.floor((u%3600)/60),s_=u%60;const upt=`${d}d ${h}h ${m}m ${s_}s`;const[l_,c_]=await Promise.allSettled([execWithTimeout(`stat -c %y ${BASE}/.last_clean 2>/dev/null|cut -d. -f1||echo "从未"`),execWithTimeout(`cat ${BASE}/.clean_count 2>/dev/null||echo 0`)]).then(r=>r.map(r=>r.value?.stdout?.trim()||(r.status==='fulfilled'?r.value?.stdout?.trim():'从未')));return{status:s,uptime:upt,uptimeSeconds:u,last_clean:l_||'从未',clean_count:c_||'0'}},
 async getConfig(){const r=await execWithTimeout(`cat ${BASE}/common/config.conf|grep -v "^#"|grep "="`);const c={};r.stdout.trim().split('\n').forEach(l=>{const[k,v]=l.split('=');if(k)c[k]=v});return c},
 async saveConfig(c){const cmds=Object.entries(c).map(([k,v])=>`sed -i 's/^${k}=.*/${k}=${v}/' ${BASE}/common/config.conf`).join('&&');const r=await execWithTimeout(cmds,15000);return r.errno===0},
 async setConfigItem(k,v){const r=await execWithTimeout(`sed -i 's/^${k}=.*/${k}=${v}/' ${BASE}/common/config.conf`,5000);return r.errno===0},
 async cleanNow(){await execWithTimeout(`rm -f ${BASE}/.clean_finished;touch ${BASE}/.trigger_clean`);toast('🧹 清理任务已提交')},
 async optimizeNow(){await execWithTimeout(`rm -f ${BASE}/.optimize_finished;touch ${BASE}/.trigger_optimize`);toast('⚡ 优化任务已提交')},
 async dataCleanNow(){await execWithTimeout(`rm -f ${BASE}/.data_clean_finished;touch ${BASE}/.trigger_data_clean`);toast('📁 Android/data清理已提交')},
 async restartService(){
  try{
   const pidR=await execWithTimeout(`cat ${BASE}/.service.pid 2>/dev/null`);const pid=pidR.stdout.trim();
   if(!pid){const p=await execWithTimeout(`pgrep -f '${BASE}/service.sh' 2>/dev/null`);if(p.stdout.trim()){await execWithTimeout(`pkill -f '${BASE}/service.sh'`);toast('⚠️ 服务进程异常，已强制终止');setTimeout(()=>toast('🔄 服务正在重启...'),1000)}else toast('❌ 服务未运行');return}
   const alive=await execWithTimeout(`kill -0 ${pid} 2>/dev/null&&echo alive`);if(!alive.stdout.includes('alive')){await execWithTimeout(`rm -f ${BASE}/.service.pid`);toast('⚠️ 服务已停止，已清理残留 PID');return}
   const k=await execWithTimeout(`kill ${pid} 2>&1&&echo ok`);if(k.stdout.includes('ok')){await execWithTimeout(`rm -f ${BASE}/.service.pid`);toast('🔄 服务停止信号已发送，正在重启...');let a=0;const iv=setInterval(async()=>{const np=await execWithTimeout(`cat ${BASE}/.service.pid 2>/dev/null`);if(np.stdout.trim()){toast('✅ 服务已成功重启');clearInterval(iv)}else if(++a>=10){toast('⚠️ 服务重启可能超时，请检查日志');clearInterval(iv)}},1000)}else{console.error('kill failed:',k.stderr);toast('❌ 无法停止服务：'+(k.stderr||'未知错误'))}
  }catch(e){console.error('restartService error:',e);toast('❌ 重启服务时发生错误')}},
 async checkTaskFinished(t){const m={clean:'.clean_finished',optimize:'.optimize_finished',dataClean:'.data_clean_finished'};const r=await execWithTimeout(`[ -f ${BASE}/${m[t]} ]&&echo 1||echo 0`);return r.stdout.trim()==='1'},
 async getLogs(){try{const c=await execWithTimeout(`[ -f ${BASE}/logs/service.log ]&&echo 1||echo 0`);if(c.stdout.trim()!=='1')return'日志文件未创建，请等待服务写入';const r=await execWithTimeout(`tail -50 ${BASE}/logs/service.log 2>/dev/null||echo "暂无日志"`);return(r.stdout&&r.stdout.trim()!=='')?r.stdout:'暂无日志，请等待服务写入或手动触发清理'}catch{return'获取日志失败'}},
 async clearLogs(){await execWithTimeout(`> ${BASE}/logs/service.log`);toast('📋 日志已清空')},
 async getSmoothnessScore(){const r=await execWithTimeout(`cat ${BASE}/.smoothness_score 2>/dev/null||echo "score=100\\nimprovement=0"`);const o={};r.stdout.trim().split('\n').forEach(l=>{const[k,v]=l.split('=');if(k)o[k]=v});return o},
 async getRamInfo(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&get_ram_info`);const o={};r.stdout.trim().split('\n').forEach(l=>{const[k,v]=l.split('=');if(k)o[k]=v});return o},
 async getAllCpuInfo(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&get_cpu_all`);const l=r.stdout.trim().split('\n');let u=0;const f=[];l.forEach(l=>{if(l.startsWith('usage='))u=parseFloat(l.split('=')[1])||0;else if(l.includes('=')){const[c,vals]=l.split('=');const[cur,max]=vals.split(',').map(Number);f.push({core:c,cur,max})}});return{usage:u,freqs:f}},
 async getGpuInfo(s){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&get_gpu_info ${s}`,3000);const l=r.stdout.trim().split('\n');const o={};l.forEach(l=>{const[k,v]=l.split('=');if(k)o[k]=parseInt(v)||0});return{freq:o.freq||0,load:o.load||0}},
 async getBatteryInfo(s){
  if(s==='shell_detailed')return this.getBatteryInfoDetailed();
  else if(s==='aling')return this.getBatteryInfoAling();
  else if(s==='xuantian_v2')return this.getXuantianV2Info();
  else if(s==='xuantian_auto')return this.getXuantianAutoInfo();
  else if(s==='detail15')return this.getDetail15Info();
  else return this.getBatteryInfoGeneric()},
 async getBatteryInfoGeneric(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&battery_info`,5000);try{return JSON.parse(r.stdout)}catch{return null}},
 async getBatteryInfoDetailed(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&battery_info_detailed`,5000);try{return JSON.parse(r.stdout)}catch{return null}},
 async getBatteryInfoAling(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&battery_info_aling`,5000);try{return JSON.parse(r.stdout)}catch{return null}},
 async getXuantianV2Info(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&xuantian_v2_info`,5000);try{return JSON.parse(r.stdout)}catch{return null}},
 async getXuantianAutoInfo(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&xuantian_auto_info`,5000);try{return JSON.parse(r.stdout)}catch{return null}},
 async getDetail15Info(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&battery_detail15_info`,5000);try{return JSON.parse(r.stdout)}catch{return null}},
 async setCellType(t){await execWithTimeout(`echo "${t}">${BASE}/common/cell_type.conf`);fetchBatteryData()},
 async getCellType(){const r=await execWithTimeout(`cat ${BASE}/common/cell_type.conf 2>/dev/null||echo "dual"`);return r.stdout.trim()},
 async setAlingType(t){await execWithTimeout(`echo "${t}">${BASE}/common/aling_type.conf`);fetchBatteryData()},
 async openCoolapkAuthor(){await execWithTimeout('am start -a android.intent.action.VIEW -d "https://www.coolapk.com/u/1779411"')},
 async openTGChannel(){await execWithTimeout('am start -a android.intent.action.VIEW -d "tg://resolve?domain=Whitelist520"')},
 async getCommonBatteryInfo(){const c=await execWithTimeout('cat /sys/class/power_supply/battery/capacity 2>/dev/null||echo 0');const v=await execWithTimeout('cat /sys/class/power_supply/battery/voltage_now 2>/dev/null||echo 0');const i=await execWithTimeout('cat /sys/class/power_supply/battery/current_now 2>/dev/null||echo 0');const t=await execWithTimeout('cat /sys/class/power_supply/battery/temp 2>/dev/null||echo 0');const cy=await execWithTimeout('cat /sys/class/power_supply/battery/cycle_count 2>/dev/null||echo 0');const d=await execWithTimeout('cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null||echo 0');const f=await execWithTimeout('cat /sys/class/power_supply/battery/charge_full 2>/dev/null||echo 0');const u=await execWithTimeout('cat /sys/class/power_supply/usb/online 2>/dev/null||echo 0');let p='未知';const ct=await execWithTimeout('cat /sys/class/power_supply/battery/charge_type 2>/dev/null||echo ""');const ut=await execWithTimeout('cat /sys/class/power_supply/usb/type 2>/dev/null||echo ""');if(ct.stdout.trim()){const ty=ct.stdout.trim();if(ty=='2')p='普通充电(5V/9V)';else if(ty=='8')p='有线快充(VOOC基础)';else if(ty=='14')p='超级快充(SVOOC)';else if(ty=='16')p='PD快充';else p=ty}else if(ut.stdout.trim())p=ut.stdout.trim();return{capacity:parseInt(c.stdout)||0,voltage:parseInt(v.stdout)/1000000,current:parseInt(i.stdout)/1000,temperature:parseInt(t.stdout)/10,cycleCount:parseInt(cy.stdout)||0,designCapacity:parseInt(d.stdout)/1000,fcc:parseInt(f.stdout)/1000,usbOnline:parseInt(u.stdout)||0,protocol:p}},
 async getOifaceStatus(){const r=await execWithTimeout(`sh ${OIFACE_SCRIPT} status`);const l=r.stdout.split('\n');let m='',s='';l.forEach(l=>{if(l.startsWith('mode='))m=l.split('=')[1];if(l.startsWith('service='))s=l.split('=')[1]});return{mode:m||'0',service:s||'stopped'}},
 async setOiface(a){const r=await execWithTimeout(`sh ${OIFACE_SCRIPT} ${a}`);return r.stdout.trim()},
 async getSelinuxStatus(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&selinux_status`);const o={};r.stdout.trim().split('\n').forEach(l=>{const[k,v]=l.split('=');if(k)o[k]=v});return o},
 async setSelinux(m){const cmd=m==='enforcing'?'selinux_set_enforcing':'selinux_set_permissive';const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&${cmd}`);return r.stdout.trim()},
 async getWhitelist(){const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&battery_whitelist_list`);return r.stdout.trim().split('\n').filter(l=>l.trim())},
 async addToWhitelist(p){
  const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&battery_whitelist_add '${p}'`);
  // 添加成功后，UI上的白名单列表会在refresh时更新
  return r.stdout.trim();
 },
 async removeFromWhitelist(p){
  const r=await execWithTimeout(`. ${BASE}/common/functions.sh&&battery_whitelist_remove '${p}'`);
  return r.stdout.trim();
 },
 async getAllApps(){const r=await execWithTimeout(`pm list packages`);return r.stdout.trim().split('\n').map(l=>l.replace('package:','')).filter(l=>l.trim())},
 async runF2fsGC(){await execWithTimeout(`nohup sh ${BASE}/common/f2fs_gc_daemon.sh>>${BASE}/logs/f2fs_gc_daemon.log 2>&1 &`);toast('F2FS 回收任务已在后台启动')},
 async getF2fsGCLog(){const r=await execWithTimeout(`cat ${BASE}/logs/f2fs_gc_daemon.log 2>/dev/null||echo "暂无日志"`);return r.stdout},
 async isColorOSInstalled(){const r=await execWithTimeout('pm list packages com.coloros.phonemanager');return r.stdout.includes('com.coloros.phonemanager')},
 async getBatteryHistory(){const r=await execWithTimeout(`tail -200 ${BASE}/logs/battery_history.log 2>/dev/null||echo ""`);const l=r.stdout.trim().split('\n').filter(l=>l);return l.map(l=>{const[t,cap,volt,curr,temp]=l.split(',');return{time:t,capacity:parseInt(cap),voltage:parseFloat(volt),current:parseFloat(curr),temperature:parseFloat(temp)}})}
};

const idToConfigKey={
 cleanInterval:'clean_interval',androidDataClean:'android_data_clean',dataCacheThreshold:'data_cache_threshold_mb',skipApps:'skip_apps',customCleanTimes:'custom_clean_times',enableFstrim:'enable_fstrim',fstrimFrequency:'fstrim_frequency',backgroundControlMode:'background_control_mode',enableIoOpt:'enable_io_opt',enableReadAhead:'enable_read_ahead',enableCpuGov:'enable_cpu_gov',enableGpuOpt:'enable_gpu_opt',enablePowerSave:'enable_power_save',dex2oatOptimization:'dex2oat_optimization',logLevelSelect:'log_level',logRetentionDays:'log_retention_days',storageWarning:'storage_warning',storageCritical:'storage_critical',enableF2fsDaemon:'enable_f2fs_daemon',f2fsCheckInterval:'f2fs_check_interval',processSuppressMode:'process_suppress_mode',processSuppressAdj:'process_suppress_adj',smartAvoidPkgs:'smart_avoid_packages',memoryLockDirs:'memory_lock_dirs',adblockEnable:'adblock_enable',adblockUpdateInterval:'adblock_update_interval',fileCleanRules:'file_clean_rules',f2fsDirtyThreshold:'f2fs_dirty_threshold_mb',f2fsGcSleep:'f2fs_gc_sleep',chargeDetectMode:'charge_detect_mode',lowVoltageShutdown:'low_voltage_shutdown',shutdownVoltage:'shutdown_voltage',shutdownDelay:'shutdown_delay',bootMinTime:'boot_minimum_time',notifyMode:'notify_mode',notifyEvents:'notify_events',batteryHistoryInterval:'battery_history_interval',batteryHistoryMaxLines:'battery_history_max_lines',forceDeviceType:'force_device_type',enableBatteryHealthDiagnosisBatt:'enable_battery_health_diagnosis',enableBatteryUnlockBatt:'enable_battery_unlock',enableDeepCycleCounterBatt:'enable_deep_cycle_counter',enableModBatteryDetectionBatt:'enable_mod_battery_detection',enableFastChargeRepairBatt:'enable_fast_charge_repair',
 // 新增白名单恢复延迟
 whitelistRestoreDelay:'whitelist_restore_delay'
};
const batteryAdvancedMap={enableBatteryHealthDiagnosisBatt:'enable_battery_health_diagnosis',enableBatteryUnlockBatt:'enable_battery_unlock',enableDeepCycleCounterBatt:'enable_deep_cycle_counter',enableModBatteryDetectionBatt:'enable_mod_battery_detection',enableFastChargeRepairBatt:'enable_fast_charge_repair'};

const UI={
 setText(id,v){const e=document.getElementById(id);if(e)e.textContent=v},
 updateHome(mod,sys,storage,smooth,battery){
  this.setText('homeServiceStatus',mod.status==='running'?'运行中':'已停止');
  const se=document.getElementById('homeServiceStatus');if(se)se.className=mod.status==='running'?'value status-running':'value status-stopped';
  this.setText('homeUptime',mod.uptime||'0d 0h 0m 0s');
  this.setText('homeCleanCount',mod.clean_count||'0');
  this.setText('homeLastClean',mod.last_clean||'从未');
  this.setText('homeSysModel',sys.model||'未知');
  this.setText('homeSysAndroid',sys.android||'未知');
  this.setText('homeSysSdk',sys.sdk||'未知');
  this.setText('homeStorageTotal',storage.total||'未知');
  this.setText('homeStorageUsed',storage.used||'未知');
  this.setText('homeStorageFree',storage.free||'未知');
  const p=parseInt(storage.percent)||0;const f=document.getElementById('homeStorageProgressFill'),t=document.getElementById('homeStorageProgressText');if(f){f.style.width=p+'%';f.className='progress-fill '+(p>=95?'danger':(p>=85?'warning':'success'))}if(t)t.textContent=p+'%';
  const sc=parseInt(smooth.score)||100,im=parseInt(smooth.improvement)||0;
  this.setText('homeSmoothScore',sc+'/100');
  const sf=document.getElementById('homeSmoothProgressFill'),st=document.getElementById('homeSmoothProgressText');if(sf){sf.style.width=sc+'%';sf.className='progress-fill '+(sc<60?'danger':(sc<80?'warning':'success'))}if(st)st.textContent=`可提升 ${im}%`;
 },
 updateSys(d){this.setText('sysModel',d.model||'未知');this.setText('sysAndroid',d.android||'未知');this.setText('sysSdk',d.sdk||'未知')},
 updateStorage(d){
  this.setText('storageTotal',d.total||'未知');this.setText('storageUsed',d.used||'未知');this.setText('storageFree',d.free||'未知');
  const p=parseInt(d.percent)||0;const f=document.getElementById('storageProgressFill'),t=document.getElementById('storageProgressText');if(f){f.style.width=p+'%';f.className='progress-fill '+(p>=95?'danger':(p>=85?'warning':'success'))}if(t)t.textContent=p+'%';
 },
 updateModule(d){
  const s=d.status==='running'?'运行中':'已停止';this.setText('modStatus',s);
  const e=document.getElementById('modStatus');if(e)e.className=d.status==='running'?'value status-running':'value status-stopped';
  this.setText('modLastClean',d.last_clean||'从未');this.setText('modCleanCount',d.clean_count||'0');this.setText('modUptime',d.uptime||'0d 0h 0m 0s');
 },
 updateSmooth(d){const s=parseInt(d.score)||100,i=parseInt(d.improvement)||0;this.setText('smoothScore',s+'/100');const f=document.getElementById('smoothProgressFill'),t=document.getElementById('smoothProgressText');if(f){f.style.width=s+'%';f.className='progress-fill '+(s<60?'danger':(s<80?'warning':'success'))}if(t)t.textContent=`可提升 ${i}%`},
 updateRamPerf(d){this.setText('ramTotalPerf',(d.total||0)+' GB');this.setText('ramUsedPerf',(d.used||0)+' GB');this.setText('ramAvailPerf',(d.avail||0)+' GB');const p=parseInt(d.percent)||0;const f=document.getElementById('ramProgressFillPerf'),t=document.getElementById('ramProgressTextPerf');if(f){f.style.width=p+'%';f.className='progress-fill '+(p>=95?'danger':(p>=85?'warning':'success'))}if(t)t.textContent=p+'%'},
 updateCpuPerf(u,freq){
  const ring=document.getElementById('cpuRingPerf');if(ring){const p=Math.min(100,Math.max(0,u));ring.style.background=`conic-gradient(var(--primary) 0deg ${p*3.6}deg, var(--border-light) ${p*3.6}deg 360deg)`;const t=ring.querySelector('.ring-text');if(t)t.textContent=`${p.toFixed(1)}%`}
  const fc=document.getElementById('cpuFreqBarsPerf');if(!fc)return;if(freq.length===0){fc.innerHTML='<div class="status-item">无法读取频率信息</div>';return}
  let html='';freq.forEach(({core,cur,max})=>{const r=Math.min(1,cur/max),p=(r*100).toFixed(0);html+=`<div style="margin-bottom:6px;"><div style="display:flex;justify-content:space-between;margin-bottom:1px;font-size:0.8rem;"><span style="color:var(--text-secondary);">${core}</span><span style="font-weight:600;">${cur}/${max} MHz</span></div><div style="height:4px;background:var(--border-light);border-radius:2px;overflow:hidden;"><div style="height:100%;width:${p}%;background:var(--primary);border-radius:2px;"></div></div></div>`});fc.innerHTML=html;
 },
 updateGpuPerf(d){
  const ring=document.getElementById('gpuRingPerf');if(ring){const l=Math.min(100,Math.max(0,d.load||0));ring.style.background=`conic-gradient(var(--primary) 0deg ${l*3.6}deg, var(--border-light) ${l*3.6}deg 360deg)`;const t=ring.querySelector('.ring-text');if(t)t.textContent=`${l}%`}
  const f=document.getElementById('gpuFreqPerf');if(f)f.textContent=d.freq?`${d.freq} MHz`:'不可用';
 },
 updateSmoothPerf(d){const s=parseInt(d.score)||100,i=parseInt(d.improvement)||0;this.setText('smoothScorePerf',s+'/100');const f=document.getElementById('smoothProgressFillPerf'),t=document.getElementById('smoothProgressTextPerf');if(f){f.style.width=s+'%';f.className='progress-fill '+(s<60?'danger':(s<80?'warning':'success'))}if(t)t.textContent=`可提升 ${i}%`},
 updateConfig(c){
  const e=id=>document.getElementById(id);
  if(e('cleanInterval'))e('cleanInterval').value = getConfigValue(c,'clean_interval',14400) / 60;
  if(e('androidDataClean'))e('androidDataClean').value=getConfigValue(c,'android_data_clean','1');
  if(e('dataCacheThreshold'))e('dataCacheThreshold').value=getConfigValue(c,'data_cache_threshold_mb',100);
  if(e('skipApps'))e('skipApps').value=getConfigValue(c,'skip_apps','com.tencent.mm,com.taobao.taobao');
  if(e('customCleanTimes'))e('customCleanTimes').value=getConfigValue(c,'custom_clean_times','03:00,15:30');
  if(e('enableFstrim'))e('enableFstrim').value=getConfigValue(c,'enable_fstrim','1');
  if(e('fstrimFrequency'))e('fstrimFrequency').value=getConfigValue(c,'fstrim_frequency','1');
  if(e('backgroundControlMode'))e('backgroundControlMode').value=getConfigValue(c,'background_control_mode','0');
  if(e('enableIoOpt'))e('enableIoOpt').value=getConfigValue(c,'enable_io_opt','0');
  if(e('enableReadAhead'))e('enableReadAhead').value=getConfigValue(c,'enable_read_ahead','0');
  if(e('enableCpuGov'))e('enableCpuGov').value=getConfigValue(c,'enable_cpu_gov','0');
  if(e('enableGpuOpt'))e('enableGpuOpt').value=getConfigValue(c,'enable_gpu_opt','0');
  if(e('enablePowerSave'))e('enablePowerSave').value=getConfigValue(c,'enable_power_save','0');
  if(e('dex2oatOptimization'))e('dex2oatOptimization').value=getConfigValue(c,'dex2oat_optimization','1');
  if(e('logLevelSelect'))e('logLevelSelect').value=getConfigValue(c,'log_level','1');
  if(e('logRetentionDays'))e('logRetentionDays').value=getConfigValue(c,'log_retention_days','7');
  if(e('storageWarning'))e('storageWarning').value=getConfigValue(c,'storage_warning','85');
  if(e('storageCritical'))e('storageCritical').value=getConfigValue(c,'storage_critical','95');
  if(e('enableF2fsDaemon'))e('enableF2fsDaemon').value=getConfigValue(c,'enable_f2fs_daemon','0');
  if(e('f2fsCheckInterval'))e('f2fsCheckInterval').value=getConfigValue(c,'f2fs_check_interval','180');
  if(e('processSuppressMode'))e('processSuppressMode').value=getConfigValue(c,'process_suppress_mode','0');
  if(e('processSuppressAdj'))e('processSuppressAdj').value=getConfigValue(c,'process_suppress_adj','800');
  if(e('smartAvoidPkgs'))e('smartAvoidPkgs').value=getConfigValue(c,'smart_avoid_packages','com.tencent.mm,com.tencent.mobileqq');
  if(e('memoryLockDirs'))e('memoryLockDirs').value=getConfigValue(c,'memory_lock_dirs','');
  if(e('adblockEnable'))e('adblockEnable').value=getConfigValue(c,'adblock_enable','0');
  if(e('adblockUpdateInterval'))e('adblockUpdateInterval').value=getConfigValue(c,'adblock_update_interval','86400');
  if(e('fileCleanRules'))e('fileCleanRules').value=getConfigValue(c,'file_clean_rules','/data/adb/modules/sys_optimizer_webui/common/clean_rules.conf');
  if(e('f2fsDirtyThreshold'))e('f2fsDirtyThreshold').value=getConfigValue(c,'f2fs_dirty_threshold_mb','5000');
  if(e('f2fsGcSleep'))e('f2fsGcSleep').value=getConfigValue(c,'f2fs_gc_sleep','60');
  // 新增白名单恢复延迟
  if(e('whitelistRestoreDelay'))e('whitelistRestoreDelay').value = getConfigValue(c,'whitelist_restore_delay',60);
 },
 updateBatteryExtraConfig(c){
  const e=id=>document.getElementById(id);
  if(e('chargeDetectMode'))e('chargeDetectMode').value=getConfigValue(c,'charge_detect_mode','10');
  if(e('lowVoltageShutdown'))e('lowVoltageShutdown').value=getConfigValue(c,'low_voltage_shutdown','0');
  if(e('shutdownVoltage'))e('shutdownVoltage').value=getConfigValue(c,'shutdown_voltage','3300');
  if(e('shutdownDelay'))e('shutdownDelay').value=getConfigValue(c,'shutdown_delay','30');
  if(e('bootMinTime'))e('bootMinTime').value=getConfigValue(c,'boot_minimum_time','120');
  if(e('notifyMode'))e('notifyMode').value=getConfigValue(c,'notify_mode','1');
  if(e('notifyEvents'))e('notifyEvents').value=getConfigValue(c,'notify_events','shutdown,low_battery,clean_done');
  if(e('batteryHistoryInterval'))e('batteryHistoryInterval').value=getConfigValue(c,'battery_history_interval','600');
  if(e('batteryHistoryMaxLines'))e('batteryHistoryMaxLines').value=getConfigValue(c,'battery_history_max_lines','1000');
  if(e('forceDeviceType'))e('forceDeviceType').value=getConfigValue(c,'force_device_type','');
  if(e('enableBatteryHealthDiagnosisBatt'))e('enableBatteryHealthDiagnosisBatt').value=getConfigValue(c,'enable_battery_health_diagnosis','1');
  if(e('enableBatteryUnlockBatt'))e('enableBatteryUnlockBatt').value=getConfigValue(c,'enable_battery_unlock','0');
  if(e('enableDeepCycleCounterBatt'))e('enableDeepCycleCounterBatt').value=getConfigValue(c,'enable_deep_cycle_counter','1');
  if(e('enableModBatteryDetectionBatt'))e('enableModBatteryDetectionBatt').value=getConfigValue(c,'enable_mod_battery_detection','1');
  if(e('enableFastChargeRepairBatt'))e('enableFastChargeRepairBatt').value=getConfigValue(c,'enable_fast_charge_repair','1');
 },
 async updateCommonUI(){
  const d=await API.getCommonBatteryInfo();const cap=d.capacity;const circle=document.getElementById('batteryCircle');if(circle){const angle=cap*3.6;circle.style.background=`conic-gradient(var(--primary) 0deg ${angle}deg, var(--border-light) ${angle}deg 360deg`}
  this.setText('capacityPercent',cap+'%');this.setText('chargeStatus',`状态: ${d.usbOnline?'充电中':'未充电'}`);const power=d.voltage*Math.abs(d.current)/1000;this.setText('powerInfo',`功率: ${power.toFixed(2)} W`);this.setText('chargeProtocol',d.protocol);this.setText('voltage',d.voltage.toFixed(2)+' V');this.setText('current',d.current.toFixed(2)+' A');this.setText('temperature',d.temperature.toFixed(1)+' °C');this.setText('cycleCount',d.cycleCount);this.setText('designCapacity',d.designCapacity+' mAh');this.setText('fcc',d.fcc+' mAh');
  this.setText('powerValue',power.toFixed(2)+' W');
  const now=new Date();this.setText('updateTime',`${now.getHours().toString().padStart(2,'0')}:${now.getMinutes().toString().padStart(2,'0')}:${now.getSeconds().toString().padStart(2,'0')}`);
 },
 updateDetailedUI(d){if(!d)return;this.setText('det_charge_status',d.charge_status||'-');this.setText('det_protocol',d.protocol||'-');this.setText('det_voltage_battery',(d.voltage_battery||'0')+' V');this.setText('det_voltage_usb',(d.voltage_usb||'0')+' V');this.setText('det_current',(d.current||'0')+' A');this.setText('det_power',(d.power||'0')+' W');this.setText('det_temp_battery',(d.temperature_battery||'0')+' °C');this.setText('det_temp_usb',(d.temperature_usb||'0')+' °C');this.setText('det_temp_vooc',(d.temperature_vooc||'0')+' °C');this.setText('det_capacity_ui',(d.capacity_ui||'0')+' %');this.setText('det_capacity_hw',(d.capacity_hardware||'0')+' %');this.setText('det_design',(d.design_capacity||'0')+' mAh');this.setText('det_fcc',(d.fcc||'0')+' mAh');this.setText('det_rm',(d.remaining_capacity||'0')+' mAh');this.setText('det_soh',(d.soh||'0')+' %');this.setText('det_health',(d.calculated_soh||'0')+' %');this.setText('det_cycle',d.cycle_count||'0');this.setText('det_manu',d.manufacture_date&&d.manufacture_date!==''?d.manufacture_date:'暂不支持');this.setText('det_sn',d.serial&&d.serial!==''?d.serial:'暂不支持');this.setText('det_qmax',(d.qmax||'0')+' mAh');this.setText('det_pps',(d.pps_power||'0')+' W');this.setText('det_locked',(d.locked_capacity||'0')+' mAh');this.setText('det_locked_pct',(d.locked_percent||'0')+' %')},
 updateAlingUI(d){if(!d)return;this.setText('aling_design',(d.design_capacity||'0')+' mAh');this.setText('aling_fcc',(d.fcc||'0')+' mAh');this.setText('aling_rm',(d.remaining_capacity||'0')+' mAh');this.setText('aling_soh',(d.soh||'0')+' %');this.setText('aling_cycle',d.cycle_count||'0');this.setText('aling_grade',d.health_grade||'-')},
 updateXuantianV2UI(d){if(!d)return;this.setText('xv2_capacity',(d.capacity||'0')+' %');this.setText('xv2_voltage',(d.voltage||'0')+' V');this.setText('xv2_temperature',(d.temperature||'0')+' °C');this.setText('xv2_design',(d.design_capacity||'0')+' mAh');this.setText('xv2_fcc',(d.fcc||'0')+' mAh');this.setText('xv2_rm',(d.remaining_capacity||'0')+' mAh');this.setText('xv2_cycle',d.cycle_count||'0');this.setText('xv2_health',(d.health||'0')+' %');this.setText('xv2_qcom_qmax',(d.qcom_qmax||'0')+' mAh');this.setText('xv2_ir',(d.qcom_ir||'0')+' mΩ');this.setText('xv2_fast_health',(d.fast_charge_health||'0')+' %');this.setText('xv2_mtk_fullcap',(d.mtk_fullcap||'0')+' mAh');this.setText('xv2_mtk_rm',(d.mtk_remaining||'0')+' mAh');this.setText('xv2_mtk_cycle',d.mtk_cycle||'0');this.setText('xv2_batt_health',d.batt_health&&d.batt_health!==''?d.batt_health:'暂不支持')},
 updateXuantianAutoUI(d){if(!d)return;this.setText('xauto_capacity',(d.capacity||'0')+' %');this.setText('xauto_voltage',(d.voltage||'0')+' V');this.setText('xauto_temperature',(d.temperature||'0')+' °C');this.setText('xauto_design',(d.design_capacity||'0')+' mAh');this.setText('xauto_fcc',(d.fcc||'0')+' mAh');this.setText('xauto_cycle',d.cycle_count||'0');this.setText('xauto_health',(d.health||'0')+' %');this.setText('xauto_real_qmax',(d.real_qmax||'0')+' mAh');this.setText('xauto_real_fcc',(d.real_fcc||'0')+' mAh');this.setText('xauto_real_health',(d.real_health||'0')+' %');this.setText('xauto_ir',(d.ir||'0')+' mΩ');this.setText('xauto_fast_health',(d.fast_charge_health||'0')+' %');this.setText('xauto_lock_diff',(d.lock_diff||'0')+' %');this.setText('xauto_lock_cap_diff',(d.lock_cap_diff||'0')+' %')},
 updateDetail15UI(d){if(!d)return;this.setText('d15_capacity',(d.capacity||'0')+' %');this.setText('d15_voltage',(d.voltage||'0')+' V');this.setText('d15_temperature',(d.temperature||'0')+' °C');this.setText('d15_design',(d.design_capacity||'0')+' mAh');this.setText('d15_fcc',(d.fcc||'0')+' mAh');this.setText('d15_cycle',d.cycle_count||'0');this.setText('d15_soh',(d.soh||'0')+' %');this.setText('d15_health',(d.health||'0')+' %');this.setText('d15_manu',d.manufacture_date&&d.manufacture_date!==''?d.manufacture_date:'暂不支持');this.setText('d15_sn',d.serial&&d.serial!==''?d.serial:'暂不支持');this.setText('d15_model',d.model||'-');this.setText('d15_android',d.android||'-');this.setText('d15_brand',d.brand||'-')},
 async updateLogs(){const l=await API.getLogs();const e=document.getElementById('logOutput');if(e)e.textContent=l},
 showProgress(bid,task){const btn=document.getElementById(bid);if(!btn)return;const orig=btn.innerHTML;btn.disabled=true;btn.innerHTML='⏳ 执行中...';const pb=document.createElement('div');pb.className='task-progress';pb.innerHTML='<div class="progress-fill" style="width:0%"></div>';btn.parentNode.insertBefore(pb,btn.nextSibling);let w=0;const iv=setInterval(async()=>{w+=1;if(w>=100)w=100;pb.querySelector('.progress-fill').style.width=w+'%';if(w>=100||await API.checkTaskFinished(task)){clearInterval(iv);this.updateLogs();setTimeout(()=>{btn.disabled=false;btn.innerHTML=orig;pb.remove()},500)}},200)},
 async updateSelinuxStatus(){const s=await API.getSelinuxStatus();this.setText('selinuxMode',s.mode||'未知');this.setText('selinuxEnforce',s.enforce||'?')},
 async refreshWhitelist(){const list=await API.getWhitelist();window.whitelist=list;const container=document.getElementById('whitelistList');if(!container)return;if(list.length===0){container.innerHTML='<div style="text-align:center;color:var(--text-tertiary);">暂无应用</div>';return}
 let html='';list.forEach(pkg=>{html+=`<div class="whitelist-item" style="display:flex;justify-content:space-between;padding:4px 0;"><span>${pkg}</span><button class="remove-whitelist btn btn-danger btn-sm" data-pkg="${pkg}" style="padding:2px 8px;">移除</button></div>`});container.innerHTML=html;document.querySelectorAll('.remove-whitelist').forEach(btn=>{btn.addEventListener('click',async(e)=>{const p=e.target.dataset.pkg;const msg=await API.removeFromWhitelist(p);toast(msg);this.refreshWhitelist()})})},
 async showF2fsLog(){const log=await API.getF2fsGCLog();const modal=document.createElement('div');modal.className='modal active';modal.innerHTML=`<div class="modal-content" style="width:90%;max-width:500px;"><div class="modal-title">F2FS 回收日志</div><pre style="white-space:pre-wrap;max-height:300px;overflow:auto;background:var(--bg-tertiary);padding:var(--space-sm);border-radius:var(--radius-sm);">${log}</pre><div class="modal-actions"><button class="btn btn-primary" id="closeF2fsLogModal">关闭</button></div></div>`;document.body.appendChild(modal);document.getElementById('closeF2fsLogModal').addEventListener('click',()=>modal.remove())},
 async refreshGpuInfo(source){const g=await API.getGpuInfo(source);this.updateGpuPerf(g)},
 async showBatteryChart(){
  const modal=document.getElementById('chartModal');const container=document.getElementById('chartContainer');const noData=document.getElementById('noChartData');modal.style.display='flex';const data=await API.getBatteryHistory();if(!data||data.length<2){container.style.display='none';noData.style.display='block';return}
  container.style.display='block';noData.style.display='none';this.drawCharts(data)},
 // 增强的绘图函数，修正电压单位
 drawCharts(data){
  const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const gridColor = isDark ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.2)';
  const textColor = isDark ? '#f0f0f0' : '#333';
  const axisColor = isDark ? '#aaa' : '#666';

  const dpr = window.devicePixelRatio || 1;
  const labels = data.map(d => {
   const time = d.time.split(' ')[1];
   return time.substring(0, 5);
  });
  // 电压数据需要从毫伏转换为伏特
  const values = [
   data.map(d => d.capacity),
   data.map(d => d.voltage / 1000), // 修正：毫伏转伏特
   data.map(d => d.current),
   data.map(d => d.temperature)
  ];
  const colors = ['#007aff', '#34c759', '#ff9500', '#ff3b30'];
  const canvasIds = ['chartCapacity', 'chartVoltage', 'chartCurrent', 'chartTemp'];
  const yLabels = ['%', 'V', 'A', '°C'];

  for (let i = 0; i < 4; i++) {
   const canvas = document.getElementById(canvasIds[i]);
   if (!canvas) continue;
   const ctx = canvas.getContext('2d');
   const cssW = canvas.clientWidth;
   const cssH = canvas.clientHeight;
   canvas.width = cssW * dpr;
   canvas.height = cssH * dpr;
   ctx.scale(dpr, dpr);

   const vals = values[i];
   const minVal = Math.min(...vals);
   const maxVal = Math.max(...vals);
   const range = maxVal - minVal || 1;

   ctx.clearRect(0, 0, cssW, cssH);

   // 绘制网格线（水平线）
   ctx.strokeStyle = gridColor;
   ctx.lineWidth = 1 / dpr;
   ctx.beginPath();
   for (let j = 0; j <= 4; j++) {
    const y = cssH - 25 - (j * (cssH - 50) / 4);
    ctx.moveTo(45, y);
    ctx.lineTo(cssW - 25, y);
   }
   ctx.stroke();

   // 绘制折线
   if (vals.length >= 2) {
    ctx.beginPath();
    ctx.strokeStyle = colors[i];
    ctx.lineWidth = 3 / dpr;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    for (let k = 0; k < vals.length; k++) {
     const x = 45 + (k / (vals.length - 1)) * (cssW - 70);
     const y = cssH - 25 - ((vals[k] - minVal) / range) * (cssH - 50);
     if (k === 0) ctx.moveTo(x, y);
     else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // 绘制数据点
    ctx.fillStyle = colors[i];
    for (let k = 0; k < vals.length; k++) {
     const x = 45 + (k / (vals.length - 1)) * (cssW - 70);
     const y = cssH - 25 - ((vals[k] - minVal) / range) * (cssH - 50);
     ctx.beginPath();
     ctx.arc(x, y, 5 / dpr, 0, 2 * Math.PI);
     ctx.fill();
     ctx.strokeStyle = '#ffffff';
     ctx.lineWidth = 1 / dpr;
     ctx.stroke();
    }
   }

   // 轴和标签
   ctx.font = `500 ${14 / dpr}px sans-serif`;
   ctx.fillStyle = textColor;
   ctx.textAlign = 'center';
   ctx.textBaseline = 'top';
   if (labels.length > 0) {
    const indices = [0, Math.floor(labels.length / 2), labels.length - 1];
    indices.forEach(idx => {
     const x = 45 + (idx / (labels.length - 1)) * (cssW - 70);
     ctx.fillText(labels[idx], x, cssH - 15);
    });
   }
   ctx.textAlign = 'right';
   ctx.textBaseline = 'middle';
   for (let j = 0; j <= 4; j++) {
    const val = minVal + (j * range / 4);
    const y = cssH - 25 - (j * (cssH - 50) / 4);
    ctx.fillText(val.toFixed(1) + yLabels[i], 40, y);
   }
   ctx.save();
   ctx.translate(18, cssH / 2);
   ctx.rotate(-Math.PI / 2);
   ctx.textAlign = 'center';
   ctx.fillStyle = axisColor;
   ctx.font = `bold ${16 / dpr}px sans-serif`;
   ctx.fillText(yLabels[i], 0, 0);
   ctx.restore();
  }
 },
 async showAppBrowser(){
  const modal = document.getElementById('appBrowserModal');
  if (!modal) { toast('模态框不存在'); return; }
  modal.style.display = 'flex';
  const container = document.getElementById('appListContainer');
  const searchInput = document.getElementById('appSearchInput');
  container.innerHTML = '加载中...';
  const pkgs = await API.getAllApps();
  let filtered = pkgs;
  const render = () => {
   const search = searchInput.value.toLowerCase();
   filtered = pkgs.filter(p => p.toLowerCase().includes(search));
   let html = '';
   filtered.forEach(p => {
    html += `<div style="display:flex;justify-content:space-between;align-items:center;padding:8px;border-bottom:1px solid var(--border-light);"><span style="word-break:break-all;flex:1;">${p}</span><div><button class="btn btn-sm btn-primary copy-pkg" data-pkg="${p}" style="margin-right:5px;padding:2px 8px;">复制</button><button class="btn btn-sm btn-success add-pkg" data-pkg="${p}" style="padding:2px 8px;">添加</button></div></div>`;
   });
   container.innerHTML = html || '<div style="text-align:center;padding:20px;">无匹配应用</div>';
   document.querySelectorAll('.copy-pkg').forEach(btn => {
    btn.addEventListener('click', e => {
     const p = e.target.dataset.pkg;
     navigator.clipboard?.writeText(p).then(() => toast('已复制')).catch(() => toast('复制失败'));
    });
   });
   document.querySelectorAll('.add-pkg').forEach(btn => {
    btn.addEventListener('click', async e => {
     const p = e.target.dataset.pkg;
     const msg = await API.addToWhitelist(p);
     toast(msg);
     await UI.refreshWhitelist();
    });
   });
  };
  searchInput.value = '';
  render();
  searchInput.addEventListener('input', render);
  document.getElementById('closeAppModal').onclick = () => {
   modal.style.display = 'none';
  };
 }
};

let batteryTimer=null,currentDataSource='shell_detailed';
async function fetchBatteryData(){
 try{
  const d=await API.getBatteryInfo(currentDataSource);
  if(currentDataSource==='shell_detailed')UI.updateDetailedUI(d);
  else if(currentDataSource==='aling')UI.updateAlingUI(d);
  else if(currentDataSource==='xuantian_v2')UI.updateXuantianV2UI(d);
  else if(currentDataSource==='xuantian_auto')UI.updateXuantianAutoUI(d);
  else if(currentDataSource==='detail15')UI.updateDetail15UI(d);
 }catch(e){console.error('fetchBatteryData error',e)}
 await UI.updateCommonUI();
}
function startBatteryMonitor(){if(batteryTimer)clearInterval(batteryTimer);fetchBatteryData();batteryTimer=setInterval(fetchBatteryData,5000)}
function stopBatteryMonitor(){if(batteryTimer){clearInterval(batteryTimer);batteryTimer=null}}
function handleDataSourceChange(source){
 currentDataSource=source;
 ['shellButtons','alingButtons','xuantianV2Buttons','xuantianAutoButtons','detail15Buttons','shellDetailedCard','alingDetailedCard','xuantianV2Card','xuantianAutoCard','detail15Card'].forEach(id=>{const e=document.getElementById(id);if(e)e.style.display='none'});
 const map={shell_detailed:['shellButtons','shellDetailedCard'],aling:['alingButtons','alingDetailedCard'],xuantian_v2:['xuantianV2Buttons','xuantianV2Card'],xuantian_auto:['xuantianAutoButtons','xuantianAutoCard'],detail15:['detail15Buttons','detail15Card']};
 if(map[source]){map[source].forEach(id=>{const e=document.getElementById(id);if(e)e.style.display='block'})}
 stopBatteryMonitor();startBatteryMonitor();
}
function initBatteryPage(){
 const sel=document.getElementById('batterySourcePage');if(!sel)return;sel.value=currentDataSource;sel.addEventListener('change',async()=>{const ns=sel.value;const ok=await API.setConfigItem('battery_source',ns);if(ok){toast('✅ 电池数据源已更新');handleDataSourceChange(ns)}else{toast('❌ 保存失败');sel.value=currentDataSource}});
 document.getElementById('btnCellSingle')?.addEventListener('click',async()=>{await API.setCellType('single');toast('✅ 已切换为单电芯模式')});
 document.getElementById('btnCellDual')?.addEventListener('click',async()=>{await API.setCellType('dual');toast('✅ 已切换为双电芯模式')});
 document.getElementById('btnAuthorHome')?.addEventListener('click',()=>API.openCoolapkAuthor());
 document.getElementById('btnAlingSingle')?.addEventListener('click',async()=>{await API.setAlingType('single');toast('✅ 已切换为单电芯模式')});
 document.getElementById('btnAlingDual')?.addEventListener('click',async()=>{await API.setAlingType('dual');toast('✅ 已切换为双电芯模式')});
 document.getElementById('btnTGChannel')?.addEventListener('click',()=>API.openTGChannel());
 handleDataSourceChange(currentDataSource);
}
async function updateOifaceStatus(){const{mode,service}=await API.getOifaceStatus();const mt={'0':'禁用','1':'普通','2':'特殊'}[mode]||mode;document.getElementById('oifaceMode').innerText=mt;const se=document.getElementById('oifaceService');se.innerText=service;se.className=service==='running'?'status-running':'status-stopped'}
function bindOifaceEvents(){document.querySelectorAll('[data-oiface]').forEach(btn=>{btn.addEventListener('click',async()=>{const a=btn.dataset.oiface;const msg=await API.setOiface(a);toast(msg||`oiface ${a} 执行成功`);await updateOifaceStatus()})})}
const DEFAULT_CONFIG={
 clean_interval:14400,enable_fstrim:1,android_data_clean:1,skip_apps:"com.tencent.mm,com.taobao.taobao",data_cache_threshold_mb:100,custom_clean_times:"03:00,15:30",fstrim_frequency:1,background_control_mode:0,enable_io_opt:0,enable_read_ahead:0,enable_cpu_gov:0,enable_gpu_opt:0,enable_power_save:0,dex2oat_optimization:1,log_level:1,log_retention_days:7,storage_warning:85,storage_critical:95,enable_f2fs_daemon:0,f2fs_check_interval:180,process_suppress_mode:0,process_suppress_adj:800,smart_avoid_packages:"com.tencent.mm,com.tencent.mobileqq",memory_lock_dirs:"",adblock_enable:0,adblock_update_interval:86400,file_clean_rules:"/data/adb/modules/sys_optimizer_webui/common/clean_rules.conf",f2fs_dirty_threshold_mb:5000,f2fs_gc_sleep:60,battery_source:"shell_detailed",gpu_source:"adreno",enable_battery_health_diagnosis:1,enable_battery_unlock:0,enable_deep_cycle_counter:1,enable_mod_battery_detection:1,enable_fast_charge_repair:1,charge_detect_mode:10,low_voltage_shutdown:0,shutdown_voltage:3300,shutdown_delay:30,boot_minimum_time:120,notify_mode:1,notify_events:"shutdown,low_battery,clean_done",battery_history_interval:600,battery_history_max_lines:1000,force_device_type:"",whitelist_restore_delay:60};

window.launchAppBrowser = () => UI.showAppBrowser();
window.showBatteryChart = () => UI.showBatteryChart();

window.App={
 upBase:0,upLoad:0,upTimer:null,configVisible:false,animationFrameId:null,batteryAdvancedVisible:false,
 async init(){
  this.upBase=await API.initUptime();this.upLoad=Date.now();await this.refreshAll();this.startMonitor();this.initNav();await updateOifaceStatus();bindOifaceEvents();initBatteryPage();this.initConfigToggle();this.initConfigUI();this.initBatteryAdvancedToggle();this.initBatteryAdvancedUI();this.initBatteryExtraUI();await UI.updateSelinuxStatus();await UI.refreshWhitelist();this.bindNewEvents();this.initChartModal();document.querySelector('body').setAttribute('aria-label','智能系统优化控制台');
 },
 initBatteryAdvancedToggle(){
  const btn=document.getElementById('btnToggleBatteryAdvanced'),content=document.getElementById('batteryAdvancedContent');if(!btn||!content)return;btn.addEventListener('click',()=>{this.batteryAdvancedVisible=!this.batteryAdvancedVisible;content.style.display=this.batteryAdvancedVisible?'block':'none';btn.innerHTML=this.batteryAdvancedVisible?'▲':'▼';content.setAttribute('aria-hidden',!this.batteryAdvancedVisible)});content.style.display='none';content.setAttribute('aria-hidden','true');
 },
 async bindNewEvents(){
  document.getElementById('btnSelinuxEnforcing')?.addEventListener('click',async()=>{const m=await API.setSelinux('enforcing');toast(m);await UI.updateSelinuxStatus()});
  document.getElementById('btnSelinuxPermissive')?.addEventListener('click',async()=>{const m=await API.setSelinux('permissive');toast(m);await UI.updateSelinuxStatus()});
  document.getElementById('btnSelinuxRefresh')?.addEventListener('click',async()=>{await UI.updateSelinuxStatus();toast('✅ SELinux 状态已刷新')});
  document.getElementById('btnWhitelistAdd')?.addEventListener('click',async()=>{const input=document.getElementById('whitelistPkgInput'),pkg=input.value.trim();if(!pkg){toast('请输入包名');return}const msg=await API.addToWhitelist(pkg);toast(msg);input.value='';await UI.refreshWhitelist()});
  document.getElementById('btnWhitelistRefresh')?.addEventListener('click',()=>UI.refreshWhitelist());
  document.getElementById('btnAppBrowser')?.addEventListener('click',()=>UI.showAppBrowser());
  document.getElementById('btnShowChart')?.addEventListener('click',()=>UI.showBatteryChart());
  document.getElementById('btnF2fsGC')?.addEventListener('click',async()=>{if(confirm('确定启动 F2FS 强制回收？此操作可能耗时较长。')){await API.runF2fsGC();toast('回收任务已提交，请稍后查看日志')}});
  document.getElementById('btnViewF2fsLog')?.addEventListener('click',()=>UI.showF2fsLog());
  document.getElementById('btnEditRules')?.addEventListener('click',async()=>{const path=document.getElementById('fileCleanRules').value;const content=await execWithTimeout(`cat "${path}" 2>/dev/null||echo ""`).then(r=>r.stdout);const modal=document.createElement('div');modal.className='modal active';modal.innerHTML=`<div class="modal-content" style="width:90%;max-width:600px;"><div class="modal-title">编辑规则文件</div><textarea class="config-textarea" style="width:100%;height:300px;">${content}</textarea><div class="modal-actions"><button class="btn btn-primary" id="saveRules">保存</button><button class="btn btn-secondary" id="cancelRules">取消</button></div></div>`;document.body.appendChild(modal);document.getElementById('saveRules').addEventListener('click',async()=>{const nc=modal.querySelector('textarea').value;await execWithTimeout(`echo '${nc}'>"${path}"`);toast('规则文件已保存');modal.remove()});document.getElementById('cancelRules').addEventListener('click',()=>modal.remove())});
  const gpuSel=document.getElementById('gpuSourceSelect');if(gpuSel){const cfg=await API.getConfig();gpuSel.value=cfg.gpu_source||'adreno';gpuSel.addEventListener('change',async()=>{const ns=gpuSel.value;const ok=await API.setConfigItem('gpu_source',ns);if(ok){toast('✅ GPU 数据源已更新');this.refreshMonitor()}else{toast('❌ 保存失败');const cfg=await API.getConfig();gpuSel.value=cfg.gpu_source||'adreno'}})}
  const colorCard=document.getElementById('colorosCard');if(colorCard){const inst=await API.isColorOSInstalled();colorCard.style.display=inst?'block':'none'}
  document.getElementById('btnPerformancePlatform')?.addEventListener('click',async()=>{const r=await execWithTimeout('am start -n com.coloros.phonemanager/com.oplus.phonemanager.idleoptimize.landing.SuperComputingFromVActivity');if(r.errno===0)toast('✅ 已启动性能平台');else toast('❌ 启动失败，可能当前系统不支持')});
  document.getElementById('btnLongTermCare')?.addEventListener('click',async()=>{const r=await execWithTimeout('am start -n com.coloros.phonemanager/com.oplus.phonemanager.sysmaint.SysMaintActivity');if(r.errno===0)toast('✅ 已启动久用保养');else toast('❌ 启动失败')});
  document.getElementById('btnNetworkDetect')?.addEventListener('click',async()=>{const r=await execWithTimeout('am start -n com.coloros.phonemanager/com.oplus.phonemanager.networkdetect.NetworkDetectActivity');if(r.errno===0)toast('✅ 已启动网络检测');else toast('❌ 启动失败')});
 },
 async refreshAll(){
  try{
   const [sys,storage,mod,cfg,sm,bat]=await Promise.allSettled([API.getSystemStatus(),API.getStorageStatus(),API.getModuleStatus(),API.getConfig(),API.getSmoothnessScore(),API.getBatteryInfo(currentDataSource)]).then(r=>r.map(r=>r.status==='fulfilled'?r.value:{}));
   UI.updateHome(mod||{},sys||{},storage||{},sm||{},bat||{});UI.updateSys(sys||{});UI.updateStorage(storage||{});UI.updateModule(mod||{});UI.updateSmooth(sm||{});UI.updateConfig(cfg||{});UI.updateBatteryExtraConfig(cfg||{});await UI.updateLogs();await UI.updateSelinuxStatus();await UI.refreshWhitelist();
  }catch(e){console.error('refreshAll error',e)}
 },
 startMonitor(){
  let lastMon=0,lastAll=0,lastLog=0;const loop=()=>{const now=Date.now();if(document.visibilityState==='visible'){if(now-lastMon>30000){this.refreshMonitor();lastMon=now}if(now-lastAll>60000){this.refreshAll();lastAll=now}if(now-lastLog>30000){UI.updateLogs();lastLog=now}}this.animationFrameId=requestAnimationFrame(loop)};this.animationFrameId=requestAnimationFrame(loop);document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'){this.refreshMonitor();this.refreshAll()}});
 },
 async refreshMonitor(){
  try{
   const [ram,cpu,cfg,smooth]=await Promise.allSettled([API.getRamInfo(),API.getAllCpuInfo(),API.getConfig(),API.getSmoothnessScore()]).then(r=>r.map(r=>r.status==='fulfilled'?r.value:{}));
   const gpu=await API.getGpuInfo(cfg?.gpu_source||'adreno').catch(()=>({freq:0,load:0}));
   UI.updateRamPerf(ram||{total:0,used:0,avail:0,percent:0});UI.updateCpuPerf(cpu?.usage||0,cpu?.freqs||[]);UI.updateGpuPerf(gpu);UI.updateSmoothPerf(smooth||{score:100,improvement:0});
  }catch(e){console.error('refreshMonitor error',e)}
 },
 startUptime(){},
 initNav(){
  const items=document.querySelectorAll('.bottom-nav .nav-item'),pages=document.querySelectorAll('.page');
  items.forEach(i=>i.classList.remove('active'));pages.forEach(p=>p.classList.remove('page-active'));
  document.getElementById('homePage')?.classList.add('page-active');const homeItem=Array.from(items).find(i=>i.dataset.page==='homePage');if(homeItem)homeItem.classList.add('active');
  items.forEach(i=>{i.addEventListener('click',()=>{const t=i.dataset.page;items.forEach(n=>n.classList.remove('active'));i.classList.add('active');pages.forEach(p=>p.classList.remove('page-active'));document.getElementById(t).classList.add('page-active');if(t==='batteryPage')startBatteryMonitor();else stopBatteryMonitor();document.querySelector(`#${t} .header h1`)?.focus()})});
  if(document.querySelector('.bottom-nav .nav-item.active')?.dataset.page==='batteryPage')startBatteryMonitor();
 },
 initConfigToggle(){
  const btn=document.getElementById('btnToggleConfig'),card=document.getElementById('configCard');if(!btn||!card)return;btn.addEventListener('click',()=>{this.configVisible=!this.configVisible;card.style.display=this.configVisible?'block':'none';btn.innerHTML=this.configVisible?'⚙️ 配置管理 ▼':'⚙️ 配置管理 ▶';card.setAttribute('aria-hidden',!this.configVisible)});card.style.display='none';card.setAttribute('aria-hidden','true');
 },
 initConfigUI(){
  const resetBtn=document.getElementById('btnResetConfig');if(resetBtn){resetBtn.addEventListener('click',async()=>{if(confirm('确定恢复所有配置为默认值？')){const ok=await API.saveConfig(DEFAULT_CONFIG);if(ok){toast('✅ 已恢复默认配置');const cfg=await API.getConfig();UI.updateConfig(cfg);UI.updateBatteryExtraConfig(cfg);this.refreshMonitor();fetchBatteryData()}else toast('❌ 恢复失败')}})}
  const inputs=document.querySelectorAll('#configCard .config-input,#configCard .config-select');inputs.forEach(input=>{input.addEventListener('change',async()=>{const id=input.id,val=input.value,key=idToConfigKey[id];if(!key){console.warn(`未找到映射: ${id}`);return}let v=val;if(id==='cleanInterval')v=parseInt(v)*60;
   const ok=await API.setConfigItem(key,v);if(ok)toast(`✅ ${id} 已更新`);else{toast(`❌ 保存 ${id} 失败`);const cfg=await API.getConfig();UI.updateConfig(cfg)}})});
 },
 initBatteryAdvancedUI(){
  Object.keys(batteryAdvancedMap).forEach(id=>{const sel=document.getElementById(id);if(!sel)return;sel.addEventListener('change',async()=>{const v=sel.value,k=batteryAdvancedMap[id];const ok=await API.setConfigItem(k,v);if(ok)toast(`✅ 电池健康设置已更新`);else{toast(`❌ 保存失败`);const cfg=await API.getConfig();UI.updateBatteryExtraConfig(cfg)}})});
 },
 initBatteryExtraUI(){
  ['chargeDetectMode','lowVoltageShutdown','shutdownVoltage','shutdownDelay','bootMinTime','notifyMode','notifyEvents','batteryHistoryInterval','batteryHistoryMaxLines','forceDeviceType'].forEach(id=>{const el=document.getElementById(id);if(!el)return;el.addEventListener('change',async()=>{const v=el.value,k=idToConfigKey[id];const ok=await API.setConfigItem(k,v);if(ok)toast(`✅ ${id} 已更新`);else{toast(`❌ 保存 ${id} 失败`);const cfg=await API.getConfig();UI.updateBatteryExtraConfig(cfg)}})});
 },
 initChartModal(){
  const modal=document.getElementById('chartModal'),close=document.getElementById('closeChartModal');if(modal&&close)close.addEventListener('click',()=>modal.style.display='none');
 },
 destroy(){if(this.upTimer)clearInterval(this.upTimer);if(this.animationFrameId)cancelAnimationFrame(this.animationFrameId);stopBatteryMonitor()}
};

document.addEventListener('DOMContentLoaded',()=>{
 window.App.init();
 document.getElementById('btnCleanNow')?.addEventListener('click',()=>{API.cleanNow();UI.showProgress('btnCleanNow','clean')});
 document.getElementById('btnOptimizeNow')?.addEventListener('click',()=>{API.optimizeNow();UI.showProgress('btnOptimizeNow','optimize')});
 document.getElementById('btnDataCleanNow')?.addEventListener('click',()=>{API.dataCleanNow();UI.showProgress('btnDataCleanNow','dataClean')});
 document.getElementById('btnRestartService')?.addEventListener('click',()=>API.restartService());
 document.getElementById('btnRefreshLog')?.addEventListener('click',async()=>{await UI.updateLogs()});
 document.getElementById('btnClearLog')?.addEventListener('click',API.clearLogs);
});