#!/usr/bin/env bash

# Copyright 2018-present Open Networking Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# helmrepo.sh
# creates or updates a helm repo for publishing on the guide website
# Reference: https://github.com/helm/charts/blob/master/test/repo-sync.sh

set -eu -o pipefail

echo "# helmrepo.sh, using helm: $(helm version -c) #"

# when not running under Jenkins, use current dir as workspace
WORKSPACE=${WORKSPACE:-.}

# branch to compare against, defaults to master
GERRIT_BRANCH=${GERRIT_BRANCH:-opencord/master}

# directory to compare against, doesn't need to be present
OLD_REPO_DIR="${OLD_REPO_DIR:-cord-charts-repo}"
NEW_REPO_DIR="${NEW_REPO_DIR:-chart_repo}"

GERRIT_BRANCH="${GERRIT_BRANCH:-$(git symbolic-ref --short HEAD)}"
PUBLISH_URL="${PUBLISH_URL:-charts.opencord.org}"

# create and clean NEW_REPO_DIR
mkdir -p "${NEW_REPO_DIR}"
rm -f "${NEW_REPO_DIR}"/*

# if OLD_REPO_DIR doesn't exist, generate packages and index in NEW_REPO_DIR
if [ ! -d "${OLD_REPO_DIR}" ]
then
  echo "Creating new helm repo: ${NEW_REPO_DIR}"

  while IFS= read -r -d '' chart
  do
    chartdir=$(dirname "${chart#${WORKSPACE}/}")
    helm package --dependency-update --destination "${NEW_REPO_DIR}" "${chartdir}"

  done < <(find "${WORKSPACE}" -name Chart.yaml -print0)

  helm repo index "${NEW_REPO_DIR}" --url https://"${PUBLISH_URL}"
  echo "# helmrepo.sh Success! Generated new repo index in ${NEW_REPO_DIR}"

else
  # OLD_REPO_DIR exists, check for new charts and update only with changes
  echo "Found existing helm repo: ${OLD_REPO_DIR}, attempting update"

  # Loop and create chart packages, only if changed
  while IFS= read -r -d '' chart
  do
    chartdir=$(dirname "${chart#${WORKSPACE}/}")

    # See if chart version changed from previous HEAD commit
    chart_yaml_diff=$(git diff -p HEAD^ "${chartdir}/Chart.yaml")

    if [ -n "$chart_yaml_diff" ]
    then
      # assumes that helmlint.sh and chart_version_check.sh have been run
      # pre-merge, which ensures that all charts are valid and have their
      # version updated in Chart.yaml
      new_version_string=$(echo "$chart_yaml_diff" | awk '/^\+version:/ { print $2 }')
      echo "New version of chart ${chartdir}, creating package: ${new_version_string//+version:/}"
      helm package --dependency-update --destination "${NEW_REPO_DIR}" "${chartdir}"
    else
      echo "Chart unchanged, not packaging: '${chartdir}'"
    fi

  done < <(find "${WORKSPACE}" -name Chart.yaml -print0)

  # Check for collisions between old/new packages
  while IFS= read -r -d '' package_path
  do
    package=$(basename "${package_path}")

    if [ -f "${OLD_REPO_DIR}/${package}" ]
    then
      echo "# helmrepo.sh Failure! Package: ${package} with same version already exists in ${OLD_REPO_DIR}"
      exit 1
    fi
  done < <(find "${NEW_REPO_DIR}" -name '*.tgz' -print0)

  # only update index if new charts are added
  if ls "${NEW_REPO_DIR}"/*.tgz > /dev/null 2>&1;
  then
    # Create updated index.yaml (new version created in NEW_REPO_DIR)
    helm repo index --url "https://${PUBLISH_URL}" --merge "${OLD_REPO_DIR}/index.yaml" "${NEW_REPO_DIR}"

    # move over packages and index.yaml
    mv "${NEW_REPO_DIR}"/*.tgz "${OLD_REPO_DIR}/"
    mv "${NEW_REPO_DIR}/index.yaml" "${OLD_REPO_DIR}/index.yaml"

    echo "# helmrepo.sh Success! Updated existing repo index in ${OLD_REPO_DIR}"

  else
    echo "# helmrepo.sh Success! No new charts added."
  fi
fi

exit 0
