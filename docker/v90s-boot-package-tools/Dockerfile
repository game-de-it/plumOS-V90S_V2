FROM debian:bookworm-slim

ARG DRAGONSECBOOT_URL=https://raw.githubusercontent.com/knulli-cfw/hdzero-goggle-tools/66703c7b12278857dad3483e9c9080758dca819d/dragonsecboot
ARG DRAGONSECBOOT_SHA256=36a42fc093ac082f2589a843407a1e460d1f4362ca321923521b755ac43aa094

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl python3 \
    && curl -fL "$DRAGONSECBOOT_URL" -o /usr/local/bin/dragonsecboot \
    && printf '%s  %s\n' "$DRAGONSECBOOT_SHA256" /usr/local/bin/dragonsecboot | sha256sum -c - \
    && chmod 0755 /usr/local/bin/dragonsecboot \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
