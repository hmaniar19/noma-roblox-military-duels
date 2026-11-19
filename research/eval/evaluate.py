#!/usr/bin/env python3
"""Military Duels autoresearch evaluator. Stdlib only. OFF-LIMITS to the research agent.
Order: tripwire -> run cap -> hard gates (check.sh, size, placeholders) -> judge (median of N,
in parallel) -> METRIC / ASI lines. Any gate failure exits non-zero.
Phased: research/CURRENT_PHASE picks the scope (phases 1..N are scored); run cap and line cap are per phase.
"""
import concurrent.futures, json, os, re, statistics, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(os.environ.get("GAME_ROOT", Path(__file__).resolve().parents[2]))
SELFTEST = os.environ.get("GAME_SELFTEST") == "1"
LOCKED = ["research/brief.md", "research/phases", "research/CURRENT_PHASE", "research/eval",
          "research/autoresearch.sh", "research/lock.sh", "research/SETUP.md", "scripts/check.sh",
          "selene.toml", "stylua.toml", ".luaurc", "rokit.toml"]
AXES = {"brief_fidelity": 0.30, "gameplay_loop": 0.30, "robustness": 0.25, "polish": 0.15}


def fail(msg, code=1):
    print(f"GATE FAILED: {msg}")
    print("ASI biggest_flaw=" + re.sub(r"\s+", " ", f"gate failed: {msg}")[:400])
    sys.exit(code)


PHASE = int((ROOT / "research/CURRENT_PHASE").read_text().strip())
STATE = Path(os.environ.get("GAME_STATE_DIR", Path.home() / ".game-autoresearch-state" / ROOT.name)) / f"phase-{PHASE}"


def tripwire():
    if SELFTEST:
        return
    def git(*a):
        return subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True)
    if git("rev-parse", "-q", "--verify", "refs/tags/locked-baseline").returncode != 0:
        fail("no locked-baseline tag. Run research/lock.sh", 4)
    changed = git("diff", "--name-only", "locked-baseline", "--", *LOCKED).stdout.split()
    if changed:
        fail("locked files changed since lock: " + ", ".join(changed), 4)


def run_cap(c):
    STATE.mkdir(parents=True, exist_ok=True)
    log = STATE / "attempts.log"
    n = sum(1 for _ in log.open()) if log.exists() else 0
    if n >= c["max_runs"]:
        print(f"RUN CAP REACHED ({n}/{c['max_runs']}) for phase {PHASE}. STOP THE LOOP and report to the owner.")
        sys.exit(3)
    with log.open("a") as f:
        f.write(f"{int(time.time())}\n")
    return n + 1


def source_files():
    return sorted(p for p in (ROOT / "src").rglob("*.luau") if p.is_file())


