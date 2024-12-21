#!/bin/bash

# Copyright 2023-2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
APPINT_SA_BASE="${EXAMPLE_NAME}-"
APPINT_ENDPT=https://integrations.googleapis.com

source ./lib/utils.sh

check_auth_configs_and_maybe_delete() {
  local urlbase array
  urlbase="${APPINT_ENDPT}/v1/projects/${APPINT_PROJECT}/locations/${REGION}/authConfigs"
  CURL -X GET "$urlbase"
  if [[ ${CURL_RC} -ne 200 ]]; then
    printf "cannot inquire authConfigs"
    cat ${CURL_OUT}
    exit 1
  fi

  array=($(
    cat ${CURL_OUT} |
      grep "\"name\":" |
      sed -E 's/"name"://g' |
      sed -E 's/[", ]//g' |
      sed -E 's@projects/[^/]+/locations/[^/]+/authConfigs/@@'
  ))

  # check each one
  found=""
  for config_id in "${array[@]}"; do
    printf "Checking authConfig %s\n" "$config_id"
    CURL -X GET "${urlbase}/${config_id}"
    sa_here=($(
      cat ${CURL_OUT} |
        grep -A 3 "\"decryptedCredential\":" |
        grep -A 3 "\"serviceAccount\":" |
        sed -E 's/"serviceAccount"://g' |
        sed -E 's/[", ]//g'
    ))

    printf "  SA %s\n" "$sa_here"
    if beginswith "$APPINT_SA_BASE" "$sa_here"; then
      printf "  deleting authConfig %s\n" "$config_id"
      CURL -X DELETE "${urlbase}/${config_id}"
      if [[ ${CURL_RC} -ne 200 ]]; then
        printf "cannot inquire authConfigs"
        cat ${CURL_OUT}
        exit 1
      fi
    fi
  done
}

