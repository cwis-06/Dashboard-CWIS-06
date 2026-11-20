const $=i=>document.getElementById(i);
const fmt=(n,d=1)=>n==null?'–':n.toLocaleString('id-ID',{maximumFractionDigits:d,minimumFractionDigits:d});
const esc=s=>String(s==null?'–':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const JK='#e8590c',OT='#0b7a8a',MX='#7048b8',G0='#8d9ba3';
const prog=p=>p>=100?'#2eaa5c':p>=50?'#2f7fe0':p>0?'#f0a020':G0;
const st=p=>p>=100?'selesai':p>0?'berjalan':'belum';
const pc=p=>p.progress_pct||0;
const dep=(g,i)=>g==null||i==null?null:g-i;   // kedalaman = GL - invert (berlaku untuk invert negatif maupun positif)
const lowIE=p=>{const a=[p.elev_downstream,p.elev_upstream_1,p.elev_upstream_2,p.elev_upstream_3].filter(v=>v!=null);return a.length?Math.min(...a):null};
const REF=new Set(['MHJ_06_02_0150','MH-0282']);
const isRef=p=>REF.has(p.manhole_id)||p.is_reference===true||p.is_reference==='true';
let PIPES,MH,IDX=[],hits=[],sel=-1,hl=null,cMode='method';
const mm=new Map(),byId=new Map(),f={zone:'',cls:'',st:''},off=new Set();
/* ===== PENGATURAN ===== */
const FOTO_URL='https://script.google.com/macros/s/AKfycbztnQkhdsc40_oCW97_k-kqZKGIxi2NIjuI2440Rrj5nfsfLubTUuz-eOea_g5wwYPO/exec';   // alamat web app Google Apps Script (berakhiran /exec) untuk foto dokumentasi. Kosongkan untuk menonaktifkan fitur foto.
const FOTO_AUTO=false;   // true: jendela "Foto kegiatan terbaru" muncul otomatis sekali per sesi (tidak saat panduan pertama kali tampil). Dimatikan di HP terlepas dari ini (lihat FOTO_AUTO_MOBILE).
const FOTO_AUTO_MOBILE=false;   // sama, tapi khusus layar sempit (<=820px). Biarkan false: di HP jendela besar ini mengganggu saat baru buka halaman.
const SHOW_HI_STATS=false;   // false: sembunyikan jumlah SR dan HI (baris "House inlet" di ringkasan progres, tabel "House inlet per zona", dan angka di daftar layer). true: tampilkan lagi.
const HI_MINZ=18;   // house inlet (SR/HI/HIP) baru tampil mulai zoom ini. Naikkan bila masih padat, turunkan bila ingin lebih cepat muncul.
/* ======================= */
const map=L.map('map',{preferCanvas:true,zoomControl:false,maxZoom:28,zoomSnap:.5,zoomDelta:.5,wheelPxPerZoomLevel:90,renderer:L.canvas({tolerance:5})});L.control.zoom({position:'topright'}).addTo(map);
const osm=L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:28,maxNativeZoom:19,attribution:'© OpenStreetMap'});
const esri=L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',{maxZoom:28,maxNativeZoom:19,attribution:'Tiles © Esri'});
const gP=L.featureGroup().addTo(map),gM=L.featureGroup().addTo(map);
/* Urutan tumpuk (bawah ke atas): Poligon (zona, RW) > Polyline (persil, collecting) > Line (pipa lateral) > Point (house inlet, inspection chamber, manhole) */
map.createPane('pz').style.zIndex=300;map.createPane('pm').style.zIndex=645;
['pz','pm'].forEach(n=>map.getPane(n).style.pointerEvents='none');
const HM=L.CircleMarker.extend({_clickTolerance(){return this.options.hit||0}});   // area klik titik dibuat lebih lebar dari gambarnya
const cm=(ll,o)=>new HM(ll,o);
const HIS=new Set(['sr','hic','hip']);
function restack(){[SL.persil,SL.collect,gP,SL.hip,SL.hic,SL.sr,SL.ic,SL.tp,gM].forEach(g=>{if(map.hasLayer(g))g.bringToFront()})}
const SL={zona:L.featureGroup(),rw:L.featureGroup(),collect:L.featureGroup(),persil:L.featureGroup(),ic:L.featureGroup(),hip:L.featureGroup(),hic:L.featureGroup(),sr:L.featureGroup(),tp:L.featureGroup(),foto:L.featureGroup()},sById=new Map(),vis={pipe:true,mh:true,collect:false,persil:false,ic:false,hip:false,hic:false,sr:false,zona:true,rw:false,tp:true,foto:true},have={};
L.DomEvent.disableClickPropagation($('lg'));
const mmeth=id=>{const s=mm.get(id);return !s?null:s.size>1?'Campuran':[...s][0]};
const colP=p=>cMode==='progress'?prog(p.progress_pct):p.method==='Jacking'?JK:OT;
const colM=p=>{if(cMode==='progress')return prog(p.progress_pct);const m=mmeth(p.manhole_id);return m==='Jacking'?JK:m==='Open Trench'?OT:m==='Campuran'?MX:G0};
const row=(a,b)=>b==null||b===''?'':'<tr><th>'+a+'</th><td>'+b+'</td></tr>';
const m3=v=>v==null?null:fmt(v,3)+' m';
const fD=v=>{const m=String(v||'').match(/(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})/);return m?dTxt(m[1]+'-'+m[2].padStart(2,'0')+'-'+m[3].padStart(2,'0')):''};   // tanggal dari data, ditampilkan mis. 30 Okt 2026
const tglRows=p=>row('Rencana mulai pekerjaan',fD(p.plan_date)||'–')+row('Realisasi mulai pekerjaan',fD(p.actual_date)||'Belum dimulai');
const progRows=p=>'work_stage' in p
 ?'<h4>Progres</h4><table>'+row('Status',esc(p.stage_label))+row('Progres',fmt(pc(p),0)+'%')+tglRows(p)+'</table>'   // manhole: status, persentase, dan tanggal mulai
 :'<h4>Progres</h4><table>'+row('Tahap',esc(p.stage_label))+row('Progres',fmt(pc(p),0)+'%')+tglRows(p)+'</table>';
function popP(p){return '<div class="pp"><h3>'+esc(p.pipe_id)+'</h3><p class="sub">'+esc(p.pipe_type)+', '+esc(p.method)+', '+esc(p.material)+', Ø'+fmt(p.diameter_mm,0)+' mm</p><table>'+
 row('Dari manhole',esc(p.from_mh))+row('Ke manhole',esc(p.to_mh))+row('Panjang',p.length_m==null?null:fmt(p.length_m,2)+' m')+row('Slope',p.slope_pct==null?null:fmt(p.slope_pct,2)+' %')+row('Lokasi',esc(p.location_name))+row('Zona',p.zone)+
 '</table><h4>Ujung hulu</h4><table>'+row('Muka tanah (GL)',m3(p.up_gl))+row('Invert',m3(p.up_ie))+row('Kedalaman (GL − invert)',m3(dep(p.up_gl,p.up_ie)))+
 '</table><h4>Ujung hilir</h4><table>'+row('Muka tanah (GL)',m3(p.lw_gl))+row('Invert',m3(p.lw_ie))+row('Kedalaman (GL − invert)',m3(dep(p.lw_gl,p.lw_ie)))+row('Drop',m3(p.drop_m))+'</table>'+progRows(p)+fDocs(p.pipe_id)+'</div>'}
function popM(p){if(isRef(p))return '<div class="pp"><h3>'+esc(p.manhole_id)+'</h3><p class="sub">Manhole paket sebelah (CWIS 02), hanya referensi posisi</p></div>';
 return '<div class="pp"><h3>'+esc(p.manhole_id)+'</h3><p class="sub">'+esc(p.mh_type)+(p.shaft?', shaft '+esc(p.shaft):'')+', Ø'+fmt(p.diameter_mm,0)+' mm</p><table>'+
 row('Lokasi',esc(p.location_name))+row('Zona',p.zone)+row('Metode pipa',mmeth(p.manhole_id))+
 '</table><h4>Elevasi</h4><table>'+row('Muka tanah (GL)',m3(p.ground_elev))+row('Invert hulu 1',m3(p.elev_upstream_1))+row('Invert hulu 2',m3(p.elev_upstream_2))+row('Invert hulu 3',m3(p.elev_upstream_3))+row('Invert hilir',m3(p.elev_downstream))+
 '</table><h4>Kedalaman (GL − invert)</h4><table>'+row('Ke invert terdalam',m3(dep(p.ground_elev,lowIE(p))))+row('Ke invert hilir',m3(dep(p.ground_elev,p.elev_downstream)))+'</table>'+progRows(p)+fDocs(p.manhole_id)+'</div>'}
const okZ=p=>!f.zone||String(p.zone)===f.zone,okS=p=>!f.st||st(p.progress_pct)===f.st;
const okP=p=>okZ(p)&&okS(p)&&(!f.cls||p.pipe_type===f.cls)&&!off.has(p.method);
const okM=p=>{const s=mm.get(p.manhole_id);return okZ(p)&&okS(p)&&(!f.cls||p.mh_type===f.cls)&&(!s||[...s].some(m=>!off.has(m)))};
const bar=p=>'<div class="bar"><i style="width:'+Math.min(100,p)+'%"></i></div>';
function agg(list,kf){const g={};list.forEach(x=>{const p=x.properties,k=kf(p),l=p.length_m||0;(g[k]=g[k]||{n:0,l:0,d:0});g[k].n++;g[k].l+=l;g[k].d+=l*pc(p)/100});return g}
function legend(){$('lg').innerHTML=(cMode==='method'?['Jacking','Open Trench'].map(k=>'<button class="btn'+(off.has(k)?' x':'')+'" data-m="'+k+'" title="Klik untuk menyembunyikan atau menampilkan"><i class="sw" style="background:'+(k==='Jacking'?JK:OT)+'"></i>'+k+'</button>').join('')+'<div><i class="sw" style="background:'+MX+'"></i>Manhole di sambungan kedua metode</div>':
 [['Belum mulai',G0],['1–49%','#f0a020'],['50–99%','#2f7fe0'],['Selesai','#2eaa5c']].map(a=>'<div><i class="sw" style="background:'+a[1]+'"></i>'+a[0]+'</div>').join(''))+(have.sr||have.hic||have.hip?'<div style="margin-top:4px">House inlet</div>'+['sr','hic','hip'].map(k=>'<div><i class="sw" style="'+(k==='hip'?'background:transparent;border:2px solid '+HIC.hip:'background:'+HIC[k])+'"></i>'+HIL[k]+'</div>').join(''):'')+(have.tp?'<div style="margin-top:4px">Test pit</div>'+[['Direncanakan',TPC.rencana],['Digali',TPC.digali],['Selesai',TPC.selesai]].map(a=>'<div><i class="sw" style="background:'+a[1]+';border:2px solid #5c3b1e"></i>'+a[0]+'</div>').join(''):'')+'<p class="sm">Tebal garis menunjukkan kelas pipa. Lingkaran putus-putus adalah manhole paket sebelah.</p>'}
