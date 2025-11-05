# syntax=docker/dockerfile:1.19.0
ARG ASTRAL_VERSION=0.9.5
ARG GARMIN_MCP_COMMIT_SHA=f2fc5d4180c3d27da3930c90a9e7398db53ce114
ARG MCP_PROXY_VERSION=0.10.0
ARG PYTHON_IMAGE_VERSION=3.13-slim-trixie

# Yoink some binaries from the uv base image
FROM ghcr.io/astral-sh/uv:${ASTRAL_VERSION} AS uv

FROM python:${PYTHON_IMAGE_VERSION} AS builder
ARG GARMIN_MCP_COMMIT_SHA
ARG MCP_PROXY_VERSION

COPY --from=uv /uv /uvx /bin/

# Install https://github.com/sparfenyuk/mcp-proxy
RUN uv tool install mcp-proxy==${MCP_PROXY_VERSION}

# Upstream is a bit more suspect here, so pin a specific commit
RUN mkdir /app
# TODO: Switch this back to upstream once PR is merged: https://github.com/Taxuspt/garmin_mcp/pull/11
ADD --checksum=sha256:d95082ed3947a470596b95caf94607e2bef69064ad7a6f46f125da51cdcd2159 \
    https://github.com/samshadwell/garmin_mcp/archive/${GARMIN_MCP_COMMIT_SHA}.tar.gz /tmp/
RUN tar -C /app -xzf /tmp/${GARMIN_MCP_COMMIT_SHA}.tar.gz && \
    rm /tmp/${GARMIN_MCP_COMMIT_SHA}.tar.gz && \
    mv /app/garmin_mcp-${GARMIN_MCP_COMMIT_SHA} /app/garmin_mcp

WORKDIR /app/garmin_mcp
ENV UV_COMPILE_BYTECODE=1
RUN uv sync --locked --no-dev

# Runtime stage
FROM python:${PYTHON_IMAGE_VERSION}

COPY --from=uv /uv /uvx /bin/

# Copy installed tools and app from builder
COPY --from=builder /root/.local /root/.local
COPY --from=builder /app/garmin_mcp /app/garmin_mcp

WORKDIR /app/garmin_mcp

ENV PORT=8080
ENV PATH="/root/.local/bin:$PATH"

HEALTHCHECK --interval=10s --timeout=2s --start-period=15s --start-interval=1s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:$PORT/status').read()"

CMD ["sh", "-c", "exec uvx mcp-proxy --allow-origin=* --pass-environment --port=$PORT --host=0.0.0.0 uv run garmin-mcp"]
