# syntax=docker/dockerfile:1.19.0
# A very thin wrapper around the base image. Mostly exists to adapt GCP's
# required PORT to the OAuth2 Proxy's PORT args. Also provides some defaults.
ARG OAUTH2_PROXY_VERSION=7.12.0

# Use Alpine base image since we need sh
FROM quay.io/oauth2-proxy/oauth2-proxy:v${OAUTH2_PROXY_VERSION}-alpine

# Copy rather than mount to simplify deployment
COPY oauth2-proxy.authed-emails.txt /app/authed-emails.txt
COPY oauth2-proxy.run.sh /app/oauth2-proxy.run.sh

ENV PORT=8080
ENV OAUTH2_PROXY_PROVIDER="google"
ENV OAUTH2_PROXY_SCOPE="email"
ENV OAUTH2_PROXY_SKIP_PROVIDER_BUTTON="true"
ENV OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE="/app/authed-emails.txt"

ENTRYPOINT [ "/app/oauth2-proxy.run.sh" ]
