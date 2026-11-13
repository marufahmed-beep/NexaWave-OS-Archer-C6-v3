# NexaWave OS — Archer C6 v3 prototype

A branded, lightweight OpenWrt Image Builder project for the TP-Link Archer C6 v3. This is a **prototype**, not a complete router operating system. It currently provides a safe base image, standard LuCI administration, and a static NexaWave dashboard preview.

## Target and limitations

- OpenWrt release default: `25.12.6` (selectable in GitHub Actions)
- Target: `ramips/mt7621`
- Profile: `tplink_archer-c6-v3`
- The exact router hardware revision and region must match the profile before flashing.
- The build script checks that the profile exists in the downloaded Image Builder and verifies the Image Builder archive SHA256.
- A successful Image Builder run and an image-size check are required; this repository has not been tested on physical hardware.

## Security design

**No Wi-Fi password, PPPoE password, Telegram token, bKash key, or other secret is embedded in the firmware.** The previous approach of baking credentials into `/etc/custom.env` was removed. Configure WAN and Wi-Fi after boot through LuCI over Ethernet. Set a strong root password immediately.

The static dashboard is at `http://192.168.1.1/nexawave/` after the web server is available. It is only a visual prototype: metrics and controls are not connected to router APIs. It intentionally does not expose shell or unrestricted ubus access.

## Build locally (Linux/WSL)

```sh
./build.sh
```

Images and SHA256 checksums are written to `out/`. The build uses the official OpenWrt Image Builder downloaded from `downloads.openwrt.org`.

## Build with GitHub Actions

1. Push this folder to a private GitHub repository.
2. Open **Actions → Build NexaWave OS (Archer C6 v3) → Run workflow**.
3. Select the OpenWrt release version and run it.
4. Download the workflow artifact and verify `SHA256SUMS` before use.

No GitHub secrets or repository variables are required. Do not add personal router credentials to repository files or workflow variables.

## First boot

1. Confirm the label under the router says **Archer C6 v3** and check the region. Do not assume that similarly named C6 hardware is compatible.
2. Connect a computer to a LAN port using Ethernet.
3. Open LuCI at `http://192.168.1.1` (unless you intentionally changed the LAN IP at build time).
4. Set a strong root password immediately.
5. Configure WAN (DHCP or PPPoE) and Wi-Fi in LuCI. The image does not preconfigure either with credentials.
6. Open `http://192.168.1.1/nexawave/` for the dashboard preview.

## Flashing warning

Do not flash until the exact hardware revision/region, image profile, image size, checksum, and recovery procedure are verified. Back up the current configuration and keep a known-good recovery image. Do not use a factory image for an OpenWrt sysupgrade or vice versa. A build artifact is not proof of hardware compatibility.

## Roadmap (not implemented yet)

- Authenticated read-only router metrics API and dynamic dashboard
- Device list and bandwidth monitoring
- Guest Wi-Fi and openNDS-based voucher portal
- Package/profile selection tuned to the 16 MB flash constraint
- External service for Telegram and bKash Merchant API integration

Telegram and bKash credentials must stay on a secured external backend, not in the router firmware. Payment status must be verified server-side with the payment provider; client-side screenshots are not proof of payment.
