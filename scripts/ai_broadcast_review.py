#!/usr/bin/env python3
"""Optional AI review of a short, read-only HLS sample."""
import base64, json, os, subprocess, sys, tempfile, urllib.request
from datetime import datetime, timezone

URL=os.environ.get("STREAM_URL","https://multik-tv-test-stream-yltl.onrender.com/live/multiktv.m3u8")
API=os.environ.get("OPENAI_API_KEY")
VISION_MODEL=os.environ.get("OPENAI_VISION_MODEL","gpt-5.5")
TRANSCRIBE_MODEL=os.environ.get("OPENAI_TRANSCRIBE_MODEL","gpt-transcribe")
SECONDS=int(os.environ.get("AI_SAMPLE_SECONDS","20"))

def ffmpeg(args):
    return subprocess.run(["ffmpeg","-hide_banner","-nostdin","-loglevel","error","-y","-i",URL,*args],capture_output=True,timeout=50)

def api_json(path, payload):
    data=json.dumps(payload).encode()
    req=urllib.request.Request("https://api.openai.com/v1/"+path,data=data,headers={"Authorization":"Bearer "+API,"Content-Type":"application/json"})
    with urllib.request.urlopen(req,timeout=90) as r: return json.loads(r.read())

def transcribe(path):
    boundary="----BroadcastAIFormBoundary"
    chunks=[]
    def field(name,value,filename=None,ctype=None):
        head=f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\""
        if filename: head+=f"; filename=\"{filename}\""
        head+="\r\n"
        if ctype: head+=f"Content-Type: {ctype}\r\n"
        chunks.extend([head.encode(),b"\r\n",value if isinstance(value,bytes) else value.encode(),b"\r\n"])
    field("model",TRANSCRIBE_MODEL)
    field("file",open(path,"rb").read(),"sample.mp3","audio/mpeg")
    chunks.append(f"--{boundary}--\r\n".encode())
    req=urllib.request.Request("https://api.openai.com/v1/audio/transcriptions",data=b"".join(chunks),headers={"Authorization":"Bearer "+API,"Content-Type":"multipart/form-data; boundary="+boundary})
    with urllib.request.urlopen(req,timeout=90) as r: return json.loads(r.read()).get("text","")

def main():
    report={"checkedAt":datetime.now(timezone.utc).isoformat(),"url":URL,"readOnly":True,"aiEnabled":bool(API)}
    if not API:
        report["status"]="skipped"; report["reason"]="OPENAI_API_KEY secret is not configured"
        print(json.dumps(report,ensure_ascii=False,indent=2)); return 0
    with tempfile.TemporaryDirectory() as d:
        frame=os.path.join(d,"frame-%02d.jpg"); audio=os.path.join(d,"audio.mp3")
        v=ffmpeg(["-t",str(SECONDS),"-vf","fps=1/8,scale=768:-1","-frames:v","2",frame])
        a=ffmpeg(["-t",str(SECONDS),"-vn","-ac","1","-ar","16000","-b:a","48k",audio])
        frame_paths=sorted(os.path.join(d,name) for name in os.listdir(d) if name.startswith("frame-") and name.endswith(".jpg"))
        if v.returncode or not frame_paths: raise RuntimeError("Could not extract a video frame from HLS")
        images=[]
        for path in frame_paths:
            with open(path,"rb") as image_file:
                raw=image_file.read()
            images.append("data:image/jpeg;base64,"+base64.b64encode(raw).decode())
        transcript=""
        if a.returncode==0 and os.path.exists(audio) and os.path.getsize(audio)>1000:
            transcript=transcribe(audio)
        prompt = ("Ты — осторожный технический аналитик телевизионного эфира. По кадрам и расшифровке оцени только наблюдаемые признаки: что видно на экране, есть ли признаки чёрного/пустого кадра, соответствует ли звук содержанию, слышна ли речь/музыка/тишина, есть ли вероятный технический сбой. Не угадывай названия передач и людей. Если данных мало, так и напиши. Верни краткий JSON с полями summary, visual_findings, audio_findings, possible_issues, confidence. Расшифровка аудио: " + (transcript or "[аудио не удалось расшифровать]"))
        content=[{"type":"input_text","text":prompt}]
        content.extend([{"type":"input_image","image_url":im,"detail":"low"} for im in images])
        result=api_json("responses",{"model":VISION_MODEL,"store":False,"input":[{"role":"user","content":content}]})
        output=[]
        for item in result.get("output",[]):
            if item.get("type")=="message":
                output.extend(c.get("text","") for c in item.get("content",[]) if c.get("type")=="output_text")
        report.update({"status":"analyzed","transcript":transcript[:4000],"analysis":"\n".join(output),"model":VISION_MODEL,"transcriptionModel":TRANSCRIBE_MODEL,"sampleSeconds":SECONDS,"framesAnalyzed":len(images)})
    print(json.dumps(report,ensure_ascii=False,indent=2))
if __name__=="__main__":
    try: main()
    except Exception as e:
        print(json.dumps({"status":"error","readOnly":True,"error":str(e)[:800]},ensure_ascii=False)); sys.exit(1)
