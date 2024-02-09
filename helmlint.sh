#!/usr/bin/env bash
# -----------------------------------------------------------------------
# Copyright 2018-2024 Open Networking Foundation (ONF) and the ONF Contributors
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
# -----------------------------------------------------------------------
# helmlint.sh
# run `helm lint` on all helm charts that are found
# -----------------------------------------------------------------------

# [TODO] use set -e else errors can fly under the radar
set +e -o pipefail

declare -g iam="${0##*/}"

# verify that we have helm installed
command -v helm >/dev/null 2>&1 || { echo "helm not found, please install it" >&2; exit 1; }

echo "# helmlint.sh, using helm version: $(helm version -c --short) #"

# Collect success/failure, and list/types of failures
fail_lint=0
declare -a failed_deps=()
declare -a failed_lint=()
declare -a failed_reqs=()

# when not running under Jenkins, use current dir as workspace
WORKSPACE=${WORKSPACE:-.}

# cleanup repos if `clean` option passed as parameter
# update then move set -u to set [+-]e -o pipefail above
# if [[ $# -gt 0 ]] && [[ "$1" = 'clean' ]]; then <--- allow set -u
if [ "$1" = "clean" ]
then
    echo "Removing any downloaded charts"
    find "${WORKSPACE}" -type d -name 'charts' -exec rm -rf {} \;
fi

# now that $1 is checked, error on undefined vars
set -u

# loop on result of 'find -name Chart.yaml'
while IFS= read -r -d '' chart
do
    chartdir=$(dirname "${chart}")

    echo "Checking chart: $chartdir"

    # update dependencies (if any)
    if ! helm dependency update "${chartdir}";
    then
        fail_lint=1
        failed_deps+=("${chartdir}")
    fi

    # lint the chart (with values.yaml if it exists)
    if [ -f "${chartdir}/values.yaml" ]; then
        helm lint --strict --values "${chartdir}/values.yaml" "${chartdir}"
    else
        helm lint --strict "${chartdir}"
    fi

    rc=$?
    if [[ $rc != 0 ]]; then
        fail_lint=1
        failed_lint+=("${chartdir}")
    fi

    # -----------------------------------------------------------------------
    # check that requirements are available if they're specified
    # how is this check different than helm dep up above ?
    # -----------------------------------------------------------------------
    # later helm versions allow requirements.yaml to be defined directly in
    # Chart.yaml so an explicit check may no longer be needed.
    #
    # Should we err when requirements.yaml detected to cleanup old code ?
    # -----------------------------------------------------------------------
    if [ -f "${chartdir}/requirements.yaml" ];
    then
        echo "Chart has requirements.yaml, checking availability"
        if ! helm dependency update "${chartdir}"; then
            fail_lint=1
            failed_reqs+=("${chartdir}")
        fi

        # remove charts dir after checking for availability, as this chart might be
        # required by other charts in the next loop
        rm -rf "${chartdir}/charts"
    fi

done < <(find "${WORKSPACE}" -name Chart.yaml -print0)

if [[ $fail_lint != 0 ]]; then
    cat <<EOM

** -----------------------------------------------------------------------
** ${iam}: Errors Detected
** -----------------------------------------------------------------------
EOM

    #   echo "Charts that failed to lint: $failed_lint"
    if [ ${#failed_lint[@]} -gt 0 ]; then
        echo "Charts that failed to lint:"
        for chart in "${failed_lint[@]}";
        do
            echo "    $chart"
        done
    fi

    if [ ${#failed_deps[@]} -gt 0 ]; then
        echo "Charts that failed helm dependency update:"
        for chart in "${failed_deps[@]}";
        do
            echo "    $chart"
        done
    fi

    if [ ${#failed_reqs[@]} -gt 0 ]; then
        echo "Charts with failures in requirements.yaml:"
        for chart in "${failed_reqs[@]}";
        do
            echo "    $chart"
        done
    fi

    echo
    echo "See Also:"
    echo "  o https://wiki.opennetworking.org/display/VOLTHA/make+lint-helm"

    echo
    exit 1
fi

echo "# helmlint.sh Success! - all charts linted and have valid requirements.yaml #"

exit 0
