-- FPVDash settings. Copy this file to config.lua in the same folder and edit it; anything you
-- leave out keeps its default. The dashboard, the callout script and the LED script all read it.
-- Restart the radio (or reselect the model) after changing it.
-- The theme isn't set here: long-press the dashboard, Widget settings, Theme.
return {
  -- Pack sizes you fly, for detecting the cell count from the voltage. Their 3.0-4.4 V per
  -- cell ranges must not overlap: 4 and 6 are fine, 3 and 4 aren't.
  cells = { 4, 6 },

  -- Logbook name by cell count. Without an entry, flights are logged under the model name.
  quadNames = {},                 -- e.g. { [4] = "Cinewhoop", [6] = "5 inch" }

  -- Betaflight's gps_rescue_min_sats. Arming with fewer satellites leaves no rescue home point,
  -- and the dashboard shows NO HOME.
  homeSats = 8,

  -- Momentary switch that steps through the pages (dashboard, GPS view, find, logbook).
  viewSwitch = "sh",              -- false for none

  -- The switch strip across the top. Leave it out and it's built from the model's mixer: one
  -- tile per channel driven by a switch or knob, labelled with the channel's name. To name the
  -- positions yourself, list the controls in the order they sit on the radio:
  --   { switch, function, up, down }             2-position switch
  --   { switch, function, up, middle, down }     3-position switch
  --   { knob, function, pot = true }             shows the knob's level
  --   { switch, function, view = true }          the page switch
  -- The first position is the switch's home; the themes show the others as set by you. A
  -- position ending in ! reads as a caution (amber), !! as armed (red).
  -- switches = {
  --   { "SF", "ARM", "OFF", "ARMED!!" },
  --   { "SB", "MODE", "ANGLE", "HORIZON", "ACRO" },
  --   { "SC", "BEEPER", "OFF", "OFF", "ON" },
  --   { "SD", "TURTLE", "OFF", "OFF", "ON" },
  --   { "SG", "RESCUE", "OFF", "OFF", "ON!" },
  --   { "S1", "VOLUME", pot = true },
  --   { "SH", "VIEW", view = true },
  -- },

  -- Hi-Vis: give every digit the same width so numbers hold still as they change. Big Shoulders
  -- has no evenly spaced digits of its own, so this spaces out the 1s. Glass Cockpit's always are.
  tabularDigits = false,

  -- Write a line to /LOGS/fpvdash-debug.txt at every page build and switch. If the radio ever
  -- restarts into Emergency mode, the last line shows what the dashboard was doing.
  debugLog = false,

  -- Voice callouts (SCRIPTS/FUNCTIONS/fpvcall.lua) --------------------------------------------

  -- "Too high" with the altitude, every 6 s above this many metres over takeoff.
  ceiling = 110,                  -- false for none

  -- A newly plugged-in pack resting below this many volts per cell is "not charged".
  charged = 4.05,

  -- Capacity by cell count, for "battery 50 / 70 / 80 percent used" (from the Capa sensor, so
  -- Betaflight's current sensor must be calibrated). A per-pack charged voltage suits LiHV.
  packs = {
    -- [4] = { mah = 850, charged = 4.20 },
    -- [6] = { mah = 1300 },
  },

  -- Momentary switch that speaks cell voltage, satellites, distance home and altitude.
  statusSwitch = false,           -- e.g. "SW1" on a TX16S MK3
}
