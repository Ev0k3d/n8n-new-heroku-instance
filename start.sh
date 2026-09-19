#!/bin/sh
# Runs two things in this one container:
#   1. n8n itself (unchanged from the original image's own startup)
#   2. the Python task runner launcher, chrooted into its own copied
#      filesystem, talking to n8n over localhost only (no external
#      networking needed - both processes share this one dyno)
set -eu

echo "[start.sh] starting n8n..."
/docker-entrypoint.sh n8n start &
N8N_PID=$!

echo "[start.sh] starting Python task runner (chrooted)..."
(
  export N8N_RUNNERS_TASK_BROKER_URI="http://127.0.0.1:5679"
  chroot /opt/python-runner-fs /usr/local/bin/task-runner-launcher python
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
