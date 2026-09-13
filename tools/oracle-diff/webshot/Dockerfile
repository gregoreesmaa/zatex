# Webshot oracle image: KaTeX 0.18.7 + MathJax v3 screenshots via system
# Chromium (puppeteer-core drives it over CDP). Base digest resolved
# 2026-09-13; refresh with: docker pull node:22-bookworm-slim &&
# docker inspect --format='{{index .RepoDigests 0}}' node:22-bookworm-slim
FROM docker.io/library/node:22-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      chromium \
      fonts-dejavu-core \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# No ENTRYPOINT network: everything below is local files.
ENV CHROME_PATH=/usr/bin/chromium

WORKDIR /oracle
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund
COPY shot.mjs ./

# Render one case: render-one.sh <engine> <texfile> <display:0|1> <out.png>
COPY render-one.sh /usr/local/bin/render-one
RUN chmod +x /usr/local/bin/render-one
ENTRYPOINT ["render-one"]
