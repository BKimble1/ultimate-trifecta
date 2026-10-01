#!/usr/bin/env bash
# Quick compile check: prints only script errors.
cd "$(dirname "$0")/.."
tools/gd.sh --headless --path game --import >/dev/null 2>&1
tools/gd.sh --headless --path game -s res://tests/run_tests.gd -- test_compile 2>&1 | grep -E 'SCRIPT ERROR|Parse Error|Compile Error|at: GDScript|tests,|FAIL' | grep -v 'Failed to compile depended' | head -${1:-40}
