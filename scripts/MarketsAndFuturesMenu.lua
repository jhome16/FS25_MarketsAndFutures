-- Market / contract menu (Left Ctrl + M). Fully mouse- and keyboard-operable.
-- Tabs: Market | My Contracts | All Events

MFMenu = {
    isOpen = false, suspended = false, hudDragging = false, resumeTimer = 0, tab = 1,
    hScroll = 0, alScroll = 0, bScroll = 0, alertItem = nil, alertDir = 1, alertPct = 10,
    sel = 1, scroll = 0, rows = 30,
    stored = {}, dragging = false, sb = nil,
    cSel = 1, confirmId = nil, confirmTime = 0, freeConfirmId = nil, freeConfirmTime = 0,
    eScroll = 0, evFilter = "all",
    amount = 10000, months = 6,
    items = {}, allItems = {},
    category = 1,
    sortKey = "name", sortAsc = true,
    resortTimer = 0, statsTimer = 0,
    msg = nil, msgTimer = 0,
    contextPushed = false,
    mx = 0, my = 0,
    hits = {},
    fast = false, menuActionIds = {}, swallowIds = {}, rep = {}, boundCache = {}, helpCache = {},
    lastToggle = -10000, pendingToggle = false, pendingClose = false, bindTimer = 0,
    onfootRegistered = false, vehicleRegistered = false,
}

local DM = MarketsAndFutures
local ROW_H = 0.0215
local LIST_W = 0.55
local PX, PY, PW, PH = 0.03, 0.06, 0.94, 0.88

local function txt(x, y, size, s, r, g, b, align, bold)
    setTextBold(bold == true)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    if type(r) == "table" then r, g, b = r[1], r[2], r[3] end
    setTextColor(r or 1, g or 1, b or 1, 1)
    renderText(x, y, size, s)
end

local function TH() return MFTheme:get("menu") end
local function fitSize(size, s, maxW)
    local tw = getTextWidth(size, s)
    if tw > maxW and tw > 0 then return size * maxW / tw end
    return size
end
local function money(v) return g_i18n:formatMoney(v, 0, true, true) end
local function pctColor(p)
    if p >= 3 then return 0.45, 1, 0.5 elseif p <= -3 then return 1, 0.45, 0.4 end
    return 1, 1, 1
end

function MFMenu:setMsg(s) self.msg, self.msgTimer = s, 3500 end

-- ===================== CATEGORIES =====================
-- 1 = All, 2..7 = listed categories, 8 = everything not listed.
local CATEGORIES = {
    {key = "mf_cat_all"},
    {key = "mf_cat_stored"},
    {key = "mf_cat_stored_all"},
    {key = "mf_cat_grain",
     names = {"WHEAT", "BARLEY", "OAT", "OATS", "CANOLA", "MAIZE", "CORN", "SUNFLOWER", "SOYBEAN", "SORGHUM"},
     titles = {"wheat", "barley", "oat", "oats", "canola", "corn", "maize", "sunflower", "sunflowers", "soybean", "soybeans", "sorghum"}},
    {key = "mf_cat_veg",
     names = {"CARROT", "PARSNIP", "BEETROOT", "REDBEET", "SPINACH", "PEA", "GREENBEAN", "ONION"},
     titles = {"carrot", "carrots", "parsnip", "parsnips", "red beet", "red beets", "beetroot", "spinach", "pea", "peas", "green bean", "green beans", "onion", "onions"}},
    {key = "mf_cat_root",
     names = {"POTATO", "SUGARBEET"},
     titles = {"potato", "potatoes", "sugar beet", "sugar beets"}},
    {key = "mf_cat_special",
     names = {"RICE", "WETRICE", "RICELONGGRAIN", "LONGGRAINRICE", "SUGARCANE", "COTTON"},
     titles = {"rice", "wet rice", "long grain rice", "sugarcane", "sugar cane", "cotton"}},
    {key = "mf_cat_orchard",
     names = {"GRAPE", "OLIVE", "COFFEE", "COFFEECHERRY", "COFFEECHERRIES", "BANANA"},
     titles = {"grape", "grapes", "olive", "olives", "coffee", "coffee cherry", "coffee cherries", "banana", "bananas"}},
    {key = "mf_cat_grass",
     names = {"GRASS", "POPLAR", "OILSEEDRADISH",
              "STRAW", "DRYGRASSWINDROW", "SILAGE", "FORAGE", "MANURE", "LIQUIDMANURE", "DIGESTATE",
              "DRYALFALFAWINDROW", "DRYCLOVERWINDROW", "ALFALFAWINDROW", "CLOVERWINDROW"},
     titles = {"grass", "poplar", "oilseed radish", "straw", "silage", "forage", "manure", "slurry",
               "liquid manure", "digestate"}},
    {key = "mf_cat_other"},
}
local OTHER_CAT = #CATEGORIES
local STORED_CAT = 2
local STORED_ALL_CAT = 3   -- complete list of stored items, with the trash column to hide items from Stored Items
local NAME_TO_CAT, TITLE_TO_CAT = {}, {}
for ci, cat in ipairs(CATEGORIES) do
    for _, n in ipairs(cat.names or {}) do NAME_TO_CAT[n] = ci end
    for _, t in ipairs(cat.titles or {}) do TITLE_TO_CAT[t] = ci end
end

local function categoryOf(ft)
    local n = string.upper(ft.name or ""):gsub("[%s_%-]", "")
    if NAME_TO_CAT[n] then return NAME_TO_CAT[n] end
    local t = string.lower(ft.title or "")
    if TITLE_TO_CAT[t] then return TITLE_TO_CAT[t] end
    return OTHER_CAT
end

-- the player's own overrides / categories (saved per savegame in MFHud) take priority over the built-in lists
local KEY_TO_CAT = {}
for ci = 4, OTHER_CAT do KEY_TO_CAT[CATEGORIES[ci].key] = ci end
local MAX_CUSTOM = 3

function MFMenu:resolveCat(ft)
    local ov = MFHud ~= nil and MFHud.catOverrides ~= nil and MFHud.catOverrides[ft.name] or nil
    if ov ~= nil then
        if KEY_TO_CAT[ov] then return KEY_TO_CAT[ov] end
        for n, c in ipairs(MFHud.customCats or {}) do
            if c.id == ov then return OTHER_CAT + n end
        end
    end
    return categoryOf(ft)
end

function MFMenu:catLabel(ci)
    if ci > OTHER_CAT then
        local c = MFHud ~= nil and MFHud.customCats ~= nil and MFHud.customCats[ci - OTHER_CAT] or nil
        return c ~= nil and c.name or "?"
    end
    return DM.t(CATEGORIES[ci].key)
end

-- after a category change: recompute every item's category and the counts, keep the selected item if still listed
function MFMenu:recomputeCats()
    self.catCounts = {}
    for _, it in ipairs(self.allItems or {}) do
        local ft = g_fillTypeManager:getFillTypeByIndex(it.idx)
        if ft ~= nil then
            it.cat = self:resolveCat(ft)
            self.catCounts[it.cat] = (self.catCounts[it.cat] or 0) + 1
        end
    end
    self.catCounts[1] = #(self.allItems or {})
    local nCustom = MFHud ~= nil and MFHud.customCats ~= nil and #MFHud.customCats or 0
    if self.category > OTHER_CAT + nCustom then self.category = 1 end
    self:applyFilter()
end

local function drawArrow(cx, cy, up)
    local hgt = 0.0016
    for i = 0, 2 do
        local wdt = up and (0.0105 - i * 0.0035) or (0.0035 + i * 0.0035)
        drawFilledRect(cx - wdt / 2, cy + i * hgt, wdt, hgt, 1, 1, 1, 1)
    end
end

-- small trash can symbol for the "hide from Stored Items" column header
local function drawTrashIcon(cx, y, r, g, b)
    local aspect = g_screenAspectRatio or 1.78
    local u = 0.0016
    local function px(n) return n * u / aspect end
    drawFilledRect(cx - px(2.3), y, px(4.6), u * 4.4, r, g, b, 1)                 -- bin
    drawFilledRect(cx - px(0.9), y + u * 0.7, px(0.5), u * 3.0, 0.05, 0.07, 0.06, 1)   -- grooves
    drawFilledRect(cx + px(0.4), y + u * 0.7, px(0.5), u * 3.0, 0.05, 0.07, 0.06, 1)
    drawFilledRect(cx - px(3.2), y + u * 4.8, px(6.4), u * 0.9, r, g, b, 1)       -- lid
    drawFilledRect(cx - px(1.1), y + u * 5.7, px(2.2), u * 0.9, r, g, b, 1)       -- handle
end

-- ===================== ITEMS / SORTING / FILTER =====================
-- Liters of each item stored in the local farm's storages (silos, etc.)
function MFMenu:refreshStored()
    local stored = {}
    local farmId = g_currentMission:getFarmId()

    local function add(idx, lvl)
        if idx ~= nil and type(lvl) == "number" and lvl > 0.5 then stored[idx] = (stored[idx] or 0) + lvl end
    end
    local function ownerOf(obj)
        local o = obj.ownerFarmId
        if o == nil and obj.getOwnerFarmId ~= nil then o = obj:getOwnerFarmId() end
        if o == nil and obj.owningPlaceable ~= nil and obj.owningPlaceable.getOwnerFarmId ~= nil then
            o = obj.owningPlaceable:getOwnerFarmId()
        end
        return o
    end
    -- every storage object is counted once, even if it can be reached from several lists
    local seen = {}
    local function addStorage(storage)
        if storage == nil or seen[storage] then return end
        seen[storage] = true
        local levels = storage.fillLevels
        if levels == nil and storage.getFillLevels ~= nil then levels = storage:getFillLevels() end
        for idx, lvl in pairs(levels or {}) do add(idx, lvl) end
    end

    -- 1) silos, sheds and other storages
    pcall(function()
        local ss = g_currentMission.storageSystem
        local list = (ss.getStorages ~= nil and ss:getStorages()) or ss.storages or {}
        for _, storage in pairs(list) do
            if ownerOf(storage) == farmId then addStorage(storage) end
        end
    end)

    -- 2) production chains: inputs and outputs
    pcall(function()
        local pcm = g_currentMission.productionChainManager
        local points = pcm.productionPoints or (pcm.getProductionPoints ~= nil and pcm:getProductionPoints()) or {}
        for _, pp in pairs(points) do
            if ownerOf(pp) == farmId then addStorage(pp.storage) end
        end
    end)

    -- 3) vehicles, trailers and pallets (everything with fill units)
    pcall(function()
        local vs = g_currentMission.vehicleSystem
        local list = (vs ~= nil and vs.vehicles) or g_currentMission.vehicles or {}
        for _, v in pairs(list) do
            pcall(function()
                if not seen[v] and v.spec_fillUnit ~= nil and ownerOf(v) == farmId then
                    seen[v] = true
                    for _, unit in ipairs(v.spec_fillUnit.fillUnits or {}) do add(unit.fillType, unit.fillLevel) end
                end
            end)
        end
    end)

    -- 4) bales
    local function addBale(entry)
        pcall(function()
            local item = entry.item or entry
            if type(item) == "table" and not seen[item] and item.getFillType ~= nil and item.getFillLevel ~= nil and ownerOf(item) == farmId then
                seen[item] = true
                add(item:getFillType(), item:getFillLevel())
            end
        end)
    end
    pcall(function()
        local its = g_currentMission.itemSystem
        for _, entry in pairs(its ~= nil and its.itemsToSave or {}) do addBale(entry) end
    end)
    pcall(function()
        local bs = g_currentMission.baleSystem
        for _, entry in pairs(bs ~= nil and bs.bales or {}) do addBale(entry) end
    end)

    self.stored = stored
    local nShown, nAll = 0, 0
    for _, it in ipairs(self.allItems) do
        if (stored[it.idx] or 0) > 0 then
            nAll = nAll + 1
            if not (MFHud ~= nil and MFHud:isStoredHidden(it.idx)) then nShown = nShown + 1 end
        end
    end
    self.catCounts = self.catCounts or {}
    self.catCounts[STORED_CAT] = nShown
    self.catCounts[STORED_ALL_CAT] = nAll
end

function MFMenu:applyFilter(keepIdx)
    keepIdx = keepIdx or (self.items[self.sel] and self.items[self.sel].idx)
    self.items = {}
    local stored = self.stored or {}
    for _, it in ipairs(self.allItems) do
        local show
        if self.category == 1 then show = true
        elseif self.category == STORED_CAT then show = (stored[it.idx] or 0) > 0 and not (MFHud ~= nil and MFHud:isStoredHidden(it.idx))
        elseif self.category == STORED_ALL_CAT then show = (stored[it.idx] or 0) > 0
        else show = it.cat == self.category end
        if show then table.insert(self.items, it) end
    end
    self.sel = 1
    if keepIdx ~= nil then
        for i, it in ipairs(self.items) do
            if it.idx == keepIdx then self.sel = i break end
        end
    end
    self:clampScroll()
end

-- locked contract price (for the amount/duration in the form) compared to the best station price, as a fraction
function MFMenu:contractVsBest(idx)
    local stats = DM.stationStats[idx]
    if stats == nil or stats.best == nil or stats.best <= 0 then return nil end
    local pv = DM:getContractPreview(idx, self.amount, math.min(self.months, math.floor(DM.CFG.maxMonths)))
    if pv == nil or not pv.hasStation then return nil end
    return pv.locked / stats.best - 1, pv
end

function MFMenu:sortItems()
    local selIdx = self.items[self.sel] and self.items[self.sel].idx
    for _, it in ipairs(self.allItems) do
        it.diff = DM:getMult(it.idx) - 1
        it.avg = DM:getBasePricePer1000(it.idx)
        local fst = DM.fills[it.idx]
        local cvb = self:contractVsBest(it.idx)
        it.rate = cvb or -9
        local stats = DM.stationStats[it.idx]
        it.stn = stats and stats.avg or -1e9
        it.best = stats and stats.best or -1e9
        it.bvm = (stats and it.avg > 0) and (stats.best / it.avg - 1) or -9
        it.hud = (MFHud ~= nil and MFHud:isChecked(it.idx)) and 1 or 0
        it.alert = (MFHud ~= nil and MFHud:getAlert(it.idx) ~= nil) and 1 or 0
    end
    local key, asc = self.sortKey, self.sortAsc
    table.sort(self.allItems, function(a, b)
        local va, vb
        if key == "diff" then va, vb = a.diff, b.diff
        elseif key == "avg" then va, vb = a.avg, b.avg
        elseif key == "rate" then va, vb = a.rate, b.rate
        elseif key == "stn" then va, vb = a.stn, b.stn
        elseif key == "best" then va, vb = a.best, b.best
        elseif key == "bvm" then va, vb = a.bvm, b.bvm
        elseif key == "hud" then va, vb = a.hud, b.hud
        elseif key == "alert" then va, vb = a.alert, b.alert end
        if va ~= nil and va ~= vb then
            if asc then return va < vb else return va > vb end
        end
        if key == "name" and a.title ~= b.title then
            if asc then return a.title < b.title else return a.title > b.title end
        end
        return a.title < b.title
    end)
    self:applyFilter(selIdx)
