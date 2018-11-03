local sync = require 'sync'

-- Moonshine is a post-processing effects library, see https://github.com/nikki93/moonshine
local moonshine = require 'https://raw.githubusercontent.com/nikki93/moonshine/9e04869e3ceaa76c42a69c52a954ea7f6af0469c/init.lua'



-- Constants

local SERVER_ADDRESS = '207.254.45.246'

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

local availableTriangleColors = {
    { 0.965, 0.961, 0.682 },
    { 0.961, 0.969, 0.286 },
    { 0.996, 0.373, 0.333 },
    { 0.18, 0.525, 0.671 },
}

function Triangle:didSpawn()
    self.r, self.g, self.b = unpack(table.remove(availableTriangleColors) or
            { 0.2 + 0.8 * math.random(), 0.2 + 0.8 * math.random(), 0.2 + 0.8 * math.random() })
    self.x, self.y = math.random(10, W - 10), math.random(10, H - 10)
    self.vx, self.vy = 0, 0
    self.targetX, self.targetY = math.random(0, W), math.random(0, H) -- Where are we looking?
    self.shootCountdown = 0 -- Seconds till we can shoot again
    self.wantToShoot = false
    self.health = 100
    self.score = 0
end

function Triangle:willDespawn()
    table.insert(availableTriangleColors, { self.r, self.g, self.b })
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
    if self.shootCountdown <= 0 and self.wantToShoot then
        self:shoot()
    end

    -- Iterate through `Bullet`s and check for collision
    local nang = -math.atan2(self.targetY - self.y, self.targetX - self.x)
    local sin, cos = math.sin(nang), math.cos(nang)
    for _, ent in pairs(self.__mgr.all) do
        if ent.__typeName == 'Bullet' and ent.ownerId ~= self.__id then
            local dx, dy = ent.x - self.x, ent.y - self.y
            local hit = false
            if dx * dx + dy * dy < 3600 then -- Ignore if far
                for i = -1, 1, 0.2 do -- Check a few points to prevent 'tunneling'
                    local bx, by = ent.x + 18 * i * ent.dirX, ent.y + 18 * i * ent.dirY
                    local dx, dy = bx - self.x, by - self.y
                    local rdx, rdy = dx * cos - dy * sin, dx * sin + dy * cos
                    if rdx > -20 then
                        rdx = rdx + 20
                        rdy = math.abs(rdy)
                        if rdx / 50 + rdy / 20 < 1 then
                            hit = true
                            break
                        end
                    end
                end
            end
            if hit then -- We got shot!
                self.__mgr:despawn(ent)
                self.health = self.health - 5
                if self.health <= 0 then -- We died! 'Respawn' and increment shooter's score
                    self.health = 100
                    self.x, self.y = math.random(10, W - 10), math.random(10, H - 10)
                    local shooter = self.__mgr.all[ent.ownerId]
                    if shooter then
                        shooter.score = shooter.score + 1
                        self.__mgr:sync(shooter)
                    end
                end
                self.__mgr:sync(self)
            end
        end
    end
end

function Triangle:draw(isOwn)
    love.graphics.stacked('all', function()
        love.graphics.translate(self.x, self.y)

        -- Draw triangle, with thicker white outline if it's our own
        love.graphics.stacked('all', function()
            love.graphics.setColor(self.r, self.g, self.b)
            love.graphics.rotate(math.atan2(self.targetY - self.y, self.targetX - self.x))
            love.graphics.polygon('fill', -20, 20, 30, 0, -20, -20)
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.setLineWidth(isOwn and 3 or 1)
            love.graphics.polygon('line', -20, 20, 30, 0, -20, -20)
        end)

        -- Draw health bar
        love.graphics.stacked('all', function()
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.rectangle('fill', -20, -35, 40, 4)
            love.graphics.setColor(0.933, 0.961, 0.859, 0.5)
            love.graphics.rectangle('fill', -20, -35, self.health / 100 * 40, 4)
        end)
    end)
end

function Triangle:setTarget(x, y)
    self.targetX, self.targetY = x, y
    self.__mgr:sync(self)
end

function Triangle:setWantToShoot(wantToShoot)
    self.wantToShoot = wantToShoot
end

function Triangle:shoot()
    if self.shootCountdown <= 0 then
        local dirX, dirY = self.targetX - self.x, self.targetY - self.y
        if dirX == 0 and dirY == 0 then dirX = 1 end -- Prevent division by zero
        local dirLen = math.sqrt(dirX * dirX + dirY * dirY)
        dirX, dirY = dirX / dirLen, dirY / dirLen
        self.__mgr:spawn('Bullet', self.__id, self.x + 30 * dirX, self.y + 30 * dirY, dirX, dirY)
        self.shootCountdown = 0.2
    end
