local entity = {}


local enet = require 'enet'
local bitser = require 'https://raw.githubusercontent.com/gvx/bitser/4f2680317cdc8b6c5af7133835de5075f2cc0d1f/bitser.lua'


local function genId()
    return tostring(math.random(2 ^ 30)) -- Going with dumb `id` generation for now
end


-- Types

local typesByName = {}

function entity.registerType(typeName, ty)
    ty = ty or {}
    ty.__typeName = typeName
    typesByName[typeName] = ty
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

    if ent.onConstruct then -- `onConstruct` event
        ent:onConstruct(props)
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
    self.entitiesById = {}
end

function Server:init(props)
    Common.init(self)

    self.serverHost = enet.host_create(props.address or '*:22122')
end

function Client:init(props)
    Common.init(self)

    self.clientHost = enet.host_create()
    assert(props.address, "client needs `props.address` to connect to")
    self.serverPeer = self.clientHost:connect(props.address)
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
    local ent = actuallyConstruct(typeName, props)
    ent.__id = genId()
    ent.__mgr = self

    -- Add to map, `didSpawn` event
    self.entitiesById[ent.__id] = ent
    if ent.didSpawn then
        ent:didSpawn(props)
    end

    -- TODO(nikki): Send

    return ent
end

defRpc('requestSpawn')
function Server:requestSpawn(peer, typeName, props)
    -- TODO(nikki): Validate
    self:spawn(typeName, props)
end

function Client:spawn(typeName, props)
    self.serverPeer:send(rpcToData('requestSpawn', typeName, props))
end


-- Updating

function Common:serviceRpcs(host)
    while true do
        local event = host:service(0)
        if not event then break end

        if event.type == 'receive' then
            self:callRpc(event.peer, dataToRpc(event.data))
        end
    end
end

function Server:update(dt)
    self:serviceRpcs(self.serverHost)
end

function Client:update(dt)
    self:serviceRpcs(self.clientHost)
end


return entity