function render(fit){
 gP.clearLayers();gM.clearLayers();byId.clear();
 const P=PIPES.features.filter(x=>okP(x.properties)),M=MH.features.filter(x=>okM(x.properties)),W={Primary:5,Secondary:3.5,Tertiary:2.5};
 if(vis.pipe)L.geoJSON({type:'FeatureCollection',features:P},{style:x=>({color:colP(x.properties),weight:W[x.properties.pipe_type]||3,opacity:.92}),onEachFeature:(x,l)=>{const p=x.properties,w=W[p.pipe_type]||3;byId.set(p.pipe_id,l);
  l.bindPopup(()=>popP(p),{maxWidth:340}).bindTooltip(p.pipe_id,{sticky:true});l.on({mouseover:()=>l.setStyle({weight:w+3}),mouseout:()=>l.setStyle({weight:w})})}}).addTo(gP);
 if(vis.mh)M.forEach(x=>{const p=x.properties,r=isRef(p);
  const mk=cm([x.geometry.coordinates[1],x.geometry.coordinates[0]],r?{hit:9,radius:6,color:G0,weight:2,dashArray:'2 2',fillOpacity:0}:{hit:9,radius:p.shaft?6:4,color:'#fff',weight:1.2,fillColor:colM(p),fillOpacity:1}).bindPopup(()=>popM(p),{maxWidth:340}).bindTooltip(p.manhole_id,{sticky:true}).addTo(gM);byId.set(p.manhole_id,mk)});
 const tot=P.reduce((s,x)=>s+(x.properties.length_m||0),0),dn=P.reduce((s,x)=>s+(x.properties.length_m||0)*pc(x.properties)/100,0),pct=tot?100*dn/tot:0,Mn=M.filter(x=>!isRef(x.properties));
 $('kPct').textContent=fmt(pct)+'%';$('kBar').style.width=pct+'%';$('kLen').textContent=fmt(tot/1000,2)+' km';$('kDone').textContent=fmt(dn/1000,2)+' km';$('kN').textContent=P.length;
 $('kMh').textContent=Mn.filter(x=>pc(x.properties)>=100).length+' / '+Mn.length;
 const z=agg(P,p=>p.zone==null?'-':String(p.zone));
 $('zones').innerHTML=Object.keys(z).sort((a,b)=>a-b).map(k=>{const v=z[k],q=v.l?100*v.d/v.l:0;return '<button class="zr'+(f.zone===k?' on':'')+'" data-z="'+k+'"><span>'+(k==='-'?'Tanpa zona':'Zona '+k)+'</span><span>'+fmt(v.l/1000,2)+' km</span><b>'+fmt(q)+'%</b>'+bar(q)+'</button>'}).join('')||'<p class="sm">Tidak ada data.</p>';
 const c=agg(P,p=>p.pipe_type+'|'+p.method);
 $('cls').innerHTML=Object.keys(c).sort().map(k=>{const v=c[k],[a,b]=k.split('|');return '<tr><td><i class="sw" style="background:'+(b==='Jacking'?JK:OT)+'"></i>'+esc(a)+', '+esc(b)+'</td><td>'+v.n+'</td><td>'+fmt(v.l/1000,2)+'</td><td>'+fmt(v.l?100*v.d/v.l:0)+'</td></tr>'}).join('');
 const bb=L.latLngBounds([]);[gP,gM].forEach(g=>g.getLayers().length&&bb.extend(g.getBounds()));if(fit&&bb.isValid())map.fitBounds(bb.pad(.06),{maxZoom:19});
 restack();
}
function resetFilters(){f.zone=f.cls=f.st='';off.clear();['fZone','fCls','fSt'].forEach(i=>$(i).value='');legend()}
const hay=p=>Object.values(p).filter(v=>v!=null&&v!=='').join(' ').toLowerCase();
const subt=i=>{const p=i.f.properties;if(i.t==='tp')return [p.status,p.location_name,p.zone==null?null:'zona '+p.zone].filter(Boolean).join(', ');if(i.t!=='p'&&i.t!=='m')return [p.hi_code||p.ic_type,p.zone_no==null?null:'zona '+p.zone_no,p.rw_label].filter(Boolean).join(', ');return i.t==='p'?p.method+', '+p.pipe_type+', Ø'+fmt(p.diameter_mm,0)+', '+fmt(p.length_m,1)+' m, zona '+p.zone:(isRef(p)?'Paket sebelah':(p.mh_type||'')+(p.shaft?', shaft '+p.shaft:'')+', zona '+p.zone)};
function draw(){const sh=hits.slice(0,8),q=$('q').value.trim();
 $('res').innerHTML=sh.map((i,k)=>'<li role="option" data-i="'+k+'" class="'+(k===sel?'on':'')+'"><b>'+esc(i.id)+'</b><small>'+esc((KIND[i.t]||'')+': '+subt(i))+'</small></li>').join('');
 $('rc').textContent=q?(hits.length?hits.length+' hasil'+(hits.length>8?', 8 teratas ditampilkan':''):'Tidak ada hasil'):'Tekan / untuk mencari. Pencarian mencakup semua atribut.'}
function search(v){const q=v.trim().toLowerCase();sel=-1;if(!q){hits=[];clearHl();return draw()}
 const t=q.split(/\s+/),r=i=>{const d=i.id.toLowerCase();return d.startsWith(q)?0:d.includes(q)?1:2};
 hits=IDX.filter(i=>t.every(w=>i.h.includes(w))).sort((a,b)=>r(a)-r(b));draw()}
function go(i){$('q').value=i.id;hits=[];draw();if(mob()){sh(0);$('q').blur()}const gk=i.g||i.t,isS=sById.has(i.id);if(isS&&!map.hasLayer(SL[gk])){vis[gk]=true;lyDraw();SL[gk].addTo(map);restack()}if(!isS&&!byId.has(i.id)){resetFilters();render(false)}
 const l=byId.get(i.id)||sById.get(i.id);if(!l)return;clearHl();seek=true;setTimeout(()=>{seek=false},2500);
 hl=L.geoJSON(i.f,{interactive:false,style:{color:'#ffd43b',weight:12,opacity:.7},pointToLayer:(x,ll)=>L.circleMarker(ll,{interactive:false,radius:14,color:'#ffd43b',weight:5,fillOpacity:0})}).addTo(map);hl.eachLayer(x=>x.bringToBack());
 if(i.t==='p'||i.t==='collect'||i.t==='persil'){map.fitBounds(l.getBounds().pad(.6),{maxZoom:19});setTimeout(()=>l.openPopup(l.getBounds().getCenter()),350)}
 else{map.flyTo(l.getLatLng(),Math.max(map.getZoom(),19),{duration:.6});setTimeout(()=>l.openPopup(),700)}}
let seek=false;const clearHl=()=>{if(hl){map.removeLayer(hl);hl=null}};
map.on('popupopen',()=>{seek=false});map.on('popupclose',()=>{if(!seek)clearHl()});map.on('click',clearHl);
$('tg').onclick=()=>{document.body.classList.toggle('min');setTimeout(()=>map.invalidateSize(),150)};
$('th').onclick=()=>{const t=document.documentElement.dataset.theme==='dark'?'light':'dark';document.documentElement.dataset.theme=t;try{localStorage.setItem('th',t)}catch(e){}};
map.createPane('po');map.getPane('po').style.zIndex=250;
const ortho=L.tileLayer('tiles/ortho/{z}/{x}/{y}.jpg',{pane:'po',minZoom:12,maxNativeZoom:20,maxZoom:28,opacity:.9,attribution:'Ortofoto CWIS-06'});
const BASES={osm:osm,esri:esri,ortho:ortho,none:null};let curBase='osm';
function bmDraw(){$('bm').innerHTML='<div class="ly" style="grid-template-columns:1fr">'+[['osm','OpenStreetMap'],['esri','Citra satelit (Esri)'],['ortho','Ortofoto CWIS-06'],['none','Tanpa peta dasar']].map(([k,n])=>'<label><input type="radio" name="bm" value="'+k+'"'+(curBase===k?' checked':'')+'><span>'+n+'</span></label>').join('')+'</div>'}
$('bm').addEventListener('change',e=>{const t=e.target;if(t.name==='bm'){Object.values(BASES).forEach(b=>b&&map.removeLayer(b));curBase=t.value;if(BASES[t.value])BASES[t.value].addTo(map)}});
document.querySelectorAll('[data-c]').forEach(b=>b.onclick=()=>{cMode=b.dataset.c;document.querySelectorAll('[data-c]').forEach(x=>x.setAttribute('aria-pressed',x===b));legend();if(PIPES)render(false)});
$('lg').onclick=e=>{const b=e.target.closest('[data-m]');if(!b)return;off.has(b.dataset.m)?off.delete(b.dataset.m):off.add(b.dataset.m);legend();render(true)};
[['fZone','zone'],['fCls','cls'],['fSt','st']].forEach(([id,k])=>$(id).onchange=e=>{f[k]=e.target.value;render(true)});
$('bReset').onclick=()=>{resetFilters();render(true)};
$('zones').onclick=e=>{const b=e.target.closest('.zr');if(!b||b.dataset.z==='-')return;f.zone=f.zone===b.dataset.z?'':b.dataset.z;$('fZone').value=f.zone;render(true)};
$('q').addEventListener('input',e=>search(e.target.value));
$('q').addEventListener('keydown',e=>{const n=Math.min(hits.length,8);
 if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();sel=Math.max(0,Math.min(n-1,sel+(e.key==='ArrowDown'?1:-1)));draw()}
 else if(e.key==='Enter'&&n)go(hits[Math.max(sel,0)]);else if(e.key==='Escape'){e.target.value='';search('')}});
