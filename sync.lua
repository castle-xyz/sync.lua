local sync = {}


local enet = require 'enet'
local bitser = require 'bitser'


local pairs, next, type = pairs, next, type


local CLOCK_SYNC_PERIOD = 1 -- Seconds between clock sync attempts

-- 200 sync channels, 1 clock sync channel
local MAX_SYNC_CHANNEL = 199
local CLOCK_SYNC_CHANNEL = MAX_SYNC_CHANNEL + 1
local MAX_CHANNEL = CLOCK_SYNC_CHANNEL

local SYNC_LEAVE = 1 -- Sentinel to sync entity leaving -- single byte when bitser'd


-- Utilities to reduce GC trashing

local function clearTable(t)
    for k in pairs(t) do t[k] = nil end
end

local pool = {}

local function getFromPool()
    return table.remove(pool) or {}
end

local function releaseToPool(t, ...)
    if t then
        clearTable(t)
        table.insert(pool, t)
        releaseToPool(...)
    end
end


-- Ids

local idCounter = 0

local function genId() -- Must be called on server
    idCounter = idCounter + 1
    return idCounter
end


-- Types

local typeNameToType, typeIdToName = {}, {}

function sync.registerType(typeName, ty)
    assert(not typeNameToType[typeName], "type with name '" .. typeName .. "' already registered")

    ty = ty or {}
    ty.__typeName = typeName
    typeNameToType[typeName] = ty

    table.insert(typeIdToName, typeName)
    ty.__typeId = #typeIdToName

    return ty
end


-- Manager metatables, creation

local Common = {}
Common.__index = Common

local Client = setmetatable({}, Common)
Client.__index = Client

local Server = setmetatable({}, Common)
Server.__index = Server

function sync.newServer(options)
    local mgr = setmetatable({}, Server)
    mgr:init(options)
    return mgr
end

function sync.newClient(options)
    local mgr = setmetatable({}, Client)
    mgr:init(options)
    return mgr
end


-- Initialization, disconnection

function Common:init(options)
    self.all = {} -- `ent.__id` -> `ent` for all on server / all sync'd on client
    self.allPerType = {} -- `ent.__typeName` -> `ent.__id` -> `ent` for all in `self.all`
    for typeName in pairs(typeNameToType) do
        self.allPerType[typeName] = {}
    end
end

function Server:init(options)
    Common.init(self)

    self.isServer, self.isClient = true, false

    self.controllerTypeName = assert(options.controllerTypeName,
        "server needs `options.controllerTypeName`")

    self.host = enet.host_create(options.address or '*:22122', 64, MAX_CHANNEL + 1)
--    self.host:compress_with_range_coder()
    if not self.host then
        error("couldn't create server, port may already be in use")
    end

    self.controllers = {} -- `peer` -> controller

    self.syncsPerType = {} -- `ent.__typeName` -> `ent.__id` -> (`ent` or `SYNC_LEAVE`)
    for typeName in pairs(typeNameToType) do
        self.syncsPerType[typeName] = {}
    end
    self.peerHasPerType = {} -- `peer` -> `ent.__typeName` -> `ent.__id` -> `true` for all on `peer`

    self.nextSyncChannel = 0
end

function Client:init(options)
    Common.init(self)

    assert(options.address, "client needs `options.address` to connect to")

    self.isServer, self.isClient = false, true

    self.host = enet.host_create()
--    self.host:compress_with_range_coder()

    self.serverPeer = self.host:connect(options.address, MAX_CHANNEL + 1)
    self.controller = nil

    self.incomingSyncDumps = {} -- `ent.__id` -> `bitser.dumps(sync)` or `SYNC_LEAVE`
    self.lastReceivedTimestamp = {}

    self.lastClockSyncTime = nil
    self.lastClockSyncDelta = nil
end

function Client:disconnect()
    self.serverPeer:disconnect()
    self.host:flush()
end


-- RPCs

local rpcNameToId, rpcIdToName = {}, {}

