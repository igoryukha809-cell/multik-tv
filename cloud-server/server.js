'use strict';
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
const PORT=Number(process.env.PORT||8080),HLS=path.resolve(process.env.HLS_DIR||'/hls'),DATA=path.resolve(process.env.DATA_DIR||'/data');
function directorStatus(){try{return JSON.parse(fs.readFileSync(path.join(DATA,'director-status.json'),'utf8'))}catch{return {status:'starting-or-waiting',encoderRunning:false}}}
const learning=require('./learning');
const MAX=32768,WRITE_TOKEN=process.env.API_WRITE_TOKEN||'';
function authorized(req){const h=req.headers.authorization||'';return !!WRITE_TOKEN&&h===`Bearer ${WRITE_TOKEN}`;}
function send(res,status,data,type='application/json; charset=utf-8'){res.writeHead(status,{'Content-Type':type,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Access-Control-Allow-Origin':'*'});res.end(typeof data==='string'?data:JSON.stringify(data));}
function safeFile(base,p){let d;try{d=decodeURIComponent(p)}catch{return null}const f=path.resolve(base,'.'+d);return f.startsWith(base+path.sep)?f:null}
function body(req){return new Promise((resolve,reject)=>{let s='';req.on('data',c=>{s+=c;if(s.length>MAX){reject(Error('Request too large'));req.destroy();}});req.on('end',()=>{try{resolve(JSON.parse(s||'{}'))}catch{reject(Error('Invalid JSON'))}});req.on('error',reject)})}
const server=http.createServer(async(req,res)=>{let u;try{u=new URL(req.url,'http://localhost')}catch{return send(res,400,{error:'Bad URL'})}
if(req.method==='OPTIONS'){res.writeHead(204,{'Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET,POST,HEAD,OPTIONS','Access-Control-Allow-Headers':'Content-Type'});return res.end()}
if(!['GET','HEAD','POST'].includes(req.method))return send(res,405,{error:'Method not allowed'});
if(req.method==='GET'&&u.pathname==='/health')return send(res,200,{service:'МУЛЬТИК ТВ',status:'online',director:directorStatus().status});
if(req.method==='GET'&&u.pathname==='/api/channel'){const playlist='/live/multiktv.m3u8',exists=fs.existsSync(path.join(HLS,playlist));return send(res,200,{channel:'МУЛЬТИК ТВ',server:'online',broadcast:exists?'signal-detected':'offline',playlist:exists?'/hls'+playlist:null,director:directorStatus(),updatedAt:new Date().toISOString()})}
if(req.method==='GET'&&u.pathname==='/api/director')return send(res,200,directorStatus());
if(req.method==='GET'&&u.pathname==='/api/learning')return send(res,200,learning.summary());
if(req.method==='POST'&&u.pathname==='/api/learning/event'){if(!authorized(req))return send(res,401,{error:'Unauthorized'});try{return send(res,201,{saved:true,result:learning.record(await body(req))})}catch(e){return send(res,400,{error:e.message})}}
if(req.method==='POST'&&u.pathname==='/api/learning/recommend'){if(!authorized(req))return send(res,401,{error:'Unauthorized'});try{return send(res,200,{recommendations:learning.recommend((await body(req)).items)})}catch(e){return send(res,400,{error:e.message})}}
if(req.method==='GET'&&u.pathname==='/api/discovery'){const q=(u.searchParams.get('q')||'cartoons').trim().slice(0,80);try{const p=new URLSearchParams({q:'mediatype:movies AND '+q.replace(/[^\p{L}\p{N} _-]/gu,' '),fl:'identifier,title,year,creator,licenseurl,rights',rows:'20',output:'json'});const r=await fetch('https://archive.org/advancedsearch.php?'+p,{signal:AbortSignal.timeout(12000)});if(!r.ok)throw Error('Source unavailable');const j=await r.json();return send(res,200,{source:'Internet Archive',results:(j.response?.docs||[]).map(x=>({title:x.title||x.identifier,year:x.year||null,creator:x.creator||null,page:'https://archive.org/details/'+encodeURIComponent(x.identifier),license:x.licenseurl||null,rights:x.rights||null,requiresManualRightsCheck:true}))})}catch(e){return send(res,502,{error:'Search failed',detail:e.message})}}
if(req.method==='GET'&&u.pathname.startsWith('/hls/')){const f=safeFile(HLS,u.pathname.slice(4));if(!f)return send(res,400,{error:'Invalid path'});return fs.stat(f,(e,s)=>{if(e||!s.isFile())return send(res,404,{error:'Stream not found'});const ext=path.extname(f).toLowerCase(),type=ext==='.m3u8'?'application/vnd.apple.mpegurl':ext==='.ts'?'video/mp2t':ext==='.m4s'?'video/iso.segment':'application/octet-stream';res.writeHead(200,{'Content-Type':type,'Cache-Control':ext==='.m3u8'?'no-store':'public,max-age=30','Access-Control-Allow-Origin':'*'});if(req.method==='HEAD')return res.end();fs.createReadStream(f).pipe(res)})}
return send(res,404,{error:'Not found'});
});
server.listen(PORT,'0.0.0.0',()=>console.log('МУЛЬТИК ТВ API listening on '+PORT));
