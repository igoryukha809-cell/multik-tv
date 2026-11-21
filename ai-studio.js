(()=>{'use strict';
const $=id=>document.getElementById(id);
document.querySelectorAll('.tab').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.tab').forEach(x=>x.classList.toggle('active',x===b));document.querySelectorAll('.tool').forEach(x=>x.classList.toggle('active',x.id==='tool-'+b.dataset.tab))}));
$('make-script').onclick=()=>{const title=$('story-title').value.trim()||'Новая история',heroes=$('story-heroes').value.trim()||'Герои',topic=$('story-topic').value.trim()||'Неожиданное приключение',place=$('story-place').value.trim()||'Сказочный мир';$('script-output').value=title+'\n\nСЦЕНА 1. '+place+'\n\nРассказчик: В '+place.toLowerCase()+' начинался новый день. '+heroes+' собрались вместе.\n\nГерой 1: Какой прекрасный день! Кажется, сегодня нас ждёт что-то необычное.\n\nГерой 2: Главное — держаться вместе и помогать друг другу!\n\nРассказчик: Вдруг друзья заметили необычное событие. '+topic+'.\n\nГерой 3: Посмотрите! Кажется, кому-то нужна наша помощь.\n\nГерой 1: Тогда отправляемся навстречу приключению!\n\nРассказчик: Так началась новая история о дружбе, смелости и взаимопомощи.\n\nКОНЕЦ СЦЕНЫ'};
$('make-board').onclick=()=>{const title=$('story-title').value.trim()||'Новая история',heroes=$('story-heroes').value.trim()||'Герои',topic=$('story-topic').value.trim()||'Неожиданное приключение',place=$('story-place').value.trim()||'Сказочный мир';const shots=[['Общий план','Показать '+place+'. Камера медленно приближается.','Установочный кадр, 4–5 секунд'],['Знакомство с героями','Показать '+heroes+', которые собираются вместе.','Средний план, плавное движение камеры, 4 секунды'],['Завязка','Герои замечают необычное событие: '+topic+'.','Крупный план удивлённых лиц, 3 секунды'],['Реакция','Один герой указывает на событие, остальные смотрят в ту сторону.','Чередование крупных планов, 4 секунды'],['Решение','Герои договариваются помочь и отправляются вместе.','Общий план, движение вслед за героями, 5 секунд'],['Финал сцены','Герои уходят навстречу приключению. Надпись: '+title+'.','Плавное затемнение, 3 секунды']];$('board-output').value='РАСКАДРОВКА: '+title+'\nМесто: '+place+'\nГерои: '+heroes+'\nТема: '+topic+'\n\n'+shots.map((s,i)=>(i+1)+'. '+s[0]+'\nДействие: '+s[1]+'\nПостановка: '+s[2]).join('\n\n')+'\n\nПримечание: это текстовый план кадров; готовые изображения и анимация не создаются.'};
async function copyField(id,buttonId){const el=$(id),b=$(buttonId);try{await navigator.clipboard.writeText(el.value);b.textContent='Скопировано!'}catch(e){el.select();document.execCommand('copy');b.textContent='Скопировано!'}}
$('copy-script').onclick=()=>copyField('script-output','copy-script');$('copy-board').onclick=()=>copyField('board-output','copy-board');
let currentAudio=null,currentAudioUrl=null,currentAbort=null;
function stopPiperAudio(){
 if(currentAbort){currentAbort.abort();currentAbort=null}
 if(currentAudio){currentAudio.pause();currentAudio.removeAttribute('src');currentAudio.load();currentAudio=null}
 if(currentAudioUrl){URL.revokeObjectURL(currentAudioUrl);currentAudioUrl=null}
}
$('speak').onclick=async()=>{
 const text=$('voice-text').value.trim(),status=$('voice-status'),button=$('speak');
 if(!text){status.textContent='Сначала введи текст для озвучки.';return}
 if(text.length>1200){status.textContent='Слишком длинный текст: максимум 1200 символов.';return}
 stopPiperAudio();
 currentAbort=new AbortController();button.disabled=true;
 status.textContent='Подключаю русский голос Piper и создаю аудио…';
 try{
  const response=await fetch('https://channel-voice-tts.onrender.com/api/tts',{
   method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({text}),signal:currentAbort.signal
  });
  if(!response.ok){let detail='HTTP '+response.status;try{const data=await response.json();if(data.detail)detail=data.detail}catch(e){}throw new Error(detail)}
  const blob=await response.blob();
  if(!blob.size||blob.type!=='audio/wav')throw new Error('Сервер вернул пустой или неверный WAV-файл.');
  currentAudioUrl=URL.createObjectURL(blob);currentAudio=new Audio(currentAudioUrl);
  currentAudio.onended=()=>{status.textContent='Озвучка Piper завершена.';stopPiperAudio()};
  currentAudio.onerror=()=>{status.textContent='Не удалось воспроизвести WAV-аудио.';stopPiperAudio()};
  await currentAudio.play();status.textContent='Идёт озвучка русским голосом Piper…';
 }catch(error){
  if(error.name==='AbortError'){status.textContent='Озвучка остановлена.'}
  else{status.textContent='Ошибка Piper: '+error.message+'. Проверь подключение к серверу.'}
 }finally{button.disabled=false;currentAbort=null}
};
$('stop-speech').onclick=()=>{stopPiperAudio();$('voice-status').textContent='Озвучка остановлена.'};
const c=$('art-canvas'),x=c.getContext('2d');
function star(cx,cy,r){x.beginPath();for(let i=0;i<10;i++){const a=-Math.PI/2+i*Math.PI/5,rr=i%2?r*.42:r;x.lineTo(cx+Math.cos(a)*rr,cy+Math.sin(a)*rr)}x.closePath();x.fill()}
function drawArt(){const theme=$('art-theme').value;x.clearRect(0,0,c.width,c.height);const g=x.createLinearGradient(0,0,0,c.height);g.addColorStop(0,theme==='cloud'?'#6bc7f5':'#5c39a6');g.addColorStop(1,theme==='forest'?'#1b754b':'#f19ac4');x.fillStyle=g;x.fillRect(0,0,1200,675);
if(theme==='rainbow'){for(let i=0;i<6;i++){x.beginPath();x.strokeStyle=['#ff5268','#ffb23f','#ffe45b','#65d68a','#54b8ff','#b88aff'][i];x.lineWidth=28;x.arc(600,560,300-i*28,Math.PI,Math.PI*2);x.stroke()}}
if(theme==='star'){x.fillStyle='#25144f';x.fillRect(0,0,1200,675);for(let i=0;i<55;i++){x.fillStyle='#fff6b0';x.beginPath();x.arc((i*193)%1200,(i*97)%600,2+(i%4),0,7);x.fill()}x.fillStyle='#ffe45e';star(600,310,170)}
if(theme==='forest'){x.fillStyle='#175c43';x.fillRect(0,430,1200,245);for(let i=0;i<9;i++){const px=70+i*140,py=430+(i%2)*45;x.fillStyle='#75452e';x.fillRect(px-12,py,24,180);x.fillStyle=['#2bb673','#23985d','#4ac77c'][i%3];x.beginPath();x.arc(px,py-35,75,0,7);x.fill()}}
if(theme==='cloud'){x.fillStyle='#f5fdff';for(let i=0;i<6;i++){const px=90+i*205,py=190+(i%2)*125;x.beginPath();x.arc(px,py,48,0,7);x.arc(px+48,py-18,64,0,7);x.arc(px+105,py,48,0,7);x.fill()}}
x.fillStyle='rgba(24,12,52,.58)';x.fillRect(0,560,1200,115);x.fillStyle='#fff';x.textAlign='center';x.font='bold 48px Arial';x.fillText($('art-title').value.slice(0,45)||'МУЛЬТИК ТВ',600,630)}
$('make-art').onclick=drawArt;$('save-art').onclick=()=>{drawArt();const a=document.createElement('a');a.download='multik-tv-illustration.png';a.href=c.toDataURL('image/png');a.click()};drawArt();
})();