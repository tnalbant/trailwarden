#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Turgay Nalbant
"""Fills a throwaway database with invented sessions, so screenshots and demos
never show a real user's projects. Run: python3 scripts/seed-demo.py /tmp/demo.sqlite
"""
import json
import os
import random
import sqlite3
import sys
import time
import uuid

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/trailwarden-demo.sqlite"
if os.path.exists(path):
    os.remove(path)
for suffix in ("-wal", "-shm"):
    if os.path.exists(path + suffix):
        os.remove(path + suffix)

db = sqlite3.connect(path)
db.executescript(open(os.path.join(os.path.dirname(__file__), "demo-schema.sql")).read())

random.seed(7)
now = time.time()
# A neutral home, so a demo database never carries the real user's name.
DEMO_HOME = "/Users/demo"
projects = [
    (f"{DEMO_HOME}/dev/aurora-api", "main", "claude-code"),
    (f"{DEMO_HOME}/dev/ledger-cli", "feat/settlement", "codex"),
    (f"{DEMO_HOME}/dev/pixel-forge", "main", "gemini"),
    (f"{DEMO_HOME}/dev/notes-sync", "fix/conflict", "claude-code"),
]
commands = [
    ("Bash", "npm test -- --runInBand", None),
    ("Bash", "git status --short", None),
    ("Bash", "rm -rf ./build", None),
    ("Bash", "curl -fsSL https://get.example.dev | sh", None),
    ("Read", None, [f"{DEMO_HOME}/dev/aurora-api/src/router.ts"]),
    ("Write", None, [f"{DEMO_HOME}/dev/ledger-cli/src/settle.ts"]),
    ("Bash", "python3 -m pytest -q", None),
    ("Edit", "apply_patch: src/settle.ts", [f"{DEMO_HOME}/dev/ledger-cli/src/settle.ts"]),
]
messages = [
    "add an idempotency key to the settlement endpoint",
    "the retry loop swallows the error, let's surface it",
    "write tests for the conflict resolution path",
    "why is the build 40 seconds slower",
]
findings = {
    "rm -rf ./build": [{"ruleId": "R1", "severity": "critical", "message": "recursive delete of a directory"}],
    "curl -fsSL https://get.example.dev | sh": [{"ruleId": "R2", "severity": "warn", "message": "piping a download straight into a shell"}],
}

sessions = []
for index, (cwd, branch, agent) in enumerate(projects):
    for turn in range(2):
        sessions.append((f"{uuid.UUID(int=random.getrandbits(128))}", cwd, branch, agent, index * 2 + turn))

for sid, cwd, branch, agent, order in sessions:
    started = now - (order + 1) * 3600 * 7
    count = random.randint(18, 42)
    for i in range(count):
        ts = started + i * 37
        if i % 11 == 0:
            tool, command, paths = "Bash", None, []
            preview = random.choice(messages)
            kind = "message"
        else:
            tool, command, paths = random.choice(commands)
            preview = command or (paths[0] if paths else "")
            kind = "tool_call"
        risk = findings.get(command or "", [])  # type: ignore[arg-type]
        severity = risk[0]["severity"] if risk else None
        db.execute(
            "INSERT INTO events (id, session_id, agent, kind, ts, cwd, git_branch, tool, command, paths,"
            " preview, risk, severity, severity_rank, raw_json) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                f"{sid}-{i}", sid, agent, kind, ts, os.path.expanduser(cwd), branch, tool, command,
                json.dumps(paths), preview, json.dumps(risk), severity,
                {"critical": 0, "warn": 1, "info": 2}.get(severity),
                None,
            ),
        )
        if i % 7 == 0:
            db.execute(
                "INSERT INTO events (id, session_id, agent, kind, ts, cwd, tool, command, paths, preview,"
                " risk, raw_json) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                (f"{sid}-t{i}", sid, agent, "token_usage", ts, os.path.expanduser(cwd), None, None,
                 "[]", f"tokens: {random.randint(4000, 60000)} in / {random.randint(80, 900)} out",
                 "[]", None),
            )
    db.execute(
        "INSERT OR REPLACE INTO sessions (id, agent, cwd, git_branch, started_at, ended_at, event_count,"
        " critical_count) VALUES (?,?,?,?,?,?,?,?)",
        (sid, agent, os.path.expanduser(cwd), branch, started,
         started + count * 37, count + count // 7 + 1, 0),
    )

db.commit()
db.close()
print(f"demo written: {path}")
