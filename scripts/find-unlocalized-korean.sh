#!/bin/bash
# find-unlocalized-korean.sh
# Swift 소스에서 String(localized:)로 감싸지 않은 한국어 하드코딩 문자열을 검출합니다.

set -euo pipefail

ROOT_DIR="${1:-.}"

rg -n --pcre2 '"[^"]*[가-힣][^"]*"' --type swift "$ROOT_DIR" \
  | grep -v 'String(localized:' \
  | grep -v "defaultValue:" \
  | grep -v "comment: " \
  | grep -v "NSLocalizedString"
