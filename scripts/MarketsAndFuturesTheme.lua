-- Colour themes for the menu and the HUD (presets, separate HUD choice, accent colour and brightness tuning)

MFTheme = {
    menuPreset = 1,   -- 1..#PRESETS
    hudPreset = 0,    -- 0 = same as the menu, otherwise 1..#PRESETS
    accent = 0,       -- 0 = the preset's own accent, otherwise 1..#ACCENTS
    bright = 100,     -- background / button brightness in percent
    cache = {},
}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local WHITE = {1, 1, 1}

local function mix(a, b, t) return {a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t} end
local function mul(a, k) return {clamp(a[1] * k, 0, 1), clamp(a[2] * k, 0, 1), clamp(a[3] * k, 0, 1)} end

-- bg = panel body, tint = buttons / header, accent = frame lines, hi = bright accent (titles, markers)
MFTheme.PRESETS = {
    {key = "mf_theme_1",  bg = {0.05, 0.07, 0.06}, tint = {0.20, 0.50, 0.28}, accent = {0.80, 0.65, 0.22}, hi = {1.00, 0.82, 0.25}},   -- Forest
    {key = "mf_theme_2",  bg = {0.04, 0.05, 0.10}, tint = {0.22, 0.38, 0.75}, accent = {0.45, 0.70, 1.00}, hi = {0.65, 0.85, 1.00}},   -- Midnight Blue
    {key = "mf_theme_3",  bg = {0.09, 0.07, 0.03}, tint = {0.70, 0.50, 0.12}, accent = {0.90, 0.72, 0.25}, hi = {1.00, 0.88, 0.40}},   -- Harvest Gold
    {key = "mf_theme_4",  bg = {0.09, 0.04, 0.04}, tint = {0.65, 0.20, 0.18}, accent = {0.85, 0.70, 0.50}, hi = {1.00, 0.85, 0.60}},   -- Barn Red
    {key = "mf_theme_5",  bg = {0.06, 0.07, 0.09}, tint = {0.30, 0.40, 0.52}, accent = {0.70, 0.78, 0.88}, hi = {0.85, 0.92, 1.00}},   -- Slate
    {key = "mf_theme_6",  bg = {0.07, 0.07, 0.07}, tint = {0.75, 0.40, 0.10}, accent = {0.95, 0.55, 0.15}, hi = {1.00, 0.70, 0.30}},   -- Charcoal & Orange
    {key = "mf_theme_7",  bg = {0.10, 0.04, 0.07}, tint = {0.75, 0.30, 0.40}, accent = {1.00, 0.60, 0.35}, hi = {1.00, 0.78, 0.50}},   -- Sunset
    {key = "mf_theme_8",  bg = {0.07, 0.05, 0.10}, tint = {0.45, 0.32, 0.70}, accent = {0.78, 0.65, 0.95}, hi = {0.90, 0.80, 1.00}},   -- Lavender
    {key = "mf_theme_9",  bg = {0.03, 0.08, 0.09}, tint = {0.10, 0.55, 0.58}, accent = {0.35, 0.85, 0.85}, hi = {0.55, 1.00, 0.95}},   -- Teal
    {key = "mf_theme_10", bg = {0.10, 0.08, 0.05}, tint = {0.62, 0.48, 0.30}, accent = {0.85, 0.72, 0.50}, hi = {0.98, 0.88, 0.65}},   -- Desert Sand
    {key = "mf_theme_11", bg = {0.05, 0.08, 0.10}, tint = {0.35, 0.62, 0.78}, accent = {0.80, 0.92, 1.00}, hi = {1.00, 1.00, 1.00}},   -- Arctic
    {key = "mf_theme_12", bg = {0.00, 0.00, 0.00}, tint = {0.15, 0.45, 0.15}, accent = {1.00, 1.00, 0.00}, hi = {1.00, 1.00, 0.20}},   -- High Contrast
    -- flat, translucent black panels like the game's own HUD and input help
    {key = "mf_theme_13", bg = {0.00, 0.00, 0.00}, tint = {0.28, 0.28, 0.28}, accent = {0.45, 0.45, 0.45}, hi = {0.96, 0.96, 0.96}, flat = true},   -- Game Default
}

