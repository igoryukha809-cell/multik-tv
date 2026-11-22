#!/usr/bin/env python3
"""Conservative triage agent: turns monitor findings into one deduplicated GitHub issue.
It never edits source code, deploys, restarts, or controls the live stream.
"""
import json, os, sys, urllib.request, urllib.error

API = "https://api.github.com"
TOKEN = os.environ.get("GITHUB_TOKEN")
REPO = os.environ.get("GITHUB_REPOSITORY")
REPORTS = ["/tmp/broadcast-report.json", "/tmp/broadcast-ai-report.json"]
MARKER = "<!-- broadcast-agent-triage -->"

def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return None

def request(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": "Bearer " + TOKEN,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
        "User-Agent": "Broadcast-Triage-Agent/1.0",
    })
    with urllib.request.urlopen(req, timeout=20) as response:
        raw = response.read()
        return json.loads(raw) if raw else {}

def main():
    if not TOKEN or not REPO:
        print("Triage skipped: GitHub Actions token/repository context unavailable.")
        return 0
    signal = load(REPORTS[0])
    ai = load(REPORTS[1])
    findings = (signal or {}).get("findings", [])
    problems = [f for f in findings if f.get("severity") in ("critical", "warning")]
    if signal is None:
        problems.append({"severity":"warning","code":"SIGNAL_REPORT_MISSING","message":"Signal diagnostic report was not produced."})
    if ai and ai.get("status") == "error":
        problems.append({"severity":"warning","code":"AI_REVIEW_FAILED","message":ai.get("error","AI review failed")})
    if not problems:
        print("Agent triage: no actionable findings; no issue created.")
        return 0

    summary = "\n".join(
        "- **{severity} — {code}:** {message}".format(
            severity=p.get("severity","warning").upper(),
            code=p.get("code","UNKNOWN"),
            message=str(p.get("message",""))[:500],
        ) for p in problems
    )
    checked = (signal or ai or {}).get("checkedAt", "unknown")
    title = "[Broadcast monitor] Review required"
    body = (
        MARKER + "\n"
        "Автоматический монитор обнаружил признаки, требующие проверки. "
        "Это диагностическое сообщение, а не подтверждение неисправности.\n\n"
        f"**Время проверки:** {checked}\n\n{summary}\n\n"
        "Агент работает в режиме только чтения: он не меняет код, не перезапускает "
        "сервер и не управляет эфиром. Проверьте отчёт GitHub Actions и сам эфир. "
        "Закройте issue после проверки; повторные события будут добавлены комментарием."
    )
    issues = request("GET", f"/repos/{REPO}/issues?state=open&per_page=100")
    existing = next((i for i in issues if MARKER in (i.get("body") or "") and not i.get("pull_request")), None)
    if existing:
        request("POST", f"/repos/{REPO}/issues/{existing['number']}/comments", {"body": f"Новое обнаружение ({checked}):\n\n{summary}"})
        print(f"Updated existing triage issue #{existing['number']}.")
    else:
        created = request("POST", f"/repos/{REPO}/issues", {"title":title,"body":body,"labels":["bug"]})
        print(f"Created triage issue #{created.get('number')}.")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"Triage agent error: {str(exc)[:500]}", file=sys.stderr)
        sys.exit(1)
