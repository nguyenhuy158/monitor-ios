#!/bin/bash
# Build Monitor va dong goi .ipa KHONG ky vao build/. Sideloadly lo phan ky.
set -euo pipefail
cd "$(dirname "$0")"

xcodebuild -scheme Monitor -sdk iphoneos -configuration Release \
  -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > /tmp/monitor-build.log || { grep -E 'error:|BUILD FAILED' /tmp/monitor-build.log | head; exit 1; }

APP=build/dd/Build/Products/Release-iphoneos/Monitor.app
[ -d "$APP" ] || { echo "Monitor.app not found at $APP"; exit 1; }

rm -rf build/Payload && mkdir -p build/Payload
cp -R "$APP" build/Payload/
rm -f build/Monitor.ipa
(cd build && zip -qry Monitor.ipa Payload && rm -rf Payload)

echo "→ $(pwd)/build/Monitor.ipa"
