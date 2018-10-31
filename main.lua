local entity = require 'entity'




local Player = entity.registerType('Player')

function Player:didSpawn(props)
    print('player spawned at (' .. props.x .. ', ' .. props.y .. ')')
    self.x = props.x
    self.y = props.y
end

function Player:draw()
    love.graphics.ellipse('fill', self.x, self.y, 20, 20)
end


local server = entity.newServer { address = '*:22122' }
local client = entity.newClient { address = '192.168.1.80:22122' }


function love.update(dt)
    server:update(dt)
    client:update(dt)
end

function love.keypressed(k)
    if k == 'p' then
        client:spawn('Player', {
            x = math.random() * love.graphics.getWidth(),
            y = math.random() * love.graphics.getHeight(),
        })
    end
end

function love.draw()
    for id, ent in pairs(client.allById) do
        ent:draw()
    end
end
