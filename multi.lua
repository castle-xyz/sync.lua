local multi = {}


local sock = require 'https://raw.githubusercontent.com/camchenry/sock.lua/b4a20aadf67480e5d06bfd06727dacd167d6f0cc/sock.lua'
local bitser = require 'https://raw.githubusercontent.com/gvx/bitser/4f2680317cdc8b6c5af7133835de5075f2cc0d1f/bitser.lua'


local DEFAULT_PORT = 22122


function multi.newServer(ip, port)
    local s = sock.newServer(ip or '*', port or DEFAULT_PORT)
    s:setSerialization(bitser.dumps, bitser.loads)
    return s
end

function multi.newClient(ip, port)
    local c = sock.newClient(assert(ip, 'clients need `ip`'), port or DEFAULT_PORT)
    c:setSerialization(bitser.dumps, bitser.loads)
    c:connect()
    return c
end


return multi