$('res').addEventListener('mousedown',e=>{const li=e.target.closest('li');if(li)go(hits[+li.dataset.i])});
document.addEventListener('keydown',e=>{if(e.key==='/'&&!/INPUT|SELECT|TEXTAREA/.test(document.activeElement.tagName)){e.preventDefault();$('q').focus()}});
const KIND={p:'Pipa lateral',m:'Manhole',collect:'Pipa collecting',persil:'Pipa persil',ic:'Inspection chamber',hi:'House inlet',tp:'Test pit'};
const SP=[{k:'zona',f:'zona',t:'Zona',id:'zone_name'},{k:'rw',f:'batas_rw',t:'Batas RW',id:'rw_label'},{k:'collect',f:'collecting_pipe',t:'Pipa collecting',id:'cp_id'},{k:'persil',f:'persil_pipe',t:'Pipa persil',id:'pp_id'},{k:'ic',f:'inspection_chamber',t:'Inspection chamber',id:'ic_id'},{k:'hi',f:'house_inlet',t:'House inlet',id:'hi_id'},{k:'tp',f:'test_pit',t:'Test pit',id:'tp_id'}];
const HIK={HIP:'hip',HI:'hic',SR:'sr'},HIL={hip:'Potensi, belum disurvey',hic:'HI, disetujui tanpa pipa dalam rumah',sr:'SR, disetujui dengan pipa dalam rumah'},HIC={hip:'#868e96',hic:'#f59f00',sr:'#2b8a3e'},hcat=p=>HIK[String(p.hi_code||'').trim().toUpperCase()]||'hip';
const SKIP=new Set(['attrs','fid','geom','updated_at','stage_code','hi_status','hi_kategori','has_inside_pipe','in_scope']);
const nv=(k,v)=>typeof v==='boolean'?(v?'ya':'tidak'):typeof v!=='number'?esc(v):/lon|lat/.test(k)?v.toFixed(6):fmt(v,Number.isInteger(v)?0:3);
const popG=(p,t,k)=>'<div class="pp"><h3>'+esc(p[k])+'</h3><p class="sub">'+t+'</p><table>'+Object.entries(p).filter(([a,v])=>!SKIP.has(a)&&a!==k&&v!=null&&v!=='').map(([a,v])=>row(esc(a.replace(/_/g,' ')),nv(a,v))).join('')+'</table></div>';
/* Test pit (titik tespit): data dari tabel sewer.test_pit, diekspor ke data/test_pit.geojson */
const TPF=new Map(),tpKey=v=>String(v||'').toLowerCase().replace(/[^a-z0-9]/g,'');
const tpSt=p=>{const t=String(p.status||'').toLowerCase();return /selesai|done|finish/.test(t)?'selesai':/gali|proses|jalan|ongoing|kerja/.test(t)?'digali':'rencana'};
const TPC={rencana:G0,digali:'#f0a020',selesai:'#2eaa5c'},tpCol=p=>TPC[tpSt(p)];
const popTP=p=>'<div class="pp"><h3>'+esc(p.tp_id)+'</h3><p class="sub">Test pit'+(p.status?', '+esc(p.status):'')+'</p><table>'+row('Lokasi',esc(p.location_name||'')||null)+row('Zona',p.zone)+row('Kedalaman galian',p.depth_m==null?null:fmt(Number(p.depth_m),2)+' m')+row('Muka tanah (GL)',p.ground_elev==null?null:m3(Number(p.ground_elev)))+row('Utilitas ditemukan',esc(p.utility_found||'')||null)+row('Rencana mulai pekerjaan',fD(p.plan_date)||'–')+row('Realisasi mulai pekerjaan',fD(p.actual_date)||'Belum dimulai')+row('Keterangan',esc(p.note||'')||null)+'</table>'+fDocs(p.tp_id)+'</div>';
function buildStatic(s,g){const poly=s.k==='zona'||s.k==='rw';
 g.features.forEach(x=>{const p=x.properties,id=p[s.id],hk=s.k==='hi'?hcat(p):null,gk=hk||s.k,G=SL[gk];if(hk)p.kategori=HIL[hk];let l,inner;
  if(x.geometry.type==='Point'){const c=x.geometry.coordinates;inner=l=cm([c[1],c[0]],s.k==='tp'?{hit:10,radius:7,color:'#5c3b1e',weight:2,fillColor:tpCol(p),fillOpacity:1}:s.k==='ic'?{hit:8,radius:5,color:'#fff',weight:1.2,fillColor:'#d6336c',fillOpacity:1}:hk==='hip'?{hit:7,radius:3.5,color:HIC.hip,weight:1.5,fillOpacity:0}:{hit:7,radius:hk==='sr'?4:3.5,color:'#fff',weight:.8,fillColor:HIC[hk],fillOpacity:1})}
  else{l=L.geoJSON(x,poly?{pane:'pz',interactive:false,style:{color:s.k==='zona'?'#7048b8':'#868e96',weight:s.k==='zona'?2.5:1.2,dashArray:s.k==='zona'?'8 5':'3 4',fillOpacity:.05}}:{style:{color:s.k==='collect'?'#c2255c':'#868e96',weight:s.k==='collect'?2.5:1.5,dashArray:s.k==='persil'?'2 4':null}});l.eachLayer(y=>{inner=y})}
  if(poly)inner.bindTooltip(String(id),{permanent:true,direction:'center',className:'plbl'+(s.k==='rw'?' rwl':'')});
  else{inner.bindPopup(()=>s.k==='tp'?popTP(p):popG(p,s.t,s.id),{maxWidth:340}).bindTooltip(String(id),{sticky:true});sById.set(id,inner);IDX.push({t:s.k,g:gk,f:x,id:String(id),h:hay(p)})}
  if(hk)inner._zn=p.zone_no==null?'-':p.zone_no;
  if(s.k==='tp'&&x.geometry.type==='Point'&&id!=null)TPF.set(tpKey(id),{t:'t',id:String(id),ll:[x.geometry.coordinates[1],x.geometry.coordinates[0]],f:x});
  G.addLayer(l);have[gk]=(have[gk]||0)+1})}
const LY=[['pipe','Pipa lateral'],['mh','Manhole'],['collect','Pipa collecting'],['persil','Pipa persil'],['ic','Inspection chamber'],['sr','SR: HI dan pipa dalam rumah'],['hic','HI: tanpa pipa dalam rumah'],['hip','HIP: potensi, belum disurvey'],['tp','Test pit'],['zona','Zona'],['rw','Batas RW'],...(FOTO_URL?[['foto','Tanda kegiatan lapangan']]:[])];
function lyDraw(){$('ly').innerHTML=LY.map(([k,n])=>{const has=k==='pipe'||k==='mh'||have[k];return '<label'+(HIS.has(k)?' class="hi"':'')+'><input type="checkbox" data-l="'+k+'"'+(vis[k]&&has?' checked':'')+(has?'':' disabled')+'><span>'+n+(has?'':' <small>(belum ada data)</small>')+(have[k]&&(SHOW_HI_STATS||!HIS.has(k))?' <small>'+fmt(have[k],0)+'</small>':'')+(HIS.has(k)&&HI_MINZ>0?' <small>· tampil di zoom ≥ '+HI_MINZ+'</small>':'')+'</span></label>'}).join('')+(HI_MINZ>0?'<p class="sm" style="grid-column:1/-1">House inlet muncul otomatis saat peta diperbesar sampai zoom '+HI_MINZ+'.</p>':'')}
function hiTable(){const z={};let n={sr:0,hic:0,hip:0};
 ['sr','hic','hip'].forEach(k=>SL[k].eachLayer(l=>{const q=l._zn==null?'-':l._zn;(z[q]=z[q]||{sr:0,hic:0,hip:0})[k]++;n[k]++}));
 if(!(n.sr+n.hic+n.hip))return;
 $('hit').innerHTML=Object.keys(z).sort((a,b)=>a-b).map(k=>'<tr><td>'+(k==='-'?'Di luar zona':'Zona '+k)+'</td><td>'+fmt(z[k].sr,0)+'</td><td>'+fmt(z[k].hic+z[k].hip,0)+'</td></tr>').join('')+'<tr><td><b>Total</b></td><td><b>'+fmt(n.sr,0)+'</b></td><td><b>'+fmt(n.hic+n.hip,0)+'</b></td></tr>';
 $('kHi').textContent=fmt(n.sr+n.hic+n.hip,0)}
function syncStatic(){let ch=false;Object.keys(SL).forEach(k=>{const on=vis[k]&&have[k]&&(!HIS.has(k)||map.getZoom()>=HI_MINZ);if(on&&!map.hasLayer(SL[k])){SL[k].addTo(map);ch=true}else if(!on&&map.hasLayer(SL[k])){map.removeLayer(SL[k]);ch=true}});document.body.classList.toggle('zrw',map.getZoom()>=15);document.body.classList.toggle('hifar',map.getZoom()<HI_MINZ);if(ch)restack()}
map.on('zoomend',syncStatic);
$('ly').onchange=e=>{const k=e.target.dataset.l;vis[k]=e.target.checked;syncStatic();if(k==='pipe'||k==='mh')render(false)};
let tt;const toast=m=>{const t=$('toast');t.textContent=m;t.style.display='block';clearTimeout(tt);tt=setTimeout(()=>{t.style.display='none'},3500)};
const GPS=L.Control.extend({options:{position:'topright'},onAdd(){const b=L.DomUtil.create('button','gps');b.id='gps';b.title='Lokasi saya (GPS)';b.setAttribute('aria-label','Lokasi saya');b.setAttribute('aria-pressed','false');b.innerHTML='<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="4"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/></svg>';L.DomEvent.disableClickPropagation(b);b.onclick=gpsToggle;return b}});
map.addControl(new GPS());
let me=null,acc=null,first=true;
function gpsToggle(){const b=$('gps');
 if(b.getAttribute('aria-pressed')==='true'){map.stopLocate();[me,acc].forEach(x=>x&&map.removeLayer(x));me=acc=null;b.setAttribute('aria-pressed','false');toast('GPS dimatikan');return}
 if(!navigator.geolocation){toast('Perangkat ini tidak mendukung GPS');return}
 first=true;b.setAttribute('aria-pressed','true');toast('Mencari lokasi...');map.locate({watch:true,enableHighAccuracy:true,setView:false,maximumAge:5000})}
