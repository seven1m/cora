#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
gem_root="$repo_root/test/gems"
minitest_version="5.27.0"
minitest_dir="$gem_root/minitest-$minitest_version"

mkdir -p "$gem_root"

if [ ! -d "$minitest_dir/.git" ]; then
    if [ -e "$minitest_dir" ]; then
        echo "error: $minitest_dir exists but is not a git checkout" >&2
        exit 1
    fi

    git clone --branch "v$minitest_version" --depth 1 \
        https://github.com/minitest/minitest.git "$minitest_dir"
fi

cd "$minitest_dir"
exec "$repo_root/build/bin/cora" --disable-gems -Ilib:test:. -e \
    'require "minitest/autorun"; (Dir["test/**/test_*.rb"] + Dir["test/**/*_test.rb"]).uniq.sort.each { |file| require file }'
