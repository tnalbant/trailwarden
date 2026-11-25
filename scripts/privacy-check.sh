#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Turgay Nalbant
#
# Privacy gate: nothing that identifies the machine a release was made on may
# reach the repository, its history or a shipped file. Exits non-zero on any
# finding and prints where, what and how many times.
#
#   scripts/privacy-check.sh                    # tree + history + .build/release
#   scripts/privacy-check.sh --tree --history   # what CI runs on every push
#   scripts/privacy-check.sh --build            # every Mach-O under .build/release/
#   scripts/privacy-check.sh --artifacts FILE…  # DMG, tar.gz, npm .tgz or a folder
#
# The generic rules live here. Anything that would itself be private — the
# names of other projects, a real name, an address — goes in a local list that
# git never tracks, one literal term per line (# starts a comment):
#
#   .git/info/privacy-denylist        (or the file named by $PRIVACY_DENYLIST)
#
# Outside CI the gate also adds the account name, the host and computer names,
# the serial number and the LAN addresses of the machine it runs on, read at
# run time and never written down. Binaries are read as bytes, never through
# `strings`, which hides most of what a Mach-O carries.
#
# In CI (CI is set) matched values are masked so the log does not repeat them;
# a secret is never printed anywhere, only its rule and length.

set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 -I - "$@" <<'PY'
import os, re, subprocess, sys, tarfile, tempfile, zipfile, shutil
from collections import defaultdict

ARGS = sys.argv[1:]
IN_CI = bool(os.environ.get("CI"))

def usage(code):
    print(__doc__ or "usage: scripts/privacy-check.sh [--tree] [--history] [--build] [--artifacts PATH...]",
          file=sys.stderr)
    sys.exit(code)

want = {"tree": False, "history": False, "build": False}
artifacts = []
mode = None
for a in ARGS:
    if a in ("--tree", "--history", "--build"):
        want[a[2:]] = True; mode = None
    elif a == "--artifacts":
        mode = "artifacts"
    elif a in ("-h", "--help"):
        print("usage: scripts/privacy-check.sh [--tree] [--history] [--build] [--artifacts PATH...]")
        sys.exit(0)
    elif mode == "artifacts":
        artifacts.append(a)
    else:
        print(f"unknown argument: {a}", file=sys.stderr); sys.exit(2)
if not any(want.values()) and not artifacts:
    want = {"tree": True, "history": True, "build": True}

def run(*cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)

# ---------------------------------------------------------------- rules
NAME = rb"[A-Za-z0-9._-]+"
# kind: "path" (shown), "secret" (never shown), "trace" (shown)
RULES = [
    ("home-path-macos", "path", re.compile(rb"/Users/(?!demo(?![A-Za-z0-9_-]))" + NAME)),
    # Claude Code names project folders after the path: -Users-<name>-repo.
    ("home-path-encoded", "path", re.compile(rb"-Users-(?!demo-)[A-Za-z0-9._]+-")),
    ("home-path-linux", "path", re.compile(rb"/home/(?!demo(?![A-Za-z0-9_-]))" + NAME)),
    ("home-path-windows", "path", re.compile(rb"[A-Za-z]:(?:\\\\|\\)Users(?:\\\\|\\)(?!demo\b)" + NAME)),
    ("email", "path", re.compile(rb"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")),
    ("lan-ip", "path", re.compile(rb"(?<![\d.])(?:192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}(?![\d.])")),
    ("token-openai-anthropic", "secret", re.compile(rb"sk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}")),
    ("token-github", "secret", re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})")),
    ("token-aws", "secret", re.compile(rb"(?:AKIA|ASIA)[0-9A-Z]{16}")),
    ("token-slack", "secret", re.compile(rb"xox[abposr]-[A-Za-z0-9-]{10,}")),
    ("token-google", "secret", re.compile(rb"AIza[0-9A-Za-z_-]{35}")),
    ("token-npm", "secret", re.compile(rb"npm_[A-Za-z0-9]{36}")),
    ("private-key", "secret", re.compile(rb"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----")),
    ("bearer-token", "secret", re.compile(rb"(?i)\bbearer [A-Za-z0-9._~+/-]{24,}")),
    # Split literals below keep this file from matching its own rules.
    ("ai-trailer", "trace", re.compile(rb"(?i)co-authored" rb"-by:[^\n]*(?:claude|anthropic|codex|openai|hermes|copilot|gpt)")),
    ("ai-generated-line", "trace", re.compile(rb"(?i)generated (?:with|by) \[?(?:claude|codex|hermes)")),
    ("ai-session-link", "trace", re.compile(rb"(?i)(?:claude\.ai/(?:code|chat|share)/|claude-sess" rb"ion:|chatgpt\.com/(?:c|share)/)")),
    ("ai-noreply", "trace", re.compile(rb"(?i)noreply@anthropic\.com")),
]
ALLOWED_EMAIL = re.compile(
    rb"(?i)(?:@(?:[a-z0-9-]+\.)*example(?:\.com|\.org|\.net|\.test)$"
    rb"|@(?:[a-z0-9-]+\.)*example\.test$|@[a-z0-9.-]+\.test$"
    rb"|@users\.noreply\.github\.com$|^(?:noreply|support)@github\.com$|^git@github\.com$"
    rb"|@[0-9]x\.(?:png|jpg|pdf)$)")

