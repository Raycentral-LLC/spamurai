#!/usr/bin/env bash
# Builds a minimal sing-box core (libbox) for the Pro DNS tunnel:
#   scripts/build_libbox.sh  -> Frameworks/Libbox.xcframework (dynamic)
#
# Upstream SagerNet/sing-box (GPLv3), no forks or patches. Only the TUN stack is compiled in —
# the tunnel just answers DNS (DoH upstream) and blocks listed domains.
# Requirements: Go, Xcode.
set -euo pipefail

VERSION="1.14.4"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/sing-box"
IOS_MIN="17.0"

if [[ ! -d "$WORK" ]]; then
  git -c advice.detachedHead=false clone --depth 1 --branch "v$VERSION" \
    https://github.com/SagerNet/sing-box.git "$WORK"
fi
cd "$WORK"

# gomobile shells out to gobind, which go install puts in GOPATH/bin.
export PATH="$(go env GOPATH)/bin:$PATH"
make lib_install # SagerNet's gomobile fork, required by libbox

TAGS="with_gvisor,badlinkname,tfogo_checklinkname0,grpcnotrace"
LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=$VERSION -checklinkname=0 -s -w -buildid="

out="$WORK/apple-build"
rm -rf "$out" && mkdir -p "$out"
gomobile bind -v -o "$out/static/Libbox.xcframework" -target ios,iossimulator \
  -libname=box -tags-not-macos=with_low_memory -iosversion="$IOS_MIN" -trimpath \
  -ldflags "$LDFLAGS" -tags "$TAGS" ./experimental/libbox

# make_dynamic <static slice dir> <sdk> "<archs>" <out dir> → prints framework path.
# gomobile emits a static library; relink it as one dynamic framework that the app embeds
# and the extension loads, instead of a full copy in each.
make_dynamic() {
  local slice="$1" sdk="$2" archs="$3" dest="$4"
  local src="$slice/Libbox.framework" fw="$dest/Libbox.framework" lib suffix="" thin=()
  lib=$(readlink -f "$src/Libbox")
  mkdir -p "$fw/Headers" "$fw/Modules"
  cp "$src"/Headers/*.h "$fw/Headers/"
  printf 'framework module "Libbox" {\n  header "Libbox.h"\n  export *\n}\n' > "$fw/Modules/module.modulemap"

  [[ "$sdk" == iphonesimulator ]] && suffix="-simulator"
  for arch in $archs; do
    lipo "$lib" -thin "$arch" -output "$dest/libbox-$arch.a" 2>/dev/null || cp "$lib" "$dest/libbox-$arch.a"
    xcrun -sdk "$sdk" clang -target "$arch-apple-ios$IOS_MIN$suffix" -dynamiclib \
      -Wl,-all_load "$dest/libbox-$arch.a" -o "$dest/Libbox-$arch" \
      -install_name @rpath/Libbox.framework/Libbox \
      -framework Foundation -framework Security -framework UIKit -framework SystemConfiguration \
      -framework CoreFoundation -framework Network -lresolv
    strip -x "$dest/Libbox-$arch"
    thin+=("$dest/Libbox-$arch")
  done
  lipo -create "${thin[@]}" -output "$fw/Libbox"

  local platform=iPhoneOS
  [[ "$sdk" == iphonesimulator ]] && platform=iPhoneSimulator
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Libbox</string>
  <key>CFBundleIdentifier</key><string>com.raycentral.spamurai.Libbox</string>
  <key>CFBundleName</key><string>Libbox</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>$IOS_MIN</string>
</dict>
</plist>
PLIST
  echo "$fw"
}

device=$(make_dynamic "$out/static/Libbox.xcframework/ios-arm64" iphoneos "arm64" "$out/device")
sim=$(make_dynamic "$out/static/Libbox.xcframework/ios-arm64_x86_64-simulator" iphonesimulator "arm64 x86_64" "$out/sim")
xcodebuild -create-xcframework -framework "$device" -framework "$sim" -output "$out/Libbox.xcframework" >/dev/null

mkdir -p "$ROOT/Frameworks"
rm -rf "$ROOT/Frameworks/Libbox.xcframework"
cp -R "$out/Libbox.xcframework" "$ROOT/Frameworks/"
echo "libbox (sing-box $VERSION) → Frameworks/Libbox.xcframework"
