
#!/usr/bin/env bash
# NexaWave OS v0.1
# Target: TP-Link Archer C6 V3
# OpenWrt: 25.12.6
#
# No Wi-Fi, PPPoE or payment credentials are embedded in firmware.

set -Eeuo pipefail

# --------------------------------------------------
# Configuration
# --------------------------------------------------

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.6}"
TARGET="ramips/mt7621"
PROFILE="tplink_archer-c6-v3"

BASE="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}"

WORK="${WORK:-$HERE/work}"
OUT="${OUT:-$HERE/out}"

# Archer C6 V3 target image size limit (KB)
MAX_IMAGE_KB=15744

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

# --------------------------------------------------
# Validate inputs
# --------------------------------------------------

[[ "$OPENWRT_VERSION" =~ ^[0-9A-Za-z._-]+$ ]] ||
    fail "Invalid OpenWrt version."

[[ -f "$HERE/packages.txt" ]] ||
    fail "packages.txt not found."

[[ -d "$HERE/files" ]] ||
    fail "files directory not found."

mkdir -p "$WORK" "$OUT"

# --------------------------------------------------
# Download official checksum manifest
# --------------------------------------------------

cd "$WORK"

echo "=========================================="
echo " NexaWave OS - OpenWrt Image Builder"
echo "=========================================="

echo ">> OpenWrt version: $OPENWRT_VERSION"
echo ">> Target: $TARGET"
echo ">> Profile: $PROFILE"

echo ">> Fetching official SHA256 manifest..."

curl --fail --location \
    --retry 3 \
    --silent --show-error \
    "$BASE/sha256sums" \
    -o sha256sums

[[ -s sha256sums ]] ||
    fail "Checksum manifest is empty."

# --------------------------------------------------
# Find correct Image Builder archive
# --------------------------------------------------

echo ">> Searching for Image Builder archive..."

IB_FILE="$(
    awk '
    NF >= 2 {
        name = $2
        sub(/^\*/, "", name)

        if (name ~ /^openwrt-imagebuilder-.*-ramips-mt7621\.Linux-x86_64\.tar\.(zst|xz)$/) {
            print name
            exit
        }
    }
    ' sha256sums
)"

[[ -n "$IB_FILE" ]] ||
    fail "No matching Image Builder archive found."

EXPECTED="$(
    awk -v file="$IB_FILE" '
    NF >= 2 {
        name = $2
        sub(/^\*/, "", name)

        if (name == file) {
            print $1
            exit
        }
    }
    ' sha256sums
)"

[[ "$EXPECTED" =~ ^[0-9a-fA-F]{64}$ ]] ||
    fail "Could not parse SHA256 for $IB_FILE."

echo ">> Image Builder: $IB_FILE"

# --------------------------------------------------
# Download and verify archive
# --------------------------------------------------

if [[ -f "$IB_FILE" ]]; then
    if ! printf '%s  %s\n' "$EXPECTED" "$IB_FILE" |
        sha256sum --check --status; then
        echo ">> Existing archive checksum invalid. Removing it."
        rm -f "$IB_FILE"
    fi
fi

if [[ ! -f "$IB_FILE" ]]; then
    echo ">> Downloading Image Builder..."

    curl --fail --location \
        --retry 3 \
        --retry-delay 3 \
        --silent --show-error \
        "$BASE/$IB_FILE" \
        -o "$IB_FILE"
fi

echo ">> Verifying archive SHA256..."

printf '%s  %s\n' "$EXPECTED" "$IB_FILE" |
    sha256sum --check ||
    fail "Image Builder SHA256 verification failed."

# --------------------------------------------------
# Extract Image Builder
# --------------------------------------------------

IB_DIR="${IB_FILE%.tar.*}"

if [[ ! -d "$IB_DIR" ]]; then
    echo ">> Extracting Image Builder..."

    case "$IB_FILE" in
        *.tar.zst)
            tar --zstd -xf "$IB_FILE"
            ;;
        *.tar.xz)
            tar -xJf "$IB_FILE"
            ;;
        *)
            fail "Unsupported Image Builder archive format."
            ;;
    esac
fi

[[ -d "$IB_DIR" ]] ||
    fail "Image Builder extraction failed: $IB_DIR"

# --------------------------------------------------
# Prepare NexaWave filesystem overlay
# --------------------------------------------------

echo ">> Preparing NexaWave filesystem..."

rm -rf "$WORK/files"
cp -a "$HERE/files" "$WORK/files"

