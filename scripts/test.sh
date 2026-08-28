#!/bin/sh

set -eu

test_root="${SPACELENS_TEST_ROOT:-/tmp/SpaceLensSwiftPM}"

export CLANG_MODULE_CACHE_PATH="$test_root/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$test_root/module-cache"

exec swift test \
    --disable-sandbox \
    --scratch-path "$test_root/build" \
    --cache-path "$test_root/cache" \
    --config-path "$test_root/config" \
    --security-path "$test_root/security" \
    --disable-dependency-cache \
    --manifest-cache local \
    "$@"
