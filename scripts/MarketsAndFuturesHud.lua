-- Rotating price HUD, price alerts and per-player (client-local) settings.
-- Everything in here is personal to the player. Saved in <user profile>/modSettings/FS25_MarketsAndFutures/:
--   client.xml          HUD position / size / visibility / rotation / transparency, colour theme (all saves)
--   saves/<save>.xml    which items are on the HUD, price alerts, hidden stored items (one file per savegame)

MFHud = {
    cfg = {x = 0.80, y = 0.56, scale = 1.0, w = 0.17, h = 0.125, visible = true, rotate = 3, alpha = 0.80, alertSound = true, showGameLine = false},
    names = {},        -- fill type names shown on the HUD (ordered)
    hiddenStored = {}, -- fill type names hidden from the "Stored Items" list (trash column)
    set = {},          -- [name] = true
    alerts = {},       -- {name, dir (1 = rises to / -1 = falls to), pct (vs average), fired}
    index = 1, timer = 0,
    loaded = false, drag = nil,
    alertTimer = 0, statsTimer = 0,
    maxAlerts = 30,
    maxCustomCats = 3,
}

local DM = MarketsAndFutures
-- the panel keeps a fixed shape; its whole size (panel and text) follows one scale value
local BASE_W, BASE_H = 0.17, 0.190
local UPPER_H = 0.125   -- height of the text part; the rest at the bottom holds the price graph
local MIN_SCALE, MAX_SCALE = 0.5, 2.5

local function txt(x, y, size, s, r, g, b, align, bold)
    setTextBold(bold == true)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    if type(r) == "table" then r, g, b = r[1], r[2], r[3] end
    setTextColor(r or 1, g or 1, b or 1, 1)
    renderText(x, y, size, s)
end
local function TH() return MFTheme:get("hud") end
local function money(v) return g_i18n:formatMoney(v, 0, true, true) end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- ===================== LOCAL FILE =====================
function MFHud:getPath()
    local base = getUserProfileAppPath() .. "modSettings/FS25_MarketsAndFutures/"
    return base, base .. "client.xml"
end

-- Which savegame this is: the save folder name (savegame1 ...). Clients in multiplayer have no save folder, so
-- they use the map instead.
function MFHud:getSaveKey()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local key
    if mi ~= nil then
        if mi.savegameDirectory ~= nil then key = string.match(mi.savegameDirectory, "([^/\\]+)[/\\]*$")
        elseif mi.savegameIndex ~= nil then key = "savegame" .. tostring(mi.savegameIndex)
        elseif mi.mapId ~= nil then key = "mp_" .. tostring(mi.mapId) end
    end
    key = key or "default"
    return (string.gsub(key, "[^%w_%-%.]", "_"))
end

function MFHud:getSavePath()
    local base = self:getPath()
    return base .. "saves/", base .. "saves/" .. self:getSaveKey() .. ".xml"
end

