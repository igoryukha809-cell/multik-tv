import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./admin-config.js";
const locked = SUPABASE_URL.includes("YOUR_PROJECT") || SUPABASE_ANON_KEY.includes("YOUR_SUPABASE");
const overlay = document.createElement("div");
overlay.style.cssText="position:fixed;inset:0;z-index:999999;background:#10162c;color:white;display:grid;place-items:center;padding:22px;font:16px system-ui;text-align:center";
overlay.innerHTML='<section style="max-width:480px;background:#1b2745;padding:28px;border-radius:20px"><h1>🔐 Раздел для администраторов</h1><p id="admin-msg">Проверяем права доступа…</p><p><a href="./login.html" style="color:#ffda73">Войти по электронной почте</a></p><p><a href="./index.html" style="color:#cbd5ee">На главную</a></p></section>';
document.body.append(overlay);
async function deny(message){overlay.querySelector("#admin-msg").textContent=message;}
if(locked){deny("Вход ещё не настроен. Владелец сайта должен подключить Supabase по инструкции admin-setup.md.");}
else{
 try{
  const supabase=createClient(SUPABASE_URL,SUPABASE_ANON_KEY);
  const {data:{session}}=await supabase.auth.getSession();
  if(!session){deny("Для доступа войдите в учётную запись администратора.");}
  else{
   const {data,error}=await supabase.from("admin_users").select("user_id").eq("user_id",session.user.id).maybeSingle();
   if(error||!data){deny("У этой учётной записи нет прав администратора.");}
   else{overlay.remove();}
  }
 }catch(e){deny("Не удалось проверить права. Проверьте настройки Supabase и подключение к интернету.");}
}
