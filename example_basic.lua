local sync = require 'sync'

local Player = sync.registerType('Player')

function Player:didSpawn()
    self.x, self.y = love.graphics.getWidth() * math.random(), love.graphics.getHeight() * math.random()
    self.r, self.g, self.b = 0.2 + 0.8 * math.random(), 0.2 + 0.8 * math.random(), 0.2 + 0.8 * math.random()
end

function Player:draw()
    love.graphics.push('all')
    love.graphics.setColor(self.r, self.g, self.b)
    love.graphics.ellipse('fill', self.x, self.y, 40, 40)
    love.graphics.pop('all')
end

local Controller = sync.registerType('Controller')

function Controller:didSpawn()
    self.player = self.__mgr:spawn('Player')
end

function Controller:willDespawn()
    self.__mgr:despawn(self.player)
    self.player = nil
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
    if client then
        for _, ent in pairs(client.all) do
            if ent.draw then
                ent:draw()
            end
        end
    end
end

