# ZaTeX service image: pinned Zig toolchain + the repo mounted at /work
# at run time (the tree under test is a mount, not baked in, so the same
# image sweeps any checkout). Zig 0.16.0 shasum from
# https://ziglang.org/download/index.json, recorded 2026-09-13.
FROM docker.io/library/debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl xz-utils ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
# Per-arch Zig 0.16.0 shasums from https://ziglang.org/download/index.json
# (recorded 2026-09-13); the build host's arch selects the toolchain.
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      ZIG_URL=https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz; \
      ZIG_SHA256=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17; \
    else \
      ZIG_URL=https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz; \
      ZIG_SHA256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00; \
    fi; \
    curl -fsSL -o /tmp/zig.tar.xz "$ZIG_URL" \
 && echo "$ZIG_SHA256  /tmp/zig.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/zig && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
 && rm /tmp/zig.tar.xz
ENV PATH=/opt/zig:$PATH

# Render one case: render-one <texfile> <display:0|1> <out.png>
# [--font PATH]. Builds zatex-png from /repo on first use. Default (no
# --font) renders with the full fixture stack incl. KaTeX Size1/Size2
# (issue #195); --font is a single-face-experiment opt-in only.
COPY render-one.sh /usr/local/bin/render-one
RUN chmod +x /usr/local/bin/render-one
ENTRYPOINT ["render-one"]
