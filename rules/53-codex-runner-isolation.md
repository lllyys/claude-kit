# 53 — Codex Runner Isolation (no more stdin-wedge ghosts)

## The failure

`codex exec "<prompt>"` passes the prompt as an argument but **also reads
stdin**. In a non-tty shell — every `run_in_background` Bash, every cron-driven
agent session — stdin never reaches EOF, so Codex prints

```
Reading additional input from stdin...
```

and **blocks forever at 0% CPU**. The process is a ghost: alive in `ps`, no
output, no completion, no failure. Observed 2026-06-01: one such ghost lingered
**4h20m**, and a freshly-launched audit wedged the same way the moment it ran in
a backgrounded shell.

This is the same class as:
- **Rule 52** — the wedged long-running test run (0% CPU, lingers for hours).
- **Rule 49** — the `pgrep -f` waiter that watches a class of work, not an
  instance.

A long-runner with no liveness signal and no timeout.

## Aggravator (what made it invisible)

Redirecting the backgrounded Codex's stdout to a side `/tmp` file
(`codex exec … > /tmp/audit.txt`) instead of letting it flow to the task-output
file. The task-output file then looked empty/dead, so the harness's own
liveness display and completion notification had nothing to show — the wedge was
invisible until someone ran `ps`.

## Hard rules

1. **Never call raw `codex exec` inside a backgrounded Bash. Route every Codex
   call through cc-suite** — `/cc-suite:audit` (read-only), `/cc-suite:audit-fix`
   (audit→fix→verify), `/cc-suite:review-plan`, etc. cc-suite is a declared
   dependency of this kit; its runner shells out to `codex exec` with stdin
   closed (`/dev/null` on fd 0), a wall-clock deadline that kills the exact pid
   (SIGTERM, then SIGKILL after a grace period), a heartbeat streamed to the job
   log, and job tracking for `/cc-suite:status | result | cancel`. A hand-rolled
   `codex exec` has none of this. **Never use the Codex MCP bridge**
   (`mcp__codex…` / `mcp__plugin_codex-toolkit_codex__codex`) — it has no
   controllable timeout and hangs on long single responses.
2. **If you must call `codex exec` directly, close stdin: `< /dev/null`.** With
   immediate EOF, Codex runs normally — it does not need stdin when the prompt
   is an argument. This is the single load-bearing fix, and it is exactly what
   cc-suite's runner does for you.
3. **Do not redirect a backgrounded long-runner's stdout to a side file.** Let
   it land in the task-output file so the harness's liveness + completion
   notification work and a wedge is visible. (cc-suite's `--background` mode
   handles this via its job log — prefer it for long reviews.)
4. **Diagnose "is it hung?" by PROCESS, not the output file** (rule 52's lesson,
   applied to Codex):

   ```bash
   ps -Ao pid=,%cpu=,etime=,comm= | grep -i '[c]odex'
   ```

   A `codex` binary at **0% CPU with growing elapsed and no output growth** =
   wedged. If it was launched through cc-suite, cancel it cleanly by job id:

   ```bash
   # cc-suite-launched job:
   /cc-suite:cancel <jobId>
   # raw fallback (note: the path pattern is macOS/BSD-shaped; on Linux match
   # the binary name instead of its install path):
   pkill -x codex        # exact process name, portable
   ```

5. **Before ending a turn, confirm no live Codex ghost:** `pgrep -x codex`
   (NOT `pgrep -f codex` — `-f` matches your own grep line). Zero = clean.

## Quick reference

```bash
# Read-only audit of the changed files (Codex audits; you fix):
/cc-suite:audit

# Full audit→fix→verify loop (Codex drives the fixes; you review):
/cc-suite:audit-fix

# Long review without blocking the turn — runs detached, returns a jobId:
/cc-suite:audit --background
/cc-suite:status <jobId>   # live log
/cc-suite:result <jobId>   # final result
/cc-suite:cancel <jobId>   # kill a running job
```

cc-suite reads model / effort / sandbox / timeout from `.cc-suite.md` (or
sensible defaults), so there is no per-call flag bookkeeping to get wrong.

## Relationship to other rules

- **Rule 49 (background shells):** cc-suite's runner waits on the exact pid and
  is cancelled when Codex finishes first — it never re-arms on a future run.
- **Rule 52 (test isolation):** same ghost-class; same process-not-output
  diagnosis. cc-suite's runner is to `codex exec` what `run-tests.sh` is to the
  project's test command — the watchdog that turns an indefinite hang into a
  bounded, self-terminating run with one unambiguous result line.
- **Rule 60 §6 (cross-model review):** `/cc-suite:review-plan` is the same
  mechanism applied to plans — it goes through the same isolated runner.
