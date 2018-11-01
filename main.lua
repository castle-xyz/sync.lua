local entity = require 'entity'


local W, H = 0.5 * love.graphics.getWidth(), 0.5 * love.graphics.getHeight()

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


-- Walls surrounding the simulation. Also holds the Love physics `World`.

local Room = entity.registerType('Room')

Room.depth = 300

function Room:didConstruct()
    love.physics.setMeter(64)
    self.__local.world = love.physics.newWorld(0, 9.81 * 64, true)

    self.__local.groundBody = love.physics.newBody(self.__local.world, 0.5 * W, H - 10)
    self.__local.groundShape = love.physics.newRectangleShape(W, 20)
    self.__local.groundFixture = love.physics.newFixture(
        self.__local.groundBody, self.__local.groundShape)
    self.__local.lwallBody = love.physics.newBody(self.__local.world, 10, 0.5 * H)
    self.__local.lwallShape = love.physics.newRectangleShape(20, H)
    self.__local.lwallFixture = love.physics.newFixture(
        self.__local.lwallBody, self.__local.lwallShape)
    self.__local.rwallBody = love.physics.newBody(self.__local.world, W - 10, 0.5 * H)
    self.__local.rwallShape = love.physics.newRectangleShape(20, H)
    self.__local.rwallFixture = love.physics.newFixture(
        self.__local.rwallBody, self.__local.rwallShape)
end

function Room:update(dt)
    self.__local.world:update(dt)
end

function Room:draw()
    love.graphics.stacked('all', function()
        love.graphics.setColor(0.8, 0.5, 0.1)
        love.graphics.rectangle('fill', 0, H - 20, W, 20)
        love.graphics.rectangle('fill', 0, 0, 20, H)
        love.graphics.rectangle('fill', W - 20, 0, 20, H)
    end)
end


-- Sync'd dynamic physics object. Forces can be applied by clients.

local Player = entity.registerType('Player')

Player.depth = 100

function Player:didConstruct()
    self.radius = 15
    self:createBody()
end

function Player:didSpawn(props)
    self.__local.body:setPosition(W * math.random(), H * math.random())
    self:fromBody()

    self.r, self.g, self.b = math.random(), math.random(), math.random()

    self.walkState = { up = false, down = false, left = false, right = false }
end

function Player:didSync()
    self:createBody()
    self:toBody()
end

function Player:update(dt)
    if self.walkState.up then self.__local.body:applyForce(0, -900) end
    if self.walkState.down then self.__local.body:applyForce(0, 200) end
    if self.walkState.left then self.__local.body:applyForce(-200, 0) end
    if self.walkState.right then self.__local.body:applyForce(200, 0) end

    if self.__local.body:isAwake() then
        self:fromBody()
        self.__mgr:sync(self)
    end
end

function Player:draw()
    love.graphics.stacked('all', function()
        love.graphics.setColor(self.r, self.g, self.b)
        love.graphics.ellipse('fill', self.x, self.y, self.radius, self.radius)
    end)
end

function Player:createBody()
    if not self.__local.body then
        local room
        for _, ent in pairs(self.__mgr.all) do
            if ent.__typeName == 'Room' then
                room = ent
            end
        end
        if room then
            self.__local.body = love.physics.newBody(room.__local.world, 0, 0, 'dynamic')
            self.__local.shape = love.physics.newCircleShape(self.radius)
            self.__local.fixture = love.physics.newFixture(self.__local.body, self.__local.shape, 3)
        end
    end
end

function Player:fromBody()
    self.x, self.y = self.__local.body:getPosition()
    self.vx, self.vy = self.__local.body:getLinearVelocity()
    self.ax, self.ay = self.__local.body:getAngularVelocity()
end

function Player:toBody()
    self.__local.body:setPosition(self.x, self.y)
    self.__local.body:setLinearVelocity(self.vx, self.vy)
    self.__local.body:setAngularVelocity(self.ax, self.ay)
end


-- Controller -- automatically spawned by the system once per client, just create `Player`s

local Controller = entity.registerType('Controller')

function Controller:didSpawn(props)
    self.player = self.__mgr:spawn('Player')
    for i = 1, 5 do
        self.__mgr:spawn('Player')
    end
end

function Controller:setWalkState(walkState)
    if self.player then
        self.player.walkState = walkState
    end
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
        server:spawn('Room')
    end
    if k == '2' then
        for i = 1, 2 do
            table.insert(clients, entity.newClient { address = '10.0.1.39:22122' })
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