map.on('locationfound',e=>{
 if(!me){acc=L.circle(e.latlng,{pane:'pm',interactive:false,radius:e.accuracy,color:'#1c7ed6',weight:1,fillOpacity:.12}).addTo(map);me=L.circleMarker(e.latlng,{pane:'pm',interactive:false,radius:8,color:'#fff',weight:3,fillColor:'#1c7ed6',fillOpacity:1}).addTo(map)}
 else{me.setLatLng(e.latlng);acc.setLatLng(e.latlng).setRadius(e.accuracy)}
 if(first){first=false;map.flyTo(e.latlng,Math.max(map.getZoom(),18))}toast('Akurasi sekitar '+Math.round(e.accuracy)+' m')});
map.on('locationerror',e=>{$('gps').setAttribute('aria-pressed','false');map.stopLocate();toast(e.code===1?'Izin lokasi ditolak. Aktifkan izin lokasi untuk situs ini di pengaturan browser.':'Lokasi belum didapat. Pastikan GPS aktif dan coba di tempat terbuka.')});
const mob=()=>matchMedia('(max-width:820px)').matches,sh=n=>{document.body.classList.remove('sh1','sh2');if(n)document.body.classList.add('sh'+n);document.body.dataset.sh=n};
(function(){
 const grab=$('grab');let sy=0,sh0=0,drag=false,moved=false;
 const vh=()=>innerHeight;
 const cur=()=>{const cs=getComputedStyle(document.body);return parseFloat(cs.getPropertyValue('--sh-px'))||$('grab').parentElement.getBoundingClientRect().height};
 function down(y){sy=y;sh0=cur();drag=true;moved=false;document.body.classList.add('dragging')}
 function move(y){if(!drag)return;const dy=sy-y;if(Math.abs(dy)>4)moved=true;const h=Math.min(vh()*.92,Math.max(64,sh0+dy));document.body.style.setProperty('--sh-px',h+'px');document.body.classList.remove('sh1','sh2');document.body.dataset.sh='drag'}
 function up(){if(!drag)return;drag=false;document.body.classList.remove('dragging');const h=parseFloat(getComputedStyle(document.body).getPropertyValue('--sh-px'))||0;
  document.body.style.removeProperty('--sh-px');
  if(!moved){sh(((+document.body.dataset.sh||0)+1)%3);return}
  const f=h/vh();sh(f<.22?0:f<.68?1:2)}
 grab.addEventListener('touchstart',e=>down(e.touches[0].clientY),{passive:true});
 grab.addEventListener('touchmove',e=>{move(e.touches[0].clientY);e.preventDefault()},{passive:false});
 grab.addEventListener('touchend',up);
 grab.addEventListener('mousedown',e=>{down(e.clientY);const mm=e=>move(e.clientY),mu=()=>{up();removeEventListener('mousemove',mm);removeEventListener('mouseup',mu)};addEventListener('mousemove',mm);addEventListener('mouseup',mu)});
})();
$('q').addEventListener('focus',()=>{if(mob()&&!+document.body.dataset.sh)sh(1)});
map.on('click',()=>{if(mob()&&+document.body.dataset.sh)sh(0)});
/* ===== ALAT UKUR: jarak dan luas =====
   Hitungan memakai proyeksi UTM 49S (EPSG:32749), sama dengan sistem koordinat database,
   jadi hasilnya selaras dengan kolom panjang dan luas dari QGIS. */
const UTM=(()=>{const a=6378137,f=1/298.257223563,n=f/(2-f),A=a/(1+n)*(1+n*n/4+n**4/64),al=[n/2-2*n*n/3+5*n**3/16,13*n*n/48-3*n**3/5,61*n**3/240],k0=.9996,l0=111*Math.PI/180,c=2*Math.sqrt(n)/(1+n);
 return ll=>{const p=ll.lat*Math.PI/180,dl=ll.lng*Math.PI/180-l0,sp=Math.sin(p),t=Math.sinh(Math.atanh(sp)-c*Math.atanh(c*sp)),xi=Math.atan2(t,Math.cos(dl)),et=Math.atanh(Math.sin(dl)/Math.sqrt(1+t*t));let E=et,N=xi;al.forEach((v,i)=>{const j=2*(i+1);E+=v*Math.cos(j*xi)*Math.sinh(j*et);N+=v*Math.sin(j*xi)*Math.cosh(j*et)});return[500000+k0*A*E,10000000+k0*A*N]}})();
const msrCalc=a=>{const u=a.map(UTM),d=(p,q)=>Math.hypot(p[0]-q[0],p[1]-q[1]);let len=0,ar=0;for(let i=1;i<u.length;i++)len+=d(u[i-1],u[i]);
 if(u.length>2){let s=0;for(let i=0;i<u.length;i++){const q=u[(i+1)%u.length];s+=u[i][0]*q[1]-q[0]*u[i][1]}ar=Math.abs(s)/2}
 return{len,ar,per:u.length>2?len+d(u[0],u[u.length-1]):0}};
const fLen=m=>m>=1000?fmt(m/1000,3)+' km':fmt(m,1)+' m',fAr=m=>fmt(m,1)+' m²';
const MC='#c2255c',mc=map.getContainer(),mg=L.featureGroup().addTo(map),rb=L.polyline([],{pane:'pm',interactive:false,color:MC,weight:2,dashArray:'5 5'}).addTo(map);
let mPts=[],mMode='d',mOn=false,mDn=null;
const mp=L.DomUtil.create('div','',$('map'));mp.id='msrp';mp.hidden=true;
mp.innerHTML='<div class="seg"><button class="btn" data-m="d" aria-pressed="true">Jarak</button><button class="btn" data-m="a" aria-pressed="false">Luas</button></div><p id="msrT"></p><div class="mb"><button class="btn" id="msrU">Urungkan</button><button class="btn" id="msrC">Hapus</button><button class="btn" id="msrX">Tutup</button></div>';
L.DomEvent.disableClickPropagation(mp);L.DomEvent.disableScrollPropagation(mp);
const mTag=(ll,t)=>L.tooltip({permanent:true,direction:'top',offset:[0,-8],className:'mlbl'}).setLatLng(ll).setContent(t);
function msrText(cur){const a=cur?mPts.concat([cur]):mPts,T=$('msrT');
 if(mMode==='d'){if(!a.length){T.innerHTML='Klik peta untuk menambah titik. Klik titik demi titik mengikuti jalur yang diukur.';return}
  const r=msrCalc(a),last=a.length>1?msrCalc(a.slice(-2)).len:0;T.innerHTML='Total jarak<br><b>'+fLen(r.len)+'</b>'+(a.length>2?'<br><span class="sm">Segmen terakhir '+fLen(last)+'</span>':'')}
 else{if(a.length<3){T.innerHTML='Klik minimal 3 titik untuk membentuk area. Titik terkumpul: '+a.length;return}
  const r=msrCalc(a);T.innerHTML='Luas<br><b>'+fAr(r.ar)+'</b><br><span class="sm">'+fmt(r.ar/10000,4)+' ha, keliling '+fLen(r.per)+'</span>'}}
function msrRedraw(){mg.clearLayers();rb.setLatLngs([]);const st={pane:'pm',interactive:false,color:MC,weight:3};
 if(mMode==='a'&&mPts.length>2){const pg=L.polygon(mPts,{...st,fillColor:MC,fillOpacity:.18}).addTo(mg);mTag(pg.getBounds().getCenter(),fAr(msrCalc(mPts).ar)).addTo(mg)}
 else if(mPts.length>1)L.polyline(mPts,st).addTo(mg);
 mPts.forEach((p,i)=>{L.circleMarker(p,{pane:'pm',interactive:false,radius:5,color:'#fff',weight:2,fillColor:MC,fillOpacity:1}).addTo(mg);
  if(mMode==='d'&&i>0)mTag(p,fLen(msrCalc(mPts.slice(0,i+1)).len)).addTo(mg)});
 msrText()}
function msrSet(v){mOn=v;mp.hidden=!v;$('msr').setAttribute('aria-pressed',String(v));mc.classList.toggle('msr-on',v);
 if(v){map.closePopup();clearHl();if(mob())sh(0);msrRedraw()}else{mPts=[];msrRedraw()}}
const MSR=L.Control.extend({options:{position:'topright'},onAdd(){const b=L.DomUtil.create('button','gps');b.id='msr';b.title='Ukur jarak dan luas';b.setAttribute('aria-label','Ukur jarak dan luas');b.setAttribute('aria-pressed','false');
 b.innerHTML='<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M3 17 17 3l4 4L7 21z"/><path d="M7 13l2 2M10 10l2 2M13 7l2 2"/></svg>';
 L.DomEvent.disableClickPropagation(b);b.onclick=()=>msrSet(!mOn);return b}});
map.addControl(new MSR());
mp.querySelector('.seg').onclick=e=>{const b=e.target.closest('button');if(!b)return;mMode=b.dataset.m;mp.querySelectorAll('.seg .btn').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));msrRedraw()};
$('msrU').onclick=()=>{mPts.pop();msrRedraw()};$('msrC').onclick=()=>{mPts=[];msrRedraw()};$('msrX').onclick=()=>msrSet(false);
/* Klik ditangkap di fase capture supaya pipa, manhole, dan popup di bawah kursor tidak ikut bereaksi saat mengukur. */
mc.addEventListener('pointerdown',e=>{mDn=[e.clientX,e.clientY]},true);
mc.addEventListener('click',e=>{if(!mOn||e.target.closest('#msrp,.leaflet-control,#lg'))return;e.stopPropagation();e.preventDefault();
 if(mDn&&Math.hypot(e.clientX-mDn[0],e.clientY-mDn[1])>6)return;mPts.push(map.mouseEventToLatLng(e));msrRedraw()},true);
mc.addEventListener('dblclick',e=>{if(mOn&&!e.target.closest('#msrp,.leaflet-control,#lg'))e.stopPropagation()},true);
map.on('mousemove',e=>{if(!mOn||!mPts.length)return;rb.setLatLngs(mMode==='a'&&mPts.length>1?[mPts[mPts.length-1],e.latlng,mPts[0]]:[mPts[mPts.length-1],e.latlng]);msrText(e.latlng)});
document.addEventListener('keydown',e=>{if(mOn&&e.key==='Escape')msrSet(false)});
/* ===== PANDUAN PENGGUNAAN (tur) =====
   Muncul otomatis saat pertama kali dashboard dibuka, bisa dilewati, dan dibuka lagi lewat tombol "Panduan" di header.
   Untuk mengubah isi: edit daftar TOUR di bawah. t = elemen yang disorot (selector CSS), c = true bila tanpa sorotan.
   Untuk memunculkan lagi bagi semua pengguna setelah panduan diubah, ganti TOUR_KEY (mis. _v2). */