denylist = []  # (label, compiled)
def add_term(label, term):
    term = term.strip()
    if len(term) < 3:
        return
    denylist.append((label, re.compile(re.escape(term.encode()), re.IGNORECASE)))

list_path = os.environ.get("PRIVACY_DENYLIST")
if not list_path:
    gd = run("git", "rev-parse", "--git-common-dir", text=True).stdout.strip()
    list_path = os.path.join(gd, "info", "privacy-denylist") if gd else ""
if list_path and os.path.isfile(list_path):
    for i, line in enumerate(open(list_path, encoding="utf-8"), 1):
        line = line.split("#", 1)[0].strip()
        if line:
            add_term(f"denylist:{i}", line)

if not IN_CI:
    user = os.environ.get("USER") or run("whoami", text=True).stdout.strip()
    if user:
        # The bare account name can be an ordinary word; look for it where a
        # path or an address would carry it.
        u = re.escape(user.encode())
        denylist.append(("machine-user", re.compile(rb"(?:/|\\|~)" + u + rb"(?![A-Za-z0-9_-])|" + u + rb"@", re.IGNORECASE)))
    for label, cmd in (("machine-host", ["hostname", "-s"]),
                       ("machine-host", ["scutil", "--get", "LocalHostName"]),
                       ("machine-name", ["scutil", "--get", "ComputerName"])):
        try:
            v = run(*cmd, text=True).stdout.strip()
        except FileNotFoundError:
            v = ""
        if v and v.lower() not in ("localhost",):
            add_term(label, v)
    try:
        io = run("ioreg", "-rd1", "-c", "IOPlatformExpertDevice", text=True).stdout
        m = re.search(r'"IOPlatformSerialNumber" = "([^"]+)"', io)
        if m:
            add_term("machine-serial", m.group(1))
    except FileNotFoundError:
        pass
    try:
        for ip in re.findall(r"inet (\d+\.\d+\.\d+\.\d+)", run("ifconfig", text=True).stdout):
            if not ip.startswith("127."):
                add_term("machine-ip", ip)
    except FileNotFoundError:
        pass
    mail = run("git", "config", "user.email", text=True).stdout.strip()
    if mail and "noreply" not in mail:
        add_term("machine-git-email", mail)

def show(rule_kind, value):
    if rule_kind == "secret":
        return f"<{len(value)} chars, hidden>"
    s = value.decode("utf-8", "replace")
    if IN_CI or rule_kind == "deny-ci":
        return (s[:3] + "***") if len(s) > 3 else "***"
    return s

