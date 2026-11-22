'use strict';
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const PORT=Number(process.env.PORT||8080),HLS=path.resolve(process.env.HLS_DIR||'/hls'),DATA=path.resolve(process.env.DATA_DIR||'/data'),MEDIA=path.resolve(process.env.MEDIA_DIR||'/media'),ALLOWED_ORIGIN=process.env.ALLOWED_ORIGIN||'https://igoryukha809-cell.github.io';
function directorStatus(){try{return JSON.parse(fs.readFileSync(path.join(DATA,'director-status.json'),'utf8'))}catch{return {status:'starting-or-waiting',encoderRunning:false}}}
const learning=require('./learning');
const MAX=32768;
const ADMIN_EMAIL=(process.env.ADMIN_EMAIL||'').trim().toLowerCase();
const LOGTO_ENDPOINT=(process.env.LOGTO_ENDPOINT||'').replace(/\\/$/,'');
const LOGTO_API_RESOURCE=(process.env.LOGTO_API_RESOURCE||'').trim();
const LOGTO_ISSUER=LOGTO_ENDPOINT?LOGTO_ENDPOINT+'/oidc':'';
const LOGTO_JWKS=LOGTO_ENDPOINT?require('jose').createRemoteJWKSet(new URL(LOGTO_ENDPOINT+'/oidc/jwks')):null;
async function adminUser(req){
 const token=String(req.headers.authorization||'').replace(/^Bearer\\s+/i,'').trim();
 const userinfoToken=String(req.headers['x-logto-userinfo-token']||'').trim();
 if(!token||!userinfoToken||!ADMIN_EMAIL||!LOGTO_API_RESOURCE||!LOGTO_JWKS)return null;
 try{
  const {payload}=await require('jose').jwtVerify(token,LOGTO_JWKS,{issuer:LOGTO_ISSUER,audience:LOGTO_API_RESOURCE,algorithms:['RS256']});
  const response=await fetch(LOGTO_ENDPOINT+'/oidc/me',{headers:{Authorization:'Bearer '+userinfoToken},signal:AbortSignal.timeout(8000)});
  if(!response.ok)return null;
  const user=await response.json();
  if(!user.email||user.email.toLowerCase()!==ADMIN_EMAIL||user.email_verified!==true)return null;
  return {id:payload.sub,email:user.email};
 }catch{return null;}
}
async function authorized(req){return !!(await adminUser(req));}
function scheduleRead(){try{return JSON.parse(fs.readFileSync(path.join(DATA,'schedule.json'),'utf8'))}catch{return {items:[]}}}
function safeSchedule(value){
 if(!value||!Array.isArray(value.items)||value.items.length>500)throw Error('Invalid playlist');
 const items=value.items.map(x=>{
  if(!x||typeof x.title!=='string'||typeof x.file!=='string'||!/^[\\w .()-]{1,180}$/.test(x.file)||typeof x.rightsCleared!=='boolean')throw Error('Invalid playlist item');
  return {title:x.title.slice(0,160),file:x.file,rightsCleared:x.rightsCleared};
 });
 return {items};
}
function send(res,status,data,type='application/json; charset=utf-8'){res.writeHead(status,{'Content-Type':type,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Access-Control-Allow-Origin':ALLOWED_ORIGIN,'Vary':'Origin'});res.end(typeof data==='string'?data:JSON.stringify(data));}
function safeFile(base,p){let d;try{d=decodeURIComponent(p)}catch{return null}const f=path.resolve(base,'.'+d);return f.startsWith(base+path.sep)?f:null}
function body(req){return new Promise((resolve,reject)=>{let s='';req.on('data',c=>{s+=c;if(s.length>MAX){reject(Error('Request too large'));req.destroy();}});req.on('end',()=>{try{resolve(JSON.parse(s||'{}'))}catch{reject(Error('Invalid JSON'))}});req.on('error',reject)})}
const server=http.createServer(async(req,res)=>{let u;try{u=new URL(req.url,'http://localhost')}catch{return send(res,400,{error:'Bad URL'})}
if(req.method==='OPTIONS'){res.writeHead(204,{'Access-Control-Allow-Origin':ALLOWED_ORIGIN,'Vary':'Origin','Access-Control-Allow-Methods':'GET,POST,PUT,HEAD,OPTIONS','Access-Control-Allow-Headers':'Content-Type, Authorization, X-Logto-Userinfo-Token'});return res.end()}
if(!['GET','HEAD','POST','PUT'].includes(req.method))return send(res,405,{error:'Method not allowed'});
if(req.method==='GET'&&u.pathname==='/health')return send(res,200,{service:'МУЛЬТИК ТВ',status:'online',director:directorStatus().status});
if(req.method==='GET'&&u.pathname==='/api/channel'){const playlist='/live/multiktv.m3u8',exists=fs.existsSync(path.join(HLS,playlist));return send(res,200,{channel:'МУЛЬТИК ТВ',server:'online',broadcast:exists?'signal-detected':'offline',playlist:exists?'/hls'+playlist:null,director:directorStatus(),updatedAt:new Date().toISOString()})}
if(req.method==='GET'&&u.pathname==='/api/director')return send(res,200,directorStatus());
if(req.method==='GET'&&u.pathname==='/api/admin/status'){
 if(!await authorized(req))return send(res,403,{error:'Admin access required'});
 let files=[];try{files=fs.readdirSync(process.env.MEDIA_DIR||'/media').filter(x=>/^[\\w .()-]{1,180}\\.(mp4|m4v|mov|webm)$/i.test(x));}catch{}
 return send(res,200,{director:directorStatus(),playlist:scheduleRead(),media:files,rtmpConfigured:!!process.env.RTMP_TARGET});
}
if(req.method==='POST'&&u.pathname==='/api/admin/upload'){
 if(!await authorized(req))return send(res,403,{error:'Admin access required'});
 const name=u.searchParams.get('filename')||'';
 if(!/^[\\w .()-]{1,160}\\.(mp4|m4v|mov|webm)$/i.test(name))return send(res,400,{error:'Use a safe video filename ending in mp4, m4v, mov or webm'});
 fs.mkdirSync(MEDIA,{recursive:true});const target=path.join(MEDIA,name);let size=0,failed=false;
 const out=fs.createWriteStream(target,{flags:'wx'});
 req.on('data',chunk=>{size+=chunk.length;if(size>524288000&&!failed){failed=true;req.destroy();out.destroy();}});
 req.pipe(out);out.on('finish',()=>send(res,201,{uploaded:true,filename:name,bytes:size}));out.on('error',e=>{if(!res.headersSent)send(res,400,{error:e.code==='EEXIST'?'File already exists':'Upload failed'})});
 return;
}
if(req.method==='PUT'&&u.pathname==='/api/admin/playlist'){
 if(!await authorized(req))return send(res,403,{error:'Admin access required'});
 try{const next=safeSchedule(await body(req));fs.mkdirSync(DATA,{recursive:true});fs.writeFileSync(path.join(DATA,'schedule.json'),JSON.stringify(next,null,2));return send(res,200,{saved:true,items:next.items.length});}catch(e){return send(res,400,{error:e.message})}
}
if(req.method==='POST'&&u.pathname==='/api/admin/broadcast/start'){
 if(!await authorized(req))return send(res,403,{error:'Admin access required'});
 const items=scheduleRead().items||[];if(!items.length||items.some(x=>x.rightsCleared!==true))return send(res,400,{error:'Add approved programme items before starting'});
 if(!process.env.RTMP_TARGET||!/^rtmps?:\\/\\//.test(process.env.RTMP_TARGET))return send(res,503,{error:'RTMP target is not configured on the server'});
 fs.mkdirSync(DATA,{recursive:true});fs.writeFileSync(path.join(DATA,'director-control.json'),JSON.stringify({enabled:true,updatedAt:new Date().toISOString()}));return send(res,202,{accepted:true,status:'starting'});
}
if(req.method==='POST'&&u.pathname==='/api/admin/broadcast/stop'){
 if(!await authorized(req))return send(res,403,{error:'Admin access required'});
 fs.mkdirSync(DATA,{recursive:true});fs.writeFileSync(path.join(DATA,'director-control.json'),JSON.stringify({enabled:false,updatedAt:new Date().toISOString()}));return send(res,202,{accepted:true,status:'stopping'});
}
if(req.method==='GET'&&u.pathname==='/api/learning')return send(res,200,learning.summary());
if(req.method==='POST'&&u.pathname==='/api/learning/event'){if(!await authorized(req))return send(res,401,{error:'Unauthorized'});try{return send(res,201,{saved:true,result:learning.record(await body(req))})}catch(e){return send(res,400,{error:e.message})}}
if(req.method==='POST'&&u.pathname==='/api/learning/recommend'){if(!await authorized(req))return send(res,401,{error:'Unauthorized'});try{return send(res,200,{recommendations:learning.recommend((await body(req)).items)})}catch(e){return send(res,400,{error:e.message})}}
if(req.method==='GET'&&u.pathname==='/api/discovery'){const q=(u.searchParams.get('q')||'cartoons').trim().slice(0,80);try{const p=new URLSearchParams({q:'mediatype:movies AND '+q.replace(/[^\p{L}\p{N} _-]/gu,' '),fl:'identifier,title,year,creator,licenseurl,rights',rows:'20',output:'json'});const r=await fetch('https://archive.org/advancedsearch.php?'+p,{signal:AbortSignal.timeout(12000)});if(!r.ok)throw Error('Source unavailable');const j=await r.json();return send(res,200,{source:'Internet Archive',results:(j.response?.docs||[]).map(x=>({title:x.title||x.identifier,year:x.year||null,creator:x.creator||null,page:'https://archive.org/details/'+encodeURIComponent(x.identifier),license:x.licenseurl||null,rights:x.rights||null,requiresManualRightsCheck:true}))})}catch(e){return send(res,502,{error:'Search failed',detail:e.message})}}
if(req.method==='GET'&&u.pathname.startsWith('/hls/')){const f=safeFile(HLS,u.pathname.slice(4));if(!f)return send(res,400,{error:'Invalid path'});return fs.stat(f,(e,s)=>{if(e||!s.isFile())return send(res,404,{error:'Stream not found'});const ext=path.extname(f).toLowerCase(),type=ext==='.m3u8'?'application/vnd.apple.mpegurl':ext==='.ts'?'video/mp2t':ext==='.m4s'?'video/iso.segment':'application/octet-stream';res.writeHead(200,{'Content-Type':type,'Cache-Control':ext==='.m3u8'?'no-store':'public,max-age=30','Access-Control-Allow-Origin':'*'});if(req.method==='HEAD')return res.end();fs.createReadStream(f).pipe(res)})}
return send(res,404,{error:'Not found'});
});
server.listen(PORT,'0.0.0.0',()=>console.log('МУЛЬТИК ТВ API listening on '+PORT));