const TOUR_KEY='cwis06_tour_v1',MO=' <span class="mo">Di HP, tarik gagang panel di bawah layar ke atas.</span>';
const TOUR=[
 {c:true,h:'Selamat datang di dashboard CWIS 06',p:'Dashboard ini memantau progres pekerjaan pipa lateral dan manhole sewerage di Banjardowo dan Genuksari. Panduan singkat ini menjelaskan fitur-fiturnya. Anda bisa melewatinya kapan saja dan membukanya lagi lewat tombol <b>Panduan</b> di bagian atas.'},
 {t:'#q',h:'Cari manhole atau pipa',p:'Ketik ID (misalnya <b>MHJ_06_0752</b>), nama jalan, atau material. Pilih salah satu hasil untuk langsung memperbesar peta ke lokasinya. Tekan tombol <b>/</b> di keyboard untuk cepat ke kotak ini.'+MO},
 {t:'aside .seg',h:'Tampilan peta',p:'<b>Metode</b> mewarnai pipa berdasarkan metode kerja (Jacking atau Open Trench). <b>Progres</b> mewarnai pipa berdasarkan persen progres. Keterangan warna ada di legenda pada peta.'+MO},
 {t:'#lyBox',h:'Layer peta',p:'Buka bagian ini untuk menyalakan atau mematikan layer: pipa collecting, pipa persil, inspection chamber, batas RW, dan house inlet (SR, HI, HIP). House inlet awalnya mati. Setelah dicentang, titiknya muncul mulai zoom '+HI_MINZ+'.'+MO},
 {t:'#bmBox',h:'Peta dasar',p:'Ganti latar peta: OpenStreetMap, citra satelit Esri, <b>Ortofoto CWIS-06</b>, atau tanpa peta dasar. Ortofoto tampil sendiri tanpa peta lain, jadi area di luar cakupan foto akan kosong.'+MO},
 {t:'.pg',h:'Ringkasan progres',p:'Persentase progres dihitung berbobot panjang pipa yang tergambar. Di bawahnya ada panjang tergambar, panjang terpasang setara, jumlah ruas pipa, manhole yang selesai'+(SHOW_HI_STATS?', dan jumlah house inlet':'')+'.'+MO},
 {t:'.fl',h:'Filter',p:'Saring peta berdasarkan <b>zona</b>, <b>kelas pipa</b> (Primary, Secondary, Tertiary), dan <b>status</b> (belum mulai, berjalan, selesai). Tombol <b>Reset</b> mengembalikan semua filter.'+MO},
 {t:'#zones',h:'Progres per zona',p:'Klik satu zona untuk memfilter data dan memperbesar peta ke zona itu. Klik lagi untuk melepas pilihan.'+MO},
 {t:'#lg',h:'Klik objek di peta',p:'Klik pipa atau manhole untuk melihat detailnya: lokasi, elevasi, kedalaman, dan status progres. Legenda warna ada di kiri bawah peta, dan di HP lewat tombol <b>Legenda</b>.'},
 {t:'#msr',h:'Ukur jarak dan luas',p:'Klik tombol penggaris, lalu pilih <b>Jarak</b> atau <b>Luas</b> dan klik titik demi titik di peta. Hasilnya muncul di panel. Gunakan <b>Urungkan</b>, <b>Hapus</b>, atau <b>Tutup</b> (juga bisa dengan tombol Esc).'},
 {t:'#gps',h:'Lokasi saya',p:'Tombol ini menampilkan posisi Anda di peta, berguna saat di lapangan. Browser akan meminta izin lokasi, dan GPS paling akurat di tempat terbuka.'},
 ...(FOTO_URL?[
  {t:'#fdt',h:'Tanggal kegiatan',p:'Peta hanya menampilkan kegiatan lapangan <b>7 hari ke belakang</b> dari tanggal yang dipilih. Gunakan tanda panah atau kalender untuk berpindah hari, dan <b>Hari ini</b> untuk kembali. Tanda bulat kecil di dekat manhole atau pipa berarti ada kegiatan di sana (kuning berdenyut = kegiatan pada tanggal yang dipilih, angka = jumlah foto).'},
  {t:'#fotoBtn',h:'Unggah foto dokumentasi',p:'Petugas lapangan mengunggah foto dari sini. Isi nama, kode akses, tanggal, dan keterangan kegiatan, lalu ambil foto di lokasi dan tekan Unggah. Foto otomatis tersimpan di Google Drive dalam folder per hari, per pekan, dan per bulan. Aktifkan GPS dan izinkan akses lokasi.'},
  {t:'#fnBtn',h:'Kegiatan terbaru',p:'Daftar kegiatan 7 hari terakhir, satu baris per keterangan pekerjaan dan dikelompokkan per hari. Ketuk satu kegiatan untuk melihat lokasinya di peta, atau ketuk gambar kecilnya untuk membuka foto.'},
  {t:'#lg',h:'Dokumentasi di popup',p:'Klik pipa atau manhole yang bertanda kegiatan: dokumentasinya tampil di bagian bawah popup, satu baris per kegiatan. Ketuk barisnya untuk membuka foto ukuran besar.'}]:[]),
 {t:'.hb',h:'Panel dan tema',p:'<b>Panel</b> menyembunyikan atau menampilkan panel kiri agar peta lebih luas (di komputer). <b>Tema</b> mengganti mode terang atau gelap. <b>Panduan</b> membuka kembali tutorial ini.'},
 {c:true,h:'Selesai',p:'Anda siap memakai dashboard. Kalau butuh panduan lagi, klik tombol <b>Panduan</b> di bagian atas halaman.'}
];
const tEl=document.createElement('div');tEl.id='tour';tEl.hidden=true;
tEl.innerHTML='<div class="bd"></div><div class="hl"></div><div class="cd" role="dialog" aria-modal="true" aria-labelledby="tourH"><span class="sm" id="tourN"></span><h3 id="tourH"></h3><p id="tourP"></p><div class="tr"><button class="btn" id="tourS">Lewati</button><span class="sp"></span><button class="btn" id="tourB">Kembali</button><button class="btn" id="tourF">Lanjut</button></div></div>';
document.body.appendChild(tEl);
let ti=0,tOn=false;
const tSeen=()=>{try{return localStorage.getItem(TOUR_KEY)==='1'}catch(e){return false}},tMark=()=>{try{localStorage.setItem(TOUR_KEY,'1')}catch(e){}};
function tPlace(){const s=TOUR[ti],el=!mob()&&s.t?document.querySelector(s.t):null,r=el?el.getBoundingClientRect():null,ok=!!r&&r.width>4&&r.height>4,hl=tEl.querySelector('.hl');
 tEl.classList.toggle('c',!ok);
 if(ok){const d=6;Object.assign(hl.style,{display:'block',left:(r.left-d)+'px',top:(r.top-d)+'px',width:(r.width+2*d)+'px',height:(r.height+2*d)+'px'})}else hl.style.display='none'}
function tShow(i){ti=Math.max(0,Math.min(TOUR.length-1,i));const s=TOUR[ti],last=ti===TOUR.length-1;
 $('tourN').textContent=ti&&!last?'Langkah '+ti+' dari '+(TOUR.length-2):'Panduan';
 $('tourH').textContent=s.h;$('tourP').innerHTML=s.p;
 $('tourB').style.visibility=ti?'visible':'hidden';$('tourS').style.display=last?'none':'';
 $('tourF').textContent=ti===0?'Mulai':last?'Selesai':'Lanjut';
 const el=!mob()&&s.t?document.querySelector(s.t):null;if(el)el.scrollIntoView({block:'nearest'});
 tPlace();$('tourF').focus()}
function tOpen(){if(mob())sh(0);map.closePopup();if(mOn)msrSet(false);tOn=true;tEl.hidden=false;tShow(0)}
function tClose(){tOn=false;tEl.hidden=true;tMark()}
$('tourF').onclick=()=>{ti===TOUR.length-1?tClose():tShow(ti+1)};$('tourB').onclick=()=>tShow(ti-1);$('tourS').onclick=tClose;
tEl.querySelector('.bd').onclick=()=>{};
window.addEventListener('resize',()=>{if(tOn)tPlace()});
document.addEventListener('keydown',e=>{if(!tOn)return;if(e.key==='Escape')tClose();else if(e.key==='ArrowRight')$('tourF').click();else if(e.key==='ArrowLeft'&&ti)tShow(ti-1)});
const tBtn=document.createElement('button');tBtn.className='btn';tBtn.id='tourBtn';tBtn.textContent='Panduan';tBtn.title='Buka panduan penggunaan';tBtn.onclick=tOpen;
const hbx=document.querySelector('.hb');hbx.insertBefore(tBtn,hbx.firstChild);
if(!tSeen()&&location.hash!=='#unggah')setTimeout(tOpen,700);

/* ===== DOKUMENTASI KEGIATAN LAPANGAN =====
   Petugas mengunggah foto lewat tombol "Foto" (kanan atas peta). Foto disimpan ke Google Drive lewat Google Apps Script
   (lihat foto/Code.gs dan README bagian B8). Di peta, foto tidak ditampilkan satu per satu: setiap lokasi kegiatan
   diberi tanda kecil bergeser dari titiknya (angka = jumlah foto). Isi dokumentasi muncul di popup pipa atau manhole
   yang diklik. Peta hanya menampilkan kegiatan 7 hari ke belakang dari tanggal yang dipilih di bar atas peta. */
