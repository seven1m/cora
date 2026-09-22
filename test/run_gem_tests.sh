#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
gem_root="$repo_root/test/gems"
minitest_version="5.27.0"
minitest_dir="$gem_root/minitest-$minitest_version"
tilt_version="2.8.0"
tilt_dir="$gem_root/tilt-$tilt_version"
rack_version="3.2.7"
rack_dir="$gem_root/rack-$rack_version"
rack_session_version="2.1.1"
rack_session_dir="$gem_root/rack-session-$rack_session_version"
minitest_global_expectations_version="1.0.2"
minitest_global_expectations_dir="$gem_root/minitest-global_expectations-$minitest_global_expectations_version"

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
"$repo_root/build/bin/cora" --disable-gems -Ilib:test:. -e \
    'require "minitest/autorun"; (Dir["test/**/test_*.rb"] + Dir["test/**/*_test.rb"]).uniq.sort.each { |file| require file }'

if [ ! -d "$tilt_dir/.git" ]; then
    if [ -e "$tilt_dir" ]; then
        echo "error: $tilt_dir exists but is not a git checkout" >&2
        exit 1
    fi

    git clone --branch "v$tilt_version" --depth 1 \
        https://github.com/jeremyevans/tilt.git "$tilt_dir"
fi

cd "$tilt_dir"
"$repo_root/build/bin/cora" --disable-gems \
    -I"$minitest_dir/lib:lib:test:." test/all.rb

if [ ! -d "$minitest_global_expectations_dir/.git" ]; then
    if [ -e "$minitest_global_expectations_dir" ]; then
        echo "error: $minitest_global_expectations_dir exists but is not a git checkout" >&2
        exit 1
    fi

    git clone --branch "$minitest_global_expectations_version" --depth 1 \
        https://github.com/jeremyevans/minitest-global_expectations.git \
        "$minitest_global_expectations_dir"
fi

if [ ! -d "$rack_dir/.git" ]; then
    if [ -e "$rack_dir" ]; then
        echo "error: $rack_dir exists but is not a git checkout" >&2
        exit 1
    fi

    git clone --branch "v$rack_version" --depth 1 \
        https://github.com/rack/rack.git "$rack_dir"
fi

cd "$rack_dir"
"$repo_root/build/bin/cora" --disable-gems \
    -I"$minitest_dir/lib:$minitest_global_expectations_dir/lib:lib:test:." -e \
    'require "helper"
     (Dir["test/**/*_test.rb"] + Dir["test/**/spec_*.rb"]).uniq.sort.each do |file|
       require file
     end'

if [ ! -d "$rack_session_dir/.git" ]; then
    if [ -e "$rack_session_dir" ]; then
        echo "error: $rack_session_dir exists but is not a git checkout" >&2
        exit 1
    fi

    git clone --branch "v$rack_session_version" --depth 1 \
        https://github.com/rack/rack-session.git "$rack_session_dir"
fi

cd "$rack_session_dir"
"$repo_root/build/bin/cora" --disable-gems \
    -I"$minitest_dir/lib:$minitest_global_expectations_dir/lib:$rack_dir/lib:lib:test:." -e \
    '(Dir["test/**/test_*.rb"] + Dir["test/**/spec_*.rb"]).uniq.sort.each { |file| require file }'
