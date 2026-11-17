import { pipeline, env } from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.2';
env.allowLocalModels = false;
let classifierPromise;
const $ = id => document.getElementById(id);
const wait = ms => new Promise(r => setTimeout(r, ms));
async function getClassifier() {
  if (!classifierPromise) {
    $('aiResults').textContent = 'Загружаю библиотеку и модель распознавания… При первом запуске потребуется интернет.';
    classifierPromise = pipeline('image-classification', 'onnx-community/mobilenet_v2_1.0_224', { dtype: 'q8' });
  }
  return classifierPromise;
}
function seek(video, time) {
  return new Promise(resolve => {
    let done = false;
    const finish = () => { if (done) return; done = true; video.removeEventListener('seeked', finish); resolve(); };
    video.addEventListener('seeked', finish, { once: true });
    video.currentTime = Math.max(0, Math.min(time, Math.max(0, (video.duration || 1) - 0.05)));
    setTimeout(finish, 2500);
  });
}
async function classifyAsset(classifier, asset) {
  const shots = [];
  if (asset.type === 'image') {
    const img = new Image(); img.src = asset.url;
    await (img.decode ? img.decode() : new Promise((ok, bad) => { img.onload=ok; img.onerror=bad; }));
    shots.push(img);
  } else {
    const video = asset.el;
    const duration = Number.isFinite(video.duration) ? video.duration : 0;
    const times = duration > 1 ? [duration * 0.2, duration * 0.5, duration * 0.8] : [0];
    const c = document.createElement('canvas'); c.width=224; c.height=224;
    const x = c.getContext('2d');
    for (const t of times) {
      await seek(video, t);
      if (video.readyState < 2) continue;
      const scale = Math.max(224/video.videoWidth, 224/video.videoHeight);
      const w=video.videoWidth*scale,h=video.videoHeight*scale;
      x.clearRect(0,0,224,224); x.drawImage(video,(224-w)/2,(224-h)/2,w,h);
      shots.push(c.toDataURL('image/jpeg',0.82));
    }
    video.pause(); video.currentTime=0;
  }
  const results=[];
  for (const shot of shots) {
    const output = await classifier(shot, { top_k: 3 });
    results.push(output.slice(0,3));
  }
  return results;
}
async function runAI() {
  const assets = window.multikAssets || [];
  if (!assets.length) { $('aiResults').textContent='Сначала добавь видео или изображения.'; return; }
  const button=$('aiBtn'); button.disabled=true;
  const root=$('aiResults'); root.replaceChildren();
  const heading=document.createElement('strong'); heading.textContent='Результаты распознавания кадров'; root.append(heading);
  try {
    const classifier=await getClassifier();
    for (let i=0;i<assets.length;i++) {
      const asset=assets[i];
      $('status').textContent='ИИ изучает материал '+(i+1)+' из '+assets.length+': '+asset.name;
      const result=await classifyAsset(classifier,asset);
      const block=document.createElement('div'); block.className='ai-item';
      const name=document.createElement('strong'); name.textContent=asset.name; block.append(name);
      if (!result.length) { block.append(document.createTextNode(' — не удалось получить кадр')); }
      result.forEach((shot,n)=>{
        const p=document.createElement('p');
        p.textContent=(result.length>1?'Кадр '+(n+1)+': ':'')+shot.map(x=>x.label+' ('+Math.round(x.score*100)+'%)').join(' · ');
        block.append(p);
      });
      root.append(block);
    }
    $('status').textContent='ИИ-анализ завершён. Подписи — предположения модели, возможны ошибки.';
  } catch (error) {
    root.textContent='Не удалось запустить ИИ-анализ: '+(error?.message || error)+'. Проверь интернет и попробуй обновить страницу.';
    $('status').textContent='Ошибка загрузки или работы модели.';
    classifierPromise=null;
  } finally { button.disabled=false; }
}
$('aiBtn').addEventListener('click', runAI);
