-- FPVDash callouts for flying in goggles. Run it from a model special function:
-- Lua Script, switch ON, script fpvcall, repeat On. Every callout also vibrates, so it's
-- noticeable over wind noise. Settings are shared with the dashboard in
-- /WIDGETS/FPVDash/config.lua (see config.example.lua there).
--   GPS: "GPS ready" once the quad can set a GPS Rescue home point (homeSats satellites and a
--        position), and "No home point, rescue is off" when it's armed before that.
--   In flight: a warning above the altitude ceiling, distance from home every 100 m (wider steps
--        further out), and battery 50/70/80% used from the Capa sensor for packs listed in packs.
--   New pack: "Battery not charged" when its resting cell voltage is below charged.
--   statusSwitch (optional, momentary): cell voltage, satellites, distance home and, when armed,
--        altitude.
-- EdgeTX strings have no methods, so string.find is called directly.
local CONFIG = {
  cells = { 4, 6 }, homeSats = 8, ceiling = 110, charged = 4.05, packs = {}, statusSwitch = false,
}
do
  local chunk = loadScript("/WIDGETS/FPVDash/config.lua")
  local ok, user = pcall(function() return chunk and chunk() end)
  if ok and type(user) == "table" then
    for k, v in pairs(user) do CONFIG[k] = v end
  end
end

local HOME_SATS = CONFIG.homeSats
local CEILING = CONFIG.ceiling           -- metres above takeoff; false for none
local SOUNDS = "fpvdash/"                -- this package's voice files, in SOUNDS/<language>/fpvdash
local NEW_PACK_GAP = 500                 -- ticks without telemetry, disarmed, that mean a new pack
local SETTLE = 300                       -- ticks after link-up before trusting the pack voltage

local s = { linked = false, armed = false, lastSeen = -NEW_PACK_GAP - 1 }
local button, buttonWas = nil, false

-- only values the receiver is sending right now
local function sensor(name)
  if getFieldInfo(name) == nil then return nil end
  local v, current = getSourceValue(name)
  if current then return v end
end

local function say(name) playFile(name .. ".wav") end

local function buzz(pulses)
  for _ = 1, pulses do playHaptic(15, 10) end  -- 10 ms units: 150 ms on, 100 ms off
end

local function round(x) return math.floor(x + 0.5) end

local function position()
  local gps = sensor("GPS")
  if type(gps) == "table" and gps.lat ~= 0 then return gps end
end

local function distance(a, b)
  local x = math.rad(b.lon - a.lon) * math.cos(math.rad((a.lat + b.lat) / 2))
  local y = math.rad(b.lat - a.lat)
  return 6371000 * math.sqrt(x * x + y * y)
end

local function nextStep(d)
  if d < 500 then return d + 100 elseif d < 1500 then return d + 250 end
  return d + 500
end

-- the configured pack size whose 3.0-4.4 V per cell range fits the voltage best
local function cells()
  if not s.cells then
    local v = sensor("RxBt")
    if v and v > 5 then
      local best, bestOff
      for _, n in ipairs(CONFIG.cells) do
        local c = v / n
        local off = (c < 3.0 and 3.0 - c) or (c > 4.4 and c - 4.4) or 0
        if not best or off < bestOff then best, bestOff = n, off end
      end
      s.cells = best
    end
  end
  return s.cells
end

local function altitude()
  local alt = sensor("Alt")
  if alt then return alt end
  local galt = sensor("GAlt")
  if galt and s.galt0 then return galt - s.galt0 end
end

local function newPack(now)
  s.linkedAt, s.cells, s.packChecked = now, nil, false
  s.gpsReady, s.readySince, s.lostSince = false, nil, nil
  s.home, s.warned = nil, {}
end

local function packCheck(now)
  if s.packChecked or not s.linkedAt or now - s.linkedAt < SETTLE then return end
  local v, n = sensor("RxBt"), cells()
  if not (v and n) then return end
  s.packChecked = true
  local charged = (CONFIG.packs[n] and CONFIG.packs[n].charged) or CONFIG.charged
  if charged and v / n < charged then say(SOUNDS .. "batchg"); buzz(2) end
end

