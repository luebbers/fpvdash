# Changelog

## 1.1.1 (2026-09-30)

- **Hi-Vis** no longer stops with "Invalid property 'dashWidth'" on the radio. EdgeTX 2.12 only draws dashes on horizontal and vertical line objects, so the dashed LAND line is now one.
- **Hi-Vis** on 480x272 screens: smaller battery digits, so they stay clear of the labels above them and the V fits in its cell.

## 1.1.0 (2026-09-30)

- Themes, picked in the widget's settings (long-press the dashboard, Widget settings, Theme):
  - **Glass Cockpit**, the new default: avionics style, near-black with thin rules, segmented gauges, a plan view with range rings for the GPS view and link lost.
  - **Hi-Vis**: fluorescent yellow for bright sun, giant condensed numbers, hatched level gauges, hazard stripes when armed, and a red-orange screen in a failsafe or when the link is lost.
  - **Classic**: the 1.0 look.
- A separate **link lost** screen when the signal drops while armed; the **flight summary** is for a quad that landed and was unplugged.
- Switch tiles show what a position means; channels named ARM, BEEPER, TURTLE, RESCUE and the like read OFF/ON without a `config.lua`.
- New setting `tabularDigits` for Hi-Vis.
- `tools/sprites.py` renders the theme images.

## 1.0.0 (2026-09-30)

First release.

- Dashboard: battery and link quality gauges, flight mode, arm state with the reason it won't arm, GPS satellites with a warning when armed without a rescue home point, timer, distance and arrow home, altitude, speed, mAh used.
- Switch strip built from the model's mixer, or from your own list in `config.lua`.
- Radio battery on every screen.
- GPS view, flight summary, Find page with a QR code of the last known position, logbook.
- Simulator mode when no RF module is on.
- Optional voice callouts (`fpvcall`) and RGB LED script (`fpvleds`).
- Settings in an optional `config.lua`, shared by all three parts.
