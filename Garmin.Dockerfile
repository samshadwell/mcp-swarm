# syntax=docker/dockerfile:1.19.0
ARG ASTRAL_VERSION=0.9.5
ARG GARMIN_MCP_COMMIT_SHA=f767bf35ca9d627de397328d4984a7e7ecb6ce0d
ARG MCP_PROXY_VERSION=0.10.0
ARG OAUTH_PROXY_VERSION=7.12.0
ARG PYTHON_IMAGE_VERSION=3.13-trixie

# Yoink some binaries from the uv and oauth2-proxy base images
FROM ghcr.io/astral-sh/uv:${ASTRAL_VERSION} AS uv
FROM quay.io/oauth2-proxy/oauth2-proxy:v${OAUTH_PROXY_VERSION} AS oauth2-proxy

# Main container begin
FROM python:${PYTHON_IMAGE_VERSION}
ARG GARMIN_MCP_COMMIT_SHA
ARG MCP_PROXY_VERSION

COPY --from=uv /uv /uvx /bin/
COPY --from=oauth2-proxy /bin/oauth2-proxy /bin/

# Install https://github.com/sparfenyuk/mcp-proxy
RUN uv tool install mcp-proxy==${MCP_PROXY_VERSION}

# Upstream is a bit more suspect here, so pin a specific commit
RUN mkdir /app
ADD --checksum=sha256:46fe83d307750dbb39f371adf4ed39fda71ec8fd0f944ea72da00427d3d1f7d1 \
    https://github.com/Taxuspt/garmin_mcp/archive/${GARMIN_MCP_COMMIT_SHA}.tar.gz /tmp/
RUN tar -C /app -xzf /tmp/${GARMIN_MCP_COMMIT_SHA}.tar.gz && \
    mv /app/garmin_mcp-${GARMIN_MCP_COMMIT_SHA} /app/garmin_mcp

WORKDIR /app/garmin_mcp
ENV UV_COMPILE_BYTECODE=1
RUN uv sync --locked --no-dev

ENV PORT=8080
CMD ["sh", "-c", "exec uvx mcp-proxy --allow-origin=* --pass-environment --port=$PORT --host=0.0.0.0 uv run garmin-mcp"]

# TODO: Use s6 for process management
