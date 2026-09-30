-- FPVDash LEDs for radios with RGB LEDs. Run it from a model special function:
-- RGB LEDs, switch ON, script fpvleds, repeat On.
-- Stick rings: white while Betaflight reports armed over telemetry, red otherwise (disarmed,
-- refusing to arm, or no link).
-- Buttons 1-6 (radios with customizable switches, e.g. TX16S MK3): a blue light chases left to
-- right while there's no telemetry. Once linked they become a GPS satellite bar scaled 0-32 sats
-- (any sats light button 1, 27+ light all six), amber until the quad can set a GPS Rescue home
-- point and white after (homeSats satellites and a position). EdgeTX only shows these colours
-- when the model turns on "Lua override" for the on and off colours of SW1-SW6.
-- homeSats comes from /WIDGETS/FPVDash/config.lua, shared with the dashboard.
-- EdgeTX strings have no methods, so string.find is called directly.
local RED, WHITE, AMBER = { 255, 0, 0 }, { 255, 255, 255 }, { 255, 140, 0 }
local BLUE, BLUE_TAIL, OFF = { 0, 120, 255 }, { 0, 20, 45 }, { 0, 0, 0 }
local BUTTONS = { "SW1", "SW2", "SW3", "SW4", "SW5", "SW6" }
local FULL_SATS = 32
local HOME_SATS = 8
do
  local chunk = loadScript("/WIDGETS/FPVDash/config.lua")
  local ok, user = pcall(function() return chunk and chunk() end)
  if ok and type(user) == "table" and user.homeSats then HOME_SATS = user.homeSats end
end
local CHASE_STEP = 12            -- 10 ms ticks per chase step
local setButtonLed = setCFSLedColor

local sticks, buttons, painted = nil, {}, 0

-- only values the receiver is sending right now
local function sensor(name)
  if getFieldInfo(name) == nil then return nil end
  local v, current = getSourceValue(name)
  if current then return v end
end

local function paintButton(i, c)
  if buttons[i] ~= c then
    setButtonLed(BUTTONS[i], c[1], c[2], c[3])
    buttons[i] = c
  end
end

-- the head sweeps 1 -> 6 with a dim tail, then one dark step before it starts over
local function chase(now)
  local head = math.floor(now / CHASE_STEP) % (#BUTTONS + 1) + 1
  for i = 1, #BUTTONS do
    paintButton(i, i == head and BLUE or (i == head - 1 and BLUE_TAIL) or OFF)
  end
end

local function satBar(sats, fix)
  local lit = math.min(#BUTTONS, math.ceil(sats * #BUTTONS / FULL_SATS))
  local c = fix and WHITE or AMBER
  for i = 1, #BUTTONS do paintButton(i, i <= lit and c or OFF) end
end

local function run()
  local now = getTime()
  -- repaint everything once a second in case something else touched the LEDs
  if now - painted >= 100 then sticks, buttons, painted = nil, {}, now end

  local rqly = sensor("RQly")
  local linked = rqly ~= nil and rqly > 0
  -- While disarmed Betaflight ends the flight mode with * (ready), ! (arming disabled) or
  -- ? (GPS Rescue not ready); nothing while armed. !FS! (failsafe) counts as armed.
  local fm = linked and sensor("FM")
  local last = type(fm) == "string" and string.sub(fm, -1) or ""
  local armed = fm == "!FS!" or (last ~= "" and last ~= "*" and last ~= "!" and last ~= "?")

  local c = armed and WHITE or RED
  if c ~= sticks then
    for i = 0, LED_STRIP_LENGTH - 1 do setRGBLedColor(i, c[1], c[2], c[3]) end
    applyRGBLedColors()
    sticks = c
  end

  if not setButtonLed then return end
  if not linked then
    chase(now)
  else
    local sats = sensor("Sats") or 0
    local gps = sensor("GPS")
    satBar(sats, type(gps) == "table" and gps.lat ~= 0 and sats >= HOME_SATS)
  end
end

return { run = run }