-- optional accent colours that replace the preset's frame / title colour
MFTheme.ACCENTS = {
    {1.00, 0.82, 0.25}, {1.00, 0.60, 0.15}, {0.95, 0.35, 0.30}, {1.00, 0.50, 0.70}, {0.70, 0.50, 0.95},
    {0.40, 0.65, 1.00}, {0.30, 0.90, 0.90}, {0.40, 0.90, 0.45}, {1.00, 1.00, 1.00},
}

-- fills a rectangle with a colour table {r, g, b}
function MFTheme.rect(x, y, w, h, c, a)
    drawFilledRect(x, y, w, h, c[1], c[2], c[3], a or 1)
end

function MFTheme:build(pi)
    local p = self.PRESETS[pi] or self.PRESETS[1]
    local k = self.bright / 100
    local bg, tint = mul(p.bg, k), mul(p.tint, k)
    local accent, hi = p.accent, p.hi
    if self.accent > 0 and self.ACCENTS[self.accent] ~= nil then
        hi = self.ACCENTS[self.accent]
        accent = mul(hi, 0.8)
    end
    return {
        bg = bg, tint = tint, flat = p.flat == true,
        box = mix(bg, tint, 0.18), btn = mix(bg, tint, 0.45), btnOn = tint,
        hdrBtn = mix(bg, tint, 0.28), hdrHover = mix(bg, tint, 0.50), hover = mix(bg, tint, 0.30),
        track = mix(bg, tint, 0.12), fill = mix(tint, WHITE, 0.10),
        hdrTop = mul(tint, 0.9), hdrBot = mul(tint, 0.45), band = mul(tint, 0.7),
        accent = accent, hi = hi, sub = mix(tint, WHITE, 0.75),
    }
end

function MFTheme:palette(pi)
    local c = self.cache[pi]
    if c == nil then c = self:build(pi); self.cache[pi] = c end
    return c
end

-- kind: "menu" or "hud"
function MFTheme:get(kind)
    local pi = self.menuPreset
    if kind == "hud" and self.hudPreset > 0 then pi = self.hudPreset end
    return self:palette(pi)
end

function MFTheme:presetName(pi)
    local p = self.PRESETS[pi]
    return p ~= nil and MarketsAndFutures.t(p.key) or "?"
end

function MFTheme:changed()
    self.cache = {}
    if MFHud ~= nil then MFHud:save() end
end

function MFTheme:stepMenu(d)
    local n = #self.PRESETS
    self.menuPreset = (self.menuPreset - 1 + d) % n + 1
    self:changed()
end

