#!/bin/bash
OCP_RELEASE=quay.io/openshift-release-dev/ocp-release:4.18.41-x86_64

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
BIN_PATH=${SCRIPTPATH}/bin
TEMP_PATH=${SCRIPTPATH}/temp
ASSETS_PATH=${SCRIPTPATH}/assets
LOCAL_SECRET_JSON=${ASSETS_PATH}/pull_secret.json

if [[ -z ${LOCAL_SECRET_JSON} ]]
then
  echo "You need to place the pull_secret.json file inside the ${ASSETS_PATH} folder"
  exit 1
fi

# This needs to happen from the mirrored release
${BIN_PATH}/oc adm release extract --registry-config $LOCAL_SECRET_JSON --command=openshift-baremetal-install --to ${BIN_PATH} $OCP_RELEASE