def scan_bytes(data):
    """Return {(rule, shown): count}."""
    hits = defaultdict(int)
    for name, kind, rx in RULES:
        for m in rx.finditer(data):
            v = m.group(0)
            if name == "email" and ALLOWED_EMAIL.search(v):
                continue
            hits[(name, show(kind, v))] += 1
    for label, rx in denylist:
        for m in rx.finditer(data):
            hits[(label, show("path", m.group(0)))] += 1
    return hits

findings = []  # (scope, location, rule, what, count, first)
def record(scope, location, hits, first=""):
    for (rule, what), n in sorted(hits.items()):
        findings.append((scope, location, rule, what, n, first))

# ---------------------------------------------------------------- a) tree
def scan_tree():
    files = run("git", "ls-files", "-z").stdout.split(b"\0")
    for f in files:
        if not f:
            continue
        path = f.decode("utf-8", "replace")
        record("tree", path + " (name)", scan_bytes(f))
        try:
            with open(f, "rb") as h:
                data = h.read()
        except (FileNotFoundError, IsADirectoryError):
            continue
        record("tree", path, scan_bytes(data))

# ---------------------------------------------------------------- b) history
def first_commit_for(obj):
    out = run("git", "log", "--exclude=refs/stash", "--all", "--reverse", "--format=%h", f"--find-object={obj}", text=True).stdout.split()
    return out[0] if out else "?"

def scan_history():
    # Every ref except refs/stash: a stash never leaves the machine.
    objs = run("git", "rev-list", "--exclude=refs/stash", "--all", "--objects").stdout.decode("utf-8", "replace").splitlines()
    paths = defaultdict(set)
    shas = []
    for line in objs:
        sha, _, p = line.partition(" ")
        shas.append(sha)
        if p:
            paths[sha].add(p)
    # Every path name that ever existed.
    names = defaultdict(set)
    for sha, ps in paths.items():
        for p in ps:
            for k in scan_bytes(p.encode()):
                names[p].add(sha)
    # Object types, then contents, in one pass each.
    check = subprocess.run(["git", "cat-file", "--batch-check"], input="\n".join(shas).encode(),
                           capture_output=True).stdout.decode().splitlines()
    kinds = {}
    for line in check:
        parts = line.split()
        if len(parts) >= 2:
            kinds[parts[0]] = parts[1]
    tags = run("git", "for-each-ref", "--format=%(objectname) %(objecttype)", "refs/tags", text=True).stdout.split("\n")
    for t in tags:
        if t.endswith(" tag"):
            kinds[t.split()[0]] = "tag"
    want_objs = [s for s, k in kinds.items() if k in ("blob", "commit", "tag")]
    proc = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    proc.stdin.write("\n".join(want_objs).encode() + b"\n"); proc.stdin.close()
    per_loc = {}  # (location) -> hits, first
    for _ in want_objs:
        header = proc.stdout.readline().split()
        if len(header) < 3:
            break
        sha, kind, size = header[0].decode(), header[1].decode(), int(header[2])
        data = proc.stdout.read(size); proc.stdout.read(1)
        hits = scan_bytes(data)
        if not hits:
            continue
        if kind == "blob":
            for p in sorted(paths.get(sha, {"?"})):
                key = ("history", p)
                agg, firsts = per_loc.setdefault(key, (defaultdict(int), set()))
                for k, n in hits.items():
                    agg[k] = max(agg[k], n)
                firsts.add(sha)
        else:
            label = f"{kind} {sha[:7]}" + (" (message/identity)" if kind == "commit" else " (tag message)")
            record("history", label, hits, sha[:7])
    proc.wait()
    order = run("git", "rev-list", "--exclude=refs/stash", "--all", "--topo-order", "--reverse", text=True).stdout.split()
    rank = {s[:7]: i for i, s in enumerate(order)}
    for (scope, p), (agg, blobs) in sorted(per_loc.items()):
        firsts = [first_commit_for(b) for b in blobs]
        first = min(firsts, key=lambda c: rank.get(c[:7], 1 << 30))
        record("history", f"{p} ({len(blobs)} versions)", agg, first)
    for p in sorted(names):
        record("history", p + " (name)", scan_bytes(p.encode()))

