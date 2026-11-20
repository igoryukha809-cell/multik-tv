import json, os, sys, urllib.request, urllib.error, urllib.parse
BASE=os.getenv('STREAM_BASE_URL','https://multik-tv-test-stream-yltl.onrender.com').rstrip('/')
def get(url):
    req=urllib.request.Request(url,headers={'User-Agent':'MultikTV-AutoRepair/1.0'})
    try:
        with urllib.request.urlopen(req,timeout=12) as r: return r.status,r.read(2000000)
    except urllib.error.HTTPError as e: return e.code,e.read(1000)
def main():
    report={'base_url':BASE,'checks':[],'diagnosis':[]}
    try:
        code,body=get(BASE+'/broadcast/health.json'); report['checks'].append({'health_http':code})
        if code!=200: report['diagnosis'].append('Health endpoint HTTP '+str(code))
        else:
            try:
                h=json.loads(body.decode()); report['health']=h
                if h.get('status')!='live' or h.get('streaming') is not True: report['diagnosis'].append('Server health is not live: '+str(h))
            except Exception as e: report['diagnosis'].append('Invalid health JSON: '+str(e))
        code,body=get(BASE+'/live/multiktv.m3u8'); report['checks'].append({'playlist_http':code})
        if code!=200: report['diagnosis'].append('HLS playlist HTTP '+str(code))
        else:
            lines=[x.strip() for x in body.decode('utf-8','replace').splitlines() if x.strip() and not x.startswith('#')]
            if not lines: report['diagnosis'].append('HLS playlist has no media segments')
            else:
                url=urllib.parse.urljoin(BASE+'/live/multiktv.m3u8',lines[-1]); sc,sb=get(url)
                report['checks'].append({'latest_segment_http':sc,'bytes':len(sb)})
                if sc!=200 or len(sb)<188: report['diagnosis'].append('Latest HLS segment unavailable or too small')
    except Exception as e: report['diagnosis'].append(type(e).__name__+': '+str(e))
    report['ok']=not report['diagnosis']; print(json.dumps(report,ensure_ascii=False,indent=2))
    if not report['ok']:
        key=os.getenv('RENDER_API_KEY'); sid=os.getenv('RENDER_SERVICE_ID')
        action='not requested: RENDER_API_KEY is not configured'
        if key and sid:
            req=urllib.request.Request('https://api.render.com/v1/services/'+sid+'/deploys',data=b'{"clearCache":false}',headers={'Authorization':'Bearer '+key,'Content-Type':'application/json'},method='POST')
            try:
                with urllib.request.urlopen(req,timeout=20) as r: action='redeploy requested: '+r.read().decode()
            except Exception as e: action='redeploy failed: '+str(e)
        print('RECOVERY: '+action)
        summary=os.getenv('GITHUB_STEP_SUMMARY','/tmp/stream-check.md')
        with open(summary,'a',encoding='utf-8') as f: f.write('## Runtime diagnosis\n\n```json\n'+json.dumps(report,ensure_ascii=False,indent=2)+'\n```\n\n'+action+'\n')
        return 1
    print('STREAM_OK: health, HLS and latest segment passed'); return 0
if __name__=='__main__': sys.exit(main())