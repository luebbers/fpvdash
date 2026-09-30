-- FPVDash theme "Hi-Vis" (tx16s-theme-spec, option B): safety signage for sunlight. Fluorescent
-- yellow ground, black ink, giant condensed numerals, 3 px rules. Caution is inverted (ink ground,
-- yellow text); warning turns the ground red-orange. Designed at 800x480 and scaled; the display
-- type is sprites from img/hivis (Big Shoulders Display, JetBrains Mono), labels use the radio's
-- own fonts.
local K = ...
local floor, max, min = math.floor, math.max, math.min
local textW, textH, ascent = K.textW, K.textH, K.ascent
local sText, sSet, sWidth = K.sText, K.sSet, K.sWidth

local RGB = lcd.RGB
local C = { y = RGB(230, 244, 58), ink = RGB(18, 18, 16), red = RGB(255, 75, 31) }
local PAGE_OF = { live = "dash", nav = "nav", lost = "lost", summary = "summary", find = "find", log = "log",
                  waiting = "wait", sim = "sim" }
local CHIPS = 4
-- the switch row says what a switch does in one short phrase: "BEEP OFF", "RATE HI", "ANGLE"
local SHORT = { TURTLE = "TRTL", RESCUE = "RESC", RATES = "RATE", PREARM = "PRE", VOLUME = "VOL", BEEPER = "BEEP",
                BUZZER = "BEEP" }
local GENERIC = { OFF = true, ON = true, UP = true, MID = true, DOWN = true, HI = true, LO = true, HIGH = "HI", LOW = "LO" }

local function upper(s) return string.upper(s or "") end
local function num(x) return string.format("%d", floor(x + 0.5)) end

local function switchText(s, t)
  local state, fn = upper(t.text), upper(s[2])
  fn = SHORT[fn] or fn
  if s.view then return state end
  if s.pot then return fn .. " " .. tostring(t.level) end
  if fn == "ARM" and state == "OFF" then return "SAFE" end
  local g = GENERIC[state]
  if not g then return state end
  if g ~= true then state = g end
  return fn .. " " .. state
end

