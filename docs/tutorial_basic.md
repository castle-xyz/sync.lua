# Basic tutorial

In this tutorial we will build up to '[example_basic.lua](../example_basic.lua)'. In this example, each player that logs in is given a single randomly-colored circle that they can move around on screen. You can see other players' circles. In addition, pressing the spacebar will play a laser noise! Each player plays the noise at a different pitch.

## Getting started

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