-- the player's own categories (max 3, each {id, name}) and per-item category overrides {fillTypeName = categoryId}
local function readCats(xml)
    local cats, ov = {}, {}
    local i = 0
    while true do
        local key = string.format("mfClient.customCats.cat(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local id, name = getXMLString(xml, key .. "#id"), getXMLString(xml, key .. "#name")
        if id ~= nil and name ~= nil and #cats < 3 then table.insert(cats, {id = id, name = name}) end
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("mfClient.catOverrides.item(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local n, c = getXMLString(xml, key .. "#name"), getXMLString(xml, key .. "#cat")
        if n ~= nil and c ~= nil then ov[n] = c end
        i = i + 1
    end
    return cats, ov
end

local function writeCats(xml, cats, ov)
    for i, c in ipairs(cats) do
        local key = string.format("mfClient.customCats.cat(%d)", i - 1)
        setXMLString(xml, key .. "#id", c.id)
        setXMLString(xml, key .. "#name", c.name)
    end
    local i = 0
    for n, c in pairs(ov) do
        local key = string.format("mfClient.catOverrides.item(%d)", i)
        setXMLString(xml, key .. "#name", n)
        setXMLString(xml, key .. "#cat", c)
        i = i + 1
    end
end

-- reads the three per-save lists (HUD items, alerts, hidden stored items) out of an open xml file
local function readLists(xml)
    local names, set, alerts, hidden = {}, {}, {}, {}
    local i = 0
    while true do
        local key = string.format("mfClient.hudItems.item(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local n = getXMLString(xml, key .. "#name")
        if n ~= nil and not set[n] then
            set[n] = true
            table.insert(names, n)
        end
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("mfClient.alerts.alert(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local n = getXMLString(xml, key .. "#name")
        if n ~= nil then
            table.insert(alerts, {
                name = n, dir = getXMLInt(xml, key .. "#dir") or 1,
                pct = getXMLFloat(xml, key .. "#pct") or 10, fired = false,
            })
        end
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("mfClient.storedHidden.item(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local n = getXMLString(xml, key .. "#name")
        if n ~= nil then hidden[n] = true end
        i = i + 1
    end
    return names, set, alerts, hidden
end

local function writeLists(xml, names, alerts, hidden)
    for i, n in ipairs(names) do
        setXMLString(xml, string.format("mfClient.hudItems.item(%d)#name", i - 1), n)
    end
    for i, a in ipairs(alerts) do
        local key = string.format("mfClient.alerts.alert(%d)", i - 1)
        setXMLString(xml, key .. "#name", a.name)
        setXMLInt(xml, key .. "#dir", a.dir)
        setXMLFloat(xml, key .. "#pct", a.pct)
    end
    local hi = 0
    for n, on in pairs(hidden) do
        if on then
            setXMLString(xml, string.format("mfClient.storedHidden.item(%d)#name", hi), n)
            hi = hi + 1
        end
    end
end

-- Global (all saves): HUD position / size / visibility / rotation / transparency and the colour theme, in client.xml.
-- Per save: HUD items, price alerts and hidden stored items, in saves/<savegame>.xml.
function MFHud:load()
    self.loaded = true
    self.saveKey = self:getSaveKey()
    self.names, self.set, self.alerts, self.hiddenStored = {}, {}, {}, {}
    self.customCats, self.catOverrides = {}, {}
    self.legacy = nil
    self.firstAlertCheck = true

    local _, file = self:getPath()
    if fileExists(file) then
        local xml = loadXMLFile("mfClient", file)
        if xml ~= nil and xml ~= 0 then
            local c = self.cfg
            c.x = getXMLFloat(xml, "mfClient.hud#x") or c.x
            c.y = getXMLFloat(xml, "mfClient.hud#y") or c.y
            local sc = getXMLFloat(xml, "mfClient.hud#scale")
            if sc == nil then
                local oldW = getXMLFloat(xml, "mfClient.hud#w")   -- file written by an earlier version
                if oldW ~= nil then sc = oldW / BASE_W end
            end
            c.scale = sc or c.scale
            local vis = getXMLBool(xml, "mfClient.hud#visible")
            if vis ~= nil then c.visible = vis end
            c.rotate = getXMLInt(xml, "mfClient.hud#rotate") or c.rotate
            c.alpha = getXMLFloat(xml, "mfClient.hud#alpha") or c.alpha
            local snd = getXMLBool(xml, "mfClient.hud#alertSound")
            if snd ~= nil then c.alertSound = snd end
            local gl = getXMLBool(xml, "mfClient.hud#showGameLine")
            if gl ~= nil then c.showGameLine = gl end
            self:clampRect()
            if MFTheme ~= nil then MFTheme:loadFrom(xml) end
            -- lists written by older versions (before they were saved per savegame): only used to seed saves that already exist
            local ln, _, la, lh = readLists(xml)
            if #ln > 0 or #la > 0 or next(lh) ~= nil then self.legacy = {names = ln, alerts = la, hidden = lh} end
            delete(xml)
        end
    end

    local _, saveFile = self:getSavePath()
    if fileExists(saveFile) then
        local xml = loadXMLFile("mfClientSave", saveFile)
        if xml ~= nil and xml ~= 0 then
            self.names, self.set, self.alerts, self.hiddenStored = readLists(xml)
            self.customCats, self.catOverrides = readCats(xml)
            delete(xml)
        end
    elseif self.legacy ~= nil then
        -- no file for this save yet: an existing save of this mod keeps what it had; a brand-new save starts empty
        local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
        local existing = mi ~= nil and mi.savegameDirectory ~= nil and fileExists(mi.savegameDirectory .. "/marketsAndFutures.xml")
        if existing then
            for _, n in ipairs(self.legacy.names) do
                if not self.set[n] then self.set[n] = true; table.insert(self.names, n) end
            end
            for _, a in ipairs(self.legacy.alerts) do
                table.insert(self.alerts, {name = a.name, dir = a.dir, pct = a.pct, fired = false})
            end
            for n, on in pairs(self.legacy.hidden) do self.hiddenStored[n] = on end
            self:save()
        end
    end
end

function MFHud:save()
    local base, file = self:getPath()
    createFolder(getUserProfileAppPath() .. "modSettings/")
    createFolder(base)
    local xml = createXMLFile("mfClient", file, "mfClient")
    if xml ~= nil and xml ~= 0 then
        local c = self.cfg
        setXMLFloat(xml, "mfClient.hud#x", c.x)
        setXMLFloat(xml, "mfClient.hud#y", c.y)
        setXMLFloat(xml, "mfClient.hud#scale", c.scale)
        setXMLBool(xml, "mfClient.hud#visible", c.visible)
        setXMLInt(xml, "mfClient.hud#rotate", c.rotate)
        setXMLFloat(xml, "mfClient.hud#alpha", c.alpha)
        setXMLBool(xml, "mfClient.hud#alertSound", c.alertSound ~= false)
        setXMLBool(xml, "mfClient.hud#showGameLine", c.showGameLine == true)
        if MFTheme ~= nil then MFTheme:saveTo(xml) end
        -- the old shared lists stay in this file untouched so other existing saves can still be seeded from them
        if self.legacy ~= nil then writeLists(xml, self.legacy.names, self.legacy.alerts, self.legacy.hidden) end
        saveXMLFile(xml)
        delete(xml)
    end

    if self.loaded then
        local dir, saveFile = self:getSavePath()
        createFolder(dir)
        local sx = createXMLFile("mfClientSave", saveFile, "mfClient")
        if sx ~= nil and sx ~= 0 then
            writeLists(sx, self.names, self.alerts, self.hiddenStored)
            writeCats(sx, self.customCats or {}, self.catOverrides or {})
            saveXMLFile(sx)
            delete(sx)
        end
    end
end

-- ===================== HIDDEN STORED ITEMS =====================
function MFHud:isStoredHidden(idx)
    local n = g_fillTypeManager:getFillTypeNameByIndex(idx)
    return n ~= nil and self.hiddenStored[n] == true
end

function MFHud:toggleStoredHidden(idx)
    local n = g_fillTypeManager:getFillTypeNameByIndex(idx)
    if n == nil then return end
    if self.hiddenStored[n] then self.hiddenStored[n] = nil else self.hiddenStored[n] = true end
    self:save()
end

-- ===================== HUD ITEMS =====================
function MFHud:nameOf(idx)
    return g_fillTypeManager:getFillTypeNameByIndex(idx)
end

function MFHud:isChecked(idx)
    local n = self:nameOf(idx)
    return n ~= nil and self.set[n] == true
end

function MFHud:toggle(idx)
    local n = self:nameOf(idx)
    if n == nil then return end
    if self.set[n] then
        self.set[n] = nil
        for i = #self.names, 1, -1 do
            if self.names[i] == n then table.remove(self.names, i) end
        end
    else
        self.set[n] = true
        table.insert(self.names, n)
    end
    self:save()
end

-- fill type indices of the checked items that exist on this map
function MFHud:getItems()
    local list = {}
    for _, n in ipairs(self.names) do
        local idx = g_fillTypeManager:getFillTypeIndexByName(n)
        if idx ~= nil and DM.fills ~= nil and DM.fills[idx] ~= nil then table.insert(list, idx) end
    end
    return list
end

function MFHud:setVisible(v)
    self.cfg.visible = v
    self:save()
end

function MFHud:setScale(v)
    local c = self.cfg
    local top = c.y + c.h
    c.scale = v
    self:clampRect()
    c.y = clamp(top - c.h, 0, 1 - c.h)   -- keep the top edge where it was
    self:save()
end

function MFHud:resetPosition()
    local c = self.cfg
    c.x, c.y, c.scale = 0.80, 0.56, 1.0
    self:clampRect()
    self:save()
end

function MFHud:clampRect()
    local c = self.cfg
    c.scale = clamp(c.scale, MIN_SCALE, MAX_SCALE)
    c.w, c.h = BASE_W * c.scale, BASE_H * c.scale
    c.x, c.y = clamp(c.x, 0, 1 - c.w), clamp(c.y, 0, 1 - c.h)
end

-- ===================== CATEGORIES (per player, per savegame) =====================
function MFHud:setCatOverride(fillName, catId)
    if fillName == nil then return end
    self.catOverrides[fillName] = catId
    self:save()
end

function MFHud:addCustomCat(name)
    if #self.customCats >= self.maxCustomCats then return nil end
    local used = {}
    for _, c in ipairs(self.customCats) do used[c.id] = true end
    local id
    for n = 1, self.maxCustomCats + 3 do
        if not used["custom" .. n] then id = "custom" .. n break end
    end
    table.insert(self.customCats, {id = id, name = name})
    self:save()
    return id
end

function MFHud:renameCustomCat(id, name)
    for _, c in ipairs(self.customCats) do
        if c.id == id then c.name = name end
    end
    self:save()
end

function MFHud:deleteCustomCat(id)
    for i, c in ipairs(self.customCats) do
        if c.id == id then table.remove(self.customCats, i) break end
    end
    for n, c in pairs(self.catOverrides) do
        if c == id then self.catOverrides[n] = nil end
    end
    self:save()
end

function MFHud:resetCategories()
    self.customCats, self.catOverrides = {}, {}
    self:save()
end

-- ===================== ALERTS =====================
-- one alert per item: returns the alert and its position in the list
function MFHud:getAlert(idx)
    local n = idx ~= nil and self:nameOf(idx) or nil
    if n == nil then return nil end
    for i, a in ipairs(self.alerts) do
        if a.name == n then return a, i end
    end
    return nil
end

-- create or update the alert of an item. Returns ok, conditionAlreadyMet
-- What alerts watch: the best station price for the item, as a percentage vs. the Price Median, and that price.
-- Falls back to the market price when no station accepts the item. Cached for a second.
function MFHud:getAlertNow(idx)
    local st = DM.fills[idx]
    if st == nil then return 0, 0 end
    self.nowCache = self.nowCache or {}
    local c = self.nowCache[idx]
    if c ~= nil and g_time - c.t < 1000 then return c.pct, c.price end
    local median = DM:getBasePricePer1000(idx)
    local best = DM:getBestStationPrice(idx)
    local pct, price
    if best ~= nil and median > 0 then
        pct, price = (best / median - 1) * 100, best
    else
        pct, price = (st.mult - 1) * 100, median * st.mult
    end
    self.nowCache[idx] = {t = g_time, pct = pct, price = price}
    return pct, price
end

function MFHud:setAlert(idx, dir, pct)
    local n = self:nameOf(idx)
    if n == nil then return false end
    local a = self:getAlert(idx)
    if a == nil then
        if #self.alerts >= self.maxAlerts then return false end
        a = {name = n}
        table.insert(self.alerts, a)
    end
    a.dir, a.pct = dir, pct
    local now = self:getAlertNow(idx)
    local cond = (dir > 0 and now >= pct) or (dir < 0 and now <= pct)
    a.fired = cond   -- only fires when the price crosses the line
    a.dismissed = cond   -- already met when set: no banner, no sound
    self:save()
    return true, cond
end

-- triggered alerts that are still shown on the HUD
function MFHud:getActiveAlerts()
    local list = {}
    for i, a in ipairs(self.alerts) do
        if a.fired and not a.dismissed then table.insert(list, i) end
    end
    return list
end

function MFHud:dismissAlert(i)
    local a = self.alerts[i]
    if a ~= nil then a.dismissed = true end
end

function MFHud:dismissAll()
    for _, a in ipairs(self.alerts) do if a.fired then a.dismissed = true end end
end

-- short sound for a new alert; the sample names are tried in order, whatever exists is used
function MFHud:playAlertSound()
    if self.cfg.alertSound == false then return end
    local sp = g_gui ~= nil and g_gui.soundPlayer or nil
    local S = GuiSoundPlayer ~= nil and GuiSoundPlayer.SOUND_SAMPLES or nil
    if sp == nil or sp.playSample == nil or S == nil then return end
    for _, n in ipairs({"NOTIFICATION", "MESSAGE", "CONFIRM", "CLICK"}) do
        if S[n] ~= nil then sp:playSample(S[n]) return end
    end
end

function MFHud:removeAlertFor(idx)
    local _, i = self:getAlert(idx)
    if i ~= nil then self:removeAlert(i) end
end

function MFHud:removeAlert(i)
    table.remove(self.alerts, i)
    self:save()
end

function MFHud:checkAlerts()
    for _, a in ipairs(self.alerts) do
        local idx = g_fillTypeManager:getFillTypeIndexByName(a.name)
        local st = idx ~= nil and DM.fills[idx] or nil
        if st ~= nil then
            local now, nowPrice = self:getAlertNow(idx)
            local cond = (a.dir > 0 and now >= a.pct) or (a.dir < 0 and now <= a.pct)
            if cond and not a.fired then
                a.fired = true
                a.dismissed = false
                self:playAlertSound()
                local ft = g_fillTypeManager:getFillTypeByIndex(idx)
                local msg = string.format(DM.t(a.dir > 0 and "mf_alert_up" or "mf_alert_down"),
                    ft and ft.title or a.name, now, money(nowPrice))
                g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, msg)
                -- Fast Forward Control (optional mod): stops a running fast-forward and restores the
                -- previous game speed when its "Stop on Markets and Futures alerts" box is ticked
                local ffc = g_currentMission.fastForwardControl
                if ffc ~= nil then
                    ffc:onExternalAlert("Markets and Futures", msg)
                end
            elseif not cond then
                a.fired = false
                a.dismissed = false
            end
        end
    end
end

-- ===================== HUD GEOMETRY / MOUSE =====================
-- true while the menu has stepped aside so the HUD can be moved
function MFHud:isEditing()
    return MFMenu ~= nil and MFMenu.isOpen == true and MFMenu.suspended == true
end

function MFHud:hasContent()
    return DM.fills ~= nil and (self.cfg.visible or self:isEditing()) and (#self:getItems() > 0 or (MFMenu ~= nil and MFMenu.isOpen) or #self:getActiveAlerts() > 0)
end

local HANDLE_W, HANDLE_H = 0.011, 0.016

function MFHud:overHandle(px, py)
    local c = self.cfg
    return px >= c.x + c.w - HANDLE_W and px <= c.x + c.w and py >= c.y and py <= c.y + HANDLE_H
end

function MFHud:isOver(px, py)
    if MFMenu == nil or not MFMenu.isOpen or not self:hasContent() then return false end
    -- the HUD is hidden while the menu is showing; it can only be grabbed in move mode
    if not MFMenu.suspended then return false end
    local c = self.cfg
    return px >= c.x and px <= c.x + c.w and py >= c.y and py <= c.y + c.h
end

function MFHud:mouseEvent(posX, posY, isDown, isUp, button)
    if MFMenu == nil or not MFMenu.isOpen or not self:hasContent() then
        if self.drag ~= nil then self.drag = nil; self:save(); if MFMenu ~= nil then MFMenu:onHudDragEnd() end end
        return
    end
    local c = self.cfg
    if self.drag ~= nil then
        if isUp and button == Input.MOUSE_BUTTON_LEFT then
            self.drag = nil
            self:clampRect()
            self:save()
            MFMenu:onHudDragEnd()
            return
        end
        if self.drag.mode == "move" then
            c.x = posX - self.drag.ox
            c.y = posY - self.drag.oy
        else
            local top = self.drag.top
            local sx = (posX - c.x) / BASE_W
            local sy = (top - posY) / BASE_H
            c.scale = clamp((sx + sy) / 2, MIN_SCALE, MAX_SCALE)
            c.w, c.h = BASE_W * c.scale, BASE_H * c.scale
            c.y = top - c.h
        end
        self:clampRect()
        return
    end
    if isDown and button == Input.MOUSE_BUTTON_LEFT and self:isOver(posX, posY) then
        if self:overHandle(posX, posY) then
            self.drag = {mode = "resize", top = c.y + c.h}
        else
            self.drag = {mode = "move", ox = posX - c.x, oy = posY - c.y}
        end
        MFMenu:onHudDragStart()
    end
end

-- ===================== UPDATE =====================
function MFHud:update(dt)
    if DM.fills == nil or g_currentMission == nil then return end
    if not self.loaded or self.saveKey ~= self:getSaveKey() then self:load() end

    -- alerts (about once a second)
    self.alertTimer = self.alertTimer + dt
    if self.alertTimer > 1000 then
        self.alertTimer = 0
        if self.firstAlertCheck then
            -- alerts loaded from the file only fire on a crossing after start-up
            self.firstAlertCheck = false
            for _, a in ipairs(self.alerts) do
                local idx = g_fillTypeManager:getFillTypeIndexByName(a.name)
                local st = idx ~= nil and DM.fills[idx] or nil
                if st ~= nil then
                    local now = self:getAlertNow(idx)
                    a.fired = (a.dir > 0 and now >= a.pct) or (a.dir < 0 and now <= a.pct)
                    a.dismissed = a.fired
                end
            end
        else
            self:checkAlerts()
        end
    end

    -- rotate through the HUD items
    local items = self:getItems()
    if #items > 0 then
        self.timer = self.timer + dt
        if self.timer >= self.cfg.rotate * 1000 then
            self.timer = 0
            self.index = self.index % #items + 1
        end
        if self.index > #items then self.index = 1 end
        -- station prices are normally refreshed by the menu; keep them fresh for the HUD too
        if not (MFMenu ~= nil and MFMenu.isOpen and not MFMenu.suspended) then
            self.statsTimer = self.statsTimer + dt
            if self.statsTimer > 2000 then
                self.statsTimer = 0
                DM:refreshStationStats()
            end
        end
    end
end

-- ===================== DRAW =====================
local function fit(size, s, maxW)
    local tw = getTextWidth(size, s)
    if tw > maxW and tw > 0 then return size * maxW / tw end
    return size
end

-- logs (once per change) when the HUD is shown or why it is not, to help diagnose problems in log.txt
function MFHud:logVisibility(reason)
    if not self.cfg.visible or #self:getItems() == 0 then return end
    local state = reason or "visible"
    if state ~= self.lastState then
        self.lastState = state
        local msg = reason and ("[MarketsAndFutures] HUD hidden because " .. reason) or "[MarketsAndFutures] HUD is being drawn"
        Logging.info(msg)
    end
end

function MFHud:draw()
    if DM.fills == nil or g_currentMission == nil or not self.loaded then return end
    local menuOpen = MFMenu ~= nil and MFMenu.isOpen
    local editing = self:isEditing()
    if menuOpen and not editing then return end   -- hidden while the menu is showing
    local reason
    if not editing then
        if g_gui:getIsGuiVisible() then
            reason = "a game menu is open"
        else
            local hidden = false
            local hud = g_currentMission.hud
            if hud ~= nil and hud.getIsVisible ~= nil and not hud:getIsVisible() then hidden = true end
            if hidden or g_noHudModeEnabled == true then reason = "the game HUD is hidden" end
        end
    end
    self:logVisibility(reason)
    if reason ~= nil then return end
    if not self:hasContent() then return end
    self:drawPanel(editing)
end

function MFHud:drawPanel(editing)
    local P = TH()
    local R = MFTheme.rect
    local c = self.cfg
    local x, y, w, h = c.x, c.y, c.w, c.h
    local pad = w * 0.045
    local items = self:getItems()
    local hb = c.scale * UPPER_H          -- text part
    local y0 = y + h - hb                 -- bottom of the text part
    local rad = hb * 0.10

    local RR = MFTheme.rrect
    if P.flat then
        -- like the game's own HUD: one flat, translucent dark panel
        RR(x, y, w, h, P.bg, c.alpha * 0.8, rad)
    else
        -- shadow, frame, body, header band
        RR(x + w * 0.02, y - h * 0.03, w, h, {0, 0, 0}, 0.4 * c.alpha, rad)
        RR(x - 0.0008, y - 0.0012, w + 0.0016, h + 0.0024, P.accent, c.alpha, rad + 0.001)
        RR(x, y, w, h, P.bg, c.alpha, rad)
        RR(x, y, w, y0 - y, {0, 0, 0}, 0.22 * c.alpha, rad, false, true)       -- darker graph area
        RR(x, y0 + hb * 0.735, w, hb * 0.265, P.band, math.min(1, c.alpha + 0.1), rad, true, false)
        R(x, y0 + hb * 0.730, w, hb * 0.008, P.accent, 0.8)
    end
    if editing then
        -- outline + resize handle while the HUD is being moved / resized with the mouse
        local o = 0.0012
        R(x, y, w, o, P.hi, 0.9)
        R(x, y + h - o, w, o, P.hi, 0.9)
        R(x, y, o, h, P.hi, 0.9)
        R(x + w - o, y, o, h, P.hi, 0.9)
        R(x + w - HANDLE_W, y, HANDLE_W, HANDLE_H, P.hi, 0.95)
        txt(x + w - HANDLE_W - 0.004, y + 0.004, 0.0115, string.format("%d%%", math.floor(c.scale * 100 + 0.5)), P.hi, nil, nil, RenderText.ALIGN_RIGHT, true)

        -- hint with the countdown until the menu comes back
        local secs = 0
        if MFMenu ~= nil and not MFMenu.hudDragging then secs = math.max(1, math.ceil((MFMenu.resumeTimer or 0) / 1000)) end
        local hint = DM.t("mf_hud_move_hint")
        if MFMenu ~= nil and not MFMenu.hudDragging then hint = hint .. "  " .. string.format(DM.t("mf_hud_move_back"), secs) end
        local hy = y + h + 0.008
        if hy > 0.96 then hy = y - 0.022 end
        txt(x, hy, 0.0135, hint, P.hi, nil, nil, RenderText.ALIGN_LEFT, true)
    end

    local graphY, graphH = y, y0 - y      -- graph zone below the text part
    y, h = y0, hb                         -- the rest of the layout works in the text part

    if #items == 0 then
        if not editing then self:drawAlertOverlay(P, x, graphY, w, graphH, pad, c) end
        txt(x + w / 2, y + h / 2 - h * 0.05, fit(h * 0.13, DM.t("mf_hud_empty"), w - 2 * pad), DM.t("mf_hud_empty"), 0.8, 0.8, 0.8, RenderText.ALIGN_CENTER)
        setTextBold(false); setTextAlignment(RenderText.ALIGN_LEFT); setTextColor(1, 1, 1, 1)
        return
    end

    local idx = items[clamp(self.index, 1, #items)]
    local st = DM.fills[idx]
    local ft = g_fillTypeManager:getFillTypeByIndex(idx)
    local stats = DM.stationStats[idx]
    local base = DM:getBasePricePer1000(idx)
    local best = stats and stats.best or nil
    local rate = (st.offset or 0) * 100

    -- title row
    local titleSize = h * 0.165
    local title = ft and ft.title or "?"
    local counter = #items > 1 and string.format("%d/%d", clamp(self.index, 1, #items), #items) or ""
    local counterW = counter ~= "" and getTextWidth(h * 0.10, counter) + pad or 0
    local ty = y + h - pad - titleSize * 0.95
    local iw = MFTheme:drawIcon(idx, x + pad, ty - titleSize * 0.12, titleSize * 1.15)
    local tx = x + pad + iw + pad * 0.5
    txt(tx, ty, fit(titleSize, title, w - pad - counterW - (tx - x)), title, P.hi, nil, nil, RenderText.ALIGN_LEFT, true)
    if counter ~= "" then txt(x + w - pad, ty + h * 0.012, h * 0.10, counter, 0.7, 0.7, 0.7, RenderText.ALIGN_RIGHT) end

    -- value rows
    local ls = h * 0.125
    local rowH = h * 0.205
    local ry = ty - rowH * 1.05
    for i = 0, 1 do
        drawFilledRect(x + pad, ry - rowH * i - h * 0.035, w - 2 * pad, math.max(0.0006, h * 0.006), 1, 1, 1, 0.10)
    end
    txt(x + pad, ry, ls, DM.t("mf_hud_avg"), 0.75, 0.75, 0.75)
    txt(x + w - pad, ry, ls, money(base), 1, 1, 1, RenderText.ALIGN_RIGHT, true)

    ry = ry - rowH
    txt(x + pad, ry, ls, DM.t("mf_hud_best"), 0.75, 0.75, 0.75)
    if best ~= nil then
        local br, bg, bb = 1, 0.9, 0.35
        txt(x + w - pad, ry, ls, money(best), br, bg, bb, RenderText.ALIGN_RIGHT, true)
    else
        txt(x + w - pad, ry, ls, "-", 0.7, 0.7, 0.7, RenderText.ALIGN_RIGHT)
    end

    ry = ry - rowH
    local rr, rg, rb = 1, 1, 1
    if rate > 0.05 then rr, rg, rb = 0.45, 1, 0.5 elseif rate < -0.05 then rr, rg, rb = 1, 0.45, 0.4 end
    txt(x + pad, ry, ls, DM.t("mf_hud_contract"), 0.75, 0.75, 0.75)
    txt(x + w - pad, ry, ls, string.format("%+.1f%%", rate), rr, rg, rb, RenderText.ALIGN_RIGHT, true)

    txt(x + pad, y + h * 0.04, h * 0.085, DM.t("mf_hud_unit"), 0.5, 0.5, 0.5)
    -- accent bar on the left edge follows the contract rate
    local ar, ag, ab = P.accent[1], P.accent[2], P.accent[3]
    if rate > 0.05 then ar, ag, ab = 0.35, 0.85, 0.40 elseif rate < -0.05 then ar, ag, ab = 0.90, 0.35, 0.30 end
    drawFilledRect(x, y + h * 0.04, math.max(0.0012, w * 0.012), h * 0.69, ar, ag, ab, 1)
    -- rotation dots
    if #items > 1 and #items <= 12 then
        local dotW = w * 0.022
        local total = #items * dotW * 2 - dotW
        local dx0 = x + w - pad - total
        for i = 1, #items do
            local on = i == clamp(self.index, 1, #items)
            drawFilledRect(dx0 + (i - 1) * dotW * 2, y + h * 0.045, dotW, dotW * 1.6, on and P.hi[1] or 0.6, on and P.hi[2] or 0.6, on and P.hi[3] or 0.6, on and 1 or 0.5)
        end
    end

    if graphH > 0.012 * c.scale then self:drawGraph(P, x + pad, graphY + graphH * 0.14, w - 2 * pad, graphH * 0.74, idx, st) end
    if not editing then self:drawAlertOverlay(P, x, graphY, w, graphH, pad, c) end

    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- pulsing banner over the graph zone for every triggered alert, until it is cleared or no longer true
function MFHud:drawAlertOverlay(P, x, gy, w, gh, pad, c)
    local act = self:getActiveAlerts()
    if #act == 0 or gh < 0.012 * c.scale then return end
    local pulse = 0.5 + 0.5 * math.sin((g_time or 0) / 260)
    local gx, gw = x + pad * 0.6, w - pad * 1.2
    local by, bh = gy + gh * 0.06, gh * 0.88
    MFTheme.rrect(gx - 0.0008, by - 0.0012, gw + 0.0016, bh + 0.0024, {1, 0.75, 0.15}, 0.35 + 0.65 * pulse, bh * 0.10)
    MFTheme.rrect(gx, by, gw, bh, {0.16, 0.11, 0.02}, 0.94, bh * 0.10)
    MFTheme.rrect(gx, by, gw, bh, {1, 0.65, 0.10}, 0.10 + 0.22 * pulse, bh * 0.10)

    local lines = math.min(#act, 3)
    local more = #act > 3
    if more then lines = 2 end
    local lh = bh / (lines + 1.15 + (more and 1 or 0))
    local ty = by + bh - lh * 0.95
    local ts = lh * 0.78
    local title = DM.t("mf_hud_alert_title")
    txt(gx + gw / 2, ty, fit(ts, title, gw - pad), title, 1, 0.82 + 0.18 * pulse, 0.25, RenderText.ALIGN_CENTER, true)
    local ry = ty
    for n = 1, lines do
        ry = ry - lh
        local a = self.alerts[act[n]]
        local idx = g_fillTypeManager:getFillTypeIndexByName(a.name)
        local ft = idx ~= nil and g_fillTypeManager:getFillTypeByIndex(idx) or nil
        local pct, price = 0, 0
        if idx ~= nil and DM.fills[idx] ~= nil then pct, price = self:getAlertNow(idx) end
        local right = string.format("%+.1f%%  %s", pct, money(price))
        local rs = lh * 0.70
        local rw = getTextWidth(rs, right)
        local ns = fit(rs, ft and ft.title or a.name, gw - pad * 2 - rw)
        txt(gx + pad * 0.6, ry, ns, ft and ft.title or a.name, 1, 1, 1)
        txt(gx + gw - pad * 0.6, ry, rs, right, a.dir > 0 and 0.5 or 1, a.dir > 0 and 1 or 0.55, a.dir > 0 and 0.5 or 0.4, RenderText.ALIGN_RIGHT, true)
    end
    if more then
        local m = string.format(DM.t("mf_hud_alert_more"), #act - lines)
        txt(gx + gw / 2, ry - lh, lh * 0.65, m, 0.85, 0.85, 0.85, RenderText.ALIGN_CENTER)
    end
    setTextBold(false); setTextAlignment(RenderText.ALIGN_LEFT); setTextColor(1, 1, 1, 1)
end

-- small year price curve (January first), average line and the live price
function MFHud:drawGraph(P, gx, gy, gw, gh, idx, st)
    if st == nil or st.hist == nil or st.gist == nil or MFMenu == nil or MFMenu.slotPeriod == nil then return end
    local base = DM:getBasePricePer1000(idx)
    local nowPeriod = DM:getCurrentPeriod()
    local live = st.hist[nowPeriod]
    local showGame = self.cfg.showGameLine == true
    local vals, gvals, nowSlot = {}, {}, 1
    local vmin, vmax = math.min(base, live), math.max(base, live)
    for j = 1, 12 do
        local p = MFMenu.slotPeriod(j)
        vals[j], gvals[j] = st.hist[p], st.gist[p]
        vmin, vmax = math.min(vmin, vals[j]), math.max(vmax, vals[j])
        if showGame then vmin, vmax = math.min(vmin, gvals[j]), math.max(vmax, gvals[j]) end
        if p == nowPeriod then nowSlot = j end
    end
    local padV = math.max((vmax - vmin) * 0.15, base * 0.02)
    vmin, vmax = vmin - padV, vmax + padV
    MFTheme.rrect(gx, gy, gw, gh, P.box, 0.55, gh * 0.12)
    local ix, iy, iw, ih = gx + gw * 0.04, gy + gh * 0.14, gw * 0.92, gh * 0.72
    local function px(j) return ix + (j - 1) / 11 * iw end
    local function py(v) return iy + (v - vmin) / (vmax - vmin) * ih end

    drawFilledRect(ix, py(base) - 0.0003, iw, 0.0006, 1, 1, 1, 0.35)       -- median line
    local dw = math.max(0.0012, gw * 0.011)
    local dh = dw * (MFTheme.aspect() > 0 and 1 / MFTheme.aspect() or 1.78)
    local function curve(v, r, g, b, k, steps)
        local w, h = dw * k, dh * k
        for j = 1, 11 do
            for s = 0, steps - 1 do
                local f = s / steps
                local vx = px(j) + (px(j + 1) - px(j)) * f
                local vy = py(v[j] + (v[j + 1] - v[j]) * f)
                local past = j < nowSlot
                drawFilledRect(vx - w / 2, vy - h / 2, w, h, r, g, b, past and 1 or 0.45)
            end
        end
    end
    if showGame then curve(gvals, 0.40, 0.78, 1, 0.8, 18) end
    curve(vals, P.fill[1], P.fill[2], P.fill[3], 1.0, 6)
    local mw, mh = dw * 2.2, dh * 2.2
    drawFilledRect(px(nowSlot) - mw / 2, py(live) - mh / 2, mw, mh, P.hi[1], P.hi[2], P.hi[3], 1)
end

addModEventListener(MFHud)