mkdir -p \
    "$WORK/files/etc" \
    "$WORK/files/etc/uci-defaults" \
    "$WORK/files/www/nexawave"

# Build information only. Never put passwords or tokens here.
cat > "$WORK/files/etc/nexawave-build-info" <<INFO
NEXAWAVE_VERSION=0.1.0-prototype
OPENWRT_VERSION=$OPENWRT_VERSION
TARGET=$TARGET
PROFILE=$PROFILE
INFO

if [[ -f "$WORK/files/etc/uci-defaults/99-nexawave" ]]; then
    chmod +x "$WORK/files/etc/uci-defaults/99-nexawave"
fi

# --------------------------------------------------
# Read package list
# --------------------------------------------------

PACKAGES="$(
    sed 's/#.*//' "$HERE/packages.txt" |
    xargs
)"

echo ">> Selected packages:"
echo "${PACKAGES:-Profile defaults only}"

# --------------------------------------------------
# Validate Image Builder profile
# --------------------------------------------------

cd "$WORK/$IB_DIR"

echo ">> Checking available Image Builder profiles..."

INFO_FILE="$WORK/imagebuilder-info.txt"

make info > "$INFO_FILE"

if ! grep -F -- "$PROFILE" "$INFO_FILE" >/dev/null; then
    echo "ERROR: Profile $PROFILE was not found."
    echo "Available Archer C6 profiles:"
    grep -Ei 'archer.*c6' "$INFO_FILE" || true

    fail "Device profile validation failed."
fi

echo ">> Confirmed device profile: $PROFILE"

# --------------------------------------------------
# Build firmware
# --------------------------------------------------

echo "=========================================="
echo " Starting NexaWave firmware build"
echo "=========================================="

make image \
    PROFILE="$PROFILE" \
    PACKAGES="$PACKAGES" \
    FILES="$WORK/files" \
    EXTRA_IMAGE_NAME="nexawave"

echo ">> Image Builder completed."

# --------------------------------------------------
# Collect firmware files
# --------------------------------------------------

BIN_DIR="bin/targets/$TARGET"

[[ -d "$BIN_DIR" ]] ||
    fail "Firmware output directory not found: $BIN_DIR"

mkdir -p "$OUT"

shopt -s nullglob

SYSUPGRADE=(
    "$BIN_DIR"/*"$PROFILE"*sysupgrade.bin
)

((${#SYSUPGRADE[@]} > 0)) ||
    fail "No matching sysupgrade firmware was generated."

echo ">> Copying sysupgrade firmware..."

cp -v "${SYSUPGRADE[@]}" "$OUT/"

FACTORY=(
    "$BIN_DIR"/*"$PROFILE"*factory.bin
)

if ((${#FACTORY[@]} > 0)); then
    cp -v "${FACTORY[@]}" "$OUT/"
fi

MANIFESTS=(
    "$BIN_DIR"/*.manifest
)

if ((${#MANIFESTS[@]} > 0)); then
    cp -v "${MANIFESTS[@]}" "$OUT/"
fi

# --------------------------------------------------
# Validate firmware image size
# --------------------------------------------------

echo ">> Checking firmware image sizes..."

for IMAGE in "$OUT"/*sysupgrade.bin; do

    [[ -f "$IMAGE" ]] || continue

    SIZE_BYTES="$(stat -c '%s' "$IMAGE")"
    SIZE_KB=$(( (SIZE_BYTES + 1023) / 1024 ))

    echo ">> $(basename "$IMAGE"): ${SIZE_KB} KB"

    if (( SIZE_KB > MAX_IMAGE_KB )); then
        fail "Firmware exceeds ${MAX_IMAGE_KB} KB target image limit."
    fi

done

# --------------------------------------------------
# Generate checksums
# --------------------------------------------------

echo ">> Generating SHA256SUMS..."

(
    cd "$OUT"
    sha256sum ./*.bin > SHA256SUMS
)

# --------------------------------------------------
# Build summary
# --------------------------------------------------

echo
echo "=========================================="
echo " NexaWave OS BUILD COMPLETED"
echo "=========================================="

echo "OpenWrt version: $OPENWRT_VERSION"
echo "Target: $TARGET"
echo "Profile: $PROFILE"
echo "Output directory: $OUT"

echo
echo "Generated files:"

find "$OUT" -maxdepth 1 -type f -printf '%f\n'

echo
echo ">> Build completed successfully."
