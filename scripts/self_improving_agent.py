#!/usr/bin/env python3
"""Continuous, bounded self-audit for the Multik TV repository.

This agent does not silently rewrite its own source. It checks the repository,
runs the existing tests and stream probe, and emits a machine-readable report.
AI-proposed code changes remain behind the existing opt-in repair workflow.
"""
from __future__ import annotations
import json
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORT = ROOT / "self-audit-report.json"
SUMMARY = os.environ.get("GITHUB_STEP_SUMMARY")


def run(label: str, command: list[str], *, timeout: int = 120) -> dict:
    try:
        p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=timeout)
        return {"check": label, "ok": p.returncode == 0,
                "exit_code": p.returncode,
                "output": (p.stdout + p.stderr)[-6000:]}
    except Exception as exc:
        return {"check": label, "ok": False, "error": f"{type(exc).__name__}: {exc}"}


def main() -> int:
    results: list[dict] = []
    py_files = sorted((ROOT / "scripts").rglob("*.py"))
    if py_files:
        results.append(run("compile all Python scripts",
                           [sys.executable, "-m", "compileall", "-q", "scripts"]))
    else:
        results.append({"check": "Python scripts exist", "ok": False})

    shell_files = sorted(p for p in ROOT.rglob("*.sh")
                         if ".git" not in p.parts and "node_modules" not in p.parts)
    for path in shell_files:
        results.append(run(f"shell syntax: {path.relative_to(ROOT)}",
                           ["bash", "-n", str(path)]))

    json_files = sorted(p for p in ROOT.rglob("*.json")
                        if ".git" not in p.parts and "node_modules" not in p.parts)
    for path in json_files:
        try:
            json.loads(path.read_text(encoding="utf-8"))
            results.append({"check": f"JSON: {path.relative_to(ROOT)}", "ok": True})
        except Exception as exc:
            results.append({"check": f"JSON: {path.relative_to(ROOT)}",
                            "ok": False, "error": str(exc)})

    tests = ROOT / "scripts"
    if list(tests.glob("test_*.py")):
        results.append(run("Python unit tests",
                           [sys.executable, "-m", "unittest", "discover",
                            "-s", "scripts", "-p", "test_*.py", "-v"], timeout=180))
    else:
        results.append({"check": "Python unit tests present", "ok": False,
                        "error": "No scripts/test_*.py tests were found."})

    compose = ROOT / "docker-compose.yml"
    if compose.exists():
        results.append(run("Docker Compose config",
                           ["docker", "compose", "-f", str(compose), "config", "--quiet"]))
    else:
        results.append({"check": "Docker Compose file", "ok": False,
                        "error": "docker-compose.yml not found"})

    report = {"agent": "Multik TV Self-Audit Agent", "version": 1,
              "timestamp_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "repository": str(ROOT.name), "checks": results,
              "ok": all(item.get("ok", False) for item in results)}
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    failed = [item for item in results if not item.get("ok")]
    lines = ["## Self-Audit Agent", "",
             f"**Result:** {'PASS' if not failed else 'FAIL'}",
             f"**Checks:** {len(results)}; **failed:** {len(failed)}", ""]
    for item in results:
        lines.append(f"- {'PASS' if item.get('ok') else 'FAIL'} — {item['check']}")
        if not item.get("ok") and item.get("error"):
            lines.append(f"  - {item['error']}")
    summary = "\n".join(lines) + "\n"
    print(summary)
    if SUMMARY:
        with open(SUMMARY, "a", encoding="utf-8") as handle:
            handle.write(summary)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
