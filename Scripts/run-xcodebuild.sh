#!/usr/bin/env bash

set -u -o pipefail

label="${XCBUILD_LABEL:-xcodebuild}"
log="$(mktemp -t "irisin-${label//\//_}.XXXXXX.log")"
trap 'rm -f "$log"' EXIT

if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild "$@" 2>&1 \
        | perl -pe 's/\r/\n/g; s/\x08//g; s/\x04//g' \
        | tee "$log" \
        | xcbeautify --disable-colored-output --disable-logging
    pipeline_status=("${PIPESTATUS[@]}")
else
    xcodebuild "$@" 2>&1 \
        | perl -pe 's/\r/\n/g; s/\x08//g; s/\x04//g' \
        | tee "$log"
    pipeline_status=("${PIPESTATUS[@]}")
fi

xcode_status="${pipeline_status[0]}"
for status in "${pipeline_status[@]:1}"; do
    if [[ "$status" -ne 0 ]]; then
        echo "error: [$label] failed to process the xcodebuild output (exit=$status)" >&2
        exit 1
    fi
done

error_pattern='(^|[[:space:]])error:|^\*\* (BUILD|TEST|ARCHIVE|CLEAN|ANALYZE) FAILED \*\*|^Testing failed:|^Failing tests:'
# the build cache's own notice about a missing git lock is not a build error
ignored_pattern='skipping cache due to an error:'
errors_in_log=0
if grep -E "$error_pattern" "$log" | grep -Ev "$ignored_pattern" >/dev/null 2>&1; then
    errors_in_log=1
fi

if [[ "$xcode_status" -ne 0 || "$errors_in_log" -ne 0 ]]; then
    echo "error: [$label] xcodebuild failed (exit=$xcode_status, errors_in_log=$errors_in_log)" >&2
    if [[ "$errors_in_log" -ne 0 ]]; then
        grep -En "$error_pattern" "$log" | grep -Ev "$ignored_pattern" | head -40 >&2 || true
    fi
    # A compiler killed by the system or a failing script phase reports no
    # "error:" line at all; the failed command and the log tail are the only
    # trace, and the log is gone once this script exits.
    grep -En 'failed with a nonzero exit code|The following build commands failed' -A 12 "$log" | head -60 >&2 || true
    echo "--- last 80 lines of the build log ---" >&2
    tail -n 80 "$log" >&2
    if [[ "$xcode_status" -ne 0 ]]; then
        exit "$xcode_status"
    fi
    exit 1
fi
