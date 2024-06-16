#!/bin/bash
version=$(curl -u "${GITHUB_ACTOR}:${GITHUB_TOKEN}" -fsSL "https://api.github.com/repos/engels74/tgraph-bot-source/releases/latest" | jq -re .tag_name) || exit 1
[[ -z ${version} ]] && exit 0
[[ ${version} == null ]] && exit 0
json=$(cat VERSION.json)
jq --sort-keys \
    --arg version "${version}" \
    '.version = $version' <<< "${json}" | tee VERSION.json
