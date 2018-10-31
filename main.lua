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

function Player:update(dt)
    self.x = self.x + 20 * dt
end




local server, client


function love.update(dt)
    if server then
        server:process()

        for ent in pairs(server.owned) do
            ent:update(dt)
            server:sync(ent)
        end
    end
    if client then
        client:process()
    end
end

function love.keypressed(k)
    if k == 's' then
        server = entity.newServer { address = '*:22122' }
    end
    if k == 'c' then
        client = entity.newClient { address = '192.168.1.80:22122' }
    end

    if k == 'p' then
        client:spawn('Player', {
            x = math.random() * love.graphics.getWidth(),
            y = math.random() * love.graphics.getHeight(),
        })
    end
end

function love.draw()
    if client then
        love.graphics.print('client ' .. client.serverPeer:state(), 20, 20)

        for id, ent in pairs(client.allById) do
            ent:draw()
        end
    else
        love.graphics.print('no client', 20, 20)
    end
end
