import json, os, sys, urllib.request, urllib.error, urllib.parse
BASE=os.getenv('STREAM_BASE_URL','https://multik-tv-test-stream-yltl.onrender.com').rstrip('/')
def get(url):
    req=urllib.request.Request(url,headers={'User-Agent':'MultikTV-AutoRepair/1.1','Cache-Control':'no-cache'})
    try:
        with urllib.request.urlopen(req,timeout=12) as r: return r.status,r.read(2000000)
    except urllib.error.HTTPError as e: return e.code,e.read(1000)
def parse_health(body):
    text=body.decode('utf-8-sig','replace').strip()
    decoder=json.JSONDecoder()
    obj, end=decoder.raw_decode(text)
    if not isinstance(obj,dict): raise ValueError('health response is not a JSON object')
    return obj, text[end:].strip()
def media_segments(url, depth=0, seen=None):
    if seen is None: seen=set()
    if depth>3 or url in seen: return [],[]
    seen.add(url)
    code,body=get(url)
    if code!=200: return [],[{'url':url,'http':code}]
    text=body.decode('utf-8-sig','replace')
    lines=[x.strip() for x in text.splitlines() if x.strip()]
    if not lines or lines[0]!='#EXTM3U': return [],[{'url':url,'error':'response is not an HLS playlist'}]
    variants=[]; segments=[]
    for i,line in enumerate(lines):
        if line.startswith('#EXT-X-STREAM-INF:') and i+1<len(lines) and not lines[i+1].startswith('#'): variants.append(lines[i+1])
        elif not line.startswith('#') and '.ts' in line.lower().split('?')[0]: segments.append(line)
    errors=[]
    if segments: return [urllib.parse.urljoin(url,x) for x in segments[-5:]],errors
    if variants:
        for variant in variants[:3]:
            found,err=media_segments(urllib.parse.urljoin(url,variant),depth+1,seen)
            errors.extend(err)
            if found: return found,errors
        return [],errors
    # A media playlist without TS segments may use fMP4/CMAF; report it explicitly.
    other=[x for x in lines if not x.startswith('#') and x.lower().split('?')[0].endswith(('.m4s','.mp4'))]
    if other: return [urllib.parse.urljoin(url,x) for x in other[-5:]],errors
    return [],[{'url':url,'error':'playlist contains no TS or fragmented-MP4 media entries'}]
def main():
    report={'base_url':BASE,'checks':[],'diagnosis':[]}
    try:
        code,body=get(BASE+'/broadcast/health.json'); report['checks'].append({'name':'health','http':code})
        if code!=200: report['diagnosis'].append('Health endpoint HTTP '+str(code))
        else:
            try:
                h,trailing=parse_health(body); report['health']=h
                if trailing: report['checks'].append({'health_trailing_bytes':len(trailing),'note':'Ignored trailing non-JSON output after first JSON object'})
                if h.get('status')!='live' or h.get('streaming') is not True: report['diagnosis'].append('Server health is not live: status='+repr(h.get('status'))+', streaming='+repr(h.get('streaming')))
            except Exception as e: report['diagnosis'].append('Health response cannot be parsed: '+str(e))
        playlist=BASE+'/live/multiktv.m3u8'
        found,errors=media_segments(playlist)
        report['checks'].append({'name':'hls_media_entries','found':len(found),'playlist_errors':errors})
        if not found: report['diagnosis'].append('No actual media segment entries found in HLS playlist chain')
        else:
            attempts=[]; playable=False
            for url in reversed(found):
                try: sc,sb=get(url)
                except Exception as e: sc,sb=0,str(e).encode()
                attempts.append({'url':url,'http':sc,'bytes':len(sb)})
                if sc==200 and len(sb)>=188: playable=True; break
            report['checks'].append({'name':'media_segment_download','attempts':attempts})
            if not playable: report['diagnosis'].append('Recent HLS media segments could not be downloaded')
    except Exception as e: report['diagnosis'].append(type(e).__name__+': '+str(e))
    report['ok']=not report['diagnosis']; print(json.dumps(report,ensure_ascii=False,indent=2))
    with open('stream-diagnosis.json','w',encoding='utf-8') as f: json.dump(report,f,ensure_ascii=False,indent=2)
    summary=os.getenv('GITHUB_STEP_SUMMARY','/tmp/stream-check.md')
    with open(summary,'a',encoding='utf-8') as f: f.write('## Runtime diagnosis\n\n```json\n'+json.dumps(report,ensure_ascii=False,indent=2)+'\n```\n')
    if not report['ok']: return 1
    print('STREAM_OK: health and actual HLS media segment passed'); return 0
if __name__=='__main__': sys.exit(main())