# syntax=docker/dockerfile:1.7

FROM ubuntu:25.04 AS uclid-builder
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG TZ=Etc/UTC
ARG UCLID_REF=4fd5e566c5f87b052f92e9b23723a85e1c4d8c1c
ARG UCLID_VERSION=0.9.5
ARG Z3_VERSION=4.8.8
ARG SETUPTOOLS_VERSION=68.2.2

RUN ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
  && echo "${TZ}" > /etc/timezone

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  git \
  gpg \
  openjdk-17-jdk \
  openssh-client \
  protobuf-compiler \
  python3 \
  python3-pip \
  python3-venv \
  tar \
  unzip \
  wget \
  zip \
  && mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://keyserver.ubuntu.com/pks/lookup?op=get\&search=0x99E82A75642AC823 \
  | gpg --dearmor -o /etc/apt/keyrings/sbt.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/sbt.gpg] https://repo.scala-sbt.org/scalasbt/debian all main" > /etc/apt/sources.list.d/sbt.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends sbt \
  && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/uclid-org/uclid.git /tmp/uclid-src \
  && cd /tmp/uclid-src \
  && git checkout "${UCLID_REF}"

# amd64 uses the official upstream binary release Uclid expects.
# arm64 builds the same Z3 version from the official upstream source tag.
RUN cd /tmp/uclid-src \
  && case "${TARGETARCH}" in \
  amd64) \
  wget -q "https://github.com/Z3Prover/z3/releases/download/z3-${Z3_VERSION}/z3-${Z3_VERSION}-x64-ubuntu-16.04.zip" -O /tmp/z3.zip \
  && unzip -q /tmp/z3.zip -d /tmp \
  && rm -rf z3 \
  && mv "/tmp/z3-${Z3_VERSION}-x64-ubuntu-16.04" z3 \
  && cp z3/bin/com.microsoft.z3.jar lib/ \
  ;; \
  arm64) \
  python3 -m venv /tmp/z3-venv \
  && /tmp/z3-venv/bin/pip install --no-cache-dir "setuptools==${SETUPTOOLS_VERSION}" \
  && git clone --depth 1 --branch "z3-${Z3_VERSION}" https://github.com/Z3Prover/z3.git /tmp/z3-src \
  && PATH="/tmp/z3-venv/bin:${PATH}" cmake -S /tmp/z3-src -B /tmp/z3-src/build -DCMAKE_BUILD_TYPE=Release -DZ3_BUILD_JAVA_BINDINGS=ON \
  && cmake --build /tmp/z3-src/build -j"$(nproc)" \
  && mkdir -p z3/bin \
  && cp /tmp/z3-src/build/z3 /tmp/z3-src/build/libz3.so /tmp/z3-src/build/libz3java.so /tmp/z3-src/build/com.microsoft.z3.jar z3/bin/ \
  && cp z3/bin/com.microsoft.z3.jar lib/ \
  ;; \
  *) \
  echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 \
  ;; \
  esac

RUN cd /tmp/uclid-src \
  && sbt update clean compile universal:packageBin \
  && unzip -q "target/universal/uclid-${UCLID_VERSION}.zip" -d /opt

FROM ubuntu:25.04 AS runtime
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Etc/UTC
ARG UCLID_VERSION=0.9.5
ARG LF_MAUDE_URL="https://github.com/symbolicsafety/lf-maude/archive/refs/tags/lf-maude-v1.2.tar.gz"
ARG LF_MAUDE_SHA256=""
ARG LFM_URL="https://github.com/symbolicsafety/lingua-franca-maude/releases/download/lfmc-v1.2/lf-mc-v1.2.tar.gz"
ARG LFM_SHA256="sha256:232c719cbbb3a2e6a5ed8d4024b31939f77122fbaa527ecb39c4f289f2819b72"
ARG LF_VERIFIER_BENCHMARKS_REF="193e6d609d57ba4540c9971ca1bdbce77a398b1a"

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
  git \
  hyperfine \
  libstdc++6 \
  maude \
  openjdk-17-jre-headless \
  tar \
  tzdata \
  unzip \
  vim \
  && rm -rf /var/lib/apt/lists/*

COPY --from=uclid-builder /tmp/uclid-src/z3 /opt/uclid-z3
COPY --from=uclid-builder /opt/uclid-${UCLID_VERSION} /opt/uclid-${UCLID_VERSION}

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

ENV PATH="${PATH}:${LFM_BASE}/bin:${LF_MAUDE_BASE}/bin:/opt/uclid-${UCLID_VERSION}/bin:/opt/uclid-z3/bin"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}/opt/uclid-z3/bin"

RUN if [ -n "${LF_VERIFIER_BENCHMARKS_REF}" ]; then \
  git clone https://github.com/lf-lang/lf-verifier-benchmarks.git /opt/lf-verifier-benchmarks \
  && cd /opt/lf-verifier-benchmarks \
  && git checkout "${LF_VERIFIER_BENCHMARKS_REF}" \
  && for f in /opt/lf-verifier-benchmarks/benchmarks/src/*lf; do sed -i 's/int(0)/int = 0/' "$f"; done \
  && sed -i 's/time(1 sec)/time = 1 sec/' /opt/lf-verifier-benchmarks/benchmarks/src/RoadsideUnit.lf; \
  fi

RUN test -x "${LFM_BASE}/bin/lfc" \
  && lfc --version \
  && z3 --version \
  && uclid --help > /dev/null \
  && command -v maude > /dev/null

RUN echo 'export LF_MAUDE_BASE=/opt/lf-maude' > /etc/profile.d/lf-maude-env.sh \
  && echo 'export LFM_BASE=/opt/lingua-franca-maude' >> /etc/profile.d/lf-maude-env.sh \
  && echo 'export MAUDE_BASE=/usr/bin' >> /etc/profile.d/lf-maude-env.sh \
  && echo 'export PATH="$PATH:$LFM_BASE/bin:$LF_MAUDE_BASE/bin:/opt/uclid-'"${UCLID_VERSION}"'/bin:/opt/uclid-z3/bin"' >> /etc/profile.d/lf-maude-env.sh \
  && echo 'export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}/opt/uclid-z3/bin"' >> /etc/profile.d/lf-maude-env.sh \
  && chmod +x /etc/profile.d/lf-maude-env.sh

LABEL org.opencontainers.image.title="lingua-franca-maude-v1.2" \
  org.opencontainers.image.description="Image includes lf-mc, lf-maude, lf-verifier-benchmarks on Ubuntu 25.04" \
  org.opencontainers.image.source="https://github.com/symbolicsafety/lf-maude"

CMD ["/bin/bash"]
