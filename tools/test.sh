#!/bin/bash
# swift test wrapper: this machine needs explicit dyld paths for XCTest bundles.
set -e
DEV=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer
cd "$(dirname "$0")/.."
DYLD_FRAMEWORK_PATH="$DEV/Library/Frameworks" DYLD_LIBRARY_PATH="$DEV/usr/lib" \
  swift test --enable-xctest "$@"
