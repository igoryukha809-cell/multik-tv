#!/usr/bin/env python3
"""Fetch official Karusel award and contest dates; preserve last good data on parse failures."""
import json, re, urllib.request, html
from html.parser import HTMLParser
from datetime import datetime, timezone

BASE = "https://www.karusel-tv.ru"
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; ChannelCalendarBot/1.0)"}

def fetch(url):
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")

class Text(HTMLParser):
    def __init__(self):
        super().__init__(); self.parts=[]
    def handle_data(self, data):
        s=data.strip()
        if s: self.parts.append(s)

def plain(source):
    p=Text(); p.feed(source)
    return " ".join(html.unescape(x) for x in p.parts)

def get_award():
    # Official announcements: initial voting announcement and finalist voting announcement.
    pages=["/news/9293","/news/9302","/news/9317"]
    bodies=[]
    for path in pages:
        try: bodies.append((BASE+path,plain(fetch(BASE+path))))
        except Exception: continue
    if not bodies: raise RuntimeError("Не удалось получить официальные новости о премии")
    year=datetime.now(timezone.utc).year
    for url,body in bodies:
        m=re.search(r"Главные Герои\s*[—–-]\s*(20\d{2})",body)
        if m: year=max(year,int(m.group(1)))
    months={"января":"01","февраля":"02","марта":"03","апреля":"04","мая":"05","июня":"06","июля":"07","августа":"08","сентября":"09","октября":"10","ноября":"11","декабря":"12"}
    dates={}
    def find(pattern,key,body,month):
        m=re.search(pattern,body,re.I)
        if m:
            day = next((group for group in m.groups() if group is not None), None)
            if day is not None:
                dates[key]=f"{year}-{months[month]}-{int(day):02d}"
    for url,body in bodies:
        find(r"до\s+(\d{1,2})\s+августа","applications_end",body,"августа")
        find(r"с\s+(\d{1,2})\s+августа[^.]{0,100}?до\s+\d{1,2}\s+сентября","first_round_start",body,"августа")
        find(r"до\s+(\d{1,2})\s+сентября","first_round_end",body,"сентября")
        find(r"до\s+(\d{1,2})\s+октября","final_round_end",body,"октября")
        find(r"(?:состоится|прошли|прошла)[^.!]{0,120}?(\d{1,2})\s+октября","ceremony",body,"октября")
        find(r"(?:(4)\s+ноября|в эфире[^.!]{0,120}?(\d{1,2})\s+ноября)","broadcast",body,"ноября")
    if not dates: raise RuntimeError("В официальных новостях не распознаны даты премии")
    source=next((u for u,b in bodies if "9293" in u),bodies[0][0])
    return {"year":year,"source":source,"dates":dates}

def get_contests():
    contest_base = "https://free.karusel-tv.ru"
    page = fetch(contest_base + "/contest")
    text = plain(page)
    titles = ("Путешествие в подводный мир", "Нарисуй, где спрятался Турбозавр")
    months = {"января":"01","февраля":"02","марта":"03","апреля":"04","мая":"05","июня":"06","июля":"07","августа":"08","сентября":"09","октября":"10","ноября":"11","декабря":"12"}
    items = []
    current_year = datetime.now(timezone.utc).year
    for title in titles:
        pos = text.find(title)
        if pos < 0:
            continue
        snippet = text[pos:pos + 220]
        m = re.search(r"[сc]\s+(\d{1,2})\s+([а-яё]+)\s+по\s+(\d{1,2})\s+([а-яё]+)(?:\s+(20\d{2}))?", snippet, re.I)
        if not m:
            continue
        try:
            start_month = months[m.group(2).lower()]
            end_month = months[m.group(4).lower()]
            year = int(m.group(5) or current_year)
            start = f"{year}-{start_month}-{int(m.group(1)):02d}"
            end_year = year + (1 if int(end_month) < int(start_month) else 0)
            end = f"{end_year}-{end_month}-{int(m.group(3)):02d}"
        except (KeyError, ValueError):
            continue
        slug = "podvodniy_mir" if title == titles[0] else "turbozavry"
        items.append({"title": title, "start": start, "end": end, "url": contest_base + "/contest/" + slug})
    if not items:
        raise RuntimeError("Не удалось распознать даты конкурсов на официальной странице; предыдущие данные не перезаписываются")
    return items

def main():
    data={"checkedAt":datetime.now(timezone.utc).isoformat(),"source":"Официальный сайт телеканала «Карусель»","award":get_award(),"contests":get_contests()}
    with open("broadcast/karusel-calendar.json","w",encoding="utf-8") as f:
        json.dump(data,f,ensure_ascii=False,indent=2)
    print("Calendar updated:",len(data["contests"]),"contests; award year",data["award"]["year"])
if __name__=="__main__": main()
