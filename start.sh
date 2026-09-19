#!/bin/sh
# Runs two things in this one container:
#   1. n8n itself (unchanged from the original image's own startup)
#   2. the Python task runner launcher, run from its own copied files,
#      talking to n8n over localhost only (no external networking needed -
#      both processes share this one dyno)
set -eu

echo "[start.sh] starting n8n..."
# Just "start" - the entrypoint script itself already runs "exec n8n $@",
# so passing "n8n start" here would run "n8n n8n start", which n8n's CLI
# reads as an unknown subcommand called "n8n".
/docker-entrypoint.sh start &
N8N_PID=$!

echo "[start.sh] starting Python task runner..."
# Heroku dynos don't allow chroot (no CAP_SYS_CHROOT), even as root, so we
# can't isolate this the way a normal Docker host would allow. Instead we
# just run the copied launcher/python directly by path, and point the
# dynamic linker and Python's own module search at the copied files with
# env vars, so it uses its own copy rather than anything of n8n's.
(
  export N8N_RUNNERS_TASK_BROKER_URI="http://127.0.0.1:5679"
  export LD_LIBRARY_PATH="/opt/python-runner-fs/usr/local/lib:${LD_LIBRARY_PATH:-}"
  export PATH="/opt/python-runner-fs/usr/local/bin:$PATH"
  /opt/python-runner-fs/usr/local/bin/task-runner-launcher python
) &
RUNNER_PID=$!

# If either process dies, bring the whole container down so Heroku restarts
# it, rather than limping along with only half the system working.
# (plain POSIX sh has no "wait -n", so poll instead)
while kill -0 "$N8N_PID" 2>/dev/null && kill -0 "$RUNNER_PID" 2>/dev/null; do
  sleep 5
done
echo "[start.sh] a process exited, shutting down"
kill "$N8N_PID" "$RUNNER_PID" 2>/dev/null || true
wait 2>/dev/null || true
