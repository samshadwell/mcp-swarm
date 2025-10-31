#!/bin/sh
if [ -z "$PORT" ] ; then
    echo "Error: PORT must be set"
    exit 1
elif [ -z "$OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE" ] ; then
    echo "Error: OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE must be set"
    exit 1
elif [ -z "$OAUTH2_PROXY_CLIENT_ID" ] ; then
    echo "Error: OAUTH2_PROXY_CLIENT_ID must be set"
    exit 1
elif [ -z "$OAUTH2_PROXY_CLIENT_SECRET_FILE" ] ; then
    echo "Error: OAUTH2_PROXY_CLIENT_SECRET_FILE must be set"
    exit 1
elif [ -z "$OAUTH2_PROXY_COOKIE_SECRET_FILE" ] ; then
    echo "Error: OAUTH2_PROXY_COOKIE_SECRET_FILE must be set"
    exit 1
elif [ -z "$OAUTH2_PROXY_REDIRECT_URL" ] ; then
    echo "Error: OAUTH2_PROXY_REDIRECT_URL must be set"
    exit 1
elif [ -z "$OAUTH2_PROXY_UPSTREAMS" ]; then
    echo "Error: OAUTH2_PROXY_UPSTREAMS must be set"
    exit 1
fi

export OAUTH2_PROXY_HTTP_ADDRESS="0.0.0.0:${PORT}"

exec /bin/oauth2-proxy
