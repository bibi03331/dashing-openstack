#!/bin/bash

my_dir="$(dirname "$0")"
source $my_dir/credentials.sh

TENANT_NAME=$1

REQUEST="{\"auth\": {\"tenantId\":\"$TENANT_NAME\", \"passwordCredentials\": {\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}}}"
RAW_TOKEN=`curl -s -d "$REQUEST" -H "Content-type: application/json" "http://$CONTROLLER_HOST:5000/v2.0/tokens"`
TOKEN=`echo $RAW_TOKEN | python -c "import sys; import json; tok = json.loads(sys.stdin.read()); print tok['access']['token']['id'];"`

curl -s -H "X-Auth-Token: $TOKEN" http://$CONTROLLER_HOST:8774/v2/$1/limits | python -mjson.tool
