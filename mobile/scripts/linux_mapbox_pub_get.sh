#!/bin/sh
# mapbox_maps_flutter 3.x ships an iOS plugin that is Swift Package Manager
# only. Linux Flutter has no Xcode, so it treats Swift Package Manager as off
# and exits 1 from `flutter pub get`, `flutter test`, and `flutter build web`
# even after the packages have resolved.
#
# A podspec next to that plugin's Package.swift satisfies the file check.
# `setupPodfile` returns immediately when Xcode is missing, so CocoaPods is
# never invoked. macOS builds do not run this stub; enable Swift Package
# Manager there with `flutter config --enable-swift-package-manager`.
set -eu

if [ "$(uname -s)" = "Darwin" ]; then
  flutter pub get "$@"
  exit $?
fi

log=$(mktemp)
set +e
flutter pub get "$@" >"$log" 2>&1
status=$?
set -e
cat "$log"

if [ "$status" -eq 0 ]; then
  rm -f "$log"
  exit 0
fi

if ! grep -q "only Swift Package Manager compatible" "$log"; then
  rm -f "$log"
  exit "$status"
fi
rm -f "$log"

pub_cache="${PUB_CACHE:-$HOME/.pub-cache}"
found=0
for ios_dir in "$pub_cache"/hosted/pub.dev/mapbox_maps_flutter_mobile-*/ios; do
  [ -d "$ios_dir" ] || continue
  found=1
  spec="$ios_dir/mapbox_maps_flutter_mobile.podspec"
  if [ ! -f "$spec" ]; then
    cat >"$spec" <<'EOF'
# Linux Flutter hosts have no Xcode, so an SPM-only plugin fails pub get.
# This file only satisfies that file-exists check. iOS builds use Package.swift.
Pod::Spec.new do |s|
  s.name = 'mapbox_maps_flutter_mobile'
  s.version = '0.0.0'
  s.summary = 'Linux pub-get placeholder. iOS uses Swift Package Manager.'
  s.homepage = 'https://github.com/mapbox/mapbox-maps-flutter'
  s.license = { :type => 'Mapbox Terms of Service' }
  s.author = { 'Mapbox' => 'mobile@mapbox.com' }
  s.source = { :path => '.' }
  s.platform = :ios, '14.0'
end
EOF
  fi
done

if [ "$found" -eq 0 ]; then
  echo "mapbox_maps_flutter_mobile was not in the pub cache; cannot continue." >&2
  exit "$status"
fi

flutter pub get "$@"
