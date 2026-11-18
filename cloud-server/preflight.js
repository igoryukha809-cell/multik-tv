'use strict';
const fs=require('node:fs'),path=require('node:path');
const MEDIA=path.resolve(process.env.MEDIA_DIR||'./media');
const SCHEDULE=path.resolve(process.env.SCHEDULE_FILE||'./schedule.json');
let errors=0,warnings=0;
function fail(message){console.error('ERROR:',message);errors++;}
function warn(message){console.warn('WARNING:',message);warnings++;}
let doc;
try{doc=JSON.parse(fs.readFileSync(SCHEDULE,'utf8'));}catch(e){fail('Cannot read/parse schedule '+SCHEDULE+': '+e.message);doc=null;}
if(doc){
 if(!Array.isArray(doc.items)||doc.items.length===0)fail('schedule.items must be a non-empty array.');
 else{
  const seen=new Set();
  for(const [i,item] of doc.items.entries()){
   const tag='items['+i+']';
   if(!item||typeof item!=='object'){fail(tag+' must be an object.');continue;}
   if(typeof item.title!=='string'||!item.title.trim())warn(tag+' has no title.');
   if(item.rightsCleared!==true){fail(tag+' is not explicitly marked rightsCleared:true. Do not air it until public-broadcast rights are confirmed.');continue;}
   if(typeof item.file!=='string'||!/^[\w .()-]{1,180}$/.test(item.file)){fail(tag+' has an invalid filename. Use a simple filename without folders.');continue;}
   if(seen.has(item.file))warn(tag+' duplicates '+item.file+'.');
   seen.add(item.file);
   const full=path.resolve(MEDIA,item.file);
   if(!full.startsWith(MEDIA+path.sep)){fail(tag+' escapes the media directory.');continue;}
   try{const st=fs.statSync(full);if(!st.isFile())fail(tag+' is not a regular file: '+item.file);else if(st.size===0)fail(tag+' is empty: '+item.file);else console.log('OK:',item.file,'('+st.size+' bytes)');}
   catch{fail(tag+' file is missing from '+MEDIA+': '+item.file);}
  }
 }
}
console.log('\nPreflight:',errors?'FAILED':'PASSED','| errors:',errors,'| warnings:',warnings);
process.exitCode=errors?1:0;