local function defRpc(name)
    if not rpcNameToId[name] then
        table.insert(rpcIdToName, name)
        rpcNameToId[name] = #rpcIdToName
    end
end

local function rpcToData(name, ...)
    return bitser.dumps({ rpcNameToId[name], select('#', ...), ... })
end

local function dataToRpc(data)
    local t = bitser.loads(data)
    return assert(rpcIdToName[t[1]], "invalid rpc id"), unpack(t, 3, t[2] + 2)
end

function Common:callRpc(peer, name, ...)
    self[name](self, peer, ...)
end


-- Querying

function Common:getAll()
    local result = {}
    for id, ent in pairs(self.all) do
        result[id] = ent
    end
    return result
end

function Common:getById(id)
    if id == nil then
        return nil
    end
    return self.all[id]
end

function Common:getByType(typeName)
    local result = {}
    for id, ent in pairs(self.allPerType[typeName]) do
        result[id] = ent
    end
    return result
end


-- Spawning

function Common:construct(id, typeName)
    local ent
    local ty = assert(typeNameToType[typeName], "no type with name '" .. typeName .. "'")
    if ty.construct then -- User-defined construction
        ent = ty:construct()
    else -- Default construction
        ty.__index = ty
        ent = setmetatable({}, ty)
    end

    ent.__typeId = ty.__typeId
    ent.__id = id
    ent.__mgr = self
    ent.__local = {}

    self.all[id] = ent
    self.allPerType[typeName][id] = ent

    if ent.didConstruct then
        ent:didConstruct()
    end
    return ent
end

function Common:destruct(ent)
    if ent.__destructed then
        return
    end
    if ent.willDestruct then
        ent:willDestruct()
    end

    local id = ent.__id
    self.allPerType[ent.__typeName][id] = nil
    self.all[id] = nil

    ent.__destructed = true
    ent.__mgr = nil
end

function Server:spawn(typeName, ...)
    local id = genId()
    local ent = self:construct(id, typeName)
    if ent.didSpawn then
        ent:didSpawn(...)
    end
    self:sync(ent)
    return id, ent
end

function Server:despawn(entOrId)
    local ent = type(entOrId) == 'table' and entOrId or self:getById(entOrId)
    if ent.__despawned then
        return
    end
    if ent.willDespawn then
        ent:willDespawn()
    end
    ent.__despawned = true
    self:sync(ent)
    self:destruct(ent)
end


-- Sync

function Server:sync(entOrId)
    local ent = type(entOrId) == 'table' and entOrId or self:getById(entOrId)
    self.syncsPerType[ent.__typeName][ent.__id] = ent.__despawned and SYNC_LEAVE or ent
end

function Client:sync(entOrId)
end

function Server:sendSyncs(peer, syncsPerType, channel)
    if not next(syncsPerType) then -- Empty?
        return
    end

    -- Rotate channels unless specified
    if not channel then
        channel = self.nextSyncChannel
        self.nextSyncChannel = (self.nextSyncChannel + 1) % (MAX_SYNC_CHANNEL + 1)
    end

    -- Memoized function to dump so we only serialize each required entity once
    local allDumps = getFromPool()
    local function getDump(id)
        local dump = allDumps[id]
        if dump == nil then
            local ent = self.all[id]
            if not ent then
                dump = SYNC_LEAVE
            else
                local savedLocal = ent.__local
                ent.__local = nil
                ent.__mgr = nil
                dump = bitser.dumps(ent) -- TODO(nikki): `:toSync` event
                ent.__local = savedLocal
                ent.__mgr = self
            end
            allDumps[id] = dump
        end
        return dump
    end

    -- Collect dumps per peer we're sending to and send them along with a timestamp
    local timestamp = love.timer.getTime()
    local controllers = peer and { [peer] = self.controllers[peer] } or self.controllers
    for peer, controller in pairs(controllers) do
        local dumps = getFromPool()
        for typeName, syncs in pairs(syncsPerType) do
            local has = self.peerHasPerType[peer][typeName]
            local ty = typeNameToType[typeName]
            if ty.getRelevants then -- Has a `.getRelevants` query, use that
                local relevants = ty.getRelevants(controller)
                for id in pairs(has) do
                    if not relevants[id] then
                        dumps[id] = SYNC_LEAVE
                        has[id] = nil
                    end
                end
                for id in pairs(relevants) do
                    dumps[id] = getDump(id)
                    has[id] = true
                end
            else -- No `.getRelevants`, iterate through all in `syncs`
                for id, sync in pairs(syncs) do
                    if sync ~= SYNC_LEAVE and
                            sync.isRelevant and sync:isRelevant(controller) == false then
                        sync = SYNC_LEAVE
                    end
                    if not (sync == SYNC_LEAVE and not has[id]) then
                        dumps[id] = sync == SYNC_LEAVE and SYNC_LEAVE or getDump(id)
                    end
                    has[id] = sync ~= SYNC_LEAVE and true or nil
                end
            end
        end
        if next(dumps) then -- Non-empty?
            peer:send(rpcToData('receiveSyncDumps', dumps, timestamp), channel)
        end
        releaseToPool(dumps)
    end

    releaseToPool(allDumps)
