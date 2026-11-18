'use strict';
const fs=require('node:fs');
const path=require('node:path');
const FILE=process.env.LEARNING_FILE||path.join(__dirname,'data','learning.json');
function load(){try{return JSON.parse(fs.readFileSync(FILE,'utf8'));}catch{return {events:[],scores:{},updatedAt:null};}}
function save(d){fs.mkdirSync(path.dirname(FILE),{recursive:true});const t=FILE+'.tmp';fs.writeFileSync(t,JSON.stringify(d,null,2));fs.renameSync(t,FILE);}
function record(e){if(!e||typeof e.title!=='string'||!e.title.trim())throw Error('title required');const kind=['completed','skipped','liked'].includes(e.kind)?e.kind:'completed';const d=load(),k=e.title.trim().slice(0,120),s=d.scores[k]||{completed:0,skipped:0,liked:0,score:0};s[kind]++;s.score=s.completed+s.liked*3-s.skipped*2;d.scores[k]=s;d.events.push({title:k,kind,at:new Date().toISOString()});d.events=d.events.slice(-1000);d.updatedAt=new Date().toISOString();save(d);return {title:k,...s};}
function recommend(items){const d=load();if(!Array.isArray(items))throw Error('items must be an array');return items.filter(x=>x&&x.rightsCleared===true&&typeof x.title==='string').map(x=>({...x,learningScore:d.scores[x.title]?.score||0})).sort((a,b)=>b.learningScore-a.learningScore);}
function summary(){const d=load();return {updatedAt:d.updatedAt,titlesLearned:Object.keys(d.scores).length,eventsRecorded:d.events.length,scores:d.scores};}
module.exports={record,recommend,summary};