function MFTheme:setMenu(i)
    self.menuPreset = clamp(i, 1, #self.PRESETS)
    self:changed()
end

function MFTheme:stepHud(d)
    local n = #self.PRESETS + 1          -- 0 (same as menu) .. n-1
    self.hudPreset = (self.hudPreset + d) % n
    self:changed()
end

function MFTheme:setAccent(i)
    self.accent = clamp(i, 0, #self.ACCENTS)
    self:changed()
end

function MFTheme:stepBright(d)
    self.bright = clamp(self.bright + d, 60, 140)
    self:changed()
end

function MFTheme:reset()
    self.menuPreset, self.hudPreset, self.accent, self.bright = 1, 0, 0, 100
    self:changed()
end

function MFTheme:saveTo(xml)
    setXMLInt(xml, "mfClient.theme#menu", self.menuPreset)
    setXMLInt(xml, "mfClient.theme#hud", self.hudPreset)
    setXMLInt(xml, "mfClient.theme#accent", self.accent)
    setXMLInt(xml, "mfClient.theme#bright", self.bright)
end

function MFTheme:loadFrom(xml)
    self.menuPreset = clamp(getXMLInt(xml, "mfClient.theme#menu") or self.menuPreset, 1, #self.PRESETS)
    self.hudPreset = clamp(getXMLInt(xml, "mfClient.theme#hud") or self.hudPreset, 0, #self.PRESETS)
    self.accent = clamp(getXMLInt(xml, "mfClient.theme#accent") or self.accent, 0, #self.ACCENTS)
    self.bright = clamp(getXMLInt(xml, "mfClient.theme#bright") or self.bright, 60, 140)
    self.cache = {}
end

-- ===================== ROUNDED RECTANGLES =====================
-- width / height of one screen unit, so that corners look round and not oval
function MFTheme.aspect()
    if g_screenWidth ~= nil and g_screenHeight ~= nil and g_screenWidth > 0 then return g_screenHeight / g_screenWidth end
    return 0.5625
end

-- rectangle with stepped, rounded corners. r = radius in screen-height units.
-- top / bottom (default true) switch the rounding of the upper / lower corner pair.
function MFTheme.rrect(x, y, w, h, c, a, r, top, bottom)
    if top == nil then top = true end
    if bottom == nil then bottom = true end
    a = a or 1
    local ar = MFTheme.aspect()
    r = math.min(r or 0.006, h / 2, w / (2 * ar))
    if r < 0.0007 or (not top and not bottom) then
        drawFilledRect(x, y, w, h, c[1], c[2], c[3], a)
        return
    end
    -- about one strip per screen pixel of radius, so the curve is smooth
    local sw, shpx = g_screenWidth or 1920, g_screenHeight or 1080
    local n = math.max(3, math.min(18, math.ceil(r * shpx)))
    local sh = r / n
    local pxw = 1 / sw
    local lo = bottom and r or 0
    local hi = top and r or 0
    -- Opaque shapes overlap their neighbours by half a pixel: where two rectangles only touch, the edge pixels can
    -- come out slightly see-through and show up as thin dark horizontal lines across the shape. (Translucent shapes
    -- must not overlap, or the doubled blend would show as light lines.)
    local e = (a >= 0.99) and (0.5 / shpx) or 0
    drawFilledRect(x, y + lo - e, w, h - lo - hi + 2 * e, c[1], c[2], c[3], a)
    local aa = a * 0.5
    for k = 0, n - 1 do
        local dy = r - (k + 0.5) * sh
        local inset = (r - math.sqrt(math.max(0, r * r - dy * dy))) * ar
        local sy1, sy2 = y + k * sh, y + h - (k + 1) * sh
        if bottom then
            drawFilledRect(x + inset, sy1, w - 2 * inset, sh + e, c[1], c[2], c[3], a)
            if inset > 0 then   -- half-transparent edge pixel softens the staircase
                drawFilledRect(x + inset - pxw, sy1, pxw, sh, c[1], c[2], c[3], aa)
                drawFilledRect(x + w - inset, sy1, pxw, sh, c[1], c[2], c[3], aa)
            end
        end
        if top then
            drawFilledRect(x + inset, sy2 - e, w - 2 * inset, sh + e, c[1], c[2], c[3], a)
            if inset > 0 then
                drawFilledRect(x + inset - pxw, sy2, pxw, sh, c[1], c[2], c[3], aa)
                drawFilledRect(x + w - inset, sy2, pxw, sh, c[1], c[2], c[3], aa)
            end
        end
    end
end

-- horizontal inset of a rounded top edge, for strips drawn by hand
function MFTheme.cornerInset(distFromTop, r)
    if distFromTop >= r then return 0 end
    local dy = r - distFromTop
    return (r - math.sqrt(math.max(0, r * r - dy * dy))) * MFTheme.aspect()
end

-- ===================== ITEM ICONS =====================
MFTheme.icons = {}

local function lookupIcon(idx)
    local ft = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeByIndex(idx) or nil
    if ft == nil then return false end
    local file = ft.hudOverlayFilename
    if file == nil or file == "" then file = ft.hudOverlayFilenameSmall end
    if file == nil or file == "" then return false end
    local id = createImageOverlay(file)
    if id == nil or id == 0 then return false end
    return id
end

-- draws the fill type's own icon (height h, square on screen); returns the width reserved for it
-- (also when the item has no icon, so that names stay aligned)
function MFTheme:drawIcon(idx, x, y, h, a)
    local w = h * self.aspect()
    local id = self.icons[idx]
    if id == nil then
        id = lookupIcon(idx)
        self.icons[idx] = id
    end
    if id then
        setOverlayColor(id, 1, 1, 1, a or 1)
        renderOverlay(id, x, y, w, h)
    end
    return w
end
