# Deployment on Lgeo4

## CI base

```yaml
deploy-job:      # This job runs in the deploy stage.
  stage: deploy  # It only runs when *both* jobs in the test stage complete successfully.
  tags: [prod]
  environment: production
  variables:
    MIX_ENV: prod
  only:
    - master
  script:
    - echo "Preparing application deployment..."
    - mix deps.get --only prod && mix compile # && mix assets.deploy
    - mix release --overwrite
    
    - echo "Copying artefact to staging location..."
    - rsync -avz --delete _build /opt/stac_api_staging/artefacts/
    - echo "$CI_JOB_ID" >> /opt/stac_api_staging/artefacts/.updated
    - sudo -u stacapi /opt/stac_api_staging/bin/deploy_stac_api_staging.sh

  artifacts:
    paths:
      - _build
    expire_in: 4 hour

```


## systemd

`/etc/systemd/system/stac_api_ex.service`

```
[Unit]
# /etc/systemd/system/stac_api_ex.service
Description=stac_api_ex

[Service]
User=stacapi
EnvironmentFile=/home/stacapi/run/.env
Environment=LANG=en_US.utf8
WorkingDirectory=/home/stacapi/run
ExecStart=/home/stacapi/run/_build/prod/rel/stac_api/bin/stac_api start
ExecStop=/home/stacapi/run/_build/prod/rel/stac_api/bin/stac_api stop
KillMode=process
Restart=on-failure
LimitNOFILE=65535
SyslogIdentifier=stac_api_ex

[Install]
WantedBy=multi-user.target
```

## staging from Gitlab runner output

`/opt/stac_api_staging/bin/deploy_stac_api_staging.sh`

```
#!/bin/bash

ARTEFACT_BASE=/opt/stac_api_staging/artefacts/_build
DEPLOY_TARGET=/home/stacapi/run/

echo "running deploy of staging"

echo "stopping app"

sudo /usr/bin/systemctl stop stac_api_staging.service

echo "syncing files"

rsync --delete -avz $ARTEFACT_BASE $DEPLOY_TARGET

echo "running migration"

source $DEPLOY_TARGET/.env
export DATABASE_URL
export MIX_ENV
export SECRET_KEY_BASE
export STAC_BASE_URL

_build/prod/rel/stac_api/bin/migrate

echo "restarting app"

sudo /usr/bin/systemctl start stac_api_staging.service
```