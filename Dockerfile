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
USER root

# Copy the ENTIRE runner image filesystem into its own folder, rather than
# merging individual files into n8n's paths. This is deliberately the
# "safe but heavier" choice: it can't silently overwrite anything n8n's own
# image already relies on (its own Node.js, its own libraries). The runner
# process then runs chrooted into this folder, so from its point of view it
# has its own complete, untouched filesystem.
COPY --from=runner / /opt/python-runner-fs

COPY start.sh /start.sh
RUN chmod +x /start.sh

# Root is required here so start.sh can chroot the runner process. n8n itself
# is still what ends up serving traffic; start.sh does not change that.
ENTRYPOINT ["/start.sh"]
