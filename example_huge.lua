local sync = require 'sync'



-- 'Globals'

local SERVER_ADDRESS = '10.0.1.39'

--local WORLD_SIZE_X, WORLD_SIZE_Y = 1000, 1000
--local WORLD_NUM_STUFFS = 10000
local WORLD_SIZE_X, WORLD_SIZE_Y = 50, 50
local WORLD_NUM_STUFFS = 100
local WORLD_SCALE = 1 -- Update later based on window size
local DISPLAY_WORLD_UNITS_WIDE = 20 -- How many world units wide should we able to see?


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



-- World

local World = sync.registerType('World')

function World:didSpawn()
    for i = 1, WORLD_NUM_STUFFS do
        self.__mgr:spawn(
            'Stuff',
            WORLD_SIZE_X * (0.5 - math.random()),
            WORLD_SIZE_Y * (0.5 - math.random()))
    end
    self.numStuffs = WORLD_NUM_STUFFS
end

function World:didEnter()
    World.instance = self
end



-- Stuff

local Stuff = sync.registerType('Stuff')

Stuff.drawOrder = {}

function Stuff:didSpawn(x, y)
    self.x, self.y = x, y
    self.angle = 2 * math.pi * math.random()
    self.rotSpeed = 0.1 * 2 * math.pi * math.random()
    self.width, self.height = 1 + 10 * math.random(), 1 + 10 * math.random()
    self.r, self.g, self.b = 0.1 + 0.7 * math.random(), 0.2 * math.random(), 0.2 + 0.5 * math.random()
    self.depth = math.random(2 ^ 30)
end

function Stuff:didEnter()
    table.insert(Stuff.drawOrder, self)
    self.__local.drawOrderIndex = #Stuff.drawOrder
end

function Stuff:willLeave()
    table.remove(Stuff.drawOrder, self.__local.drawOrderIndex)
end

function Stuff:update(dt)
    self.angle = self.angle + self.rotSpeed * dt
    self.__mgr:sync(self)
end

function Stuff:draw()
    love.graphics.stacked('all', function()
        love.graphics.translate(self.x, self.y)
        love.graphics.rotate(self.angle)
        love.graphics.setColor(self.r, self.g, self.b)
        love.graphics.rectangle('fill',
            -0.5 * self.width, -0.5 * self.height,
            self.width, self.height)
    end)
end

function Stuff.drawAll()
    table.sort(Stuff.drawOrder, function(s, t) return s.depth < t.depth end)
    for index, ent in ipairs(Stuff.drawOrder) do
        ent.__local.drawOrderIndex = index
    end
    for _, ent in ipairs(Stuff.drawOrder) do
        ent:draw()
    end
end



-- Player

local Player = sync.registerType('Player')

function Player:didSpawn()
    self.x, self.y = 0, 0
end

function Player:update(dt)
    self.x = self.x + dt
    self.__mgr:sync(self)
end



-- Controller

local Controller = sync.registerType('Controller')

function Controller:didSpawn()
    self.playerId = self.__mgr:spawn('Player')
end

function Controller:willDespawn()
    self.__mgr:despawn(self.playerId)
end



-- Server / client instances and top-level Love callbacks

local server, client


function love.update(dt)
    local ww = love.graphics.getWidth()
    WORLD_SCALE = ww / DISPLAY_WORLD_UNITS_WIDE

    if server then
        server:process()

        for _, ent in pairs(server.all) do
            if ent.update then
                ent:update(dt)
            end
        end
    end
    if client then
        client:process()
    end
end


function love.keypressed(key)
    if key == '0' then
        server = sync.newServer {
            address = '*:22122',
            controllerTypeName = 'Controller',
        }
        server:spawn('World')
    end
    if key == 'return' then
        client = sync.newClient { address = SERVER_ADDRESS .. ':22122' }
    end
end


function love.draw()
    if client and client.controller then
        love.graphics.stacked('all', function()
            local ww, wh = love.graphics.getDimensions()
            love.graphics.translate(ww / 2, wh / 2)

            love.graphics.scale(WORLD_SCALE)

            local player = client:byId(client.controller.playerId)
            love.graphics.translate(-player.x, -player.y)

            Stuff.drawAll()
        end)
    end

    if World.instance then
        love.graphics.print('total: ' .. World.instance.numStuffs, 20, 20)
        love.graphics.print('\nrelevant: ' .. #Stuff.drawOrder, 20, 20)
    end
end