map.createPane('pf').style.zIndex=646;
if(FOTO_URL)L.Popup.mergeOptions({autoPanPaddingTopLeft:[16,84]});
const TZ='Asia/Jakarta',HARI=['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'],BLN=['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'];
const ymd=d=>d.toLocaleDateString('sv-SE',{timeZone:TZ});
const dPlus=(s,n)=>{const q=s.split('-').map(Number);return new Date(Date.UTC(q[0],q[1]-1,q[2]+n)).toISOString().slice(0,10)};
const dTxt=(s,full)=>{const q=s.split('-').map(Number),w=new Date(Date.UTC(q[0],q[1]-1,q[2])).getUTCDay();return (full?HARI[w]+', ':'')+q[2]+' '+(full?BLN[q[1]-1]:BLN[q[1]-1].slice(0,3))+' '+q[0]};
const fTime=w=>{const d=new Date(w);return isNaN(d)?'':d.toLocaleTimeString('id-ID',{timeZone:TZ,hour:'2-digit',minute:'2-digit',hour12:false}).replace(':','.')};
const drvUrl=(id,w)=>'https://drive.google.com/thumbnail?id='+encodeURIComponent(id)+'&sz=w'+w;
let fDate=ymd(new Date()),FOTOS=[],fAuto=false,fLast=[];const fMarks=new Map();
const fWin=()=>({a:dPlus(fDate,-6),b:fDate});
const fInWin=p=>{const w=fWin();return p.day>=w.a&&p.day<=w.b};
const fRange=()=>{const w=fWin(),x=dTxt(w.a),y=dTxt(w.b);return (w.a.slice(0,4)===w.b.slice(0,4)?x.replace(/ \d{4}$/,''):x)+' – '+y};
const fSort=(a,b)=>new Date(b.w)-new Date(a.w);
const fWho=p=>esc(p.n)+(p.t&&p.t!=='Umum'?' · '+esc(p.t):'');
const fReady=()=>typeof MH!=='undefined'&&!!MH&&typeof PIPES!=='undefined'&&!!PIPES;
/* Mengaitkan foto ke manhole atau pipa: lewat ID yang diisi petugas, atau manhole terdekat dalam radius 25 m. */
function fLink(p){if(p._l!==undefined)return p._l;if(!fReady())return null;let r=null;const id=String(p.k||'').trim().toLowerCase(),mll=x=>[x.geometry.coordinates[1],x.geometry.coordinates[0]];
 if(id){let x=MH.features.find(z=>String(z.properties.manhole_id).toLowerCase()===id);
  if(x)r={t:'m',id:x.properties.manhole_id,ll:mll(x),f:x};
  else{x=PIPES.features.find(z=>String(z.properties.pipe_id).toLowerCase()===id);
   if(x){const c=x.geometry.type==='LineString'?x.geometry.coordinates:x.geometry.coordinates.flat(),m=c[Math.floor(c.length/2)];r={t:'p',id:x.properties.pipe_id,ll:[m[1],m[0]],f:x}}}}
 if(!r&&id){const t=TPF.get(tpKey(id));if(t)r=t}
 if(!r){const q=L.latLng(p.lat,p.lng);let best=25;MH.features.forEach(x=>{if(isRef(x.properties))return;const d=q.distanceTo(mll(x));if(d<best){best=d;r={t:'m',id:x.properties.manhole_id,ll:mll(x),f:x}}})}
 return p._l=r}
const fNorm=x=>String(x||'').trim().replace(/\s+/g,' ').toLowerCase();
/* Satu baris = satu kegiatan (keterangan yang sama pada hari yang sama), bukan satu foto. */
function fGrp(list){const g=new Map();list.forEach(p=>{const k=p.day+'|'+fNorm(p.d);let o=g.get(k);if(!o){o={day:p.day,d:String(p.d||'').trim(),list:[]};g.set(k,o)}o.list.push(p)});
 const u=a=>[...new Set(a.filter(Boolean))];
 return [...g.values()].map(o=>{o.list.sort(fSort);const ts=o.list.map(p=>fTime(p.w)).filter(Boolean).sort();
  o.ids=u(o.list.map(p=>p.k));o.who=u(o.list.map(p=>p.n));o.tim=u(o.list.map(p=>p.t&&p.t!=='Umum'?p.t:''));o.t0=ts[0]||'';o.t1=ts[ts.length-1]||'';o.last=o.list[0].w;return o})
  .sort((a,b)=>b.day.localeCompare(a.day)||new Date(b.last)-new Date(a.last))}
function fMeta(o,ids,day){const j=o.t0&&o.t1&&o.t0!==o.t1?o.t0+'–'+o.t1:o.t0,idt=o.ids.length>3?o.ids.slice(0,3).join(', ')+' +'+(o.ids.length-3):o.ids.join(', '),
  who=o.who.slice(0,2).join(', ')+(o.who.length>2?' +'+(o.who.length-2):'');
 return [day&&dTxt(o.day,true),ids&&idt,j,who,o.tim.join(', ')].filter(Boolean).map(x=>esc(x)).join(' · ')}
const fThumb=o=>'<span class="fmg"><img src="'+drvUrl(o.list[0].id,160)+'" alt="" loading="lazy" onerror="this.style.visibility=\'hidden\'">'+(o.list.length>1?'<i class="cn">'+o.list.length+' foto</i>':'')+'</span>';
const fList=l=>{const g=fGrp(l);fLast=g;return '<div class="fdl">'+g.map((o,i)=>'<button type="button" class="fdi" data-i="'+i+'"><span class="ft"><b>'+esc(o.d||'Tanpa keterangan')+'</b><small>'+fMeta(o,false,true)+'</small></span>'+fThumb(o)+'</button>').join('')+'</div>'};
/* Bagian "Dokumentasi kegiatan" di popup pipa atau manhole (dipanggil dari popP dan popM). */
function fDocs(id){if(!FOTO_URL||!FOTOS.length)return '';const k=String(id).toLowerCase(),all=FOTOS.filter(p=>{const r=fLink(p);return r&&String(r.id).toLowerCase()===k});if(!all.length)return '';
 const inw=all.filter(fInWin).sort(fSort),old=all.length-inw.length;
 return '<h4>Dokumentasi kegiatan</h4>'+(inw.length?fList(inw):'<p class="sm">Tidak ada kegiatan pada '+esc(fRange())+'.</p>')+(old?'<p class="sm">'+old+' dokumentasi lain di luar rentang ini. Ganti tanggal di bar atas peta untuk melihatnya.</p>':'')}
function fBadgePop(o){if(o.r&&o.r.t==='t')return popTP(o.r.f.properties);if(o.r&&o.r.t==='m')return popM(o.r.f.properties);if(o.r&&o.r.t==='p')return popP(o.r.f.properties);
 return '<div class="pp"><h3>Kegiatan lapangan</h3><p class="sub">Titik GPS petugas, '+esc(fRange())+'</p><h4>Dokumentasi kegiatan</h4>'+fList(o.list)+'</div>'}
function fBar(){if(!FOTO_URL)return;const t=ymd(new Date());$('fdD').value=fDate;$('fdD').max=t;$('fdN').disabled=fDate>=t;
 $('fdL').textContent='Kegiatan '+fRange()+' · '+fMarks.size+' lokasi, '+FOTOS.filter(fInWin).length+' foto'}
function fotoRender(tries){SL.foto.clearLayers();fMarks.clear();have.foto=0;tries=tries||0;
 if(!fReady()&&tries<25)setTimeout(()=>fotoRender(tries+1),400);   // tunggu data pipa dan manhole supaya foto bisa dikaitkan
 const g=new Map();FOTOS.filter(fInWin).forEach(p=>{const r=fLink(p),k=r?r.t+':'+r.id:'x:'+p.lat.toFixed(5)+','+p.lng.toFixed(5);let o=g.get(k);if(!o){o={k,r,ll:r?r.ll:[p.lat,p.lng],list:[]};g.set(k,o)}o.list.push(p)});
 g.forEach(o=>{o.list.sort(fSort);const hot=o.list[0].day===fDate;
  const m=L.marker(o.ll,{pane:'pf',keyboard:false,icon:L.divIcon({className:'fa'+(hot?' hot':''),html:'<b>'+o.list.length+'</b>',iconSize:[22,22],iconAnchor:[-5,27],popupAnchor:[0,-6],tooltipAnchor:[34,-16]})})
   .bindTooltip((o.r?o.r.id:'Titik GPS')+' · '+o.list.length+' foto · '+dTxt(o.list[0].day),{direction:'right'}).bindPopup(()=>fBadgePop(o),{maxWidth:340}).addTo(SL.foto);
  fMarks.set(o.k,m);have.foto++});
 fBar();lyDraw();syncStatic()}
function fSetDate(s){const t=ymd(new Date());if(!/^\d{4}-\d{2}-\d{2}$/.test(s||''))return;fDate=s>t?t:s;map.closePopup();fotoRender();if(!FNW.hidden)fnRender()}
function fotoLoad(){if(!FOTO_URL)return;
 fetch(FOTO_URL,{cache:'no-store'}).then(r=>r.json()).then(a=>{
  FOTOS=(Array.isArray(a)?a:[]).filter(p=>p&&p.id&&isFinite(p.lat)&&isFinite(p.lng)).map(p=>{p.lat=+p.lat;p.lng=+p.lng;p.day=/^\d{4}-\d{2}-\d{2}$/.test(p.tg||'')?p.tg:(isNaN(new Date(p.w))?'':ymd(new Date(p.w)));return p}).filter(p=>p.day);
  fotoRender();
  if(!fAuto){fAuto=true;let seen=false;try{seen=sessionStorage.getItem('cwis06_fnew')==='1'}catch(e){}
   if((mob()?FOTO_AUTO_MOBILE:FOTO_AUTO)&&FOTOS.some(fInWin)&&!seen&&tSeen()&&!tOn&&FUP.hidden&&location.hash!=='#unggah'){try{sessionStorage.setItem('cwis06_fnew','1')}catch(e){}fnOpen()}}}).catch(()=>{})}

/* ----- Penampil foto (lightbox) ----- */
const FLB=document.createElement('div');FLB.id='flb';FLB.hidden=true;
FLB.innerHTML='<div class="bx" role="dialog" aria-modal="true" aria-labelledby="flbH"><div class="im"><img id="flbI" alt="Foto dokumentasi"></div><div class="cp"><h3 id="flbH"></h3><div class="mt" id="flbM"></div><div class="ac"><button type="button" class="btn" id="flbP">‹ Sebelumnya</button><span class="sm" id="flbC"></span><button type="button" class="btn" id="flbN">Berikutnya ›</button><span class="sp"></span><a class="btn" id="flbD" target="_blank" rel="noopener">Buka di Drive</a><button type="button" class="btn" id="flbX">Tutup</button></div></div></div>';
document.body.appendChild(FLB);
let flL=[],flI=0;
function flbShow(i){flI=(i+flL.length)%flL.length;const p=flL[flI];$('flbI').src=drvUrl(p.id,1600);$('flbH').textContent=p.d||'Tanpa keterangan';
 $('flbM').innerHTML='<span class="chip">'+esc(dTxt(p.day,true))+' · '+fTime(p.w)+'</span>'+(p.k?'<span class="chip">'+esc(p.k)+'</span>':'')+'<span class="chip">'+esc(p.n)+'</span>'+(p.t&&p.t!=='Umum'?'<span class="chip">'+esc(p.t)+'</span>':'');
 $('flbC').textContent=(flI+1)+' / '+flL.length;$('flbD').href='https://drive.google.com/file/d/'+encodeURIComponent(p.id)+'/view';$('flbP').disabled=$('flbN').disabled=flL.length<2}
