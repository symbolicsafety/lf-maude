# Ubuntu 25.04 base
FROM ubuntu:25.04
#
# Use bash for RUN so we can use bash-isms if needed
SHELL ["/bin/bash", "-lc"]

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC

# Install Java, Maude build deps, and helpers for release discovery
RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates curl jq unzip tar \
  build-essential cmake gcc \
  default-jdk-headless \
  maude \
  && rm -rf /var/lib/apt/lists/*

# Where we’ll place things
ENV LF_MAUDE_BASE=/opt/lf-maude \
  LFM_BASE=/opt/lingua-franca-maude \
  MAUDE_BASE=/usr/bin

# Download & unpack journal-with-prop tagged release of lf-maude release
RUN set -eux; \
  mkdir -p "${LF_MAUDE_BASE}" /tmp/lfm; \
  MLF_URL='https://api.github.com/repos/symbolicsafety/lf-maude/tarball/journal-with-prop'; \
  echo "Downloading lf-maude: ${MLF_URL}"; \
  curl -L "${MLF_URL}" -o /tmp/lfm/pkg.tar.gz ; \
  mkdir -p /tmp/lfm/extract; \
  tar -xf /tmp/lfm/pkg.tar.gz -C /tmp/lfm/extract; \
  # Move contents (handles either a top-level dir or flat files)
  SRC_DIR="$(find /tmp/lfm/extract -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"; \
  if [ -n "${SRC_DIR}" ]; then \
  shopt -s dotglob && mv "${SRC_DIR}"/* "${LF_MAUDE_BASE}/"; \
  else \
  shopt -s dotglob && mv /tmp/lfm/extract/* "${LF_MAUDE_BASE}/"; \
  fi; \
  rm -rf /tmp/lfm

# --- Download & unpack latest lingua-franca-maude release ---
RUN set -eux; \
  mkdir -p "${LFM_BASE}" /tmp/lfproj; \
  PROJ_URL="$(curl -s https://api.github.com/repos/symbolicsafety/lingua-franca-maude/releases/tags/lfmc-v1 | \
  jq -r '.assets[] | select(.name=="lf-maude-cli-v1.tar.gz") | .browser_download_url' )"; \
  test -n "${PROJ_URL}"; echo "Downloading lingua-franca-maude: ${PROJ_URL}"; \
  curl -L "${PROJ_URL}" -o /tmp/lfproj/lf-maude-cli-v1.tar.gz; \
  mkdir -p /tmp/lfproj/extract; \
  tar -xf /tmp/lfproj/lf-maude-cli-v1.tar.gz -C /tmp/lfproj/extract; \
  SRC_DIR="$(find /tmp/lfproj/extract -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"; \
  if [ -n "${SRC_DIR}" ]; then \
  shopt -s dotglob && mv "${SRC_DIR}"/* "${LFM_BASE}/"; \
  else \
  shopt -s dotglob && mv /tmp/lfproj/extract/* "${LFM_BASE}/"; \
  fi; \
  rm -rf /tmp/lfproj

# Put Maude and LF-Maude CLI on PATH
ENV PATH="${PATH}:${LFM_BASE}/bin"

# Persist env vars for interactive shells too
RUN echo 'export LF_MAUDE_BASE=/opt/lf-maude'                 >  /etc/profile.d/lf-maude.sh && \
  echo 'export MAUDE_BASE=/usr/bin'                >> /etc/profile.d/lf-maude.sh && \
  echo 'export LFM_BASE=/opt/lingua-franca-maude'           >> /etc/profile.d/lf-maude.sh && \
  echo 'export PATH="$PATH:$LFM_BASE/bin"'      >> /etc/profile.d/lf-maude.sh && \
  chmod +x /etc/profile.d/lf-maude.sh

# OCI labels (helpful for GHCR)
LABEL org.opencontainers.image.title="lingua-franca-maude-v1" \
  org.opencontainers.image.description="Ubuntu 25.04 with Java, make, GCC, and lf-maude + lingua-franca-maude preinstalled" \
  org.opencontainers.image.source="https://github.com/symbolicsafety/lingua-franca-maude"

# Default command shows versions & where things live
CMD bash -lc 'java -version && echo "LF_MAUDE_BASE=$LF_MAUDE_BASE" && echo "MAUDE_BASE=$MAUDE_BASE" && echo "LFM_BASE=$LFM_BASE" && command -v maude || true && ls -la "$MAUDE_BASE" || true'
