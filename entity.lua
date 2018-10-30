local entity = {}


local uuid = require 'uuid'
local multi = require 'multi'


local Entity = {}

function Entity:new()
    local ent = setmetatable({}, { __index = self })

    ent.__id = ent.__id or uuid()

    return ent
end


return Entity
