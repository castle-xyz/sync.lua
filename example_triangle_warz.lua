local sync = require 'sync'



-- Constants

local SERVER_ADDRESS = '10.0.1.39'

local W, H = 800, 600



-- Utilities

-- `love.graphics.stacked([arg], func)` calls `func` between `love.graphics.push([arg])` and
-- `love.graphics.pop()` while being resilient to errors
function love.graphics.stacked(argOrFunc, funcOrNil)
    love.graphics.push(funcOrNil and argOrFunc)
    local succeeded, err = pcall(funcOrNil or argOrFunc)
    love.graphics.pop()
    if not succeeded then
        error(err, 0)
    end
end



-- Triangle

local Triangle = sync.registerType('Triangle')

function Triangle:didSpawn()
    self.x, self.y = math.random(10, W - 10), math.random(10, H - 10)
    self.vx, self.vy = 0, 0
    self.targetX, self.targetY = math.random(0, W), math.random(0, H)
    self.shootCountdown = 0 -- Seconds till we can shoot again
    self.isShooting = false
end

function Triangle:update(dt)
    if self.vx ~= 0 or self.vy ~= 0 then
        self.x = self.x + self.vx * dt
        self.y = self.y + self.vy * dt
        self.x = math.max(0, math.min(self.x, W))
        self.y = math.max(0, math.min(self.y, H))
        self.__mgr:sync(self)
    end

    if self.shootCountdown > 0 then
        self.shootCountdown = self.shootCountdown - dt
    end
    if self.shootCountdown <= 0 and self.isShooting then
        self:shoot()
    end
end

function Triangle:draw(isOwn)
    love.graphics.stacked('all', function()
        if isOwn then
            love.graphics.setColor(0.78, 0.937, 0.812)
        else
            love.graphics.setColor(0.996, 0.373, 0.333)
        end
        love.graphics.translate(self.x, self.y)
        love.graphics.rotate(math.atan2(self.targetY - self.y, self.targetX - self.x))
        love.graphics.polygon('fill', -20, 20, 30, 0, -20, -20)
    end)
end

function Triangle:setTarget(x, y)
    self.targetX, self.targetY = x, y
    self.__mgr:sync(self)
end

function Triangle:setShooting(isShooting)
    self.isShooting = isShooting
end

function Triangle:shoot()
    if self.shootCountdown <= 0 then
        local dirX, dirY = self.targetX - self.x, self.targetY - self.y
        if dirX == 0 and dirY == 0 then dirX = 1 end -- Prevent division by zero
        local dirLen = math.sqrt(dirX * dirX + dirY * dirY)
        dirX, dirY = dirX / dirLen, dirY / dirLen
        self.__mgr:spawn('Bullet', self.x + 30 * dirX, self.y + 30 * dirY, dirX, dirY)
        self.shootCountdown = 0.2
    end
end

function Triangle:setWalkState(up, down, left, right)
    self.vx, self.vy = 0, 0
    if left then self.vx = self.vx - 220 end
    if right then self.vx = self.vx + 220 end
    if up then self.vy = self.vy - 220 end
    if down then self.vy = self.vy + 220 end
    local v = math.sqrt(self.vx * self.vx + self.vy * self.vy)
    if v > 0 then -- Limit speed
        self.vx, self.vy = 220 * self.vx / v, 220 * self.vy / v
    end
    self.__mgr:sync(self)
end



-- Bullet

local Bullet = sync.registerType('Bullet')

function Bullet:didSpawn(x, y, dirX, dirY)
    self.x, self.y, self.vx, self.vy = x, y, 800 * dirX, 800 * dirY
end

function Bullet:update(dt)
    self.x, self.y = self.x + self.vx * dt, self.y + self.vy * dt
    if self.x < 0 or self.x > W or self.y < 0 or self.y > H then
        self.__mgr:despawn(self)
    else
        self.__mgr:sync(self)
    end
end

function Bullet:draw()
    love.graphics.stacked('all', function()
        love.graphics.setColor(0.902, 0.204, 0.384)
        love.graphics.translate(self.x, self.y)
        love.graphics.rotate(math.atan2(self.vy, self.vx))
        love.graphics.ellipse('fill', 0, 0, 18, 2)
    end)
end



-- Controller -- one of these is spawned automatically by the system per client that connects, and
-- is despawned on disconnect

local Controller = sync.registerType('Controller')

function Controller:didSpawn()
    self.triangle = self.__mgr:spawn('Triangle')
end

function Controller:willDespawn()
    if self.triangle then
        self.__mgr:despawn(self.triangle)
        self.triangle = nil
    end
end

function Controller:setTarget(x, y)
    if self.triangle then
        self.triangle:setTarget(x, y)
    end
end

function Controller:setShooting(isShooting)
    if self.triangle then
        self.triangle:setShooting(isShooting)
    end
end

function Controller:setWalkState(up, down, left, right)
    if self.triangle then
        self.triangle:setWalkState(up, down, left, right)
    end
end



-- Server / client instances and top-level input

local server, client

function love.update(dt)
    -- Do game logic on the server
    if server then
        for _, ent in pairs(server.all) do
            if ent.update then
                ent:update(dt)
            end
        end
    end

    -- Both server and client need `:process()` called on them every frame
    if server then
        server:process()
    end
    if client then
        client:process()
    end
end

function love.mousemoved(x, y)
    if client and client.controller then
        local ox, oy = 0.5 * (love.graphics.getWidth() - W), 0.5 * (love.graphics.getHeight() - H)
        client.controller:setTarget(x - ox, y - oy)
    end
end

local function mouseEvent(button)
    if client and client.controller then
        if button == 1 then
            client.controller:setShooting(love.mouse.isDown(1) or love.keyboard.isDown('space'))
        end
    end
end

function love.mousepressed(x, y, button)
    mouseEvent(button)
end

function love.mousereleased(x, y, button)
    mouseEvent(button)
end

local function keyEvent(k) -- Common key event handler
    if client and client.controller then
        if k == 'w' or k == 'a' or k == 's' or k == 'd' then
            client.controller:setWalkState(
                love.keyboard.isDown('w'),
                love.keyboard.isDown('s'),
                love.keyboard.isDown('a'),
                love.keyboard.isDown('d'))
        end
        if k == 'space' then
            client.controller:setShooting(love.mouse.isDown(1) or love.keyboard.isDown('space'))
        end
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

    keyEvent(k)
end

function love.keyreleased(k)
    keyEvent(k)
end



-- Top-level drawing

function love.draw()
    love.graphics.stacked('all', function()
        local ox, oy = 0.5 * (love.graphics.getWidth() - W), 0.5 * (love.graphics.getHeight() - H)
        love.graphics.setScissor(ox, oy, W, H)
        love.graphics.translate(ox, oy)

        love.graphics.clear(0.2, 0.216, 0.271)

        if client and client.controller then
            -- Draw our own triangle
            local ownTriangle = client.controller.triangle
            if ownTriangle then
                ownTriangle:draw(true)
            end

            -- Draw everyone else's triangles
            for _, ent in pairs(client.all) do
                if ent.__typeName == 'Triangle' then
                    if ent ~= ownTriangle then
                        ent:draw(false)
                    end
                end
            end

            -- Draw bullets
            for _, ent in pairs(client.all) do
                if ent.__typeName == 'Bullet' then
                    ent:draw()
                end
            end
        else
            love.graphics.setColor(1, 1, 1)
            if server then
                love.graphics.print('server running', 20, 20)
            else
                love.graphics.print('press 1 to start a server', 20, 20)
            end
            love.graphics.print('\npress 2 to connect to server', 20, 20)
        end
    end)
end

