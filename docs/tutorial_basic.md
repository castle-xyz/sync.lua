# Basic tutorial

In this tutorial we will build up to '[example_basic.lua](../example_basic.lua)'. In this example, each player that logs in is given a single randomly-colored circle that they can move around on screen. You can see other players' circles. In addition, pressing the spacebar will play a laser noise! Each player plays the noise at a different pitch.

## Setup

In this tutorial we will be using the [LÖVE](https://love2d.org/) framework for drawing graphics and playing sounds. You could use 
LÖVE directly or you could use [Castle](https://www.playcastle.io/) (which the developer of sync.lua also works on) which gives you a viewer for LÖVE games posted on GitHub or available locally and also lets you load libraries directly from GitHub.

Start a new 'main.lua' file for your game.

If you're using plain LÖVE, download 'sync.lua' and 'bitser.lua' from the *sync.lua* repository and place them next to your source files. Then add `local sync = require 'sync'` in your 'main.lua' file to use *sync.lua*. Now load your 'main.lua' as you [normally would in LÖVE](https://love2d.org/wiki/Getting_Started).

If you're using Castle, you can just write `local sync = 'https://raw.githubusercontent.com/expo/sync.lua/master/sync.lua`. Then load 'main.lua' as you [normally would in Castle](https://medium.com/castle-archives/making-games-with-castle-e4d0e9e7a910).

We'll keep this `local sync = require ...` line at the top of the file.

To make sure things are working, add the following:

```lua
function love.draw()
    love.graphics.print('hello, world!', 20, 20)
end
```

Then reload the game. You should now see this (I'm using Castle -- the title bar will be different for you in plain LÖVE):

![](./tutorial_basic_1.png)

Before we write more code, let's go over some background on how *sync.lua* splits work across multiple computers...

## Client / server system

In multiplayer games, multiple computers communicate over the internet or local networks to synchronize game state among themselves and give players the illusion that they are all playing in the same game world. *sync.lua* achieves this by designating one computer as the **server**, with all computers connecting to it called **clients**. The server runs the main instance of the game and sends updates to all clients to let them know what's happened in the game so far. Each client has a local *copy* of the game world that it updates according to these messages and displays to the user. This way all players see the same game world. Note that the clients don't talk to each other, they only talk to the server.

Clients also need a way to influence the game world so that players can actually make things happen in the game. In *sync.lua*, each client gets a **controller** object on which it can call methods -- these methods are then triggered on the server and the server can make changes in the game world accordingly. In this sense, the controller objects are quite like physical game controllers in your hands (the clients) attached to a video game console (the server) that runs the actual game, hence the name.

Now let's write some code to actually create server and client instances of *sync.lua*...

## Creating server and client instances

Normally a game would list servers and let you connect to them or let you start your own server and invite a friend. For this basic example, let's just pick the computer we're coding on as the server for now, and also launch a client instance on the same computer. We'll make it so that the user can press '1' to launch a server, and '2' to connect as a client (again, in a real game you would make a nice menu screen). Put this before our existing `love.draw` code:

```lua
local server, client

function love.keypressed(key)
    if key == '1' then
        server = sync.newServer { address = '*:22122' }
    end
    if key == '2' then
        client = sync.newClient { address = '127.0.0.1:22122' }
    end
end
```

We're using `22122` as the port, and `'127.0.0.1'` basically means "local server", so that the client connects to the server running on the same computer.

We also need to call `:process()` on the client and server instances every frame. This makes them actually send and receive messages and update the game state accordingly. Add a `love.update` to do this (make sure to put it somewhere after the `local server, client` line):

```lua
function love.update(dt)
    if server then
        server:process()
    end
    if client then
        client:process()
    end
end
```

Now reload the game and press '1'. Oops! We get an error:

```
server needs `props.controllerTypeName`
```

This is because we need to specify a controller type to create for each client that joins the server. So let's do that...

## Adding a `Controller`

Before the `local server, client` line, add this:

```lua
local Controller = sync.registerType('Controller')
```

This registers a new type named `'Controller'` with *sync.lua*. You can use any system for defining types, such as [classic](https://github.com/rxi/classic) or [middleclass](https://github.com/kikito/middleclass), but the default *sync.lua* system works well for this example. *sync.lua* needs the notion of types so that it knows how to construct replica instances on clients and notify instances of events. This will make sense as we go on...

Let's update our `sync.newServer` call from before to use this controller type:

```lua
        server = sync.newServer { address = '*:22122', controllerTypeName = 'Controller' }
```

Now reload the game. Press '1', then press '2'. There should be no errors. But the game doesn't show any feedback either. Let's fix that. Let's have our `Controller` `print` something when a client connects or disconnects:

```lua
function Controller:didSpawn()
    print('a client connected')
end

function Controller:willDespawn()
    print('a client disconnected')
end
```

The `server` spawns a `Controller` when a client connects and despawns it on disconnect.

Now if you reload and press '1' then '2' you should have the "a client connected" message be printed!

## (Optional) Connecting a different computer

If you have another computer, we could test that the server is accessible from it. Connect that computer to the same local area network (say by connecting to the same Wi-Fi router). [Get the local IP address](https://www.whatismybrowser.com/detect/what-is-my-local-ip-address) of your first computer, then update the `sync.newClient` line to use this IP address instead. For example, my local IP address is `'192.168.1.80'`, so I have this:

```lua
        client = sync.newClient { address = '192.168.1.80:22122' }
```

Now run your game on both computers (if using LÖVE you could copy the code, in Castle you could just serve the game on the first computer and use the local IP on the second). On the first computer, press '1' to start the server. Then on the second computer, press '2' to connect. On the first computer you should see the message "a client connected" be printed. If you quit the game on the second computer, you'll see the "a client disconnected" message be printed on the first after some time, because the server notices that the client has stopped responding.
