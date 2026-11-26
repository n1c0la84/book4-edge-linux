# Ambient light sensor

The Galaxy Book4 Edge 14" has a Vishay VEML3328 colour/light sensor. Linux
can't reach it directly: it hangs off the ADSP's **Qualcomm Sensor Core
(SSC)**, the sensor hub that runs in the audio DSP's firmware. Windows drives
it through Qualcomm's sensor drivers. The approach here is Rafael Meneses' for
the 16" (github.com/rafaelmnz/SB4-Edge-Linux, `overlay/sensors`,
`build-ssc.sh`), adapted to the 14" and to Arch.

## The chain

1. **Sensor config and registry** (local only, from this laptop's Windows, in
   `book4-edge-firmware`, under `/usr/share/book4/sensors/`):
   - `config/`: the JSON files of the `qcsensorsconfigcrd8380` driver package,
     including the 14"'s own `8380_ss_nx14_veml3328_0.json` (the 16" has
     `nx16`), and `json.lst`;
   - `sns_reg_config`: which files the firmware reads (it names
     `/sys/devices/soc0/*`, `/vendor/etc/sensors/config`,
     `/persist/sensors/registry/registry`);
   - `socinfo/`: the six SoC values Windows gives it (`soc_id` 555, `CRD`,
     `revision` 3.1, ...);
   - `registry/`: the registry Windows' sensor stack generated from the
     config (`System32/drivers/DriverData/Qualcomm/fastRPC/persist/sensors/registry`).
   Picked by checksum (`packages/book4-edge-firmware/sha256sums.txt`) by
   `install/arch/firmware-stage.sh`.
2. **`book4-sensors-setup`** (`book4-sensors` package) copies them into
   `/var/lib/book4/vendor` (linked as `/vendor`), rewrites `sns_reg_config`'s
   paths, sets the config files' mtime to Windows' (`1719257058`; the
   registry records it, and a mismatch makes the firmware rebuild the
   registry at every start), and seeds the writable registry once.
3. **`adsprpcd sensorspd adsp`** (`fastrpc` package, `book4-sensors.service`)
   serves those files to the ADSP's sensors domain. The firmware writes to the
   registry and asserts (taking the ADSP down) if it can't.
4. **`libssc`** reads the sensor over QRTR. The VEML3328 is published with
   data type `color`, not `ambient_light`, so `libssc-book4` carries Rafael's
   `LIBSSC_LIGHT_DATA_TYPE` override (`color`, set in the iio-sensor-proxy
   drop-in).
5. **`iio-sensor-proxy`** 3.9 with SSC support (`iio-sensor-proxy-book4`, plus
   Rafael's client-vanished crash fix) publishes the light level on D-Bus
   (`net.hadess.SensorProxy`); `monitor-sensor` shows it. The udev rule
   `81-book4-ssc-light.rules` marks `/dev/fastrpc-adsp` as an SSC light
   sensor and starts it.
6. **Automatic brightness**: `book4-autobrightness` (below) drives the panel
   backlight from `iio-sensor-proxy` (screen done 25 Nov; automatic keyboard
   backlight is optional / not yet added).

## Safety

- At EL2 a crashed ADSP stays down until reboot (no PAS restart), and with it
  sound. The chain was tested at EL1 and then at EL2 (25 Nov 2026: ~91-112
  lux, 0 covered, jump with a torch, ADSP attached, audio unaffected), so the
  `/dev/kvm` guard is gone: it runs at both.
- `fastrpc` ships no udev rules or units: upstream's start `cdsprpcd` by
  themselves, which crashed the CDSP on other X1E laptops.
- `book4-sensors.service` and `iio-sensor-proxy` are started automatically by
  udev at boot; `book4-autobrightness` is not enabled on install.

## Installing and verifying

    bash install/arch/firmware-stage.sh && (cd packages/book4-edge-firmware && makepkg -f)
    bash install/arch/book4-repo.sh add book4-edge-firmware
    sudo pacman -Syu && sudo pacman -S book4-sensors
    # After a reboot (EL2 or EL1; udev starts the services automatically):
    journalctl -u book4-sensors -b; journalctl -k -b | grep -i -E "adsp|remoteproc"
    LIBSSC_LIGHT_DATA_TYPE=color ssccli --sensor light
    monitor-sensor --light

## Automatic brightness

`book4-autobrightness` (user service, in book4-sensors, not enabled on
install) claims the light sensor on iio-sensor-proxy and sets the panel
backlight (`dp_aux_backlight`) through logind's `Session.SetBrightness`, so it
needs neither root nor the video group.

- Curve: lux to percent, interpolated on log10(lux + 1): 0 lux 5 %, 10 lux
  20 %, 100 lux 38 %, 1000 lux 70 %, 10000 lux 100 %. Readings are smoothed
  (factor 0.3 per sample) and differences under 3 % are left alone; moves go
  in 1 % steps every 40 ms (under a second for 20 %).
- A brightness set by hand (keys, OSD, brightnessctl) is kept: the difference
  to the curve becomes an offset (saved in
  `~/.local/state/book4-autobrightness/offset`, limited to +-60 %). The
  backlight is checked every second, since iio-sensor-proxy signals only a
  changed value.
- Nothing is written while the panel is off (Hyprland DPMS, lock).

    systemctl --user enable --now book4-autobrightness     # on
    systemctl --user disable --now book4-autobrightness    # off
    journalctl --user -u book4-autobrightness              # what it did
