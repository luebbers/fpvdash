# FPVDash

A full-screen telemetry dashboard for EdgeTX colour radios, for Betaflight quads on ExpressLRS or Crossfire. Everything you need before, during and after a flight on one screen, with a find-my-quad QR code, a logbook and optional voice callouts. Three themes to pick from.

![Glass Cockpit and Hi-Vis on a RadioMaster TX16S MK3](docs/themes-tx16s-mk3.jpg)

<sub>Radio photo: RadioMaster. The screens are rendered from the widget's code.</sub>

## Themes

Pick one in the widget's settings: long-press the dashboard, choose **Widget settings**, then **Theme**. The change shows at once, and each model keeps its own choice.

| Glass Cockpit | Hi-Vis | Classic |
|---|---|---|
| ![Glass Cockpit](docs/cockpit-dashboard.png) | ![Hi-Vis](docs/hivis-dashboard.png) | ![Classic](docs/classic-dashboard.png) |
| Avionics style: near-black, thin rules, colour only where it means something (cyan for your switch settings, amber for caution, red for warnings, magenta for home). The default. | Safety signage for bright sun: fluorescent yellow, giant condensed numbers, hazard stripes when armed, and the whole screen turns red-orange in a failsafe or when the link is lost. | The original look: rounded tiles and ring gauges in green, amber and red. |

## Features

- **Dashboard**: battery (volts per cell, cell count detected automatically) and link quality gauges, flight mode, arm state, GPS satellites, flight timer, distance and arrow home, altitude, speed and mAh used.
- **Arm state that explains itself**: CAN'T ARM or NO RESCUE while disarmed, and NO HOME if you arm before Betaflight can set a GPS Rescue home point.
- **Switch strip**: every switch and knob that drives a channel, showing what it does (OFF, ANGLE, ARMED...) rather than where it sits. Built from your model automatically, or with your own labels.
- **Radio battery** on every screen.
- **GPS view** while flying, and a **link lost** screen with the last known position when the signal drops in the air.
- **Flight summary** after landing.
- **Find my quad**: the last known position as a QR code. Scan it with your phone and the map opens at the spot. It survives a radio restart.
- **Logbook**: flights and time per quad and the latest flights. Bench tests with the props off aren't counted.
- **Simulator mode** for models used as a USB joystick.
- Optional **voice callouts** (GPS ready, no home point, too high, distance every 100 m, battery 50/70/80% used, pack not charged, status readout) and **RGB LED** effects on radios that have them.

## Screens

Every page in the two newest themes, rendered from the widget code at 800x480.

| | Glass Cockpit | Hi-Vis |
|---|---|---|
| **Waiting.** Before a quad links. The switch strip is already live, so you can check every switch before plugging in. | ![](docs/cockpit-waiting.png) | ![](docs/hivis-waiting.png) |
| **On the bench.** Disarmed; the annunciators say why it isn't ready. Here NO RESCUE: too few satellites for a GPS Rescue home point yet. | ![](docs/cockpit-bench.png) | ![](docs/hivis-bench.png) |
| **Flying.** Pack and link gauges, mode, satellites, timer, and home distance with an arrow pointing home. | ![](docs/cockpit-dashboard.png) | ![](docs/hivis-dashboard.png) |
| **No home point.** Armed with 6 satellites, so Betaflight set no rescue home. | ![](docs/cockpit-no-home.png) | ![](docs/hivis-no-home.png) |
| **Failsafe.** A sagging pack, a weak link, no GPS fix and a low radio battery. | ![](docs/cockpit-failsafe.png) | ![](docs/hivis-failsafe.png) |
| **GPS view.** Press the view switch while flying: where the quad is from home, the position and the numbers that matter. | ![](docs/cockpit-gps-view.png) | ![](docs/hivis-gps-view.png) |
| **Link lost.** When the signal drops in the air: where the quad was last seen and how long ago. | ![](docs/cockpit-link-lost.png) | ![](docs/hivis-link-lost.png) |
| **Flight summary.** After landing and unplugging: flight time, lowest cell, mAh, distance, altitude, speed, and where it landed. | ![](docs/cockpit-summary.png) | ![](docs/hivis-summary.png) |
| **Find my quad.** The last known position as a QR code for your phone's map. | ![](docs/cockpit-find.png) | ![](docs/hivis-find.png) |
| **Logbook.** Flights and time per quad, and the latest flights. | ![](docs/cockpit-logbook.png) | ![](docs/hivis-logbook.png) |
| **Simulator mode.** When the model has no RF module switched on. | ![](docs/cockpit-simulator.png) | ![](docs/hivis-simulator.png) |

Classic has the same pages:

| | | |
|---|---|---|
| ![](docs/classic-gps-view.png) | ![](docs/classic-link-lost.png) | ![](docs/classic-find.png) |

On 480x272 screens (TX16S MKII and similar) everything scales down:

![Glass Cockpit at 480x272](docs/cockpit-small-screen.png)

## Requirements

- EdgeTX 2.11 or later on a colour-screen radio. Designed at 800x480 (RadioMaster TX16S MK3) and scales to 480x272. Tested on EdgeTX 2.12.
- Betaflight with ExpressLRS or Crossfire telemetry. Tested with Betaflight 4.5, 2025.12 and 2026.6 on ExpressLRS 4.1.

