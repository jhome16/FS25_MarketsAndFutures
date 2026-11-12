-- Markets and Futures & Contracts (FS25)
-- Server simulates market multipliers + contracts, clients are synced via events.

MarketsAndFutures = {}
MarketsAndFutures.modName = g_currentModName
MarketsAndFutures.modDir = g_currentModDirectory

-- ===================== TUNING =====================
MarketsAndFutures.CFG = {
    minMult = 0.50, maxMult = 2.00,
    hourlyBlend = 0.20,
    trendPull = 0.12, trendNoise = 0.035,
    trendMin = 0.85, trendMax = 1.15,
    dailyEventChance = 0.03,   -- chance per game month that an item gets a new event
    maxEventsPerFill = 2,
    surplusMin = 0.60, surplusMax = 0.85,
    demandMin = 1.15, demandMax = 1.50,
    eventMinMonths = 3, eventMaxMonths = 14,   -- event length in game months (converted to days with the days-per-month setting)
    announceBelow = 0.72, announceAbove = 1.35,
    minAmount = 1000, maxAmount = 500000,
    minMonths = 1, maxMonths = 48,      -- contract length is chosen in game months (host can set the maximum from 1 to 120)
    discountPerMonth = 0.00125,          -- duration part of the contract fee, per month
    discountPerValue = 0.01,             -- quantity part of the contract fee: 1% per valueStep of contract value (pre-fee locked price x amount)
    valueStep = 125000,
    maxQuantityFee = 0.15,               -- cap for the quantity part (scaled by the host's quantity multiplier)
    maxDiscount = 0.50,                  -- cap for the whole contract fee (default rates reach at most 15% + 6% = 21%)
    feeAmountMult = 1.0, feeDurationMult = 1.0,   -- adjustable multipliers for the quantity / duration part of the contract fee
    maxContractsPerFarm = 20,
    -- per-item contract rate: each item gets its own offer between -offsetMax and +offsetMax that
    -- slowly drifts (hourly random walk pulled back toward 0). Applied on top of the contract fee.
    offsetMax = 0.25, offsetPull = 0.0035, offsetNoise = 0.014,
    -- after a contract is signed for an item, no new contract for that item can be signed for this many game months
    contractCooldownMonths = 6,
    -- penalties (fraction of the still-undelivered contract value, at the locked price), for cancelling and for expiring
    cancelPenalty = 0.15, expiryPenalty = 0.15,
    -- free cancel: earned after this much contract value has been delivered; only one can be stored at a time
    freeCancelThreshold = 500000,
    -- delivery notifications are batched: shown this many ms after the last delivery to a contract
    noteDelayMs = 2500,
    -- in-game adjustable (see Settings tab): event strength, linked markets, active preset (0 = custom)
    autoAccess = true, eventScale = 1.0, linkEnabled = true, linkStrength = 0.35, linkDaysFactor = 0.7,
    preset = 2,
    maxHistory = 25,       -- contract history records kept per farm
}

MarketsAndFutures.fills = {}          -- [fillTypeIndex] = {mult, trend, dayRef, events, stationKey, stationName}
MarketsAndFutures.contracts = {}      -- {id, farmId, fillTypeIndex, amount, remaining, endDay, lockedMult, lockedPrice (per 1000 L, fixed), stationKey, stationName}
MarketsAndFutures.nextContractId = 1
MarketsAndFutures.perks = {}          -- [farmId] = {progress = delivered value toward next free cancel, tokens = 0|1}
MarketsAndFutures.pendingNotes = {}   -- [contractId] = {farmId, idx, amount, remaining}
MarketsAndFutures.history = {}        -- finished contracts, newest first
MarketsAndFutures.links = {}          -- [fillTypeIndex] = {[linkedFillTypeIndex] = true}
MarketsAndFutures.noteTimer = 0
MarketsAndFutures.dirty = false
MarketsAndFutures.dirtyTimer = 0

MarketsAndFutures.stationList = {}    -- all known SellingStation objects
MarketsAndFutures.blocked = {}        -- [stationKey] = true: stations ignored for prices / contracts (set by the host)
MarketsAndFutures.keyCache = {}
MarketsAndFutures.accessCache = {}   -- [station] = true/false: can the local farm deliver there (refreshed every second)
MarketsAndFutures.stationSet = {}
MarketsAndFutures.stationStats = {}   -- [fillTypeIndex] = {avg, best, bestName, count} (price per 1000 L, incl. market mult)
MarketsAndFutures.stationsReady = false
MarketsAndFutures.readyTimer = 0

function MarketsAndFutures.t(name)
    return g_i18n:getText(name, MarketsAndFutures.modName)
end

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- ===================== STATIONS =====================
function MarketsAndFutures:registerStation(station)
    if station == nil or self.stationSet[station] then return end
    self.stationSet[station] = true
    table.insert(self.stationList, station)
end

function MarketsAndFutures:unregisterStation(station)
    if not self.stationSet[station] then return end
    self.stationSet[station] = nil
    for i = #self.stationList, 1, -1 do
        if self.stationList[i] == station then table.remove(self.stationList, i) end
    end
end

function MarketsAndFutures:scanPlaceables()
    pcall(function()
        for _, placeable in pairs(g_currentMission.placeableSystem.placeables) do
            local spec = placeable.spec_sellingStation
            if spec ~= nil and spec.sellingStation ~= nil then
                self:registerStation(spec.sellingStation)
            end
        end
    end)
end

function MarketsAndFutures:getStationName(station)
    local n
    pcall(function() n = station:getName() end)
    if (n == nil or n == "") and station.owningPlaceable ~= nil then
        pcall(function() n = station.owningPlaceable:getName() end)
    end
    if (n == nil or n == "") then n = station.stationName end
    if n == nil or n == "" then n = "Station" end
    return tostring(n)
end

function MarketsAndFutures:getStationKey(station)
    local cached = self.keyCache[station]
    if cached ~= nil then return cached end
    local p = station.owningPlaceable
    if p ~= nil then
        local uid = p.uniqueId
        if uid == nil and p.getUniqueId ~= nil then pcall(function() uid = p:getUniqueId() end) end
        if uid ~= nil then
            self.keyCache[station] = tostring(uid)
            return self.keyCache[station]
        end
    end
    return "name:" .. self:getStationName(station)
end

function MarketsAndFutures:findStation(key)
    if key == nil or key == "" then return nil end
    for _, s in ipairs(self.stationList) do
        if self:getStationKey(s) == key then return s end
    end
    return nil
end

function MarketsAndFutures:isStationBlocked(station)
    return self.blocked[self:getStationKey(station)] == true
end

-- host only: block / unblock a selling station (ignored for prices, averages and new contracts)
function MarketsAndFutures:setStationBlocked(key, blocked)
    if not self.isServer then return false end
    if blocked then self.blocked[key] = true else self.blocked[key] = nil end
    self:refreshStationStats()
    self:ensureContractStations()
    self:broadcast()
    return true
end

-- Asks the game whether the local farm may deliver to this station. Anything unexpected counts as "allowed".
function MarketsAndFutures:canFarmUseStation(station)
    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    if farmId == nil or farmId == FarmManager.SPECTATOR_FARM_ID then return true end
    local ok, res = pcall(function()
        if station.getIsFillAllowedFromFarm ~= nil then return station:getIsFillAllowedFromFarm(farmId) end
        local ah = g_currentMission.accessHandler
        if ah ~= nil and ah.canFarmAccess ~= nil then return ah:canFarmAccess(farmId, station) end
        return true
    end)
    if ok and res == false then return false end
    return true
end

-- does the station take this item at all (ignores the block list and the access check)
function MarketsAndFutures:stationAcceptsRaw(station, idx)
    if station.acceptedFillTypes ~= nil then return station.acceptedFillTypes[idx] == true end
    local ok, p = pcall(self.origGetPrice, station, idx)
    return ok and type(p) == "number" and p > 0
end

-- world position of the local player (vehicle if driving, otherwise the player, otherwise the camera)
function MarketsAndFutures:getPlayerPosition()
    local x, y, z
    pcall(function()
        local p = g_localPlayer
        local veh = p ~= nil and p.getCurrentVehicle ~= nil and p:getCurrentVehicle() or nil
        if veh ~= nil and veh.rootNode ~= nil then x, y, z = getWorldTranslation(veh.rootNode) return end
        if p ~= nil and p.rootNode ~= nil then x, y, z = getWorldTranslation(p.rootNode) return end
        local mp = g_currentMission.player
        if mp ~= nil and mp.rootNode ~= nil then x, y, z = getWorldTranslation(mp.rootNode) return end
    end)
    if x == nil then
        pcall(function() x, y, z = getWorldTranslation(getCamera()) end)
    end
    return x, y, z
end

-- distance in metres (horizontal) from the player to a station, or nil when unknown
function MarketsAndFutures:getStationDistance(station)
    local px, _, pz = self:getPlayerPosition()
    if px == nil then return nil end
    local sx, sz
    pcall(function()
        local node = station.owningPlaceable ~= nil and station.owningPlaceable.rootNode or station.rootNode
        if node ~= nil then
            local x, _, z = getWorldTranslation(node)
            sx, sz = x, z
        end
    end)
    if sx == nil then return nil end
    return math.sqrt((sx - px) ^ 2 + (sz - pz) ^ 2)
end

-- every station that accepts the item, with its current price and why it might be unusable
function MarketsAndFutures:getStationsForItem(idx)
    local list = {}
    local contractKey = self.fills[idx] and self.fills[idx].stationKey or ""
    for _, s in ipairs(self.stationList) do
        if self:stationAcceptsRaw(s, idx) then
            local key = self:getStationKey(s)
            local price
            local ok, p = pcall(s.getEffectiveFillTypePrice, s, idx)
            if ok and type(p) == "number" and p > 0 then price = p * 1000 end
            table.insert(list, {
                station = s, key = key, name = self:getStationName(s), price = price,
                blocked = self.blocked[key] == true,
                noAccess = self.CFG.autoAccess and not self:canFarmUseStation(s),
                isContract = key == contractKey,
                dist = self:getStationDistance(s),
            })
        end
    end
    return list
end

function MarketsAndFutures:stationAccepts(station, idx)
    if self.blocked[self:getStationKey(station)] then return false end
    if self.CFG.autoAccess then
        local a = self.accessCache[station]
        if a == nil then
            a = self:canFarmUseStation(station)
            self.accessCache[station] = a
        end
        if not a then return false end
    end
    if station.acceptedFillTypes ~= nil then return station.acceptedFillTypes[idx] == true end
    local ok, p = pcall(self.origGetPrice, station, idx)
    return ok and type(p) == "number" and p > 0
end

-- Recompute average / best station price per fill type (price per 1000 L, incl. market multiplier)
function MarketsAndFutures:refreshStationStats()
    self.accessCache = {}
    local stats = {}
    for idx in pairs(self.fills) do
        local sum, n, best, bestStation = 0, 0, 0, nil
        for _, s in ipairs(self.stationList) do
            if self:stationAccepts(s, idx) then
                local ok, p = pcall(s.getEffectiveFillTypePrice, s, idx)
                if ok and type(p) == "number" and p > 0 then
                    sum = sum + p
                    n = n + 1
                    if p > best then best, bestStation = p, s end
                end
            end
        end
        if n > 0 then
            stats[idx] = {avg = sum / n * 1000, best = best * 1000, bestName = self:getStationName(bestStation), count = n}
        end
    end
    self.stationStats = stats
end

-- Best price per 1000 L that any usable station pays for this item right now (nil when none accepts it).
function MarketsAndFutures:getBestStationPrice(idx)
    local best = 0
    for _, s in ipairs(self.stationList) do
        if self:stationAccepts(s, idx) then
            local ok, p = pcall(s.getEffectiveFillTypePrice, s, idx)
            if ok and type(p) == "number" and p > best then best = p end
        end
    end
    if best > 0 then return best * 1000 end
    return nil
end

-- Server: make sure every item has a (randomly chosen) contract station that accepts it.
function MarketsAndFutures:ensureContractStations()
    if not self.isServer or not self.stationsReady then return end
    self.accessCache = {}
    local changed = false
    for idx, st in pairs(self.fills) do
        local cur = self:findStation(st.stationKey)
        if cur == nil or not self:stationAccepts(cur, idx) then
            local cands = {}
            for _, s in ipairs(self.stationList) do
                if self:stationAccepts(s, idx) then table.insert(cands, s) end
            end
            if #cands > 0 then
                local s = cands[math.random(#cands)]
                st.stationKey, st.stationName = self:getStationKey(s), self:getStationName(s)
                changed = true
            elseif st.stationKey ~= "" then
                st.stationKey, st.stationName = "", ""
                changed = true
            end
        end
    end
    if changed then self.dirty = true end
end

-- ===================== HELPERS =====================
function MarketsAndFutures:isSellable(ft)
    if ft == nil or (ft.pricePerLiter or 0) <= 0 then return false end
    if self.useShowOnPriceTable then return ft.showOnPriceTable == true end
    return ft.showOnPriceTable ~= false
end

function MarketsAndFutures:getState(idx)
    local st = self.fills[idx]
    if st == nil then
        st = {mult = 1, trend = 1, dayRef = 1, events = {}, stationKey = "", stationName = "", hist = nil, histSum = 0, histN = 0}
        self.fills[idx] = st
    end
    return st
end

function MarketsAndFutures:getMult(idx)
    local st = self.fills[idx]
    return st and st.mult or 1
end

-- Economic difficulty price multiplier. Returns the value and where it came from
-- ("engine", "table" or "default" = 1.0 because nothing usable was found).
function MarketsAndFutures:getDifficultyMultiplier()
    local m, source
    pcall(function()
        if EconomyManager ~= nil and EconomyManager.getPriceMultiplier ~= nil then
            m = EconomyManager.getPriceMultiplier()
            source = "engine"
        end
    end)
    if type(m) ~= "number" or m <= 0 then
        m = nil
        pcall(function()
            local d = g_currentMission.missionInfo.economicDifficulty
            local t = EconomyManager.DIFFICULTY_PRICE_MULTIPLIER
            if t ~= nil and type(t[d]) == "number" then m, source = t[d], "table" end
        end)
    end
    if type(m) ~= "number" or m <= 0 then m, source = 1, "default" end
    return m, source
end

-- Item price from the game data (pricePerLiter x 1000), before difficulty
function MarketsAndFutures:getRawPricePer1000(idx)
    local ft = g_fillTypeManager:getFillTypeByIndex(idx)
    return ft ~= nil and (ft.pricePerLiter or 0) * 1000 or 0
end

-- The "Avg" price: game data price x difficulty multiplier, per 1000 L
function MarketsAndFutures:getBasePricePer1000(idx)
    return self:getRawPricePer1000(idx) * (self:getDifficultyMultiplier())
end

-- Unmultiplied price per 1000 L at a given station (falls back to the base price)
function MarketsAndFutures:getStationBasePer1000(station, idx)
    if station ~= nil then
        local ok, p = pcall(self.origGetPrice, station, idx)
        if ok and type(p) == "number" and p > 0 then return p * 1000 end
    end
    return self:getBasePricePer1000(idx)
end

function MarketsAndFutures:getToday()
    return g_currentMission.environment.currentMonotonicDay or 0
end

-- contract fee (fraction taken off the locked price): a duration part and a quantity part, each with an adjustable multiplier
function MarketsAndFutures:getDaysPerMonth()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local d = env ~= nil and env.daysPerPeriod or 1
    return math.max(1, math.floor(d or 1))
end

-- remaining wait after signing (game hours) shown in game months (rounded up)
function MarketsAndFutures:cooldownToMonths(hours)
    return math.max(1, math.ceil(hours / (24 * self:getDaysPerMonth())))
end

-- days left of an event, shown in game months (rounded up)
function MarketsAndFutures:daysToMonths(days)
    return math.max(1, math.ceil(days / self:getDaysPerMonth()))
end

-- value = amount x the locked price before fees (market x contract rate), so expensive items pay a fair share
function MarketsAndFutures:getDiscount(amount, months, preFeePer1000)
    local c = self.CFG
    local am = c.feeAmountMult or 1
    local value = amount / 1000 * (preFeePer1000 or 0)
    local qty = math.min(c.maxQuantityFee * am, c.discountPerValue * value / c.valueStep * am)
    local fee = c.discountPerMonth * months * (c.feeDurationMult or 1) + qty
    return math.min(c.maxDiscount, fee)
end

function MarketsAndFutures:getPreFeePer1000(st, stnBase)
    return stnBase * st.mult * (1 + (st.offset or 0))
end

-- Locked multiplier = market multiplier x item contract rate x contract fee
function MarketsAndFutures:computeLockedMult(st, amount, months, stnBase)
    local c = self.CFG
    local m = st.mult * (1 + (st.offset or 0)) * (1 - self:getDiscount(amount, months, self:getPreFeePer1000(st, stnBase)))
    return clamp(m, c.minMult * 0.7, c.maxMult * 1.3)
end

-- Preview for the contract form
function MarketsAndFutures:getContractPreview(idx, amount, months)
    local st = self.fills[idx]
    if st == nil then return nil end
    local c = self.CFG
    local station = self:findStation(st.stationKey)
    local stnBase = self:getStationBasePer1000(station, idx)
    local disc = self:getDiscount(amount, months, self:getPreFeePer1000(st, stnBase))
    local locked = stnBase * self:computeLockedMult(st, amount, months, stnBase)
    local avgBase = self:getBasePricePer1000(idx)
    return {
        stationNow = stnBase * st.mult, vsAvg = avgBase > 0 and (locked / avgBase - 1) or 0,
        discount = disc, locked = locked, offset = st.offset or 0, cooldown = st.cooldown or 0,
        hasStation = st.stationKey ~= nil and st.stationKey ~= "",
        stationName = (st.stationName ~= "" and st.stationName) or nil,
    }
end

-- Locked and current price per 1000 L for a contract (at its own station)
-- The locked price is a fixed amount (per 1000 L) stored when the contract is signed.
-- Contracts from older saves have no stored price yet; it is fixed once, the first time it is needed.
function MarketsAndFutures:ensureLockedPrice(ct)
    if ct.lockedPrice == nil or ct.lockedPrice <= 0 then
        local station = self:findStation(ct.stationKey)
        ct.lockedPrice = self:getStationBasePer1000(station, ct.fillTypeIndex) * ct.lockedMult
    end
    return ct.lockedPrice
end

function MarketsAndFutures:getContractPrices(ct)
    local station = self:findStation(ct.stationKey)
    local base = self:getStationBasePer1000(station, ct.fillTypeIndex)
    return self:ensureLockedPrice(ct), base * self:getMult(ct.fillTypeIndex)
end

-- Money value of `liters` of a contract at its locked price (at its own station)
function MarketsAndFutures:getContractValue(ct, liters)
    local locked = self:getContractPrices(ct)
    return liters / 1000 * locked
end

-- Server: take a penalty from the farm and tell the players (kind 1 = cancelled, 2 = expired unfilled).
-- Booked as "Other" (an expense); the game has no dedicated contract-penalty category.
function MarketsAndFutures:chargePenalty(farmId, fillTypeIndex, amount, kind)
    if not self.isServer or amount < 1 then return end
    g_currentMission:addMoney(-amount, farmId, MoneyType.OTHER, true)
    self:showPenaltyNote(farmId, fillTypeIndex, amount, kind)
    g_server:broadcastEvent(MFPenaltyEvent.new(farmId, fillTypeIndex, amount, kind), false)
end

function MarketsAndFutures:showPenaltyNote(farmId, idx, amount, kind)
    if g_currentMission:getFarmId() ~= farmId then return end
    local ft = g_fillTypeManager:getFillTypeByIndex(idx)
    if ft == nil then return end
    local text = self.t(kind == 1 and "mf_note_pen_cancel" or "mf_note_pen_expired")
    local msg = string.format(text, ft.title, g_i18n:formatMoney(amount, 0, true, true))
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL or FSBaseMission.INGAME_NOTIFICATION_INFO, msg)
end

function MarketsAndFutures:getPerks(farmId)
    local p = self.perks[farmId]
    if p == nil then
        p = {progress = 0, tokens = 0}
        self.perks[farmId] = p
    end
    return p
end

-- Server: count delivered contract value toward the free cancel (nothing accumulates while one is stored)
function MarketsAndFutures:addDeliveredValue(farmId, value)
    local perk = self:getPerks(farmId)
    if perk.tokens > 0 or value <= 0 then return end
    perk.progress = perk.progress + value
    if perk.progress >= self.CFG.freeCancelThreshold then
        perk.tokens, perk.progress = 1, 0
        self:notifyFarm(farmId, 3, 0, 0, 0, 0)
    end
    self.dirty = true
end

-- Server: notification for one farm. kind 1 = progress, 2 = fulfilled, 3 = free cancel earned, 4 = free cancel used
function MarketsAndFutures:notifyFarm(farmId, kind, idx, pct, delivered, total)
    if not self.isServer then return end
    self:showNotify(farmId, kind, idx, pct, delivered, total)
    g_server:broadcastEvent(MFNotifyEvent.new(farmId, kind, idx, pct, delivered, total), false)
end

function MarketsAndFutures:showNotify(farmId, kind, idx, pct, delivered, total)
    if g_currentMission:getFarmId() ~= farmId then return end
    local ft = g_fillTypeManager:getFillTypeByIndex(idx)
    local title = ft ~= nil and ft.title or "?"
    local fmt = function(v) return g_i18n:formatNumber(math.floor(v)) end
    local msg
    if kind == 1 then msg = string.format(self.t("mf_note_progress"), title, math.floor(pct), fmt(delivered), fmt(total))
    elseif kind == 2 then msg = string.format(self.t("mf_note_complete"), title, fmt(total))
    elseif kind == 3 then msg = self.t("mf_note_free_earned")
    elseif kind == 4 then msg = string.format(self.t("mf_note_free_used"), title) end
    if msg ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_INFO, msg)
    end
end

function MarketsAndFutures:flushDeliveryNotes()
    for id, n in pairs(self.pendingNotes) do
        local delivered = n.amount - n.remaining
        if n.remaining <= 0.5 then
            self:notifyFarm(n.farmId, 2, n.idx, 100, n.amount, n.amount)
        else
            self:notifyFarm(n.farmId, 1, n.idx, delivered / n.amount * 100, delivered, n.amount)
        end
    end
    self.pendingNotes = {}
end

function MarketsAndFutures:getFarmContracts(farmId)
    local list = {}
    for _, c in ipairs(self.contracts) do
        if c.farmId == farmId then table.insert(list, c) end
    end
    return list
end

function MarketsAndFutures:getFarmIdFromConnection(connection)
    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local farm = g_farmManager:getFarmByUserId(userId)
    return farm ~= nil and farm.farmId or nil
end

-- ===================== SIMULATION (server) =====================
function MarketsAndFutures:computeTarget(st)
    local c = self.CFG
    local fadeDays = math.max(3, self:getDaysPerMonth())   -- an event fades out over its last month (at least 3 days)
    local t = st.trend
    for _, e in ipairs(st.events) do
        t = t * (1 + (e.factor - 1) * math.min(1, e.daysLeft / fadeDays))
    end
    return clamp(t, c.minMult, c.maxMult)
end

-- Price history: one averaged market multiplier per period (1..12) of the year.
-- Periods not yet reached this year keep last year's value (new games start with a seeded "last year").
function MarketsAndFutures:seedHistory(st)
    local v = 0.95 + math.random() * 0.10
    st.hist = {}
    for p = 1, 12 do
        v = clamp(v + (1 - v) * 0.25 + (math.random() * 2 - 1) * 0.06, 0.78, 1.30)
        st.hist[p] = v
    end
end

function MarketsAndFutures:getCurrentPeriod()
    local env = g_currentMission.environment
    local p = env ~= nil and env.currentPeriod or 1
    return clamp(math.floor(p or 1), 1, 12)
end

function MarketsAndFutures:sampleHistory()
    local p = self:getCurrentPeriod()
    if self.lastPeriod ~= p then
        if self.lastPeriod ~= nil then
            for _, st in pairs(self.fills) do st.histSum, st.histN = 0, 0 end
        end
        self.lastPeriod = p
    end
    for _, st in pairs(self.fills) do
        if st.hist == nil then self:seedHistory(st) end
        st.histSum = st.histSum + st.mult
        st.histN = st.histN + 1
        st.hist[p] = st.histSum / st.histN
    end
end

function MarketsAndFutures:seedOffset(st)
    -- two uniforms -> triangular distribution: most items near 0, a few towards +/-20%
    st.offset = (math.random() + math.random() - 1) * self.CFG.offsetMax
end

function MarketsAndFutures:initialiseNewMarket()
    for idx, ft in pairs(g_fillTypeManager.fillTypes) do
        if self:isSellable(ft) then
            local st = self:getState(idx)
            st.trend = 0.95 + math.random() * 0.10
            st.mult = st.trend
            st.dayRef = st.mult
            self:seedHistory(st)
            self:seedOffset(st)
        end
    end
end

-- ===================== PRESETS / SETTINGS =====================
MarketsAndFutures.PRESETS = {
    {dailyEventChance = 0.01, eventScale = 0.6, trendNoise = 0.020},   -- 1 calm
    {dailyEventChance = 0.03, eventScale = 1.0, trendNoise = 0.035},   -- 2 normal
    {dailyEventChance = 0.06, eventScale = 1.4, trendNoise = 0.050},   -- 3 volatile
}
MarketsAndFutures.SETTING_LIMITS = {
    dailyEventChance = {0, 0.5}, eventScale = {0.25, 2.5}, trendNoise = {0, 0.12}, linkStrength = {0, 1},
    cancelPenalty = {0, 0.5}, expiryPenalty = {0, 0.5}, freeCancelThreshold = {50000, 3000000},
    feeAmountMult = {0, 5}, feeDurationMult = {0, 5}, maxMonths = {1, 120},
}
-- float settings that are synced / saved together
MarketsAndFutures.SETTING_KEYS = {"dailyEventChance", "eventScale", "trendNoise", "linkStrength", "cancelPenalty", "expiryPenalty", "freeCancelThreshold", "feeAmountMult", "feeDurationMult", "maxMonths"}

-- factory defaults of every market setting (captured before any save is loaded), used by "restore defaults"
MarketsAndFutures.DEFAULTS = {}
for _, key in ipairs(MarketsAndFutures.SETTING_KEYS) do MarketsAndFutures.DEFAULTS[key] = MarketsAndFutures.CFG[key] end
MarketsAndFutures.DEFAULTS.contractCooldownMonths = MarketsAndFutures.CFG.contractCooldownMonths
MarketsAndFutures.DEFAULTS.linkEnabled = MarketsAndFutures.CFG.linkEnabled
MarketsAndFutures.DEFAULTS.autoAccess = MarketsAndFutures.CFG.autoAccess
MarketsAndFutures.DEFAULTS.preset = MarketsAndFutures.CFG.preset

function MarketsAndFutures:applyPreset(i)
    if not self.isServer then return false end
    local pr = self.PRESETS[i]
    if pr == nil then return false end
    for k, v in pairs(pr) do self.CFG[k] = v end
    self.CFG.preset = i
    self:broadcast()
    return true
end

function MarketsAndFutures:setSetting(key, value)
    if not self.isServer then return false end
    local c = self.CFG
    if key == "autoAccess" then
        c.autoAccess = (value == true)
        self.accessCache = {}
        self:refreshStationStats()
        self:ensureContractStations()
        self:broadcast()
        return true
    elseif key == "linkEnabled" then
        c.linkEnabled = (value == true)
    elseif key == "contractCooldownMonths" then
        c.contractCooldownMonths = clamp(math.floor(value + 0.5), 1, 36)
    else
        local lim = self.SETTING_LIMITS[key]
        if lim == nil then return false end
        c[key] = clamp(math.floor(value * 1000 + 0.5) / 1000, lim[1], lim[2])
        if key == "maxMonths" then c[key] = math.floor(c[key] + 0.5) end
    end
    if key ~= "feeAmountMult" and key ~= "feeDurationMult" and key ~= "maxMonths" then
        c.preset = 0   -- any manual change to the market behaviour makes it a custom setup
    end
    self:broadcast()
    return true
end

-- puts every market setting back to its default (host only)
function MarketsAndFutures:resetSettings()
    if not self.isServer then return false end
    for key, v in pairs(self.DEFAULTS) do self.CFG[key] = v end
    self:broadcast()
    return true
end

-- ===================== LINKED MARKETS =====================
-- Items in the same group tend to move together: when one gets an event, the others get a weaker, shorter echo.
MarketsAndFutures.LINK_GROUPS = {
    {"WHEAT", "BARLEY", "OAT", "SORGHUM", "MAIZE"},
    {"CANOLA", "SUNFLOWER", "SOYBEAN", "OILSEEDRADISH"},
    {"POTATO", "SUGARBEET", "CARROT", "PARSNIP", "BEETROOT"},
    {"CARROT", "PARSNIP", "BEETROOT", "SPINACH", "PEA", "GREENBEAN", "ONION"},
    {"RICE", "RICELONGGRAIN"},
    {"GRASS_WINDROW", "DRYGRASS_WINDROW", "SILAGE", "FORAGE", "HAY", "ALFALFA_WINDROW", "DRYALFALFA_WINDROW", "CLOVER_WINDROW", "DRYCLOVER_WINDROW"},
    {"GRAPE", "OLIVE", "BANANA", "COFFEE"},
    {"MANURE", "LIQUIDMANURE", "DIGESTATE"},
}

function MarketsAndFutures:buildLinks()
    self.links = {}
    for _, group in ipairs(self.LINK_GROUPS) do
        local idxs = {}
        for _, name in ipairs(group) do
            local i = g_fillTypeManager:getFillTypeIndexByName(name)
            if i ~= nil and self.fills[i] ~= nil then table.insert(idxs, i) end
        end
        for _, a in ipairs(idxs) do
            for _, b in ipairs(idxs) do
                if a ~= b then
                    self.links[a] = self.links[a] or {}
                    self.links[a][b] = true
                end
            end
        end
    end
end

-- ===================== CONTRACT HISTORY =====================
-- result: 1 fulfilled, 2 cancelled (penalty), 3 expired (penalty), 4 cancelled with the free cancel
function MarketsAndFutures:recordHistory(ct, result, penalty)
    local rec = {
        id = ct.id, farmId = ct.farmId, fillTypeIndex = ct.fillTypeIndex,
        amount = ct.amount, delivered = ct.amount - ct.remaining,
        lockedPrice = self:ensureLockedPrice(ct), result = result, penalty = penalty or 0,
        gain = ct.gain or 0, day = self:getToday(), stationName = ct.stationName or "",
    }
    table.insert(self.history, 1, rec)
    local counts, kept = {}, {}
    for _, r in ipairs(self.history) do
        counts[r.farmId] = (counts[r.farmId] or 0) + 1
        if counts[r.farmId] <= self.CFG.maxHistory then table.insert(kept, r) end
    end
    self.history = kept
    self.dirty = true
end

-- remove one finished contract from a farm's history (server)
function MarketsAndFutures:deleteHistory(farmId, id)
    if not self.isServer then return false end
    for i, r in ipairs(self.history) do
        if r.id == id and r.farmId == farmId then
            table.remove(self.history, i)
            self:broadcast()
            return true
        end
    end
    return false
end

function MarketsAndFutures:requestDeleteHistory(id)
    if self.isServer then
        return self:deleteHistory(g_currentMission:getFarmId(), id)
    end
    g_client:getServerConnection():sendEvent(MFDeleteHistoryEvent.new(id))
    return true
end

function MarketsAndFutures:getFarmHistory(farmId)
    local list = {}
    for _, r in ipairs(self.history) do
        if r.farmId == farmId then table.insert(list, r) end
    end
    return list
end

-- Events can start at any hour. dailyEventChance (the name is kept for old saves) is the chance per game MONTH,
-- converted to an equivalent per-hour chance, so the market feels the same whatever the days-per-month setting is.
function MarketsAndFutures:rollEvents()
    local c = self.CFG
    local hourlyChance = 1 - (1 - c.dailyEventChance) ^ (1 / (24 * self:getDaysPerMonth()))
    local noteKind, noteFill
    for idx, st in pairs(self.fills) do
        if #st.events < c.maxEventsPerFill and math.random() < hourlyChance then
            local surplus = math.random() < 0.5
            local factor
            if surplus then factor = c.surplusMin + math.random() * (c.surplusMax - c.surplusMin)
            else factor = c.demandMin + math.random() * (c.demandMax - c.demandMin) end
            factor = clamp(1 + (factor - 1) * c.eventScale, 0.25, 2.5)
            local days = math.random(c.eventMinMonths, c.eventMaxMonths) * self:getDaysPerMonth()
            table.insert(st.events, {surplus = surplus, factor = factor, daysLeft = days})

            -- echo on linked items (weaker and shorter)
            if c.linkEnabled and c.linkStrength > 0 and self.links ~= nil and self.links[idx] ~= nil then
                local lf = 1 + (factor - 1) * c.linkStrength
                local ld = math.max(1, math.floor(days * c.linkDaysFactor + 0.5))
                for lidx in pairs(self.links[idx]) do
                    local lst = self.fills[lidx]
                    if lst ~= nil and #lst.events < c.maxEventsPerFill + 1 then
                        table.insert(lst.events, {surplus = surplus, factor = lf, daysLeft = ld, linked = true})
                    end
                end
            end

            if noteKind == nil and (factor <= c.announceBelow or factor >= c.announceAbove) then
                noteKind = surplus and "surplus" or "demand"
                noteFill = idx
            end
        end
    end
    return noteKind, noteFill
end

function MarketsAndFutures:onHourChanged()
    if not self.isServer then return end
    local c = self.CFG
    local noteKind, noteFill = self:rollEvents()
    -- the contract rate drifts per game month, not per hour: the hourly pull / step shrink as months get longer
    local dpm = self:getDaysPerMonth()
    local pull = 1 - (1 - c.offsetPull) ^ (1 / dpm)
    local noise = c.offsetNoise / math.sqrt(dpm)
    for _, st in pairs(self.fills) do
        local target = self:computeTarget(st)
        st.mult = clamp(st.mult + (target - st.mult) * c.hourlyBlend + (math.random() * 2 - 1) * 0.004, c.minMult, c.maxMult)
        st.offset = clamp((st.offset or 0) * (1 - pull) + (math.random() * 2 - 1) * noise, -c.offsetMax, c.offsetMax)
        if (st.cooldown or 0) > 0 then st.cooldown = st.cooldown - 1 end
    end
    self:sampleHistory()
    self:broadcast(noteKind, noteFill)
end

function MarketsAndFutures:onDayChanged()
    if not self.isServer then return end
    local c = self.CFG
    local noteKind, noteFill
    for idx, st in pairs(self.fills) do
        st.dayRef = st.mult
        st.trend = clamp(st.trend + (1 - st.trend) * c.trendPull + (math.random() * 2 - 1) * c.trendNoise, c.trendMin, c.trendMax)
        for i = #st.events, 1, -1 do
            local e = st.events[i]
            e.daysLeft = e.daysLeft - 1
            if e.daysLeft <= 0 then table.remove(st.events, i) end
        end
    end
    local today = self:getToday()
    for i = #self.contracts, 1, -1 do
        local ct = self.contracts[i]
        local expired = today >= ct.endDay
        if expired or ct.remaining <= 0.5 then
            if expired and ct.remaining > 0.5 then
                local penalty = c.expiryPenalty * self:getContractValue(ct, ct.remaining)
                self:chargePenalty(ct.farmId, ct.fillTypeIndex, penalty, 2)
                self:recordHistory(ct, 3, penalty)
            end
            self.pendingNotes[ct.id] = nil
            table.remove(self.contracts, i)
        end
    end
    self:ensureContractStations()
    self:broadcast(noteKind, noteFill)
end

-- ===================== CONTRACTS (server) =====================
function MarketsAndFutures:createContract(farmId, idx, amount, months)
    local c = self.CFG
    if not self.isServer or farmId == nil or farmId == FarmManager.SPECTATOR_FARM_ID then return false end
    local st = self.fills[idx]
    if st == nil or st.stationKey == nil or st.stationKey == "" then return false end
    if (st.cooldown or 0) > 0 then return false end
    amount = clamp(math.floor(amount), c.minAmount, c.maxAmount)
    months = clamp(math.floor(months), c.minMonths, math.max(c.minMonths, math.floor(c.maxMonths)))
    local days = months * self:getDaysPerMonth()
    if #self:getFarmContracts(farmId) >= c.maxContractsPerFarm then return false end

    local stnBase = self:getStationBasePer1000(self:findStation(st.stationKey), idx)
    local locked = self:computeLockedMult(st, amount, months, stnBase)
    local lockedPrice = stnBase * locked
    table.insert(self.contracts, {
        id = self.nextContractId, farmId = farmId, fillTypeIndex = idx,
        amount = amount, remaining = amount,
        endDay = self:getToday() + days, lockedMult = locked, lockedPrice = lockedPrice, gain = 0,
        stationKey = st.stationKey, stationName = st.stationName,
    })
    self.nextContractId = self.nextContractId + 1
    st.cooldown = c.contractCooldownMonths * 24 * self:getDaysPerMonth()   -- remaining wait in game hours
    self:broadcast()
    return true
end

function MarketsAndFutures:cancelContract(farmId, id, free)
    if not self.isServer then return false end
    for i, ct in ipairs(self.contracts) do
        if ct.id == id and ct.farmId == farmId then
            local penalty = self.CFG.cancelPenalty * self:getContractValue(ct, ct.remaining)
            local usedFree = false
            if free then
                local perk = self:getPerks(farmId)
                if perk.tokens <= 0 then return false end
                perk.tokens, perk.progress = 0, 0   -- the counter starts over once the stored cancel is used
                penalty, usedFree = 0, true
            end
            table.remove(self.contracts, i)
            self.pendingNotes[ct.id] = nil
            self:recordHistory(ct, usedFree and 4 or 2, penalty)
            if usedFree then self:notifyFarm(farmId, 4, ct.fillTypeIndex, 0, 0, 0)
            else self:chargePenalty(farmId, ct.fillTypeIndex, penalty, 1) end
            self:broadcast()
            return true
        end
    end
    return false
end

-- Settle a sale against contracts tied to THIS station. Station already paid the market
-- price; we pay (or deduct) the difference to the locked price.
function MarketsAndFutures:applyContracts(station, farmId, liters, idx, toolType, moneyType)
    local st = self.fills[idx]
    if st == nil or liters <= 0 or #self.contracts == 0 then return end
    local ok, orig = pcall(self.origGetPrice, station, idx, toolType)
    if not ok or orig == nil then return end
    local stationKey = self:getStationKey(station)

    local left, bonus, changed, delivered = liters, 0, false, 0
    for _, ct in ipairs(self.contracts) do
        if left <= 0 then break end
        if ct.farmId == farmId and ct.fillTypeIndex == idx and ct.remaining > 0 and ct.stationKey == stationKey then
            local used = math.min(ct.remaining, left)
            ct.remaining = ct.remaining - used
            left = left - used
            local lockedPerLiter = self:ensureLockedPrice(ct) / 1000
            local diff = used * (lockedPerLiter - orig * st.mult)      -- station paid orig * market multiplier
            bonus = bonus + diff
            ct.gain = (ct.gain or 0) + diff
            delivered = delivered + used * lockedPerLiter              -- value at the locked price
            changed = true
            self.pendingNotes[ct.id] = {farmId = farmId, idx = idx, amount = ct.amount, remaining = ct.remaining}
            self.noteTimer = 0
        end
    end
    if changed then
        for i = #self.contracts, 1, -1 do
            local done = self.contracts[i]
            if done.remaining <= 0.5 then
                self:recordHistory(done, 1, 0)
                table.remove(self.contracts, i)
            end
        end
        if math.abs(bonus) >= 1 then
            g_currentMission:addMoney(bonus, farmId, moneyType or MoneyType.OTHER, true)
        end
        self:addDeliveredValue(farmId, delivered)
        self.dirty = true
    end
end

-- ===================== NETWORK =====================
function MarketsAndFutures:broadcast(noteKind, noteFill)
    if not self.isServer then return end
    g_server:broadcastEvent(MFStateEvent.new(noteKind, noteFill), false)
    if noteKind ~= nil then self:showNote(noteKind, noteFill) end
    self.dirty = false
    self.dirtyTimer = 0
end

function MarketsAndFutures:showNote(kind, idx)
    local ft = g_fillTypeManager:getFillTypeByIndex(idx)
    if ft == nil then return end
    local msg = string.format(self.t(kind == "surplus" and "mf_note_surplus" or "mf_note_demand"), ft.title)
    g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, msg)
