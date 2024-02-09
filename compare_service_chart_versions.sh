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

# compare_service_chart_version.sh
# Prints out the service version in the chart and the source repo
# Useful for seeing how far behind the chart versions are

REPODIR=${REPODIR:-~/cord}
DEBUG=${DEBUG:-false}

for CHART in "$REPODIR"/helm-charts/xos-services/*
do
    APPVERSION=$( awk '/^appVersion:/ { print $2 }' "$CHART/Chart.yaml" )
    SVCNAME=$( basename "$CHART")

    case $SVCNAME in
        volt)
            SVCNAME=olt-service
            ;;
        kubernetes)
            SVCNAME=kubernetes-service
            ;;
    esac

    if [ ! -e "$REPODIR/orchestration/xos-services/$SVCNAME/VERSION" ]
    then
        $DEBUG && echo "WARN: $SVCNAME has no VERSION file"
        continue
    fi

    SVCVERSION=$( cat "$REPODIR/orchestration/xos-services/$SVCNAME/VERSION" )
    echo $SVCNAME
    echo "  Chart:   $APPVERSION"
    echo "  Service: $SVCVERSION"
done
