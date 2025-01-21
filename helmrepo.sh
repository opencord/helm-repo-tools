#!/usr/bin/env bash

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

# helmrepo.sh
# creates or updates a helm repo for publishing on the guide website
# Reference: https://github.com/helm/charts/blob/master/test/repo-sync.sh

set -eu -o pipefail

##-------------------##
##---]  GLOBALS  [---##
##-------------------##

# when not running under Jenkins, use current dir as workspace
WORKSPACE=${WORKSPACE:-.}

# directory to compare against, doesn't need to be present
OLD_REPO_DIR="${OLD_REPO_DIR:-cord-charts-repo}"
NEW_REPO_DIR="${NEW_REPO_DIR:-chart_repo}"

PUBLISH_URL="${PUBLISH_URL:-charts.opencord.org}"

## -----------------------------------------------------------------------
## Intent: Dispay called function with given output
## -----------------------------------------------------------------------
function func_echo()
{
    echo "** ${FUNCNAME[1]}: $*"
    return
}

## -----------------------------------------------------------------------
## Intent: Display given text and exit with shell error status.
## -----------------------------------------------------------------------
function error()
{
    echo -e "** ${BASH_SOURCE[0]##*/}::${FUNCNAME[1]} ERROR: $*"
    exit 1
}

## -----------------------------------------------------------------------
## Intent: Detect pre-existing versioned packages.
## -----------------------------------------------------------------------
function check_packages()
{
    local dir="$1"; shift

    readarray -t package_paths < <(find "${dir}" -name '*.tgz' -print)
    declare -p package_paths

    # ---------------------------------------------
    # Check for versioned package collision.
    # ---------------------------------------------
    for package_path in "${package_paths[@]}";
    do
        package="${package_path##*/}" # basename

        if [ -f "${OLD_REPO_DIR}/${package}" ]; then
            echo
            echo "PACKAGE: $package"
            /bin/ls -l "$package_path"
            /bin/ls -l "${OLD_REPO_DIR}/${package}"
            error "Package: ${package} with same version already exists in ${OLD_REPO_DIR}"
        fi
    done

    return
}

## -----------------------------------------------------------------------
## Intent: Gather a list of Chart.yaml files from the filesystem.
## -----------------------------------------------------------------------
function get_chart_yaml()
{
    local dir="$1"    ; shift
    declare -n ref=$1 ; shift

    readarray -t _charts < <(find "$dir" -name Chart.yaml -print | sort)
    ref=("${_charts[@]}")
    return
}

## -----------------------------------------------------------------------
## Intent: Given a helm chart line extract and return *version.
## -----------------------------------------------------------------------
function getVersion()
{
    # shellcheck disable=SC2178
    local -n ref=$1; shift # declare -A
    local line="$1"; shift

    [[ -v debug ]] && func_echo "LINE: $line"

    # version : x.y.z
    readarray -d':' -t _fields < <(printf '%s' "$line")

    local key="${_fields[0]}"
    local val="${_fields[1]}"
    # shellcheck disable=SC2004
    ref[$key]="$val"

    return
}

## -----------------------------------------------------------------------
## Intent: Update helm package dependencies
## -----------------------------------------------------------------------
function helm_deps_update()
{
    local dest="$1"; shift    # helm --destination

    if [[ -v dry_run ]]; then
        func_echo "helm package --dependency-update --destination $dest $chartdir"
    else
        helm package --dependency-update --destination "$dest" "$chartdir"
    fi
    return
}

## -----------------------------------------------------------------------
## Intent: Update helm package index
## -----------------------------------------------------------------------
function helm_index_publish()
{
    local repo_dir="$1"; shift    # helm --destination

    if [[ -v dry_run ]]; then
        func_echo "helm repo index $repo_dir --url https://${PUBLISH_URL}"

    elif [[ -v no_publish ]]; then
        func_echo "[SKIP] helm publishing due to --no-publish"

    else
        ## ------------------------------------------------
        ## Helm updates are guarded by jenkins
        ## Revision control should reinforce that assertion
        ## ------------------------------------------------
        case "$USER" in
            jenkins)
                helm repo index "$repo_dir" --url https://"${PUBLISH_URL}"
                ;;
            *)
                func_echo "[SKIP] helm publishing due to ($USER != jenkins)"
                ;;
        esac
    fi

    return
}

