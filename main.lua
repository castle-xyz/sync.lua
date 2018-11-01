local entity = require 'entity'

local W, H = 0.5 * love.graphics.getWidth(), 0.5 * love.graphics.getHeight()



local Gun = entity.registerType('Gun')

Gun.depth = 200

function Gun:didSpawn(props)
    self.x, self.y = props.x, props.y

    self.r, self.g, self.b = math.random(), math.random(), math.random()
end

function Gun:draw()
    love.graphics.push('all')
    love.graphics.setColor(self.r, self.g, self.b)
    love.graphics.rectangle('fill', self.x, self.y, 15, 15)
    love.graphics.pop()
end


local Player = entity.registerType('Player')

Player.depth = 100

function Player:didSpawn(props)
    self.x, self.y = W * math.random(), H * math.random()
    self.walkState = { up = false, down = false, left = false, right = false }

    self.r, self.g, self.b = math.random(), math.random(), math.random()

    local gunX, gunY = self:_gunPos()
    self.gun = self.__mgr:spawn('Gun', { x = gunX, y = gunY })
end

function Player:draw()
    love.graphics.push('all')
    love.graphics.setColor(self.r, self.g, self.b)
    love.graphics.ellipse('fill', self.x, self.y, 40, 40)
    love.graphics.pop()
end

function Player:update(dt)
    local vx, vy = 0, 0
    if self.walkState.up then vy = vy - 40 end
    if self.walkState.down then vy = vy + 40 end
    if self.walkState.left then vx = vx - 40 end
    if self.walkState.right then vx = vx + 40 end
    self.x, self.y = self.x + vx * dt, self.y + vy * dt

    self.gun.x, self.gun.y = self:_gunPos()
end

function Player:_gunPos()
    return self.x + 10, self.y - 10
end


local Controller = entity.registerType('Controller')

function Controller:didSpawn(props)
    self.player = self.__mgr:spawn('Player')
end

function Controller:setWalkState(walkState)
    self.player.walkState = walkState
end



-- 4 clients

local server
local clients = {}

function love.update(dt)
    if server then
        for id, ent in pairs(server.all) do
            if ent.update then
                ent:update(dt)
            end
            server:sync(ent)
        end

        server:process()
    end

    for _, client in pairs(clients) do
        client:process()
    end
end

local function updateWalkState()
    if clients[1] and clients[1].controller then
        clients[1].controller:setWalkState({
            up = love.keyboard.isDown('up'),
            down = love.keyboard.isDown('down'),
            left = love.keyboard.isDown('left'),
            right = love.keyboard.isDown('right'),
        })
    end
    if clients[2] and clients[2].controller then
        clients[2].controller:setWalkState({
            up = love.keyboard.isDown('w'),
            down = love.keyboard.isDown('s'),
            left = love.keyboard.isDown('a'),
            right = love.keyboard.isDown('d'),
        })
    end
end

function love.keypressed(k)
    updateWalkState()

    if k == '1' then
        server = entity.newServer {
            address = '*:22122',
            controllerTypeName = 'Controller',
        }
    end
    if k == '2' then
        for i = 1, 4 do
            clients[i] = entity.newClient { address = '10.0.1.39:22122' }
        end
    end
end

function love.keyreleased(k)
    updateWalkState()
end

function love.draw()
    for i, client in ipairs(clients) do
        love.graphics.push('all')

        local dx = (require('bit')).band(i - 1, 1) * W
        local dy = (require('bit')).band(i - 1, 2) / 2 * H

        love.graphics.translate(dx, dy)
        love.graphics.setScissor(dx, dy, W, H)
        love.graphics.print('client ' .. client.serverPeer:state(), 20, 20)

        local drawOrder = {}
        for id, ent in pairs(client.all) do
            if ent.draw then
                table.insert(drawOrder, ent)
            end
        end
        table.sort(drawOrder, function(e1, e2)
            return e1.depth < e2.depth
        end)
        for _, ent in ipairs(drawOrder) do
            ent:draw()
        end

        love.graphics.pop()
    end
end
