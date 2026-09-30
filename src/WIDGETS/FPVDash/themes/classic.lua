-- FPVDash theme "Classic": the original look. Rounded tiles, arc gauges, green/amber/red.
-- Designed at 800x480 and scaled to the zone. EdgeTX's font sizes don't scale with the screen,
-- so each text slot picks the largest font that fits and vertical spacing follows the chosen
-- fonts. LVGL wants whole pixels, so every coordinate is rounded.
local K = ...
local floor, max, min = math.floor, math.max, math.min
local textW, textH, fit, pt = K.textW, K.textH, K.fit, K.pt

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

local MODES = {
  ACRO = { "ACRO", C.info }, AIR = { "AIR", C.info }, ANGL = { "ANGLE", C.good }, STAB = { "ANGLE", C.good },
  HOR = { "HORIZON", C.good }, RTH = { "RESCUE", C.warn }, WAIT = { "WAIT GPS", C.warn },
  ["!FS!"] = { "FAILSAFE", C.bad }, ["!ERR"] = { "CAN'T ARM", C.bad }, MANU = { "MANUAL", C.info },
}
-- disarmed, by the suffix Betaflight puts on the flight mode
local READY = { ["*"] = { "READY", C.good }, ["!"] = { "CAN'T ARM", C.warn }, ["?"] = { "NO RESCUE", C.warn } }
-- switch positions: colour and whether the tile lights up
local SEV = { home = { C.dim }, set = { C.info }, caution = { C.warn, true }, armed = { C.bad, true } }

local function cellColor(v)
  if not v then return C.faint end
  return (v > 3.7 and C.good) or (v > 3.5 and C.warn) or C.bad
end

local function lqColor(q) return (q > 80 and C.good) or (q > 50 and C.warn) or C.bad end

local RING0, RING_SWEEP = 135, 270          -- gauge arc: 0 deg is 3 o'clock, clockwise
local XLFONT = XLSIZE or DBLSIZE           -- XLSIZE sits between DBLSIZE and XXLSIZE; older EdgeTX lacks it
local UNIT_FOR = { [XXLSIZE] = MIDSIZE, [XLFONT] = MIDSIZE, [DBLSIZE] = 0, [MIDSIZE] = SMLSIZE, [0] = SMLSIZE,
                   [SMLSIZE] = TINSIZE, [TINSIZE] = TINSIZE }
local PAGE_OF = { live = "live", nav = "nav", lost = "summary", summary = "summary", find = "find", log = "log",
                  waiting = "waiting", sim = "waiting" }

local function baseline(y, fromH, toH) return floor(y + (fromH - toH) * 0.79 + 0.5) end

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

  v.timer = K.clock(d.timer)
  local timerX = L.right - textW(v.timer, F.timer)
  local sats = d.sats or 0
  if sats == 0 then v.gpsNum, v.gpsText, v.gpsColor = "", "NO GPS", C.bad
  elseif not d.fix then v.gpsNum, v.gpsText, v.gpsColor = tostring(sats), "SATS  NO FIX", C.bad
  elseif d.armed and not w.armedHome then v.gpsNum, v.gpsText, v.gpsColor = tostring(sats), "SATS  NO HOME", C.bad
  else v.gpsNum, v.gpsText, v.gpsColor = tostring(sats), "SATS", (sats >= K.HOME_SATS and C.good or C.warn) end
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
  local dv, du = K.distVU(d.dist)
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
  v.arrowDeg = d.homeRel
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
    v.nBearing = K.bearing(w.home, pos)
    v.nDist, v.nDistUnit = K.distVU(d.dist)
    v.nDir = K.compass(v.nBearing) .. " OF HOME"
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
  local lost = d.screen == "lost"
  v.sTitle = lost and "LINK LOST" or "FLIGHT SUMMARY"
  v.sColor, v.sSolid = lost and C.bad or C.info, lost
  v.sTitleW = textW(v.sTitle, F.chip) + 2 * L.chipPad
  v.sAgo = w.lostAt and ((lost and "SIGNAL LOST " or "ENDED ") .. K.clock((d.now - w.lostAt) / 100) .. " AGO") or ""

  v.sHasHome = (w.home and w.lastDist and w.last) and true or false
  if v.sHasHome then
    v.sBearing = K.bearing(w.home, w.last)
    v.sDist, v.sDistUnit = K.distVU(w.lastDist)
    v.sDir = K.compass(v.sBearing) .. " OF HOME"
  else
    v.sBearing, v.sDist, v.sDistUnit, v.sDir = 0, "--", "", "NO HOME POINT"
  end
  v.sDistUnitX = L.infoX + textW(v.sDist, F.sDist) + L.small
  v.sPos = w.last and string.format("%.6f, %.6f", w.last.lat, w.last.lon) or "No GPS fix this flight"

  local md, mu = K.distVU(s.maxDist > 0 and s.maxDist or nil)
  v.sStats = {
    { md, mu },
    { s.maxAlt and string.format("%d", floor(s.maxAlt + 0.5)) or "--", s.maxAlt and "m" or "" },
    { s.maxSpd > 0 and string.format("%d", floor(s.maxSpd + 0.5)) or "--", s.maxSpd > 0 and "km/h" or "" },
    { s.minCell and string.format("%.2f", s.minCell) or "--", s.minCell and "V" or "", cellColor(s.minCell) },
    { (s.capa and s.capa > 0) and string.format("%d", s.capa) or "--", (s.capa and s.capa > 0) and "mAh" or "" },
    { K.clock(d.timer), "" },
  }
  placeStats(w, v.sStats)
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
  v.fAgo = (secs and secs >= 0) and K.ago(secs) or s.when
  v.fWhen = s.when .. (s.quad and ("   " .. s.quad) or "")
  v.fDist = s.dist and (s.dist .. " m from home") or "Distance from home unknown"