end

function MarketsAndFutures:writeState(streamId)
    local keys = {}
    for idx in pairs(self.fills) do table.insert(keys, idx) end
    streamWriteUInt16(streamId, #keys)
    for _, idx in ipairs(keys) do
        local st = self.fills[idx]
        streamWriteUIntN(streamId, idx, FillTypeManager.SEND_NUM_BITS)
        streamWriteFloat32(streamId, st.mult)
        streamWriteFloat32(streamId, st.dayRef)
        streamWriteString(streamId, st.stationKey or "")
        streamWriteString(streamId, st.stationName or "")
        for i = 1, 12 do streamWriteFloat32(streamId, (st.hist and st.hist[i]) or 1) end
        streamWriteFloat32(streamId, st.offset or 0)
        streamWriteUInt16(streamId, math.min(65535, st.cooldown or 0))
        streamWriteUInt8(streamId, #st.events)
        for _, e in ipairs(st.events) do
            streamWriteBool(streamId, e.surplus)
            streamWriteFloat32(streamId, e.factor)
            streamWriteUInt16(streamId, e.daysLeft)
            streamWriteBool(streamId, e.linked == true)
        end
    end
    streamWriteUInt16(streamId, #self.contracts)
    for _, ct in ipairs(self.contracts) do
        streamWriteInt32(streamId, ct.id)
        streamWriteUInt8(streamId, ct.farmId)
        streamWriteUIntN(streamId, ct.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
        streamWriteFloat32(streamId, ct.amount)
        streamWriteFloat32(streamId, ct.remaining)
        streamWriteInt32(streamId, ct.endDay)
        streamWriteFloat32(streamId, ct.lockedMult)
        streamWriteFloat32(streamId, ct.lockedPrice or 0)
        streamWriteFloat32(streamId, ct.gain or 0)
        streamWriteString(streamId, ct.stationKey or "")
        streamWriteString(streamId, ct.stationName or "")
    end
    local farmIds = {}
    for fid in pairs(self.perks) do table.insert(farmIds, fid) end
    streamWriteUInt8(streamId, #farmIds)
    for _, fid in ipairs(farmIds) do
        streamWriteUInt8(streamId, fid)
        streamWriteFloat32(streamId, self.perks[fid].progress)
        streamWriteUInt8(streamId, self.perks[fid].tokens)
    end
    -- settings
    local c = self.CFG
    for _, key in ipairs(self.SETTING_KEYS) do streamWriteFloat32(streamId, c[key]) end
    streamWriteUInt8(streamId, c.contractCooldownMonths)
    streamWriteBool(streamId, c.linkEnabled == true)
    streamWriteBool(streamId, c.autoAccess == true)
    streamWriteUInt8(streamId, c.preset or 0)
    -- contract history
    streamWriteUInt16(streamId, #self.history)
    for _, r in ipairs(self.history) do
        streamWriteInt32(streamId, r.id)
        streamWriteUInt8(streamId, r.farmId)
        streamWriteUIntN(streamId, r.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
        streamWriteFloat32(streamId, r.amount)
        streamWriteFloat32(streamId, r.delivered)
        streamWriteFloat32(streamId, r.lockedPrice)
        streamWriteUInt8(streamId, r.result)
        streamWriteFloat32(streamId, r.penalty)
        streamWriteFloat32(streamId, r.gain)
        streamWriteInt32(streamId, r.day)
        streamWriteString(streamId, r.stationName or "")
    end
    -- blocked stations
    local bl = {}
    for key in pairs(self.blocked) do table.insert(bl, key) end
    streamWriteUInt16(streamId, #bl)
    for _, key in ipairs(bl) do streamWriteString(streamId, key) end
end

function MarketsAndFutures:readState(streamId)
    local n = streamReadUInt16(streamId)
    for _ = 1, n do
        local idx = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        local st = self:getState(idx)
        st.mult = streamReadFloat32(streamId)
        st.dayRef = streamReadFloat32(streamId)
        st.stationKey = streamReadString(streamId)
        st.stationName = streamReadString(streamId)
        st.hist = {}
        for i = 1, 12 do st.hist[i] = streamReadFloat32(streamId) end
        st.offset = streamReadFloat32(streamId)
        st.cooldown = streamReadUInt16(streamId)
        st.events = {}
        local ne = streamReadUInt8(streamId)
        for _ = 1, ne do
            local e = {}
            e.surplus = streamReadBool(streamId)
            e.factor = streamReadFloat32(streamId)
            e.daysLeft = streamReadUInt16(streamId)
            e.linked = streamReadBool(streamId)
            table.insert(st.events, e)
        end
    end
    self.contracts = {}
    local nc = streamReadUInt16(streamId)
    for _ = 1, nc do
        local ct = {}
        ct.id = streamReadInt32(streamId)
        ct.farmId = streamReadUInt8(streamId)
        ct.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        ct.amount = streamReadFloat32(streamId)
        ct.remaining = streamReadFloat32(streamId)
        ct.endDay = streamReadInt32(streamId)
        ct.lockedMult = streamReadFloat32(streamId)
        ct.lockedPrice = streamReadFloat32(streamId)
        ct.gain = streamReadFloat32(streamId)
        ct.stationKey = streamReadString(streamId)
        ct.stationName = streamReadString(streamId)
        table.insert(self.contracts, ct)
    end
    self.perks = {}
    local np = streamReadUInt8(streamId)
    for _ = 1, np do
        local fid = streamReadUInt8(streamId)
        self.perks[fid] = {progress = streamReadFloat32(streamId), tokens = streamReadUInt8(streamId)}
    end
    local c = self.CFG
    for _, key in ipairs(self.SETTING_KEYS) do c[key] = streamReadFloat32(streamId) end
    c.contractCooldownMonths = streamReadUInt8(streamId)
    c.linkEnabled = streamReadBool(streamId)
    c.autoAccess = streamReadBool(streamId)
    self.accessCache = {}
    c.preset = streamReadUInt8(streamId)
    self.history = {}
    local nh = streamReadUInt16(streamId)
    for _ = 1, nh do
        local r = {}
        r.id = streamReadInt32(streamId)
        r.farmId = streamReadUInt8(streamId)
        r.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        r.amount = streamReadFloat32(streamId)
        r.delivered = streamReadFloat32(streamId)
        r.lockedPrice = streamReadFloat32(streamId)
        r.result = streamReadUInt8(streamId)
        r.penalty = streamReadFloat32(streamId)
        r.gain = streamReadFloat32(streamId)
        r.day = streamReadInt32(streamId)
        r.stationName = streamReadString(streamId)
        table.insert(self.history, r)
    end
    self.blocked = {}
    local nb = streamReadUInt16(streamId)
    for _ = 1, nb do self.blocked[streamReadString(streamId)] = true end
    self:refreshStationStats()
end

function MarketsAndFutures:requestContract(idx, amount, months)
    if self.isServer then
        return self:createContract(g_currentMission:getFarmId(), idx, amount, months), true
    end
    g_client:getServerConnection():sendEvent(MFCreateContractEvent.new(idx, amount, months))
    return true, false
end

function MarketsAndFutures:requestCancel(id, free)
    if self.isServer then
        return self:cancelContract(g_currentMission:getFarmId(), id, free == true)
    end
    g_client:getServerConnection():sendEvent(MFCancelContractEvent.new(id, free == true))
    return true
end

-- ===================== SAVE / LOAD =====================
function MarketsAndFutures:saveToXML(missionInfo)
    if not self.isServer or missionInfo == nil or missionInfo.savegameDirectory == nil then return end
    local path = missionInfo.savegameDirectory .. "/marketsAndFutures.xml"
    local xml = createXMLFile("marketsAndFutures", path, "marketsAndFutures")
    local i = 0
    for idx, st in pairs(self.fills) do
        local key = string.format("marketsAndFutures.fillTypes.fillType(%d)", i)
        setXMLString(xml, key .. "#name", g_fillTypeManager:getFillTypeNameByIndex(idx))
        setXMLFloat(xml, key .. "#mult", st.mult)
        setXMLFloat(xml, key .. "#trend", st.trend)
        setXMLFloat(xml, key .. "#dayRef", st.dayRef)
        setXMLString(xml, key .. "#stationKey", st.stationKey or "")
        setXMLString(xml, key .. "#stationName", st.stationName or "")
        setXMLFloat(xml, key .. "#offset", st.offset or 0)
        setXMLInt(xml, key .. "#cooldown", st.cooldown or 0)
        if st.hist ~= nil then
            local parts = {}
            for k = 1, 12 do parts[k] = string.format("%.4f", st.hist[k] or 1) end
            setXMLString(xml, key .. "#hist", table.concat(parts, " "))
            setXMLFloat(xml, key .. "#histSum", st.histSum or 0)
            setXMLInt(xml, key .. "#histN", st.histN or 0)
        end
        for j, e in ipairs(st.events) do
            local ek = string.format("%s.event(%d)", key, j - 1)
            setXMLBool(xml, ek .. "#surplus", e.surplus)
            setXMLFloat(xml, ek .. "#factor", e.factor)
            setXMLInt(xml, ek .. "#daysLeft", e.daysLeft)
            setXMLBool(xml, ek .. "#linked", e.linked == true)
        end
        i = i + 1
    end
    for j, ct in ipairs(self.contracts) do
        local key = string.format("marketsAndFutures.contracts.contract(%d)", j - 1)
        setXMLInt(xml, key .. "#id", ct.id)
        setXMLInt(xml, key .. "#farmId", ct.farmId)
        setXMLString(xml, key .. "#fillType", g_fillTypeManager:getFillTypeNameByIndex(ct.fillTypeIndex))
        setXMLFloat(xml, key .. "#amount", ct.amount)
        setXMLFloat(xml, key .. "#remaining", ct.remaining)
        setXMLInt(xml, key .. "#endDay", ct.endDay)
        setXMLFloat(xml, key .. "#lockedMult", ct.lockedMult)
        setXMLFloat(xml, key .. "#lockedPrice", ct.lockedPrice or 0)
        setXMLFloat(xml, key .. "#gain", ct.gain or 0)
        setXMLString(xml, key .. "#stationKey", ct.stationKey or "")
        setXMLString(xml, key .. "#stationName", ct.stationName or "")
    end
    for _, key in ipairs(self.SETTING_KEYS) do setXMLFloat(xml, "marketsAndFutures.settings#" .. key, self.CFG[key]) end
    setXMLInt(xml, "marketsAndFutures.settings#contractCooldownMonths", self.CFG.contractCooldownMonths)
    setXMLBool(xml, "marketsAndFutures.settings#linkEnabled", self.CFG.linkEnabled == true)
    setXMLBool(xml, "marketsAndFutures.settings#autoAccess", self.CFG.autoAccess == true)
    setXMLInt(xml, "marketsAndFutures.settings#preset", self.CFG.preset or 0)
    local bi = 0
    for key in pairs(self.blocked) do
        setXMLString(xml, string.format("marketsAndFutures.blockedStations.station(%d)#key", bi), key)
        bi = bi + 1
    end
    for hi, r in ipairs(self.history) do
        local key = string.format("marketsAndFutures.history.record(%d)", hi - 1)
        setXMLInt(xml, key .. "#id", r.id)
        setXMLInt(xml, key .. "#farmId", r.farmId)
        setXMLString(xml, key .. "#fillType", g_fillTypeManager:getFillTypeNameByIndex(r.fillTypeIndex))
        setXMLFloat(xml, key .. "#amount", r.amount)
        setXMLFloat(xml, key .. "#delivered", r.delivered)
        setXMLFloat(xml, key .. "#lockedPrice", r.lockedPrice)
        setXMLInt(xml, key .. "#result", r.result)
        setXMLFloat(xml, key .. "#penalty", r.penalty)
        setXMLFloat(xml, key .. "#gain", r.gain)
        setXMLInt(xml, key .. "#day", r.day)
        setXMLString(xml, key .. "#station", r.stationName or "")
    end
    local pi = 0
    for fid, perk in pairs(self.perks) do
        local key = string.format("marketsAndFutures.perks.perk(%d)", pi)
        setXMLInt(xml, key .. "#farmId", fid)
        setXMLFloat(xml, key .. "#progress", perk.progress)
        setXMLInt(xml, key .. "#tokens", perk.tokens)
        pi = pi + 1
    end
    setXMLInt(xml, "marketsAndFutures#nextContractId", self.nextContractId)
    if self.lastPeriod ~= nil then setXMLInt(xml, "marketsAndFutures#lastPeriod", self.lastPeriod) end
    saveXMLFile(xml)
    delete(xml)
end

function MarketsAndFutures:loadFromXML(missionInfo)
    if missionInfo == nil or missionInfo.savegameDirectory == nil then return false end
    local path = missionInfo.savegameDirectory .. "/marketsAndFutures.xml"
    if not fileExists(path) then return false end
    local xml = loadXMLFile("marketsAndFutures", path)
    if xml == nil or xml == 0 then return false end

    local i = 0
    while true do
        local key = string.format("marketsAndFutures.fillTypes.fillType(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local idx = g_fillTypeManager:getFillTypeIndexByName(getXMLString(xml, key .. "#name"))
        if idx ~= nil then
            local st = self:getState(idx)
            st.mult = getXMLFloat(xml, key .. "#mult") or 1
            st.trend = getXMLFloat(xml, key .. "#trend") or 1
            st.dayRef = getXMLFloat(xml, key .. "#dayRef") or st.mult
            st.stationKey = getXMLString(xml, key .. "#stationKey") or ""
            st.stationName = getXMLString(xml, key .. "#stationName") or ""
            st.offset = getXMLFloat(xml, key .. "#offset")
            st.cooldown = getXMLInt(xml, key .. "#cooldown") or 0
            local histStr = getXMLString(xml, key .. "#hist")
            if histStr ~= nil then
                local vals = {}
                for v in string.gmatch(histStr, "%S+") do table.insert(vals, tonumber(v) or 1) end
                if #vals == 12 then
                    st.hist = vals
                    st.histSum = getXMLFloat(xml, key .. "#histSum") or 0
                    st.histN = getXMLInt(xml, key .. "#histN") or 0
                end
            end
            st.events = {}
            local j = 0
            while true do
                local ek = string.format("%s.event(%d)", key, j)
                if not hasXMLProperty(xml, ek) then break end
                table.insert(st.events, {
                    surplus = getXMLBool(xml, ek .. "#surplus") or false,
                    factor = getXMLFloat(xml, ek .. "#factor") or 1,
                    daysLeft = getXMLInt(xml, ek .. "#daysLeft") or 1,
                    linked = getXMLBool(xml, ek .. "#linked") or false,
                })
                j = j + 1
            end
        end
        i = i + 1
    end
    i = 0
    while true do
        local key = string.format("marketsAndFutures.contracts.contract(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local idx = g_fillTypeManager:getFillTypeIndexByName(getXMLString(xml, key .. "#fillType"))
        if idx ~= nil then
            table.insert(self.contracts, {
                id = getXMLInt(xml, key .. "#id"), farmId = getXMLInt(xml, key .. "#farmId"),
                fillTypeIndex = idx,
                amount = getXMLFloat(xml, key .. "#amount"), remaining = getXMLFloat(xml, key .. "#remaining"),
                endDay = getXMLInt(xml, key .. "#endDay"), lockedMult = getXMLFloat(xml, key .. "#lockedMult"), lockedPrice = getXMLFloat(xml, key .. "#lockedPrice"), gain = getXMLFloat(xml, key .. "#gain") or 0,
                stationKey = getXMLString(xml, key .. "#stationKey") or "",
                stationName = getXMLString(xml, key .. "#stationName") or "",
            })
        end
        i = i + 1
    end
    self.nextContractId = getXMLInt(xml, "marketsAndFutures#nextContractId") or (#self.contracts + 1)
    self.lastPeriod = getXMLInt(xml, "marketsAndFutures#lastPeriod")
    if hasXMLProperty(xml, "marketsAndFutures.settings#preset") then
        for _, key in ipairs(self.SETTING_KEYS) do
            local v = getXMLFloat(xml, "marketsAndFutures.settings#" .. key)
            if v ~= nil then self.CFG[key] = v end
        end
        self.CFG.contractCooldownMonths = getXMLInt(xml, "marketsAndFutures.settings#contractCooldownMonths") or self.CFG.contractCooldownMonths
        local le = getXMLBool(xml, "marketsAndFutures.settings#linkEnabled")
        if le ~= nil then self.CFG.linkEnabled = le end
        local aa = getXMLBool(xml, "marketsAndFutures.settings#autoAccess")
        if aa ~= nil then self.CFG.autoAccess = aa end
        self.CFG.preset = getXMLInt(xml, "marketsAndFutures.settings#preset") or 0
    end
    self.blocked = {}
    local bi = 0
    while true do
        local bkey = string.format("marketsAndFutures.blockedStations.station(%d)", bi)
        if not hasXMLProperty(xml, bkey) then break end
        local k = getXMLString(xml, bkey .. "#key")
        if k ~= nil and k ~= "" then self.blocked[k] = true end
        bi = bi + 1
    end
    local hi = 0
    while true do
        local key = string.format("marketsAndFutures.history.record(%d)", hi)
        if not hasXMLProperty(xml, key) then break end
        local hidx = g_fillTypeManager:getFillTypeIndexByName(getXMLString(xml, key .. "#fillType"))
        if hidx ~= nil then
            table.insert(self.history, {
                id = getXMLInt(xml, key .. "#id") or 0, farmId = getXMLInt(xml, key .. "#farmId") or 1, fillTypeIndex = hidx,
                amount = getXMLFloat(xml, key .. "#amount") or 0, delivered = getXMLFloat(xml, key .. "#delivered") or 0,
                lockedPrice = getXMLFloat(xml, key .. "#lockedPrice") or 0, result = getXMLInt(xml, key .. "#result") or 1,
                penalty = getXMLFloat(xml, key .. "#penalty") or 0, gain = getXMLFloat(xml, key .. "#gain") or 0,
                day = getXMLInt(xml, key .. "#day") or 0, stationName = getXMLString(xml, key .. "#station") or "",
            })
        end
        hi = hi + 1
    end
    i = 0
    while true do
        local key = string.format("marketsAndFutures.perks.perk(%d)", i)
        if not hasXMLProperty(xml, key) then break end
        local fid = getXMLInt(xml, key .. "#farmId")
        if fid ~= nil then
            self.perks[fid] = {progress = getXMLFloat(xml, key .. "#progress") or 0, tokens = math.min(1, getXMLInt(xml, key .. "#tokens") or 0)}
        end
        i = i + 1
    end
    delete(xml)
    return true
end

-- ===================== LIFECYCLE =====================
function MarketsAndFutures:onMissionLoaded()
    self.isServer = g_currentMission:getIsServer()
    do
        local m, src = self:getDifficultyMultiplier()
        pcall(function() Logging.info(string.format("[MarketsAndFutures] difficulty price multiplier = %.3f (source: %s)", m, src)) end)
    end

    self.useShowOnPriceTable = false
    for _, ft in pairs(g_fillTypeManager.fillTypes) do
        if ft.showOnPriceTable == true then self.useShowOnPriceTable = true break end
    end

    self.fills, self.contracts, self.nextContractId = {}, {}, 1
    self.perks, self.pendingNotes, self.noteTimer = {}, {}, 0
    self.history = {}
    self.blocked = {}
    self.lastPeriod = nil
    self.stationsReady, self.readyTimer = false, 0
    for idx, ft in pairs(g_fillTypeManager.fillTypes) do
        if self:isSellable(ft) then self:getState(idx) end
    end

    if self.isServer then
        if not self:loadFromXML(g_currentMission.missionInfo) then
            self:initialiseNewMarket()
        end
        for _, st in pairs(self.fills) do
            if st.hist == nil then self:seedHistory(st) end
            if st.offset == nil then self:seedOffset(st) end
        end
        self:buildLinks()
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)
        g_messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    end
end

function MarketsAndFutures:update(dt)
    if self.fills == nil then return end
    if self.isServer then
        if not self.stationsReady then
            self.readyTimer = self.readyTimer + dt
            if self.readyTimer > 3000 then
                self:scanPlaceables()
                self.stationsReady = true
                self:ensureContractStations()
            end
        end
        if self.dirty then
            self.dirtyTimer = self.dirtyTimer + dt
            if self.dirtyTimer > 1000 then self:broadcast() end
        end
        if next(self.pendingNotes) ~= nil then
            self.noteTimer = self.noteTimer + dt
            if self.noteTimer >= self.CFG.noteDelayMs then
                self.noteTimer = 0
                self:flushDeliveryNotes()
            end
        end
    elseif not self.scannedClient then
        self.readyTimer = self.readyTimer + dt
        if self.readyTimer > 3000 then self:scanPlaceables(); self.scannedClient = true end
    end
end

-- ===================== HOOKS =====================
-- 1) Every selling station price gets multiplied by the market multiplier.
MarketsAndFutures.origGetPrice = SellingStation.getEffectiveFillTypePrice
SellingStation.getEffectiveFillTypePrice = Utils.overwrittenFunction(SellingStation.getEffectiveFillTypePrice,
    function(station, superFunc, fillTypeIndex, ...)
        MarketsAndFutures:registerStation(station)
        local price = superFunc(station, fillTypeIndex, ...)
        return price * MarketsAndFutures:getMult(fillTypeIndex)
    end)

-- 2) After a sale, settle any contract tied to this station.
SellingStation.addFillLevelFromTool = Utils.overwrittenFunction(SellingStation.addFillLevelFromTool,
    function(station, superFunc, farmId, deltaFillLevel, fillTypeIndex, fillInfo, toolType, ...)
        MarketsAndFutures:registerStation(station)
        local applied
        local capturedType
        if MarketsAndFutures.isServer and #MarketsAndFutures.contracts > 0 then
            -- remember which finance category the game books this sale under (its largest payment), so the
            -- contract adjustment can be booked in the same one
            local mission = g_currentMission
            local ownAddMoney = rawget(mission, "addMoney")
            local origAddMoney = mission.addMoney
            local capturedAmount = 0
            mission.addMoney = function(m, amount, fId, moneyType, ...)
                -- the sale itself is the biggest payment; smaller extras (e.g. Precision Farming's environmental score)
                -- must not decide the finance category
                if type(amount) == "number" and amount > capturedAmount and fId == farmId and moneyType ~= nil then
                    capturedType, capturedAmount = moneyType, amount
                end
                return origAddMoney(m, amount, fId, moneyType, ...)
            end
            local ok, res = pcall(superFunc, station, farmId, deltaFillLevel, fillTypeIndex, fillInfo, toolType, ...)
            mission.addMoney = ownAddMoney
            if not ok then error(res, 0) end
            applied = res
        else
            applied = superFunc(station, farmId, deltaFillLevel, fillTypeIndex, fillInfo, toolType, ...)
        end
        if MarketsAndFutures.isServer and type(applied) == "number" and applied > 0 then
            MarketsAndFutures:applyContracts(station, farmId, applied, fillTypeIndex, toolType, capturedType)
        end
        return applied
    end)

-- 3) Track stations as they are created / removed.
if SellingStation.load ~= nil then
    SellingStation.load = Utils.appendedFunction(SellingStation.load, function(station)
        MarketsAndFutures:registerStation(station)
    end)
end
if SellingStation.delete ~= nil then
    SellingStation.delete = Utils.prependedFunction(SellingStation.delete, function(station)
        MarketsAndFutures:unregisterStation(station)
    end)
end

-- 4) Lifecycle / persistence / join sync.
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function()
    MarketsAndFutures:onMissionLoaded()
end)

FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function(missionInfo)
    MarketsAndFutures:saveToXML(missionInfo)
end)

FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState,
    function(mission, connection)
        if MarketsAndFutures.isServer then connection:sendEvent(MFStateEvent.new()) end
    end)

addModEventListener(MarketsAndFutures)
