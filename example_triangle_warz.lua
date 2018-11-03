local sync = require 'sync'

-- Constants

local SERVER_ADDRESS = '10.0.1.39'

local W, H = 800, 600



-- Utils

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



-- Triangle

local Triangle = sync.registerType('Triangle')

function Triangle:didSpawn()
    self.x, self.y = math.random(10, W - 10), math.random(10, H - 10)
    self.rot = 0
    self.vx, self.vy = 0, 0
end

function Triangle:update(dt)
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    self.x = math.max(0, math.min(self.x, W))
    self.y = math.max(0, math.min(self.y, H))
    self.__mgr:sync(self)
end

function Triangle:draw(isOwn)
    love.graphics.stacked('all', function()
        if isOwn then
            love.graphics.setColor(0.78, 0.937, 0.812)
        else
            love.graphics.setColor(0.996, 0.373, 0.333)
        end
        love.graphics.translate(self.x, self.y)
        love.graphics.rotate(self.rot)
        love.graphics.polygon('fill',
            -20, 20,
            30, 0,
            -20, -20)
    end)
end

function Triangle:lookAt(x, y)
    self.rot = math.atan2(y - self.y, x - self.x)
    self.__mgr:sync(self)
end

function Triangle:setWalkState(up, down, left, right)
    self.vx, self.vy = 0, 0
    if left then self.vx = self.vx - 220 end
    if right then self.vx = self.vx + 220 end
    if up then self.vy = self.vy - 220 end
    if down then self.vy = self.vy + 220 end
    self.__mgr:sync(self)
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

function Controller:lookAt(x, y)
    if self.triangle then
        self.triangle:lookAt(x, y)
    end
end

function Controller:setWalkState(up, down, left, right)
    if self.triangle then
        self.triangle:setWalkState(up, down, left, right)
    end
end


-- Server / client instances and top-level Love events

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

function love.mousemoved(x, y)
    if client and client.controller then
        local ox, oy = 0.5 * (love.graphics.getWidth() - W), 0.5 * (love.graphics.getHeight() - H)
        client.controller:lookAt(x - ox, y - oy)
    end
end

local function keyEvent(k) -- Common key event handler
    if client and client.controller then
        -- WASD
        if k == 'w' or k == 'a' or k == 's' or k == 'd' then
            client.controller:setWalkState(
                love.keyboard.isDown('w'),
                love.keyboard.isDown('s'),
                love.keyboard.isDown('a'),
                love.keyboard.isDown('d'))
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
