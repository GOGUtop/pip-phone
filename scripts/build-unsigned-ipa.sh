#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="SillyTavernNativePiP.xcodeproj"
TARGET="SillyTavernNativePiP"
PRODUCT="SillyTavernNativePiP"
BUILD_ROOT="$ROOT_DIR/build"
OUTPUT_DIR="$ROOT_DIR/output"

rm -rf "$BUILD_ROOT" "$OUTPUT_DIR"
mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR"

echo "== Xcode =="
xcodebuild -version

echo "== Build unsigned iPhone app =="
# Some recent Xcode/CI combinations can print ** BUILD SUCCEEDED ** yet still
# return status 65 during the final validation phase of an unsigned device build.
# Do not let `set -e` abort before we can inspect the produced .app.
set +e
xcodebuild \
  -project "$PROJECT" \
  -target "$TARGET" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  SYMROOT="$BUILD_ROOT" \
  OBJROOT="$BUILD_ROOT/obj" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  clean build
XCODE_STATUS=$?
set -e

APP_PATH="$BUILD_ROOT/Release-iphoneos/${PRODUCT}.app"
APP_EXECUTABLE="$APP_PATH/$PRODUCT"

if [[ $XCODE_STATUS -ne 0 ]]; then
  echo "WARNING: xcodebuild returned status $XCODE_STATUS." >&2
  echo "Checking whether Xcode nevertheless produced a complete unsigned app..." >&2
fi

if [[ ! -d "$APP_PATH" || ! -f "$APP_PATH/Info.plist" || ! -f "$APP_EXECUTABLE" ]]; then
  echo "ERROR: a complete app was not produced at $APP_PATH" >&2
  echo "xcodebuild exit status: $XCODE_STATUS" >&2
  find "$BUILD_ROOT" -maxdepth 4 -type d -name '*.app' -print || true
  exit "${XCODE_STATUS:-1}"
fi

echo "App product found: $APP_PATH"
/usr/bin/file "$APP_EXECUTABLE" || true
if [[ $XCODE_STATUS -ne 0 ]]; then
  echo "Continuing because the expected .app and executable exist."
fi

echo "== Package IPA =="
PAYLOAD_ROOT="$BUILD_ROOT/ipa"
rm -rf "$PAYLOAD_ROOT"
mkdir -p "$PAYLOAD_ROOT/Payload"
cp -R "$APP_PATH" "$PAYLOAD_ROOT/Payload/"

IPA_PATH="$OUTPUT_DIR/${PRODUCT}-unsigned.ipa"
(
  cd "$PAYLOAD_ROOT"
  /usr/bin/zip -qry "$IPA_PATH" Payload
)

# Also make the raw .app available for signing/debugging tools.
APP_ZIP="$OUTPUT_DIR/${PRODUCT}-app.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_ZIP"

if command -v shasum >/dev/null 2>&1; then
  (cd "$OUTPUT_DIR" && shasum -a 256 *.ipa *.zip > SHA256SUMS.txt)
fi

echo "Built: $IPA_PATH"
ls -lh "$OUTPUT_DIR"
