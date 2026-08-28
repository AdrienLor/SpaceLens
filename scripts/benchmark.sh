#!/bin/sh

set -eu

SPACELENS_BENCHMARK=1 ./scripts/test.sh --filter ScannerPerformanceTests/testSyntheticTreeThroughput
