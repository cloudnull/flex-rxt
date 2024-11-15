#!/usr/bin/env bash

# Copyright 2024, Rackspace Technology, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
export LC_ALL=C.UTF-8
mkdir -p ~/.venvs

BASEDIR="$(dirname "$0")"
cd "${BASEDIR}" || error "Could not change to ${BASEDIR}"

source scripts/lib/functions.sh

set -e

success "Environment variables:"
env | grep -E '^(SUDO|RPC_|ANSIBLE_|GENESTACK_|K8S|CONTAINER_|OPENSTACK_|OSH_)' | sort -u

success "Installing base packages (git):"
apt update

DEBIAN_FRONTEND=noninteractive \
  apt-get -o "Dpkg::Options::=--force-confdef" \
          -o "Dpkg::Options::=--force-confold" \
          -qy install make git python3-pip python3-venv jq make > ~/genestack-base-package-install.log 2>&1

if [ $? -gt 1 ]; then
  error "Check for ansible errors at ~/genestack-base-package-install.log"
else
  success "Local base OS packages installed"
fi

# Install project dependencies
success "Installing genestack dependencies"
test -L "$GENESTACK_CONFIG" 2>&1 || mkdir -p "${GENESTACK_CONFIG}"

# Set config
test -f "$GENESTACK_CONFIG/provider" || echo "${K8S_PROVIDER}" > "${GENESTACK_CONFIG}/provider"
mkdir -p "$GENESTACK_CONFIG/inventory/group_vars" "${GENESTACK_CONFIG}/inventory/credentials"

# Copy default k8s config
PRODUCT_DIR="ansible/inventory/genestack"
if [ "$(find "${GENESTACK_CONFIG}/inventory" -name \*.yaml -o -name \*.yml 2>/dev/null | wc -l)" -eq 0 ]; then
  cp -r "${PRODUCT_DIR}"/* "${GENESTACK_CONFIG}/inventory"
fi

# Copy gateway-api example configs
test -d "$GENESTACK_CONFIG/gateway-api" || cp -a "${BASEDIR}/etc/gateway-api" "$GENESTACK_CONFIG"/

# Create venv and prepare Ansible
python3 -m venv "${HOME}/.venvs/genestack"
"${HOME}/.venvs/genestack/bin/pip" install pip --upgrade
source "${HOME}/.venvs/genestack/bin/activate" && success "Switched to venv ~/.venvs/genestack"
pip install -r "${BASEDIR}/requirements.txt" && success "Installed ansible package"
ansible-playbook "${BASEDIR}/scripts/get-ansible-collection-requirements.yml" \
  -e collections_file="${ANSIBLE_COLLECTION_FILE}" \
  -e user_collections_file="${USER_COLLECTION_FILE}"

source  "${BASEDIR}/scripts/genestack.rc"
success "Environment sourced per ${BASEDIR}/scripts/genestack.rc"

message "OpenStack Release: ${OPENSTACK_RELEASE}"
message "Target OS Distro: ${CONTAINER_DISTRO_NAME}:${CONTAINER_DISTRO_VERSION}"
message "Deploy Mulinode: ${OSH_DEPLOY_MULTINODE}"

# Ensure /etc/genestack exists
mkdir -p /etc/genestack

# Ensure each service from /opt/genestack/base-kustomize
# exists in /etc/genestack/kustomize and symlink
# base and aio.
base_source_dir="/opt/genestack/base-kustomize"
base_target_dir="/etc/genestack/kustomize"

for service in "$base_source_dir"/*; do
  service_name=$(basename "$service")
  if [ -d "$service" ] && [ -d "$service/base" ]; then
    if [ -d "$base_target_dir/$service_name" ]; then
      message "$base_target_dir/$service_name already exists"
    else
      message "Creating $base_target_dir/$service_name"
      mkdir -p "$base_target_dir/$service_name"
    fi
    if [ ! -L "$base_target_dir/$service_name/base" ]; then
      ln -s "$service/base" "$base_target_dir/$service_name/base"
      success "Created symlink for $service_name/base"
    fi
  else
    message "No base folder for $service_name, skipping..."
  fi
  if [ -d "$service" ] && [ -d "$service/aio" ]; then
    if [ ! -L "$base_target_dir/$service_name/aio" ]; then
      ln -s "$service/aio" "$base_target_dir/$service_name/aio"
      success "Created symlink for $service_name/aio"
    fi
  else
    message "No aio folder for $service_name, skipping..."
  fi
done

# Symlin /opt/genestack/kustomize.sh to 
# /etc/genestack/kustomize/kustomize.sh
ln -s $base_source_dir/base-kustomize/kustomize.sh $base_target_dir/kustomize/kustomize.sh

# Ensure kustomization.yaml exists in each
# service base/overlay directory
# Directory paths
overlay_target_dir="/etc/genestack/kustomize"

kustomization_content="apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
"

for service in "$overlay_target_dir"/*; do
  if [ -d "$service" ]; then
    overlay_path="${service}/overlay"

    if [ ! -d "$overlay_path" ]; then
      mkdir -p "$overlay_path"
      success "Creating overlay path $overlay_path"
    fi

    if [ ! -f "$overlay_path/kustomization.yaml" ]; then
      echo "$kustomization_content" > "$overlay_path/kustomization.yaml"
      success "Created overlay and kustomization.yaml for $(basename "$service")"
    else
      message "kustomization.yaml already exists for $(basename "$service"), skipping..."
    fi
  fi
done

# Copy base-helm-configs if it does not already exist
if [ ! -d "/etc/genestack/helm-configs" ]; then
  cp -r /opt/genestack/base-helm-configs /etc/genestack/helm-configs
  success "Copied helm-configs to /etc/genestack/"
else
  message "helm-configs already exists in /etc/genestack, skipping copy."
fi

# Copy manifests if it does not already exist
if [ ! -d "/etc/genestack/manifests" ]; then
  cp -r /opt/genestack/manifests /etc/genestack/
  success "Copied manifests to /etc/genestack/"
else
  message "manifests already exists in /etc/genestack, skipping copy."
fi

echo
