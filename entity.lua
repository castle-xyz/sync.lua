local entity = {}


local enet = require 'enet'
local bitser = require 'bitser'


local function genId()
    return tostring(math.random(2 ^ 30)) -- Going with dumb `id` generation for now
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
    self.receivedSyncs = {} -- Received syncs pending apply
end

function Server:init(props)
    Common.init(self)

    assert(props.controllerTypeName, "server needs `props.controllerTypeName`")

    self.host = enet.host_create(props.address or '*:22122')
    self.serverController = self:spawn(props.controllerTypeName)
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
    return bitser.dumps({ rpcNameToId[name], ... })
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

--defRpc('requestSpawn')
--function Server:requestSpawn(peer, typeName, props)
--    props = props or {}
--    props.__clientId = peer:connect_id()
--    self:spawn(typeName, props)
--end
--
--function Client:spawn(typeName, props)
--    self.serverPeer:send(rpcToData('requestSpawn', typeName, props))
--end


-- Sync

function Server:sync(ent)
    self.needsSend[ent.__id] = ent
end

function Server:sendSyncs(peer, syncs) -- `peer == nil` to broadcast to all connected peers
    for _, ent in pairs(syncs) do
        ent.__mgr = nil
    end
    local data = rpcToData('receiveSyncs', syncs) -- TODO(nikki): Convert
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
    for _, sync in pairs(syncs) do
        -- TODO(nikki): Validate, queue
        self.receivedSyncs[sync.__id] = sync
    end
end

function Common:applyReceivedSyncs()
    local syncedEnts = {}
    for _, sync in pairs(self.receivedSyncs) do
        -- TODO(nikki): Dequeue
        local ent = self.all[sync.__id]
        if not ent then
            ent = actuallyConstruct(typeIdToName[sync.__typeId])
            ent.__mgr = self
            self.all[sync.__id] = ent
        end
        if ent.willSync then
            ent:willSync(sync)
        end
        for k, v in pairs(sync) do
            ent[k] = v
        end
        syncedEnts[ent] = true
    end
    self.receivedSyncs = {}
    for ent in pairs(syncedEnts) do
        if ent.didSync then
            ent:didSync()
        end
    end
end


-- Connection / disconnection

function Server:didConnect(peer)
    if self.serverController.didConnect then
        self.serverController:didConnect(peer:connect_id())
    end
    self:sendSyncs(peer, self.all)
end

function Client:didConnect()
end

function Server:didDisconnect(peer)
    if self.serverController.didDisconnect then
        self.serverController:didDisconnect(peer:connect_id())
    end
end

function Client:didDisconnect()
end


-- Top-level process

function Common:process()
    while true do
        local event = self.host:service(0)
        if not event then break end

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
