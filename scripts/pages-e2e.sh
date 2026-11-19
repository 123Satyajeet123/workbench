#!/bin/sh
# Runs the browser-page host (swift test builds it) as a real process against a scratch store.
set -e
cd "$(dirname "$0")/../Packages/WorkbenchCore"
swift test --filter PageHostProcessTests 2>&1 | grep -q "Test run with 1 test in 1 suite passed" && echo PASS || echo FAIL