function flbOpen(l,i){flL=l.slice();FLB.hidden=false;flbShow(i)}
$('flbP').onclick=()=>flbShow(flI-1);$('flbN').onclick=()=>flbShow(flI+1);$('flbX').onclick=()=>{FLB.hidden=true};
FLB.addEventListener('click',e=>{if(e.target===FLB)FLB.hidden=true});
document.addEventListener('keydown',e=>{if(FLB.hidden)return;e.stopImmediatePropagation();if(e.key==='Escape')FLB.hidden=true;else if(e.key==='ArrowLeft')flbShow(flI-1);else if(e.key==='ArrowRight')flbShow(flI+1)},true);
map.on('popupopen',e=>{const el=e.popup.getElement();if(!el)return;el.querySelectorAll('.fdi').forEach(b=>{b.onclick=()=>{const o=fLast[+b.dataset.i];if(o)flbOpen(o.list,0)}})});

/* Ukuran popup menyesuaikan zoom peta dan layar: makin jauh di-zoom out, makin kecil. Di HP dibuat lebih kecil lagi. */
function popApply(){const z=map.getZoom(),k=(z>=17?1:z>=16?.93:z>=15?.86:z>=14?.8:.74)*(mob()?.88:1);mc.style.setProperty('--ps',k);const p=map._popup;if(p&&map.hasLayer(p))p.update()}
map.on('zoomend',popApply);window.addEventListener('resize',popApply);popApply();

/* ----- Formulir unggah ----- */
const FUP=document.createElement('div');FUP.id='fup';FUP.hidden=true;
FUP.innerHTML='<div class="cd" role="dialog" aria-modal="true" aria-labelledby="fupH"><h3 id="fupH">Unggah foto dokumentasi</h3>'
 +'<label class="f">Nama petugas<input id="fN" type="text" autocomplete="name"></label>'
 +'<label class="f">Kode akses<input id="fK" type="password" autocomplete="off"></label>'
 +'<label class="f">ID manhole, pipa, atau test pit (opsional)<input id="fI" type="text" list="fIL" autocomplete="off" placeholder="mis. MHJ_06_0752"></label><datalist id="fIL"></datalist>'
 +'<label class="f">Tanggal kegiatan<input id="fT" type="date"></label>'
 +'<label class="f">Keterangan kegiatan<textarea id="fD" rows="2" maxlength="300" placeholder="mis. Pekerjaan grouting shaft"></textarea></label>'
 +'<div class="fb"><button type="button" class="btn" id="fCam">Ambil foto</button><button type="button" class="btn" id="fGal">Pilih dari galeri</button></div>'
 +'<input type="file" id="fFc" accept="image/*" capture="environment" hidden><input type="file" id="fFg" accept="image/*" multiple hidden>'
 +'<div class="fth" id="fTh"></div>'
 +'<div class="floc"><b>Lokasi foto</b><p class="sm" id="fLs"></p>'
 +'<label class="fr"><input type="radio" name="fsrc" value="gps" checked><span>Lokasi saya sekarang (GPS). Pilih ini bila foto diambil di tempat.</span></label>'
 +'<label class="fr"><input type="radio" name="fsrc" value="id" disabled><span>Titik <b id="fIn">manhole atau pipa</b> di atas. Pilih ini untuk foto dari galeri.</span></label>'
 +'<button type="button" class="btn" id="fRe" style="margin-top:8px">Ambil ulang lokasi</button></div>'
 +'<p class="sm" id="fMsg" role="status"></p>'
 +'<div class="tr"><button type="button" class="btn" id="fX">Batal</button><span class="sp"></span><button type="button" class="btn" id="fS">Unggah</button></div></div>';
document.body.appendChild(FUP);
let fFiles=[],fGps=null,fBusy=false;
const LS=(k,v)=>{try{if(v===undefined)return localStorage.getItem(k)||'';localStorage.setItem(k,v)}catch(e){return ''}};
function fPt(id){id=String(id||'').trim().toLowerCase();if(!id)return null;let f;
 if(typeof MH!=='undefined'&&MH){f=MH.features.find(x=>String(x.properties.manhole_id).toLowerCase()===id);if(f)return{lat:f.geometry.coordinates[1],lng:f.geometry.coordinates[0],nm:f.properties.manhole_id}}
 if(typeof PIPES!=='undefined'&&PIPES){f=PIPES.features.find(x=>String(x.properties.pipe_id).toLowerCase()===id);if(f){const c=f.geometry.type==='LineString'?f.geometry.coordinates:f.geometry.coordinates.flat(),m=c[Math.floor(c.length/2)];return{lat:m[1],lng:m[0],nm:f.properties.pipe_id}}}
 if(TPF.size){const t=TPF.get(tpKey(id));if(t)return{lat:t.ll[0],lng:t.ll[1],nm:t.id}}
 return null}
function fRefresh(failed){const q=fPt($('fI').value),r=document.querySelectorAll('[name=fsrc]');
 $('fIn').textContent=q?q.nm:'manhole atau pipa';r[1].disabled=!q;
 if(!q&&r[1].checked)r[0].checked=true;if(q&&!fGps)r[1].checked=true;
 if(fGps)$('fLs').textContent='GPS didapat, akurasi sekitar '+fGps.acc+' m'+(fGps.acc>50?'. Akurasi rendah, coba ulangi di tempat terbuka.':'.');
 else if(failed)$('fLs').textContent='GPS tidak tersedia. Aktifkan GPS dan izin lokasi, atau isi ID manhole atau pipa lalu pakai titiknya.'}
function fLoc(){fGps=null;$('fLs').textContent='Mencari lokasi GPS...';
 if(!navigator.geolocation){fRefresh(true);return}
 navigator.geolocation.getCurrentPosition(p=>{fGps={lat:p.coords.latitude,lng:p.coords.longitude,acc:Math.round(p.coords.accuracy)};fRefresh()},()=>{fGps=null;fRefresh(true)},{enableHighAccuracy:true,timeout:20000,maximumAge:0})}
function fThumbs(){const w=$('fTh');w.innerHTML='';fFiles.forEach((f,i)=>{const d=document.createElement('div'),im=new Image(),b=document.createElement('button');im.src=URL.createObjectURL(f);im.alt='';b.type='button';b.textContent='×';b.setAttribute('aria-label','Hapus foto');b.onclick=()=>{fFiles.splice(i,1);fThumbs()};d.append(im,b);w.append(d)})}
const F_MAX=10;   // jumlah foto maksimal per sekali unggah
function fAdd(list){let skip=0;[...list].forEach(f=>{if(fFiles.length<F_MAX)fFiles.push(f);else skip++});$('fMsg').textContent=skip?'Maksimal '+F_MAX+' foto per unggahan. '+skip+' foto tidak ditambahkan.':'';fThumbs()}
async function fKecil(file){let bm;
 try{bm=await createImageBitmap(file,{imageOrientation:'from-image'})}catch(e){bm=await new Promise((ok,no)=>{const i=new Image();i.onload=()=>ok(i);i.onerror=no;i.src=URL.createObjectURL(file)})}
 const w=bm.width||bm.naturalWidth,h=bm.height||bm.naturalHeight,k=Math.min(1,1600/Math.max(w,h)),c=document.createElement('canvas');
 c.width=Math.round(w*k);c.height=Math.round(h*k);c.getContext('2d').drawImage(bm,0,0,c.width,c.height);
 const blob=await new Promise(r=>c.toBlob(r,'image/jpeg',.8));
 return await new Promise((ok,no)=>{const fr=new FileReader();fr.onload=()=>ok(String(fr.result).split(',')[1]);fr.onerror=no;fr.readAsDataURL(blob)})}
function fOpen(){if(tOn)tClose();map.closePopup();if(mOn)msrSet(false);if(mob())sh(0);
 const hi=ymd(new Date());$('fT').max=hi;$('fT').min=dPlus(hi,-60);$('fT').value=hi;
 $('fN').value=LS('fo_nama');$('fK').value=LS('fo_kode');$('fMsg').textContent='';
 const ids=[];if(typeof MH!=='undefined'&&MH)MH.features.forEach(x=>{if(!isRef(x.properties))ids.push(x.properties.manhole_id)});if(typeof PIPES!=='undefined'&&PIPES)PIPES.features.forEach(x=>ids.push(x.properties.pipe_id));TPF.forEach(t=>ids.push(t.id));
 $('fIL').innerHTML=ids.map(v=>'<option value="'+esc(v)+'">').join('');
 FUP.hidden=false;fLoc();fRefresh()}
const fClose=()=>{FUP.hidden=true};
async function fKirim(){if(fBusy)return;const nama=$('fN').value.trim(),pin=$('fK').value.trim(),m=$('fMsg'),idv=$('fI').value.trim(),q=fPt(idv),src=document.querySelector('[name=fsrc]:checked').value,pt=src==='id'&&q?q:fGps,tg=$('fT').value||ymd(new Date());
 if(!nama){m.textContent='Isi nama petugas.';return}if(!pin){m.textContent='Isi kode akses.';return}
 if(!fFiles.length){m.textContent='Tambahkan minimal satu foto.';return}
 if(!pt){m.textContent='Lokasi belum tersedia. Ambil ulang lokasi atau isi ID manhole atau pipa yang valid.';return}
 fBusy=true;$('fS').disabled=true;LS('fo_nama',nama);LS('fo_kode',pin);
 try{const total=fFiles.length;let noShare=false;
  for(let i=0;i<total;i++){m.textContent='Mengunggah foto '+(i+1)+' dari '+total+'...';
   const b64=await fKecil(fFiles[0]);
   const r=await fetch(FOTO_URL,{method:'POST',headers:{'Content-Type':'text/plain;charset=utf-8'},body:JSON.stringify({kode_akses:pin,nama:nama,kode:idv,tanggal:tg,keterangan:$('fD').value.trim(),lat:pt.lat,lng:pt.lng,akurasi:src==='gps'&&fGps?fGps.acc:'',sumber:src==='id'&&q?'titik '+q.nm:'gps',foto:b64})});
   const j=await r.json();if(!j.ok)throw new Error(j.pesan||'Server menolak unggahan');if(j.bagikan===false)noShare=true;
   fFiles.shift();fThumbs()}
  toast(noShare?'Foto terunggah, tetapi folder Drive belum dibagikan sehingga gambar belum tampil. Hubungi admin.':'Foto berhasil diunggah');
  $('fD').value='';fClose();const w=fWin();if(tg<w.a||tg>w.b)fDate=tg;fotoLoad();map.setView([pt.lat,pt.lng],Math.max(map.getZoom(),18))}
 catch(e){m.textContent='Gagal mengunggah: '+(e.message||e)+'. Periksa sinyal dan kode akses, lalu coba lagi.'}
 finally{fBusy=false;$('fS').disabled=false}}
