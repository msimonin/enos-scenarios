#!/usr/bin/env bash

# Runner for the second wan experiment.
# Aim: TODO

set -x
set -e

# Experience Parameters
LATENCIES='0 10 25 50 100'
LOSSES='0 0.1 1 10 25'
ENOS_GIT='https://github.com/msimonin/enos.git'
ENOS_REF='chameleon-openstack-provider-clean'

EXP_HOME=$(pwd)
ENOS_HOME="${EXP_HOME}/enos"
WORKLOAD="${EXP_HOME}/workload"

trap 'exit' SIGINT

sudo apt-get update
sudo apt-get install -y git virtualenv python-dev
# Get Enos and setup the Virtual environment (if none)
if [ ! -d "${ENOS_HOME}" ]; then
  git clone "${ENOS_GIT}" --depth 1 --branch "${ENOS_REF}" "${ENOS_HOME}" 
fi

pushd "${ENOS_HOME}"
virtualenv --python=python2.7 venv
. venv/bin/activate
pip install git+https://github.com/openstack/python-blazarclient.git
pip install -r requirements.txt
popd

. "${ENOS_HOME}/venv/bin/activate"

# Run the experiment a first time to fill cache
pushd "${ENOS_HOME}"
python -m enos.enos up -f "${EXP_HOME}/reservation.yml" 
python -m enos.enos os
# chameleon related
# this variable conflict with those required on the under-cloud
unset OS_TENANT_ID
python -m enos.enos init
python -m enos.enos bench --workload="${WORKLOAD}"
popd

# Run experiments with different latencies 
for LTY in $LATENCIES; do for LOSS in $LOSSES; do
  ansible disco/bench -i ${ENOS_HOME}/current/multinode -m command -a 'rm -rf /root/rally_home'
  OLD_RES_DIR=$(readlink "${ENOS_HOME}/current")
  NEW_RES_DIR="${EXP_HOME}/cpt10-lat${LTY}-los${LOSS}"

  # Construct the repository for the new experiment
  cp -r "${OLD_RES_DIR}" "${NEW_RES_DIR}"

  # Update Enos environment with the location of the new experiment
  sed -i 's|'${OLD_RES_DIR}'|'${NEW_RES_DIR}'|' "${NEW_RES_DIR}/env"

  # Set the latency and loss of the reservation.yml
  sed -i 's|default_delay: .\+|default_delay: '${LTY}'ms|' "${EXP_HOME}/reservation.yml"
  sed -i 's|default_loss: .\+|default_loss: '${LOSS}'%|'   "${EXP_HOME}/reservation.yml"

  # Run Enos, setup latency, make test and backup results
  pushd "${ENOS_HOME}"
  ENV=${NEW_RES_DIR}
  python -m enos.enos tc --env="${ENV}"
  python -m enos.enos tc --test --env="${ENV}"
  python -m enos.enos bench --workload="${WORKLOAD}" --env="${ENV}"
  python -m enos.enos backup --env="${ENV}"
  popd
done; done
