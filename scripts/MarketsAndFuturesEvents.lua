-- Network events for Markets and Futures

-- Server -> Client: full market + contract state (optional announcement)
MFStateEvent = {}
local MFStateEvent_mt = Class(MFStateEvent, Event)
InitEventClass(MFStateEvent, "MFStateEvent")

function MFStateEvent.emptyNew()
    return Event.new(MFStateEvent_mt)
end

function MFStateEvent.new(noteKind, noteFill)
    local self = MFStateEvent.emptyNew()
    self.noteKind = noteKind
    self.noteFill = noteFill
    return self
end

function MFStateEvent:writeStream(streamId, connection)
    MarketsAndFutures:writeState(streamId)
    local has = self.noteKind ~= nil
    streamWriteBool(streamId, has)
    if has then
        streamWriteBool(streamId, self.noteKind == "surplus")
        streamWriteUIntN(streamId, self.noteFill, FillTypeManager.SEND_NUM_BITS)
    end
end

function MFStateEvent:readStream(streamId, connection)
    MarketsAndFutures:readState(streamId)
    if streamReadBool(streamId) then
        local surplus = streamReadBool(streamId)
        local fill = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        MarketsAndFutures:showNote(surplus and "surplus" or "demand", fill)
    end
end

function MFStateEvent:run(connection) end


-- Client -> Server: create contract
MFCreateContractEvent = {}
local MFCreateContractEvent_mt = Class(MFCreateContractEvent, Event)
InitEventClass(MFCreateContractEvent, "MFCreateContractEvent")

function MFCreateContractEvent.emptyNew()
    return Event.new(MFCreateContractEvent_mt)
end

function MFCreateContractEvent.new(fillTypeIndex, amount, months)
    local self = MFCreateContractEvent.emptyNew()
    self.fillTypeIndex, self.amount, self.months = fillTypeIndex, amount, months
    return self
end

function MFCreateContractEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
    streamWriteInt32(streamId, self.amount)
    streamWriteUInt8(streamId, self.months)
end

function MFCreateContractEvent:readStream(streamId, connection)
    self.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.amount = streamReadInt32(streamId)
    self.months = streamReadUInt8(streamId)
    self:run(connection)
end

function MFCreateContractEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then
        local farmId = MarketsAndFutures:getFarmIdFromConnection(connection)
        MarketsAndFutures:createContract(farmId, self.fillTypeIndex, self.amount, self.months)
    end
end


-- Client -> Server: cancel contract
MFCancelContractEvent = {}
local MFCancelContractEvent_mt = Class(MFCancelContractEvent, Event)
InitEventClass(MFCancelContractEvent, "MFCancelContractEvent")

function MFCancelContractEvent.emptyNew()
    return Event.new(MFCancelContractEvent_mt)
end

function MFCancelContractEvent.new(id, free)
    local self = MFCancelContractEvent.emptyNew()
    self.id = id
    self.free = free == true
    return self
end

function MFCancelContractEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.id)
    streamWriteBool(streamId, self.free)
end

function MFCancelContractEvent:readStream(streamId, connection)
    self.id = streamReadInt32(streamId)
    self.free = streamReadBool(streamId)
    self:run(connection)
end

function MFCancelContractEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then
        local farmId = MarketsAndFutures:getFarmIdFromConnection(connection)
        MarketsAndFutures:cancelContract(farmId, self.id, self.free)
    end
end


-- Server -> Client: a contract penalty was charged (kind 1 = cancelled, 2 = expired unfilled)
MFPenaltyEvent = {}
local MFPenaltyEvent_mt = Class(MFPenaltyEvent, Event)
InitEventClass(MFPenaltyEvent, "MFPenaltyEvent")

function MFPenaltyEvent.emptyNew()
    return Event.new(MFPenaltyEvent_mt)
end

function MFPenaltyEvent.new(farmId, fillTypeIndex, amount, kind)
    local self = MFPenaltyEvent.emptyNew()
    self.farmId, self.fillTypeIndex, self.amount, self.kind = farmId, fillTypeIndex, amount, kind
    return self
end

function MFPenaltyEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.farmId)
    streamWriteUIntN(streamId, self.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
    streamWriteFloat32(streamId, self.amount)
    streamWriteUInt8(streamId, self.kind)
end

function MFPenaltyEvent:readStream(streamId, connection)
    self.farmId = streamReadUInt8(streamId)
    self.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.amount = streamReadFloat32(streamId)
    self.kind = streamReadUInt8(streamId)
    self:run(connection)
end

function MFPenaltyEvent:run(connection)
    MarketsAndFutures:showPenaltyNote(self.farmId, self.fillTypeIndex, self.amount, self.kind)
end


-- Server -> Client: contract delivery / free-cancel notification for one farm
-- kind 1 = progress, 2 = fulfilled, 3 = free cancel earned, 4 = free cancel used
MFNotifyEvent = {}
local MFNotifyEvent_mt = Class(MFNotifyEvent, Event)
InitEventClass(MFNotifyEvent, "MFNotifyEvent")

function MFNotifyEvent.emptyNew()
    return Event.new(MFNotifyEvent_mt)
end

function MFNotifyEvent.new(farmId, kind, fillTypeIndex, pct, delivered, total)
    local self = MFNotifyEvent.emptyNew()
    self.farmId, self.kind, self.fillTypeIndex = farmId, kind, fillTypeIndex
    self.pct, self.delivered, self.total = pct, delivered, total
    return self
end

function MFNotifyEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.farmId)
    streamWriteUInt8(streamId, self.kind)
    streamWriteUIntN(streamId, self.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
    streamWriteFloat32(streamId, self.pct)
    streamWriteFloat32(streamId, self.delivered)
    streamWriteFloat32(streamId, self.total)
end

function MFNotifyEvent:readStream(streamId, connection)
    self.farmId = streamReadUInt8(streamId)
    self.kind = streamReadUInt8(streamId)
    self.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.pct = streamReadFloat32(streamId)
    self.delivered = streamReadFloat32(streamId)
    self.total = streamReadFloat32(streamId)
    self:run(connection)
end

function MFNotifyEvent:run(connection)
    MarketsAndFutures:showNotify(self.farmId, self.kind, self.fillTypeIndex, self.pct, self.delivered, self.total)
end


-- Client -> Server: delete one entry of the contract history
MFDeleteHistoryEvent = {}
local MFDeleteHistoryEvent_mt = Class(MFDeleteHistoryEvent, Event)
InitEventClass(MFDeleteHistoryEvent, "MFDeleteHistoryEvent")

function MFDeleteHistoryEvent.emptyNew()
    return Event.new(MFDeleteHistoryEvent_mt)
end

function MFDeleteHistoryEvent.new(id)
    local self = MFDeleteHistoryEvent.emptyNew()
    self.id = id
    return self
end

function MFDeleteHistoryEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.id)
end

function MFDeleteHistoryEvent:readStream(streamId, connection)
    self.id = streamReadInt32(streamId)
    self:run(connection)
end

function MFDeleteHistoryEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then
        local farmId = MarketsAndFutures:getFarmIdFromConnection(connection)
        MarketsAndFutures:deleteHistory(farmId, self.id)
    end
end