end

function MFMenu:setSort(key, asc)
    self.sortKey, self.sortAsc = key, asc
    self:sortItems()
    self.scroll = 0                      -- jump back to the top of the list after sorting
    if #self.items > 0 then self.sel = 1 end
    self:clampScroll()
end

-- header click: toggle direction if already active, otherwise use the default direction
function MFMenu:clickSortHeader(key, defaultAsc)
    if self.sortKey == key then self:setSort(key, not self.sortAsc)
    else self:setSort(key, defaultAsc) end
end

local SORT_CYCLE = {
    {"name", true}, {"name", false}, {"avg", false}, {"avg", true}, {"diff", false}, {"diff", true},
    {"rate", false}, {"rate", true},
    {"stn", false}, {"stn", true}, {"best", false}, {"best", true}, {"bvm", false}, {"bvm", true},
}
function MFMenu:cycleSort()
    local cur = 0
    for i, s in ipairs(SORT_CYCLE) do
        if s[1] == self.sortKey and s[2] == self.sortAsc then cur = i break end
    end
    local nxt = SORT_CYCLE[cur % #SORT_CYCLE + 1]
    self:setSort(nxt[1], nxt[2])
end

function MFMenu:setCategory(c)
    self.category = c
    self.scroll = 0
    self:applyFilter()
    self:ensureVisible()
end

function MFMenu:buildItems()
    self.allItems = {}
    self.catCounts = {}
    for idx in pairs(DM.fills) do
        local ft = g_fillTypeManager:getFillTypeByIndex(idx)
        if ft ~= nil then
            local cat = self:resolveCat(ft)
            table.insert(self.allItems, {idx = idx, title = ft.title or ft.name, diff = 0, avg = 0, cat = cat})
            self.catCounts[cat] = (self.catCounts[cat] or 0) + 1
        end
    end
    self.catCounts[1] = #self.allItems
    self.items = {}
    self.sel = 1
    self:sortItems()
end

function MFMenu:clampScroll()
    self.scroll = math.max(0, math.min(self.scroll, math.max(0, #self.items - self.rows)))
end

function MFMenu:ensureVisible()
    if self.sel <= self.scroll then self.scroll = self.sel - 1 end
    if self.sel > self.scroll + self.rows then self.scroll = self.sel - self.rows end
    self:clampScroll()
end

function MFMenu:jumpToItem(idx)
    local found = false
    for _, it in ipairs(self.items) do
        if it.idx == idx then found = true break end
    end
    if not found then self.category = 1 end
    self:applyFilter(idx)
    self.tab = 1
    self:ensureVisible()
end

-- ===================== EVENTS LIST =====================
function MFMenu:getEventRows()
    local list = {}
    for idx, st in pairs(DM.fills) do
        local ft = g_fillTypeManager:getFillTypeByIndex(idx)
        for _, e in ipairs(st.events) do
            local ok = self.evFilter == "all" or (self.evFilter == "surplus") == e.surplus
            if ok and ft ~= nil then
                table.insert(list, {idx = idx, title = ft.title or ft.name, surplus = e.surplus,
                    factor = e.factor, daysLeft = e.daysLeft, mult = st.mult, linked = e.linked})
            end
        end
    end
    table.sort(list, function(a, b)
        local da, db = math.abs(a.factor - 1), math.abs(b.factor - 1)
        if da ~= db then return da > db end
        return a.title < b.title
    end)
    return list
end

-- ===================== INPUT ACTIONS (rebindable in Settings > Controls) =====================
local MENU_COMMANDS = {
    {cmd = "up",       action = "MF_UP",        rep = true},
    {cmd = "down",     action = "MF_DOWN",      rep = true},
    {cmd = "left",     action = "MF_LEFT",      rep = true},
    {cmd = "right",    action = "MF_RIGHT",     rep = true},
    {cmd = "daysDown", action = "MF_DAYS_DOWN", rep = true},
    {cmd = "daysUp",   action = "MF_DAYS_UP",   rep = true},
    {cmd = "pageUp",   action = "MF_PAGE_UP",   rep = true},
    {cmd = "pageDown", action = "MF_PAGE_DOWN", rep = true},
    {cmd = "fast",     action = "MF_FAST",      up = true},
    {cmd = "sort",     action = "MF_SORT"},
    {cmd = "confirm",  action = "MF_CONFIRM"},
    {cmd = "tab",      action = "MF_NEXT_TAB"},
    {cmd = "cancel",   action = "MF_CANCEL"},
    {cmd = "freeCancel", action = "MF_FREE_CANCEL"},
    {cmd = "close",    action = "MF_CLOSE"},
}
local CMD_ACTION = {}
for _, c in ipairs(MENU_COMMANDS) do CMD_ACTION[c.cmd] = c.action end

-- Built-in default keys. Used as a fallback only when the game left an action unbound
-- (e.g. its default key conflicted with another binding) or could not register it.
local RAW_KEYS = {
    [Input.KEY_up] = "up", [Input.KEY_down] = "down", [Input.KEY_left] = "left", [Input.KEY_right] = "right",
    [Input.KEY_q] = "daysDown", [Input.KEY_e] = "daysUp",
    [Input.KEY_pageup] = "pageUp", [Input.KEY_pagedown] = "pageDown",
    [Input.KEY_s] = "sort", [Input.KEY_return] = "confirm", [Input.KEY_KP_enter] = "confirm",
    [Input.KEY_tab] = "tab", [Input.KEY_delete] = "cancel", [Input.KEY_backspace] = "cancel",
    [Input.KEY_f] = "freeCancel",
}
local DEFAULT_LABELS = {
    MF_TOGGLE_MENU = "Ctrl+M", MF_UP = "Up", MF_DOWN = "Down", MF_LEFT = "Left", MF_RIGHT = "Right",
    MF_DAYS_DOWN = "Q", MF_DAYS_UP = "E", MF_PAGE_UP = "PgUp", MF_PAGE_DOWN = "PgDn", MF_FAST = "Shift",
    MF_SORT = "S", MF_CONFIRM = "Enter", MF_NEXT_TAB = "Tab", MF_CANCEL = "Del", MF_FREE_CANCEL = "F", MF_CLOSE = "Esc",
}

-- returns known (bool), text (current binding as shown in the settings, "" if unbound)
function MFMenu:queryBinding(actionName)
    local ok, res = pcall(function()
        local names = g_inputBinding:getKeyNamesOfDigitalAction(InputAction[actionName])
        if type(names) == "string" then return names end
        local parts = {}
        if type(names) == "table" then
            for _, n in ipairs(names) do
                if type(n) == "string" and n ~= "" then table.insert(parts, n)
                elseif type(n) == "table" then
                    for _, m in ipairs(n) do
                        if type(m) == "string" and m ~= "" then table.insert(parts, m) end
                    end
                end
            end
        end
        return table.concat(parts, "+")
    end)
    if not ok or type(res) ~= "string" then return false, "" end
    return true, res
end

-- true when the user's current binding exists; false when it is unbound; nil = unknown
function MFMenu:rawAllowed(actionName)
    return self.boundCache[actionName] == false
end

function MFMenu:refreshHelp()
    for action in pairs(DEFAULT_LABELS) do
        local known, text = self:queryBinding(action)
        if known then self.boundCache[action] = (text ~= "") else self.boundCache[action] = nil end
    end
    local function k(action)
        local known, text = self:queryBinding(action)
        if not known or text == "" then return DEFAULT_LABELS[action] end
        return text
    end
    local t = DM.t
    self.helpCache[1] = string.format("%s   [%s/%s] %s   [%s/%s] %s   [%s/%s] %s   [%s] %s   [%s] %s   [%s] %s   [%s] %s   [%s] %s",
        t("mf_h_mouse"), k("MF_UP"), k("MF_DOWN"), t("mf_h_item"), k("MF_LEFT"), k("MF_RIGHT"), t("mf_h_amount"),
        k("MF_DAYS_DOWN"), k("MF_DAYS_UP"), t("mf_h_days"), k("MF_FAST"), t("mf_h_fast"), k("MF_SORT"), t("mf_h_sort"),
        k("MF_CONFIRM"), t("mf_h_sign"), k("MF_NEXT_TAB"), t("mf_h_tab"), k("MF_CLOSE"), t("mf_h_close"))
    self.helpCache[2] = string.format("%s   [%s/%s] %s   [%s] %s   [%s] %s   [%s] %s   [%s] %s",
        t("mf_h_mouse"), k("MF_UP"), k("MF_DOWN"), t("mf_h_select"), k("MF_CANCEL"), t("mf_h_cancel"),
        k("MF_FREE_CANCEL"), t("mf_h_free"), k("MF_NEXT_TAB"), t("mf_h_tab"), k("MF_CLOSE"), t("mf_h_close"))
    self.helpCache[3] = string.format("%s   [%s/%s] %s   [%s] %s   [%s] %s",
        t("mf_h_mouse"), k("MF_UP"), k("MF_DOWN"), t("mf_h_scroll"), k("MF_NEXT_TAB"), t("mf_h_tab"), k("MF_CLOSE"), t("mf_h_close"))
    self.helpCache[7] = self.helpCache[3]
end

function MFMenu:hasMenuActions()
    return #self.menuActionIds > 0
end

-- Menu actions are registered in whatever input context is active while the menu is open.
-- "disableConflictingBindings" keeps vehicle / player controls from reacting to the same keys.
-- name of the input context that is active right now (the game wants it passed explicitly)
function MFMenu:getInputContext()
    local ctx
    pcall(function() ctx = g_inputBinding:getContextName() end)
    if ctx == nil then ctx = g_inputBinding.currentContextName end
    return ctx
end

function MFMenu:registerMenuActions()
    self.menuActionIds = {}
    self.swallowIds = {}
    self.rep = {}
    local ctx = self:getInputContext()
    self.menuContext = ctx
    local began = false
    if ctx ~= nil then
        began = pcall(function() g_inputBinding:beginActionEventsModification(ctx) end)
    end
    pcall(function()
        for _, c in ipairs(MENU_COMMANDS) do
            local actionId = InputAction[c.action]
            if actionId ~= nil then
                local target = {cmd = c.cmd, rep = c.rep == true}
                local ok, id = g_inputBinding:registerActionEvent(actionId, target, MFMenu.onCommand,
                    c.up == true, not c.rep, c.rep == true, true, nil, true)
                if ok and id ~= nil then
                    table.insert(self.menuActionIds, id)
                    pcall(function() g_inputBinding:setActionEventTextVisibility(id, false) end)
                end
            end
        end
    end)
    -- swallow the on-foot camera look axes so the view does not turn while the menu is open
    pcall(function()
        for _, name in ipairs({"AXIS_LOOK_LEFTRIGHT_PLAYER", "AXIS_LOOK_UPDOWN_PLAYER"}) do
            local actionId = InputAction[name]
            if actionId ~= nil then
                local ok, id = g_inputBinding:registerActionEvent(actionId, MFMenu, MFMenu.onSwallow, false, false, true, true, nil, true)
                if ok and id ~= nil then
                    table.insert(self.swallowIds, id)
                    pcall(function() g_inputBinding:setActionEventTextVisibility(id, false) end)
                end
            end
        end
    end)
    if began then pcall(function() g_inputBinding:endActionEventsModification() end) end
end

function MFMenu.onSwallow() end

function MFMenu:unregisterMenuActions()
    if #self.menuActionIds == 0 and #self.swallowIds == 0 then return end
    local ctx = self.menuContext
    -- if the context changed meanwhile (e.g. a game menu opened) the game already dropped our events
    if ctx ~= nil and self:getInputContext() == ctx then
        local began = pcall(function() g_inputBinding:beginActionEventsModification(ctx) end)
        for _, id in ipairs(self.menuActionIds) do
            pcall(function() g_inputBinding:removeActionEvent(id) end)
        end
        for _, id in ipairs(self.swallowIds) do
            pcall(function() g_inputBinding:removeActionEvent(id) end)
        end
        if began then pcall(function() g_inputBinding:endActionEventsModification() end) end
    end
    self.menuActionIds = {}
    self.swallowIds = {}
    self.menuContext = nil
end

-- callback for all menu actions
function MFMenu.onCommand(target, actionName, inputValue)
    local self = MFMenu
    if not self.isOpen or target == nil then return end
    local pressed = inputValue ~= nil and inputValue > 0
    if target.cmd == "fast" then self.fast = pressed return end
    if not pressed then return end
    if target.rep then self:handleRepeat(target.cmd)
    else self:runCommand(target.cmd, false) end
end

-- hold-to-repeat for movement style actions
function MFMenu:handleRepeat(cmd)
    local st = self.rep[cmd]
    if st == nil then st = {}; self.rep[cmd] = st end
    local now = g_time
    if st.stamp == nil or now - st.stamp > 150 then
        st.t0, st.last = now, now
        self:runCommand(cmd, false)
    elseif now - st.t0 > 350 and now - st.last > 70 then
        st.last = now
        self:runCommand(cmd, false)
    end
    st.stamp = now
end

-- ---- toggle action (on foot + in vehicles) ----
function MFMenu:requestToggle()
    if g_time - self.lastToggle < 300 then return end
    self.lastToggle = g_time
    self.pendingToggle = true
end

function MFMenu.onToggleAction(target, actionName, inputValue)
    if inputValue == nil or inputValue > 0 then MFMenu:requestToggle() end
end

function MFMenu.registerOnFootActions()
    pcall(function()
        local ok, id = g_inputBinding:registerActionEvent(InputAction.MF_TOGGLE_MENU, MFMenu, MFMenu.onToggleAction, false, true, false, true)
        if ok and id ~= nil then
            MFMenu.onfootRegistered = true
            g_inputBinding:setActionEventTextVisibility(id, true)
            g_inputBinding:setActionEventText(id, DM.t("mf_action_open"))
        end
    end)
end

function MFMenu.registerVehicleActions(vehicle, isActiveForInput, isActiveForInputIgnoreSelection)
    if not vehicle.isClient or not isActiveForInputIgnoreSelection then return end
    pcall(function()
        local spec = vehicle.spec_enterable
        if spec == nil or spec.actionEvents == nil then return end
        local ok, id = vehicle:addActionEvent(spec.actionEvents, InputAction.MF_TOGGLE_MENU, MFMenu, MFMenu.onToggleAction, false, true, false, true, nil)
        if ok and id ~= nil then
            MFMenu.vehicleRegistered = true
            g_inputBinding:setActionEventTextVisibility(id, true)
            g_inputBinding:setActionEventText(id, DM.t("mf_action_open"))
        end
    end)
end

-- ===================== INPUT HELP OVERLAP FIX =====================
-- The HUD's on-screen input help draws on top of mod overlays, so it is skipped while the menu is open.
function MFMenu:hookInputHelp()
    if self.inputHelpHooked or g_currentMission == nil then return end
    local hud = g_currentMission.hud
    local ih = hud ~= nil and hud.inputHelp or nil
    if ih == nil then return end
    local orig = ih.draw
    if type(orig) ~= "function" then return end
    ih.draw = function(element, ...)
        if MFMenu.isOpen and not MFMenu.suspended then return end
        return orig(element, ...)
    end
    self.inputHelpHooked = true
end

-- ===================== OPEN / CLOSE =====================
-- hides (or restores) the base-game HUD while the menu is open
function MFMenu:setGameHudHidden(hide)
    pcall(function()
        local hud = g_currentMission ~= nil and g_currentMission.hud or nil
        if hud == nil or hud.setIsVisible == nil then return end
        if hide then
            if self.gameHudHidden then return end
            local was = true
            if hud.getIsVisible ~= nil then was = hud:getIsVisible() end
            if was then
                hud:setIsVisible(false)
                self.gameHudHidden = true
            end
        elseif self.gameHudHidden then
            hud:setIsVisible(true)
            self.gameHudHidden = false
        end
    end)
end

function MFMenu:open()
    self.stationPopup = nil
    self.catPopup = nil
    self:installLateHook()
    self:installGlobalDrawHook()
    if g_currentMission == nil or DM.fills == nil or g_gui:getIsGuiVisible() then return end
    self:buildItems()
    self:refreshStored()
    self:applyFilter()
    DM:refreshStationStats()
    self.isOpen = true
    self:installEventSkip()
    self:wrapOtherHuds()
    self:setGameHudHidden(true)
    self.openTime = g_time
    self.suspended = false
    self.hudDragging = false
    self.fast = false
    self:registerMenuActions()
    self:refreshHelp()
    pcall(function() g_inputBinding:setShowMouseCursor(true) end)
end

-- ---------- HUD move mode: the menu steps aside while the HUD is moved ----------
local RESUME_MS = 5000

function MFMenu:enterHudMove()
    if not self.isOpen then return end
    self.suspended = true
    self:setGameHudHidden(false)
    self.hudDragging = false
    self.resumeTimer = RESUME_MS
end

function MFMenu:onHudDragStart()
    if not self.isOpen then return end
    self.suspended = true
    self:setGameHudHidden(false)
    self.hudDragging = true
    self.resumeTimer = RESUME_MS
end

function MFMenu:onHudDragEnd()
    self.hudDragging = false
    self.resumeTimer = RESUME_MS
end

function MFMenu:openEase()
    local t = (g_time - (self.openTime or 0)) / 220
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) * (1 - t) * (1 - t)
end

function MFMenu:resumeFromHudMove()
    self.openTime = g_time
    self.suspended = false
    self:setGameHudHidden(true)
    self.hudDragging = false
    self.resumeTimer = 0
    self.dragging = false
end

function MFMenu:isOverPanel(px, py)
    return px >= PX and px <= PX + PW and py >= PY and py <= PY + PH
end

function MFMenu:close()
    if self.nameEdit ~= nil then self:endNameEdit(false) end
    self.isOpen = false
    self:restoreHooks()
    self:setGameHudHidden(false)
    self.suspended = false
    self.hudDragging = false
    self.dragging = false
    self.fast = false
    self:unregisterMenuActions()
    pcall(function() g_inputBinding:setShowMouseCursor(false) end)
end

function MFMenu:update(dt)
    if not self.inputHelpHooked then self:hookInputHelp() end

    -- actions are deferred out of the input callbacks
    if self.pendingToggle then
        self.pendingToggle = false
        if self.isOpen then self:close() else self:open() end
    end
    if self.pendingClose then
        self.pendingClose = false
        if self.isOpen then self:close() end
    end


    if self.msgTimer > 0 then
        self.msgTimer = self.msgTimer - dt
        if self.msgTimer <= 0 then self.msg = nil end
    end

    self.bindTimer = self.bindTimer + dt
    if self.bindTimer > 2000 then
        self.bindTimer = 0
        if self.isOpen then self:installLateHook() self:installGlobalDrawHook() end
        if g_currentMission ~= nil then self:refreshHelp() end
    end

    if self.isOpen and self.suspended and not self.hudDragging then
        self.resumeTimer = self.resumeTimer - dt
        if self.resumeTimer <= 0 then self:resumeFromHudMove() end
    end

    if self.isOpen then
        if g_gui:getIsGuiVisible() then self:close() return end
        self.statsTimer = self.statsTimer + dt
        if self.statsTimer > 1000 then
            self.statsTimer = 0
            DM:refreshStationStats()
            self:refreshStored()
            if self.sortKey == "diff" or self.sortKey == "rate" or self.sortKey == "stn" or self.sortKey == "best" or self.sortKey == "bvm" then self:sortItems()
            elseif self.category == STORED_CAT or self.category == STORED_ALL_CAT then self:applyFilter() end
        end
    end
end

-- ===================== ACTIONS =====================
function MFMenu:changeAmount(d)
    local c = DM.CFG
    self.amount = math.max(c.minAmount, math.min(c.maxAmount, self.amount + d))
    if self.sortKey == "rate" then self:sortItems() end
end

function MFMenu:changeDays(d)
    local c = DM.CFG
    self.months = math.max(c.minMonths, math.min(math.floor(c.maxMonths), self.months + d))
    if self.sortKey == "rate" then self:sortItems() end
end

function MFMenu:signContract()
    local it = self.items[self.sel]
    if it == nil then return end
    local st = DM.fills[it.idx]
    if st == nil or st.stationKey == nil or st.stationKey == "" then
        self:setMsg(DM.t("mf_msg_nostation"))
        return
    end
    if (st.cooldown or 0) > 0 then
        self:setMsg(string.format(DM.t("mf_msg_cooldown"), DM:cooldownToMonths(st.cooldown) .. " " .. DM.t("mf_months")))
        return
    end
    local ok, immediate = DM:requestContract(it.idx, self.amount, math.min(self.months, math.floor(DM.CFG.maxMonths)))
    if ok then self:setMsg(DM.t(immediate and "mf_msg_signed" or "mf_msg_sent"))
    else self:setMsg(DM.t("mf_msg_failed")) end
end

function MFMenu:requestCancelContract(ct)
    if ct == nil then return end
    if self.confirmId == ct.id and g_time - self.confirmTime < 4000 then
        self.confirmId = nil
        self:cancelContract(ct)
    else
        self.confirmId, self.confirmTime = ct.id, g_time
        local fee = DM.CFG.cancelPenalty * DM:getContractValue(ct, ct.remaining)
        self:setMsg(string.format(DM.t("mf_msg_confirm_cancel"), g_i18n:formatMoney(fee, 0, true, true)))
    end
end

function MFMenu:cancelContract(ct)
    if ct == nil then return end
    DM:requestCancel(ct.id, false)
    self:setMsg(DM.t("mf_msg_cancelled"))
end

-- Spend the stored free cancel (asks for confirmation first, since only one can be held)
function MFMenu:requestFreeCancel(ct)
    if ct == nil then return end
    local perk = DM:getPerks(g_currentMission:getFarmId())
    if perk.tokens <= 0 then
        self:setMsg(DM.t("mf_msg_no_free"))
        return
    end
    if self.freeConfirmId == ct.id and g_time - self.freeConfirmTime < 4000 then
        self.freeConfirmId = nil
        DM:requestCancel(ct.id, true)
        self:setMsg(DM.t("mf_msg_free_used"))
    else
        self.freeConfirmId, self.freeConfirmTime = ct.id, g_time
        self:setMsg(DM.t("mf_msg_free_confirm"))
    end
end

-- ===================== COMMANDS =====================
function MFMenu:runCommand(cmd, rawShift)
    if self.suspended then
        if cmd == "close" then self:resumeFromHudMove() end   -- Esc ends the HUD move early
        return
    end
    local fast = self.fast or rawShift == true

    if self.nameEdit ~= nil then return end   -- typing a name: everything goes to the name editor
    if self.catPopup ~= nil then   -- category window is open
        if cmd == "close" then self.catPopup = nil end
        return
    end
    if self.stationPopup ~= nil then   -- station list popup is open: it takes the keys
        if cmd == "close" then self.stationPopup = nil
        elseif cmd == "down" then self.stationPopup.scroll = self.stationPopup.scroll + 1
        elseif cmd == "up" then self.stationPopup.scroll = math.max(0, self.stationPopup.scroll - 1) end
        return
    end
    if cmd == "close" then self.pendingClose = true return end
    if cmd == "tab" then self.tab = self.tab % 7 + 1 return end

    if self.tab == 1 then
        if cmd == "down" then self.sel = math.min(self.sel + 1, #self.items); self:ensureVisible()
        elseif cmd == "up" then self.sel = math.max(self.sel - 1, 1); self:ensureVisible()
        elseif cmd == "pageUp" then self.sel = math.max(self.sel - self.rows, 1); self:ensureVisible()
        elseif cmd == "pageDown" then self.sel = math.min(self.sel + self.rows, #self.items); self:ensureVisible()
        elseif cmd == "right" then self:changeAmount((fast and 10 or 1) * 1000)
        elseif cmd == "left" then self:changeAmount(-(fast and 10 or 1) * 1000)
        elseif cmd == "daysUp" then self:changeDays(fast and 6 or 1)
        elseif cmd == "daysDown" then self:changeDays(fast and -6 or -1)
        elseif cmd == "sort" then self:cycleSort()
        elseif cmd == "confirm" then self:signContract()
        end
    elseif self.tab == 2 then
        local list = DM:getFarmContracts(g_currentMission:getFarmId())
        if cmd == "down" then self.cSel = math.min(self.cSel + 1, #list)
        elseif cmd == "up" then self.cSel = math.max(self.cSel - 1, 1)
        elseif cmd == "cancel" then
            self:requestCancelContract(list[self.cSel])
        elseif cmd == "freeCancel" then
            self:requestFreeCancel(list[self.cSel])
        end
    else
        local key = (self.tab == 3 and "eScroll") or (self.tab == 4 and "hScroll") or (self.tab == 5 and "alScroll") or (self.tab == 7 and "bScroll") or nil
        if key ~= nil then
            if cmd == "down" then self[key] = self[key] + 1
            elseif cmd == "up" then self[key] = math.max(0, self[key] - 1) end
        end
    end
end

-- ===================== RAW KEY FALLBACK =====================
-- Only used where the game's own binding is missing (unbound / not registered).
function MFMenu:keyEvent(unicode, sym, modifier, isDown)
    if not isDown then return end
    if self.nameEdit ~= nil and self.isOpen then   -- typing a category name: nothing else may react
        self:nameEditKey(unicode, sym)
        return
    end
    local ctrl = Input.isKeyPressed(Input.KEY_lctrl)

    if sym == Input.KEY_m and ctrl then
        local inVehicle = g_currentMission ~= nil and g_currentMission.controlledVehicle ~= nil
        local registered = inVehicle and self.vehicleRegistered or (not inVehicle and self.onfootRegistered)
        if not registered or self:rawAllowed("MF_TOGGLE_MENU") then self:requestToggle() end
        return
    end
    if not self.isOpen then return end

    if sym == Input.KEY_esc then
        if self.suspended then self:resumeFromHudMove() else self.pendingClose = true end
        return
    end   -- always works as a safety net

    local cmd = RAW_KEYS[sym]
    if cmd == nil then return end
    if self:hasMenuActions() and not self:rawAllowed(CMD_ACTION[cmd]) then return end

    local shift = Input.isKeyPressed(Input.KEY_lshift) or Input.isKeyPressed(Input.KEY_rshift)
    local rawShift = shift and (not self:hasMenuActions() or self:rawAllowed("MF_FAST"))
    self:runCommand(cmd, rawShift)
end

function MFMenu:mouseEvent(posX, posY, isDown, isUp, button)
    self.mx, self.my = posX, posY
    if not self.isOpen or self.suspended then return end
    if self.dragging then
        if isUp then self.dragging = false else self:dragScroll(posY) end
        return
    end
    if not isDown then return end
    local wheel = button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN
    if not wheel and MFHud ~= nil and MFHud:isOver(posX, posY) then return end   -- HUD move / resize handles it

    if button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN then
        local d = (button == Input.MOUSE_BUTTON_WHEEL_UP) and -3 or 3
        if self.stationPopup ~= nil then self.stationPopup.scroll = math.max(0, self.stationPopup.scroll + d)
        elseif self.tab == 1 then self.scroll = self.scroll + d; self:clampScroll()
        elseif self.tab == 3 then self.eScroll = math.max(0, self.eScroll + d)
        elseif self.tab == 4 then self.hScroll = math.max(0, self.hScroll + d)
        elseif self.tab == 5 then self.alScroll = math.max(0, self.alScroll + d)
        elseif self.tab == 7 then self.bScroll = math.max(0, self.bScroll + d) end
    elseif button == Input.MOUSE_BUTTON_LEFT then
        for i = #self.hits, 1, -1 do
            local h = self.hits[i]
            if posX >= h.x and posX <= h.x + h.w and posY >= h.y and posY <= h.y + h.h then
                h.fn()
                break
            end
        end
    end
end

-- ===================== DRAW HELPERS =====================
function MFMenu:hover(x, y, w, h)
    if (self.stationPopup ~= nil or self.catPopup ~= nil or self.nameEdit ~= nil) and not self.popupDraw then return false end   -- popup open: nothing underneath reacts
    return self.mx >= x and self.mx <= x + w and self.my >= y and self.my <= y + h
end

function MFMenu:addHit(x, y, w, h, fn)
    table.insert(self.hits, {x = x, y = y, w = w, h = h, fn = fn})
end

function MFMenu:button(x, y, w, h, label, fn, active, size)
    local P = TH()
    local c = active and P.btnOn or P.btn
    local hov = self:hover(x, y, w, h)
    local rad = math.min(0.0045, h * 0.3)
    local ins = rad * MFTheme.aspect()
    if hov then   -- soft glow around the hovered button
        MFTheme.rrect(x - 0.0016, y - 0.0026, w + 0.0032, h + 0.0052, P.hi, 0.28, rad + 0.0016)
    end
    local r, g, b = c[1], c[2], c[3]
    if hov then r, g, b = math.min(1, r + 0.12), math.min(1, g + 0.12), math.min(1, b + 0.12) end
    MFTheme.rrect(x, y, w, h, {r, g, b}, 1, rad)
    drawFilledRect(x + ins, y + h * 0.5, w - 2 * ins, h * 0.5 - rad * 0.4, 1, 1, 1, 0.05)       -- soft top sheen
    drawFilledRect(x + ins, y + h - h * 0.07, w - 2 * ins, h * 0.07, 1, 1, 1, 0.16)            -- top highlight
    drawFilledRect(x + ins, y, w - 2 * ins, h * 0.07, 0, 0, 0, 0.35)                           -- bottom shade
    if active then MFTheme.rect(x + w * 0.1, y, w * 0.8, h * 0.09, P.hi, 1) end                -- accent underline
    txt(x + w / 2, y + h * 0.27, size or 0.0135, label, 1, 1, 1, RenderText.ALIGN_CENTER, active)
    self:addHit(x, y, w, h, fn)
end

function MFMenu:rowBackground(x, y, w, h, selected, fn)
    if selected then
        MFTheme.rrect(x, y, w, h, TH().btnOn, 0.75, 0.003)
        MFTheme.rect(x, y + h * 0.15, 0.0022, h * 0.7, TH().hi, 1)       -- accent marker on the selected row
    elseif self:hover(x, y, w, h) then
        MFTheme.rrect(x, y, w, h, TH().hover, 0.8, 0.003)
        MFTheme.rect(x, y + h * 0.2, 0.0015, h * 0.6, TH().hi, 0.7)      -- glow marker under the mouse
    end
    self:addHit(x, y, w, h, fn)
end

-- sortable column header; align: LEFT text at textX, or RIGHT text ending at textX
-- sortable single-line header (no box): bold + sort arrow above the text when active
function MFMenu:headerButton(bx, by, bw, bh, label, textX, align, key, defaultAsc, hy)
    local active = self.sortKey == key
    local size = 0.0125
    local hov = self:hover(bx, by, bw, bh)
    local c = (active or hov) and 1 or 0.85
    local tw = getTextWidth(size, label)
    local ty = (hy or (by + 0.004)) - 0.003
    if active then txt(textX, ty, size, label, TH().hi[1] or 1, TH().hi[2] or 1, TH().hi[3] or 1, align, true)
    else txt(textX, ty, size, label, c, c, c, align, false) end
    if active then
        local cx = (align == RenderText.ALIGN_RIGHT) and (textX - tw / 2) or (textX + tw / 2)
        drawArrow(cx, ty + 0.0145, self.sortAsc)
    end
    self:addHit(bx, by, bw, bh, function() self:clickSortHeader(key, defaultAsc) end)
end

-- two-line column header; sortable when key is given
function MFMenu:headerButton2(rightX, hy, l1, l2, key, defaultAsc)
    local size = 0.0115
    local maxW = 0.056
    size = math.min(fitSize(size, l1, maxW), fitSize(size, l2, maxW))
    local bx, by, bw, bh = rightX - maxW - 0.002, hy - 0.0215, maxW + 0.006, 0.031
    local active = key ~= nil and self.sortKey == key
    local hov = key ~= nil and self:hover(bx, by, bw, bh)
    local c = key == nil and 0.7 or ((active or hov) and 1 or 0.85)
    local r, g, b = c, c, c
    if active then r, g, b = TH().hi[1] or 1, TH().hi[2] or 1, TH().hi[3] or 1 end
    txt(rightX, by + 0.0185, size, l1, r, g, b, RenderText.ALIGN_RIGHT, active)
    txt(rightX, by + 0.0045, size, l2, r, g, b, RenderText.ALIGN_RIGHT, active)
    if active then
        local tw = math.max(getTextWidth(size, l1), getTextWidth(size, l2))
        drawArrow(rightX - tw / 2, hy + 0.0105, self.sortAsc)
    end
    if key ~= nil then self:addHit(bx, by, bw, bh, function() self:clickSortHeader(key, defaultAsc) end) end
end

-- narrow sortable header over a checkbox column (HUD / Alert): label centred on cx, arrow above when active
function MFMenu:headerCheck(cx, hy, label, key)
    local size = 0.0088
    local bw = 0.0145
    local bx, by, bh = cx - bw / 2, hy - 0.0065, 0.026
    local active = self.sortKey == key
    local hov = self:hover(bx, by, bw, bh)
    local c = (active or hov) and 1 or 0.7
    if active then txt(cx, hy, size, label, TH().hi[1] or 1, TH().hi[2] or 1, TH().hi[3] or 1, RenderText.ALIGN_CENTER, true)
    else txt(cx, hy, size, label, c, c, c, RenderText.ALIGN_CENTER) end
    if active then drawArrow(cx, hy + 0.0125, self.sortAsc) end
    self:addHit(bx, by, bw, bh, function() self:clickSortHeader(key, false) end)   -- first click: checked items on top
end

-- Two rows: [All Items | Stored Items | Other Items Not Listed Below] over the crop categories
local function categoryRows()
    local row2 = {4, 5, 6, 7, 8, 9}
    local n = MFHud ~= nil and MFHud.customCats ~= nil and #MFHud.customCats or 0
    for k = 1, n do table.insert(row2, OTHER_CAT + k) end
    return {{1, STORED_CAT, STORED_ALL_CAT, OTHER_CAT}, row2}
end

function MFMenu:drawCategoryButtons(x, ty)
    local baseSize = 0.0115
    local availW = LIST_W - 0.024
    for rowIdx, row in ipairs(categoryRows()) do
        local labels, widths, total = {}, {}, 0
        setTextBold(false)
        for k, ci in ipairs(row) do
            labels[k] = string.format("%s (%d)", self:catLabel(ci), (self.catCounts and self.catCounts[ci]) or 0)
            widths[k] = getTextWidth(baseSize, labels[k]) + 0.014
            total = total + widths[k] + 0.004
        end
        local scale = math.min(1, availW / total)
        local cx = x + 0.012
        local by = ty - (rowIdx - 1) * 0.026
        for k, ci in ipairs(row) do
            local bw = widths[k] * scale
            self:button(cx, by, bw, ROW_H, labels[k], function() self:setCategory(ci) end, self.category == ci, baseSize * scale)
            cx = cx + bw + 0.004 * scale
        end
    end
end

-- vertical scroll bar for the item list (click / drag the track)
function MFMenu:drawScrollbar(trackX, trackTop, trackH)
    local trackW = 0.009
    local total, rows = #self.items, self.rows
    local trackBottom = trackTop - trackH
    MFTheme.rect(trackX, trackBottom, trackW, trackH, TH().track, 1)
    self.sb = {bottom = trackBottom, h = trackH}
    if total <= rows then return end
    local thumbH = math.max(0.03, trackH * rows / total)
    local maxScroll = total - rows
    local thumbBottom = trackBottom + (trackH - thumbH) * (1 - self.scroll / maxScroll)
    self.sb.thumbH = thumbH
    local active = self.dragging or self:hover(trackX, trackBottom, trackW, trackH)
    MFTheme.rect(trackX, thumbBottom, trackW, thumbH, active and TH().fill or TH().btnOn, 1)
    self:addHit(trackX - 0.004, trackBottom, trackW + 0.008, trackH, function()
        self.dragging = true
        self:dragScroll(self.my)
    end)
end

function MFMenu:dragScroll(posY)
    local sb = self.sb
    if sb == nil or sb.thumbH == nil then return end
    local maxScroll = math.max(0, #self.items - self.rows)
    if maxScroll == 0 then return end
    local frac = 1 - (posY - sb.bottom - sb.thumbH / 2) / (sb.h - sb.thumbH)
    frac = math.max(0, math.min(1, frac))
    self.scroll = math.floor(frac * maxScroll + 0.5)
    self:clampScroll()
end

-- label ... [-steps...]  value  [+steps...]   (steps listed from most negative to most positive)
function MFMenu:stepper(dx, rx, y, label, valueStr, steps, fn)
    local bw, pitch, valueW, bh = 0.027, 0.029, 0.080, ROW_H
    local n = #steps
    local half = n / 2
    local gx = rx - (n * pitch + valueW)
    txt(dx, y + 0.005, 0.0145, label)
    for i = 1, n do
        local bx
        if i <= half then bx = gx + (i - 1) * pitch
        else bx = gx + half * pitch + valueW + (i - half - 1) * pitch end
        local step = steps[i]
        self:button(bx, y, bw, bh, step.label, function() fn(step.d) end, false, 0.0110)
    end
    txt(gx + half * pitch + valueW / 2, y + 0.005, 0.0145, valueStr, 1, 1, 1, RenderText.ALIGN_CENTER, true)
end

-- ===================== DRAW =====================
-- The menu is drawn at the very end of the frame (see the Gui.draw hook below) so it ends up above every HUD and
-- overlay that other mods draw. This listener draw is only a fallback for when that hook is not running.
function MFMenu:draw()
    if MFMenu.lateStamp ~= nil and g_time - MFMenu.lateStamp < 150 then return end
    if MFMenu.globalStamp ~= nil and g_time - MFMenu.globalStamp < 150 then return end
    if self.isOpen and not self.fallbackLogged then
        self.fallbackLogged = true
        Logging.info("[MarketsAndFutures] menu is being drawn by the fallback listener draw (late hook not running)")
    end
    self:drawPanel()
end

function MFMenu:drawPanel()
    if not self.isOpen or self.suspended then return end
    -- Other mods (AutoDrive, CoursePlay, ...) call new2DLayer() before drawing their HUD, which puts it above
    -- everything drawn earlier. Starting our own new layer here (from the last-in-frame hook) puts the menu above them.
    if new2DLayer ~= nil then new2DLayer() end
    self.hits = {}
    local x, y, w, h = PX, PY, PW, PH

    -- open animation: the backdrop fades in while the panel slides up
    local ease = self:openEase()
    y = y - (1 - ease) * 0.05
    drawFilledRect(0, 0, 1, 1, 0, 0, 0, 0.55 * ease)
    local P = TH()
    local R, RR = MFTheme.rect, MFTheme.rrect
    local rad = 0.013
    RR(x + 0.004, y - 0.006, w, h, {0, 0, 0}, 0.45 * ease, rad + 0.001)      -- drop shadow
    RR(x - 0.0015, y - 0.0025, w + 0.003, h + 0.005, P.accent, 1, rad + 0.0015)   -- frame
    RR(x, y, w, h, P.bg, 0.97, rad)
    RR(x, y, w, h * 0.22, {0, 0, 0}, 0.18, rad, false, true)                  -- shading toward the bottom
    -- gradient header bar with rounded top corners
    local hh, strips = 0.045, 30
    local sh = hh / strips
    local pxw = 1 / (g_screenWidth or 1920)
    for j = 0, strips - 1 do      -- j = 0 is the top strip
        local t = j / (strips - 1)
        local inset = MFTheme.cornerInset((j + 0.5) * sh, rad)
        local col = {
            P.hdrTop[1] + (P.hdrBot[1] - P.hdrTop[1]) * t,
            P.hdrTop[2] + (P.hdrBot[2] - P.hdrTop[2]) * t,
            P.hdrTop[3] + (P.hdrBot[3] - P.hdrTop[3]) * t}
        local sy = y + h - (j + 1) * sh
        R(x + inset, sy, w - 2 * inset, sh + 0.0002, col, 1)
        if inset > 0 then   -- soft edge pixel against the frame
            R(x + inset - pxw, sy, pxw, sh + 0.0002, col, 0.5)
            R(x + w - inset, sy, pxw, sh + 0.0002, col, 0.5)
        end
    end
    R(x, y + h - hh - 0.0018, w, 0.0018, P.accent, 1)                          -- rule under header
    RR(x + 0.007, y + h - hh + 0.008, 0.0035, hh - 0.016, P.hi, 1, 0.0012)    -- title marker
    R(x + 0.016, y + 0.030, w - 0.032, 0.0010, P.accent, 0.45)                 -- footer rule

    -- station list popup: draw only the empty frame plus the popup, so nothing underneath can show through
    if self.nameEdit ~= nil then
        self:drawNameEditor()
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(1, 1, 1, 1)
        return
    end
    if self.catPopup ~= nil then
        self:drawCategoryPopup()
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(1, 1, 1, 1)
        return
    end
    if self.stationPopup ~= nil then
        self:drawStationPopup()
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(1, 1, 1, 1)
        return
    end

    txt(x + 0.015, y + h - 0.034, 0.022, DM.t("mf_title"), 1, 1, 1, nil, true)
    local ty = y + h - 0.0385
    self:button(x + 0.170, ty, 0.070, 0.030, DM.t("mf_tab_market"), function() self.tab = 1 end, self.tab == 1, 0.0140)
    self:button(x + 0.244, ty, 0.090, 0.030, DM.t("mf_tab_contracts"), function() self.tab = 2 end, self.tab == 2, 0.0140)
    self:button(x + 0.338, ty, 0.085, 0.030, DM.t("mf_tab_events"), function() self.tab = 3 end, self.tab == 3, 0.0140)
    self:button(x + 0.427, ty, 0.065, 0.030, DM.t("mf_tab_history"), function() self.tab = 4 end, self.tab == 4, 0.0140)
    self:button(x + 0.496, ty, 0.060, 0.030, DM.t("mf_tab_alerts"), function() self.tab = 5 end, self.tab == 5, 0.0140)
    self:button(x + 0.560, ty, 0.075, 0.030, DM.t("mf_tab_settings"), function() self.tab = 6 end, self.tab == 6, 0.0140)
    self:button(x + 0.639, ty, 0.105, 0.030, DM.t("mf_tab_block"), function() self.tab = 7 end, self.tab == 7, 0.0140)
    local hudOn = MFHud ~= nil and MFHud.cfg.visible
    self:button(x + w - 0.180, ty, 0.070, 0.030, DM.t("mf_hud_btn_move"),
        function() self:enterHudMove() end, false, 0.0120)
    self:button(x + w - 0.105, ty, 0.065, 0.030, DM.t(hudOn and "mf_hud_btn_on" or "mf_hud_btn_off"),
        function() if MFHud ~= nil then MFHud:setVisible(not MFHud.cfg.visible) end end, hudOn, 0.0120)
    self:button(x + w - 0.035, ty, 0.028, 0.030, "X", function() self.pendingClose = true end, false, 0.015)

    if self.msg ~= nil then
        txt(x + w - 0.020, y + h - 0.062, 0.0135, self.msg, TH().hi, nil, nil, RenderText.ALIGN_RIGHT, true)
    end

    if self.tab == 1 then self:drawMarket(x, y, w, h)
    elseif self.tab == 2 then self:drawContracts(x, y, w, h)
    elseif self.tab == 3 then self:drawEvents(x, y, w, h)
    elseif self.tab == 4 then self:drawHistory(x, y, w, h)
    elseif self.tab == 5 then self:drawAlerts(x, y, w, h)
    elseif self.tab == 7 then self:drawBlock(x, y, w, h)
    else self:drawSettings(x, y, w, h) end

    txt(x + 0.015, y + 0.012, 0.0120, self.helpCache[self.tab] or self.helpCache[3] or "", 0.75, 0.75, 0.75)


    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- ---------- STATION LIST POPUP ----------
local function formatDistance(m)
    if m == nil then return "-" end
    if m >= 1000 then return string.format("%.1f km", m / 1000) end
    return string.format("%d m", math.floor(m + 0.5))
end

function MFMenu:drawStationPopup()
    local pop = self.stationPopup
    local ft = g_fillTypeManager:getFillTypeByIndex(pop.idx)
    local base = DM:getBasePricePer1000(pop.idx)
    local px, py, pw, ph = 0.18, 0.17, 0.64, 0.64

    -- dim everything underneath and swallow clicks outside the window (a click outside closes it)
    drawFilledRect(0, 0, 1, 1, 0, 0, 0, 0.55)
    self:addHit(0, 0, 1, 1, function() self.stationPopup = nil end)
    self:addHit(px, py, pw, ph, function() end)
    self.popupDraw = true

    MFTheme.rrect(px, py, pw, ph, TH().bg, 1, 0.008)
    MFTheme.rect(px + 0.012, py + ph - 0.052, pw - 0.024, 0.0014, TH().accent, 0.7)
    txt(px + 0.020, py + ph - 0.036, 0.0185, string.format("%s - %s", ft and ft.title or "?", DM.t("mf_popup_title")), 1, 1, 1, nil, true)
    self:button(px + pw - 0.045, py + ph - 0.042, 0.028, 0.026, "X", function() self.stationPopup = nil end, false, 0.0145)

    -- columns (right edges)
    local cName = px + 0.062
    local cPrice, cVs, cDist, cTag = px + 0.345, px + 0.420, px + 0.505, px + pw - 0.020
    local hy = py + ph - 0.078
    txt(cName, hy, 0.0125, DM.t("mf_block_station"), 0.7, 0.7, 0.7)
    local function sortHeader(label, rightX, key, w)
        local active = pop.sortKey == key
        local hov = self:hover(rightX - w, hy - 0.004, w + 0.004, 0.020)
        local c = (active or hov) and 1 or 0.85
        if active then txt(rightX, hy, 0.0125, label, TH().hi[1], TH().hi[2], TH().hi[3], RenderText.ALIGN_RIGHT, true)
        else txt(rightX, hy, 0.0125, label, c, c, c, RenderText.ALIGN_RIGHT) end
        if active then drawArrow(rightX - getTextWidth(0.0125, label) / 2, hy + 0.0155, key == "price") end
        self:addHit(rightX - w, hy - 0.004, w + 0.004, 0.020, function() pop.sortKey = key; pop.scroll = 0 end)
    end
    sortHeader(DM.t("mf_col_price"), cPrice, "price", 0.095)
    txt(cVs, hy, 0.0125, DM.t("mf_vs_median"), 0.7, 0.7, 0.7, RenderText.ALIGN_RIGHT)
    sortHeader(DM.t("mf_distance"), cDist, "dist", 0.070)

    local list = DM:getStationsForItem(pop.idx)
    local function usable(e) return not e.blocked and not e.noAccess and e.price ~= nil end
    table.sort(list, function(a, b)
        local ua, ub = usable(a), usable(b)
        if ua ~= ub then return ua end
        if ua then
            if pop.sortKey == "dist" then
                local da, db = a.dist or 1e12, b.dist or 1e12
                if da ~= db then return da < db end
            else
                if a.price ~= b.price then return a.price > b.price end
            end
        end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)

    if #list == 0 then
        txt(px + 0.020, hy - 0.045, 0.016, DM.t("mf_popup_none"), 0.8, 0.8, 0.8)
        self.popupDraw = false
        return
    end

    local bestPrice = 0
    for _, e in ipairs(list) do if usable(e) and e.price > bestPrice then bestPrice = e.price end end

    local rh = ROW_H * 1.1
    local visible = math.floor((hy - (py + 0.020)) / rh)
    pop.scroll = math.max(0, math.min(pop.scroll, math.max(0, #list - visible)))
    local editable = DM.isServer == true
    for r = 1, visible do
        local e = list[pop.scroll + r]
        if e == nil then break end
        local ry = hy - r * rh - 0.004
        if r % 2 == 0 then MFTheme.rect(px + 0.010, ry - 0.004, pw - 0.020, rh, TH().box, 0.45) end
        local grey = not usable(e)
        local c = grey and 0.5 or 1
        local isBest = usable(e) and e.price >= bestPrice - 0.001

        local station = e
        self:drawCheckbox(px + 0.034, ry, e.blocked, function()
            if editable then DM:setStationBlocked(station.key, not (DM.blocked[station.key] == true))
            else self:setMsg(DM.t("mf_set_hostonly")) end
        end)
        txt(cName, ry, fitSize(0.0135, e.name, cPrice - 0.105 - cName), e.name, c, c, c, nil, isBest)
        if e.price ~= nil then
            local pr, pg, pb = c, c, c
            if isBest then pr, pg, pb = 1, 0.9, 0.35 end
            txt(cPrice, ry, 0.0135, money(e.price), pr, pg, pb, RenderText.ALIGN_RIGHT, isBest)
            if base > 0 then
                local pct = (e.price / base - 1) * 100
                local vr, vg, vb = pctColor(pct)
                if grey then vr, vg, vb = 0.5, 0.5, 0.5 end
                txt(cVs, ry, 0.0135, string.format("%+.1f%%", pct), vr, vg, vb, RenderText.ALIGN_RIGHT)
            end
        else
            txt(cPrice, ry, 0.0135, "-", 0.5, 0.5, 0.5, RenderText.ALIGN_RIGHT)
        end
        txt(cDist, ry, 0.0135, formatDistance(e.dist), c, c, c, RenderText.ALIGN_RIGHT)
        if e.blocked then txt(cTag, ry, 0.0125, DM.t("mf_block_blocked"), 1, 0.45, 0.4, RenderText.ALIGN_RIGHT, true)
        elseif e.noAccess then txt(cTag, ry, 0.0125, DM.t("mf_block_noaccess"), 1, 0.7, 0.4, RenderText.ALIGN_RIGHT, true)
        elseif e.isContract then txt(cTag, ry, 0.0125, DM.t("mf_tag_contract"), 0.45, 1, 0.5, RenderText.ALIGN_RIGHT, true) end
    end
    self.popupDraw = false
end

-- ---------- MARKET TAB ----------
function MFMenu:drawMarket(x, y, w, h)
    local ty = y + h - 0.074
    self:drawCategoryButtons(x, ty)

    -- column headers (Item / Avg / vs Avg are sort buttons)
    local hy = ty - 0.052
    local cAvg, cDiff, cStn, cBest, cBvm, cCvb = x + 0.200, x + 0.252, x + 0.330, x + 0.389, x + 0.444, x + 0.497
    local hb = 0.0205
    self:headerButton(x + 0.008, hy - 0.0215, 0.140, 0.031, DM.t("mf_col_item"), x + 0.012, RenderText.ALIGN_LEFT, "name", true, hy)
    self:headerButton2(cAvg, hy, DM.t("mf_hd_price1"), DM.t("mf_hd_price2"), "avg", false)
    self:headerButton2(cDiff, hy, DM.t("mf_hd_vs1"), DM.t("mf_hd_vs2"), "diff", false)
    self:headerButton2(cStn, hy, DM.t("mf_hd_stn1"), DM.t("mf_hd_stn2"), "stn", false)
    self:headerButton2(cBest, hy, DM.t("mf_hd_best1"), DM.t("mf_hd_best2"), "best", false)
    self:headerButton2(cBvm, hy, DM.t("mf_hd_bvm1"), DM.t("mf_hd_bvm2"), "bvm", false)
    self:headerButton2(cCvb, hy, DM.t("mf_hd_cvb1"), DM.t("mf_hd_cvb2"), "rate", false)
    self:headerCheck(x + 0.5040, hy, DM.t("mf_col_hud"), "hud")
    self:headerCheck(x + 0.5185, hy, DM.t("mf_col_alert"), "alert")
    if self.category == STORED_ALL_CAT then
        drawTrashIcon(x + 0.5330, hy - 0.0005, 0.75, 0.75, 0.75)
        txt(x + 0.50, hy - 0.018, 0.0095, DM.t("mf_stored_hide_hint"), 0.6, 0.6, 0.6, RenderText.ALIGN_RIGHT)
    end
    txt(x + 0.012, hy - 0.018, 0.0095, DM.t("mf_col_price"), 0.5, 0.5, 0.5)
    if #self.items == 0 then
        txt(x + 0.012, hy - 0.050, 0.016, DM.t("mf_no_items"), 0.8, 0.8, 0.8)
    end

    for r = 1, self.rows do
        local i = self.scroll + r
        local it = self.items[i]
        if it == nil then break end
        local st = DM.fills[it.idx]
        local ry = hy - 0.020 - r * ROW_H - 0.004
        if r % 2 == 0 then MFTheme.rect(x + 0.008, ry - 0.004, LIST_W - 0.0165, ROW_H, TH().box, 0.45) end   -- row striping
        self:rowBackground(x + 0.008, ry - 0.004, LIST_W - 0.0165, ROW_H, i == self.sel, function() self.sel = i end)

        local base = DM:getBasePricePer1000(it.idx)
        local stats = DM.stationStats[it.idx]
        local pct = (st.mult - 1) * 100
        local cr, cg, cb = pctColor(pct)
        local iw = MFTheme:drawIcon(it.idx, x + 0.012, ry - 0.0025, ROW_H * 0.85)
        local nx = x + 0.012 + iw + 0.004
        txt(nx, ry, fitSize(0.0130, it.title, cAvg - 0.052 - nx), it.title)
        txt(cAvg, ry, 0.0130, money(base), 0.8, 0.8, 0.8, RenderText.ALIGN_RIGHT)
        txt(cStn, ry, 0.0130, stats and money(stats.avg) or "-", TH().sub, nil, nil, RenderText.ALIGN_RIGHT)
        txt(cBest, ry, 0.0130, stats and money(stats.best) or "-", 1, 0.9, 0.35, RenderText.ALIGN_RIGHT)
        txt(cDiff, ry, 0.0130, string.format("%+.0f%%", pct), cr, cg, cb, RenderText.ALIGN_RIGHT)
        -- best station vs the price median, and the locked contract price vs the best station
        if stats ~= nil and base > 0 then
            local bp = (stats.best / base - 1) * 100
            local br, bg, bb = pctColor(bp)
            txt(cBvm, ry, 0.0130, string.format("%+.1f%%", bp), br, bg, bb, RenderText.ALIGN_RIGHT)
        else
            txt(cBvm, ry, 0.0130, "-", 0.6, 0.6, 0.6, RenderText.ALIGN_RIGHT)
        end
        local cvb = self:contractVsBest(it.idx)
        if cvb ~= nil then
            local rr, rg, rb = pctColor(cvb * 100)
            if (st.cooldown or 0) > 0 then rr, rg, rb = 0.5, 0.5, 0.5 end   -- grey = no contract available right now
            txt(cCvb, ry, 0.0130, string.format("%+.1f%%", cvb * 100), rr, rg, rb, RenderText.ALIGN_RIGHT)
        else
            txt(cCvb, ry, 0.0130, "-", 0.6, 0.6, 0.6, RenderText.ALIGN_RIGHT)
        end

        -- HUD and Alert checkboxes
        local itIdx = it.idx
        self:drawCheckbox(x + 0.5040, ry, MFHud ~= nil and MFHud:isChecked(itIdx), function()
            if MFHud ~= nil then MFHud:toggle(itIdx) end
        end)
        self:drawCheckbox(x + 0.5185, ry, MFHud ~= nil and MFHud:getAlert(itIdx) ~= nil, function()
            self:toggleAlertFromList(itIdx)
        end)
        if self.category == STORED_ALL_CAT and MFHud ~= nil then   -- trash column: hide from "Stored Items"
            self:drawCheckbox(x + 0.5330, ry, MFHud:isStoredHidden(itIdx), function()
                MFHud:toggleStoredHidden(itIdx)
                self:refreshStored()
            end)
        end
        if #st.events > 0 then
            local e = st.events[1]
            local bc = e.surplus and {0.80, 0.28, 0.26} or {0.22, 0.62, 0.30}
            MFTheme.rrect(cDiff + 0.004, ry - 0.0005, 0.019, 0.0145, bc, 0.95, 0.003)
            txt(cDiff + 0.0135, ry + 0.0015, 0.0085, DM.t(e.surplus and "mf_badge_sur" or "mf_badge_dem"), 1, 1, 1, RenderText.ALIGN_CENTER, true)
        end
    end

    self:drawScrollbar(x + LIST_W - 0.007, hy - 0.028, self.rows * ROW_H)

    -- detail panel
    local dx, dy = x + LIST_W + 0.025, y + h - 0.085
    drawFilledRect(x + LIST_W + 0.010, y + 0.04, 0.002, h - 0.095, 0.3, 0.3, 0.3, 1)
    local it = self.items[self.sel]
    if it == nil then return end
    local st = DM.fills[it.idx]
    local base = DM:getBasePricePer1000(it.idx)
    local stats = DM.stationStats[it.idx]
    local rx = x + w - 0.02

    local tiw = MFTheme:drawIcon(it.idx, dx, dy - 0.006, 0.032)
    local storedL = (self.stored or {})[it.idx]
    local hasStored = storedL ~= nil and storedL > 0
    local storedStr = hasStored and string.format("%s: %s L", DM.t("mf_stored"), g_i18n:formatNumber(math.floor(storedL))) or nil
    do   -- item name (shrunk to fit) with the "List Stations" button right after it
        local bw = 0.082
        local nameX = dx + tiw + 0.006
        local limit = rx
        if storedStr ~= nil then
            setTextBold(true)
            limit = rx - getTextWidth(0.0150, storedStr) - 0.012
            setTextBold(false)
        end
        local availName = limit - bw - 0.010 - nameX
        setTextBold(true)
        local nameSize = math.max(fitSize(0.022, it.title, availName), 0.0125)
        local nameW = getTextWidth(nameSize, it.title)
        setTextBold(false)
        txt(nameX, dy, nameSize, it.title, TH().hi, nil, nil, nil, true)
        local bx = nameX + nameW + 0.010
        if bx + bw > limit then bx = math.max(nameX, limit - bw) end
        local itemIdx = it.idx
        self:button(bx, dy - 0.003, bw, 0.024, DM.t("mf_list_stations"), function()
            self.stationPopup = {idx = itemIdx, scroll = 0, sortKey = "price"}
        end, false, 0.0125)
    end
    if hasStored then
        txt(rx, dy, 0.0150, storedStr, 0.45, 1, 0.5, RenderText.ALIGN_RIGHT, true)
    end
    dy = dy - 0.030
    self:drawCategoryRow(dx, rx, dy, it)
    dy = dy - 0.032
    txt(dx, dy, 0.0145, DM.t("mf_base")); txt(rx, dy, 0.0145, money(base), 1, 1, 1, RenderText.ALIGN_RIGHT)
    do
        local diffMult, diffSrc = DM:getDifficultyMultiplier()
        local note = string.format(DM.t("mf_base_note"), money(DM:getRawPricePer1000(it.idx)), diffMult)
        local nr, ng, nb = 0.6, 0.6, 0.6
        if diffSrc == "default" then note, nr, ng, nb = DM.t("mf_base_note_nodiff"), 1, 0.7, 0.4 end
        txt(rx - 0.075, dy + 0.0015, 0.0100, note, nr, ng, nb, RenderText.ALIGN_RIGHT)
    end
    dy = dy - 0.024
    local avgPct = (st.mult - 1) * 100
    local cr, cg, cb = pctColor(avgPct)
    txt(dx, dy, 0.0145, DM.t("mf_vs_median")); txt(rx, dy, 0.0145, string.format("%+.1f%%  (%s)", avgPct, money(base * (st.mult - 1))), cr, cg, cb, RenderText.ALIGN_RIGHT)
    dy = dy - 0.024
    txt(dx, dy, 0.0145, DM.t("mf_best_vs_median"))
    if stats ~= nil and base > 0 then
        local bp = (stats.best / base - 1) * 100
        local br, bg, bb = pctColor(bp)
        txt(rx, dy, 0.0145, string.format("%+.1f%%  (%s)", bp, money(stats.best - base)), br, bg, bb, RenderText.ALIGN_RIGHT)
    else
        txt(rx, dy, 0.0145, "-", 0.7, 0.7, 0.7, RenderText.ALIGN_RIGHT)
    end
    dy = dy - 0.024
    local dayPct = st.dayRef > 0 and (st.mult / st.dayRef - 1) * 100 or 0
    cr, cg, cb = pctColor(dayPct * 3)
    txt(dx, dy, 0.0145, DM.t("mf_today")); txt(rx, dy, 0.0145, string.format("%+.1f%%", dayPct), cr, cg, cb, RenderText.ALIGN_RIGHT)

    -- station prices
    dy = dy - 0.030
    if stats ~= nil then
        txt(dx, dy, 0.0145, string.format(DM.t("mf_stn_avg"), stats.count)); txt(rx, dy, 0.0145, money(stats.avg), TH().sub, nil, nil, RenderText.ALIGN_RIGHT)
        dy = dy - 0.022
        txt(dx, dy, 0.0145, DM.t("mf_stn_best")); txt(rx, dy, 0.0145, money(stats.best), 1, 0.9, 0.35, RenderText.ALIGN_RIGHT, true)
        dy = dy - 0.019
        txt(dx + 0.012, dy, 0.0120, stats.bestName, 0.7, 0.7, 0.7)
    else
        txt(dx, dy, 0.0145, string.format(DM.t("mf_stn_avg"), 0)); txt(rx, dy, 0.0145, "-", 0.7, 0.7, 0.7, RenderText.ALIGN_RIGHT)
        dy = dy - 0.041
    end

    dy = dy - 0.032
    txt(dx, dy, 0.0155, DM.t("mf_events"), TH().sub, nil, nil, nil, true)
    if #st.events == 0 then
        dy = dy - 0.022
        txt(dx + 0.01, dy, 0.0135, DM.t("mf_none"), 0.7, 0.7, 0.7)
    end
    for _, e in ipairs(st.events) do
        dy = dy - 0.022
        local label = string.format("%s %+.0f%%  (%d %s)", (DM.t(e.surplus and "mf_surplus" or "mf_demand") .. (e.linked and DM.t("mf_linked_suffix") or "")),
            (e.factor - 1) * 100, DM:daysToMonths(e.daysLeft), DM.t("mf_months"))
        txt(dx + 0.01, dy, 0.0135, label, e.surplus and 1 or 0.45, e.surplus and 0.45 or 1, 0.45)
    end

    -- contract form (tied to this item's contract station)
    local preview = DM:getContractPreview(it.idx, self.amount, math.min(self.months, math.floor(DM.CFG.maxMonths)))
    local boxTop = dy - 0.030
    local boxH = 0.330
    MFTheme.rrect(dx - 0.008, boxTop - boxH, rx - dx + 0.016, boxH, TH().box, 1, 0.006)
    local fy = boxTop - 0.026
    txt(dx, fy, 0.0165, DM.t("mf_new_contract"), TH().sub, nil, nil, nil, true)

    fy = fy - 0.026
    txt(dx, fy, 0.0145, DM.t("mf_contract_station"))
    if preview and preview.hasStation then
        txt(rx, fy, 0.0145, preview.stationName or "?", 0.45, 1, 0.5, RenderText.ALIGN_RIGHT, true)
    else
        txt(rx, fy, 0.0145, DM.t("mf_no_station"), 1, 0.45, 0.4, RenderText.ALIGN_RIGHT, true)
    end

    fy = fy - 0.030
    self:stepper(dx, rx, fy, DM.t("mf_amount"), g_i18n:formatNumber(self.amount) .. " L",
        {{label = "-50k", d = -50000}, {label = "-10k", d = -10000}, {label = "-1k", d = -1000},
         {label = "+1k", d = 1000}, {label = "+10k", d = 10000}, {label = "+50k", d = 50000}},
        function(d) self:changeAmount(d) end)
    fy = fy - 0.030
    self:stepper(dx, rx, fy, DM.t("mf_duration"), math.min(self.months, math.floor(DM.CFG.maxMonths)) .. " " .. DM.t("mf_months"),
        {{label = "-6", d = -6}, {label = "-1", d = -1}, {label = "+1", d = 1}, {label = "+6", d = 6}},
        function(d) self:changeDays(d) end)

    local disc = preview and preview.discount or 0
    local locked = preview and preview.locked or 0
    local offer = preview and preview.offset or 0
    local or_, og, ob = 1, 1, 1
    if offer > 0.0005 then or_, og, ob = 0.45, 1, 0.5 elseif offer < -0.0005 then or_, og, ob = 1, 0.45, 0.4 end
    local vsAvg = preview and preview.vsAvg or 0
    local vr, vg, vb = pctColor(vsAvg * 100)
    fy = fy - 0.027
    txt(dx, fy, 0.0145, DM.t("mf_stn_now")); txt(rx, fy, 0.0145, preview and money(preview.stationNow) or "-", 1, 1, 1, RenderText.ALIGN_RIGHT)
    fy = fy - 0.022
    txt(dx, fy, 0.0145, DM.t("mf_offer")); txt(rx, fy, 0.0145, string.format("%+.1f%%", offer * 100), or_, og, ob, RenderText.ALIGN_RIGHT, true)
    fy = fy - 0.022
    txt(dx, fy, 0.0145, DM.t("mf_discount")); txt(rx, fy, 0.0145, string.format("-%.1f%%", disc * 100), 1, 0.6, 0.5, RenderText.ALIGN_RIGHT)
    fy = fy - 0.022
    txt(dx, fy, 0.0145, DM.t("mf_locked")); txt(rx, fy, 0.0145, money(locked), 0.45, 1, 0.5, RenderText.ALIGN_RIGHT, true)
    fy = fy - 0.022
    txt(dx, fy, 0.0145, DM.t("mf_locked_vs_avg")); txt(rx, fy, 0.0145, string.format("%+.1f%%", vsAvg * 100), vr, vg, vb, RenderText.ALIGN_RIGHT)
    fy = fy - 0.022
    txt(dx, fy, 0.0145, DM.t("mf_total")); txt(rx, fy, 0.0145, money(locked * self.amount / 1000), 1, 1, 1, RenderText.ALIGN_RIGHT)

    local cooldown = preview and preview.cooldown or 0
    local signLabel = cooldown > 0 and string.format(DM.t("mf_cooldown_btn"), DM:cooldownToMonths(cooldown) .. " " .. DM.t("mf_months")) or DM.t("mf_sign_btn")
    self:button(dx, boxTop - boxH + 0.008, rx - dx, 0.028, signLabel, function() self:signContract() end,
        preview and preview.hasStation and cooldown == 0, 0.0150)

    -- price history graph in the free space below the contract box
    self:drawPriceGraph(dx, rx, boxTop - boxH - 0.012, y + 0.036, it.idx)
end

-- ---------- CATEGORY ROW (info box) ----------
-- shows which category the selected item belongs to; Edit opens the category window
function MFMenu:drawCategoryRow(dx, rx, y, it)
    if MFHud == nil or MFHud.catOverrides == nil then return end
    local ft = g_fillTypeManager:getFillTypeByIndex(it.idx)
    if ft == nil then return end
    local ov = MFHud.catOverrides[ft.name]
    local lab = DM.t("mf_cat_label")
    txt(dx, y + 0.005, fitSize(0.0145, lab, 0.060), lab)
    local label = self:catLabel(it.cat)
    local cr, cg, cb = 0.7, 0.7, 0.7
    if ov ~= nil then cr, cg, cb = TH().hi[1], TH().hi[2], TH().hi[3] end
    local bw = 0.052
    local nx = dx + 0.066
    txt(nx, y + 0.005, fitSize(0.0145, label, rx - bw - 0.008 - nx), label, cr, cg, cb, nil, ov ~= nil)
    local idx = it.idx
    self:button(rx - bw, y, bw, ROW_H, DM.t("mf_cat_edit"), function() self.catPopup = {idx = idx} end, false, 0.0125)
end

-- move an item to category ci (a click on the already-ticked box does nothing); the list follows the item
function MFMenu:setItemCategory(idx, ci)
    local ft = g_fillTypeManager:getFillTypeByIndex(idx)
    if ft == nil or MFHud == nil then return end
    local val
    if ci > OTHER_CAT then
        local c = MFHud.customCats[ci - OTHER_CAT]
        val = c ~= nil and c.id or nil
    elseif ci ~= categoryOf(ft) then
        val = CATEGORIES[ci].key
    end
    MFHud:setCatOverride(ft.name, val)
    self:recomputeCats()
    if self.category >= 4 then
        for _, it in ipairs(self.allItems) do
            if it.idx == idx then self.category = it.cat break end
        end
        self:applyFilter(idx)
        self:ensureVisible()
    end
end

function MFMenu:newCategory(idx)
    if #MFHud.customCats >= MAX_CUSTOM then self:setMsg(DM.t("mf_cat_max")) return end
    local ft = g_fillTypeManager:getFillTypeByIndex(idx)
    if ft == nil then return end
    local fname = ft.name
    local def = string.format(DM.t("mf_cat_default_name"), #MFHud.customCats + 1)
    self:beginNameEdit({default = def, idx = idx, onOk = function(name)
        local id = MFHud:addCustomCat(name)
        if id ~= nil then MFHud:setCatOverride(fname, id) end
    end})
end

function MFMenu:renameCategory(n, idx)
    local c = MFHud.customCats[n]
    if c == nil then return end
    local id = c.id
    self:beginNameEdit({default = c.name, idx = idx, onOk = function(name) MFHud:renameCustomCat(id, name) end})
end

-- the category window: every category with a checkbox for the one the item belongs to
function MFMenu:drawCategoryPopup()
    local pop = self.catPopup
    local ft = g_fillTypeManager:getFillTypeByIndex(pop.idx)
    local cur = 0
    for _, it in ipairs(self.allItems or {}) do
        if it.idx == pop.idx then cur = it.cat break end
    end
    local list = {4, 5, 6, 7, 8, 9}
    for n = 1, #MFHud.customCats do table.insert(list, OTHER_CAT + n) end
    table.insert(list, OTHER_CAT)

    local rh = 0.033
    local pw = 0.36
    local ph = 0.075 + #list * rh + 0.060
    local px, py = 0.5 - pw / 2, 0.5 - ph / 2

    drawFilledRect(0, 0, 1, 1, 0, 0, 0, 0.55)
    self:addHit(0, 0, 1, 1, function() self.catPopup = nil end)
    self:addHit(px, py, pw, ph, function() end)
    self.popupDraw = true

    MFTheme.rrect(px, py, pw, ph, TH().bg, 1, 0.008)
    MFTheme.rect(px + 0.012, py + ph - 0.052, pw - 0.024, 0.0014, TH().accent, 0.7)
    local title = string.format("%s - %s", ft and ft.title or "?", DM.t("mf_cat_label"))
    txt(px + 0.020, py + ph - 0.036, fitSize(0.0185, title, pw - 0.090), title, 1, 1, 1, nil, true)
    self:button(px + pw - 0.045, py + ph - 0.042, 0.028, 0.026, "X", function() self.catPopup = nil end, false, 0.0145)

    local top = py + ph - 0.078
    for r, ci in ipairs(list) do
        local ry = top - r * rh + 0.004
        if r % 2 == 0 then MFTheme.rect(px + 0.010, ry - 0.007, pw - 0.020, rh, TH().box, 0.45) end
        local target = ci
        local pick = function() self:setItemCategory(pop.idx, target) end
        self:rowBackground(px + 0.010, ry - 0.007, pw - 0.020, rh, false, pick)
        self:drawCheckbox(px + 0.034, ry, cur == ci, pick)
        local custom = ci > OTHER_CAT
        local nameW = pw - 0.080 - (custom and 0.110 or 0)
        local name = self:catLabel(ci)
        txt(px + 0.054, ry, fitSize(0.0140, name, nameW), name, cur == ci and 1 or 0.85, cur == ci and 1 or 0.85, cur == ci and 1 or 0.85, nil, cur == ci)
        if custom then
            local n = ci - OTHER_CAT
            local cid = MFHud.customCats[n].id
            self:button(px + pw - 0.128, ry - 0.003, 0.070, ROW_H - 0.003, DM.t("mf_cat_rename"), function() self:renameCategory(n, pop.idx) end, false, 0.0115)
            self:button(px + pw - 0.054, ry - 0.003, 0.028, ROW_H - 0.003, "X", function()
                MFHud:deleteCustomCat(cid)
                self:recomputeCats()
            end, false, 0.0115)
        end
    end

    local by = py + 0.014
    self:button(px + 0.020, by, 0.100, 0.028, DM.t("mf_cat_new"), function() self:newCategory(pop.idx) end, false, 0.0140)
    self:button(px + 0.128, by, 0.100, 0.028, DM.t("mf_cat_reset_item"), function()
        if ft ~= nil then self:setItemCategory(pop.idx, categoryOf(ft)) end
    end, false, 0.0140)
    self.popupDraw = false
end

-- ---------- NAME EDITOR (typing a category name inside the menu) ----------
-- While it is open the game's own controls are switched off: the menu moves to an empty input context, so
-- typed letters cannot walk the player, drive a vehicle or trigger any other key binding.
local NAME_KEYS = {"mf_cat_p1", "mf_cat_p2", "mf_cat_p3", "mf_cat_p4", "mf_cat_p5", "mf_cat_p6", "mf_cat_p7", "mf_cat_p8"}
local NAME_MAX = 16

local function splitChars(str)
    local t = {}
    for ch in string.gmatch(str or "", "[%z\1-\127\194-\244][\128-\191]*") do table.insert(t, ch) end
    return t
end

local function unicodeToStr(u)
    if u == nil or u < 32 or u == 127 then return nil end
    if u < 127 then return string.char(u) end
    local ok, str = pcall(function() return unicodeToUtf8(u) end)
    if ok and type(str) == "string" and str ~= "" then return str end
    return nil
end

function MFMenu:beginNameEdit(d)
    if self.nameEdit ~= nil then return end
    d.chars = splitChars(d.default)
    while #d.chars > NAME_MAX do table.remove(d.chars) end
    d.fresh = true   -- the first key typed replaces the suggested name
    d.ctx = pcall(function() g_inputBinding:setContext("MF_NAMING", true, false) end)
    pcall(function() g_inputBinding:setShowMouseCursor(true) end)
    if not d.ctx then
        pcall(function() Logging.info("[MarketsAndFutures] could not switch the input context for typing a name") end)
    end
    self.nameEdit = d
end

function MFMenu:endNameEdit(confirm)
    local d = self.nameEdit
    if d == nil then return end
    self.nameEdit = nil
    if d.ctx then pcall(function() g_inputBinding:revertContext(true) end) end
    pcall(function() g_inputBinding:setShowMouseCursor(self.isOpen == true) end)
    if confirm then
        local name = table.concat(d.chars)
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then name = d.default end
        d.onOk(name)
        self:recomputeCats()
    end
end

function MFMenu:nameEditKey(unicode, sym)
    local d = self.nameEdit
    if sym == Input.KEY_esc then self:endNameEdit(false) return end
    if sym == Input.KEY_return or sym == Input.KEY_KP_enter then self:endNameEdit(true) return end
    if sym == Input.KEY_backspace then
        if d.fresh then d.chars = {} d.fresh = false return end
        if #d.chars > 0 then table.remove(d.chars) end
        return
    end
    if Input.isKeyPressed(Input.KEY_lctrl) or Input.isKeyPressed(Input.KEY_rctrl) then return end
    local ch = unicodeToStr(unicode)
    if ch ~= nil then
        if d.fresh then d.chars = {} d.fresh = false end
        if #d.chars < NAME_MAX then table.insert(d.chars, ch) end
    end
end

function MFMenu:drawNameEditor()
    local d = self.nameEdit
    local pw, ph = 0.34, 0.330
    local px, py = 0.5 - pw / 2, 0.5 - ph / 2
    drawFilledRect(0, 0, 1, 1, 0, 0, 0, 0.55)
    self:addHit(0, 0, 1, 1, function() end)
    self:addHit(px, py, pw, ph, function() end)
    self.popupDraw = true
    MFTheme.rrect(px, py, pw, ph, TH().bg, 1, 0.008)
    MFTheme.rect(px + 0.012, py + ph - 0.052, pw - 0.024, 0.0014, TH().accent, 0.7)
    local title = DM.t("mf_cat_prompt")
    txt(px + 0.020, py + ph - 0.036, fitSize(0.0185, title, pw - 0.040), title, 1, 1, 1, nil, true)

    -- the text box
    local bx, by, bw, bh = px + 0.020, py + ph - 0.100, pw - 0.040, 0.034
    MFTheme.rrect(bx, by, bw, bh, TH().box, 1, 0.004)
    MFTheme.rect(bx, by, bw, 0.0012, TH().hi, 0.9)
    local str = table.concat(d.chars)
    local cursor = (g_time % 1000) < 500 and "|" or " "
    txt(bx + 0.008, by + 0.009, 0.0160, str .. cursor, 1, 1, 1)
    txt(bx + bw - 0.006, by + 0.0105, 0.0105, string.format("%d / %d", #d.chars, NAME_MAX), 0.6, 0.6, 0.6, RenderText.ALIGN_RIGHT)
    txt(px + 0.020, by - 0.020, 0.0115, DM.t("mf_cat_type_hint"), 0.7, 0.7, 0.7)

    -- suggested names: click to fill the box
    local cw, ch = (pw - 0.040 - 0.006) / 2, 0.026
    for i, key in ipairs(NAME_KEYS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local name = DM.t(key)
        self:button(px + 0.020 + col * (cw + 0.006), by - 0.050 - row * (ch + 0.004) - ch, cw, ch, name, function()
            d.fresh = false
            d.chars = splitChars(string.sub(name, 1, 24))
            while #d.chars > NAME_MAX do table.remove(d.chars) end
        end, false, 0.0125)
    end

    local fy = py + 0.014
    self:button(px + 0.020, fy, 0.100, 0.028, DM.t("mf_cat_ok"), function() self:endNameEdit(true) end, true, 0.0140)
    self:button(px + 0.128, fy, 0.100, 0.028, DM.t("mf_cat_cancel"), function() self:endNameEdit(false) end, false, 0.0140)
    self.popupDraw = false
end

-- ---------- PRICE HISTORY GRAPH ----------
local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

-- Game period 1 = March (northern hemisphere). If the game exposes a visual period that
-- differs from the logical period (southern hemisphere), that offset is applied.
local function getPeriodOffset()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and type(env.currentVisualPeriod) == "number" and type(env.currentPeriod) == "number" then
        return (env.currentVisualPeriod - env.currentPeriod) % 12
    end
    return 0
end

-- graph slot 1..12 = Jan..Dec  ->  game period
local function slotPeriod(j)
    local vis = (j - 3) % 12   -- 0-based visual period (March = 0)
    return (vis - getPeriodOffset()) % 12 + 1
end

MFMenu.slotPeriod = slotPeriod   -- also used by the HUD graph

function MFMenu:drawPriceGraph(dx, rx, top, bottom, idx)
    local gh = top - bottom
    if gh < 0.09 then return end
    local st = DM.fills[idx]
    MFTheme.rrect(dx - 0.008, bottom, rx - dx + 0.016, gh, TH().box, 1, 0.006)
    txt(dx, top - 0.020, 0.0150, DM.t("mf_graph_title"), TH().sub, nil, nil, nil, true)
    if st == nil or st.hist == nil then return end

    local base = DM:getBasePricePer1000(idx)
    local periodNow = DM:getCurrentPeriod()
    local live = base * st.mult
    txt(rx, top - 0.020, 0.0130, string.format("%s: %s", DM.t("mf_graph_now"), money(live)), 0.45, 1, 0.5, RenderText.ALIGN_RIGHT, true)
    txt(dx, top - 0.036, 0.0100, DM.t("mf_graph_legend"), 0.6, 0.6, 0.6)

    -- values per slot (January first)
    local vals, thisYear, nowSlot = {}, {}, 1
    for j = 1, 12 do
        local p = slotPeriod(j)
        vals[j] = base * st.hist[p]
        thisYear[j] = p <= periodNow
        if p == periodNow then nowSlot = j end
    end

    local lx = dx + 0.062
    local pw = rx - lx - 0.004
    local pyb = bottom + 0.028
    local pyt = top - 0.048
    local ph = pyt - pyb
    if ph <= 0.02 then return end

    local vmin, vmax = math.min(base, live), math.max(base, live)
    for j = 1, 12 do vmin, vmax = math.min(vmin, vals[j]), math.max(vmax, vals[j]) end
    local pad = math.max((vmax - vmin) * 0.12, base * 0.02)
    vmin, vmax = vmin - pad, vmax + pad
    local function ypos(v) return pyb + (v - vmin) / (vmax - vmin) * ph end
    local colW = pw / 12
    local function xpos(j) return lx + (j - 0.5) * colW end

    -- grid + y axis labels
    for g = 0, 2 do
        local v = vmin + (vmax - vmin) * g / 2
        local gy = ypos(v)
        drawFilledRect(lx, gy - 0.0004, pw, 0.0008, 0.35, 0.35, 0.35, 0.6)
        txt(lx - 0.006, gy - 0.004, 0.0105, money(v), 0.75, 0.75, 0.75, RenderText.ALIGN_RIGHT)
    end

    -- bars (bright = this year, dim = last year's value for periods not reached yet)
    for j = 1, 12 do
        local bx = lx + (j - 1) * colW + colW * 0.15
        local bh = ypos(vals[j]) - pyb
        if bh > 0 then
            if thisYear[j] then MFTheme.rect(bx, pyb, colW * 0.70, bh, TH().fill, 0.60)
            else drawFilledRect(bx, pyb, colW * 0.70, bh, 0.45, 0.55, 0.65, 0.28) end
        end
    end

    -- average price line
    local ay = ypos(base)
    drawFilledRect(lx, ay - 0.0007, pw, 0.0014, 1, 1, 1, 0.55)
    txt(lx + pw - 0.003, ay + 0.002, 0.0095, DM.t("mf_hd_price2"), 1, 1, 1, RenderText.ALIGN_RIGHT)

    -- line through the values
    for j = 1, 11 do
        local x1, y1 = xpos(j), ypos(vals[j])
        local x2, y2 = xpos(j + 1), ypos(vals[j + 1])
        local a = (thisYear[j] and thisYear[j + 1]) and 1 or 0.45
        for k = 0, 7 do
            local t = k / 8
            drawFilledRect(x1 + (x2 - x1) * t - 0.0009, y1 + (y2 - y1) * t - 0.0014, 0.0018, 0.0028, 1, 0.85, 0.3, a)
        end
    end
    for j = 1, 12 do
        drawFilledRect(xpos(j) - 0.0018, ypos(vals[j]) - 0.0032, 0.0036, 0.0064, 1, 0.85, 0.3, thisYear[j] and 1 or 0.5)
    end

    -- "now" marker
    local nx = xpos(nowSlot)
    drawFilledRect(nx - 0.0005, pyb, 0.001, ph, 0.45, 1, 0.5, 0.55)
    drawFilledRect(nx - 0.0035, ypos(live) - 0.0065, 0.007, 0.013, 1, 1, 1, 1)

    -- x axis labels (Jan..Dec)
    for j = 1, 12 do
        local cur = j == nowSlot
        txt(xpos(j), pyb - 0.015, 0.0092, MONTHS[j], cur and 0.45 or 0.7, cur and 1 or 0.7, cur and 0.5 or 0.7, RenderText.ALIGN_CENTER, cur)
    end
end

-- ---------- CONTRACTS TAB ----------
function MFMenu:drawContracts(x, y, w, h)
    local top = y + h - 0.080
    local cols = {0.015, 0.15, 0.30, 0.43, 0.54, 0.630, 0.705}
    txt(x + cols[1], top, 0.0125, DM.t("mf_col_item"), 0.7, 0.7, 0.7)
    txt(x + cols[2], top, 0.0125, DM.t("mf_col_station"), 0.7, 0.7, 0.7)
    txt(x + cols[3], top, 0.0125, DM.t("mf_remaining"), 0.7, 0.7, 0.7)
    txt(x + cols[4], top, 0.0125, DM.t("mf_locked"), 0.7, 0.7, 0.7)
    txt(x + cols[5], top, 0.0125, DM.t("mf_base"), 0.7, 0.7, 0.7)
    txt(x + cols[6], top, 0.0125, DM.t("mf_months_left"), 0.7, 0.7, 0.7)
    txt(x + cols[7], top, 0.0125, DM.t("mf_col_fee"), 0.7, 0.7, 0.7)
    txt(x + 0.015, y + 0.032, 0.0115, string.format(DM.t("mf_penalty_info"),
        math.floor(DM.CFG.cancelPenalty * 100 + 0.5), math.floor(DM.CFG.expiryPenalty * 100 + 0.5)), 0.75, 0.75, 0.75)

    -- free cancel status / progress toward the next one
    local perk = DM:getPerks(g_currentMission:getFarmId())
    local threshold = DM.CFG.freeCancelThreshold
    if perk.tokens > 0 then
        txt(x + 0.015, y + 0.056, 0.0135, DM.t("mf_free_ready"), 0.45, 1, 0.5, nil, true)
    else
        txt(x + 0.015, y + 0.056, 0.0125, string.format(DM.t("mf_free_progress"), money(perk.progress), money(threshold)), TH().sub, nil, nil)
        local bw = 0.16
        MFTheme.rect(x + 0.36, y + 0.0585, bw, 0.009, TH().track, 1)
        MFTheme.rect(x + 0.36, y + 0.0585, bw * math.min(1, perk.progress / threshold), 0.009, TH().fill, 1)
    end

    local list = DM:getFarmContracts(g_currentMission:getFarmId())
    if #list == 0 then
        txt(x + 0.015, top - 0.04, 0.016, DM.t("mf_no_contracts"), 0.8, 0.8, 0.8)
        return
    end
    self.cSel = math.min(math.max(self.cSel, 1), #list)
    local today = DM:getToday()
    local rh = ROW_H * 1.3
    for i, ct in ipairs(list) do
        if i > self.rows then break end
        local ry = top - i * rh - 0.004
        if i % 2 == 0 then MFTheme.rect(x + 0.008, ry - 0.005, w - 0.110, rh, TH().box, 0.45) end
        self:rowBackground(x + 0.008, ry - 0.005, w - 0.110, rh, i == self.cSel, function() self.cSel = i end)

        local ft = g_fillTypeManager:getFillTypeByIndex(ct.fillTypeIndex)
        local lock, cur = DM:getContractPrices(ct)
        local median = DM:getBasePricePer1000(ct.fillTypeIndex)
        local cr, cg, cb = pctColor((lock / math.max(median, 0.01) - 1) * 100)
        txt(x + cols[1], ry, 0.0140, ft and ft.title or "?")
        txt(x + cols[2], ry, 0.0130, ct.stationName ~= "" and ct.stationName or "?", TH().sub, nil, nil)
        txt(x + cols[3], ry, 0.0140, string.format("%s / %s L", g_i18n:formatNumber(math.floor(ct.remaining)), g_i18n:formatNumber(math.floor(ct.amount))))
        -- delivery progress bar
        do
            local frac = ct.amount > 0 and math.max(0, math.min(1, (ct.amount - ct.remaining) / ct.amount)) or 0
            local pbw = 0.115
            MFTheme.rrect(x + cols[3], ry - 0.0042, pbw, 0.0034, TH().track, 1, 0.0017)
            if frac > 0 then MFTheme.rrect(x + cols[3], ry - 0.0042, math.max(0.004, pbw * frac), 0.0034, TH().hi, 1, 0.0017) end
            txt(x + cols[3] + pbw + 0.004, ry - 0.0045, 0.0090, string.format("%d%%", math.floor(frac * 100 + 0.5)), 0.75, 0.75, 0.75)
        end
        txt(x + cols[4], ry, 0.0140, money(lock), cr, cg, cb, nil, true)
        txt(x + cols[5], ry, 0.0140, money(median))
        txt(x + cols[6], ry, 0.0140, string.format("%.1f", math.max(0, ct.endDay - today) / DM:getDaysPerMonth()))
        txt(x + cols[7], ry, 0.0140, money(DM.CFG.cancelPenalty * DM:getContractValue(ct, ct.remaining)), 1, 0.55, 0.45)
        local confirming = self.confirmId == ct.id and g_time - self.confirmTime < 4000
        self:button(x + w - 0.095, ry - 0.004, 0.080, rh - 0.003,
            confirming and DM.t("mf_confirm_btn") or DM.t("mf_cancel_btn"),
            function() self:requestCancelContract(ct) end, confirming, 0.0125)
        if perk.tokens > 0 then
            local fconfirm = self.freeConfirmId == ct.id and g_time - self.freeConfirmTime < 4000
            self:button(x + w - 0.185, ry - 0.004, 0.085, rh - 0.003,
                fconfirm and DM.t("mf_confirm_btn") or DM.t("mf_free_btn"),
                function() self:requestFreeCancel(ct) end, fconfirm, 0.0115)
        end
    end
end

-- ---------- ALL EVENTS TAB ----------
function MFMenu:drawEvents(x, y, w, h)
    local ty = y + h - 0.078
    local filters = {
        {"mf_filter_all", "all", 0.015, 0.060},
        {"mf_filter_surplus", "surplus", 0.080, 0.075},
        {"mf_filter_demand", "demand", 0.160, 0.075},
    }
    for _, f in ipairs(filters) do
        self:button(x + f[3], ty, f[4], ROW_H, DM.t(f[1]), function() self.evFilter = f[2]; self.eScroll = 0 end, self.evFilter == f[2], 0.0125)
    end

    local rows = self:getEventRows()
    txt(x + w - 0.02, ty + 0.006, 0.0135, string.format(DM.t("mf_events_count"), #rows), 0.7, 0.7, 0.7, RenderText.ALIGN_RIGHT)

    local hy = ty - 0.026
    local cols = {0.015, 0.22, 0.32, 0.44, 0.56, 0.69}
    txt(x + cols[1], hy, 0.0125, DM.t("mf_col_item"), 0.7, 0.7, 0.7)
    txt(x + cols[2], hy, 0.0125, DM.t("mf_col_type"), 0.7, 0.7, 0.7)
    txt(x + cols[3], hy, 0.0125, DM.t("mf_col_effect"), 0.7, 0.7, 0.7)
    txt(x + cols[4], hy, 0.0125, DM.t("mf_months_left"), 0.7, 0.7, 0.7)
    txt(x + cols[5], hy, 0.0125, DM.t("mf_base"), 0.7, 0.7, 0.7)
    txt(x + cols[6], hy, 0.0125, DM.t("mf_vs_median"), 0.7, 0.7, 0.7)

    if #rows == 0 then
        txt(x + 0.015, hy - 0.04, 0.016, DM.t("mf_no_events"), 0.8, 0.8, 0.8)
        return
    end
    self.eScroll = math.max(0, math.min(self.eScroll, math.max(0, #rows - self.rows)))

    for r = 1, self.rows do
        local e = rows[self.eScroll + r]
        if e == nil then break end
        local ry = hy - r * ROW_H - 0.004
        local idx = e.idx
        if r % 2 == 0 then MFTheme.rect(x + 0.008, ry - 0.004, w - 0.016, ROW_H, TH().box, 0.45) end
        self:rowBackground(x + 0.008, ry - 0.004, w - 0.016, ROW_H, false, function() self:jumpToItem(idx) end)

        local base = DM:getBasePricePer1000(e.idx)
        local pct = (e.mult - 1) * 100
        local er, eg, eb = e.surplus and 1 or 0.45, e.surplus and 0.45 or 1, 0.45
        local cr, cg, cb = pctColor(pct)
        txt(x + cols[1], ry, 0.0135, e.title)
        txt(x + cols[2], ry, 0.0135, (DM.t(e.surplus and "mf_surplus" or "mf_demand") .. (e.linked and DM.t("mf_linked_suffix") or "")), er, eg, eb, nil, true)
        txt(x + cols[3], ry, 0.0135, string.format("%+.0f%%", (e.factor - 1) * 100), er, eg, eb)
        txt(x + cols[4], ry, 0.0135, tostring(DM:daysToMonths(e.daysLeft)))
        txt(x + cols[5], ry, 0.0135, money(base), 0.8, 0.8, 0.8)
        txt(x + cols[6], ry, 0.0135, string.format("%+.0f%%", pct), cr, cg, cb)
    end
end

if InputHelpDisplay ~= nil and InputHelpDisplay.draw ~= nil then
    InputHelpDisplay.draw = Utils.overwrittenFunction(InputHelpDisplay.draw, function(element, superFunc, ...)
        if MFMenu.isOpen and not MFMenu.suspended then return end
        return superFunc(element, ...)
    end)
end

for _, fname in ipairs({"onInputLookLeftRight", "onInputLookUpDown"}) do
    if PlayerInputComponent ~= nil and type(PlayerInputComponent[fname]) == "function" then
        PlayerInputComponent[fname] = Utils.overwrittenFunction(PlayerInputComponent[fname], function(component, superFunc, ...)
            if MFMenu.isOpen then return end
            return superFunc(component, ...)
        end)
    end
end

-- Register the open/close action on foot and inside vehicles
if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil then
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents, MFMenu.registerOnFootActions)
end
if Enterable ~= nil and Enterable.onRegisterActionEvents ~= nil then
    Enterable.onRegisterActionEvents = Utils.appendedFunction(Enterable.onRegisterActionEvents, MFMenu.registerVehicleActions)
end

-- Makes sure our draw is the LAST thing in Gui.draw. Other mods (CoursePlay, AutoDrive, ...) append their own
-- HUD drawing to Gui.draw when they start, which can put them after us, so this is re-checked whenever the
-- menu opens (and every couple of seconds while it is open). Older wrappers switch themselves off.
function MFMenu:installLateHook()
    if Gui == nil or Gui.draw == nil then return end
    if Gui.draw == MFMenu.lateWrapper then return end
    MFMenu.hookGen = (MFMenu.hookGen or 0) + 1
    local gen = MFMenu.hookGen
    local wrapped = Utils.appendedFunction(Gui.draw, function()
        if gen == MFMenu.hookGen and MFMenu.isOpen and g_currentMission ~= nil then
            if MFMenu.globalStamp ~= nil and g_time - MFMenu.globalStamp < 150 then return end
            if not MFMenu.lateLogged then
                MFMenu.lateLogged = true
                Logging.info("[MarketsAndFutures] menu is being drawn by the late Gui.draw hook")
            end
            MFMenu.lateStamp = g_time
            MFMenu:drawPanel()
        end
    end)
    MFMenu.lateWrapper = wrapped
    Gui.draw = wrapped
end
MFMenu:installLateHook()

-- Wraps the engine's global draw() so the menu is drawn after EVERYTHING else in the frame, including HUDs that
-- other mods draw from their own mod-event-listener draw (those run after Gui.draw).
function MFMenu:installGlobalDrawHook()
    local G = _G
    if type(G.draw) ~= "function" then return end
    if G.draw == MFMenu.globalWrapper then return end
    MFMenu.globalGen = (MFMenu.globalGen or 0) + 1
    local gen = MFMenu.globalGen
    local orig = G.draw
    local wrapped = function(...)
        local r1, r2 = orig(...)
        if gen == MFMenu.globalGen and MFMenu.isOpen and g_currentMission ~= nil then
            if not MFMenu.globalLogged then
                MFMenu.globalLogged = true
                Logging.info("[MarketsAndFutures] menu is being drawn by the global draw hook (last in frame)")
            end
            MFMenu.globalStamp = g_time
            MFMenu:drawPanel()
        end
        return r1, r2
    end
    MFMenu.globalWrapper = wrapped
    G.draw = wrapped
end
MFMenu:installGlobalDrawHook()

-- Other mods' HUDs (CoursePlay, AutoDrive, TerminalAgricola, ...) are drawn after Gui.draw, so they end up over the
-- menu. While the menu is open their draw functions are skipped. Found by name (global tables whose name matches),
-- re-scanned whenever the menu opens because those mods may create their objects after this one loaded.
MFMenu.hudPatterns = {"[Cc]ourseplay", "^Cp", "AutoDrive", "^AD", "Terminal"}
MFMenu.hudFuncNames = {draw = true, drawHud = true, onDraw = true, drawHUD = true}
MFMenu.wrappedList = {}   -- {owner, fname, orig, wrapper} for every draw function currently wrapped
MFMenu.ourWrappers = {}   -- set of our wrapper functions, so we never wrap one twice

function MFMenu:wrapOtherHuds()
    local found = {}
    local function consider(owner, ownerName)
        if type(owner) ~= "table" then return end
        local names = {}
        for fname, f in pairs(owner) do
            if type(fname) == "string" and type(f) == "function" and (string.find(fname, "^[Dd]raw") or string.find(fname, "^on[Dd]raw")) then
                table.insert(names, fname)
            end
        end
        for _, fname in ipairs(names) do
            local f = rawget(owner, fname)
            if type(f) == "function" and not MFMenu.ourWrappers[f] then
                local orig = f
                local wrapper = function(...)
                    if MFMenu.isOpen and not MFMenu.suspended then return end
                    return orig(...)
                end
                local ok = pcall(function() owner[fname] = wrapper end)
                if ok then
                    MFMenu.ourWrappers[wrapper] = true
                    table.insert(MFMenu.wrappedList, {owner = owner, fname = fname, orig = orig, wrapper = wrapper})
                    table.insert(found, ownerName .. "." .. fname)
                end
            end
        end
    end
    -- Mods are found through the mod manager (pairs(_G) shows nothing from inside this mod), then each mod's
    -- environment table is looked up by name.
    local modNames = {}
    pcall(function()
        local list = {}
        if g_modManager ~= nil then
            if g_modManager.nameToMod ~= nil then
                for n, _ in pairs(g_modManager.nameToMod) do table.insert(list, n) end
            elseif g_modManager.getMods ~= nil then
                for _, m in ipairs(g_modManager:getMods()) do table.insert(list, m.modName) end
            end
        end
        for _, n in ipairs(list) do
            local low = string.lower(tostring(n))
            if n ~= g_currentModName and (string.find(low, "courseplay") or string.find(low, "autodrive")
                or string.find(low, "terminal") or string.find(low, "agricola")) then
                table.insert(modNames, n)
            end
        end
        MFMenu.modCount = #list
    end)
    local envLog = {}
    for _, n in ipairs(modNames) do
        local env
        pcall(function() env = _G[n] end)
        if type(env) == "table" then
            local count = 0
            pcall(function()
                for cname, class in pairs(env) do
                    if type(cname) == "string" and type(class) == "table" then
                        count = count + 1
                        consider(class, n .. "." .. cname)
                    end
                end
            end)
            table.insert(envLog, n .. "(env ok, " .. count .. " classes)")
        else
            table.insert(envLog, n .. "(no env)")
        end
    end
    if not MFMenu.envLogged then
        MFMenu.envLogged = true
        Logging.info("[MarketsAndFutures] mods seen: %s; matching: %s", tostring(MFMenu.modCount), table.concat(envLog, ", "))
    end
    pcall(function()
        for name, value in pairs(_G) do
            if type(name) == "string" and type(value) == "table" and value ~= MFMenu then
                local matches = false
                for _, p in ipairs(MFMenu.hudPatterns) do
                    if string.find(name, p) then matches = true break end
                end
                if matches and not string.find(name, "Markets") then
                    consider(value, name)
                    -- one level down for instances stored on the main table (e.g. g_Courseplay.hud)
                    for k, v in pairs(value) do
                        if type(k) == "string" and type(v) == "table" and v ~= value and (string.find(k, "[Hh]ud") or string.find(k, "[Dd]isplay")) then
                            consider(v, name .. "." .. k)
                        end
                    end
                end
            end
        end
    end)
    if #found > 0 then
        if not MFMenu.skipLogged then
            MFMenu.skipLogged = true
            Logging.info("[MarketsAndFutures] skipping %d draw functions from other mods while the menu is open", #found)
        end
    elseif not MFMenu.scanLogged then
        MFMenu.scanLogged = true
        Logging.info("[MarketsAndFutures] no other-HUD draw functions found to skip")
    end
end

-- Vehicle draw events: CoursePlay draws its HUD from onDrawUIInfo, AutoDrive from onDraw. Skipping the events while
-- the menu is open works without having to find those mods' classes. The wrapper (and the draw-function wrappers
-- from wrapOtherHuds) exist only while the menu is open, so they never sit in other mods' call stacks during play.
function MFMenu:installEventSkip()
    if SpecializationUtil == nil or SpecializationUtil.raiseEvent == nil then return end
    if SpecializationUtil.raiseEvent == MFMenu.eventWrapper then return end
    local origRaise = SpecializationUtil.raiseEvent
    local wrapper
    wrapper = function(vehicle, eventName, ...)
        if MFMenu.isOpen and not MFMenu.suspended and type(eventName) == "string"
            and (eventName == "onDraw" or eventName == "onDrawUIInfo" or eventName == "onDrawControlledVehicle") then
            if not MFMenu.evLogged then
                MFMenu.evLogged = true
                Logging.info("[MarketsAndFutures] skipping vehicle draw event %s while the menu is open", eventName)
            end
            return
        end
        return origRaise(vehicle, eventName, ...)
    end
    MFMenu.eventWrapper, MFMenu.eventOrig = wrapper, origRaise
    SpecializationUtil.raiseEvent = wrapper
end

function MFMenu:restoreHooks()
    -- put everything back, but only where nobody wrapped on top of ours in the meantime
    if MFMenu.eventWrapper ~= nil and SpecializationUtil ~= nil and SpecializationUtil.raiseEvent == MFMenu.eventWrapper then
        SpecializationUtil.raiseEvent = MFMenu.eventOrig
        MFMenu.eventWrapper, MFMenu.eventOrig = nil, nil
    end
    for k = #MFMenu.wrappedList, 1, -1 do
        local w = MFMenu.wrappedList[k]
        if rawget(w.owner, w.fname) == w.wrapper then
            pcall(function() w.owner[w.fname] = w.orig end)
            MFMenu.ourWrappers[w.wrapper] = nil
            table.remove(MFMenu.wrappedList, k)
        end
    end
end

addModEventListener(MFMenu)
