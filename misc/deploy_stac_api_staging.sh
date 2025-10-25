#!/bin/bash
#
# /opt/stac_api_staging/bin/deploy_stac_api_staging.sh

ARTEFACT_BASE=/opt/stac_api_staging/artefacts/_build
DEPLOY_TARGET=/home/stacapi/run/

echo "running deploy of staging"

echo "stopping app"

sudo /usr/bin/systemctl stop stac_api_ex.service

echo "syncing files"

rsync --delete -avz $ARTEFACT_BASE $DEPLOY_TARGET

echo "running migration"

source $DEPLOY_TARGET/.env
export DATABASE_URL
export MIX_ENV
export SECRET_KEY_BASE

_build/prod/rel/stac_api/bin/migrate

echo "restarting app"

sudo /usr/bin/systemctl start stac_api_ex.service