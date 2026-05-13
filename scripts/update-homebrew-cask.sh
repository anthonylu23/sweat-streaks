#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: scripts/update-homebrew-cask.sh X.Y.Z SHA256 path/to/sweat-streaks.rb" >&2
  exit 64
fi

VERSION="$1"
SHA256="$2"
CASK_PATH="$3"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like 0.1.0" >&2
  exit 64
fi

if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "SHA-256 must be 64 lowercase hex characters" >&2
  exit 64
fi

if [[ ! -f "$CASK_PATH" ]]; then
  echo "Missing cask file: $CASK_PATH" >&2
  exit 66
fi

ruby - "$VERSION" "$SHA256" "$CASK_PATH" <<'RUBY'
version, sha256, path = ARGV
content = File.read(path)

version_count = 0
sha_count = 0

content = content.gsub(/(\bversion\s+")[^"]+(")/) do
  version_count += 1
  "#{$1}#{version}#{$2}"
end

content = content.gsub(/(\bsha256\s+")[0-9a-f]{64}(")/) do
  sha_count += 1
  "#{$1}#{sha256}#{$2}"
end

unless version_count == 1
  warn "Expected exactly one version stanza, found #{version_count}"
  exit 1
end

unless sha_count == 1
  warn "Expected exactly one sha256 stanza, found #{sha_count}"
  exit 1
end

File.write(path, content)
RUBY
