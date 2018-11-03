local sync = require 'sync'

local SERVER_ADDRESS = '192.168.1.80'



-- Controller -- one of these is spawned automatically by the system per client that connects, and
-- is despawned on disconnect

local Controller = sync.registerType('Controller')

function Controller:didSpawn()
    print('a client connected')
end

function Controller:willDespawn()
    print('a client disconnected')
end



-- Server / client instances and top-level Love events

local server, client

function love.update(dt)
    -- Both server and client need `:process()` called on them every frame
    if server then
        server:process()
    end
    if client then
        client:process()
    end
end

function love.keypressed(k)
    -- Spawn server or client instances as the user asks. The server needs to know the name of our
    -- `Controller` type.
    if k == '1' then
        server = sync.newServer {
            address = '*:22122',
            controllerTypeName = 'Controller',
        }
    end
    if k == '2' then
        client = sync.newClient { address = SERVER_ADDRESS .. ':22122' }
    end
end