## Install

1. Download `FPVDash-<version>.zip` from the [latest release](https://github.com/vcazan/fpvdash/releases/latest). The same zip is also in [`dist/`](dist/).
2. Connect the radio by USB and choose **USB Storage**. Unzip the file onto the root of the SD card, merging with the folders already there (`WIDGETS`, `SCRIPTS`, `SOUNDS`). Eject the SD card and unplug.
3. On the radio, open the screen setup (the TELE key on a TX16S), add a screen or pick one, choose the **Full screen** layout, turn off Top bar, Flight mode, Sliders and Trims, then set the widget to **FPVDash**.

That's all the dashboard needs. The switch strip is built from the model's mixer, and flights go into the logbook under the model's name.

### Voice callouts (optional)

In the model's **Special Functions**, add: switch **ON**, function **Lua Script**, script **fpvcall**, repeat **On**. For the battery percentage callouts, list your pack capacities in the settings.

### LEDs (optional)

In the model's **Special Functions**, add: switch **ON**, function **RGB LEDs**, script **fpvleds**, repeat **On**. The stick LEDs turn white when armed and red when not. On a TX16S MK3, the six buttons chase while waiting for telemetry and then show GPS satellites; they only take these colours when the model's customizable switches SW1 to SW6 have **Lua override** turned on for their on and off colours.

## Using it

- The **view switch** (SH by default, a momentary switch) steps through the pages: dashboard and GPS view while linked; otherwise the home screen, Find and Logbook.
- Long-press the dashboard and choose **Widget settings** for the **Theme** and **Cells** options. Cells forces a cell count; 0 detects it from the pack voltage. The same settings are in the screen setup: pick the widget, then Settings.

## Settings

Copy `WIDGETS/FPVDash/config.example.lua` to `config.lua` in the same folder on the SD card and edit it. Anything you leave out keeps its default, and the file explains each setting:

- `cells`: the pack sizes you fly (default 4 and 6).
- `quadNames`: logbook names by cell count, instead of the model name.
- `homeSats`: Betaflight's `gps_rescue_min_sats` (default 8).
- `viewSwitch`: the page switch (default `"sh"`).
- `switches`: your own switch strip with named positions (ANGLE, HORIZON, ACRO...), instead of the automatic one.
- `tabularDigits`: in Hi-Vis, gives every digit the same width so numbers hold still as they change, at the cost of looser spacing around the 1s (default off; Glass Cockpit's digits always are).
- `debugLog`: writes a line to `/LOGS/fpvdash-debug.txt` at every page build and switch (default off). If the radio restarts into Emergency mode, the last line shows what the dashboard was doing; please include the file in a bug report.
- `ceiling`, `charged`, `packs`, `statusSwitch`: for the voice callouts.

Restart the radio (or reselect the model) after changing it.

## Files it writes

In `/LOGS` on the SD card: `fpvdash-lastpos.txt` (a line per link loss or landing, used by the Find page), `fpvdash-flights.csv` (every flight) and `fpvdash-logbook.txt` (totals and the latest flights).

## Upgrading

Unzip the new version over the old one. Your `config.lua` and logbook are kept, because the zip doesn't contain them. If the radio still shows the old version, delete the `.luac` files in `WIDGETS/FPVDash` and `WIDGETS/FPVDash/themes` so EdgeTX recompiles them.

Coming from 1.0: the dashboard opens in Glass Cockpit. Choose Classic in the widget's settings for the old look.

## Uninstalling

Delete `WIDGETS/FPVDash`, `SCRIPTS/FUNCTIONS/fpvcall.lua`, `SCRIPTS/RGBLED/fpvleds.lua`, `SOUNDS/en/fpvdash` and, if you like, the `fpvdash-*` files in `/LOGS`.

## How the themes are drawn

EdgeTX widgets can only use the radio's built-in fonts, so the large numbers and display words of Glass Cockpit and Hi-Vis are pre-rendered images in `WIDGETS/FPVDash/img`: one sheet per font size, each character in a cell, one band per colour. The widget shows a character by placing its sheet in a clipping box one cell wide, so a screen opens only a few image files. Labels and small text use the radio's fonts.

## Making a release

The files that go on the SD card are in [`src/`](src/). To release a new version, bump `VERSION` in `src/WIDGETS/FPVDash/main.lua`, add it to [CHANGELOG.md](CHANGELOG.md) and run `python3 build.py`, which writes `dist/FPVDash-<version>.zip`.

The theme images come from `python3 tools/sprites.py` (needs Pillow, fontTools and brotli). It downloads the typefaces from Google Fonts the first time.

## Credits

The themes are set in [IBM Plex Mono](https://fonts.google.com/specimen/IBM+Plex+Mono), [Barlow Semi Condensed](https://fonts.google.com/specimen/Barlow+Semi+Condensed), [Big Shoulders Display](https://fonts.google.com/specimen/Big+Shoulders+Display) and [JetBrains Mono](https://fonts.google.com/specimen/JetBrains+Mono), all under the SIL Open Font License. Only rendered images of them are included.

## License

MIT, see [LICENSE](LICENSE).
