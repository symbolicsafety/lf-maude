# Ubuntu 25.04 base
FROM ubuntu:20.04
#
# Use bash for RUN so we can use bash-isms if needed
SHELL ["/bin/bash", "-lc"]

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC

# Install Java, Maude build deps, and helpers for release discovery
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates curl jq unzip tar \
  maude \
  && rm -rf /var/lib/apt/lists/*

# Where we’ll place things
ENV LF_MAUDE_RT_BASE=/opt/lf-maude

# Download & unpack TCTL-with-dataflow tagged release of lf-maude real-time branch
RUN set -eux; \
  mkdir -p "${LF_MAUDE_RT_BASE}" /tmp/lfrt; \
  MLF_URL='https://api.github.com/repos/symbolicsafety/lf-maude/tarball/TCTL-further-analysis'; \
  echo "Downloading lf-maude: ${MLF_URL}"; \
  curl -L "${MLF_URL}" -o /tmp/lfrt/pkg.tar.gz ; \
  mkdir -p /tmp/lfrt/extract; \
  tar -xf /tmp/lfrt/pkg.tar.gz -C /tmp/lfrt/extract; \
  # Move contents (handles either a top-level dir or flat files)
  SRC_DIR="$(find /tmp/lfrt/extract -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"; \
  if [ -n "${SRC_DIR}" ]; then \
  shopt -s dotglob && mv "${SRC_DIR}"/* "${LF_MAUDE_RT_BASE}/"; \
  else \
  shopt -s dotglob && mv /tmp/lfrt/extract/* "${LF_MAUDE_RT_BASE}/"; \
  fi; \
  rm -rf /tmp/lfrt

# OCI labels (helpful for GHCR)
LABEL org.opencontainers.image.title="lf-maude-rtm-v1" \
  org.opencontainers.image.description="Ubuntu 20.04 with lf-maude real-time version preinstalled" \
  org.opencontainers.image.source="https://github.com/symbolicsafety/lingua-franca-maude"

# Default command shows versions & where things live
CMD bash -lc 'echo "LFM_BASE=$LFM_BASE" && command -v maude || true '
