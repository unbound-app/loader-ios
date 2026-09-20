#!/bin/bash

set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
archive_path=${1:?}
include_path=${2:?}
source_path="$project_root/vendor/libffi"
build_path=$(mktemp -d "${TMPDIR:-/tmp}/unbound-libffi.XXXXXX")

cleanup() {
    rm -rf "$build_path"
}

trap cleanup EXIT

git -C "$source_path" archive --format=tar HEAD | tar -x -C "$build_path"
cd "$build_path"
autoreconf -i -f -v

/usr/bin/python3 - <<'PY'
import collections
import runpy
import subprocess

module = runpy.run_path('generate-darwin-source-and-headers.py')
headers = collections.defaultdict(set)
module['copy_files']('src', 'darwin_common/src', pattern='*.c')
module['copy_files']('include', 'darwin_common/include', pattern='*.h')

for arch in ('arm64', 'arm64e'):
    platform = type(f'ios_device_{arch}_platform', (module['ios_device_arm64_platform'],), {})
    platform.arch = arch
    platform.target = f'{arch}-apple-ios'
    platform.directory = f'darwin_ios_{arch}'
    module['copy_src_platform_files'](platform)
    module['build_target'](platform, headers)
    subprocess.check_call(['make', '-C', f'build_iphoneos-{arch}', '-j4', 'libffi.la'])
PY

mkdir -p "$(dirname "$archive_path")" "$include_path"
xcrun lipo -create \
    "$build_path/build_iphoneos-arm64/.libs/libffi.a" \
    "$build_path/build_iphoneos-arm64e/.libs/libffi.a" \
    -output "$archive_path"
cp "$build_path/build_iphoneos-arm64/include/ffi.h" "$include_path/ffi.h"
cp "$build_path/build_iphoneos-arm64/include/ffitarget.h" "$include_path/ffitarget.h"
cp "$build_path/build_iphoneos-arm64/fficonfig.h" "$include_path/fficonfig.h"
