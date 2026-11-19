# Military Duels autoresearch

The game is built in 6 phases (`research/phases/1.md` … `6.md`). `research/CURRENT_PHASE` holds the phase being built. The judge scores phases 1..N together, so earlier phases can't break without the score dropping. The run cap and the line cap reset for each phase.

Rules for the whole job:
- After locking, never edit anything under `research/`, or `scripts/check.sh`, `selene.toml`, `stylua.toml`, `.luaurc`, `rokit.toml`. The benchmark refuses to score if you do.
- Build everything from code in `src/`. No uploaded assets, no packages, no monetization.
- Commit each kept iteration and revert a discarded one.

Per phase:
1. The owner sets `research/CURRENT_PHASE` to N. Only the owner does this, never the loop.
2. `python3 research/eval/evaluate.py --selftest` must print `SELFTEST OK`.
3. `research/lock.sh` must print `LOCKED phase N`.
4. In omp (`omp --model grok-4.7`), open this folder and start `/autoresearch` with:
   - Intent: build phase N of Military Duels (`research/phases/N.md`; full design in `research/brief.md`). Keep phases 1..N-1 working.
   - Benchmark command: `bash research/autoresearch.sh`
   - Primary metric: `composite_score`, unit points, direction higher
   - Files in scope: `src/`, `default.project.json`, `README.md`
   - Off-limits: everything listed in the rules above
   - Max iterations: 25
   - Constraints:
     - Each iteration, fix the `ASI biggest_flaw` from the last run.
     - Keep `./scripts/check.sh` green with zero selene warnings.
     - Never build features from later phases.
5. Stop at `RUN CAP REACHED`, the iteration cap, or 6 runs without improvement.
6. **Phase gate (owner):** play the phase in Studio. Noelle playtests it. Only move to N+1 when the playtest passes and the composite score is at least 70. A score is a code review, not a playtest.
