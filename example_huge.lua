local sync = require 'sync'



-- Constants

local SERVER_ADDRESS = '10.0.1.39'



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



-- Server / client instances and top-level input

local server, client

function love.keypressed(key)
    if key == '0' then
        server = sync.newServer {
            address = '*:22122',
            controllerTypeName = 'Controller',
        }
    end
    if key == 'return' then
        client = sync.newClient { address = SERVER_ADDRESS .. ':22122' }
    end
end



-- Top-level update

function love.update()
    if server then
        server:process()
    end
    if client then
        client:process()
    end
end



-- Top-level draw

function love.draw()
    love.graphics.print('hello, world', 20, 20)
end