## -----------------------------------------------------------------------
## Intent: Update helm package index
## -----------------------------------------------------------------------
function helm_index_merge()
{
    local old_repo="$1" ; shift
    local new_repo="$1" ; shift

    declare -a cmd=()
    cmd+=('helm' 'repo' 'index')
    cmd+=('--url' "https://${PUBLISH_URL}")
    cmd+=('--merge' "${old_repo}/index.yaml" "$new_repo")

    if [[ -v dry_run ]]; then
        func_echo "${cmd[@]}"
    else
        "${cmd[@]}"
    fi
    return
}

## -----------------------------------------------------------------------
## Intent: Given a Chart.yaml file path return test directory where stored
## -----------------------------------------------------------------------
function chart_path_to_test_dir()
{
    local val="$1"    ; shift

    # shellcheck disable=SC2178
    declare -n ref=$1 ; shift # indirect var

    val="${val%/Chart.yaml}"  # dirname: prune /Chart.yaml
    val="${val##*/}"          # basename: test directory

    # shellcheck disable=SC2034,SC2178
    ref="$val"                # Return value to caller
    return
}

## -----------------------------------------------------------------------
## Intent: Given Chart.yaml files create a new indexed chart repository
## -----------------------------------------------------------------------
function create_helm_repo_new()
{
    local repo_dir="$1"; shift # NEW_REPO_DIR
    local work_dir="$1"; shift # WORKSPACE

    echo "Creating new helm repo: ${repo_dir}"

    declare -a charts=()
    get_chart_yaml "$work_dir" charts

    local chart
    for chart in "${charts[@]}";
    do
        echo
        func_echo "Chart.yaml: $chart"

        chartdir=''
        chart_path_to_test_dir "$chart" chartdir
        func_echo " Chart.dir: $chartdir"

        helm_deps_update "${repo_dir}"
    done

    helm_index_publish "${repo_dir}"

    return
}

## -----------------------------------------------------------------------
## Intent: Compare version stings extracted from Chart.yaml delta.
##   o attribute version:x.y.z must be changed to enable change
##     detection and chart loading.
## -----------------------------------------------------------------------
function validate_changes()
{
    local chart="$1"; shift
    # shellcheck disable=SC2178
    local -n ref=$1; shift

    local msg
    ## -------------------------------------------
    ## Validation logic: all keys collected exist
    ## Chart version must change to enable loading
    ## -------------------------------------------
    local key0
    for key0 in "${!ref[@]}";
    do
        local key="${key0:1}"
        # shellcheck disable=SC2034
        local old="-${key}"
        local new="+${key}"

        ## Key/val paris are diff deltas:
        ##   -version : 1.2.3
        ##   +version : 4.5.6
        if [[ ! -v ref['-version'] ]]; then
            msg='Modify version to publish chart changes'
        elif [[ ! -v ref["$new"] ]]; then
            msg="Failed to detect +${key} change in attributes"
        else
            continue
        fi

        local -i failed=1
        cat <<ERR

** -----------------------------------------------------------------------
** Chart dir: $chartdir
** Chart.yml: $chart
**     Error: $msg
** -----------------------------------------------------------------------
ERR
        func_echo "$(declare -p versions | sed -e 's/\[/\n\[/g')"
    done

    if [[ -v failed ]]; then
        false
    else
        true
    fi

    return
}

##----------------##
##---]  MAIN  [---##
##----------------##

while [ $# -gt 0 ]; do
    arg="$1"; shift

    case "$arg" in
        -*debug)      declare -g -i debug=1      ;;
        -*dry*)       declare -g -i dry_run=1    ;;
        -*no-publish) declare -g -i no_publish=1 ;;
        -*help)
            cat <<EOH
Usage: $0
  --debug       Enable debug mode
  --dry-run     Simulate helm calls
EOH
            ;;

        -*) echo "[SKIP] unknown switch [$arg]" ;;
        *) echo "[SKIP] unknown argument [$arg]" ;;
    esac
done


