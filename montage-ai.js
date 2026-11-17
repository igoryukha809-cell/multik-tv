'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));

  function analyzePixels(source) {
    const c = document.createElement('canvas');
    c.width = 96; c.height = 54;
    const x = c.getContext('2d', { willReadFrequently: true });
    const sw = source.videoWidth || source.naturalWidth || 1;
    const sh = source.videoHeight || source.naturalHeight || 1;
    const scale = Math.max(c.width / sw, c.height / sh);
    x.drawImage(source, (c.width - sw * scale) / 2, (c.height - sh * scale) / 2, sw * scale, sh * scale);
    const d = x.getImageData(0, 0, c.width, c.height).data;
    let r=0,g=0,b=0,bright=0,sat=0,edges=0,count=0;
    const gray = new Float32Array(c.width*c.height);
    for(let yy=0;yy<c.height;yy++) for(let xx=0;xx<c.width;xx++){
      const i=(yy*c.width+xx)*4, rr=d[i],gg=d[i+1],bb=d[i+2];
      r+=rr;g+=gg;b+=bb;
      const hi=Math.max(rr,gg,bb),lo=Math.min(rr,gg,bb);
      bright+=(rr*.299+gg*.587+bb*.114)/255;
      sat+=(hi-lo)/Math.max(1,hi);
      gray[yy*c.width+xx]=(rr*.299+gg*.587+bb*.114)/255;
      count++;
    }
    for(let yy=1;yy<c.height-1;yy++) for(let xx=1;xx<c.width-1;xx++){
      const i=yy*c.width+xx;
      edges+=Math.abs(gray[i+1]-gray[i-1])+Math.abs(gray[i+c.width]-gray[i-c.width]);
    }
    return {
      brightness:bright/count,
      saturation:sat/count,
      edge:edges/((c.width-2)*(c.height-2)),
      red:r/count,green:g/count,blue:b/count
    };
  }
  function describe(f){
    const tags=[];
    if(f.brightness>.72) tags.push('яркий кадр');
    else if(f.brightness<.25) tags.push('тёмный кадр');
    else tags.push('средняя освещённость');
    if(f.saturation>.48) tags.push('насыщенные цвета');
    else if(f.saturation<.16) tags.push('спокойные цвета');
    if(f.edge>.22) tags.push('много мелких деталей');
    else if(f.edge<.09) tags.push('простая композиция');
    const dominant=[['красный',f.red],['зелёный',f.green],['синий',f.blue]].sort((a,b)=>b[1]-a[1])[0][0];
    tags.push('преобладает '+dominant+' оттенок');
    return tags;
  }
  function score(f){
    return Math.round(clamp((f.saturation*.35+f.edge*.9+(1-Math.abs(f.brightness-.55))*.25)*100,0,100));
  }
  async function seek(video,time){
    await new Promise(resolve=>{
      let done=false;
      const finish=()=>{if(done)return;done=true;video.removeEventListener('seeked',finish);resolve()};
      video.addEventListener('seeked',finish,{once:true});
      video.currentTime=clamp(time,0,Math.max(0,(video.duration||1)-.05));
      setTimeout(finish,1800);
    });
  }
  async function analyze(asset){
    if(asset.type==='image'){
      const img=new Image();img.src=asset.url;
      if(img.decode) await img.decode(); else await new Promise((ok,bad)=>{img.onload=ok;img.onerror=bad});
      return [analyzePixels(img)];
    }
    const v=asset.el, duration=Number.isFinite(v.duration)?v.duration:0;
    const times=duration>2?[duration*.2,duration*.5,duration*.8]:[0];
    const out=[];
    for(const t of times){await seek(v,t);if(v.readyState>=2)out.push(analyzePixels(v))}
    v.pause();v.currentTime=0;
    return out;
  }
  async function run(){
    const assets=window.multikAssets||[];
    const button=$('aiBtn'),root=$('aiResults');
    if(!assets.length){root.textContent='Сначала добавь видео или изображения.';return}
    button.disabled=true;root.replaceChildren();
    const heading=document.createElement('strong');
    heading.textContent='Бесплатный локальный анализ кадров';root.append(heading);
    try{
      for(let i=0;i<assets.length;i++){
        const asset=assets[i];
        $('status').textContent='Анализирую '+(i+1)+' из '+assets.length+': '+asset.name;
        const frames=await analyze(asset);
        const block=document.createElement('div');block.className='ai-item';
        const name=document.createElement('strong');name.textContent=asset.name;block.append(name);
        if(!frames.length){block.append(document.createTextNode(' — кадры недоступны'));root.append(block);continue}
        frames.forEach((f,n)=>{
          const p=document.createElement('p');
          p.textContent=(frames.length>1?'Кадр '+(n+1)+': ':'')+describe(f).join(' · ')+'. Оценка визуальной выразительности: '+score(f)+'/100.';
          block.append(p);
        });
        root.append(block);
      }
      $('status').textContent='Анализ завершён. Всё обработано прямо в браузере; интернет и платные API не использовались.';
    }catch(error){
      root.textContent='Не удалось проанализировать материал: '+(error?.message||error);
      $('status').textContent='Ошибка анализа.';
    }finally{button.disabled=false}
  }
  $('aiBtn').addEventListener('click',run);
})();