end

defRpc('receiveSyncDumps')
function Client:receiveSyncDumps(peer, dumps, timestamp)
    for id, dump in pairs(dumps) do
        local lastReceivedTimestamp = self.lastReceivedTimestamp[id]
        if not lastReceivedTimestamp or timestamp > lastReceivedTimestamp then
            self.incomingSyncDumps[id] = { dump = dump, timestamp = timestamp }
            self.lastReceivedTimestamp[id] = timestamp
        end
    end
end

function Common:applyReceivedSyncs()
    if not next(self.incomingSyncDumps) then -- Nothing to apply?
        return
    end

    if not self.lastClockSyncDelta then -- Wait till clock sync
        return
    end

    -- Deserialize syncs and notify leavers
    local leavers = getFromPool() -- `ent.__id` -> `ent` for entities that left
    local appliable = getFromPool() -- `id` -> `sync` for non-leaving syncs
    for id, row in pairs(self.incomingSyncDumps) do
        local sync = type(row.dump) == 'string' and bitser.loads(row.dump) or row.dump
        if type(sync) == 'table' then
            sync.__timestamp = row.timestamp
        end
        if sync == SYNC_LEAVE then
            local ent = self.all[id]
            if ent then
                if ent.willLeave then
                    ent:willLeave()
                end
                leavers[id] = ent
            end
        else
            appliable[id] = sync
        end
    end
    clearTable(self.incomingSyncDumps)

    -- Destruct leavers
    for id, ent in pairs(leavers) do
        self:destruct(ent)
    end

    -- Apply syncs then notify
    local time = self:getTime()
    local synced, enterers = getFromPool(), getFromPool()
    for id, sync in pairs(appliable) do
        local ent = self.all[id]
        if not ent then -- Entered -- construct and remember to notify later
            ent = self:construct(id, typeIdToName[sync.__typeId])
            enterers[ent] = true
        end
        local defaultSyncBehavior = true
        if ent.willSync then -- Notify `:willSync` and check if it asks us to skip default syncing
            defaultSyncBehavior = ent:willSync(sync, time - sync.__timestamp)
        end
        if defaultSyncBehavior ~= false then -- Just copy members by default
            local savedLocal = ent.__local
            for k in pairs(ent) do
                if sync[k] == nil then
                    ent[k] = nil
                end
            end
            for k, v in pairs(sync) do
                if k ~= '__timestamp' then
                    ent[k] = v
                end
            end
            ent.__local = savedLocal
        end
        ent.__mgr = self
        synced[ent] = true
    end
    for ent in pairs(enterers) do
        if ent.didEnter then
            ent:didEnter()
        end
    end
    for ent in pairs(synced) do
        if ent.didSync then
            ent:didSync()
        end
    end

    releaseToPool(leavers, appliable, synced, enterers)
end


-- Controllers and connection / disconnection

