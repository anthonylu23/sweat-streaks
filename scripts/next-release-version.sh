#!/usr/bin/env bash
set -euo pipefail

COMMIT="${1:-HEAD}"

git rev-parse --verify "$COMMIT^{commit}" >/dev/null

existing_tag="$(
  git tag --points-at "$COMMIT" |
    awk -F'[v.]' '
      /^v[0-9]+\.[0-9]+\.[0-9]+$/ {
        print $2 "." $3 "." $4 " " $0
      }
    ' |
    sort -t. -k1,1n -k2,2n -k3,3n |
    tail -n 1 |
    awk '{ print $2 }'
)"

if [[ -n "$existing_tag" ]]; then
  printf '%s\n' "$existing_tag"
  exit 0
fi

latest_tag="$(
  git tag --list 'v[0-9]*.[0-9]*.[0-9]*' |
    awk -F'[v.]' '
      /^v[0-9]+\.[0-9]+\.[0-9]+$/ {
        if (!found || $2 > major || ($2 == major && $3 > minor) || ($2 == major && $3 == minor && $4 > patch)) {
          major = $2
          minor = $3
          patch = $4
          found = 1
        }
      }
      END {
        if (found) {
          printf "v%d.%d.%d\n", major, minor, patch
        }
      }
    '
)"

if [[ -z "$latest_tag" ]]; then
  printf 'v0.1.0\n'
  exit 0
fi

version="${latest_tag#v}"
IFS='.' read -r major minor patch <<< "$version"
printf 'v%d.%d.%d\n' "$major" "$minor" "$((patch + 1))"
