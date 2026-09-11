---
name: long-running
description: Use before starting anything that does not return on its own — a dev server, an API, docker compose up, a watcher, a queue worker, a database — or when a command has already hung with no output. Covers starting it detached with a log file, waiting for readiness by polling instead of sleeping, verifying the endpoint, reading the log, always killing it and freeing the port, and the interactive commands that hang forever. Triggers in Spanish too: "levanta el servidor", "arranca la app", "se queda colgado", "no responde el comando", "prueba el endpoint".
---

# Long-running processes

A shell tool call waits for the command to end. A server never ends. So a naive
`./server` or `npm run dev` burns the whole timeout and comes back with nothing
useful — and "nothing useful" is exactly what makes you retry it.

The rule: **never run a long-running process in the foreground.** Start it
detached, with its output in a file you can read.

## 1. Start it detached, with a log

```bash
nohup <command> > /tmp/<name>.log 2>&1 &
echo "pid=$!"
```

- The `> log 2>&1` is not optional: it is the only way to read why it died.
- Keep the PID. You will need it to kill the thing.
- `docker compose` has its own way: `docker compose up -d`, then
  `docker compose logs --tail 50`.

## 2. Wait for readiness — poll, never `sleep`

A fixed `sleep 5` is either too short (flaky) or too slow (wasted). Ask the
service instead, in a loop with a hard cap:

```bash
for i in $(seq 1 20); do
  curl -sf http://localhost:8080/health && break
  sleep 0.5
done
```

For something without an endpoint, poll the log or the port:

```bash
for i in $(seq 1 20); do grep -q "listening" /tmp/app.log && break; sleep 0.5; done
lsof -i :8080 | head -3
```

If the loop ends without success, **the process died or never bound the port**.
Do not retry the same start command — read the log (§4).

## 3. Verify what the task actually asked for

Status code *and* body, in one call:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/health
curl -s http://localhost:8080/health
```

"The server started" is not the goal. The response is the goal.

## 4. When it does not come up, the log has the answer

```bash
tail -40 /tmp/app.log
```

Read it whole — no `| grep` on the first read, or you will filter out the very
line that explains it. `address already in use` (something else is on that port:
`lsof -i :8080`), a missing env var, a failed migration, a stack trace on
startup. Then the `unstick` skill applies: name the error, fix the cause.

## 5. Always clean up

Leaving a process running poisons the next run — the port is taken and the next
start fails for a reason that has nothing to do with the code.

```bash
kill <pid> 2>/dev/null || pkill -f '<unique part of the command>'
lsof -i :8080 | head -3          # confirm it is free
rm -f /tmp/<name>.log
```

Do this **before** you report the task complete, and mention it in the report.

## 6. Commands that hang because they want input

Same symptom, different cause: no output, no exit. These are the usual
offenders — always give them the non-interactive form:

| Hangs | Use instead |
| --- | --- |
| `npm init`, `npm create <x>` | add `-y` / `--yes`, pass `--template` |
| `git rebase -i`, `git commit` (no `-m`) | non-interactive flags, `-m "msg"` |
| `docker run` (attached) | `-d`, and `--rm` when it is throwaway |
| `psql`, `mysql`, `node`, `python3` with no script | pass `-c`, `-e`, or a file |
| anything opening `$EDITOR` | `GIT_EDITOR=true`, `--no-edit` |
| a prompt for a password | stop and ask the user; never guess |

If a command returns nothing and the tool reports a timeout, assume one of these
two causes — detached process or waiting for stdin — before assuming anything
else.
