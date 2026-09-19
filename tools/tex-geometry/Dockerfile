# Pure-TeX geometry oracle image (issue #178): stock TeX Live renders a
# math snippet to DVI; `dvitype` dumps absolute glyph/rule positions and
# `geometry` normalizes the dump to machine-comparable JSON.
#
# Base digest resolved 2026-09-19; refresh with:
#   docker pull debian:bookworm-slim &&
#   docker inspect --format='{{index .RepoDigests 0}}' debian:bookworm-slim
FROM docker.io/library/debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      texlive-base \
      texlive-latex-base \
      texlive-latex-recommended \
      texlive-fonts-recommended \
      poppler-utils \
      python3 \
 && rm -rf /var/lib/apt/lists/*
# texlive-base carries `latex` (DVI mode) and `dvitype`; -recommended
# carries amsmath (`\frac` in the narrow corpus); -fonts-recommended
# carries the rsfs metrics. python3 is stdlib-only glue (`geometry`).

# Extract one case: extract <texfile> <display:0|1> <out.json>
COPY extract.sh /usr/local/bin/extract
COPY geometry.py /usr/local/bin/geometry
RUN chmod +x /usr/local/bin/extract /usr/local/bin/geometry
ENTRYPOINT ["extract"]
