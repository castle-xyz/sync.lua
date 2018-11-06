# sync.lua

*sync.lua* aims to make Lua-based multiplayer games easier to write. It's meant to run in a [LÖVE](https://love2d.org/) context but could work anywhere [lua-enet](http://leafo.net/lua-enet/) and [LuaJIT's FFI library](http://luajit.org/ext_ffi.html) are available (both built-into LÖVE by default).

To use it in your game, just copy 'sync.lua' and 'bitser.lua' into a place you can `require` from in the game, and load `sync` as `local sync = require 'sync'`.

Read the [basic tutorial](./docs/tutorial_basic.md) to get started. See '[example_triangle_warz.lua](./example_triangle_warz.lua)' for the code of a more involved game that uses this library. More tutorial(s) and documentation coming soon...