echo "# helmrepo.sh, using helm: $(helm version -c) #"

# create and clean NEW_REPO_DIR
mkdir -p "${NEW_REPO_DIR}"
rm -f "${NEW_REPO_DIR}"/*

# if OLD_REPO_DIR doesn't exist, generate packages and index in NEW_REPO_DIR
if [ ! -d "${OLD_REPO_DIR}" ]
then
    create_helm_repo_new "$NEW_REPO_DIR" "$WORKSPACE"
    echo
    echo "# helmrepo.sh Success! Generated new repo index in ${NEW_REPO_DIR}"

else
    # OLD_REPO_DIR exists, check for new charts and update only with changes
    echo "Found existing helm repo: ${OLD_REPO_DIR}, attempting update"

    # Loop and create chart packages, only if changed
    declare -a charts=()
    get_chart_yaml "$WORKSPACE" charts

    for chart in "${charts[@]}";
    do
        echo
        func_echo "Chart.yaml: $chart"

        chartdir=''
        chart_path_to_test_dir "$chart" chartdir
        func_echo " Chart.dir: $chartdir"

        # See if chart version changed from previous HEAD commit
        readarray -t chart_yaml_diff < <(git diff -p HEAD^ -- "$chart")

        if [[ ! -v chart_yaml_diff ]]; then
            echo "Chart unchanged, not packaging: '${chartdir}'"

            # -------------------------------------------------------------------
            # Assumes that helmlint.sh and chart_version_check.sh have been run
            # pre-merge, which ensures that all charts are valid and have their
            # version updated in Chart.yaml
            # -------------------------------------------------------------------
        elif [ ${#chart_yaml_diff} -gt 0 ]; then
            declare -A versions=()
            for line in "${chart_yaml_diff[@]}";
            do
                [[ -v debug ]] && func_echo "$line"
                
                # foo=${string#"$prefix"}
                line="${line%\#*}"            # Snip comments
                line="${line//[[:blank:]]}"   # Prune whitespace

                case "$line" in
                    # appVersion: "1.0.3"
                    # version: 1.2.3
                    [-+]*[vV]ersion:*) getVersion versions "$line" ;;
                esac
            done

            # ---------------------------------------------------------------
            # [TODO] -- versions['-version']='version string change required'
            # ---------------------------------------------------------------
            # version: string change initiates a delta forcing helm to update.
            # Should it be required by every checkin ?  For ex: release may
            # accumulate several version edits then publish all when finished.
            #
            # Danger would be chart changes are not published/tested when
            # a dev forgets to update the chart version string.
            # ---------------------------------------------------------------

            ## ---------------------------------------------------------------
            ## Check for required version change and stray attribute deletions
            ## We are comparing diff output [-+]verison : x.y
            ## +{key} indicates a required attribute exists and was modified
            ## ---------------------------------------------------------------
            if ! validate_changes "$chart" versions; then
                declare -g -i failed=1
                continue
            fi

            # Always query, version string may not have changed
            readarray -t ver < <(grep -oP '(?<= version: )\S+' "$chart")
            declare -p ver

            echo "Detected new version of chart ${chartdir}, creating package: ${ver[*]}"

            helm_deps_update "${NEW_REPO_DIR}"

        else
            echo "Chart unchanged, not packaging: '${chartdir}'"
        fi
    done

    check_packages "$NEW_REPO_DIR"

    ## -----------------------------------------------------------------------
    ## -----------------------------------------------------------------------
    # only update index when new charts are added
    if [ ${#package_paths[@]} -gt 0 ]; then

        # Create updated index.yaml (new version created in NEW_REPO_DIR)
        helm_index_merge "${OLD_REPO_DIR}" "${NEW_REPO_DIR}"

        # move over packages and index.yaml
        mv "${NEW_REPO_DIR}"/*.tgz "${OLD_REPO_DIR}/"
        mv "${NEW_REPO_DIR}/index.yaml" "${OLD_REPO_DIR}/index.yaml"

        echo "# helmrepo.sh Success! Updated existing repo index in ${OLD_REPO_DIR}"

    else
        echo "# helmrepo.sh Success! No new charts added."
    fi
fi

exit 0

# [EOF]