$('fCam').onclick=()=>$('fFc').click();$('fGal').onclick=()=>$('fFg').click();
$('fFc').onchange=e=>{fAdd(e.target.files);e.target.value=''};$('fFg').onchange=e=>{fAdd(e.target.files);e.target.value=''};
$('fI').oninput=()=>fRefresh();$('fRe').onclick=fLoc;$('fX').onclick=fClose;$('fS').onclick=fKirim;
document.addEventListener('keydown',e=>{if(!FUP.hidden&&e.key==='Escape')fClose()});

/* ----- Daftar kegiatan terbaru (rentang 7 hari menurut tanggal di bar atas peta) ----- */
const FNW=document.createElement('div');FNW.id='fnew';FNW.hidden=true;
FNW.innerHTML='<div class="cd" role="dialog" aria-modal="true" aria-labelledby="fnH"><div class="fhd"><h3 id="fnH">Kegiatan terbaru</h3><button type="button" class="btn" id="fnX">Tutup</button></div><p class="sm" id="fnR"></p><label class="f" id="fnTl">Tampilkan dari tim<select id="fnT"></select></label><div id="fnL"></div></div>';
document.body.appendChild(FNW);
let fnShown=[];
function fnRender(){const t=$('fnT').value,a=FOTOS.filter(p=>fInWin(p)&&(!t||p.t===t)),g=fGrp(a);fnShown=g;
 $('fnR').textContent='Rentang '+fRange()+' ('+g.length+' kegiatan, '+a.length+' foto). Ubah tanggal lewat bar di atas peta.';
 let h='',cur='';g.forEach((o,i)=>{if(o.day!==cur){cur=o.day;const dg=g.filter(x=>x.day===cur);h+='<div class="fdh"><span>'+esc(dTxt(cur,true))+'</span><small>'+dg.length+' kegiatan · '+dg.reduce((n,x)=>n+x.list.length,0)+' foto</small></div>'}
  h+='<div class="fni"><button type="button" class="fgo" data-i="'+i+'"><b>'+esc(o.d||'Tanpa keterangan')+'</b><small>'+fMeta(o,true,false)+'</small></button><button type="button" class="fim" data-i="'+i+'" aria-label="Lihat foto">'+fThumb(o)+'</button></div>'});
 $('fnL').innerHTML=h||'<p class="sm">Belum ada kegiatan pada rentang ini.</p>'}
function fnOpen(){const ts=[...new Set(FOTOS.map(p=>p.t).filter(Boolean))].sort();$('fnTl').hidden=ts.length<2;$('fnT').innerHTML='<option value="">Semua tim</option>'+ts.map(t=>'<option>'+esc(t)+'</option>').join('');fnRender();FNW.hidden=false}
$('fnT').onchange=fnRender;$('fnX').onclick=()=>{FNW.hidden=true};
FNW.addEventListener('click',e=>{if(e.target===FNW)FNW.hidden=true});
$('fnL').onclick=e=>{const im=e.target.closest('.fim'),go=e.target.closest('.fgo');
 if(im){const o=fnShown[+im.dataset.i];if(o)flbOpen(o.list,0);return}if(!go)return;const o=fnShown[+go.dataset.i];if(!o)return;
 FNW.hidden=true;if(mob())sh(0);if(!vis.foto){vis.foto=true;lyDraw()}syncStatic();
 const ls=o.list.map(p=>{const r=fLink(p);return{ll:r?r.ll:[p.lat,p.lng],k:r?r.t+':'+r.id:'x:'+p.lat.toFixed(5)+','+p.lng.toFixed(5)}}),ks=[...new Set(ls.map(x=>x.k))];
 if(ks.length===1){map.setView(ls[0].ll,Math.max(map.getZoom(),19));setTimeout(()=>{const m=fMarks.get(ks[0]);if(m)m.openPopup()},80)}
 else map.fitBounds(L.latLngBounds(ls.map(x=>x.ll)).pad(.3),{maxZoom:19})};
document.addEventListener('keydown',e=>{if(!FNW.hidden&&e.key==='Escape')FNW.hidden=true});

/* ----- Bar tanggal di atas peta ----- */
const FDT=document.createElement('div');FDT.id='fdt';FDT.hidden=!FOTO_URL;
FDT.innerHTML='<div class="r"><button type="button" class="btn" id="fdP" aria-label="Hari sebelumnya">‹</button><input type="date" id="fdD" aria-label="Tanggal akhir rentang"><button type="button" class="btn" id="fdN" aria-label="Hari berikutnya">›</button><button type="button" class="btn" id="fdT">Hari ini</button></div><div class="sm" id="fdL"></div>';
$('map').appendChild(FDT);L.DomEvent.disableClickPropagation(FDT);L.DomEvent.disableScrollPropagation(FDT);
$('fdD').onchange=e=>fSetDate(e.target.value);$('fdP').onclick=()=>fSetDate(dPlus(fDate,-1));$('fdN').onclick=()=>fSetDate(dPlus(fDate,1));$('fdT').onclick=()=>fSetDate(ymd(new Date()));
fBar();

const NBTN=L.Control.extend({options:{position:'topright'},onAdd(){const b=L.DomUtil.create('button','gps fbtn');b.id='fnBtn';b.title='Kegiatan terbaru';b.setAttribute('aria-label','Kegiatan terbaru');
 b.innerHTML='<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.8"/><path d="M21 16l-5-5-8 9"/></svg><span>Terbaru</span>';
 L.DomEvent.disableClickPropagation(b);b.onclick=fnOpen;return b}});
const FBTN=L.Control.extend({options:{position:'topright'},onAdd(){const b=L.DomUtil.create('button','gps fbtn');b.id='fotoBtn';b.title='Unggah foto dokumentasi';b.setAttribute('aria-label','Unggah foto dokumentasi');
 b.innerHTML='<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/></svg><span>Foto</span>';
 L.DomEvent.disableClickPropagation(b);b.onclick=fOpen;return b}});
if(FOTO_URL){map.addControl(new FBTN());map.addControl(new NBTN());fotoLoad();if(location.hash==='#unggah')setTimeout(fOpen,900)}


if(!SHOW_HI_STATS){const tb=$('hit').closest('table'),hs=[$('kHi').previousElementSibling,$('kHi'),tb,tb&&tb.previousElementSibling];hs.forEach(e=>{if(e)e.style.display='none'})}
$('lgT').onclick=()=>document.body.classList.toggle('lgon');
legend();
const NUM=['length_m','slope_pct','progress_pct','diameter_mm','depth_m','ground_elev','invert_elev','elev_downstream','elev_upstream_1','elev_upstream_2','elev_upstream_3','up_gl','up_ie','up_depth','lw_gl','lw_ie','lw_depth','drop_m'];
const norm=g=>{g.features=g.features.filter(x=>x.geometry);g.features.forEach(x=>NUM.forEach(k=>{if(k in x.properties){const v=x.properties[k];x.properties[k]=(v===null||v===undefined||v==='')?null:Number(v)}}));return g};
const get=u=>fetch(u,{cache:'no-cache'}).then(r=>{if(!r.ok)throw new Error(u+' ('+r.status+')');return r.json().then(j=>({j,lm:r.headers.get('Last-Modified')}))});
function start(){
 PIPES.features.forEach(x=>{const p=x.properties;[p.from_mh,p.to_mh].forEach(id=>{if(!mm.has(id))mm.set(id,new Set());mm.get(id).add(p.method)})});
 IDX=PIPES.features.map(x=>({t:'p',f:x,id:x.properties.pipe_id,h:hay(x.properties)})).concat(MH.features.map(x=>({t:'m',f:x,id:x.properties.manhole_id,h:hay(x.properties)+' '+(mmeth(x.properties.manhole_id)||'').toLowerCase()})));
 const opt=(id,vals)=>vals.forEach(v=>{const o=document.createElement('option');o.value=v[0];o.textContent=v[1];$(id).appendChild(o)});
 opt('fZone',[...new Set(PIPES.features.concat(MH.features).map(x=>x.properties.zone).filter(z=>z!=null))].sort((a,b)=>a-b).map(z=>[String(z),'Zona '+z]));
 opt('fCls',['Primary','Secondary','Tertiary'].map(c=>[c,c]));
 osm.addTo(map);bmDraw();map.fitBounds(L.geoJSON(PIPES).getBounds().pad(.05));render(false);lyDraw();
 Promise.allSettled(SP.map(s=>get('data/'+s.f+'.geojson').then(r=>{r.j.features=r.j.features.filter(x=>x.geometry);buildStatic(s,r.j)}))).then(()=>{lyDraw();syncStatic();legend();hiTable();if(FOTO_URL&&FOTOS.length){FOTOS.forEach(p=>{p._l=undefined});fotoRender()}});
}
Promise.all([get('data/v_lateral_pipe.geojson'),get('data/v_manhole.geojson')]).then(([a,b])=>{
 PIPES=norm(a.j);MH=norm(b.j);
 const lm=a.lm||b.lm;if(lm)$('upd').textContent=new Date(lm).toLocaleDateString('id-ID',{day:'numeric',month:'long',year:'numeric'});
  fetch('data/meta.json',{cache:'no-cache'}).then(r=>r.ok?r.json():null).then(m=>{const d=m&&m.updated?new Date(m.updated):null;if(d&&!isNaN(d))$('upd').textContent=d.toLocaleString('id-ID',{day:'numeric',month:'long',year:'numeric',hour:'2-digit',minute:'2-digit'})}).catch(()=>{});
 start();
}).catch(e=>{$('map').innerHTML='<p style="padding:16px">Data tidak bisa dimuat: '+esc(e.message)+'. Pastikan folder data berisi v_lateral_pipe.geojson dan v_manhole.geojson, dan buka halaman lewat alamat GitHub Pages, bukan dengan klik dua kali file index.html.</p>'});
