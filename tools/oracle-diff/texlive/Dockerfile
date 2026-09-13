# LuaTeX-lineage oracle image: pdflatex -> pdftoppm -r 300. Base digest
# resolved 2026-09-13 (see webshot Dockerfile for the refresh recipe).
# pdflatex renders in Computer Modern — the design Latin Modern remakes —
# so this oracle shares the LM/CM outlines with ZaTeX's fixture render.
FROM docker.io/library/debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      texlive-latex-base \
      texlive-latex-recommended \
      texlive-fonts-recommended \
      poppler-utils \
 && rm -rf /var/lib/apt/lists/*
# texlive-fonts-recommended carries the rsfs metrics behind mathrsfs
# (\mathscr in the fonts case); without it pdflatex dies in mktextfm.

# Render one case: render-one <texfile> <display:0|1> <out.png>
COPY render-one.sh /usr/local/bin/render-one
RUN chmod +x /usr/local/bin/render-one
ENTRYPOINT ["render-one"]
