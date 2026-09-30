-- FPVDash - telemetry dashboard for EdgeTX colour radios (ELRS or Crossfire + Betaflight)
-- Needs EdgeTX 2.11 or later (LVGL widget API). Use it on a Full screen layout.
-- Settings: copy config.example.lua to config.lua in this folder and edit it.
--
-- Three states, switched automatically:
--   Waiting  - radio on, no quad seen yet (or "Simulator mode" when no RF module is on)
--   Live     - linked; battery and link rings, mode, GPS, home, altitude, speed, mAh
--   Summary  - link dropped; last known position (also logged to SD) + flight stats
-- The view switch (SH by default) steps through pages: while linked, dashboard and GPS view;
-- otherwise the screen above, then Find (last saved position as a QR code for a phone's map)
-- and Logbook.

local VERSION = "1.0.0"

local options = {
  { "Cells", VALUE, 0, 0, 12 },   -- 0 = auto-detect per pack
}

-- Defaults, overridden by /WIDGETS/FPVDash/config.lua when it exists (see config.example.lua)
local CONFIG = {
  cells = { 4, 6 },        -- pack sizes flown, for auto-detect; their 3.0-4.4 V/cell ranges must not overlap
  quadNames = {},          -- logbook name by cell count; otherwise the model name
  homeSats = 8,            -- Betaflight's gps_rescue_min_sats: fewer at arming = no home
  viewSwitch = "sh",       -- momentary switch that steps through the pages; false for none
  switches = nil,          -- switch strip; nil builds it from the model's mixer
}
do
  local chunk = loadScript("/WIDGETS/FPVDash/config.lua")
  local ok, user = pcall(function() return chunk and chunk() end)
  if ok and type(user) == "table" then
    for k, v in pairs(user) do CONFIG[k] = v end
  end
end

local RESET_AFTER = 30 * 100      -- link down > 30 s then back = new flight (10 ms ticks)
local LOG_PATH    = "/LOGS/fpvdash-lastpos.txt"     -- one line per link loss or landing
local FLIGHTS_PATH = "/LOGS/fpvdash-flights.csv"    -- every flight, appended
local BOOK_PATH   = "/LOGS/fpvdash-logbook.txt"     -- per-quad totals and the latest flights
local QUAD_FOR_CELLS = CONFIG.quadNames
local HOME_SATS   = CONFIG.homeSats
local MIN_FLIGHT  = 10            -- seconds armed before a flight goes in the logbook
local BOOK_RECENT = 6
local PACK_CELLS  = CONFIG.cells
local floor, max, min = math.floor, math.max, math.min
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- Palette ---------------------------------------------------------------------
local RGB = lcd.RGB
local C = {
  bg    = RGB(0, 0, 0),
  track = RGB(24, 27, 33),
  rule  = RGB(36, 40, 47),
  ink   = RGB(245, 247, 250),
  dim   = RGB(154, 163, 174),
  faint = RGB(94, 102, 113),
  good  = RGB(46, 230, 166),
  warn  = RGB(255, 181, 71),
  bad   = RGB(255, 90, 95),
  info  = RGB(79, 195, 255),
}
local QR_INK, QR_PAPER = RGB(0, 0, 0), RGB(255, 255, 255)  -- phone cameras want dark on light

-- Geo & formatting --------------------------------------------------------------
local function distance(a, b)
  local r = math.rad
  local dLat, dLon = r(b.lat - a.lat), r(b.lon - a.lon)
  local h = math.sin(dLat / 2) ^ 2 + math.cos(r(a.lat)) * math.cos(r(b.lat)) * math.sin(dLon / 2) ^ 2
  return 6371000 * 2 * math.asin(min(1, math.sqrt(h)))
end

local function bearing(a, b)
  local r = math.rad
  local p1, p2, dl = r(a.lat), r(b.lat), r(b.lon - a.lon)
  local y = math.sin(dl) * math.cos(p2)
  local x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
  return (math.deg(atan2(y, x)) + 360) % 360
end

local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function compass(deg) return DIRS[floor(((deg % 360) + 22.5) / 45) % 8 + 1] end

local function distVU(d)
  if not d then return "--", "" end
  if d >= 1000 then return string.format("%.1f", d / 1000), "km" end
  return string.format("%d", floor(d + 0.5)), "m"
end

local function clock(s)
  s = floor(math.abs(s or 0))
  if s >= 3600 then return string.format("%d:%02d:%02d", floor(s / 3600), floor(s / 60) % 60, s % 60) end
  return string.format("%d:%02d", floor(s / 60), s % 60)
end

local MODES = {
  ACRO = { "ACRO", C.info }, AIR = { "AIR", C.info }, ANGL = { "ANGLE", C.good }, STAB = { "ANGLE", C.good },
  HOR = { "HORIZON", C.good }, RTH = { "RESCUE", C.warn }, WAIT = { "WAIT GPS", C.warn },
  ["!FS!"] = { "FAILSAFE", C.bad }, ["!ERR"] = { "CAN'T ARM", C.bad }, MANU = { "MANUAL", C.info },
}

-- disarmed, by the suffix Betaflight puts on the flight mode
local READY = { ["*"] = { "READY", C.good }, ["!"] = { "CAN'T ARM", C.warn }, ["?"] = { "NO RESCUE", C.warn } }

local function cellColor(v)
  if not v then return C.faint end
  return (v > 3.7 and C.good) or (v > 3.5 and C.warn) or C.bad
end

local function lqColor(q) return (q > 80 and C.good) or (q > 50 and C.warn) or C.bad end

-- State -----------------------------------------------------------------------
-- nil unless the value is current: EdgeTX keeps the last value after the link
-- drops, and a stale reading must not be taken for a live one
local function sensor(name)
  if getFieldInfo(name) == nil then return nil end
  if not getSourceValue then return getValue(name) end
  local v, current = getSourceValue(name)
  if current then return v end
end

local function packCells(v)
  local best, bestOff
  for _, n in ipairs(PACK_CELLS) do
    local c = v / n
    local off = (c < 3.0 and 3.0 - c) or (c > 4.4 and c - 4.4) or 0
    if not best or off < bestOff then best, bestOff = n, off end
  end
  return best or math.ceil(v / 4.35)
end

local function newStats() return { maxDist = 0, maxAlt = nil, maxSpd = 0, minCell = nil } end

local function reset(w)
  w.cells, w.home, w.last, w.lastDist, w.armedHome, w.stats = 0, nil, nil, nil, false, newStats()
  w.cellsLocked, w.flight = false, nil
  w.altSrc = getFieldInfo("Alt") and "Alt" or "GAlt"
end

local function quadName(cells)
  if QUAD_FOR_CELLS[cells] then return QUAD_FOR_CELLS[cells] end
  local info = model.getInfo()
  if info and info.name and info.name ~= "" then return info.name end
  return ((cells or 0) > 0 and (cells .. "S")) or "QUAD"
end

local function stamp()
  local dt = getDateTime()
  return string.format("%04d-%02d-%02d %02d:%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min), dt.sec
end

local function split(line)
  local fields = {}
  for x in string.gmatch(line, "[^,]+") do fields[#fields + 1] = x end
  return fields
end

-- A LOG_PATH line: "2026-09-29 18:20:05  45.500000,-73.600000  312m from home  5INCH  @1790...".
-- Older lines end after "from home".
local function parseLastPos(line)
  local lat, lon = string.match(line, "(%-?%d+%.%d+),(%-?%d+%.%d+)")
  if not lat then return nil end
  return { lat = tonumber(lat), lon = tonumber(lon), when = string.sub(line, 1, 16),
           dist = tonumber(string.match(line, "(%d+)m from home") or ""),
           quad = string.match(line, "from home  (%w+)"), epoch = tonumber(string.match(line, "@(%d+)") or "") }
end

local function saveLastPos(w)
  if not w.last then return end
  local when, sec = stamp()
  local line = string.format("%s:%02d  %.6f,%.6f  %s from home  %s  @%d", when, sec, w.last.lat, w.last.lon,
    w.lastDist and string.format("%dm", floor(w.lastDist + 0.5)) or "?", quadName(w.cells), getRtcTime())
  w.saved = parseLastPos(line)
  pcall(function()
    local f = io.open(LOG_PATH, "a")
    if not f then return end
    io.write(f, line .. "\n")
    io.close(f)
  end)
end

-- the newest line of LOG_PATH, so the find page survives a radio restart
local function loadLastPos(w)
  pcall(function()
    local info = fstat(LOG_PATH)
    local f = info and io.open(LOG_PATH, "r")
    if not f then return end
    io.seek(f, max(0, info.size - 200))
    local tail = io.read(f, 200)
    io.close(f)
    local last
    for line in string.gmatch(tail or "", "[^\n]+") do last = line end
    w.saved = last and parseLastPos(last)
  end)
end

-- Logbook. A flight is one arm to disarm (or to a link loss while armed). BOOK_PATH holds
-- "total,<quad>,<flights>,<seconds>" lines and the newest flights as "flight,<csv>", where
-- csv matches a FLIGHTS_PATH row: date, quad, seconds, lowest cell V, max distance m,
-- max altitude m, top speed km/h, mAh used, link lost (1/0); "-" when unknown.
local function parseFlight(csv)
  local f = split(csv)
  return { csv = csv, when = f[1], quad = f[2], secs = tonumber(f[3]) or 0, minCell = tonumber(f[4]),
           maxDist = tonumber(f[5]), maxAlt = tonumber(f[6]), maxSpd = tonumber(f[7]), mah = tonumber(f[8]),
           lost = f[9] == "1" }
end

local function loadBook(w)
  w.book = { totals = {}, recent = {} }
  pcall(function()
    local f = io.open(BOOK_PATH, "r")
    if not f then return end
    local text = io.read(f, 4096)
    io.close(f)
    for line in string.gmatch(text or "", "[^\n]+") do
      local kind, rest = string.match(line, "^(%a+),(.*)$")
      local t = rest and split(rest)
      if kind == "total" and #t >= 3 then
        w.book.totals[t[1]] = { flights = tonumber(t[2]) or 0, secs = tonumber(t[3]) or 0 }
      elseif kind == "flight" and #t >= 9 and #w.book.recent < BOOK_RECENT then
        w.book.recent[#w.book.recent + 1] = parseFlight(rest)
      end
    end
  end)
end

local function saveBook(w)
  local out = {}
  for quad, t in pairs(w.book.totals) do out[#out + 1] = string.format("total,%s,%d,%d", quad, t.flights, t.secs) end
  for _, r in ipairs(w.book.recent) do out[#out + 1] = "flight," .. r.csv end
  pcall(function()
    local f = io.open(BOOK_PATH, "w")
    if not f then return end
    io.write(f, table.concat(out, "\n") .. "\n")
    io.close(f)
  end)
end

local function endFlight(w, lost)
  local fl = w.flight
  w.flight = nil
  if not fl then return end
  local secs = floor((getTime() - fl.start) / 100)
  if secs < MIN_FLIGHT then return end
  local function num(x, fmt) return x and (fmt and string.format(fmt, x) or tostring(floor(x + 0.5))) or "-" end
  local used = w.capaNow and w.capaNow >= fl.capa0 and (w.capaNow - fl.capa0) or nil
  -- a props-off bench test doesn't move and draws a few mAh; a hover uses hundreds
  if (fl.maxDist or 0) < 10 and (fl.maxAlt or 0) < 2 and used and used < 30 then return end
  local quad = quadName(fl.cells)
  local csv = table.concat({ (stamp()), quad, tostring(secs), num(fl.minCell, "%.2f"), num(fl.maxDist),
    num(fl.maxAlt), num(fl.maxSpd), num(used), lost and "1" or "0" }, ",")
  pcall(function()
    local new = fstat(FLIGHTS_PATH) == nil
    local f = io.open(FLIGHTS_PATH, "a")
    if not f then return end
    if new then
      io.write(f, "date,quad,seconds,lowest_cell_v,max_distance_m,max_altitude_m,top_speed_kmh,used_mah,link_lost\n")
    end
    io.write(f, csv .. "\n")
    io.close(f)
  end)
  local t = w.book.totals[quad] or { flights = 0, secs = 0 }
  t.flights, t.secs = t.flights + 1, t.secs + secs
  w.book.totals[quad] = t
  table.insert(w.book.recent, 1, parseFlight(csv))
  while #w.book.recent > BOOK_RECENT do table.remove(w.book.recent) end
  saveBook(w)
end

local function track(w)
  local d = { now = getTime() }
  d.rqly = sensor("RQly")
  d.linked = d.rqly ~= nil and d.rqly > 0

  if d.linked then
    if not w.linked and w.lostAt and d.now - w.lostAt > RESET_AFTER then w.pendingReset = true end
    w.lostAt, w.seen = nil, true
  elseif w.linked then
    w.lostAt, w.page = d.now, 0
    saveLastPos(w)
    if w.armed then endFlight(w, true) end
  end
  w.linked = d.linked
  if not d.linked then return d end

  -- flight mode. While disarmed Betaflight ends it with * (ready to arm), ! (arming disabled)
  -- or ? (GPS Rescue not ready); 4.5 only ever used *. Nothing while armed. !FS! (failsafe) has
  -- no suffix either way, so it keeps the last known state. EdgeTX strings have no methods, so
  -- the string library is called directly.
  local fm = sensor("FM")
  if type(fm) == "string" and fm ~= "" then
    local last = string.sub(fm, -1)
    if fm == "!FS!" then
      d.armed, d.fm = w.armed, fm
    elseif last == "*" or last == "!" or last == "?" then
      d.armed, d.ready, d.fm = false, last, string.sub(fm, 1, -2)
    else
      d.armed, d.fm = true, fm
    end
  end

  -- a reconnect after a long gap is a new flight, unless the quad is still in the air
  if w.pendingReset and d.armed ~= nil then
    w.pendingReset = nil
    if not d.armed then
      reset(w)
      model.resetTimer(0)
    end
  end

  -- battery; the cell count follows the resting voltage until the first arm, then holds
  local v = sensor("RxBt")
  if v and v > 0.5 then
    local cells = w.options.Cells
    if cells == 0 then
      if not w.cellsLocked then w.cells = packCells(v) end
      w.cellsLocked = w.cellsLocked or d.armed == true
      cells = w.cells
    end
    d.v, d.cells, d.cell = v, cells, v / cells
    if d.armed and (not w.stats.minCell or d.cell < w.stats.minCell) then w.stats.minCell = d.cell end
  end
  d.capa = sensor("Capa")
  if d.capa then w.capaNow = d.capa end
  if d.capa and d.capa > 0 then w.stats.capa = d.capa end
  d.rssi, d.tpwr = sensor("1RSS"), sensor("TPWR")

  -- GPS; home = where it armed with enough satellites (Betaflight's rescue home), else the
  -- first solid fix, for distances only
  local gps = sensor("GPS")
  d.sats = sensor("Sats") or 0
  d.fix = type(gps) == "table" and gps.lat ~= 0 and d.sats >= 5
  local alt = sensor(w.altSrc)
  d.spd, d.hdg = sensor("GSpd"), sensor("Hdg")
  if d.spd and d.spd > w.stats.maxSpd then w.stats.maxSpd = d.spd end

  if d.fix then
    local pos = { lat = gps.lat, lon = gps.lon }
    w.last = pos
    if d.armed and not w.armed and not w.armedHome and d.sats >= HOME_SATS then
      w.home, w.armedHome = { lat = pos.lat, lon = pos.lon, alt = alt or 0 }, true
    elseif w.home == nil and d.sats >= 6 then
      w.home = { lat = pos.lat, lon = pos.lon, alt = alt or 0 }
    end
    if w.home then
      d.dist = distance(w.home, pos)
      d.toHome = bearing(pos, w.home)
      w.lastDist = d.dist
      if d.dist > w.stats.maxDist then w.stats.maxDist = d.dist end
      if alt then
        d.alt = alt - w.home.alt
        if not w.stats.maxAlt or d.alt > w.stats.maxAlt then w.stats.maxAlt = d.alt end
      end
    end
  end

  local fl = w.flight
  if d.armed then
    if not fl then
      fl = { start = d.now, capa0 = d.capa or 0, cells = d.cells or w.cells, maxDist = 0, maxSpd = 0 }
      w.flight = fl
    end
    if d.cell and (not fl.minCell or d.cell < fl.minCell) then fl.minCell = d.cell end
    if d.dist and d.dist > fl.maxDist then fl.maxDist = d.dist end
    if d.alt and (not fl.maxAlt or d.alt > fl.maxAlt) then fl.maxAlt = d.alt end
    if d.spd and d.spd > fl.maxSpd then fl.maxSpd = d.spd end
  elseif d.armed == false and fl then
    saveLastPos(w)
    endFlight(w, false)
  end
  if d.armed ~= nil then w.armed = d.armed end
  return d
end

-- View ------------------------------------------------------------------------
-- Designed at 800x480 and scaled to the zone. EdgeTX's font sizes don't scale with the
-- screen, so each text slot picks the largest font that fits and vertical spacing follows
-- the chosen fonts. LVGL wants whole pixels, so every coordinate is rounded.
local RING0, RING_SWEEP = 135, 270          -- gauge arc: 0 deg is 3 o'clock, clockwise
local VIEW_SWITCH = CONFIG.viewSwitch or nil -- momentary; each press steps to the next page
local XLFONT = XLSIZE or DBLSIZE           -- XLSIZE sits between DBLSIZE and XXLSIZE; older EdgeTX lacks it
local UNIT_FOR = { [XXLSIZE] = MIDSIZE, [XLFONT] = MIDSIZE, [DBLSIZE] = 0, [MIDSIZE] = SMLSIZE, [0] = SMLSIZE,
                   [SMLSIZE] = TINSIZE, [TINSIZE] = TINSIZE }

-- The switch strip: tiles of { name, function, positions (up, middle, down) }, a position being
-- { text, colour, live } where a live position tints the tile; pots show their level and the
-- view switch names the page on screen. Built in build() from CONFIG.switches or, by default,
-- from the model's mixer. Quiet tiles show their position in the small font.
local SWITCHES = {}
local VIEW_STATES = { { "DASH", C.dim }, { "GPS", C.info }, { "FIND", C.info }, { "LOG", C.info } }
local NAMED = { ink = C.ink, dim = C.dim, faint = C.faint, good = C.good, warn = C.warn, bad = C.bad, info = C.info }

-- a configured position: "TEXT", "TEXT!" (live, amber), "TEXT!!" (live, red) or { text, colour, live }
local function position(p, first)
  if type(p) == "table" then return { p[1], NAMED[p[2]] or C.info, p[3] } end
  local text, bangs = string.match(p, "^(.-)(!*)$")
  if bangs == "!!" then return { text, C.bad, true } end
  if bangs == "!" then return { text, C.warn, true } end
  return { text, first and C.dim or C.info }
end

local function configSwitches(list)
  local out = {}
  for _, e in ipairs(list) do
    if e.view then
      out[#out + 1] = { e[1], e[2] or "VIEW", VIEW_STATES, momentary = true }
    elseif e.pot then
      out[#out + 1] = { e[1], e[2], pot = { string.lower(e[1]) } }
    else
      local ps = {}
      for i = 3, #e do ps[#ps + 1] = position(e[i], i == 3) end
      out[#out + 1] = { e[1], e[2], ps, quiet = e.quiet }
    end
  end
  return out
end

-- one tile per channel driven by a switch or knob, labelled with the channel's name
local function autoSwitches()
  local out = {}
  local view = VIEW_SWITCH and string.upper(VIEW_SWITCH)
  for ch = 0, 15 do
    local mix = (model.getMixesCount(ch) or 0) > 0 and model.getMix(ch, 0)
    -- menus prefix switch names with a glyph; ASCII ranges keep the match locale-independent
    local name = mix and string.match(getSourceName(mix.source) or "", "(S[A-Z0-9]+)$")
    local knob = name and string.match(name, "^S[0-9]$")
    if name and name ~= view and (knob or string.match(name, "^S[A-Z]$") or string.match(name, "^SW[0-9]$")) then
      local output = model.getOutput(ch)
      local label = (output and output.name ~= "" and string.upper(output.name)) or ("CH" .. (ch + 1))
      if knob then
        out[#out + 1] = { name, label, pot = { mix.source } }
      else
        out[#out + 1] = { name, label, { { "UP", C.dim }, { "MID", C.info }, { "DOWN", C.info } }, src = mix.source }
      end
    end
  end
  if view then out[#out + 1] = { view, "VIEW", VIEW_STATES, momentary = true } end
  return out
end

local function textW(s, f) return (lcd.sizeText(s, f)) end
local function textH(f) return select(2, lcd.sizeText("0", f)) end
local function baseline(y, fromH, toH) return floor(y + (fromH - toH) * 0.79 + 0.5) end

local function fit(ref, maxW, fonts)
  for _, f in ipairs(fonts) do
    if textW(ref, f) <= maxW then return f end
  end
  return fonts[#fonts]
end

-- largest value font where "value unit" fits in maxW
local function fitPair(value, unit, maxW, gap, fonts)
  for _, f in ipairs(fonts) do
    if textW(value, f) + gap + textW(unit, UNIT_FOR[f]) <= maxW then return f end
  end
  return fonts[#fonts]
end

-- x of a value+unit pair centred on cx, and the unit's x
local function pairX(cx, value, vf, unit, uf, gap)
  local vw = textW(value, vf)
  local uw = (unit ~= "") and (gap + textW(unit, uf)) or 0
  local x = floor(cx - (vw + uw) / 2 + 0.5)
  return x, x + vw + gap
end

local function arcEnd(frac) return floor(RING0 + RING_SWEEP * max(0, min(1, frac)) + 0.5) % 360 end

-- point at `ang` radians (0 = up) and `rad` from cx,cy; triangles take unsigned points
local function pt(cx, cy, ang, rad)
  return { max(0, floor(cx + math.sin(ang) * rad + 0.5)), max(0, floor(cy - math.cos(ang) * rad + 0.5)) }
end

local function needle(cx, cy, r, deg, half)
  local a = math.rad(deg)
  return { pt(cx, cy, a, r), pt(cx, cy, a + math.pi / 2, half), pt(cx, cy, a - math.pi / 2, half) }
end

-- one half of a notched navigation arrow pointing `deg`
local function navArrow(cx, cy, r, deg, side)
  local a = math.rad(deg)
  local tip, notch = pt(cx, cy, a, r), pt(cx, cy, a + math.pi, r * 0.3)
  return { tip, pt(cx, cy, a + side * math.rad(142), r), notch }
end

local function viewLive(w, d)
  local v, L, F = w.v, w.L, w.F
  local m = d.fm and (MODES[d.fm] or { d.fm, C.info }) or { "NO MODE", C.faint }
  v.mode, v.modeColor, v.modeSolid = m[1], m[2], m[2] == C.bad
  v.modeW = textW(v.mode, F.chip) + 2 * L.chipPad
  v.armed = d.armed ~= nil
  local st = d.armed and { "ARMED", C.bad } or READY[d.ready] or { "DISARMED", C.dim }
  v.armedText, v.armedColor, v.armedSolid = st[1], st[2], d.armed == true
  v.armedW = textW(v.armedText, F.chip) + 2 * L.chipPad

  local t = model.getTimer(0)
  v.timer = clock(t and t.value)
  local timerX = L.right - textW(v.timer, F.timer)
  if d.sats == 0 then v.gpsNum, v.gpsText, v.gpsColor = "", "NO GPS", C.bad
  elseif not d.fix then v.gpsNum, v.gpsText, v.gpsColor = tostring(d.sats), "SATS  NO FIX", C.bad
  elseif d.armed and not w.armedHome then v.gpsNum, v.gpsText, v.gpsColor = tostring(d.sats), "SATS  NO HOME", C.bad
  else v.gpsNum, v.gpsText, v.gpsColor = tostring(d.sats), "SATS", (d.sats >= HOME_SATS and C.good or C.warn) end
  v.gpsTextX = timerX - L.gap - textW(v.gpsText, F.gps)
  v.gpsNumX = v.gpsTextX - ((v.gpsNum ~= "") and (textW(v.gpsNum, F.chip) + L.small) or 0)
  v.gpsDotX = v.gpsNumX - L.small - L.dot

  -- rings: the arc carries the state colour, the number only when something is wrong
  if d.cell then
    v.bat = string.format("%.2f", d.cell)
    v.batUnit, v.batSub = "V", string.format("%dS   %.1f V", d.cells, d.v)
    v.batColor, v.batFrac = cellColor(d.cell), (d.cell - 3.3) / 0.9
    v.batInk = (d.cell > 3.7) and C.ink or v.batColor
  else
    v.bat, v.batUnit, v.batSub, v.batColor, v.batFrac, v.batInk = "--", "", "NO VOLTAGE DATA", C.faint, nil, C.faint
  end
  v.batX, v.batUnitX = pairX(L.ring1, v.bat, F.hero, v.batUnit, F.heroUnit, L.small)

  local lq = d.rqly or 0
  v.lq, v.lqColor, v.lqFrac = tostring(lq), lqColor(lq), lq / 100
  v.lqInk = (lq > 80) and C.ink or v.lqColor
  local sub = {}
  if d.rssi then sub[#sub + 1] = string.format("%d dBm", d.rssi) end
  if d.tpwr then sub[#sub + 1] = string.format("%d mW", d.tpwr) end
  v.lqSub = table.concat(sub, "   ")
  v.lqX, v.lqUnitX = pairX(L.ring2, v.lq, F.hero, "%", F.heroUnit, L.small)

  -- instrument row
  local dv, du = distVU(d.dist)
  v.m = {
    { dv, du },
    { d.alt and string.format("%d", floor(d.alt + 0.5)) or "--", d.alt and "m" or "" },
    { d.spd and string.format("%d", floor(d.spd + 0.5)) or "--", d.spd and "km/h" or "" },
    { (d.capa and d.capa > 0) and string.format("%d", d.capa) or "--", (d.capa and d.capa > 0) and "mAh" or "" },
  }
  for i, it in ipairs(v.m) do
    it.ux = L.colX[i] + textW(it[1], F.value) + L.small
    it.color = (it[1] == "--") and C.faint or C.ink
  end
  local showArrow = d.dist and d.dist > 5 and d.hdg and d.spd and d.spd >= 3
  v.arrowDeg = showArrow and (d.toHome - d.hdg) or nil
  v.arrowX = v.m[1].ux + textW(v.m[1][2], F.unit) + L.arrowGap
end

local function placeStats(w, list)
  local L, F = w.L, w.F
  for i, it in ipairs(list) do
    it.ux = L.statX[(i - 1) % 3 + 1] + textW(it[1], F.sStat) + L.small
    it.color = (it[1] == "--") and C.faint or (it[3] or C.ink)
  end
end

-- GPS view while linked: the summary's layout with live data
local function viewNav(w, d)
  local v, L, F = w.v, w.L, w.F
  local pos = d.fix and w.last or nil
  v.nHasHome = (w.home and pos and d.dist) and true or false
  if v.nHasHome then
    v.nBearing = bearing(w.home, pos)
    v.nDist, v.nDistUnit = distVU(d.dist)
    v.nDir = compass(v.nBearing) .. " OF HOME"
  else
    v.nBearing, v.nDist, v.nDistUnit = 0, "--", ""
    v.nDir = pos and "NO HOME POINT" or "WAITING FOR GPS FIX"
  end
  v.nDistUnitX = L.infoX + textW(v.nDist, F.sDist) + L.small
  v.nPos = pos and string.format("%.6f, %.6f", pos.lat, pos.lon) or "No GPS fix"
  v.nStats = {
    { d.alt and string.format("%d", floor(d.alt + 0.5)) or "--", d.alt and "m" or "" },
    { d.spd and string.format("%d", floor(d.spd + 0.5)) or "--", d.spd and "km/h" or "" },
    { d.hdg and string.format("%d", floor(d.hdg + 0.5) % 360) or "--", d.hdg and "deg" or "" },
    { d.cell and string.format("%.2f", d.cell) or "--", d.cell and "V" or "", cellColor(d.cell) },
    { d.rqly and tostring(d.rqly) or "--", d.rqly and "%" or "", d.rqly and lqColor(d.rqly) },
    { (d.capa and d.capa > 0) and string.format("%d", d.capa) or "--", (d.capa and d.capa > 0) and "mAh" or "" },
  }
  placeStats(w, v.nStats)
end

local function viewSummary(w, d)
  local v, L, F, s = w.v, w.L, w.F, w.stats
  local lost = (w.lastDist or 0) > 30
  v.sTitle = lost and "LINK LOST" or "FLIGHT SUMMARY"
  v.sColor, v.sSolid = lost and C.bad or C.info, lost
  v.sTitleW = textW(v.sTitle, F.chip) + 2 * L.chipPad
  v.sAgo = w.lostAt and ((lost and "SIGNAL LOST " or "ENDED ") .. clock((d.now - w.lostAt) / 100) .. " AGO") or ""

  v.sHasHome = (w.home and w.lastDist and w.last) and true or false
  if v.sHasHome then
    v.sBearing = bearing(w.home, w.last)
    v.sDist, v.sDistUnit = distVU(w.lastDist)
    v.sDir = compass(v.sBearing) .. " OF HOME"
  else
    v.sBearing, v.sDist, v.sDistUnit, v.sDir = 0, "--", "", "NO HOME POINT"
  end
  v.sDistUnitX = L.infoX + textW(v.sDist, F.sDist) + L.small
  v.sPos = w.last and string.format("%.6f, %.6f", w.last.lat, w.last.lon) or "No GPS fix this flight"

  local t = model.getTimer(0)
  local md, mu = distVU(s.maxDist > 0 and s.maxDist or nil)
  v.sStats = {
    { md, mu },
    { s.maxAlt and string.format("%d", floor(s.maxAlt + 0.5)) or "--", s.maxAlt and "m" or "" },
    { s.maxSpd > 0 and string.format("%d", floor(s.maxSpd + 0.5)) or "--", s.maxSpd > 0 and "km/h" or "" },
    { s.minCell and string.format("%.2f", s.minCell) or "--", s.minCell and "V" or "", cellColor(s.minCell) },
    { (s.capa and s.capa > 0) and string.format("%d", s.capa) or "--", (s.capa and s.capa > 0) and "mAh" or "" },
    { clock(t and t.value), "" },
  }
  placeStats(w, v.sStats)
end

local function ago(secs)
  if secs < 60 then return "Just now" end
  local m = floor(secs / 60)
  if m < 60 then return m .. " min ago" end
  local h = floor(m / 60)
  if h < 48 then return h .. " h " .. (m % 60) .. " min ago" end
  return floor(h / 24) .. " days ago"
end

-- last saved position, as text and as a map link for the QR code
local function viewFind(w)
  local v, s = w.v, w.saved
  v.fHas = s ~= nil
  if not s then
    v.fQR, v.fPos, v.fAgo, v.fWhen, v.fDist = nil, "", "", "", ""
    return
  end
  v.fQR = string.format("https://maps.google.com/?q=%.6f,%.6f", s.lat, s.lon)
  v.fPos = string.format("%.6f, %.6f", s.lat, s.lon)
  local secs = s.epoch and (getRtcTime() - s.epoch)
  v.fAgo = (secs and secs >= 0) and ago(secs) or s.when
  v.fWhen = s.when .. (s.quad and ("   " .. s.quad) or "")
  v.fDist = s.dist and (s.dist .. " m from home") or "Distance from home unknown"
end

local function hm(secs)
  local m = floor(secs / 60 + 0.5)
  return (m >= 60) and string.format("%d h %02d min", floor(m / 60), m % 60) or (m .. " min")
end

local function viewLog(w)
  local v, b = w.v, w.book
  -- the two quads with the most flights
  local quads = {}
  for quad in pairs(b.totals) do quads[#quads + 1] = quad end
  table.sort(quads, function(a, c) return b.totals[a].flights > b.totals[c].flights end)
  v.lTotals = {}
  for i = 1, 2 do
    local t = quads[i] and b.totals[quads[i]]
    v.lTotals[i] = t and { string.sub(quads[i], 1, 15), t.flights == 1 and "1 flight" or (t.flights .. " flights"), hm(t.secs) }
                   or { "", "", "" }
  end
  v.lRows = {}
  for i = 1, BOOK_RECENT do
    local r = b.recent[i]
    if r then
      local dv, du = distVU(r.maxDist)
      v.lRows[i] = {
        string.sub(r.when, 6), string.sub(r.quad, 1, 9), clock(r.secs),
        r.minCell and string.format("%.2f V", r.minCell) or "--",
        r.maxDist and (dv .. " " .. du) or "--",
        r.lost and "LINK LOST" or (r.mah and (r.mah .. " mAh") or "--"),
        color = r.lost and C.bad or C.ink,
      }
    else
      v.lRows[i] = { "", "", "", "", "", "", color = C.ink }
    end
  end
  v.lEmpty = b.recent[1] == nil
end

-- the radio's own battery against its settings (battery range and low-battery warning), as the
-- EdgeTX top bar shows it; smoothed so the reading doesn't flicker with load
local function viewRadio(w)
  local v, g = w.v, w.gs
  local volts = getValue("tx-voltage") or 0
  w.txV = w.txV and (w.txV + (volts - w.txV) * 0.05) or volts
  local span = g.battMax - g.battMin
  local frac = span > 0 and max(0, min(1, (w.txV - g.battMin) / span)) or 0
  v.txFrac, v.txPct = frac, string.format("%d%%", floor(frac * 100 + 0.5))
  v.txVolts = string.format("%.1f V", w.txV)
  v.txColor = (w.txV <= g.battWarn and C.bad) or (frac < 0.35 and C.warn) or C.good
end

local function view(w, d)
  local v = w.v
  if d.linked then
    v.screen = w.navView and "nav" or "live"
    viewLive(w, d)
    if v.screen == "nav" then viewNav(w, d) end
  elseif w.page == 1 then
    v.screen = "find"
    viewFind(w)
  elseif w.page == 2 then
    v.screen = "log"
    viewLog(w)
  else
    v.screen = w.seen and "summary" or "waiting"
    if v.screen == "summary" then viewSummary(w, d) end
  end
end

-- The view switch steps through the pages: dashboard and GPS view while linked, otherwise the waiting or
-- summary screen, the find page and the logbook
local function readViewSwitch(w)
  if not VIEW_SWITCH then return end
  local down = (getValue(VIEW_SWITCH) or 0) > 0
  if down and not w.viewDown then
    if w.linked then w.navView = not w.navView else w.page = (w.page + 1) % 3 end
  end
  w.viewDown = down
end

-- switch positions come straight from the radio, so the strip follows a flip at once
local function viewSwitches(w)
  for i, s in ipairs(SWITCHES) do
    local t = w.v.sw[i]
    local raw = t.src and getValue(t.src)
    if s.pot then
      t.level = raw and floor((raw + 1024) * 100 / 2048 + 0.5) or 0
      t.state, t.color, t.hot, t.font = raw and (t.level .. "%") or "--", C.dim, false, t.fonts[1]
    else
      local n = #s[3]
      if s.momentary then
        -- the state names the page on screen; the dots show the button itself
        t.pos = w.linked and (w.navView and 2 or 1) or ((w.page == 0) and 1 or w.page + 2)
        t.dot = ((raw or 0) > 0) and 2 or 1
      elseif not raw then
        t.pos = nil
      elseif n == 2 then
        t.pos = (raw > 0) and 2 or 1
      else
        t.pos = (raw < -512 and 1) or (raw > 512 and 3) or 2
      end
      local st = t.pos and s[3][t.pos]
      t.state, t.color, t.hot = st and st[1] or "--", st and st[2] or C.faint, st and st[3] or false
      t.font = t.pos and t.fonts[t.pos] or SMLSIZE
    end
  end
end

-- the SIM model has no RF module on and is used as a USB joystick
local function isSim()
  for i = 0, 1 do
    local m = model.getModule(i)
    if m and m.Type and m.Type ~= 0 then return false end
  end
  return true
end

-- the QR code's data is fixed once built, so a new position means a new QR object
local function syncQR(w)
  local want = w.v.fHas and w.v.fQR or nil
  local box = w.refs and w.refs.qr
  if want == w.qrShown or not box then return end
  box:clear()
  if want then
    box:build({ { type = "qrcode", x = 0, y = 0, w = w.L.qrSide, h = w.L.qrSide, data = want,
                  color = QR_INK, bgColor = QR_PAPER } })
  end
  w.qrShown = want
end

-- Layout ------------------------------------------------------------------------
local function build(w)
  local ok, list = pcall(function()
    return CONFIG.switches and configSwitches(CONFIG.switches) or autoSwitches()
  end)
  SWITCHES = ok and list or {}
  local W, H = w.zone.w, w.zone.h
  local k = min(W / 800, H / 480)
  local function P(n) return floor(n * k + 0.5) end
  local v = w.v
  local M = P(28)
  local L = { right = W - M, gap = P(22), small = P(6), dot = max(2, P(5)), chipPad = P(16), arrowGap = P(24),
              ring1 = floor(W / 4 + 0.5), ring2 = floor(W * 3 / 4 + 0.5), colX = {}, statX = {} }
  local F = {}
  w.L, w.F = L, F

  -- a band along the bottom of every screen holds the radio battery; every page ends above it
  F.tx = SMLSIZE
  local bandH = textH(F.tx) + P(8)
  local Hc = H - bandH

  -- top bar
  F.chip = BOLD
  F.timer = fit("8:88:88", P(220), { DBLSIZE, MIDSIZE, 0 })
  F.gps = fit("SATS  NO HOME", P(170), { SMLSIZE, TINSIZE })
  local chipH = textH(F.chip) + P(12)
  local chipY = P(18)
  local top = chipY + chipH + P(6)
  local topMid = chipY + floor(chipH / 2)

  -- switch strip (dashboard and waiting screen): one tile per control, widths follow the words
  F.swLabel, F.swFunc = SMLSIZE, TINSIZE
  -- the position indicator sits beside the switch label, so the rows below get the full width
  local swPad, swGap, stripX, stripY = P(7), P(4), P(8), P(8)
  local dotR, dotStep = max(2, P(2)), max(4, P(7))
  local natural, total = {}, 0
  for i, s in ipairs(SWITCHES) do
    local wmax = max(textW(s[1], F.swLabel) + P(6) + 2 * dotR, textW(s[2], F.swFunc))
    for _, st in ipairs(s[3] or { { "100%" } }) do wmax = max(wmax, textW(st[1], s.quiet and TINSIZE or SMLSIZE)) end
    natural[i] = wmax + 2 * swPad
    total = total + natural[i]
  end
  local avail = W - 2 * stripX - (#SWITCHES - 1) * swGap
  local tileH = (#SWITCHES > 0) and (P(6) + textH(F.swLabel) + textH(F.swFunc) + textH(SMLSIZE) + P(6)) or 0
  local stripBottom = stripY + tileH
  L.tiles = {}
  v.sw = {}
  local tx = stripX
  for i, s in ipairs(SWITCHES) do
    local tw = floor(natural[i] * avail / total)
    local room = tw - 2 * swPad
    local fonts = {}
    for j, st in ipairs(s[3] or { { "100%" } }) do
      fonts[j] = s.quiet and TINSIZE or fit(st[1], room, { SMLSIZE, TINSIZE })
    end
    L.tiles[i] = { x = tx, w = tw }
    local src = s.src
    for _, name in ipairs(s.pot or { string.lower(s[1]) }) do
      if not src and (type(name) == "number" or getFieldInfo(name)) then src = name end
    end
    v.sw[i] = { src = src, fonts = fonts, level = 0 }
    tx = tx + tw + swGap
  end
  local dashChipY = stripBottom + P(10)
  local dashTop = dashChipY + chipH + P(6)

  -- instrument row, stacked up from the bottom edge
  local colW = (W - 2 * M) / 4
  for i = 1, 4 do L.colX[i] = floor(M + (i - 1) * colW + (i > 1 and P(20) or 0) + 0.5) end
  F.value = fitPair("1680", "mAh", colW - P(24), L.small, { DBLSIZE, MIDSIZE, 0 })
  F.unit = UNIT_FOR[F.value]
  F.label = fit("ALTITUDE", colW - P(24), { SMLSIZE, TINSIZE })
  local valueH = textH(F.value)
  local valueY = Hc - P(4) - valueH
  local labelY = valueY - textH(F.label) - P(2)
  local hairY = labelY - P(14)

  -- rings fill the space between: the ticks reach R + tickOut above the centre, the title
  -- label ends at 0.64 R + its height below it, and both keep clear of their neighbours
  local tickOut, titleGap = P(22) + P(6), P(14)
  local R = floor(min(P(132), (hairY - titleGap - textH(SMLSIZE) - dashTop - tickOut) / 1.64, W / 4 - P(30)))
  local T = max(4, P(18))
  local cy = dashTop + tickOut + R
  local inner = 2 * (R - T - P(12))
  F.hero = fitPair("8.88", "V", inner, L.small, { XXLSIZE, XLFONT, DBLSIZE, MIDSIZE })
  F.heroUnit = UNIT_FOR[F.hero]
  F.sub = fit("-100 dBm   250 mW", inner, { 0, SMLSIZE, TINSIZE })
  F.title = fit("LINK QUALITY", floor(R * 1.2), { SMLSIZE, TINSIZE })

  -- summary: compass on the left, details stacked on the right
  L.infoX = P(330)
  local infoW = W - M - L.infoX
  for i = 1, 3 do L.statX[i] = floor(L.infoX + (i - 1) * infoW / 3 + 0.5) end
  local statW = floor(infoW / 3) - P(10)
  -- tier 1: everything; 2: without the two section labels; 3: smaller fonts as well
  local function stackSummary(tier)
    local compact = tier == 3
    F.sLabel = compact and TINSIZE or fit("MAX DISTANCE", statW, { SMLSIZE, TINSIZE })
    F.sDist = compact and DBLSIZE or fitPair("88.8", "km", infoW, L.small, { XXLSIZE, DBLSIZE })
    F.sPos = compact and 0 or fit("-88.888888, -888.888888", infoW, { MIDSIZE, 0, SMLSIZE })
    F.sStat = compact and 0 or fitPair("1316", "mAh", statW, L.small, { MIDSIZE, 0 })
    F.sDir = 0
    local S, y = { labels = tier == 1 }, top + P(8)
    if S.labels then S.distLabel = y; y = y + textH(F.sLabel) end
    S.dist = y; y = y + textH(F.sDist) - P(8)
    S.dir = y; y = y + textH(F.sDir) + P(14)
    if S.labels then S.posLabel = y; y = y + textH(F.sLabel) end
    S.pos = y; y = y + textH(F.sPos) + P(14)
    S.hair = y; y = y + P(14)
    S.row1 = y; y = y + textH(F.sLabel) + textH(F.sStat) + P(12)
    S.row2 = y; y = y + textH(F.sLabel) + textH(F.sStat)
    return S, y
  end
  local S, bottom
  for tier = 1, 3 do
    S, bottom = stackSummary(tier)
    if bottom <= Hc - P(4) then break end
  end

  -- every property function runs as soon as its object is built, hidden screens included
  viewSwitches(w)
  viewLive(w, { now = getTime(), sats = 0 })
  viewRadio(w)
  view(w, { linked = false, now = getTime() })

  local function on(screen) return function() return v.screen == screen end end
  local function add(list, objs) for _, o in ipairs(objs) do list[#list + 1] = o end end
  local stdH, chipTH = textH(0), textH(F.chip)

  -- translucent chip, solid when the state is critical
  local function chip(y, getText, getColor, getSolid, getW, getX)
    local ty = y + floor((chipH - chipTH) / 2 + 0.5)
    return {
      { type = "rectangle", x = M, y = y, w = P(120), h = chipH, filled = true, rounded = floor(chipH / 2),
        color = getColor, opacity = function() return getSolid() and 255 or 60 end,
        size = function() return getW(), chipH end, pos = function() return getX(), y end },
      { type = "label", x = M + L.chipPad, y = ty, font = F.chip, text = getText,
        color = function() return getSolid() and C.ink or getColor() end,
        pos = function() return getX() + L.chipPad, ty end },
    }
  end

  local function ring(cx, getText, getInk, getUnit, getSub, getColor, getFrac, getNumX, getUnitX, title)
    local heroH, subH = textH(F.hero), textH(F.sub)
    local numY = cy - floor((heroH + subH - P(6)) / 2 + 0.5) - P(12)
    local unitY = baseline(numY, heroH, textH(F.heroUnit))
    local lit = function() return (getFrac() or 0) > 0.005 end
    local objs = {
      { type = "arc", x = cx, y = cy, radius = R + P(9), thickness = T + P(18), rounded = true,
        startAngle = RING0, endAngle = function() return arcEnd(getFrac() or 0) end,
        bgStartAngle = RING0, bgEndAngle = RING0 + 1, bgOpacity = 0,
        color = getColor, opacity = 40, visible = lit },
      { type = "arc", x = cx, y = cy, radius = R, thickness = T, rounded = true,
        startAngle = RING0, endAngle = function() return arcEnd(getFrac() or 0) end,
        bgStartAngle = RING0, bgEndAngle = (RING0 + RING_SWEEP) % 360, bgColor = C.track, bgOpacity = 255,
        color = getColor, opacity = function() return lit() and 255 or 0 end },
      { type = "label", x = cx - R, y = numY, font = F.hero, text = getText, color = getInk,
        pos = function() return getNumX(), numY end },
      { type = "label", x = cx, y = unitY, font = F.heroUnit, text = getUnit, color = C.dim,
        pos = function() return getUnitX(), unitY end },
      { type = "label", x = cx - R, y = numY + heroH - P(6), w = 2 * R, align = CENTER, font = F.sub,
        text = getSub, color = C.dim },
      { type = "label", x = cx - R, y = cy + floor(R * 0.64 + 0.5), w = 2 * R, align = CENTER, font = F.title,
        text = title, color = C.faint },
    }
    for f = 0, 4 do
      local a = math.rad(RING0 + RING_SWEEP * f / 4)
      local r1, r2 = R + P(14), R + P(22)
      objs[#objs + 1] = { type = "line", color = C.rule, thickness = max(1, P(2)), rounded = true,
        pts = { { floor(cx + math.cos(a) * r1 + 0.5), floor(cy + math.sin(a) * r1 + 0.5) },
                { floor(cx + math.cos(a) * r2 + 0.5), floor(cy + math.sin(a) * r2 + 0.5) } } }
    end
    return objs
  end

  -- top bar: mode and armed chips, GPS and timer; the dashboard's sits under the switch strip
  local function topBar(y)
    local list, mid = {}, y + floor(chipH / 2)
    add(list, chip(y, function() return v.mode end, function() return v.modeColor end,
      function() return v.modeSolid end, function() return v.modeW end, function() return M end))
    local armed = chip(y, function() return v.armedText end, function() return v.armedColor end,
      function() return v.armedSolid end, function() return v.armedW end, function() return M + v.modeW + P(10) end)
    for _, o in ipairs(armed) do o.visible = function() return v.armed end end
    add(list, armed)
    local gpsNumY = mid - floor(chipTH / 2 + 0.5)
    local gpsTextY = baseline(gpsNumY, chipTH, textH(F.gps))
    add(list, {
      { type = "label", x = L.right - P(240), y = mid - floor(textH(F.timer) / 2 + 0.5), w = P(240), align = RIGHT,
        font = F.timer, text = function() return v.timer end, color = C.ink },
      { type = "circle", x = M, y = mid, radius = L.dot, filled = true, color = function() return v.gpsColor end,
        pos = function() return v.gpsDotX, mid end },
      { type = "label", x = M, y = gpsNumY, font = F.chip, text = function() return v.gpsNum end, color = C.ink,
        pos = function() return v.gpsNumX, gpsNumY end },
      { type = "label", x = M, y = gpsTextY, font = F.gps, text = function() return v.gpsText end, color = C.dim,
        pos = function() return v.gpsTextX, gpsTextY end },
    })
    return list
  end

  -- switch strip: label, function and live state per control, dots for the physical position
  local strip = {}
  local labelH, funcH, smlH, tinH = textH(F.swLabel), textH(F.swFunc), textH(SMLSIZE), textH(TINSIZE)
  for i, s in ipairs(SWITCHES) do
    local t, x, tw = v.sw[i], L.tiles[i].x, L.tiles[i].w
    local lx, stateY = x + swPad, stripY + P(6) + labelH + funcH
    local midY, dotX = stripY + P(6) + floor(labelH / 2 + 0.5), x + tw - swPad - dotR
    add(strip, {
      { type = "rectangle", x = x, y = stripY, w = tw, h = tileH, filled = true, rounded = P(10),
        color = function() return t.hot and t.color or C.track end,
        opacity = function() return t.hot and 72 or 255 end },
      { type = "label", x = lx, y = stripY + P(6), font = F.swLabel, text = s[1], color = C.ink },
      { type = "label", x = lx, y = stripY + P(6) + labelH, font = F.swFunc, text = s[2], color = C.faint },
      { type = "label", x = lx, y = stateY, text = function() return t.state end,
        color = function() return t.color end, font = function() return t.font end,
        pos = function() return lx, stateY + ((t.font == TINSIZE) and floor((smlH - tinH) * 0.79 + 0.5) or 0) end },
    })
    if s.pot then
      local barH, barW = 2 * dotStep + 2 * dotR, max(2, P(3))
      local barY = midY - floor(barH / 2)
      add(strip, {
        { type = "rectangle", x = dotX - floor(barW / 2), y = barY, w = barW, h = barH, filled = true,
          rounded = floor(barW / 2), color = C.rule },
        { type = "rectangle", x = dotX - floor(barW / 2), y = barY, w = barW, h = barH, filled = true,
          rounded = floor(barW / 2), color = C.dim,
          size = function() return barW, max(barW, floor(barH * t.level / 100 + 0.5)) end,
          pos = function() return dotX - floor(barW / 2), barY + barH - max(barW, floor(barH * t.level / 100 + 0.5)) end },
      })
    else
      local n = s.momentary and 2 or #s[3]
      for j = 1, n do
        local dy = (n == 2) and ((j == 1) and -dotStep or dotStep) or (j - 2) * dotStep
        strip[#strip + 1] = { type = "circle", x = dotX, y = midY + dy, radius = dotR, filled = true,
          color = function()
            if (t.dot or t.pos) ~= j then return C.rule end
            return (t.color == C.faint or t.color == C.dim) and C.ink or t.color
          end }
      end
    end
  end

  -- dashboard
  local live = topBar(dashChipY)
  add(live, ring(L.ring1, function() return v.bat end, function() return v.batInk end, function() return v.batUnit end,
    function() return v.batSub end, function() return v.batColor end, function() return v.batFrac end,
    function() return v.batX end, function() return v.batUnitX end, "BATTERY"))
  add(live, ring(L.ring2, function() return v.lq end, function() return v.lqInk end, function() return "%" end,
    function() return v.lqSub end, function() return v.lqColor end, function() return v.lqFrac end,
    function() return v.lqX end, function() return v.lqUnitX end, "LINK QUALITY"))

  live[#live + 1] = { type = "rectangle", x = M, y = hairY, w = W - 2 * M, h = 1, filled = true, color = C.rule }
  local unitY = baseline(valueY, valueH, textH(F.unit))
  for i, name in ipairs({ "HOME", "ALTITUDE", "SPEED", "USED" }) do
    if i > 1 then
      live[#live + 1] = { type = "rectangle", x = floor(M + (i - 1) * colW + 0.5), y = labelY, w = 1,
        h = valueY + valueH - labelY - P(6), filled = true, color = C.rule }
    end
    add(live, {
      { type = "label", x = L.colX[i], y = labelY, font = F.label, text = name, color = C.faint },
      { type = "label", x = L.colX[i], y = valueY, font = F.value, text = function() return v.m[i][1] end,
        color = function() return v.m[i].color end },
      { type = "label", x = L.colX[i], y = unitY, font = F.unit, text = function() return v.m[i][2] end,
        color = C.dim, pos = function() return v.m[i].ux, unitY end },
    })
  end
  local arrowY, arrowR = valueY + floor(valueH * 0.55 + 0.5), P(16)
  for _, side in ipairs({ 1, -1 }) do
    live[#live + 1] = { type = "triangle", color = C.info, visible = function() return v.arrowDeg ~= nil end,
      pts = function() return navArrow(v.arrowX, arrowY, arrowR, v.arrowDeg or 0, side) end }
  end

  -- compass and position details, shared by the GPS view ("n" fields) and the summary ("s")
  local leftEdge = L.infoX - P(24)
  local ccx = floor((M + leftEdge) / 2 + 0.5)
  local cr = floor(min(P(118), (leftEdge - M) / 2, (Hc - P(4) - top) / 2))
  local ccy = floor((top + Hc - P(4)) / 2 + 0.5)
  local distUnitY = baseline(S.dist, textH(F.sDist), textH(UNIT_FOR[F.sDist]))
  local statUnitF = UNIT_FOR[F.sStat]
  local ticks                                -- the compass ticks, the same for both panels

  local function panel(p, labels, distLabel, posLabel)
    local kHome, kBearing, kStats = p .. "HasHome", p .. "Bearing", p .. "Stats"
    local kDist, kUnit, kUnitX, kDir, kPos = p .. "Dist", p .. "DistUnit", p .. "DistUnitX", p .. "Dir", p .. "Pos"
    local list = {
      { type = "arc", x = ccx, y = ccy, radius = cr, thickness = max(1, P(2)), startAngle = 0, endAngle = 0,
        opacity = 0, bgStartAngle = 0, bgEndAngle = 360, bgColor = C.rule, bgOpacity = 255 },
      { type = "arc", x = ccx, y = ccy, radius = cr - P(22), thickness = 1, startAngle = 0, endAngle = 0,
        opacity = 0, bgStartAngle = 0, bgEndAngle = 360, bgColor = C.track, bgOpacity = 255 },
    }
    if not ticks then
      ticks = {}
      for i = 0, 11 do
        local a = math.rad(i * 30)
        ticks[i + 1] = { pt(ccx, ccy, a, cr - P(i % 3 == 0 and 14 or 8)), pt(ccx, ccy, a, cr - P(3)) }
      end
    end
    for i = 0, 11 do
      list[#list + 1] = { type = "line", color = (i == 0) and C.ink or C.faint, thickness = max(1, P(2)),
        rounded = true, pts = ticks[i + 1] }
    end
    add(list, {
      { type = "label", x = ccx - P(20), y = ccy - cr + P(18), w = P(40), align = CENTER,
        font = SMLSIZE, text = "N", color = C.ink },
      { type = "triangle", color = C.info, visible = function() return v[kHome] end,
        pts = function() return needle(ccx, ccy, cr - P(34), v[kBearing], P(10)) end },
      { type = "triangle", color = C.faint, visible = function() return v[kHome] end,
        pts = function() return needle(ccx, ccy, floor(cr * 0.42), v[kBearing] + 180, P(10)) end },
      { type = "circle", x = ccx, y = ccy, radius = max(2, P(6)), filled = true, color = C.ink },
    })

    local x0 = L.infoX
    if S.labels then
      add(list, {
        { type = "label", x = x0, y = S.distLabel, font = F.sLabel, text = distLabel, color = C.faint },
        { type = "label", x = x0, y = S.posLabel, font = F.sLabel, text = posLabel, color = C.faint },
      })
    end
    add(list, {
      { type = "label", x = x0, y = S.dist, font = F.sDist, text = function() return v[kDist] end, color = C.ink },
      { type = "label", x = x0, y = distUnitY, font = UNIT_FOR[F.sDist], text = function() return v[kUnit] end,
        color = C.dim, pos = function() return v[kUnitX], distUnitY end },
      { type = "label", x = x0, y = S.dir, font = F.sDir, text = function() return v[kDir] end, color = C.dim },
      { type = "label", x = x0, y = S.pos, font = F.sPos, text = function() return v[kPos] end, color = C.ink },
      { type = "rectangle", x = x0, y = S.hair, w = infoW, h = 1, filled = true, color = C.rule },
    })
    for i, name in ipairs(labels) do
      local x, y = L.statX[(i - 1) % 3 + 1], (i <= 3) and S.row1 or S.row2
      local vy = y + textH(F.sLabel)
      local uy = baseline(vy, textH(F.sStat), textH(statUnitF))
      add(list, {
        { type = "label", x = x, y = y, font = F.sLabel, text = name, color = C.faint },
        { type = "label", x = x, y = vy, font = F.sStat, text = function() return v[kStats][i][1] end,
          color = function() return v[kStats][i].color end },
        { type = "label", x = x, y = uy, font = statUnitF, text = function() return v[kStats][i][2] end,
          color = C.dim, pos = function() return v[kStats][i].ux, uy end },
      })
    end
    return list
  end

  -- Every page but the dashboard and the waiting screen is built the first time it's shown
  -- (see showPage): building them all here would take update() near EdgeTX's limit of 20000
  -- Lua instructions per call.

  -- GPS view
  local function navPage()
    local nav = topBar(chipY)
    add(nav, panel("n", { "ALTITUDE", "SPEED", "HEADING", "BATTERY", "LINK", "USED" },
      "DISTANCE FROM HOME", "POSITION"))
    return nav
  end

  -- summary screen
  local function summaryPage()
    local sum = {}
    add(sum, chip(chipY, function() return v.sTitle end, function() return v.sColor end,
      function() return v.sSolid end, function() return v.sTitleW end, function() return M end))
    sum[#sum + 1] = { type = "label", x = L.right - P(420), y = topMid - floor(stdH / 2 + 0.5), w = P(420),
      align = RIGHT, font = 0, text = function() return v.sAgo end, color = C.dim }
    add(sum, panel("s", { "MAX DISTANCE", "MAX ALTITUDE", "TOP SPEED", "LOWEST CELL", "USED", "FLIGHT TIME" },
      "DISTANCE FROM HOME", "LAST KNOWN POSITION"))
    return sum
  end

  -- page header for find and logbook: title chip and the way on
  local hintY = topMid - floor(stdH / 2 + 0.5)
  local function pageHead(title)
    local cw = textW(title, F.chip) + 2 * L.chipPad
    local list = chip(chipY, function() return title end, function() return C.info end, function() return false end,
      function() return cw end, function() return M end)
    list[#list + 1] = { type = "label", x = L.right - P(300), y = hintY, w = P(300), align = RIGHT, font = SMLSIZE,
      text = VIEW_SWITCH and (string.upper(VIEW_SWITCH) .. "  NEXT PAGE") or "", color = C.faint }
    return list
  end

  -- find page: the QR code on the left, what it points at on the right
  local function findPage()
    local qrPad = P(14)
    local qrSide = floor(min(Hc - top - P(8), W * 0.42))
    local qrX, qrY = M, top + P(4)
    L.qrSide = qrSide - 2 * qrPad
    local fx = qrX + qrSide + P(36)
    local fW = W - M - fx
    F.fAgo = fit("23 h 59 min ago", fW, { DBLSIZE, MIDSIZE, 0 })
    F.fPos = fit("-88.888888, -888.888888", fW, { MIDSIZE, 0, SMLSIZE })
    local find = pageHead("FIND MY QUAD")
    local has = function() return v.fHas end
    add(find, {
      { type = "rectangle", x = qrX, y = qrY, w = qrSide, h = qrSide, filled = true, rounded = P(12), color = QR_PAPER,
        visible = has },
      { type = "box", name = "qr", x = qrX + qrPad, y = qrY + qrPad, w = L.qrSide, h = L.qrSide, visible = has },
    })
    local fy = qrY
    for _, row in ipairs({
      { "LAST SEEN", SMLSIZE, C.faint, 0 },
      { function() return v.fAgo end, F.fAgo, C.ink, 0 },
      { function() return v.fWhen end, 0, C.dim, P(18) },
      { "POSITION", SMLSIZE, C.faint, 0 },
      { function() return v.fPos end, F.fPos, C.ink, 0 },
      { function() return v.fDist end, 0, C.dim, P(18) },
      { "Scan the code with your phone's camera", SMLSIZE, C.dim, 0 },
      { "to open the map at this spot.", SMLSIZE, C.dim, 0 },
    }) do
      find[#find + 1] = { type = "label", x = fx, y = fy, font = row[2], text = row[1], color = row[3], visible = has }
      fy = fy + textH(row[2]) + row[4]
    end
    F.fNone = fit("No saved position yet", W - 2 * M, { DBLSIZE, MIDSIZE, 0 })
    local noneY = floor((top + Hc) / 2 - textH(F.fNone) + 0.5)
    add(find, {
      { type = "label", x = 0, y = noneY, w = W, align = CENTER, font = F.fNone, text = "No saved position yet",
        color = C.ink, visible = function() return not v.fHas end },
      { type = "label", x = 0, y = noneY + textH(F.fNone) + P(6), w = W, align = CENTER, font = SMLSIZE,
        text = "It's saved when the link drops or the quad lands with a GPS fix.", color = C.dim,
        visible = function() return not v.fHas end },
    })
    return find
  end

  -- logbook page: totals per quad, then the latest flights
  local function logPage()
    local log = pageHead("LOGBOOK")
    local half = floor((W - 2 * M) / 2)
    F.lBig = fit("888 flights", half - P(20), { DBLSIZE, MIDSIZE, 0 })
    local ly = top + P(6)
    for i = 1, 2 do
      local x = M + (i - 1) * half
      add(log, {
        { type = "label", x = x, y = ly, font = SMLSIZE, text = function() return v.lTotals[i][1] end, color = C.faint },
        { type = "label", x = x, y = ly + textH(SMLSIZE), font = F.lBig, text = function() return v.lTotals[i][2] end,
          color = C.ink },
        { type = "label", x = x, y = ly + textH(SMLSIZE) + textH(F.lBig), font = 0,
          text = function() return v.lTotals[i][3] end, color = C.dim },
      })
    end
    local ruleY = ly + textH(SMLSIZE) + textH(F.lBig) + textH(0) + P(12)
    log[#log + 1] = { type = "rectangle", x = M, y = ruleY, w = W - 2 * M, h = 1, filled = true, color = C.rule }
    local colAt = { 0, 0.20, 0.36, 0.48, 0.64, 0.80, 1 }
    local widest = { "09-29 22:10", "QUADNAME9", "88:88", "3.88 V", "8.8 km", "LINK LOST" }
    local rowF
    for _, f in ipairs({ 0, SMLSIZE, TINSIZE }) do
      rowF = f
      local ok = true
      for j = 1, 6 do
        if textW(widest[j], f) > floor((W - 2 * M) * (colAt[j + 1] - colAt[j])) - P(8) then ok = false end
      end
      if ok then break end
    end
    local headY = ruleY + P(12)
    local rowY, rowH = headY + textH(TINSIZE) + P(6), textH(rowF) + P(6)
    for j, name in ipairs({ "DATE", "QUAD", "TIME", "LOWEST CELL", "MAX DIST", "USED" }) do
      log[#log + 1] = { type = "label", x = M + floor((W - 2 * M) * colAt[j]), y = headY, font = TINSIZE, text = name,
        color = C.faint }
    end
    for i = 1, min(BOOK_RECENT, floor((Hc - P(4) - rowY) / rowH)) do
      for j = 1, 6 do
        log[#log + 1] = { type = "label", x = M + floor((W - 2 * M) * colAt[j]), y = rowY + (i - 1) * rowH, font = rowF,
          text = function() return v.lRows[i][j] end,
          color = function() return (j == 6 and v.lRows[i].color) or (j == 1 and C.dim) or C.ink end }
      end
    end
    log[#log + 1] = { type = "label", x = 0, y = rowY + P(10), w = W, align = CENTER, font = 0,
      text = "No flights yet. Each one is logged when the quad disarms.", color = C.dim,
      visible = function() return v.lEmpty end }
    return log
  end
  w.lazy = { nav = navPage, summary = summaryPage, find = findPage, log = logPage }

  -- waiting screen: spinner, title and hint centred as one block
  local sim = isSim()
  local wTitle = sim and "Simulator mode" or "Waiting for the quad"
  local wHint = sim and "Plug in USB and pick Joystick. The switches work as on the quads."
    or "Plug in a battery. Telemetry appears once it links."
  F.wTitle = fit(wTitle, W - 2 * M, { DBLSIZE, MIDSIZE, 0 })
  F.wSub = fit(wHint, W - 2 * M, { 0, SMLSIZE, TINSIZE })
  local spinR = P(56)
  local blockH = 2 * spinR + P(44) + textH(F.wTitle) + P(4) + textH(F.wSub)
  local wy = stripBottom + floor((Hc - stripBottom - blockH) / 2 + 0.5)
  local wcx, titleY = floor(W / 2 + 0.5), wy + 2 * spinR + P(44)
  local waiting = {
    { type = "arc", x = wcx, y = wy + spinR, radius = spinR, thickness = max(3, P(8)), rounded = true, color = C.info,
      startAngle = function() return floor(getTime() * 2.4) % 360 end,
      endAngle = function() return (floor(getTime() * 2.4) + 100) % 360 end,
      bgStartAngle = 0, bgEndAngle = 360, bgColor = C.track, bgOpacity = 255 },
    { type = "label", x = 0, y = titleY, w = W, align = CENTER, font = F.wTitle, text = wTitle, color = C.ink },
    { type = "label", x = 0, y = titleY + textH(F.wTitle) + P(4), w = W, align = CENTER, font = F.wSub,
      text = wHint, color = C.dim },
  }

  -- radio battery, right-aligned in the bottom band: RADIO, a battery glyph, percent, volts
  local txH = textH(F.tx)
  local txY = Hc + floor((bandH - txH) / 2 + 0.5)
  local voltW, pctW, gap = textW("8.8 V", F.tx), textW("100%", F.tx), P(8)
  local xVolt = L.right - voltW
  local xPct = xVolt - gap - pctW
  local cellW, cellH, nubW, inset = P(30), P(14), max(2, P(3)), max(2, P(3))
  local cellX = xPct - gap - nubW - cellW
  local cellY = txY + floor((txH - cellH) / 2 + 0.5)
  local fillW = cellW - 2 * inset
  local radio = {
    { type = "label", x = cellX - P(8) - textW("RADIO", TINSIZE), font = TINSIZE, text = "RADIO", color = C.faint,
      y = cellY + floor((cellH - textH(TINSIZE)) / 2 + 0.5) },
    { type = "rectangle", x = cellX, y = cellY, w = cellW, h = cellH, filled = false, thickness = max(1, P(2)),
      rounded = P(3), color = C.dim },
    { type = "rectangle", x = cellX + cellW, y = cellY + floor(cellH / 4), w = nubW, h = cellH - 2 * floor(cellH / 4),
      filled = true, rounded = 1, color = C.dim },
    { type = "rectangle", x = cellX + inset, y = cellY + inset, w = fillW, h = cellH - 2 * inset, filled = true,
      rounded = P(1), color = function() return v.txColor end,
      size = function() return max(1, floor(fillW * v.txFrac + 0.5)), cellH - 2 * inset end },
    { type = "label", x = xPct, y = txY, w = pctW, align = RIGHT, font = F.tx, text = function() return v.txPct end,
      color = function() return (v.txColor == C.good) and C.ink or v.txColor end },
    { type = "label", x = xVolt, y = txY, w = voltW, align = RIGHT, font = F.tx,
      text = function() return v.txVolts end, color = C.dim },
  }

  lvgl.clear()
  w.qrShown = nil
  w.refs = lvgl.build({
    { type = "rectangle", x = 0, y = 0, w = W, h = H, filled = true, color = C.bg },
    { type = "box", x = 0, y = 0, w = W, h = H, visible = on("waiting"), children = waiting },
    { type = "box", x = 0, y = 0, w = W, h = H, children = strip,
      visible = function() return v.screen == "waiting" or v.screen == "live" end },
    { type = "box", x = 0, y = 0, w = W, h = H, visible = on("live"), children = live },
    { type = "box", name = "nav", x = 0, y = 0, w = W, h = H, visible = on("nav") },
    { type = "box", name = "summary", x = 0, y = 0, w = W, h = H, visible = on("summary") },
    { type = "box", name = "find", x = 0, y = 0, w = W, h = H, visible = on("find") },
    { type = "box", name = "log", x = 0, y = 0, w = W, h = H, visible = on("log") },
    { type = "box", x = 0, y = 0, w = W, h = H, children = radio },
  })
end

-- builds a page the first time it's on screen, and keeps the find page's QR code current
local function showPage(w)
  local screen = w.v.screen
  local make, box = w.lazy and w.lazy[screen], w.refs and w.refs[screen]
  if make and box then
    w.lazy[screen] = nil
    local refs = box:build(make())
    if refs and refs.qr then w.refs.qr = refs.qr end
  end
  if screen == "find" then syncQR(w) end
end

-- Widget ------------------------------------------------------------------------
local function create(zone, opts)
  local w = { zone = zone, options = opts, linked = false, seen = false, armed = false, page = 0, v = {},
              gs = getGeneralSettings() }
  reset(w)
  loadLastPos(w)
  loadBook(w)
  return w
end

local function update(w, opts)
  w.options = opts
  build(w)
end

local function refresh(w)
  readViewSwitch(w)
  viewSwitches(w)
  viewRadio(w)
  view(w, track(w))
  showPage(w)
end

-- EdgeTX only calls refresh while the widget is on screen
local function background(w) track(w) end

return { name = "FPVDash", options = options, create = create, update = update, refresh = refresh,
  background = background, useLvgl = true }
