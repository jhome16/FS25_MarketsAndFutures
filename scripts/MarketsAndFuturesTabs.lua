-- Extra menu tabs: History, Alerts, Settings (added to MFMenu; loaded after MarketsAndFuturesMenu.lua)

local DM = MarketsAndFutures
local ROW_H = 0.0215

local function txt(x, y, size, s, r, g, b, align, bold)
    setTextBold(bold == true)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    if type(r) == "table" then r, g, b = r[1], r[2], r[3] end
    setTextColor(r or 1, g or 1, b or 1, 1)
    renderText(x, y, size, s)
end
local function TH() return MFTheme:get("menu") end
local function money(v) return g_i18n:formatMoney(v, 0, true, true) end
local function signedMoney(v)
    if v >= 0 then return "+" .. money(v) end
    return "-" .. money(-v)
end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- ===================== HISTORY =====================
local RESULT_KEYS = {"mf_res_fulfilled", "mf_res_cancelled", "mf_res_expired", "mf_res_free"}
local RESULT_COLORS = {{0.45, 1, 0.5}, {1, 0.55, 0.45}, {1, 0.55, 0.45}, {1, 0.9, 0.35}}

function MFMenu:drawHistory(x, y, w, h)
    local top = y + h - 0.080
    local cols = {0.015, 0.150, 0.255, 0.390, 0.480, 0.570, 0.665, 0.760}
    local heads = {"mf_col_item", "mf_col_result", "mf_col_delivered", "mf_locked", "mf_col_penalty", "mf_col_gain", "mf_col_net", "mf_col_day"}
    for i, key in ipairs(heads) do txt(x + cols[i], top, 0.0125, DM.t(key), 0.7, 0.7, 0.7) end

    local list = DM:getFarmHistory(g_currentMission:getFarmId())
    if #list == 0 then
        txt(x + 0.015, top - 0.04, 0.016, DM.t("mf_no_history"), 0.8, 0.8, 0.8)
        return
    end

    local rh = ROW_H * 1.1
    local visible = math.floor((top - (y + 0.06)) / rh)
    self.hScroll = clamp(self.hScroll, 0, math.max(0, #list - visible))
    for r = 1, visible do
        local rec = list[self.hScroll + r]
        if rec == nil then break end
        local ry = top - r * rh - 0.004
        if r % 2 == 0 then MFTheme.rect(x + 0.008, ry - 0.004, w - 0.016, rh, TH().box, 0.7) end

        local ft = g_fillTypeManager:getFillTypeByIndex(rec.fillTypeIndex)
        local rc = RESULT_COLORS[rec.result] or {1, 1, 1}
        local net = rec.gain - rec.penalty
        txt(x + cols[1], ry, 0.0135, ft and ft.title or "?")
        txt(x + cols[2], ry, 0.0135, DM.t(RESULT_KEYS[rec.result] or "mf_res_fulfilled"), rc[1], rc[2], rc[3], nil, true)
        txt(x + cols[3], ry, 0.0130, string.format("%s / %s L", g_i18n:formatNumber(math.floor(rec.delivered)), g_i18n:formatNumber(math.floor(rec.amount))))
        txt(x + cols[4], ry, 0.0135, money(rec.lockedPrice))
        txt(x + cols[5], ry, 0.0135, rec.penalty > 0.5 and ("-" .. money(rec.penalty)) or "-", 1, 0.55, 0.45)
        local gr, gg, gb = 1, 1, 1
        if rec.gain > 0.5 then gr, gg, gb = 0.45, 1, 0.5 elseif rec.gain < -0.5 then gr, gg, gb = 1, 0.55, 0.45 end
        txt(x + cols[6], ry, 0.0135, signedMoney(rec.gain), gr, gg, gb)
        local nr, ng, nb = 1, 1, 1
        if net > 0.5 then nr, ng, nb = 0.45, 1, 0.5 elseif net < -0.5 then nr, ng, nb = 1, 0.55, 0.45 end
        txt(x + cols[7], ry, 0.0135, signedMoney(net), nr, ng, nb, nil, true)
        txt(x + cols[8], ry, 0.0130, string.format("%s %d", DM.t("mf_col_day"), rec.day), 0.7, 0.7, 0.7)
        self:button(x + w - 0.095, ry - 0.004, 0.080, rh - 0.005, DM.t("mf_al_delete"), function() DM:requestDeleteHistory(rec.id) end, false, 0.0125)
    end

    -- totals over everything listed
    local gain, pen = 0, 0
    for _, rec in ipairs(list) do gain, pen = gain + rec.gain, pen + rec.penalty end
    txt(x + 0.015, y + 0.036, 0.0135, string.format(DM.t("mf_hist_totals"), #list, signedMoney(gain), money(pen), signedMoney(gain - pen)), 0.9, 0.9, 0.9, nil, true)
end

-- ===================== CHECKBOX (market list + alerts form) =====================
-- cx = horizontal centre, ry = text baseline of the row the box sits in
function MFMenu:drawCheckbox(cx, ry, checked, fn)
    local aspect = g_screenAspectRatio or 1.78
    local cbh = 0.0165
    local cbw = cbh / aspect
    local cbx, cby = cx - cbw / 2, ry - 0.0015
    drawFilledRect(cbx, cby, cbw, cbh, 0.75, 0.75, 0.75, 1)
    drawFilledRect(cbx + 0.0012 / aspect, cby + 0.0012, cbw - 0.0024 / aspect, cbh - 0.0024, 0.08, 0.11, 0.09, 1)
    if checked then
        drawFilledRect(cbx + 0.0030 / aspect, cby + 0.0030, cbw - 0.0060 / aspect, cbh - 0.0060, TH().hi[1], TH().hi[2], TH().hi[3], 1)
    end
    self:addHit(cbx - 0.003, ry - 0.004, cbw + 0.006, ROW_H, fn)
end

-- ===================== BLOCK STATIONS =====================
local function acceptedCount(station)
    local n = 0
    if station.acceptedFillTypes ~= nil then
        for _, v in pairs(station.acceptedFillTypes) do if v == true then n = n + 1 end end
    end
    return n
end

function MFMenu:drawBlock(x, y, w, h)
    local top = y + h - 0.080
    local editable = DM.isServer == true
    txt(x + 0.015, top, 0.0135, DM.t("mf_block_info"), 0.8, 0.8, 0.8)
    if not editable then txt(x + w - 0.02, top - 0.020, 0.0120, DM.t("mf_set_hostonly"), 1, 0.7, 0.4, RenderText.ALIGN_RIGHT) end

    -- automatic access check toggle
    local autoY = top - 0.044
    local autoFn = function()
        if editable then DM:setSetting("autoAccess", not DM.CFG.autoAccess)
        else self:setMsg(DM.t("mf_set_hostonly")) end
    end
    self:drawCheckbox(x + 0.030, autoY, DM.CFG.autoAccess == true, autoFn)
    txt(x + 0.050, autoY, 0.0140, DM.t("mf_block_auto"), 1, 1, 1)

    local hy = top - 0.080
    txt(x + 0.050, hy, 0.0125, DM.t("mf_block_station"), 0.7, 0.7, 0.7)
    txt(x + w - 0.140, hy, 0.0125, DM.t("mf_block_accepts"), 0.7, 0.7, 0.7, RenderText.ALIGN_RIGHT)

    local list = {}
    for _, s in ipairs(DM.stationList) do
        table.insert(list, {station = s, name = DM:getStationName(s), key = DM:getStationKey(s)})
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    if #list == 0 then
        txt(x + 0.015, hy - 0.040, 0.016, DM.t("mf_block_none"), 0.8, 0.8, 0.8)
        return
    end

    local rh = ROW_H * 1.1
    local visible = math.floor((hy - (y + 0.050)) / rh)
    self.bScroll = clamp(self.bScroll, 0, math.max(0, #list - visible))
    for r = 1, visible do
        local e = list[self.bScroll + r]
        if e == nil then break end
        local ry = hy - r * rh - 0.004
        local blocked = DM.blocked[e.key] == true
        if r % 2 == 0 then MFTheme.rect(x + 0.008, ry - 0.004, w - 0.016, rh, TH().box, 0.45) end
        local toggle = function()
            if editable then DM:setStationBlocked(e.key, not (DM.blocked[e.key] == true))
            else self:setMsg(DM.t("mf_set_hostonly")) end
        end
        self:rowBackground(x + 0.008, ry - 0.004, w - 0.016, rh, false, toggle)
        self:drawCheckbox(x + 0.030, ry, blocked, toggle)
        txt(x + 0.050, ry, 0.0135, e.name, blocked and 0.6 or 1, blocked and 0.6 or 1, blocked and 0.6 or 1)
        if not blocked and not DM:canFarmUseStation(e.station) then
            txt(x + w - 0.230, ry, 0.0130, DM.t("mf_block_noaccess"), 1, 0.7, 0.4, RenderText.ALIGN_RIGHT, true)
        end
        if blocked then
            txt(x + w - 0.230, ry, 0.0130, DM.t("mf_block_blocked"), 1, 0.45, 0.4, RenderText.ALIGN_RIGHT, true)
        end
        txt(x + w - 0.140, ry, 0.0130, string.format(DM.t("mf_block_items"), acceptedCount(e.station)), 0.8, 0.8, 0.8, RenderText.ALIGN_RIGHT)
    end
end

-- ===================== ALERTS =====================
-- One alert per item. A ticked item has an alert; the form below edits it live.
function MFMenu:syncAlertForm()
    local a = MFHud ~= nil and MFHud:getAlert(self.alertItem) or nil
    if a ~= nil then self.alertDir, self.alertPct = a.dir, a.pct end
    return a
end

function MFMenu:cycleAlertItem(step)
    local items = self.allItems
    if items == nil or #items == 0 then return end
    local cur = 1
    for i, it in ipairs(items) do
        if it.idx == self.alertItem then cur = i break end
    end
    self.alertItem = items[(cur - 1 + step) % #items + 1].idx
    self:syncAlertForm()
end

-- direction / threshold changes: stored in the form, and applied to the item's alert when it has one
function MFMenu:setAlertForm(dir, pct)
    self.alertDir, self.alertPct = dir, pct
    if MFHud ~= nil and self.alertItem ~= nil and MFHud:getAlert(self.alertItem) ~= nil then
        MFHud:setAlert(self.alertItem, dir, pct)
    end
end

-- tick / untick inside the Alerts tab
function MFMenu:toggleAlertActive()
    local idx = self.alertItem
    if MFHud == nil or idx == nil then return end
    if MFHud:getAlert(idx) ~= nil then
        MFHud:removeAlertFor(idx)
        self:setMsg(DM.t("mf_msg_alert_removed"))
    else
        local ok, met = MFHud:setAlert(idx, self.alertDir, self.alertPct)
        if not ok then self:setMsg(DM.t("mf_msg_alert_limit"))
        elseif met then self:setMsg(DM.t("mf_msg_alert_added_met"))
        else self:setMsg(DM.t("mf_msg_alert_added")) end
    end
end

-- tick / untick in the Market list: ticking jumps to the Alerts tab for that item
function MFMenu:toggleAlertFromList(idx)
    if MFHud == nil then return end
    if MFHud:getAlert(idx) ~= nil then
        MFHud:removeAlertFor(idx)
        self:setMsg(DM.t("mf_msg_alert_removed"))
        return
    end
    self.alertItem = idx
    local ok, met = MFHud:setAlert(idx, self.alertDir, self.alertPct)
    if not ok then
        self:setMsg(DM.t("mf_msg_alert_limit"))
        return
    end
    self.tab = 5
    self:setMsg(DM.t(met and "mf_msg_alert_added_met" or "mf_msg_alert_added_edit"))
end

function MFMenu:drawAlerts(x, y, w, h)
    if self.alertItem == nil or DM.fills[self.alertItem] == nil then
        local sel = self.items[self.sel]
        self.alertItem = sel and sel.idx or next(DM.fills)
        self:syncAlertForm()
    end
    local idx = self.alertItem
    local ft = idx and g_fillTypeManager:getFillTypeByIndex(idx)
    local st = idx and DM.fills[idx]
    local alert = MFHud ~= nil and idx ~= nil and MFHud:getAlert(idx) or nil

    local lx = x + 0.025
    local cx = x + 0.28
    local y1 = y + h - 0.098
    local boxH = 0.150
    MFTheme.rect(x + 0.012, y1 - boxH + 0.034, w - 0.024, boxH, TH().box, 1)

    -- item picker
    txt(lx, y1 + 0.005, 0.0145, DM.t("mf_al_item"))
    self:button(cx, y1, 0.030, ROW_H, "<", function() self:cycleAlertItem(-1) end, false, 0.0140)
    txt(cx + 0.030 + 0.095, y1 + 0.005, 0.0150, ft and ft.title or "-", TH().hi, nil, nil, RenderText.ALIGN_CENTER, true)
    self:button(cx + 0.220, y1, 0.030, ROW_H, ">", function() self:cycleAlertItem(1) end, false, 0.0140)
    if st ~= nil and MFHud ~= nil then
        local nowPct, nowPrice = MFHud:getAlertNow(idx)
        txt(cx + 0.270, y1 + 0.005, 0.0140, string.format("%s: %s  (%+.1f%% %s)", DM.t("mf_al_now"),
            money(nowPrice), nowPct, DM.t("mf_vs_median")), TH().sub, nil, nil)
    end

    -- alert on / off checkbox
    local y2 = y1 - 0.034
    txt(lx, y2 + 0.005, 0.0145, DM.t("mf_al_active"))
    self:drawCheckbox(cx + 0.015, y2, alert ~= nil, function() self:toggleAlertActive() end)
    txt(cx + 0.040, y2 + 0.005, 0.0125, DM.t(alert and "mf_al_hint_on" or "mf_al_hint_off"), alert and 0.45 or 0.7, alert and 1 or 0.7, alert and 0.5 or 0.7)

    -- direction
    local y3 = y2 - 0.034
    local dir = alert and alert.dir or self.alertDir
    local pct = alert and alert.pct or self.alertPct
    txt(lx, y3 + 0.005, 0.0145, DM.t("mf_al_when"))
    self:button(cx, y3, 0.110, ROW_H, DM.t("mf_al_rises"), function()
        self:setAlertForm(1, pct < 0 and 10 or pct)
    end, dir > 0, 0.0135)
    self:button(cx + 0.115, y3, 0.110, ROW_H, DM.t("mf_al_falls"), function()
        self:setAlertForm(-1, pct > 0 and -10 or pct)
    end, dir < 0, 0.0135)
    if idx ~= nil then
        txt(cx + 0.270, y3 + 0.005, 0.0140, string.format("%s: %s", DM.t("mf_al_triggers_at"),
            money(DM:getBasePricePer1000(idx) * (1 + pct / 100))), TH().hi, nil, nil, nil, true)
    end

    -- threshold
    local y4 = y3 - 0.034
    self:stepper(lx, cx + 0.254, y4, DM.t("mf_al_threshold"), string.format("%+d%%", pct),
        {{label = "-10", d = -10}, {label = "-5", d = -5}, {label = "-1", d = -1}, {label = "+1", d = 1}, {label = "+5", d = 5}, {label = "+10", d = 10}},
        function(d) self:setAlertForm(dir, clamp(pct + d, -50, 100)) end)
    txt(cx + 0.270, y4 + 0.005, 0.0125, string.format("%d / %d", MFHud and #MFHud.alerts or 0, MFHud and MFHud.maxAlerts or 0), 0.6, 0.6, 0.6)

    -- list of alerts
    local top = y1 - boxH + 0.004
    local cols = {0.015, 0.165, 0.285, 0.390, 0.495, 0.590, 0.690}
    txt(x + cols[1], top, 0.0125, DM.t("mf_col_item"), 0.7, 0.7, 0.7)
    txt(x + cols[2], top, 0.0125, DM.t("mf_al_cond"), 0.7, 0.7, 0.7)
    local function head(i, key, size, maxW)
        local t = DM.t(key)
        local tw = getTextWidth(size, t)
        if tw > maxW then size = size * maxW / tw end
        txt(x + cols[i], top, size, t, 0.7, 0.7, 0.7)
    end
    head(3, "mf_al_now", 0.0125, 0.100)
    head(4, "mf_al_trigger", 0.0125, 0.100)
    head(5, "mf_base", 0.0125, 0.090)
    txt(x + cols[6], top, 0.0108, DM.t("mf_best_vs_median"), 0.7, 0.7, 0.7)
    txt(x + cols[7], top, 0.0125, DM.t("mf_al_status"), 0.7, 0.7, 0.7)

    local alerts = MFHud and MFHud.alerts or {}
    if #alerts == 0 then
        txt(x + 0.015, top - 0.04, 0.016, DM.t("mf_al_none"), 0.8, 0.8, 0.8)
        return
    end
    local rh = ROW_H * 1.2
    local visible = math.floor((top - (y + 0.04)) / rh)
    self.alScroll = clamp(self.alScroll, 0, math.max(0, #alerts - visible))
    for r = 1, visible do
        local i = self.alScroll + r
        local a = alerts[i]
        if a == nil then break end
        local ry = top - r * rh - 0.004
        local aidx = g_fillTypeManager:getFillTypeIndexByName(a.name)
        local aft = aidx and g_fillTypeManager:getFillTypeByIndex(aidx)
        local ast = aidx and DM.fills[aidx]
        if r % 2 == 0 then MFTheme.rect(x + 0.008, ry - 0.005, w - 0.110, rh, TH().box, 0.45) end
        local pulse = 0.5 + 0.5 * math.sin(g_time / 330)
        if a.fired then   -- triggered alerts glow gently
            MFTheme.rrect(x + 0.008, ry - 0.005, w - 0.110, rh, TH().hi, 0.06 + 0.14 * pulse, 0.003)
            MFTheme.rect(x + 0.008, ry - 0.005 + rh * 0.15, 0.0022, rh * 0.7, TH().hi, 0.5 + 0.5 * pulse)
        end
        self:rowBackground(x + 0.008, ry - 0.005, w - 0.110, rh, aidx == self.alertItem, function()
            if aidx ~= nil then self.alertItem = aidx; self:syncAlertForm() end
        end)

        local nameSize = 0.0138
        local nameStr = aft and aft.title or a.name
        local nameW = getTextWidth(nameSize, nameStr)
        if nameW > cols[2] - cols[1] - 0.006 then nameSize = nameSize * (cols[2] - cols[1] - 0.006) / nameW end
        txt(x + cols[1], ry, nameSize, nameStr)
        local condStr = string.format(DM.t(a.dir > 0 and "mf_al_cond_up" or "mf_al_cond_down"), string.format("%+.0f%%", a.pct))
        local condSize = 0.0135
        local condW = getTextWidth(condSize, condStr)
        if condW > cols[3] - cols[2] - 0.006 then condSize = condSize * (cols[3] - cols[2] - 0.006) / condW end
        txt(x + cols[2], ry, condSize, condStr, TH().sub, nil, nil)
        if aidx ~= nil then
            local _, bestPrice = MFHud:getAlertNow(aidx)
            txt(x + cols[3], ry, 0.0135, money(bestPrice), 1, 0.9, 0.35, nil, true)
            txt(x + cols[4], ry, 0.0135, money(DM:getBasePricePer1000(aidx) * (1 + a.pct / 100)), TH().hi, nil, nil, nil, true)
        else
            txt(x + cols[3], ry, 0.0135, "-", 0.6, 0.6, 0.6)
            txt(x + cols[4], ry, 0.0135, "-", 0.6, 0.6, 0.6)
        end
        if ast ~= nil then
            local ap = MFHud:getAlertNow(aidx)
            local ar, ag, ab = 1, 1, 1
            if ap >= 3 then ar, ag, ab = 0.45, 1, 0.5 elseif ap <= -3 then ar, ag, ab = 1, 0.45, 0.4 end
            txt(x + cols[5], ry, 0.0135, money(DM:getBasePricePer1000(aidx)), 0.8, 0.8, 0.8)
            txt(x + cols[6], ry, 0.0135, string.format("%+.1f%%", ap), ar, ag, ab)
        else
            txt(x + cols[5], ry, 0.0135, "-", 0.6, 0.6, 0.6)
        end
        if a.fired then txt(x + cols[7], ry, 0.0135, DM.t("mf_al_status_trig"), 0.45 + 0.4 * pulse, 1, 0.5 + 0.4 * pulse, nil, true)
        else txt(x + cols[7], ry, 0.0135, DM.t("mf_al_status_wait"), 0.7, 0.7, 0.7) end
        if a.fired and not a.dismissed then
            self:button(x + w - 0.185, ry - 0.004, 0.080, rh - 0.005, DM.t("mf_al_clear"), function() MFHud:dismissAlert(i) end, true, 0.0125)
        end
        self:button(x + w - 0.095, ry - 0.004, 0.080, rh - 0.005, DM.t("mf_al_delete"), function() MFHud:removeAlert(i) end, false, 0.0125)
    end
end

-- ===================== SETTINGS =====================
function MFMenu:drawSettings(x, y, w, h)
    local c = DM.CFG
    local editable = DM.isServer == true
    local function statRow(dx, rx, yy, label, valueStr, steps, fn)
        if editable then self:stepper(dx, rx, yy, label, valueStr, steps, fn)
        else
            txt(dx, yy + 0.005, 0.0145, label)
            txt(rx, yy + 0.005, 0.0145, valueStr, 1, 1, 1, RenderText.ALIGN_RIGHT, true)
        end
    end
    local function pctSteps(a, b)
        return {{label = "-" .. a, d = -a}, {label = "-" .. b, d = -b}, {label = "+" .. b, d = b}, {label = "+" .. a, d = a}}
    end

    -- ---------- market settings (host) ----------
    local dx, rx = x + 0.025, x + 0.520
    local yy = y + h - 0.090
    txt(dx, yy, 0.0170, DM.t("mf_set_market"), TH().sub, nil, nil, nil, true)
    if not editable then txt(rx, yy, 0.0120, DM.t("mf_set_hostonly"), 1, 0.7, 0.4, RenderText.ALIGN_RIGHT) end

    yy = yy - 0.036
    txt(dx, yy + 0.005, 0.0145, DM.t("mf_set_preset"))
    local px = rx - 0.280
    for i = 1, 3 do
        local idx = i
        local label = DM.t("mf_preset_" .. i)
        if editable then
            self:button(px + (i - 1) * 0.095, yy, 0.090, ROW_H, label, function() DM:applyPreset(idx) end, c.preset == i, 0.0135)
        else
            local on = c.preset == i
            txt(px + (i - 1) * 0.095 + 0.045, yy + 0.005, 0.0135, label, on and 0.45 or 0.6, on and 1 or 0.6, on and 0.5 or 0.6, RenderText.ALIGN_CENTER, on)
        end
    end
    if c.preset == 0 then txt(dx + 0.150, yy + 0.005, 0.0125, "(" .. DM.t("mf_preset_0") .. ")", TH().hi, nil, nil) end

    local rows = 0.034
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_chance"), string.format("%d%%", math.floor(c.dailyEventChance * 100 + 0.5)), pctSteps(5, 1),
        function(d) DM:setSetting("dailyEventChance", c.dailyEventChance + d / 100) end)
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_strength"), string.format("%.2fx", c.eventScale),
        {{label = "-.25", d = -0.25}, {label = "-.1", d = -0.1}, {label = "+.1", d = 0.1}, {label = "+.25", d = 0.25}},
        function(d) DM:setSetting("eventScale", c.eventScale + d) end)
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_drift"), string.format("%.1f%%", c.trendNoise * 100),
        {{label = "-1%", d = -0.01}, {label = "-.5%", d = -0.005}, {label = "+.5%", d = 0.005}, {label = "+1%", d = 0.01}},
        function(d) DM:setSetting("trendNoise", c.trendNoise + d) end)

    yy = yy - rows
    txt(dx, yy + 0.005, 0.0145, DM.t("mf_set_links"))
    if editable then
        self:button(rx - 0.090, yy, 0.090, ROW_H, DM.t(c.linkEnabled and "mf_on" or "mf_off"), function() DM:setSetting("linkEnabled", not c.linkEnabled) end, c.linkEnabled, 0.0135)
    else
        txt(rx, yy + 0.005, 0.0145, DM.t(c.linkEnabled and "mf_on" or "mf_off"), 1, 1, 1, RenderText.ALIGN_RIGHT, true)
    end
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_link_strength"), string.format("%d%%", math.floor(c.linkStrength * 100 + 0.5)), pctSteps(20, 10),
        function(d) DM:setSetting("linkStrength", c.linkStrength + d / 100) end)

    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_cancel"), string.format("%d%%", math.floor(c.cancelPenalty * 100 + 0.5)), pctSteps(5, 1),
        function(d) DM:setSetting("cancelPenalty", c.cancelPenalty + d / 100) end)
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_expiry"), string.format("%d%%", math.floor(c.expiryPenalty * 100 + 0.5)), pctSteps(5, 1),
        function(d) DM:setSetting("expiryPenalty", c.expiryPenalty + d / 100) end)
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_wait"), string.format("%d %s", c.contractCooldownMonths, DM.t("mf_months")),
        {{label = "-6", d = -6}, {label = "-1", d = -1}, {label = "+1", d = 1}, {label = "+6", d = 6}},
        function(d) DM:setSetting("contractCooldownMonths", c.contractCooldownMonths + d) end)
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_free"), money(c.freeCancelThreshold),
        {{label = "-50k", d = -50000}, {label = "-10k", d = -10000}, {label = "+10k", d = 10000}, {label = "+50k", d = 50000}},
        function(d) DM:setSetting("freeCancelThreshold", c.freeCancelThreshold + d) end)
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_maxmonths"), string.format("%d %s", math.floor(c.maxMonths + 0.5), DM.t("mf_months")),
        {{label = "-6", d = -6}, {label = "-1", d = -1}, {label = "+1", d = 1}, {label = "+6", d = 6}},
        function(d) DM:setSetting("maxMonths", c.maxMonths + d) end)
    local feeSteps = {{label = "-.5", d = -0.5}, {label = "-.25", d = -0.25}, {label = "+.25", d = 0.25}, {label = "+.5", d = 0.5}}
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_fee_amount"), string.format("%.2fx", c.feeAmountMult), feeSteps,
        function(d) DM:setSetting("feeAmountMult", c.feeAmountMult + d) end)
    txt(dx + getTextWidth(0.0145, DM.t("mf_set_fee_amount")) + 0.008, yy + 0.006, 0.0105,
        string.format("%.2f%% / %s", DM.CFG.discountPerValue * c.feeAmountMult * 100, g_i18n:formatMoney(DM.CFG.valueStep, 0, true, true)), 0.6, 0.6, 0.6)
    yy = yy - rows
    statRow(dx, rx, yy, DM.t("mf_set_fee_duration"), string.format("%.2fx", c.feeDurationMult), feeSteps,
        function(d) DM:setSetting("feeDurationMult", c.feeDurationMult + d) end)
    txt(dx + getTextWidth(0.0145, DM.t("mf_set_fee_duration")) + 0.008, yy + 0.006, 0.0105,
        string.format("%.3f%% / %s", DM.CFG.discountPerMonth * c.feeDurationMult * 100, DM.t("mf_month")), 0.6, 0.6, 0.6)

    -- restore all market settings to their defaults (asks twice)
    yy = yy - rows - 0.006
    if editable then
        local confirming = self.resetConfirm ~= nil and g_time - self.resetConfirm < 4000
        self:button(rx - 0.200, yy, 0.200, ROW_H, DM.t(confirming and "mf_confirm_btn" or "mf_set_defaults"), function()
            if confirming then
                self.resetConfirm = nil
                DM:resetSettings()
                self:setMsg(DM.t("mf_msg_reset_done"))
            else
                self.resetConfirm = g_time
                self:setMsg(DM.t("mf_msg_reset_confirm"))
            end
        end, confirming, 0.0135)
    end

    drawFilledRect(x + 0.540, y + 0.050, 0.002, h - 0.120, 0.3, 0.3, 0.3, 1)

    -- ---------- HUD settings (this player only) ----------
    if MFHud == nil then return end
    local hx, hrx = x + 0.565, x + w - 0.025
    local hy = y + h - 0.090
    txt(hx, hy, 0.0170, DM.t("mf_set_hud"), TH().sub, nil, nil, nil, true)

    hy = hy - 0.036
    txt(hx, hy + 0.005, 0.0145, DM.t("mf_tab_hud_show"))
    self:button(hrx - 0.090, hy, 0.090, ROW_H, DM.t(MFHud.cfg.visible and "mf_on" or "mf_off"), function() MFHud:setVisible(not MFHud.cfg.visible) end, MFHud.cfg.visible, 0.0135)

    hy = hy - rows
    self:stepper(hx, hrx, hy, DM.t("mf_set_hud_rotate"), string.format("%d s", MFHud.cfg.rotate),
        {{label = "-1", d = -1}, {label = "+1", d = 1}},
        function(d) MFHud.cfg.rotate = clamp(MFHud.cfg.rotate + d, 1, 15); MFHud:save() end)
    hy = hy - rows
    self:stepper(hx, hrx, hy, DM.t("mf_set_hud_opacity"), string.format("%d%%", math.floor(MFHud.cfg.alpha * 100 + 0.5)),
        {{label = "-10", d = -0.1}, {label = "+10", d = 0.1}},
        function(d) MFHud.cfg.alpha = clamp(math.floor((MFHud.cfg.alpha + d) * 100 + 0.5) / 100, 0.2, 1); MFHud:save() end)
    hy = hy - rows
    self:stepper(hx, hrx, hy, DM.t("mf_set_hud_size"), string.format("%d%%", math.floor(MFHud.cfg.scale * 100 + 0.5)),
        {{label = "-25", d = -0.25}, {label = "-5", d = -0.05}, {label = "+5", d = 0.05}, {label = "+25", d = 0.25}},
        function(d) MFHud:setScale(math.floor((MFHud.cfg.scale + d) * 100 + 0.5) / 100) end)
    hy = hy - rows
    local soundOn = MFHud.cfg.alertSound ~= false
    self:button(hrx - 0.345, hy, 0.140, ROW_H, DM.t("mf_set_alert_sound") .. ": " .. DM.t(soundOn and "mf_on" or "mf_off"),
        function() MFHud.cfg.alertSound = not soundOn; MFHud:save() end, soundOn, 0.0125)
    self:button(hrx - 0.200, hy, 0.200, ROW_H, DM.t("mf_set_hud_reset"), function() MFHud:resetPosition(); self:setMsg(DM.t("mf_msg_hud_reset")) end, false, 0.0135)

    hy = hy - 0.050
    txt(hx, hy, 0.0125, DM.t("mf_set_hud_help1"), 0.75, 0.75, 0.75)
    hy = hy - 0.022
    txt(hx, hy, 0.0125, DM.t("mf_set_hud_help2"), 0.75, 0.75, 0.75)

    -- ---------- appearance (colour themes, this player only) ----------
    local P = TH()
    local span = hrx - hx
    local function swatch(sx, sy, sw, sh, pal, selected, fn)
        local hov = self:hover(sx, sy, sw, sh)
        drawFilledRect(sx - 0.0013, sy - 0.0020, sw + 0.0026, sh + 0.0040, selected and 1 or (hov and 0.7 or 0.28), selected and 1 or (hov and 0.7 or 0.28), selected and 1 or (hov and 0.7 or 0.28), 1)
        MFTheme.rect(sx, sy, sw, sh, pal.bg, 1)
        MFTheme.rect(sx, sy + sh * 0.30, sw * 0.62, sh * 0.70, pal.tint, 1)
        MFTheme.rect(sx + sw * 0.62, sy + sh * 0.30, sw * 0.38, sh * 0.70, pal.hi, 1)
        MFTheme.rect(sx, sy, sw, sh * 0.12, pal.accent, 1)
        self:addHit(sx, sy, sw, sh, fn)
    end

    hy = hy - 0.048
    txt(hx, hy, 0.0170, DM.t("mf_set_style"), TH().sub, nil, nil, nil, true)
    hy = hy - 0.030
    txt(hx, hy + 0.005, 0.0145, DM.t("mf_set_menu_style"))
    txt(hrx, hy + 0.005, 0.0145, MFTheme:presetName(MFTheme.menuPreset), TH().hi, nil, nil, RenderText.ALIGN_RIGHT, true)
    local perRow, gap = 7, 0.005
    local sw, sh = (span - gap * (perRow - 1)) / perRow, 0.024
    for i = 1, #MFTheme.PRESETS do
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        local pi = i
        swatch(hx + col * (sw + gap), hy - 0.034 - row * 0.034, sw, sh, MFTheme:palette(pi), MFTheme.menuPreset == pi, function() MFTheme:setMenu(pi) end)
    end
    hy = hy - 0.034 - 0.034 - 0.040
    local hudName = MFTheme.hudPreset == 0 and DM.t("mf_theme_same") or MFTheme:presetName(MFTheme.hudPreset)
    self:stepper(hx, hrx, hy, DM.t("mf_set_hud_style"), hudName,
        {{label = "<", d = -1}, {label = ">", d = 1}}, function(d) MFTheme:stepHud(d) end)

    hy = hy - rows
    txt(hx, hy + 0.005, 0.0145, DM.t("mf_set_accent"))
    local aw = 0.050
    self:button(hx + 0.140, hy, aw, ROW_H, DM.t("mf_theme_auto"), function() MFTheme:setAccent(0) end, MFTheme.accent == 0, 0.0125)
    local nA = #MFTheme.ACCENTS
    local ax0 = hx + 0.140 + aw + 0.006
    local aSw = (hrx - ax0 - 0.004 * (nA - 1)) / nA
    for i = 1, nA do
        local c = MFTheme.ACCENTS[i]
        local ai = i
        swatch(ax0 + (i - 1) * (aSw + 0.004), hy + 0.0015, aSw, ROW_H - 0.003, {bg = c, tint = c, hi = c, accent = c}, MFTheme.accent == ai, function() MFTheme:setAccent(ai) end)
    end

    hy = hy - rows
    self:stepper(hx, hrx, hy, DM.t("mf_set_bright"), string.format("%d%%", MFTheme.bright),
        {{label = "-10", d = -10}, {label = "+10", d = 10}}, function(d) MFTheme:stepBright(d) end)
    hy = hy - rows
    local function fitTo(label, size, maxW)
        local tw = getTextWidth(size, label)
        return tw > maxW and size * maxW / tw or size
    end
    local rw = 0.170   -- two reset buttons side by side must fit between the right panel's edges (and clear the divider)
    local lblA, lblC = DM.t("mf_set_style_reset"), DM.t("mf_cat_reset")
    self:button(hrx - rw, hy, rw, ROW_H, lblA, function() MFTheme:reset() end, false, fitTo(lblA, 0.0135, rw - 0.012))
    local armed = self.catResetArm ~= nil and g_time - self.catResetArm < 4000
    self:button(hrx - 2 * rw - 0.006, hy, rw, ROW_H, lblC, function()
        if armed then
            self.catResetArm = nil
            MFHud:resetCategories()
            self:recomputeCats()
            self:setMsg(DM.t("mf_msg_cat_reset"))
        else
            self.catResetArm = g_time
            self:setMsg(DM.t("mf_cat_reset_confirm"))
        end
    end, armed, fitTo(lblC, 0.0135, rw - 0.012))
end
