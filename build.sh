#!/usr/bin/env bash
# NexaWave OS - reproducible OpenWrt Image Builder wrapper.
# No Wi-Fi or PPPoE secrets are embedded in the image. Configure networking after boot.
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.6}"
TARGET="ramips/mt7621"
PROFILE="tplink_archer-c6-v3"
BASE="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}"
WORK="${WORK:-$HERE/work}"
OUT="${OUT:-$HERE/out}"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ "$OPENWRT_VERSION" =~ ^[0-9A-Za-z._-]+$ ]] || fail 'Invalid OPENWRT_VERSION.'

mkdir -p "$WORK" "$OUT"
cd "$WORK"
printf '>> Fetching official checksum manifest: %s/sha256sums\n' "$BASE"
curl --fail --location --silent --show-error "$BASE/sha256sums" -o sha256sums
# OpenWrt manifests use either "HASH  filename" or "HASH *filename".
IB_FILE="$(awk '$2 ~ /^openwrt-imagebuilder-.*\.tar\.(zst|xz)$/ {gsub(/^\*/, "", $2); print $2; exit}' sha256sums)"
[[ -n "$IB_FILE" ]] || fail "No Image Builder archive found in $BASE/sha256sums"
EXPECTED="$(awk -v f="$IB_FILE" '$2==f || $2=="*" f {print $1; exit}' sha256sums)"
[[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]] || fail "Could not parse SHA256 for $IB_FILE"
if [[ ! -f "$IB_FILE" ]]; then
  echo ">> Downloading $IB_FILE"
  curl --fail --location --retry 3 --silent --show-error "$BASE/$IB_FILE" -o "$IB_FILE"
fi
printf '%s  %s\n' "$EXPECTED" "$IB_FILE" | sha256sum --check --status || fail 'Image Builder SHA256 verification failed.'
IB_DIR="${IB_FILE%.tar.*}"
if [[ ! -d "$IB_DIR" ]]; then
  case "$IB_FILE" in *.tar.zst) tar --zstd -xf "$IB_FILE" ;; *.tar.xz) tar -xJf "$IB_FILE" ;; esac
fi
[[ -d "$IB_DIR" ]] || fail "Could not locate extracted Image Builder directory: $IB_DIR"

# Keep the overlay free of secrets. Only non-secret defaults are baked into firmware.
rm -rf "$WORK/files"
cp -a "$HERE/files" "$WORK/files"
mkdir -p "$WORK/files/etc/uci-defaults" "$WORK/files/www/nexawave"
cat > "$WORK/files/etc/nexawave-build-info" <<INFO
NEXAWAVE_VERSION=0.1.0-prototype
OPENWRT_VERSION=$OPENWRT_VERSION
TARGET=$TARGET
PROFILE=$PROFILE
INFO
chmod +x "$WORK/files/etc/uci-defaults/99-nexawave"

PACKAGES="$(sed -e 's/#.*//' "$HERE/packages.txt" | xargs)"
echo ">> Packages: ${PACKAGES:-'(profile defaults only)'}"
cd "$WORK/$IB_DIR"
make info | grep -Fq "$PROFILE" || fail "Profile $PROFILE is not listed by this Image Builder. Check hardware revision/region."
make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="$WORK/files" EXTRA_IMAGE_NAME="nexawave"

BIN_DIR="bin/targets/$TARGET"
mkdir -p "$OUT"
shopt -s nullglob
SYSUPGRADE=("$BIN_DIR"/*"$PROFILE"*sysupgrade.bin)
((${#SYSUPGRADE[@]} > 0)) || fail 'Build completed but no matching sysupgrade image was produced.'
cp -v "${SYSUPGRADE[@]}" "$OUT/"
FACTORY=("$BIN_DIR"/*"$PROFILE"*factory.bin)
((${#FACTORY[@]} == 0)) || cp -v "${FACTORY[@]}" "$OUT/"
MANIFESTS=("$BIN_DIR"/*.manifest)
((${#MANIFESTS[@]} == 0)) || cp -v "${MANIFESTS[@]}" "$OUT/"
( cd "$OUT" && sha256sum ./*.bin > SHA256SUMS )
echo ">> Build complete. Review image size and SHA256SUMS in $OUT"
