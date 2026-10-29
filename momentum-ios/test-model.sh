#!/bin/sh
# Runs the pure-logic model checks without Xcode or a simulator.
# Requires the Swift toolchain (installed with Xcode or the Command Line Tools).
#
#   ./test-model.sh
#
set -e
cd "$(dirname "$0")"
cat Momentum/FocusModel.swift Tests/ModelTests.swift | swift -