local function gpsCallout(now, ready)
  if ready then
    s.lostSince = nil
    s.readySince = s.readySince or now
    if not s.gpsReady and now - s.readySince >= 200 then
      s.gpsReady = true
      say("gps"); say("ready"); buzz(1)
    end
  else
    s.readySince = nil
    -- forget "ready" only after 5 s without it, so a flicker doesn't repeat the callout
    if s.gpsReady then
      s.lostSince = s.lostSince or now
      if now - s.lostSince >= 500 then s.gpsReady, s.lostSince = false, nil end
    end
  end
end

local function onArm(ready, pos)
  s.nextDist, s.ceilingAt, s.galt0 = 100, 0, sensor("GAlt")
  if s.home then return end
  -- Betaflight sets home at the first arm with enough satellites and keeps it for the pack
  if ready then s.home = pos else say(SOUNDS .. "nohome"); buzz(3) end
end

local function flying(now, pos)
  local alt = altitude()
  if alt and CEILING then
    if alt >= CEILING then
      if now >= s.ceilingAt then
        say(SOUNDS .. "toohi"); playNumber(round(alt), UNIT_METERS); buzz(2)
        s.ceilingAt = now + 600
      end
    elseif alt < CEILING - 5 then
      s.ceilingAt = 0
    end
  end

  if s.home and pos then
    local d = distance(s.home, pos)
    if d >= s.nextDist then
      local step = s.nextDist
      while d >= nextStep(step) do step = nextStep(step) end
      playNumber(step, UNIT_METERS); buzz(1)
      s.nextDist = nextStep(step)
    end
  end

  local capa, n = sensor("Capa"), cells()
  local pack = n and CONFIG.packs[n]
  if capa and pack and pack.mah then
    local used = capa * 100 / pack.mah
    if used >= 80 then
      if now >= (s.warned[80] or 0) then say(SOUNDS .. "bat80"); buzz(3); s.warned[80] = now + 1000 end
    elseif used >= 70 then
      if not s.warned[70] then say(SOUNDS .. "bat70"); buzz(2); s.warned[70] = true end
    elseif used >= 50 and not s.warned[50] then
      say(SOUNDS .. "bat50"); buzz(1); s.warned[50] = true
    end
  end
end

local function status()
  if not s.linked then say("SYSTEM/telemko"); return end
  local v, n = sensor("RxBt"), cells()
  if v and n then say("cell"); playNumber(round(v / n * 10), UNIT_VOLTS, PREC1) end
  playNumber(sensor("Sats") or 0, UNIT_RAW); say(SOUNDS .. "sats")
  local pos = position()
  if s.home and pos then say(SOUNDS .. "home"); playNumber(round(distance(s.home, pos)), UNIT_METERS) end
  local alt = s.armed and altitude()
  if alt then say(SOUNDS .. "alt"); playNumber(round(alt), UNIT_METERS) end
end

local function init()
  s.warned = {}
  button = CONFIG.statusSwitch and getSourceIndex(CONFIG.statusSwitch) or nil
end

local function run()
  local now = getTime()
  local rqly = sensor("RQly")
  local linked = rqly ~= nil and rqly > 0
  -- While disarmed Betaflight ends the flight mode with * (ready), ! (arming disabled) or
  -- ? (GPS Rescue not ready); nothing while armed. !FS! (failsafe) keeps the last state.
  local fm = linked and sensor("FM")
  local last = type(fm) == "string" and string.sub(fm, -1) or ""
  local armed = last ~= "" and last ~= "*" and last ~= "!" and last ~= "?"
  if fm == "!FS!" then armed = s.armed end

  if linked then
    if not s.linked and not armed and now - s.lastSeen > NEW_PACK_GAP then newPack(now) end
    s.lastSeen = now
    local pos, sats = position(), sensor("Sats") or 0
    local ready = pos ~= nil and sats >= HOME_SATS
    if armed then
      if not s.armed then onArm(ready, pos) end
      flying(now, pos)
    else
      packCheck(now)
      gpsCallout(now, ready)
    end
    -- the last known arm state is kept through a link loss, so recovering isn't a new arm
    s.armed = armed
  end
  s.linked = linked

  if button then
    local down = (getValue(button) or 0) > 0
    if down and not buttonWas then status() end
    buttonWas = down
  end
end

return { init = init, run = run }
