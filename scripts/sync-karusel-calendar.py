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
    index=fetch(BASE+"/news/event")
    candidates=re.findall(r'href=["\']([^"\']*/news/\d+[^"\']*)["\'][^>]*>(.*?)</a>', index, re.I|re.S)
    url=None
    for href, label in candidates:
        title=plain(label)
        if "Главные Герои" in title:
            url=href if href.startswith("http") else BASE+href
            break
    # Known official archive fallback: the index can change markup.
    if not url:
        for page in ("/news/9302","/news/9317"):
            body=fetch(BASE+page)
            if "Главные Герои" in body:
                url=BASE+page; break
    if not url: raise RuntimeError("Не найдена официальная новость о премии")
    body=plain(fetch(url))
    dates={}
    patterns={
      "first_round_end": r"до\s+(\d{1,2})\s+([а-яё]+)",
      "final_round_end": r"до\s+(\d{1,2})\s+октября",
      "ceremony": r"(\d{1,2})\s+октября",
      "broadcast": r"(\d{1,2})\s+ноября"
    }
    months={"января":"01","февраля":"02","марта":"03","апреля":"04","мая":"05","июня":"06","июля":"07","августа":"08","сентября":"09","октября":"10","ноября":"11","декабря":"12"}
    def iso(d,m,y):
        return f"{y}-{months[m]}-{int(d):02d}"
    year_match=re.search(r"Главные Герои\s*[—–-]\s*(20\d{2})", body)
    year=int(year_match.group(1)) if year_match else datetime.now(timezone.utc).year
    m=re.search(r"до\s+(\d{1,2})\s+сентября",body,re.I)
    if m: dates["first_round_end"]=iso(m.group(1),"сентября",year)
    m=re.search(r"до\s+(\d{1,2})\s+октября",body,re.I)
    if m: dates["final_round_end"]=iso(m.group(1),"октября",year)
    m=re.search(r"(?:состоится|прошли|прошла)[^.!]{0,100}?(\d{1,2})\s+октября",body,re.I)
    if m: dates["ceremony"]=iso(m.group(1),"октября",year)
    m=re.search(r"(?:4 ноября|в эфире[^.!]{0,100}?(\d{1,2})\s+ноября)",body,re.I)
    if m:
        day=m.group(1) or "4"; dates["broadcast"]=iso(day,"ноября",year)
    if not dates: raise RuntimeError("В новости не распознаны даты премии")
    return {"year":year,"source":url,"dates":dates}

def get_contests():
    page=fetch(BASE+"/contest")
    # Extract links to contest rules/details and date ranges from nearby visible text.
    links=re.findall(r'href=["\']([^"\']*/contest/[^"\']+)["\'][^>]*>(.*?)</a>',page,re.I|re.S)
    items=[]; seen=set()
    for href,label in links:
        title=plain(label)
        if not title or href in seen: continue
        seen.add(href)
        m=re.search(r"с\s+(\d{1,2})\s+([а-яё]+)\s+по\s+(\d{1,2})\s+([а-яё]+)(?:\s+(20\d{2})\s*г?\.?)?",title,re.I)
        if not m: continue
        months={"января":"01","февраля":"02","марта":"03","апреля":"04","мая":"05","июня":"06","июля":"07","августа":"08","сентября":"09","октября":"10","ноября":"11","декабря":"12"}
        year=int(m.group(5) or datetime.now(timezone.utc).year)
        try:
            start=f"{year}-{months[m.group(2).lower()]}-{int(m.group(1)):02d}"
            endyear=year+(1 if months[m.group(4).lower()] < months[m.group(2).lower()] else 0)
            end=f"{endyear}-{months[m.group(4).lower()]}-{int(m.group(3)):02d}"
        except KeyError: continue
        items.append({"title":title,"start":start,"end":end,"url":href if href.startswith("http") else BASE+href})
    # If active listing markup changes, keep the known current official list via strict textual extraction.
    if not items:
        text=plain(page)
        for title in ("Путешествие в подводный мир","Нарисуй, где спрятался Турбозавр"):
            pos=text.find(title)
            if pos<0: continue
            snippet=text[pos:pos+180]
            m=re.search(r"с\s+(\d{1,2})\s+([а-яё]+)\s+по\s+(\d{1,2})\s+([а-яё]+)(?:\s+(20\d{2}))?",snippet,re.I)
            if m:
                months={"января":"01","февраля":"02","марта":"03","апреля":"04","мая":"05","июня":"06","июля":"07","августа":"08","сентября":"09","октября":"10","ноября":"11","декабря":"12"}
                y=int(m.group(5) or datetime.now(timezone.utc).year)
                items.append({"title":title,"start":f"{y}-{months[m.group(2).lower()]}-{int(m.group(1)):02d}","end":f"{y}-{months[m.group(4).lower()]}-{int(m.group(3)):02d}","url":BASE+"/contest"})
    if not items: raise RuntimeError("Не удалось распознать даты конкурсов; предыдущие данные не перезаписываются")
    return items

def main():
    data={"checkedAt":datetime.now(timezone.utc).isoformat(),"source":"Официальный сайт телеканала «Карусель»","award":get_award(),"contests":get_contests()}
    with open("broadcast/karusel-calendar.json","w",encoding="utf-8") as f:
        json.dump(data,f,ensure_ascii=False,indent=2)
    print("Calendar updated:",len(data["contests"]),"contests; award year",data["award"]["year"])
if __name__=="__main__": main()
