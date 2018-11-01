-- `love.graphics.stacked([arg], foo)` calls `foo` between `love.graphics.push([arg])` and
-- `love.graphics.pop()` while being resilient to errors
function love.graphics.stacked(...)
    local arg, func
    if select('#', ...) == 1 then
        func = select(1, ...)
    else
        arg = select(1, ...)
        func = select(2, ...)
    end
    love.graphics.push(arg)

    local succeeded, err = pcall(func)

    love.graphics.pop()

    if not succeeded then
        error(err, 0)
    end
end


local entity = require 'entity'

local W, H = 0.5 * love.graphics.getWidth(), 0.5 * love.graphics.getHeight()



local Gun = entity.registerType('Gun')

Gun.depth = 200

function Gun:didSpawn(props)
    self.x, self.y = props.x, props.y

    self.r, self.g, self.b = math.random(), math.random(), math.random()
end

function Gun:draw()
    love.graphics.stacked('all', function()
        love.graphics.setColor(self.r, self.g, self.b)
        love.graphics.rectangle('fill', self.x, self.y, 15, 15)
    end)
end


local Player = entity.registerType('Player')

Player.depth = 100

function Player:didSpawn(props)
    self.x, self.y = W * math.random(), H * math.random()
    self.walkState = { up = false, down = false, left = false, right = false }

    self.r, self.g, self.b = math.random(), math.random(), math.random()

    self.guns = {}
    for i = 1, 4 do
        table.insert(self.guns, self.__mgr:spawn('Gun', {
            x = self.x + 15 * (1 - 2 * math.random()),
            y = self.y + 15 * (1 - 2 * math.random()),
        }))
    end
end

function Player:draw()
    love.graphics.stacked('all', function()
        love.graphics.setColor(self.r, self.g, self.b)
        love.graphics.ellipse('fill', self.x, self.y, 40, 40)
    end)
end

function Player:update(dt)
    local vx, vy = 0, 0

    if self.walkState.up then vy = vy - 120 end
    if self.walkState.down then vy = vy + 120 end
    if self.walkState.left then vx = vx - 120 end
    if self.walkState.right then vx = vx + 120 end

    local newX, newY = self.x + vx * dt, self.y + vy * dt

    local canMove = true
    for _, ent in pairs(self.__mgr.all) do
        if ent ~= self and ent.__typeName == 'Player' then
            local dx = newX - ent.x
            local dy = newY - ent.y
            if dx * dx + dy * dy < 80 * 80 then
                canMove = false
            end
        end
    end
    if canMove then
        self.x, self.y = newX, newY
        self.__mgr:sync(self)

        for _, gun in ipairs(self.guns) do
            gun.x, gun.y = gun.x + vx * dt, gun.y + vy * dt
            self.__mgr:sync(gun)
        end
    end
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
        end

        server:process()
    end

    for _, client in pairs(clients) do
        client:process()

        for id, ent in pairs(client.all) do
            if ent.update then
                ent:update(dt)
            end
        end
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
        love.graphics.stacked('all', function()
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
        end)
    end
end
