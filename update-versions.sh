#!/bin/bash
version=$(curl -fsSL "https://api.github.com/repos/engels74/tgraph-bot-source/commits/main" | jq -re .sha) || exit 1
[[ -z ${version} ]] && exit 0
[[ ${version} == null ]] && exit 0
json=$(cat meta.json)
jq --sort-keys \
    --arg version "${version//v/}" \
    '.version = $version' <<< "${json}" | tee meta.json