# ---------------------------------------------------------------- c/d) files
MACHO = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xfe\xed\xfa\xcf", b"\xbe\xba\xfe\xca"}

def scan_dir(scope, root, label_root, only_macho=False):
    count = 0
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        if only_macho:
            dirnames[:] = [d for d in dirnames if not d.endswith((".build", ".swiftmodule", "ModuleCache"))]
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            if os.path.islink(full) or not os.path.isfile(full):
                continue
            with open(full, "rb") as h:
                head = h.read(4)
                if only_macho and head not in MACHO:
                    continue
                data = head + h.read()
            count += 1
            rel = os.path.relpath(full, root)
            record(scope, f"{label_root}/{rel}", scan_bytes(data))
    return count

def scan_build():
    root = os.path.realpath(".build/release")
    if not os.path.isdir(root):
        print("note: no .build/release — build check skipped", file=sys.stderr)
        return
    n = scan_dir("build", root, ".build/release", only_macho=True)
    print(f"   build: {n} Mach-O files read as bytes", file=sys.stderr)

def scan_artifact(path):
    name = os.path.basename(path.rstrip("/"))
    if os.path.isdir(path):
        for entry in sorted(os.listdir(path)):
            full = os.path.join(path, entry)
            if os.path.isfile(full) and entry.endswith((".dmg", ".tar.gz", ".tgz", ".zip", ".json")) or entry == "SHA256SUMS":
                scan_artifact(full)
        return
    if not os.path.isfile(path):
        print(f"ERROR: no such artifact: {path}", file=sys.stderr); sys.exit(2)
    tmp = tempfile.mkdtemp(prefix="privacy-check-")
    try:
        if name.endswith(".dmg"):
            mnt = os.path.join(tmp, "mnt"); os.mkdir(mnt)
            r = run("hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mnt, path)
            if r.returncode != 0:
                print(f"ERROR: could not mount {name}", file=sys.stderr); sys.exit(2)
            try:
                n = scan_dir("artifact", mnt, name)
            finally:
                run("hdiutil", "detach", "-quiet", mnt)
        elif name.endswith((".tar.gz", ".tgz", ".tar")):
            with tarfile.open(path) as t:
                t.extractall(tmp, filter="data")
            n = scan_dir("artifact", tmp, name)
        elif name.endswith(".zip"):
            with zipfile.ZipFile(path) as z:
                z.extractall(tmp)
            n = scan_dir("artifact", tmp, name)
        else:
            record("artifact", name, scan_bytes(open(path, "rb").read())); n = 1
        print(f"   artifact: {name}: {n} files read as bytes", file=sys.stderr)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

# ---------------------------------------------------------------- run
print(f"== privacy gate ({'CI, values masked' if IN_CI else 'local'}; "
      f"{len(RULES)} rules + {len(denylist)} local terms) ==", file=sys.stderr)
if want["tree"]: scan_tree()
if want["history"]: scan_history()
if want["build"]: scan_build()
for a in artifacts: scan_artifact(a)

if not findings:
    scopes = [k for k, v in want.items() if v] + (["artifacts"] if artifacts else [])
    print(f"OK: privacy gate clean ({', '.join(scopes)})")
    sys.exit(0)

print(f"{'SCOPE':8}  {'COUNT':>5}  {'FIRST':7}  {'RULE':22}  {'WHAT':34}  LOCATION")
for scope, loc, rule, what, n, first in findings:
    print(f"{scope:8}  {n:>5}  {first or '-':7}  {rule:22}  {what[:34]:34}  {loc}")
print(f"FAIL: {len(findings)} findings, {sum(f[4] for f in findings)} occurrences", file=sys.stderr)
sys.exit(1)
PY
