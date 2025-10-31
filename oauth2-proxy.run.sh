#!/bin/sh
if [ -z "$OAUTH2_PROXY_UPSTREAMS" ]; then
    echo "Error: OAUTH2_PROXY_UPSTREAMS must be set"
    exit 1
elif [ -z "$OAUTH2_PROXY_CLIENT_ID" ] ; then
    echo "Error: OAUTH2_PROXY_CLIENT_ID must be set"
    exit 1
elif [ -z "$OAUTH2_PROXY_CLIENT_SECRET" ] ; then
    echo "Error: OAUTH2_PROXY_CLIENT_SECRET must be set"
    exit 1
elif [ -z "$OAUTH2_PROXY_COOKIE_SECRET" ] ; then
    echo "Error: OAUTH2_PROXY_COOKIE_SECRET must be set"
    exit 1
elif [ -z "$PORT" ] ; then
    echo "Error: PORT must be set"
    exit 1
elif [ -z "$HOST_DOMAIN" ] ; then
    echo "Error: HOST_DOMAIN must be set"
    exit 1
fi

export OAUTH2_PROXY_HTTP_ADDRESS="0.0.0.0:${PORT}"
export OAUTH2_PROXY_REDIRECT_URL="${HOST_DOMAIN}/oauth2/callback"

exec /bin/oauth2-proxy
