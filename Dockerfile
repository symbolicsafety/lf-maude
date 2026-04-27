# syntax=docker/dockerfile:1.7

FROM ubuntu:25.04 AS runtime
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
ARG LF_MAUDE_URL="https://github.com/symbolicsafety/lf-maude/archive/refs/tags/lf-maude-v1.2.2.tar.gz"
ARG LF_MAUDE_SHA256=""
ARG LFM_URL="https://github.com/symbolicsafety/lingua-franca-maude/releases/download/lfmc-v1.2/lf-mc-v1.2.tar.gz"
ARG LFM_SHA256="sha256:232c719cbbb3a2e6a5ed8d4024b31939f77122fbaa527ecb39c4f289f2819b72"

ENV LF_MAUDE_BASE=/opt/lf-maude
ENV LFM_BASE=/opt/lingua-franca-maude
ENV MAUDE_BASE=/usr/bin

RUN ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && echo "${TZ}" > /etc/timezone

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  bash \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  hyperfine \
  jq \
  libstdc++6 \
  maude \
  openjdk-17-jre-headless \
  tar \
  tzdata \
  unzip \
  vim \
  && rm -rf /var/lib/apt/lists/*

RUN install_release() { \
  local url="$1"; \
  local sha="$2"; \
  local dest="$3"; \
  local tmpdir; \
  local src_dir; \
  local normalized_sha; \
  test -n "${url}"; \
  tmpdir="$(mktemp -d)"; \
  mkdir -p "${dest}"; \
  curl -fsSL "${url}" -o "${tmpdir}/package"; \
  normalized_sha="${sha#sha256:}"; \
  if [ -n "${normalized_sha}" ]; then echo "${normalized_sha}  ${tmpdir}/package" | sha256sum -c -; fi; \
  case "${url}" in \
  *.tar.gz|*.tgz|*/tar.gz/*|*/tarball/*) tar -xzf "${tmpdir}/package" -C "${tmpdir}" ;; \
  *.zip) unzip -q "${tmpdir}/package" -d "${tmpdir}" ;; \
  *) echo "Unsupported artifact format: ${url}" >&2; exit 1 ;; \
  esac; \
  shopt -s dotglob; \
  src_dir="$(find "${tmpdir}" -mindepth 1 -maxdepth 1 -type d | head -n1)"; \
  if [ -n "${src_dir}" ]; then \
  mv "${src_dir}"/* "${dest}/"; \
  else \
  mv "${tmpdir}"/* "${dest}/"; \
  rm -f "${dest}/package"; \
  fi; \
  rm -rf "${tmpdir}"; \
  }; \
  install_release "${LF_MAUDE_URL}" "${LF_MAUDE_SHA256}" "${LF_MAUDE_BASE}"; \
  install_release "${LFM_URL}" "${LFM_SHA256}" "${LFM_BASE}"

ENV PATH="${PATH}:${LFM_BASE}/bin:${LF_MAUDE_BASE}/bin"

RUN test -x "${LFM_BASE}/bin/lfc" \
  && lfc --version \
  && jq --version \
  && command -v maude > /dev/null

RUN echo 'export LF_MAUDE_BASE=/opt/lf-maude' > /etc/profile.d/lf-maude-env.sh \
  && echo 'export LFM_BASE=/opt/lingua-franca-maude' >> /etc/profile.d/lf-maude-env.sh \
  && echo 'export MAUDE_BASE=/usr/bin' >> /etc/profile.d/lf-maude-env.sh \
  && echo 'export PATH="$PATH:$LFM_BASE/bin:$LF_MAUDE_BASE/bin"' >> /etc/profile.d/lf-maude-env.sh \
  && chmod +x /etc/profile.d/lf-maude-env.sh

LABEL org.opencontainers.image.title="lingua-franca-maude-v1.2" \
  org.opencontainers.image.description="Image includes lf-mc and lf-maude on Ubuntu 25.04" \
  org.opencontainers.image.source="https://github.com/symbolicsafety/lf-maude"

CMD ["/bin/bash"]