defRpc('receiveControllerCall')
function Server:receiveControllerCall(peer, methodName, ...)
    local controller = assert(self.controllers[peer], "no controller for this `peer`")
    local method = assert(controller[methodName], "controller has no method '" .. methodName .. "'")
    method(controller, ...)
end

defRpc('receiveControllerId')
function Client:receiveControllerId(peer, controllerId)
    self:applyReceivedSyncs() -- Make sure we've received the controller
    local controller = self.all[controllerId]
    self.controller = setmetatable({}, {
        __index = function(t, k)
            local v = controller[k]
            if type(v) == 'function' then
                t[k] = function(_, ...)
                    self.serverPeer:send(rpcToData('receiveControllerCall', k, ...))
                end
                return t[k]
            else
                return v
            end
        end
    })
end

function Server:didConnect(peer)
    -- Create a controller and initialize per-peer data
    assert(not self.controllers[peer], "controller for `peer` already exists")
    local controllerId, controller = self:spawn(self.controllerTypeName)
    self.controllers[peer] = controller
    self.peerHasPerType[peer] = {}
    for typeName in pairs(typeNameToType) do
        self.peerHasPerType[peer][typeName] = {}
    end

    -- Send all of these on channel 0 to ensure in-order delivery
    peer:send(rpcToData('receiveClockSync', nil, love.timer.getTime()), 0)
    self:sendSyncs(peer, self.allPerType, 0)
    peer:send(rpcToData('receiveControllerId', controllerId), 0)
end

function Client:didConnect()
end

function Server:didDisconnect(peer)
    local controller = assert(self.controllers[peer], "no controller for this `peer`")
    self.controllers[peer] = nil
    self.peerHasPerType[peer] = nil
    self:despawn(controller)
end

function Client:didDisconnect()
    self.controller = nil
end


-- Clock sync

defRpc('receiveClockSyncRequest')
function Server:receiveClockSyncRequest(peer, requestTime)
    peer:send(rpcToData('receiveClockSync', requestTime, love.timer.getTime()), CLOCK_SYNC_CHANNEL)
end

defRpc('receiveClockSync')
function Client:receiveClockSync(peer, requestTime, serverTime)
    local now = love.timer.getTime()
    local delta = serverTime + (requestTime and 0.5 * (now - requestTime) or 0) - now
    if not self.lastClockSyncDelta then
        self.lastClockSyncDelta = delta
    else
        self.lastClockSyncDelta = self.lastClockSyncDelta + (delta - self.lastClockSyncDelta) / 8
    end
end

function Server:getTime()
    return love.timer.getTime()
end

function Client:getTime()
    return love.timer.getTime() + self.lastClockSyncDelta
end


-- Top-level process

function Common:process()
    local errs = {}

    while true do
        local event = self.host:service(0)
        if not event then break end

        local success, err = pcall(function()
            if event.type == 'receive' then
                self:callRpc(event.peer, dataToRpc(event.data))
            elseif event.type == 'connect' then
                self:didConnect(event.peer)
            elseif event.type == 'disconnect' then
                self:didDisconnect(event.peer)
            end
        end)
        table.insert(errs, err)
    end

    self:processSyncs()

    self.host:flush()

    if next(errs) then
        error('`:process()` errors:\n\t' .. table.concat(errs, '\n\t'))
    end
end

function Server:processSyncs()
    self:sendSyncs(nil, self.syncsPerType)
    for _, syncs in pairs(self.syncsPerType) do
        clearTable(syncs)
    end
end

function Client:processSyncs()
    self:applyReceivedSyncs()

    -- Initiate a clock sync every `CLOCK_SYNC_PERIOD` seconds
    if self.serverPeer:state() == 'connected' then
        local now = love.timer.getTime()
        if not self.lastClockSyncTime or now - self.lastClockSyncTime >= CLOCK_SYNC_PERIOD then
            self.serverPeer:send(rpcToData('receiveClockSyncRequest', now))
            self.lastClockSyncTime = now
        end
    end
end


return sync
