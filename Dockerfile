# Combines n8n's own image (which has no Python at all in its final layer)
# with n8n's separate task-runner image (which does have Python + pip + uv),
# so the Code node's "Python" option works with real pip packages on a single
# Heroku dyno. Pin both to the SAME n8n version - the runner and n8n main
# talk to each other over a versioned protocol, so a mismatch can break them.
ARG N8N_VERSION=1.121.0

# ---- Stage 1: build a Python task runner with your pip packages baked in ----
FROM n8nio/runners:${N8N_VERSION} AS runner
USER root
COPY runner-requirements.txt /tmp/runner-requirements.txt
RUN cd /opt/runners/task-runner-python && \
    uv pip install -r /tmp/runner-requirements.txt

# ---- Stage 2: n8n itself, with the whole runner filesystem grafted in ----
FROM n8nio/n8n:${N8N_VERSION}

# COPY doesn't need USER root - the builder does it with full privileges
# regardless of the active USER. So we don't touch USER here, and the image
# keeps running as n8n's own intended user throughout (Heroku dynos also
# don't allow chroot even as root, so isolating the runner that way is not
# an option here - we just point it at its own copied files instead).
COPY --from=runner / /opt/python-runner-fs

# n8n's own image ships a task-runner config with no "python" entry (it only
# expects JavaScript). Overwrite it with the runner image's own config,
# which does define python, so the launcher can actually find that runner
# type at its default config path.
COPY --from=runner /etc/n8n-task-runners.json /etc/n8n-task-runners.json

COPY start.sh /start.sh
USER root
RUN chmod +x /start.sh
USER node

ENTRYPOINT ["/start.sh"]
