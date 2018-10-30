local sync = {}


local multi = require 'multi'

local server, client


function sync.startServer()
    server = multi.newServer()
end

function sync.startClient(ip)
    server = multi.newClient(ip)
end


return sync