def hard_gates(c):
    env = dict(os.environ, PATH=f"{Path.home() / '.rokit/bin'}:{os.environ.get('PATH', '')}")
    cmd = os.environ.get("CHECK_CMD") if SELFTEST else None
    r = subprocess.run(cmd or "./scripts/check.sh", shell=True, cwd=ROOT, env=env,
                       capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    if r.returncode != 0 or "CHECK OK" not in out:
        tail = " | ".join(l for l in out.strip().splitlines()[-12:] if "[INFO]" not in l)
        fail(f"scripts/check.sh failed: {tail}")
    m = re.search(r"(\d+) warnings", out)
    warnings = int(m.group(1)) if m else 0

    files = source_files()
    if not files:
        fail("no .luau files under src/")
    sources, lines = {}, 0
    for p in files:
        text = p.read_text(encoding="utf-8")
        rel = str(p.relative_to(ROOT))
        if re.search(r"\b(TODO|FIXME|TBD|XXX)\b", text):
            fail(f"{rel} contains a placeholder (TODO/FIXME/TBD/XXX)")
        sources[rel] = text
        lines += text.count("\n") + 1
    cap = c["max_src_lines"][str(PHASE)]
    if lines > cap:
        fail(f"src/ is {lines} lines; phase {PHASE} cap is {cap}. Simplify.")
    return sources, warnings, lines


def ask_judge(cmd, prompt):
    try:
        r = subprocess.run(cmd, shell=True, input=prompt, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return None
    for m in reversed(list(re.finditer(r"\{[^{}]*\}", r.stdout, re.S))):
        try:
            d = json.loads(m.group(0))
            out = {a: max(0, min(100, int(d[a]))) for a in AXES}
            out["biggest_flaw"] = str(d.get("biggest_flaw", ""))[:400]
            return out
        except (ValueError, KeyError, TypeError):
            continue
    return None


def phase_scope():
    return "\n\n".join((ROOT / f"research/phases/{n}.md").read_text() for n in range(1, PHASE + 1))


def judge_prompt(brief, scope, sources):
    code = "\n\n".join(f"===== {path} =====\n{text}" for path, text in sources.items())
    return f"""You are a senior Roblox FPS developer and a skeptical playtester reviewing a Roblox duel shooter's
source code (Luau, synced with Rojo; server in src/server, client in src/client, shared in src/shared).
You cannot run it. Trace what actually happens at runtime from the code. Ignore comments, names and README
claims: a feature counts only if the code really does it. 50 means mediocre. Be harsh.

The game is built in phases. We are on phase {PHASE}. Score ONLY against the CURRENT SCOPE (phases 1..{PHASE});
do not penalize missing features from later phases. The full design is context for intent and naming.

Score 0-100 on four axes:
- brief_fidelity: every item in the CURRENT SCOPE is present and behaves as described; earlier phases still work.
- gameplay_loop: a kid pressing Play alone in Studio gets a working duel (bots fill empty slots), rounds end with
  a clear win/loss/draw, weapons and tuning (damage, fire rate, speeds, timings) are plausibly fun and fair.
- robustness: the server is authoritative for hits, damage, ammo, movement limits and rewards; RemoteEvents are
  type-checked and rate-limited; shots through walls or from impossible positions are rejected; no runtime bugs,
  Roblox API misuse, nil/destroyed-instance errors, stuck bots, leaks across rounds, or join/leave/death edge cases.
- polish: player feedback (HUD, hit markers, messages, sounds, effects), readable maps, team readability.

CURRENT SCOPE (fixed):
{scope}

FULL DESIGN (context only):
{brief}

SOURCE:
{code}

Return ONLY one JSON object, no prose, no code fence:
{{"brief_fidelity": int, "gameplay_loop": int, "robustness": int, "polish": int, "biggest_flaw": "one sentence naming the single most important thing to fix next, with file and function"}}"""


def weighted(r):
    return sum(r[a] * w for a, w in AXES.items())


def main():
    c = json.loads((ROOT / "research/eval/constraints.json").read_text())
    tripwire()
    run_no = run_cap(c)
    sources, warnings, lines = hard_gates(c)
    cmd = os.environ.get("JUDGE_CMD", "").strip()
    if not cmd:
        fail("JUDGE_CMD not set in research/eval/judge.env", 4)
    prompt = judge_prompt((ROOT / "research/brief.md").read_text(), phase_scope(), sources)
    with concurrent.futures.ThreadPoolExecutor(c["judge_runs"]) as pool:
        results = [r for r in pool.map(lambda _: ask_judge(cmd, prompt), range(c["judge_runs"])) if r]
    if len(results) < (c["judge_runs"] + 1) // 2:
        fail(f"judge returned usable JSON only {len(results)}/{c['judge_runs']} times", 5)
    med = {a: statistics.median(r[a] for r in results) for a in AXES}
    raw = weighted(med)
    penalty = c["warning_penalty"] * warnings
    composite = max(0, round(raw - penalty))
    worst = min(results, key=weighted)
    rec = {"phase": PHASE, "run": run_no, "ts": int(time.time()), "composite": composite, "raw": round(raw, 1),
           "penalty": penalty, "median": med, "lines": lines, "flaw": worst["biggest_flaw"]}
    hold = os.environ.get("HOLDOUT_CMD", "").strip()
    if hold and run_no % c["holdout_every"] == 0:
        h = ask_judge(hold, prompt)
        if h:
            rec["holdout"] = round(weighted(h), 1)
            print(f"METRIC holdout_score={rec['holdout']:.0f}")
    with (STATE / "runs.jsonl").open("a") as f:
        f.write(json.dumps(rec) + "\n")
    print(f"METRIC composite_score={composite}")
    for a in AXES:
        print(f"METRIC {a}={med[a]:.0f}")
    print(f"METRIC lint_warnings={warnings}")
    print(f"METRIC src_lines={lines}")
    print("ASI biggest_flaw=" + re.sub(r"\s+", " ", worst["biggest_flaw"]))
    print(f"ASI phase={PHASE} run={run_no}/{c['max_runs']} penalty={penalty} (each selene warning costs {c['warning_penalty']})")


def selftest():
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        (t / "research/eval").mkdir(parents=True)
        (t / "research/phases").mkdir()
        (t / "src/server").mkdir(parents=True)
        (t / "state").mkdir()
        (t / "research/brief.md").write_text("Two soldiers duel.")
        (t / "research/phases/1.md").write_text("Phase 1: one duel.")
        (t / "research/CURRENT_PHASE").write_text("1\n")
        (t / "research/eval/constraints.json").write_text(json.dumps(
            {"max_runs": 5, "judge_runs": 3, "holdout_every": 5, "warning_penalty": 2, "max_src_lines": {"1": 100}}))
        (t / "src/server/init.server.luau").write_text('print("hi")\n')
        stub = ("python3 -c \"print('ok {\\\"brief_fidelity\\\": 60, \\\"gameplay_loop\\\": 70, "
                "\\\"robustness\\\": 50, \\\"polish\\\": 40, \\\"biggest_flaw\\\": \\\"stub\\\"}')\"")
        env = dict(os.environ, GAME_ROOT=str(t), GAME_STATE_DIR=str(t / "state"), GAME_SELFTEST="1",
                   JUDGE_CMD=stub, HOLDOUT_CMD="", CHECK_CMD="echo '1 warnings'; echo 'CHECK OK'")
        r = subprocess.run([sys.executable, __file__], env=env, capture_output=True, text=True)
        # 60*.30 + 70*.30 + 50*.25 + 40*.15 = 57.5, minus 1 warning * 2 = 55.5 -> 56
        if r.returncode == 0 and "METRIC composite_score=56" in r.stdout and "phase=1" in r.stdout:
            bad = dict(env, CHECK_CMD="echo boom; exit 1")
            r2 = subprocess.run([sys.executable, __file__], env=bad, capture_output=True, text=True)
            if r2.returncode != 0 and "GATE FAILED" in r2.stdout:
                print("SELFTEST OK")
                return 0
            print("SELFTEST FAILED (gate)\n" + r2.stdout + r2.stderr)
            return 1
        print("SELFTEST FAILED\n" + r.stdout + r.stderr)
        return 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        sys.exit(selftest())
    main()
