import express from "express";
import helmet from "helmet";
import multer from "multer";
import path from "node:path";
import fs from "node:fs/promises";
import { randomUUID, timingSafeEqual } from "node:crypto";

const app=express();
app.disable("x-powered-by");
app.use(helmet({crossOriginResourcePolicy:{policy:"cross-origin"}}));
app.use(express.json({limit:"64kb"}));
const PORT=Number(process.env.PORT||10000);
const DATA=path.resolve(process.env.DATA_DIR||"./data");
const MEDIA=path.join(DATA,"media");
const DB=path.join(DATA,"library.json");
const TOKEN=process.env.UPLOAD_API_TOKEN||"";
const ORIGINS=(process.env.ALLOWED_ORIGINS||"https://igoryukha809-cell.github.io").split(",").map(x=>x.trim());
await fs.mkdir(MEDIA,{recursive:true});
async function read(){try{return JSON.parse(await fs.readFile(DB,"utf8"));}catch{return [];}}
async function write(rows){const tmp=DB+".tmp";await fs.writeFile(tmp,JSON.stringify(rows,null,2));await fs.rename(tmp,DB);}
app.use((req,res,next)=>{const o=req.headers.origin;if(o&&ORIGINS.includes(o)){res.setHeader("Access-Control-Allow-Origin",o);res.setHeader("Vary","Origin");res.setHeader("Access-Control-Allow-Headers","Authorization,Content-Type");res.setHeader("Access-Control-Allow-Methods","GET,POST,DELETE,OPTIONS");}if(req.method==="OPTIONS")return res.sendStatus(204);next();});
function auth(req,res,next){const got=(req.headers.authorization||"").replace(/^Bearer /,"");if(!TOKEN||got.length!==TOKEN.length||!timingSafeEqual(Buffer.from(got),Buffer.from(TOKEN)))return res.status(401).json({error:"Неверный пароль загрузчика."});next();}
const storage=multer.diskStorage({destination:MEDIA,filename:(_req,file,cb)=>{const ext=path.extname(file.originalname).toLowerCase();cb(null,randomUUID()+ext);}});
const upload=multer({storage,limits:{fileSize:2*1024*1024*1024},fileFilter:(_req,file,cb)=>{const ok=new Set([".mp4",".webm",".mov"]);cb(ok.has(path.extname(file.originalname).toLowerCase())?null:new Error("Разрешены MP4, WebM и MOV."),ok);}});
app.get("/health",async(_req,res)=>res.json({ok:true,storage:"local-disk",persistent:process.env.DATA_DIR?true:false}));
app.use("/media",express.static(MEDIA,{fallthrough:false, maxAge:"1h",setHeaders:r=>r.setHeader("Access-Control-Allow-Origin","*")}));
app.get("/api/videos",async(_req,res)=>{const rows=await read();res.json(rows.map(({id,name,size,type,createdAt,url})=>({id,name,size,type,createdAt,url})));});
app.post("/api/upload",auth,upload.single("video"),async(req,res)=>{if(!req.file)return res.status(400).json({error:"Файл не получен."});const rows=await read();const item={id:path.basename(req.file.filename,path.extname(req.file.filename)),name:req.file.originalname,size:req.file.size,type:req.file.mimetype,createdAt:new Date().toISOString(),url:"/media/"+encodeURIComponent(req.file.filename)};rows.push(item);await write(rows);res.status(201).json(item);});
app.get("/api/playlist",async(_req,res)=>{const rows=await read();res.json({channel:"МУЛЬТИК ТВ",items:rows});});
app.delete("/api/videos/:id",auth,async(req,res)=>{const rows=await read();const item=rows.find(x=>x.id===req.params.id);if(!item)return res.sendStatus(404);await fs.rm(path.join(MEDIA,path.basename(item.url)),{force:true});await write(rows.filter(x=>x.id!==item.id));res.json({ok:true});});
app.use((err,_req,res,_next)=>{res.status(err.code==="LIMIT_FILE_SIZE"?413:400).json({error:err.message||"Ошибка загрузки."});});
app.listen(PORT,"0.0.0.0",()=>console.log("МУЛЬТИК ТВ лёгкое хранилище запущено на порту "+PORT));