remove_iam_policy_bindings() {
  printf "Checking IAM Policy Bindings\n"

  IFS=',' read -r -a projects <<<"$APIGEE_PROJECTS"
  for k in "${!projects[@]}"; do
    APIGEE_PROJECT="${projects[k]}"
    printf "  Checking policy bindings for project %s...\n" "$APIGEE_PROJECT"

    # shellcheck disable=SC2207
    echo "--------------------" >>"$OUTFILE"
    echo "gcloud projects get-iam-policy $APIGEE_PROJECT --flatten=bindings[].members |
        grep ${EXAMPLE_NAME} | grep -v deleted: | sed -E 's/ +members: *//g'" >>"$OUTFILE"
    members=($(
      gcloud projects get-iam-policy "$APIGEE_PROJECT" --flatten="bindings[].members" |
        grep "${EXAMPLE_NAME}" | grep -v "deleted:" | sed -E 's/ +members: *//g'
    ))
    echo "${members[@]}" >>"$OUTFILE"
    if [[ ${#members[@]} -gt 0 ]]; then
      ROLES_OF_INTEREST=("roles/apigee.readOnlyAdmin")
      for role in "${ROLES_OF_INTEREST[@]}"; do
        printf "    Checking role %s\n" "$role"
        for member in "${members[@]}"; do
          printf "    Removing IAM binding for %s\n" "$member"
          echo "--------------------" >>"$OUTFILE"
          echo "gcloud projects remove-iam-policy-binding ${APIGEE_PROJECT} \
            --member=$member --role=$role --all" >>"$OUTFILE"
          gcloud projects remove-iam-policy-binding "${APIGEE_PROJECT}" \
            --member="$member" --role="$role" --all >>"$OUTFILE" 2>&1
        done
      done
    else
      printf "    No bindings for members of interest...\n"
    fi
  done
}

remove_service_accounts() {
  echo "Checking service accounts"
  echo "--------------------" >>"$OUTFILE"
  echo "gcloud iam service-accounts list --project ${APPINT_PROJECT} --format=value(email) | grep $APPINT_SA_BASE" >>"$OUTFILE"
  mapfile -t ARR < <(gcloud iam service-accounts list --project "${APPINT_PROJECT}" --format="value(email)" | grep "$APPINT_SA_BASE")
  if [[ ${#ARR[@]} -gt 0 ]]; then
    for sa in "${ARR[@]}"; do
      echo "Deleting service account ${sa}"
      echo "--------------------" >>"$OUTFILE"
      echo "gcloud --quiet iam service-accounts delete ${sa} --project ${APPINT_PROJECT}" >>"$OUTFILE"
      gcloud --quiet iam service-accounts delete "${sa}" --project "${APPINT_PROJECT}" >>"$OUTFILE" 2>&1
    done
  else
    printf "  No service accounts of interest...\n"
  fi
}

check_integrations_and_delete() {
  local arr
  printf "Looking at all integrations...\n"
  intarr=($(integrationcli integrations list -r "$REGION" -p "$APPINT_PROJECT" -t "$TOKEN" |
    grep "\"name\"" |
    sed -E 's/"name"://g' |
    tr -d ' "\t,' |
    sed -E 's@projects/[^/]+/locations/[^/]+/integrations/@@'))
  for a in "${intarr[@]}"; do
    #printf "  Checking $a...\n" "$a"
    if beginswith "$APPINT_SA_BASE" "$a"; then
      printf "  Checking $a...\n" "$a"
      echo "--------------------" >>"$OUTFILE"
      echo "Find versions of $a that are published." >>"$OUTFILE"

      verarr=($(integrationcli integrations versions list -n "$a" --filter "state=ACTIVE" -r "$REGION" -p "$APPINT_PROJECT" -t "$TOKEN" |
        grep "\"name\"" |
        sed -E 's/"name"://g' |
        tr -d ' "\t,' |
        sed -E 's@projects/[^/]+/locations/[^/]+/integrations/[^/]+/versions/@@'))
      for v in "${verarr[@]}"; do
        printf "    unpublishing version %s...\n" "$v"
        echo "--------------------" >>"$OUTFILE"
        echo "integrationcli integrations versions unpublish -n $a -v $v -r $REGION -p $APPINT_PROJECT" >>"$OUTFILE"
        integrationcli integrations versions unpublish -n "$a" -v "$v" -r "$REGION" -p "$APPINT_PROJECT" -t "$TOKEN" >>"$OUTFILE" 2>&1
      done
      # finally, delete it
      printf "    deleting %s...\n" "$a"
      echo "--------------------" >>"$OUTFILE"
      echo "integrationcli integrations delete -n $a -r $REGION -p $APPINT_PROJECT" >>"$OUTFILE"
      integrationcli integrations delete -n "$a" -r "$REGION" -p "$APPINT_PROJECT" -t "$TOKEN" >>"$OUTFILE" 2>&1
    fi
  done
}

# ====================================================================
OUTFILE=$(mktemp /tmp/appint-sample.cleanup.out.XXXXXX)
printf "\nLogging to %s\n" "$OUTFILE"
printf "timestamp: %s\n" "$TIMESTAMP" >>"$OUTFILE"
check_shell_variables

# it is necessary to get a token... if using curl or integrationcli for anything
TOKEN=$(gcloud auth print-access-token)
if [[ -z "$TOKEN" ]]; then
  printf "you must have the gcloud cli on your path to use this tool.\n"
  printf "you must have the gcloud cli on your path to use this tool.\n" >>"$OUTFILE"
  exit 1
fi

[[ -f .integration_name ]] && echo "integration name: $(<.integration_name)" >>"$OUTFILE"

googleapis_whoami
maybe_install_integrationcli
check_integrations_and_delete
check_auth_configs_and_maybe_delete
remove_iam_policy_bindings
remove_service_accounts

rm -f .integration_name
rm -f .trigger_id
rm -f .appint_sa_name

printf "\nAll the artifacts for this sample have now been removed.\n\n"