end

function Triangle:setWantToWalk(up, down, left, right)
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

function Bullet:didSpawn(ownerId, x, y, dirX, dirY)
    self.ownerId = ownerId
    self.x, self.y, self.dirX, self.dirY = x, y, dirX, dirY
end

function Bullet:update(dt)
    self.x, self.y = self.x + 800 * self.dirX * dt, self.y + 800 * self.dirY * dt
    if self.x < 0 or self.x > W or self.y < 0 or self.y > H then
        self.__mgr:despawn(self)
    else
        self.__mgr:sync(self)
    end
end

function Bullet:draw()
    love.graphics.stacked('all', function()
        love.graphics.setColor(1, 0.6, 0.7)
        love.graphics.translate(self.x, self.y)
        love.graphics.rotate(math.atan2(self.dirY, self.dirX))
        love.graphics.ellipse('fill', 0, 0, 24, 1)
    end)
end



-- Controller -- one of these is spawned automatically by the system per client that connects and
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

function Controller:setWantToShoot(wantToShoot)
    if self.triangle then
        self.triangle:setWantToShoot(wantToShoot)
    end
end

function Controller:setWantToWalk(up, down, left, right)
    if self.triangle then
        self.triangle:setWantToWalk(up, down, left, right)
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

local function mouseEvent(button) -- Common mouse event handler
    if client and client.controller then
        if button == 1 then
            client.controller:setWantToShoot(love.mouse.isDown(1) or love.keyboard.isDown('space'))
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
            client.controller:setWantToWalk(
                love.keyboard.isDown('w'),
                love.keyboard.isDown('s'),
                love.keyboard.isDown('a'),
                love.keyboard.isDown('d'))
        end
        if k == 'space' then
            client.controller:setWantToShoot(love.mouse.isDown(1) or love.keyboard.isDown('space'))
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

local effect = moonshine(moonshine.effects.glow).chain(moonshine.effects.vignette)
effect.glow.strength = 2

function love.draw()
    effect(function()
        love.graphics.stacked('all', function()
            local ox, oy = 0.5 * (love.graphics.getWidth() - W), 0.5 * (love.graphics.getHeight() - H)
            love.graphics.setScissor(ox, oy, W, H)
            love.graphics.translate(ox, oy)

            love.graphics.clear(0.2, 0.216, 0.271)

            if client and client.controller then
                -- Draw triangles
                for _, ent in pairs(client.all) do
                    if ent.__typeName == 'Triangle' then
                        ent:draw(ent == client.controller.triangle) -- Tell if it's our triangle
                    end
                end

                -- Draw bullets
                for _, ent in pairs(client.all) do
                    if ent.__typeName == 'Bullet' then
                        ent:draw()
                    end
                end

                -- Draw scores in descending order
                love.graphics.stacked('all', function()
                    local scoreOrder = {}
                    for _, ent in pairs(client.all) do
                        if ent.__typeName == 'Triangle' then
                            table.insert(scoreOrder, ent)
                        end
                    end
                    table.sort(scoreOrder, function(e1, e2)
                        if e1.score == e2.score then
                            return e1.__id < e2.__id
                        end
                        return e1.score > e2.score
                    end)

                    love.graphics.setColor(1, 1, 1)
                    local scoreY = 20
                    for _, ent in ipairs(scoreOrder) do
                        love.graphics.stacked('all', function()
                            love.graphics.setColor(ent.r, ent.g, ent.b)
                            love.graphics.rectangle('fill', 20, scoreY, 12, 12)
                        end)
                        love.graphics.print(ent.score, 42, scoreY)
                        scoreY = scoreY + 16
                    end
                end)

                -- Draw fps and latency
                love.graphics.print('fps:  ' .. love.timer.getFPS(), 20, H - 52)
                love.graphics.print('ping: ' .. client.serverPeer:round_trip_time(), 20, H - 36)
            else -- Show connection instructions if no client
                love.graphics.setColor(1, 1, 1)
                if server then
                    love.graphics.print('server running', 20, 20)
                else
                    love.graphics.print('press 1 to start a server', 20, 20)
                end
                love.graphics.print([[

press 2 to connect to server

move with W, A, S, D
aim with mouse
shoot with left mouse button or SPACE]], 20, 20)
            end
        end)
    end)
end

