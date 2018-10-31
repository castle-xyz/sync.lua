local entity = require 'entity'

local W, H = 0.5 * love.graphics.getWidth(), 0.5 * love.graphics.getHeight()



local Player = entity.registerType('Player')

function Player:didSpawn(props)
    self.x = W * math.random()
    self.y = H * math.random()
end

function Player:draw()
    love.graphics.ellipse('fill', self.x, self.y, 20, 20)
end

function Player:update(dt)
    self.x = self.x + 20 * dt
end



-- 4 clients

local server
local clients = {}

function love.update(dt)
    if server then
        server:process()

        for id, ent in pairs(server.owned) do
            ent:update(dt)
            server:sync(ent)
        end
    end

    for _, client in pairs(clients) do
        client:process()
    end
end

function love.keypressed(k)
    if k == 's' then
        server = entity.newServer { address = '*:22122' }
    end
    if k == 'c' then
        for i = 1, 4 do
            clients[i] = entity.newClient { address = '10.0.1.39:22122' }
        end
    end

    if k == 'i' then
        clients[1]:spawn('Player', { })
    end
    if k == 'o' then
        clients[2]:spawn('Player', { })
    end
end

function love.draw()
    for i, client in ipairs(clients) do
        love.graphics.push('all')

        local dx = (require('bit')).band(i - 1, 1) * W
        local dy = (require('bit')).band(i - 1, 2) / 2 * H

        love.graphics.translate(dx, dy)
        love.graphics.setScissor(dx, dy, W, H)
        love.graphics.print('client ' .. client.serverPeer:state(), 20, 20)

        for id, ent in pairs(client.all) do
            ent:draw()
        end

        love.graphics.pop()
    end
end