local function build(w)
  local W, H = w.zone.w, w.zone.h
  local k = min(W / 800, H / 480)
  local function P(n) return floor(n * k + 0.5) end
  local S = K.loadSprites(K.DIR .. "img/hivis/" .. (k < 0.8 and "60" or "100") .. "/fonts.lua", K.CONFIG.tabularDigits)
  if not S then error("sprites missing: " .. K.DIR .. "img/hivis") end
  local v = w.v
  v.screen, v.ground, v.chips = "wait", C.y, {}
  local SW = K.switches
  local gap = max(1, P(3))

  local function add(list, objs) for _, o in ipairs(objs) do list[#list + 1] = o end end
  local function on(page) return function() return v.screen == page end end
  local function ground() return v.ground end
  local function lab(x, base, font, text, color, right, visible)
    local y = base - ascent(font)
    if right then
      return { type = "label", x = x - P(500), y = y, w = P(500), align = RIGHT, font = font, text = text,
               color = color, visible = visible }
    end
    return { type = "label", x = x, y = y, font = font, text = text, color = color, visible = visible }
  end
  local function rect(x, y, wd, ht, color, extra)
    local r = { type = "rectangle", x = x, y = y, w = wd, h = ht, filled = true, color = color }
    for key, val in pairs(extra or {}) do r[key] = val end
    return r
  end
  local function field(list, font, n, x, base, align, em)
    local f = S[font]
    local objs, fld = sText(f, n, x, base, align, (em or 0) * f.px)
    add(list, objs)
    return fld
  end
  -- a label on a small pad of ground colour, so it reads over the hatch
  local function padded(list, x, base, text, right, key)
    local e = { text = text, x = x }
    if key then v[key] = e end
    local pw = function() return textW(e.text, TINSIZE) + 2 * P(4) end
    local top = base - ascent(TINSIZE) - P(1)
    add(list, {
      rect(x, top, P(60), textH(TINSIZE) - P(1), C.y, { color = ground,
        pos = function() return right and (x - pw()) or (x - P(4)), top end,
        size = function() return pw(), textH(TINSIZE) - P(1) end }),
      lab(x, base, TINSIZE, function() return e.text end, C.ink, right),
    })
    return e
  end

  -- Top band: solid ink, or hazard stripes when armed; state chips and the radio battery -----
  local bandH = P(44)
  local function band(list, key)
    local b = { file = nil }
    v[key] = b
    local pat = S.patterns
    list[#list + 1] = { type = "image", x = 0, y = 0, w = pat.haz_iy.w, h = pat.haz_iy.h,
      visible = function() return b.file ~= nil end, file = function() return b.file or pat.haz_iy.f end }
    local chips = {}
    v.chips[key] = chips
    for i = 1, CHIPS do
      local c = { x = P(6), w = 0, bg = C.y }
      chips[i] = c
      list[#list + 1] = rect(P(6), P(6), P(60), P(32), C.y, { visible = function() return c.w > 0 end,
        color = function() return c.bg end, pos = function() return c.x, P(6) end,
        size = function() return c.w, P(32) end })
      c.fld = field(list, "chip", 10, P(16), P(34), "l", 0.02)
    end
    -- the radio's battery, in colours inverted against the band
    local tx = { x = W - P(100), w = P(100), bg = C.y, fg = C.ink }
    v[key .. "Tx"] = tx
    local tb = P(26)
    add(list, {
      rect(W - P(100), P(6), P(100), P(32), C.y, { color = function() return tx.bg end,
        pos = function() return tx.x, P(6) end, size = function() return tx.w, P(32) end }),
      { type = "label", x = 0, y = tb - ascent(TINSIZE), font = TINSIZE, text = "TX",
        color = function() return tx.fg end, pos = function() return tx.x + P(10), tb - ascent(TINSIZE) end },
      { type = "label", x = 0, y = tb - ascent(BOLD), font = BOLD, text = function() return v.txPct end,
        color = function() return tx.fg end, pos = function() return tx.pctX, tb - ascent(BOLD) end },
      { type = "label", x = 0, y = tb - ascent(TINSIZE), font = TINSIZE, text = function() return v.txVolts end,
        color = function() return tx.fg end, pos = function() return tx.voltX, tb - ascent(TINSIZE) end },
    })
    tx.pctX, tx.voltX = 0, 0
    return b
  end

  -- Switch row along the bottom (dashboard, waiting, simulator) --------------------------------
  local row = {}
  local n = #SW
  local rowTop = H - P(40)
  local cellW = n > 0 and (W - (n - 1) * gap) / n or W
  v.sw = {}
  for i, s in ipairs(SW) do
    local x0 = floor((i - 1) * (cellW + gap) + 0.5)
    local x1 = (i == n) and W or floor((i - 1) * (cellW + gap) + cellW + 0.5)
    local t, tile = w.sw[i], { bg = C.y, fg = C.ink }
    v.sw[i] = tile
    add(row, {
      rect(x0, rowTop, x1 - x0, H - rowTop, C.y, { color = function() return tile.bg end }),
      lab(x0 + P(9), rowTop + P(24), TINSIZE, s[1], function() return tile.fg end),
    })
    tile.room = x1 - x0 - P(29) - P(4)
    tile.fld = field(row, "sw", 10, x0 + P(29), rowTop + P(29), "l", -0.01)
  end

  -- Dashboard ----------------------------------------------------------------------------------
  local mainTop, statsTop = bandH + gap, H - P(40) - gap - P(100)
  local mainH = statsTop - gap - mainTop
  local batW = P(468)
  local rx = batW + gap
  local rw = W - rx
  local cellH = floor((mainH - gap) / 2)

  -- a level gauge: the cell's own fill; the depleted part from the top is hatched
  local function gauge(list, x, y, wd, ht, e)
    local hatch = S.patterns.hatch
    add(list, {
      rect(x, y, wd, ht, C.y, { color = ground }),
      { type = "box", x = x, y = y, w = wd, h = ht, size = function() return wd, max(0, e.dep) end,
        children = { { type = "image", x = 0, y = 0, w = hatch.w, h = hatch.h, file = hatch.f } } },
    })
  end
  -- the gauge's level line, over the knockout so it reads right across the cell
  local function level(list, x, y, wd, e)
    list[#list + 1] = rect(x, y, wd, P(3), C.ink, { pos = function() return x, y + max(0, e.dep - P(1)) end })
  end
  -- a knockout of ground colour behind a number, so the hatch doesn't run through it (spec 7.2)
  local function knockout(list, x, base, capH, e)
    list[#list + 1] = rect(x - P(4), base - capH - P(4), P(100), capH + P(8), C.y, { color = ground,
      visible = function() return e.dep > base - capH - P(4) - e.top end,
      size = function() return e.heroW + P(8), capH + P(8) end })
  end
  local function unitPad(list, e, base, font, text)
    local ht = textH(font)
    add(list, {
      rect(0, base - ascent(font) - P(1), P(10), ht - P(2), C.y, { color = ground,
        size = function() return textW(e.unit or text, font) + P(8), ht - P(2) end,
        pos = function() return e.unitX - P(4), base - ascent(font) - P(1) end }),
      { type = "label", x = 0, y = base - ascent(font), font = font, text = function() return e.unit or text end,
        color = C.ink, pos = function() return e.unitX, base - ascent(font) end },
    })
  end

  local function dashPage()
    local list = {}
    band(list, "dashBand")
    -- battery: level gauge, LAND 3.5 line, hero cell voltage
    local bat = { dep = 0, top = mainTop, h = mainH, heroW = 0, unitX = P(14) }
    v.bat = bat
    gauge(list, 0, mainTop, batW, mainH, bat)
    -- the digits stand on the LAND line and its tag hangs below it, so no reading ever covers it
    local landY = mainTop + mainH - floor(mainH * 0.2 / 0.9 + 0.5) - P(1)
    local heroBase = landY - P(5)
    local capH = floor(S.bat.px * 0.8 + 0.5)          -- Big Shoulders' capitals are 0.8 em
    knockout(list, P(14), heroBase, capH, bat)
    level(list, 0, mainTop, batW, bat)
    local tagW, tagH = textW("LAND 3.5", TINSIZE) + 2 * P(5), P(27)
    local tagX = batW - P(12) - tagW
    local tagY = landY + P(3)
    add(list, {
      { type = "line", color = C.ink, thickness = max(1, P(2)), dashWidth = P(6), dashGap = P(4),
        pts = { { 0, landY }, { batW, landY } } },
      rect(tagX, tagY, tagW, tagH, C.ink),
      { type = "label", x = tagX, y = tagY + floor((tagH - textH(TINSIZE)) / 2 + 0.5), w = tagW,
        align = CENTER, font = TINSIZE, text = "LAND 3.5", color = ground },
    })
    bat.hero = field(list, "bat", 5, P(14), heroBase, "l", -0.01)
    unitPad(list, bat, heroBase, BOLD, "V")
    padded(list, P(18), mainTop + P(24), "BATT / CELL")
    bat.detail = padded(list, batW - P(14), mainTop + P(24), "", true)

    -- link quality
    local lq = { dep = 0, top = mainTop, h = cellH, heroW = 0, unitX = rx + P(14) }
    v.lq = lq
    gauge(list, rx, mainTop, rw, cellH, lq)
    local lqBase = mainTop + P(128)
    knockout(list, rx + P(14), lqBase, floor(S.hero.px * 0.8 + 0.5), lq)
    level(list, rx, mainTop, rw, lq)
    lq.hero = field(list, "hero", 4, rx + P(14), lqBase, "l", -0.01)
    unitPad(list, lq, lqBase - P(2), BOLD, "%")
    padded(list, rx + P(18), mainTop + P(24), "LINK")
    lq.detail = padded(list, W - P(14), mainTop + P(24), "", true)

    -- timer, with the GPS chip top right
    local ty = mainTop + cellH + gap
    list[#list + 1] = rect(rx, ty, rw, mainH - cellH - gap, C.y, { color = ground })
    list[#list + 1] = lab(rx + P(14), ty + P(22), TINSIZE, "TIMER", C.ink)
    -- the inverted GPS chip is shorter than the design's 38 px so it clears the timer's digits
    v.timer = field(list, "hero", 7, rx + P(14), ty + P(137), "l", -0.01)
    local g = { x = 0, w = 0, inv = false, gpsX = 0, satX = 0, status = "", statusX = 0 }
    v.gps = g
    local gb = ty + P(27)
    add(list, {
      rect(0, ty + P(8), P(10), P(30), C.ink, { visible = function() return g.inv end,
        pos = function() return g.x, ty + P(8) end, size = function() return g.w, P(30) end }),
      { type = "label", x = 0, y = gb - ascent(TINSIZE), font = TINSIZE, text = "GPS", color = function() return g.fg end,
        pos = function() return g.gpsX, gb - ascent(TINSIZE) end },
      { type = "label", x = 0, y = gb - ascent(TINSIZE), font = TINSIZE, text = "SAT", color = function() return g.fg end,
        pos = function() return g.satX, gb - ascent(TINSIZE) end },
      { type = "label", x = 0, y = gb - ascent(TINSIZE), font = TINSIZE, text = function() return g.status end,
        color = function() return g.fg end, pos = function() return g.statusX, gb - ascent(TINSIZE) end },
    })
    g.fg = C.ink
    g.count = field(list, "chip", 3, 0, gb + P(8), "l", -0.01)

    -- stats row
    local cells = {}
    v.stats = cells
    local cw = (W - 3 * gap) / 4
    for i, name in ipairs({ "HOME", "ALT", "SPEED", "USED" }) do
      local x0 = floor((i - 1) * (cw + gap) + 0.5)
      local x1 = (i == 4) and W or floor((i - 1) * (cw + gap) + cw + 0.5)
      local c = { unit = "", unitX = x0 + P(14), inv = false, right = x1 - P(4), uf = SMLSIZE }
      cells[i] = c
      local vb = statsTop + P(87)
      add(list, {
        rect(x0, statsTop, x1 - x0, P(100), C.y, { color = function() return c.inv and C.ink or v.ground end }),
        lab(x0 + P(14), statsTop + P(20), TINSIZE, name, function() return c.inv and v.ground or C.ink end),
      })
      c.fld = field(list, "stat", 6, x0 + P(14), vb, "l", -0.01)
      list[#list + 1] = { type = "label", x = x0, y = vb - ascent(SMLSIZE), font = SMLSIZE,
        text = function() return c.unit end, color = C.ink, pos = function() return c.unitX, vb - ascent(SMLSIZE) end }
      if i == 1 then
        local half = P(20) / 10
        local shape = { { 0, -9.5 * half }, { 8.5 * half, 9 * half }, { 0, 4 * half }, { -8.5 * half, 9 * half } }
        local ax, ay = x1 - P(14) - P(20), statsTop + P(68)
        for _, tri in ipairs({ { 1, 2, 3 }, { 1, 3, 4 } }) do
          list[#list + 1] = { type = "triangle", color = C.ink, visible = function() return c.arrow ~= nil end,
            pts = function()
              local p = K.turn(ax, ay, c.arrow or 0, shape)
              return { p[tri[1]], p[tri[2]], p[tri[3]] }
            end }
        end
        add(list, {
          K.sWord(S.words.nohome, x0 + P(14), vb, function() return c.inv and v.ground == C.y end),
          K.sWord(S.words.nohome_r, x0 + P(14), vb, function() return c.inv and v.ground == C.red end),
        })
      end
    end
    return list
  end

  -- Nav and link lost ----------------------------------------------------------------------------
  local leftW = P(260)
  local function navLayout(list, lost)
    local barH = lost and P(60) or P(48)
    local stripTop = H - P(86)
    local barTop = stripTop - gap - barH
    local e = { cells = {}, unit = "", unitX = leftW + gap + P(14), dir = "" }
    v[lost and "lostInfo" or "navInfo"] = e
    local mainH2 = barTop - gap - mainTop
    add(list, {
      rect(0, mainTop, leftW, mainH2, C.y, { color = ground }),
      rect(leftW + gap, mainTop, W - leftW - gap, mainH2, C.y, { color = ground }),
      lab(P(14), mainTop + P(22), TINSIZE, lost and "SIGNAL" or "HOME IS", C.ink),
      lab(leftW + gap + P(14), mainTop + P(22), TINSIZE, "FROM HOME", C.ink),
      lab(W - P(14), mainTop + P(22), TINSIZE, function() return e.dir end, C.ink, true),
    })
    if lost then
      local fld = field(list, "huge", 1, floor(leftW / 2 + 0.5), mainTop + P(235), "c", 0)
      sSet(fld, "?", "ink")
    else
      local half = P(200) / 20
      local shape = { { 0, -9.5 * half }, { 8.5 * half, 9 * half }, { 0, 4 * half }, { -8.5 * half, 9 * half } }
      local ax, ay = floor(leftW / 2 + 0.5), mainTop + P(152)
      for _, tri in ipairs({ { 1, 2, 3 }, { 1, 3, 4 } }) do
        list[#list + 1] = { type = "triangle", color = C.ink, visible = function() return e.arrow ~= nil end,
          pts = function()
            local p = K.turn(ax, ay, e.arrow or 0, shape)
            return { p[tri[1]], p[tri[2]], p[tri[3]] }
          end }
      end
    end
    local db = barTop - gap - P(16)
    e.dist = field(list, "huge", 6, leftW + gap + P(14), db, "l", -0.01)
    list[#list + 1] = { type = "label", x = 0, y = db - ascent(BOLD), font = BOLD, text = function() return e.unit end,
      color = C.ink, pos = function() return e.unitX, db - ascent(BOLD) end }
    -- coordinate bar
    local cb = barTop + floor(barH / 2 + 0.5)
    add(list, {
      rect(0, barTop, W, barH, C.ink),
      lab(P(14), cb + P(4), TINSIZE, lost and "LAST POS" or "POS", ground),
    })
    e.coord = field(list, lost and "j30" or "j24", 22, (lost and P(95) or P(54)), cb + (lost and P(11) or P(9)), "l", 0)
    -- stat strip
    local sw = (W - 5 * gap) / 6
    local labels = lost and { "MAX DIST", "MAX ALT", "TOP SPD", "LOW CELL", "USED", "TIME" }
      or { "ALT", "SPD", "HDG", "BATT", "LINK", "USED" }
    for i = 1, 6 do
      local x0 = floor((i - 1) * (sw + gap) + 0.5)
      local x1 = (i == 6) and W or floor((i - 1) * (sw + gap) + sw + 0.5)
      local c = { unit = "", unitX = x0 + P(12), inv = false, right = x1 - P(3), uf = TINSIZE }
      e.cells[i] = c
      local vb = H - P(12)
      add(list, {
        rect(x0, stripTop, x1 - x0, H - stripTop, C.y, { color = function() return c.inv and C.ink or v.ground end }),
        lab(x0 + P(12), stripTop + P(17), TINSIZE, labels[i], function() return c.inv and v.ground or C.ink end),
      })
      c.fld = field(list, "strip", 5, x0 + P(12), vb, "l", -0.01)
      list[#list + 1] = { type = "label", x = x0, y = vb - ascent(TINSIZE), font = TINSIZE,
        text = function() return c.unit end, color = function() return c.inv and v.ground or C.ink end,
        pos = function() return c.unitX, vb - ascent(TINSIZE) end }
    end
    return e
  end

  local function navPage()
    local list = {}
    band(list, "navBand")
    navLayout(list, false)
    return list
  end

  local function lostPage()
    local list = {}
    band(list, "lostBand")
    navLayout(list, true)
    return list
  end

  -- Ground pages: an ink header bar with the title and the page key ----------------------------
  local function header(list, title, right)
    local fld = field(list, "title", 16, P(14), P(35), "l", 0.02)
    sSet(fld, title, "y")
    if right == "key" and K.VIEW_SWITCH then
      local key = upper(K.VIEW_SWITCH)
      local hint = W - P(14) - textW("NEXT PAGE", TINSIZE)
      local kw = textW(key, TINSIZE) + P(12)
      add(list, {
        rect(hint - P(8) - kw, P(13), kw, P(18), C.y),
        { type = "label", x = hint - P(8) - kw, y = P(22) - floor(textH(TINSIZE) / 2 + 0.5), w = kw, align = CENTER,
          font = TINSIZE, text = key, color = C.ink },
        lab(W - P(14), P(26), TINSIZE, "NEXT PAGE", C.y, true),
      })
    end
  end

  local function findPage()
    local list = {}
    header(list, "FIND MY QUAD", "key")
    local e = { has = false, agoX = 0, meta = "", fromX = 0 }
    v.find = e
    local qw = P(393)
    local has = function() return e.has end
    add(list, {
      rect(0, mainTop, qw, H - P(40) - gap - mainTop, C.y),
      rect(qw + gap, mainTop, W - qw - gap, H - P(40) - gap - mainTop, C.y),
      rect(0, H - P(40), W, P(40), C.y),
      { type = "box", name = "qr", x = floor((qw - P(360)) / 2 + 0.5), y = mainTop + P(15), w = P(360), h = P(360),
        visible = has },
    })
    w.qrSide = P(360)
    local x = qw + gap + P(14)
    add(list, {
      lab(x, mainTop + P(22), TINSIZE, "LAST SEEN", C.ink, false, has),
      lab(W - P(14), mainTop + P(22), TINSIZE, function() return e.meta end, C.ink, true, has),
      lab(x, P(297), TINSIZE, "POSITION", C.ink, false, has),
      { type = "label", x = 0, y = P(414) - ascent(TINSIZE), font = TINSIZE, text = "FROM HOME", color = C.ink,
        visible = function() return e.has and e.distKnown end, pos = function() return e.fromX, P(414) - ascent(TINSIZE) end },
      lab(P(14), H - P(16), TINSIZE, "SCAN WITH YOUR PHONE CAMERA TO OPEN THE MAP AT THIS SPOT", C.ink),
      { type = "label", x = x, y = P(220), font = BOLD, text = "NO SAVED POSITION YET", color = C.ink,
        visible = function() return not e.has end },
    })
    e.ago = field(list, "seen", 4, x, P(203), "l", -0.01)
    e.agoUnit = field(list, "ago", 9, x, P(204), "l", -0.01)
    e.lat = field(list, "j34", 12, x, P(336), "l", 0)
    e.lon = field(list, "j34", 12, x, P(378), "l", 0)
    e.dist = field(list, "chip", 8, x, P(422), "l", -0.01)
    return list
  end

  local function summaryPage()
    local list = {}
    header(list, "FLIGHT SUMMARY")
    local e = { ago = "", inv = false, cells = {} }
    v.sum = e
    local lw, rx2 = P(400), P(403)
    local topH = P(261)
    local half = floor((topH - gap) / 2)
    add(list, {
      lab(W - P(14), P(26), TINSIZE, function() return e.ago end, C.y, true),
      rect(0, mainTop, lw, topH, C.y),
      lab(P(14), mainTop + P(22), TINSIZE, "FLIGHT TIME", C.ink),
      rect(rx2, mainTop, W - rx2, half, C.y, { color = function() return e.inv and C.ink or C.y end }),
      lab(rx2 + P(14), mainTop + P(22), TINSIZE, "LOWEST CELL", function() return e.inv and C.y or C.ink end),
      rect(rx2, mainTop + half + gap, W - rx2, topH - half - gap, C.y),
      lab(rx2 + P(14), mainTop + half + gap + P(22), TINSIZE, "USED", C.ink),
    })
    e.flight = field(list, "flight", 7, P(14), mainTop + P(244), "l", -0.01)
    local cb, ub = mainTop + P(114), mainTop + half + gap + P(114)
    e.cell = field(list, "cell", 5, rx2 + P(14), cb, "l", -0.01)
    e.used = field(list, "cell", 6, rx2 + P(14), ub, "l", -0.01)
    e.cellUnitX, e.usedUnitX = rx2, rx2
    add(list, {
      { type = "label", x = 0, y = cb - ascent(BOLD), font = BOLD, text = "V",
        color = function() return e.inv and C.y or C.ink end, pos = function() return e.cellUnitX, cb - ascent(BOLD) end,
        visible = function() return e.cellUnitX > rx2 end },
      { type = "label", x = 0, y = ub - ascent(BOLD), font = BOLD, text = "MAH", color = C.ink,
        pos = function() return e.usedUnitX, ub - ascent(BOLD) end, visible = function() return e.usedUnitX > rx2 end },
    })
    local rowTop2 = mainTop + topH + gap
    local tw = (W - 2 * gap) / 3
    for i, name in ipairs({ "MAX DIST", "MAX ALT", "TOP SPEED" }) do
      local x0 = floor((i - 1) * (tw + gap) + 0.5)
      local x1 = (i == 3) and W or floor((i - 1) * (tw + gap) + tw + 0.5)
      local c = { unit = "", unitX = x0 + P(14), right = x1 - P(4), uf = BOLD }
      e.cells[i] = c
      local vb = rowTop2 + P(102)
      add(list, {
        rect(x0, rowTop2, x1 - x0, P(118), C.y),
        lab(x0 + P(14), rowTop2 + P(22), TINSIZE, name, C.ink),
      })
      c.fld = field(list, "sum", 6, x0 + P(14), vb, "l", -0.01)
      list[#list + 1] = { type = "label", x = x0, y = vb - ascent(BOLD), font = BOLD, text = function() return c.unit end,
        color = C.ink, pos = function() return c.unitX, vb - ascent(BOLD) end }
    end
    local ft = rowTop2 + P(118) + gap
    local fb = ft + P(28)
    add(list, {
      rect(0, ft, W, H - ft, C.y),
      lab(P(14), fb, TINSIZE, "LANDED", C.ink),
      { type = "label", x = 0, y = fb - ascent(TINSIZE), font = TINSIZE, text = function() return e.dir end, color = C.ink,
        pos = function() return e.dirX, fb - ascent(TINSIZE) end },
      lab(W - P(14), fb, TINSIZE, function() return e.pos end, C.ink, true),
    })
    e.dirX, e.dir, e.pos = 0, "", ""
    e.landed = field(list, "chip", 8, P(77), fb + P(7), "l", -0.01)
    return list
  end

  local function logPage()
    local list = {}
    header(list, "LOGBOOK", "key")
    local e = { totals = {}, rows = {} }
    v.log = e
    local tw = (W - gap) / 2
    for i = 1, 2 do
      local x0 = (i == 1) and 0 or floor(tw + gap + 0.5)
      local x1 = (i == 1) and floor(tw + 0.5) or W
      local t = { has = false, quad = "", unit = "", unitX = x0 + P(14) }
      e.totals[i] = t
      add(list, {
        rect(x0, mainTop, x1 - x0, P(172), C.y),
        lab(x0 + P(14), mainTop + P(22), TINSIZE, function() return t.quad end, C.ink),
        { type = "label", x = 0, y = mainTop + P(155) - ascent(SMLSIZE), font = SMLSIZE, text = function() return t.unit end,
          color = C.ink, pos = function() return t.unitX, mainTop + P(155) - ascent(SMLSIZE) end },
      })
      t.count = field(list, "count", 4, x0 + P(14), mainTop + P(156), "l", -0.01)
    end
    local ht = mainTop + P(172) + gap
    local cols = { 0, 150, 260, 350, 490, 610 }
    local heads = { "DATE", "QUAD", "TIME", "LOW CELL", "MAX DIST", "USED" }
    list[#list + 1] = rect(0, ht, W, P(30), C.y)
    for j = 1, 6 do list[#list + 1] = lab(P(14) + P(cols[j]), ht + P(19), TINSIZE, heads[j], C.ink) end
    local top = ht + P(30) + gap
    local rh = P(73)
    local fits = min(K.BOOK_RECENT, floor((H - top + gap) / (rh + gap)))
    for i = 1, fits do
      local y0 = top + (i - 1) * (rh + gap)
      local r = { "", "", "", "", "", "", lost = false }
      e.rows[i] = r
      local base = y0 + P(42)
      local chipX, chipY = P(14) + P(cols[6]), y0 + P(22)
      add(list, {
        rect(0, y0, W, min(rh, H - y0), C.y),
        lab(P(14), base, SMLSIZE, function() return r[1] end, C.ink),
        rect(chipX, chipY, P(92), P(29), C.red, { visible = function() return r.lost end }),
        { type = "label", x = chipX, y = chipY + floor((P(29) - textH(TINSIZE)) / 2 + 0.5), w = P(92), align = CENTER,
          font = TINSIZE, text = "LINK LOST", color = C.ink, visible = function() return r.lost end },
      })
      r.quad = field(list, "chip", 9, P(14) + P(cols[2]), base + P(6), "l", -0.01)
      for j = 3, 6 do
        list[#list + 1] = lab(P(14) + P(cols[j]), base, SMLSIZE, function() return r[j] end, C.ink,
          false, (j == 6) and function() return not r.lost end or nil)
      end
    end
    list[#list + 1] = { type = "label", x = 0, y = P(300), w = W, align = CENTER, font = BOLD,
      text = "NO FLIGHTS YET. EACH ONE IS LOGGED WHEN THE QUAD DISARMS.", color = C.ink,
      visible = function() return e.empty end }
    return list
  end

  -- Waiting and simulator -------------------------------------------------------------------
  local function waitPage()
    local list = {}
    band(list, "waitBand")
    local word = S.words.wait
    local base = H - P(40) - gap - P(55)
    add(list, {
      rect(0, mainTop, W, H - P(40) - gap - mainTop, C.y),
      lab(P(14), mainTop + P(22), TINSIZE, "NO TELEMETRY", C.ink),
      K.sWord(word, P(14), base),
      -- the cursor stands 24 px clear of the G (spec 7.3)
      rect(P(14) + floor(word.adv + 0.5) + P(24), base - P(146), P(44), P(150), C.ink,
        { visible = function() return getTime() % 110 < 55 end }),
      lab(P(14), H - P(40) - gap - P(17), SMLSIZE, "PLUG IN A BATTERY. TELEMETRY APPEARS ONCE IT LINKS.", C.ink),
    })
    return list
  end

  local function simPage()
    local list = {}
    band(list, "simBand")
    local base = H - P(40) - gap - P(60)
    add(list, {
      rect(0, mainTop, W, H - P(40) - gap - mainTop, C.ink),
      lab(P(14), mainTop + P(22), TINSIZE, "USB JOYSTICK", C.y),
      K.sWord(S.words.sim, P(14), base),
      lab(P(14), H - P(40) - gap - P(23), SMLSIZE, "PLUG IN USB AND PICK JOYSTICK. THE SWITCHES WORK AS ON THE QUADS.", C.y),
    })
    return list
  end

  w.lazy = { dash = dashPage, nav = navPage, lost = lostPage, find = findPage, summary = summaryPage, log = logPage,
             wait = waitPage, sim = simPage }
  v.txPct, v.txVolts = "", ""

  w.refs = lvgl.build({
    -- the screen is ink and every cell a filled rectangle, so the 3 px gaps read as rules; the
    -- simulator turns it inside out
    rect(0, 0, W, H, C.ink, { color = function() return v.screen == "sim" and C.y or C.ink end }),
    { type = "box", name = "dash", x = 0, y = 0, w = W, h = H, visible = on("dash") },
    { type = "box", name = "wait", x = 0, y = 0, w = W, h = H, visible = on("wait") },
    { type = "box", name = "sim", x = 0, y = 0, w = W, h = H, visible = on("sim") },
    { type = "box", name = "nav", x = 0, y = 0, w = W, h = H, visible = on("nav") },
    { type = "box", name = "lost", x = 0, y = 0, w = W, h = H, visible = on("lost") },
    { type = "box", name = "find", x = 0, y = 0, w = W, h = H, visible = on("find") },
    { type = "box", name = "summary", x = 0, y = 0, w = W, h = H, visible = on("summary") },
    { type = "box", name = "log", x = 0, y = 0, w = W, h = H, visible = on("log") },
    { type = "box", x = 0, y = 0, w = W, h = H, children = row,
      visible = function() return v.screen == "dash" or v.screen == "wait" or v.screen == "sim" end },
  })
  w.P, w.S = P, S
end

-- Per frame -------------------------------------------------------------------------------------
-- chips from x = 6: yellow on the plain ink band, ink on hazard stripes, red for caution flags
local function layChips(P, chips, list, striped)
  local x = P(6)
  for i = 1, CHIPS do
    local c = chips[i]
    local b = list and list[i]
    if b then
      local text = b[1]
      local fg
      if striped then c.bg, fg = C.ink, "y"
      elseif b[2] == "caution" then c.bg, fg = C.red, "ink"
      else c.bg, fg = C.y, "ink" end
      local wd = sSet(c.fld, text, fg, x + P(10))
      c.x, c.w = x, wd + 2 * P(10)
      x = x + c.w + P(6)
    else
      c.w = 0
      sSet(c.fld, "", "ink")
    end
  end
end

-- the TX chip on the right of the band, in colours inverted against it
local function layTx(w, tx, striped, low)
  local P = w.P
  local v = w.v
  tx.bg = striped and C.ink or C.y
  tx.fg = low and C.red or (striped and C.y or C.ink)
  if low then tx.bg = C.ink end
  local wTx, wPct, wV = textW("TX", TINSIZE), textW(v.txPct, BOLD), textW(v.txVolts, TINSIZE)
  tx.w = P(10) + wTx + P(8) + wPct + P(8) + wV + P(10)
  tx.x = w.zone.w - P(6) - tx.w
  tx.pctX = tx.x + P(10) + wTx + P(8)
  tx.voltX = tx.pctX + wPct + P(8)
end

local function view(w, d)
  local v, P = w.v, w.P
  v.screen = PAGE_OF[d.screen]
  local alarm = d.failsafe or d.screen == "lost"
  v.ground = alarm and C.red or C.y
  v.txPct, v.txVolts = string.format("%d%%", floor(d.txFrac * 100 + 0.5)), string.format("%.1fV", d.txV)
  local function stat(c, value, unit, row)
    if value then
      local wd = sSet(c.fld, value, row or "ink")
      c.unit, c.unitX = unit or "", c.fld.x + wd + P(6)
      -- a unit that would run into the next cell is left off
      if c.right and c.unit ~= "" and c.unitX + textW(c.unit, c.uf) > c.right then c.unit = "" end
    else
      sSet(c.fld, "~", "ink35")
      c.unit = ""
    end
  end

  -- switch row: yellow at home, ink when set, red when armed; the simulator swaps yellow and ink
  if v.screen == "dash" or v.screen == "wait" or v.screen == "sim" then
    local sim = v.screen == "sim"
    for i, s in ipairs(K.switches) do
      local t, tile = w.sw[i], v.sw[i]
      local text = switchText(s, t)
      local f = tile.fld
      if sWidth(f.f, text, f.track) > tile.room then text = upper(t.text) end
      while #text > 1 and sWidth(f.f, text, f.track) > tile.room do text = string.sub(text, 1, -2) end
      local home = t.sev == "home"
      if t.sev == "armed" then tile.bg, tile.fg = C.red, C.ink
      elseif home ~= sim then tile.bg, tile.fg = C.y, C.ink
      else tile.bg, tile.fg = C.ink, C.y end
      sSet(f, text, (tile.fg == C.y) and "y" or "ink")
    end
  end

  -- band: stripes when armed (red with them in an alarm), plain ink otherwise
  local bandKey = v.screen .. "Band"
  local b = v[bandKey]
  if b then
    local pat = w.S.patterns
    local striped = (v.screen == "sim") or d.armed or alarm
    b.file = (v.screen == "sim" and pat.haz_yi.f) or (alarm and pat.haz_ir.f) or (striped and pat.haz_iy.f) or nil
    local list
    if v.screen == "dash" or v.screen == "nav" then
      list = {}
      for _, x in ipairs(d.blocks or {}) do
        if x[3] ~= "nohome" then list[#list + 1] = x end
      end
    elseif v.screen == "lost" then
      list = { { "LINK LOST", "warn" }, { K.clock((d.now - (w.lostAt or d.now)) / 100) .. " AGO", "warn" } }
    elseif v.screen == "wait" then
      list = { { "NO LINK", "neutral" } }
    elseif v.screen == "sim" then
      list = { { "SIMULATOR", "set" } }
    end
    layChips(P, v.chips[bandKey], list, striped)
    layTx(w, v[bandKey .. "Tx"], striped, d.txLow)
  end

  if v.screen == "dash" and v.bat then
    local bat, lq = v.bat, v.lq
    -- battery gauge
    if d.cell then
      local frac = max(0, min(1, (d.cell - 3.3) / 0.9))
      bat.dep = floor(bat.h * (1 - frac) + 0.5)
      bat.heroW = sSet(bat.hero, string.format("%.2f", d.cell), "ink")
      bat.detail.text = string.format("%dS %.1fV", d.cells, d.v)
    else
      bat.dep = bat.h
      bat.heroW = sSet(bat.hero, "", "ink")
      bat.detail.text = ""
    end
    bat.unitX = bat.hero.x + bat.heroW + P(10)
    local q = d.rqly or 0
    lq.dep = floor(lq.h * (1 - max(0, min(1, q / 100))) + 0.5)
    lq.heroW = sSet(lq.hero, tostring(q), "ink")
    lq.unitX = lq.hero.x + lq.heroW + P(10)
    local sub = {}
    if d.rssi then sub[#sub + 1] = string.format("%dDBM", d.rssi) end
    if d.tpwr then sub[#sub + 1] = string.format("%dMW", d.tpwr) end
    lq.detail.text = table.concat(sub, " ")
    sSet(v.timer, K.clock(d.timer), "ink")

    -- GPS chip: plain when all is well, inverted with a word when not
    local g = v.gps
    local right = w.zone.w - P(14)
    local inv = d.gps ~= "ok" and d.gps ~= "none"
    local status = (d.gps == "nofix" and " NO FIX") or (d.gps == "nohome" and " NO HOME") or ""
    g.inv, g.fg, g.status = inv, inv and v.ground or C.ink, status
    local x = right - (inv and P(8) or 0)
    g.statusX = x - textW(status, TINSIZE)
    g.satX = g.statusX - textW("SAT", TINSIZE)
    local count = d.hasGps and tostring(d.sats) or "~"
    local cw = sWidth(g.count.f, count, g.count.track)
    local cx = g.satX - P(6) - cw
    sSet(g.count, count, inv and ((v.ground == C.red) and "red" or "y") or "ink", cx)
    g.gpsX = cx - P(6) - textW("GPS", TINSIZE)
    g.x, g.w = g.gpsX - P(8), right - g.gpsX + P(8)

    -- stats
    local c = v.stats
    local home = c[1]
    home.inv = d.armed and d.gps == "nohome"
    if home.inv then
      sSet(home.fld, "", "ink")
      home.unit, home.arrow = "", nil
    else
      local dv, du = K.distVU(d.dist)
      stat(home, d.dist and dv, upper(du))
      home.arrow = d.homeRel
    end
    stat(c[2], d.alt and num(d.alt), "M")
    stat(c[3], d.spd and num(d.spd), "KM/H")
    stat(c[4], (d.capa and d.capa > 0) and tostring(d.capa), "MAH")
  elseif (v.screen == "nav" and v.navInfo) or (v.screen == "lost" and v.lostInfo) then
    local lost = v.screen == "lost"
    local e = lost and v.lostInfo or v.navInfo
    local dist, pos, b
    if lost then
      dist, pos = w.lastDist, w.last
      b = (w.home and pos) and K.bearing(w.home, pos) or nil
    else
      dist, pos, b = d.dist, d.pos, d.fromHome
      e.arrow = d.homeRel
    end
    if dist and b then
      local dv, du = K.distVU(dist)
      local wd = sSet(e.dist, dv, "ink")
      e.unit, e.unitX, e.dir = upper(du), e.dist.x + wd + P(8), K.compass(b) .. " OF HOME"
    else
      sSet(e.dist, "", "ink")
      e.unit, e.dir = "", ""
    end
    sSet(e.coord, pos and string.format("%.6f, %.6f", pos.lat, pos.lon) or "", lost and "red" or "y")
    local c = e.cells
    local red = lost and "red" or "y"
    local function cell(i, value, unit, inv)
      c[i].inv = inv or false
      stat(c[i], value, unit, inv and red or "ink")
    end
    if lost then
      local s = w.stats
      local md, mu = K.distVU(s.maxDist > 0 and s.maxDist or nil)
      cell(1, s.maxDist > 0 and md, upper(mu))
      cell(2, s.maxAlt and num(s.maxAlt), "M")
      cell(3, s.maxSpd > 0 and num(s.maxSpd), "KM/H")
      cell(4, s.minCell and string.format("%.2f", s.minCell), "V", K.lowSev(s.minCell) == "caution")
      cell(5, (s.capa and s.capa > 0) and tostring(s.capa), "MAH")
      cell(6, K.clock(d.timer), "")
    else
      cell(1, d.alt and num(d.alt), "M")
      cell(2, d.spd and num(d.spd), "KM/H")
      cell(3, d.hdg and tostring(floor(d.hdg + 0.5) % 360), "\194\176")
      cell(4, d.cell and string.format("%.2f", d.cell), "V", K.cellSev(d.cell) == "warn")
      cell(5, d.rqly and tostring(d.rqly), "%")
      cell(6, (d.capa and d.capa > 0) and tostring(d.capa), "MAH")
    end
  elseif v.screen == "find" and v.find then
    local e, s = v.find, w.saved
    e.has = s ~= nil
    if s then
      local secs = s.epoch and (getRtcTime() - s.epoch)
      local n, unit = K.agoParts((secs and secs >= 0) and secs or 0)
      local wd = sSet(e.ago, n, "ink")
      sSet(e.agoUnit, upper(unit), "ink", e.ago.x + wd + P(8))
      e.meta = (s.quad and (s.quad .. " \226\128\162 ") or "") .. s.when
      sSet(e.lat, string.format("%.6f", s.lat), "ink")
      sSet(e.lon, string.format("%.6f", s.lon), "ink")
      e.distKnown = s.dist ~= nil
      local dw = sSet(e.dist, s.dist and (s.dist .. " M") or "", "ink")
      e.fromX = e.dist.x + dw + P(8)
      K.syncQR(w, string.format("https://maps.google.com/?q=%.6f,%.6f", s.lat, s.lon), w.qrSide, C.ink, C.y)
    else
      for _, f in ipairs({ e.ago, e.agoUnit, e.lat, e.lon, e.dist }) do sSet(f, "", "ink") end
      K.syncQR(w, nil, w.qrSide, C.ink, C.y)
    end
  elseif v.screen == "summary" and v.sum then
    local e, s = v.sum, w.stats
    e.ago = "ENDED " .. K.clock((d.now - (w.lostAt or d.now)) / 100) .. " AGO"
    sSet(e.flight, K.clock(d.timer), "ink")
    e.inv = K.lowSev(s.minCell) == "caution"
    if s.minCell then
      local wd = sSet(e.cell, string.format("%.2f", s.minCell), e.inv and "y" or "ink")
      e.cellUnitX = e.cell.x + wd + P(6)
    else
      sSet(e.cell, "", "ink")
      e.cellUnitX = 0
    end
    if s.capa and s.capa > 0 then
      local wd = sSet(e.used, tostring(s.capa), "ink")
      e.usedUnitX = e.used.x + wd + P(6)
    else
      sSet(e.used, "", "ink")
      e.usedUnitX = 0
    end
    local md, mu = K.distVU(s.maxDist > 0 and s.maxDist or nil)
    stat(e.cells[1], s.maxDist > 0 and md, upper(mu))
    stat(e.cells[2], s.maxAlt and num(s.maxAlt), "M")
    stat(e.cells[3], s.maxSpd > 0 and num(s.maxSpd), "KM/H")
    if w.home and w.last and w.lastDist then
      local dv, du = K.distVU(w.lastDist)
      local wd = sSet(e.landed, dv .. " " .. upper(du), "ink")
      e.dir, e.dirX = K.compass(K.bearing(w.home, w.last)) .. " OF HOME", e.landed.x + wd + P(12)
    else
      sSet(e.landed, "", "ink")
      e.dir = ""
    end
    e.pos = w.last and string.format("%.6f, %.6f", w.last.lat, w.last.lon) or ""
  elseif v.screen == "log" and v.log then
    local e, b = v.log, w.book
    local quads = K.topQuads(b, 2)
    for i = 1, 2 do
      local t = e.totals[i]
      local q = quads[i] and b.totals[quads[i]]
      t.has = q ~= nil
      if q then
        t.quad = upper(string.sub(quads[i], 1, 14))
        local cw = sSet(t.count, tostring(q.flights), "ink")
        t.unit = ((q.flights == 1) and "FLIGHT" or "FLIGHTS") .. " \226\128\162 " .. floor(q.secs / 60 + 0.5) .. " MIN"
        t.unitX = t.count.x + cw + P(6)
      else
        t.quad, t.unit = "", ""
        sSet(t.count, "", "ink")
      end
    end
    e.empty = b.recent[1] == nil
    for i, r in ipairs(e.rows) do
      local f = b.recent[i]
      if f then
        local dv, du = K.distVU(f.maxDist)
        r[1] = string.sub(f.when, 6)
        sSet(r.quad, upper(string.sub(f.quad, 1, 9)), "ink")
        r[3] = K.clock(f.secs)
        r[4] = f.minCell and string.format("%.2f V", f.minCell) or "--"
        r[5] = f.maxDist and (dv .. " " .. upper(du)) or "--"
        r.lost = f.lost
        r[6] = f.lost and "LINK LOST" or (f.mah and (f.mah .. " MAH") or "--")
      else
        r[1], r[3], r[4], r[5], r[6], r.lost = "", "", "", "", "", false
        sSet(r.quad, "", "ink")
      end
    end
  end
end

return { build = build, view = view, page = function(screen) return PAGE_OF[screen] end }