end

local function viewLog(w)
  local v, b = w.v, w.book
  local quads = K.topQuads(b, 2)
  v.lTotals = {}
  for i = 1, 2 do
    local t = quads[i] and b.totals[quads[i]]
    v.lTotals[i] = t and { string.sub(quads[i], 1, 15), t.flights == 1 and "1 flight" or (t.flights .. " flights"), K.hm(t.secs) }
                   or { "", "", "" }
  end
  v.lRows = {}
  for i = 1, K.BOOK_RECENT do
    local r = b.recent[i]
    if r then
      local dv, du = K.distVU(r.maxDist)
      v.lRows[i] = {
        string.sub(r.when, 6), string.sub(r.quad, 1, 9), K.clock(r.secs),
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

local function viewRadio(w, d)
  local v = w.v
  v.txFrac, v.txPct = d.txFrac, string.format("%d%%", floor(d.txFrac * 100 + 0.5))
  v.txVolts = string.format("%.1f V", d.txV)
  v.txColor = (d.txLow and C.bad) or (d.txWarn and C.warn) or C.good
end

local function viewSwitches(w)
  for i, s in ipairs(K.switches) do
    local t, tile = w.sw[i], w.v.sw[i]
    local sev = SEV[t.sev] or SEV.home
    tile.state, tile.color, tile.hot = t.text, sev[1], sev[2] or false
    if s.pot then
      tile.color, tile.font = C.dim, tile.fonts[1]
    elseif t.text == "--" then
      tile.color, tile.font = C.faint, SMLSIZE
    else
      tile.font = tile.fonts[t.pos] or SMLSIZE
    end
  end
end

local function view(w, d)
  local v = w.v
  viewSwitches(w)
  viewRadio(w, d)
  v.screen = PAGE_OF[d.screen]
  if d.linked then
    viewLive(w, d)
    if v.screen == "nav" then viewNav(w, d) end
  elseif v.screen == "find" then
    viewFind(w)
    K.syncQR(w, v.fHas and v.fQR or nil, w.L.qrSide, QR_INK, QR_PAPER)
  elseif v.screen == "log" then
    viewLog(w)
  elseif v.screen == "summary" then
    viewSummary(w, d)
  end
end

-- Layout ------------------------------------------------------------------------
local function build(w)
  local SWITCHES = K.switches
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
  local function texts(s)
    if s.pot then return { { "100%" } } end
    if s.view then return { { "DASH" }, { "GPS" }, { "FIND" }, { "LOG" } } end
    return s[3]
  end
  local natural, total = {}, 0
  for i, s in ipairs(SWITCHES) do
    local wmax = max(textW(s[1], F.swLabel) + P(6) + 2 * dotR, textW(s[2], F.swFunc))
    for _, st in ipairs(texts(s)) do wmax = max(wmax, textW(st[1], s.quiet and TINSIZE or SMLSIZE)) end
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
    for j, st in ipairs(texts(s)) do
      fonts[j] = s.quiet and TINSIZE or fit(st[1], room, { SMLSIZE, TINSIZE })
    end
    L.tiles[i] = { x = tx, w = tw }
    v.sw[i] = { fonts = fonts, state = "--", color = C.faint, hot = false, font = SMLSIZE }
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
  local blank = { now = getTime(), sats = 0, timer = 0, txFrac = 0, txV = 0, screen = "waiting" }
  viewSwitches(w)
  viewLive(w, blank)
  viewNav(w, blank)
  viewSummary(w, blank)
  viewFind(w)
  viewLog(w)
  viewRadio(w, blank)
  v.screen = "waiting"

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
    local t, sw, x, tw = v.sw[i], w.sw[i], L.tiles[i].x, L.tiles[i].w
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
          size = function() return barW, max(barW, floor(barH * sw.level / 100 + 0.5)) end,
          pos = function() return dotX - floor(barW / 2), barY + barH - max(barW, floor(barH * sw.level / 100 + 0.5)) end },
      })
    else
      local n = sw.n
      for j = 1, n do
        local dy = (n == 2) and ((j == 1) and -dotStep or dotStep) or (j - 2) * dotStep
        strip[#strip + 1] = { type = "circle", x = dotX, y = midY + dy, radius = dotR, filled = true,
          color = function()
            if sw.dot ~= j then return C.rule end
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
      text = K.VIEW_SWITCH and (string.upper(K.VIEW_SWITCH) .. "  NEXT PAGE") or "", color = C.faint }
    return list
  end

  -- find page: the QR code on the left, what it points at on the right
  local qrPad = P(14)
  local qrSide = floor(min(Hc - top - P(8), W * 0.42))
  L.qrSide = qrSide - 2 * qrPad
  local function findPage()
    local qrX, qrY = M, top + P(4)
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
    for i = 1, min(K.BOOK_RECENT, floor((Hc - P(4) - rowY) / rowH)) do
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
  local wTitle = w.sim and "Simulator mode" or "Waiting for the quad"
  local wHint = w.sim and "Plug in USB and pick Joystick. The switches work as on the quads."
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

return { build = build, view = view, page = function(screen) return PAGE_OF[screen] end }
