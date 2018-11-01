local entity = {}


local enet = require 'enet'
local bitser = require 'bitser'


local function genId()
    return math.random(2 ^ 30) -- Going with dumb `id` generation for now
end


-- Types

local typesByName, typeIdToName = {}, {}

function entity.registerType(typeName, ty)
    assert(not typesByName[typeName])

    ty = ty or {}
    ty.__typeName = typeName
    typesByName[typeName] = ty

    table.insert(typeIdToName, typeName)
    ty.__typeId = #typeIdToName

    return ty
end

local function actuallyConstruct(typeName, props)
    local ent

    local ty = typesByName[typeName]
    if ty.construct then -- User-defined construction
        ent = ty:construct(props)
    else -- Default construction
        ty.__index = ty
        ent = setmetatable({}, ty)
    end
    ent.__typeId = ty.__typeId

    if ent.didConstruct then -- `didConstruct` event
        ent:didConstruct(props)
    end
    return ent
end


-- Manager metatables, creation

local Common = {}
Common.__index = Common

local Client = setmetatable({}, Common)
Client.__index = Client

local Server = setmetatable({}, Common)
Server.__index = Server

function entity.newServer(props)
    local mgr = setmetatable({}, Server)
    mgr:init(props)
    return mgr
end

function entity.newClient(props)
    local mgr = setmetatable({}, Client)
    mgr:init(props)
    return mgr
end


-- Initialization

function Common:init(props)
    -- Each of these tables is a 'set' of the form `t[k.__id] = k` for all `k` in the set
    self.all = {} -- Entities we can read
    self.needsSend = {} -- Entities whose sync we need to send
    self.receivedSyncsDumps = {} -- Received syncs pending apply
end

function Server:init(props)
    Common.init(self)

    self.controllerTypeName = assert(props.controllerTypeName,
        "server needs `props.controllerTypeName`")

    self.host = enet.host_create(props.address or '*:22122')
    self.controllers = {}
end

function Client:init(props)
    Common.init(self)

    assert(props.address, "client needs `props.address` to connect to")

    self.host = enet.host_create()
    self.serverPeer = self.host:connect(props.address)
end


-- RPCs

local rpcNameToId, rpcIdToName = {}, {}

local function defRpc(name)
    assert(not rpcNameToId[name])
    table.insert(rpcIdToName, name)
    rpcNameToId[name] = #rpcIdToName
end

local function rpcToData(name, ...)
    return bitser.dumps({ rpcNameToId[name], ... }) -- TODO(nikki): Allow `nil`s in between
end

local function dataToRpc(data)
    local t = bitser.loads(data)
    t[1] = assert(rpcIdToName[t[1]], "invalid rpc id")
    return unpack(t)
end

function Common:callRpc(peer, name, ...)
    self[name](self, peer, ...)
end


-- Spawning

function Server:spawn(typeName, props)
    props = props or {}

    local ent = actuallyConstruct(typeName, props)
    ent.__id = genId()
    ent.__mgr = self

    self.all[ent.__id] = ent

    if ent.didSpawn then
        ent:didSpawn(props)
    end
    self:sync(ent)

    return ent
end


-- Sync

function Server:sync(ent)
    self.needsSend[ent.__id] = ent
end

function Client:sync(ent)
end

function Server:sendSyncs(peer, syncs) -- `peer == nil` to broadcast to all connected peers
    for _, ent in pairs(syncs) do
        ent.__mgr = nil
    end
    local data = rpcToData('receiveSyncs', bitser.dumps(syncs)) -- TODO(nikki): Convert
    for _, ent in pairs(syncs) do
        ent.__mgr = self
    end

    if peer then
        peer:send(data)
    else
        self.host:broadcast(data)
    end
end

defRpc('receiveSyncs')
function Client:receiveSyncs(peer, syncs)
    table.insert(self.receivedSyncsDumps, syncs)
end

function Common:applyReceivedSyncs()
    -- Our bitser fork uses this to deserialize entity references
    function __DESERIALIZE_ENTITY_REF(id, typeId)
        local ent = self.all[id]
        if not ent then
            ent = actuallyConstruct(typeIdToName[typeId])
            ent.__id = id
            ent.__mgr = self
            self.all[id] = ent
        end
        return ent
    end

    -- Collect latest syncs per-entity
    local latestSyncs = {}
    for _, dump in pairs(self.receivedSyncsDumps) do
        local syncs = bitser.loads(dump)
        for _, sync in pairs(syncs) do
            latestSyncs[sync.__id] = sync
        end
    end
    self.receivedSyncsDumps = {}

    -- Actually apply the syncs
    local syncedEnts = {}
    for _, sync in pairs(latestSyncs) do
        local ent = __DESERIALIZE_ENTITY_REF(sync.__id, sync.__typeId)
        if ent.willSync then
            ent:willSync(sync)
        end
        for k in pairs(ent) do
            if sync[k] == nil then
                ent[k] = nil
            end
        end
        for k, v in pairs(sync) do
            ent[k] = v
        end
        ent.__mgr = self -- Just to be sure
        syncedEnts[ent] = true
    end
    for ent in pairs(syncedEnts) do
        if ent.didSync then
            ent:didSync()
        end
    end

    __DESERIALIZE_ENTITY_REF = nil
end


-- Controllers and connection / disconnection

defRpc('receiveControllerCall')
function Server:receiveControllerCall(peer, methodName, ...)
    local controller = assert(self.controllers[peer:connect_id()], "no controller for this `peer`")
    local method = assert(controller[methodName], "controller has no method '" .. methodName .. "'")
    method(controller, ...)
end

defRpc('receiveControllerId')
function Client:receiveControllerId(peer, controllerId)
    self:applyReceivedSyncs() -- Make sure we've sync'd the controller
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
    local clientId = peer:connect_id()
    assert(not self.controllers[clientId], "`clientId` clash")
    local controller = self:spawn(self.controllerTypeName, { __clientId = clientId })
    self.controllers[clientId] = controller
    self:sendSyncs(peer, self.all)
    peer:send(rpcToData('receiveControllerId', controller.__id))
end

function Client:didConnect()
end

function Server:didDisconnect(peer)
    local clientId = peer:connect_id()
    assert(self.controllers[clientId], "no controller for this `peer`")
    -- TODO(nikki): Despawn
end

function Client:didDisconnect()
end


-- Top-level process

function Common:process()
    while true do
        local event = self.host:service(0)
        if not event then break end

        -- TODO(nikki): Error-tolerance
        if event.type == 'receive' then
            self:callRpc(event.peer, dataToRpc(event.data))
        elseif event.type == 'connect' then
            self:didConnect(event.peer)
        elseif event.type == 'disconnect' then
            self:didDisconnect(event.peer)
        end
    end

    self:processSyncs()

    self.host:flush()
end

function Server:processSyncs()
    self:sendSyncs(nil, self.needsSend)
    self.needsSend = {}
end

function Client:processSyncs()
    self:applyReceivedSyncs()
end


return entity
