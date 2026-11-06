#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/nido-finance-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
swiftc Shared/FinanceSheet.swift Tests/FinanceSheetTests.swift -o "$test_dir/finance-tests"
"$test_dir/finance-tests"
swiftc Shared/FinanceSheet.swift Shared/ExpenseCapture.swift Tests/ExpenseCaptureTests.swift -o "$test_dir/capture-tests"
"$test_dir/capture-tests"
