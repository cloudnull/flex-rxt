#!/bin/bash

# Directory to check for YAML files
CONFIG_DIR="/etc/genestack/helm-configs/postgres-operator"

pushd /opt/genestack/submodules/postgres-operator/charts/postgres-operator || exit

# Base helm command setup
HELM_CMD="helm upgrade --install postgres-operator ./postgres-operator \
  --namespace=postgres-system \
  --create-namespace \
  --timeout 120m"

# Add the base overrides file
HELM_CMD+=" -f /opt/genestack/base-helm-configs/postgres-operator/postgres-operator-helm-overrides.yaml"

# Check if YAML files exist in the specified directory
if compgen -G "${CONFIG_DIR}/*.yaml" > /dev/null; then
    # Append all YAML files from the directory to the helm command
    for yaml_file in "${CONFIG_DIR}"/*.yaml; do
        HELM_CMD+=" -f ${yaml_file}"
    done
fi

# Run the helm command
eval "${HELM_CMD}"
echo "${HELM_CMD}"

popd || exit
