local sync = require 'sync'

local Controller = sync.registerType('Controller')

function Controller:didSpawn()
    print('a client connected')
end

function Controller:willDespawn()
    print('a client disconnected')
end

local server, client

function love.keypressed(key)
    if key == '1' then
        server = sync.newServer { address = '*:22122', controllerTypeName = 'Controller' }
    end
    if key == '2' then
        client = sync.newClient { address = '192.168.1.80:22122' }
    end
end

function love.update(dt)
    if server then
        server:process()
    end
    if client then
        client:process()
    end
end

function love.draw()
    love.graphics.print('hello, world!', 20, 20)
end

