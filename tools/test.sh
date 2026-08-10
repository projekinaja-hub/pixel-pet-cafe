#!/bin/bash
# swift test wrapper: this machine needs explicit dyld paths for XCTest bundles.
#
# Builds OUTSIDE the project. ~/Documents is a Google Drive sync root (Drive's
# own config lists it), and DriveFS interferes with SQLite locking on
# .build/build.db. The symptom is
#
#     error: accessing build database ...: disk I/O error
#
# and the trap is that the run CONTINUES — against the previous binary. A pass
# or failure printed after that error is not about the code you just edited,
# which has twice sent someone debugging a change that never compiled.
#
# ~/Library/Caches is outside every sync root, so the database is never touched
# by Drive. Override with PPC_SCRATCH if you keep caches elsewhere.
set -e
DEV=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer
cd "$(dirname "$0")/.."
SCRATCH="${PPC_SCRATCH:-$HOME/Library/Caches/pixel-pet-cafe}"
DYLD_FRAMEWORK_PATH="$DEV/Library/Frameworks" DYLD_LIBRARY_PATH="$DEV/usr/lib" \
  swift test --enable-xctest --scratch-path "$SCRATCH" "$@"
