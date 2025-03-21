#!/bin/bash

# Copyright 2023-2025 Google LLC
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
# shellcheck disable=SC2002
rand_string=$(cat /dev/urandom | LC_CTYPE=C tr -cd '[:alnum:]' | head -c 4 | tr '[:upper:]' '[:lower:]')
APPINT_SA="${EXAMPLE_NAME}-${rand_string}"
INTEGRATION_NAME="${EXAMPLE_NAME}-${rand_string}"
FULL_SA_EMAIL="${APPINT_SA}@${APPINT_PROJECT}.iam.gserviceaccount.com"
SA_REQUIRED_ROLES=("roles/apigee.readOnlyAdmin")
echo "$INTEGRATION_NAME" >./.integration_name

# Array of environment variable names to check
env_vars_to_check=(
  "APPINT_PROJECT"
  "APIGEE_PROJECTS"
  "REGION"
  "EXAMPLE_NAME"
  "EMAIL_ADDR"
  "SCHEDULE"
)

source ./lib/utils.sh

create_appint_auth_profile() {
  local urlbase
  urlbase="$1"
  CURL -X POST "${urlbase}" -H 'Content-Type: application/json; charset=utf-8' \
    -d '{
  "displayName": "service-account-for-'${INTEGRATION_NAME}'",
  "decryptedCredential": {
    "credentialType": "SERVICE_ACCOUNT",
    "serviceAccountCredentials": {
      "serviceAccount": "'${FULL_SA_EMAIL}'",
      "scope": "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}'
  cat ${CURL_OUT}
  # grep for the id, we will need it later
}

check_auth_configs_and_maybe_create() {
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
  # just for diagnostics purposes, show them
  printf "\nAuth Configs:\n"
  for config_id in "${array[@]}"; do
    printf "%s\n" "$config_id"
  done

  # check each one
  AUTH_CONFIG=""
  for config_id in "${array[@]}"; do
    CURL -X GET "${urlbase}/${config_id}"
    sa_here=($(
      cat ${CURL_OUT} |
        grep -A 3 "\"decryptedCredential\":" |
        grep -A 3 "\"serviceAccount\":" |
        sed -E 's/"serviceAccount"://g' |
        sed -E 's/[", ]//g'
    ))
    if [[ "$sa_here" == "$FULL_SA_EMAIL" ]]; then
      AUTH_CONFIG = "$config_id"
    fi
  done

  if [[ -z "$AUTH_CONFIG" ]]; then
    # create the required authConfig
    create_appint_auth_profile "$urlbase"
    AUTH_CONFIG=$(cat ${CURL_OUT} |
      grep "\"name\":" |
      sed -E 's/"name"://g' |
      sed -E 's/[", ]//g' |
      sed -E 's@projects/[^/]+/locations/[^/]+/authConfigs/@@')
    printf "created authConfig %s\n" "$AUTH_CONFIG"
  else
    printf "using authConfig ID %s\n" "$AUTH_CONFIG"
  fi
}

check_and_maybe_create_sa() {
  local ROLE AVAILABLE_ROLES
  printf "Checking Service account (%s)...\n" "${FULL_SA_EMAIL}"
  echo "--------------------" >>"$OUTFILE"
  echo "It is ok if this command fails..." >>"$OUTFILE"
  echo "gcloud iam service-accounts describe ${FULL_SA_EMAIL} --project=$APPINT_PROJECT --quiet" >>"$OUTFILE"
  if gcloud iam service-accounts describe "${FULL_SA_EMAIL}" --project="$APPINT_PROJECT" --quiet >>"$OUTFILE" 2>&1; then
    echo "--------------------" >>"$OUTFILE"
    printf "That service account already exists.\n"
    printf "Checking for required roles....\n"
    IFS=',' read -r -a projects <<<"$APIGEE_PROJECTS"
    for k in "${!projects[@]}"; do
      APIGEE_PROJECT=${projects[k]}
      printf "  Checking project %s....\n" "$APIGEE_PROJECT"

      # shellcheck disable=SC2076
      AVAILABLE_ROLES=($(gcloud projects get-iam-policy "${APIGEE_PROJECT}" \
        --flatten="bindings[].members" \
        --filter="bindings.members:${FULL_SA_EMAIL}" |
        grep -v deleted | grep -A 1 members | grep role | sed -e 's/role: //'))

      for j in "${!SA_REQUIRED_ROLES[@]}"; do
        ROLE=${SA_REQUIRED_ROLES[j]}
        printf "    check the role %s...\n" "$ROLE"
        if ! [[ ${AVAILABLE_ROLES[*]} =~ "${ROLE}" ]]; then
          printf "Adding role %s...\n" "${ROLE}"
          echo "--------------------" >>"$OUTFILE"
          echo "gcloud projects add-iam-policy-binding ${APIGEE_PROJECT} \
                 --condition=None \
                 --member=serviceAccount:${FULL_SA_EMAIL} \
                 --role=${ROLE} --quiet" >>"$OUTFILE"
          if gcloud projects add-iam-policy-binding "${APIGEE_PROJECT}" \
            --condition=None \
            --member="serviceAccount:${FULL_SA_EMAIL}" \
            --role="${ROLE}" --quiet >>"$OUTFILE" 2>&1; then
            printf "Success\n"
          else
            printf "\n*** FAILED\n\n"
            printf "You must manually run:\n\n"
            echo "gcloud projects add-iam-policy-binding ${APIGEE_PROJECT} \
                 --condition=None \
                 --member=serviceAccount:${FULL_SA_EMAIL} \
                 --role=${ROLE}"
          fi
        else
          printf "      That role is already set.\n"
        fi
      done
    done

  else
    echo "--------------------" >>"$OUTFILE"
    echo "$APPINT_SA" >./.appint_sa_name
    printf "Creating Service account (%s)...\n" "${FULL_SA_EMAIL}"
    echo "gcloud iam service-accounts create $APPINT_SA --project=$APPINT_PROJECT --quiet" >>"$OUTFILE"
    gcloud iam service-accounts create "$APPINT_SA" --project="$APPINT_PROJECT" --quiet >>"$OUTFILE" 2>&1

    printf "There can be errors if all these changes happen too quickly, so we need to sleep a bit...\n"
    sleep 12

    IFS=',' read -r -a projects <<<"$APIGEE_PROJECTS"
    for k in "${!projects[@]}"; do
      APIGEE_PROJECT=${projects[k]}
      printf "Granting access for that service account to project %s...\n" "$APIGEE_PROJECT"
      for j in "${!SA_REQUIRED_ROLES[@]}"; do
        ROLE=${SA_REQUIRED_ROLES[j]}
        printf "  Adding role %s...\n" "${ROLE}"
        echo "--------------------" >>"$OUTFILE"
        echo "gcloud projects add-iam-policy-binding ${APIGEE_PROJECT} \
               --condition=None \
               --member=serviceAccount:${FULL_SA_EMAIL} \
               --role=${ROLE} --quiet" >>"$OUTFILE"
        if gcloud projects add-iam-policy-binding "${APIGEE_PROJECT}" \
          --condition=None \
          --member="serviceAccount:${FULL_SA_EMAIL}" \
          --role="${ROLE}" --quiet >>"$OUTFILE" 2>&1; then
          printf "Success\n"
        else
          printf "\n*** FAILED\n\n"
          printf "You must manually run:\n\n"
          echo "gcloud projects add-iam-policy-binding ${APIGEE_PROJECT} \
                 --condition=None \
                 --member=serviceAccount:${FULL_SA_EMAIL} \
                 --role=${ROLE}"

        fi
      done
    done
  fi
}

replace_keywords_in_template() {
  local TMP SCHED_PLUS
  TMP=$(mktemp /tmp/appint-setup.tmp.out.XXXXXX)
  sed "s/@@AUTH_CONFIG@@/${AUTH_CONFIG}/g" $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE
  # the following is needed only if running the integration as this SA.
  #sed "s/@@FULL_SA_EMAIL@@/${FULL_SA_EMAIL}/g" $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE
  sed "s/@@EMAIL_ADDR@@/${EMAIL_ADDR}/g" $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE
  sed "s/@@APIGEE_PROJECTS@@/${APIGEE_PROJECTS}/g" $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE
  sed "s/@@INTEGRATION_NAME@@/${INTEGRATION_NAME}/g" $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE
  sed "s/@@SCHEDULE@@/${SCHEDULE}/g" $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE
  #   4+21+*+*+*
  SCHED_PLUS="${SCHEDULE// /+}"
  sed "s/@@SCHED_PLUS@@/${SCHED_PLUS}/g" $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE
  rm -f $TMP
}

replace_content_files_in_template() {
  local TMP
  TMP=$(mktemp /tmp/appint-setup.tmp.out.XXXXXX)

  # This slurps in a content file and inserts it into the appropriate place in
  # the template. For now, content files include various JavaScripts and the
  # email text body template.

  jq --arg content "$(cat ./content/processExpiry.js)" \
    '(.taskConfigs[] | select(.task == "JavaScriptTask" and .taskId == "17") | .parameters).script.value.stringValue = $content' $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE

  jq --arg content "$(cat ./content/initializeState.js)" \
    '(.taskConfigs[] | select(.task == "JavaScriptTask" and .taskId == "21") | .parameters).script.value.stringValue = $content' $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE

  jq --arg content "$(cat ./content/constructAdminEmail.js)" \
    '(.taskConfigs[] | select(.task == "JavaScriptTask" and .taskId == "24") | .parameters).script.value.stringValue = $content' $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE

  jq --arg content "$(cat ./content/admin-email.htm)" \
    '(.taskConfigs[] | select(.task == "EmailTask" and .taskId == "18") | .parameters).TextBody.value.stringValue = $content' $INTEGRATION_FILE >$TMP && cp $TMP $INTEGRATION_FILE

  rm -f $TMP
}

# ====================================================================
printf "\nThis is the setup for the App Int Cert Expiry report sample.\n\n"
OUTFILE=$(mktemp /tmp/appint-sample.setup.out.XXXXXX)
printf "Logging to %s\n\n" "$OUTFILE"

printf "timestamp: %s\n" "$TIMESTAMP" >>"$OUTFILE"
check_shell_variables "${env_vars_to_check[@]}"
check_required_commands jq curl gcloud grep sed tr

printf "\nrandom seed: %s\n" "$rand_string"
printf "random seed: %s\n" "$rand_string" >>"$OUTFILE"

TOKEN=$(gcloud auth print-access-token)
if [[ -z "$TOKEN" ]]; then
  printf "Could not get a token with the gcloud cli. See logs in %s\n" "$OUTFILE"
  printf "Could not get a token with the gcloud cli. See logs in %s\n" "$OUTFILE" >>"$OUTFILE"
  exit 1
fi

googleapis_whoami
maybe_install_integrationcli
check_and_maybe_create_sa
check_auth_configs_and_maybe_create

# Replace all the keywords
INTEGRATION_FILE="${EXAMPLE_NAME}-${rand_string}.json"
cp ./content/cert-expiry-checker-multiorg-v5-template.json "$INTEGRATION_FILE"
chmod 644 "$INTEGRATION_FILE"

replace_keywords_in_template
replace_content_files_in_template

echo "--------------------" >>"$OUTFILE"
echo "integrationcli integrations create -f $INTEGRATION_FILE -n $INTEGRATION_NAME -p $APPINT_PROJECT -r $REGION" >>"$OUTFILE"
integrationcli integrations create -f "$INTEGRATION_FILE" -n "$INTEGRATION_NAME" -p "$APPINT_PROJECT" -r "$REGION" -t "$TOKEN" >>"$OUTFILE" 2>&1

# If we try to list versions straightaway, sometimes it does not work
sleep 2

snapshotarr=($(integrationcli integrations versions list -n "$INTEGRATION_NAME" -r "$REGION" -p "$APPINT_PROJECT" -t "$TOKEN" | jq '.integrationVersions[].snapshotNumber'))

if [[ ${#snapshotarr[@]} -gt 0 ]]; then
  snapshot="${snapshotarr[0]}"
  printf "The Integration has been created. Now let's wait a bit before publishing snapshot %s.\n\n" "$snapshot"
  sleep 5
  echo "--------------------" >>"$OUTFILE"
  echo "integrationcli integrations versions publish -n $INTEGRATION_NAME -s $snapshot --latest=false -r $REGION -p $APPINT_PROJECT" >>"$OUTFILE"

  if ! integrationcli integrations versions publish -n "$INTEGRATION_NAME" -s "$snapshot" --latest=false -r "$REGION" -p "$APPINT_PROJECT" -t "$TOKEN" >>"$OUTFILE" 2>&1; then
    printf "The publish attempt failed. For diagnostics, check the output file $OUTFILE \n"
    exit 1
  fi

  printf "The Integration has been published. Now let's wait a bit for it to become available.\n\n"
  sleep 16
  printf "Now trying to invoke it...\n"

  trigger_id=$(grep cron_trigger "$INTEGRATION_FILE" |
    sed -E 's/"triggerId"://g' |
    tr -d ' "\t,')
  echo "$trigger_id" >./.trigger_id

  invoke_one "$trigger_id" "$INTEGRATION_NAME"

  console_link="https://console.cloud.google.com/integrations/edit/$INTEGRATION_NAME/locations/$REGION?project=$APPINT_PROJECT"
  printf "\nTo view the uploaded integration on Cloud Console, open this link:\n    %s\n\n" "$console_link"

  invoke_one "$trigger_id" "$INTEGRATION_NAME" "just-show-command"
  printf "\n\n"

else
  printf "Failed retrieving versions of the Integration we just created. Check the log file?\n"
  printf "==> %s\n" "$OUTFILE"
  exit 1
fi
