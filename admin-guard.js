import LogtoClient from "https://cdn.jsdelivr.net/npm/@logto/browser@3.1.2/+esm";
import {LOGTO_ENDPOINT,LOGTO_APP_ID,LOGTO_API_RESOURCE} from "./logto-config.js";

const overlay=document.createElement("div");
overlay.style.cssText="position:fixed;inset:0;z-index:999999;background:#10162c;color:white;display:grid;place-items:center;padding:22px;font:16px system-ui;text-align:center";
overlay.innerHTML='<section style="max-width:480px;background:#1b2745;padding:28px;border-radius:20px"><h1>🔐 Раздел для администраторов</h1><p id="admin-msg">Проверяем права доступа…</p><p><a href="./login.html" style="color:#ffda73">Войти через защищённую страницу</a></p><p><a href="./index.html" style="color:#cbd5ee">На главную</a></p></section>';
document.body.append(overlay);
const message=overlay.querySelector("#admin-msg");
try{
 const client=new LogtoClient({endpoint:LOGTO_ENDPOINT,appId:LOGTO_APP_ID,resources:[LOGTO_API_RESOURCE],scopes:[]});
 if(!await client.isAuthenticated()){message.textContent="Для доступа войдите в учётную запись администратора.";throw new Error("AUTH_REQUIRED");}
 const token=await client.getAccessToken(LOGTO_API_RESOURCE);
 const userinfoToken=await client.getAccessToken();
 const response=await fetch(LOGTO_API_RESOURCE+"/api/admin/keys",{headers:{Authorization:"Bearer "+token,"X-Logto-Userinfo-Token":userinfoToken}});
 if(!response.ok){message.textContent=response.status===401||response.status===403?"У этой учётной записи нет прав администратора.":"Не удалось проверить права доступа.";throw new Error("ACCESS_DENIED");}
 overlay.remove();
}catch(error){
 if(error.message!=="AUTH_REQUIRED"&&error.message!=="ACCESS_DENIED")message.textContent="Не удалось проверить права через Logto. Повторите вход.";
}
