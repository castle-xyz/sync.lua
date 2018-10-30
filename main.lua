local Entity = require 'Entity'


function love.keypressed()
    if key == 's' then
        Entity:initServer()
    end
    if key == 'c' then
        Entity:initClient('192.168.1.160')
    end
end
