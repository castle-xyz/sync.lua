# *sync.lua* reference manual

**NOTE**: This is a work in progress, more to come soon...

## Contents

  * [Module](#module)
  * [Initializing clients and servers](#initializing-clients-and-servers)
     * [sync.newServer(options)](#syncnewserveroptions)
     * [sync.newClient(options)](#syncnewclientoptions)
  * [Disconnecting](#disconnecting)
     * [Client:disconnect()](#clientdisconnect)
  * [Spawning and despawning entities](#spawning-and-despawning-entities)
     * [Server:spawn(typeName, ...)](#serverspawntypename-)
     * [Server:despawn(entOrId)](#serverdespawnentorid)
  * [Querying entities](#querying-entities)
     * [Common.all](#commonall)
     * [Common:byId(id)](#commonbyidid)
     * [Common:byType(typeName)](#commonbytypetypename)
  * [Synchronizing entities](#synchronizing-entities)
     * [Common:sync(entOrId)](#commonsyncentorid)
  * [Processing](#processing)
     * [Common:process()](#commonprocess)
  * [Controllers](#controllers)
     * [Client.controller](#clientcontroller)
  * [Time](#time)
     * [Client:serverTime()](#clientservertime)

## Module

*sync.lua* only contains one module, returned by `require`ing the [sync.lua](https://github.com/expo/sync.lua/blob/master/sync.lua) file. Values in this module are referred-to as `sync.<key>` below, such as `sync.newServer` or `sync.newClient`.

## Initializing clients and servers

*sync.lua* synchronizes state using a client / server architecture. The *server* is the authority over all state. *clients* connect to the server and receive state updates from it. Clients usually connect to a sever running on a different computer over the network. A client can also connect to a server on the same computer or in the same process, which is useful for testing or to allow one of the players of a game to host a server.

### `sync.newServer(options)`

Creates a new *sync.lua* server instance.

#### Arguments

- **`options` (table, required)**: A table of options:
  - **`options.address` (string, optional)**: If set, an address form `'<ipaddress>:<port>'`, `'<hostname>:<port>'` or `'*:<port>'` (the `'*'` form uses the default host for this computer). If not set, defaults to `'*:22122'`.
  - **`options.controllerTypeName` (string, required)**: Should be the name of the type used to instantiate controller entities for clients that connect to this server.

#### Returns

Returns the `Server` instance created, which supports methods prefixed with `Server:` or `Common:` below.

### `sync.newClient(options)`

Creates a new *sync.lua* client instance.

#### Arguments

- **`options` (table, required)**: A table of options:
  - **`options.address` (string, required)**: An address of the form `'<ipaddress>:<port>'` or `'<hostname>:<port>'` to connect to.

#### Returns

Returns the `Client` instance created, which supports methods prefixed with `Client:` or `Common:` below.

## Disconnecting

### `Client:disconnect()`

Disconnect from the server this client is connected to.

## Spawning and despawning entities

### `Server:spawn(typeName, ...)`

Create an entity of the given type. Automatically synchronizes the entity to all connected clients for which the entity is relevant (the actual synchronization is sent on the next `:process` call).

#### Arguments

- **`typeName` (string, required)**: The name of the type of entity to spawn.
- **`...`**: Extra parameters to pass to the type's constructor and entity's `:didConstruct` and `:didSpawn` events.

#### Returns

- **`id` (number)**: The id of the entity created.
- **`ent` (entity)**: The entity itself.

### `Server:despawn(entOrId)`

Destroy an entity. Automatically removes the entity from all connected clients for which the entity is relevant (the actual synchronization is sent on the next `:process` call).

#### Arguments

- **`entOrId` (entity or id, required)**: The entity or the id of the entity to despawn.

#### Returns

Nothing.

## Querying entities

### `Common.all`

A table of all entities, where the keys are the ids of the entities and the values are the corresponding entities. This table is used internally by *sync.lua*, so *make sure not to modify* this table.

### `Common:byId(id)`

Find an entity by id.

#### Arguments

- **`id` (number or nil)**: The id of the entity to look for.

#### Returns

Returns the entity that has the id given, or `nil` if the id is `nil` or if there is no entity with this id.

### `Common:byType(typeName)`

Find entities by type.

#### Arguments

- **`typeName` (string, required)**: The name of the type to search by.

#### Returns

Returns a table of all the entities of the named type, where the keys are the ids of the entities and the values are the corresponding entities. Returns a direct reference to a table used internally by *sync.lua*, so *make sure not to modify* this table.

## Synchronizing entities

### `Common:sync(entOrId)`

Mark an entity as needing synchronization.

On server instances the state of the entity is sent to all clients for which the entity is relevant (the actual synchronization is sent on the next `:process` call). On client instances this doesn't send any synchronizations, but the method is still provided so that you can call `:sync` in shared code without causing an error.

Typically this needs to be called on an entity when any of its members change that clients need to be aware of, or if its return value for `:isRelevant` may have changed for any controller.

#### Arguments

- **`entOrId` (entity or id, required)**: The entity or the id of the entity to mark as needing synchronization.

#### Returns

Nothing.

## Processing

### `Common:process()`

Send and receive synchronization data over the network. This method needs to be called on server and client instances periodically to keep them up to date. Typically you just call this method in `love.update`.

If you notice that calling this method every frame causes too much overhead and reduces your game's frame rate, you could try calling it every other frame or even less often than that. The trade-off is that the less often you call this method, the higher the latency in clients receiving network updates from the server.

#### Arguments

None.

#### Returns

Nothing.

## Controllers

### `Client.controller`

The controller for a client. This is a local replica synchronized from the server, so all members are copied from the server, just like other replicated entities. The added specialty of the controller entity is that method calls on the client entity are sent to the server to be executed remotely. This allows clients to influence server state, while allowing the server to control what each client can influence.

## Time

### `Client:serverTime()`

Get expected value returned by `love.timer.getTime()` as called on the server at this moment. *sync.lua* computes this value by synchronizing the client-server time difference periodically while accounting for network delay.

## Types and entity construction

*sync.lua* lets you register named types with the system, which provide blueprints for how to construct entities and how to call methods on them. *sync.lua* concerns itself with entity construction because it needs to automatically construct entity replicas on clients. You can use any class system for Lua, but the default behavior built into *sync.lua* should also work for most purposes.

Note the **difference between 'spawn' and 'construct'**: *spawning* an entity only happens on the server and only once for that entity id; while *constructing* happens once on the server for the main instance but also happens on clients when they construct local replicas of that entity. 

### `sync.registerType(typeName, ty)`

Register a type with the system, or create and return a new registered type.

#### Arguments

- **`typeName` (string, required)**: The name to register this type under. This is what you will use in `Server:spawn`.
- **`ty` (table, optional)**: The type itself. Pass this to register an existing table. Defaults to `{}` (a new empty table).

#### Returns

Returns `ty`, the type registered. This is useful so you can do `local Type = sync.register('Type')` to use the default value `{}` for `ty` but still save the value.

### Entity construction

When you call `Server:spawn(typeName, ...)` or when clients need to replicate a new entity from the server, *sync.lua* constructs an entity instance from a type. To do this, it first looks up the table `ty` previously registered under that `typeName` using `sync.registerType(typeName, ty)`. Then, it does one of two things based on whether `ty.construct` is defined:

- **`ty.construct` is not defined (default construction)**: *sync.lua* sets `ty.__index = ty` and uses `setmetatable({}, ty)` as the new entity. In effect, the entity 'inherits' from `ty`. This is how the [basic example defines methods for `Player`](https://github.com/expo/sync.lua/blob/48c2ea1561f3819ba0598b62c43639345caa2590/example_basic.lua#L7-L39), for example.
- **`ty.construct` is defined (custom construction)**: `ty:construct()` is called and the returned value (which should be a table) is used as the entity. This lets you define custom construction behaviors (eg. to tie *sync.lua* with your own class system or entity-component system).

## Entity events

*sync.lua* calls methods on entities to notify them of events such as their recent spawning, imminent despawning or sync'ing. Below is a listing of the methods *sync.lua* will call on an entity. If a method is not defined, *sync.lua* simply skips calling it.

### `Entity:didSpawn(...)`

**Server-only.** Called right after the entity is spawned. `...` are the extra arguments passed in `Server:Spawn(typeName, ...)`. Typically this is where you initialize synchronized data members of the entity and update other server-side data about the entity (eg. adding it to a table that finds entities by their positions).

### `Entity:willDespawn()`

**Server-only.** Called right before the entity is despawned. `...` are the extra arguments passed in `Server:Spawn(typeName, ...)`.

### `Entity:didEnter()`

**Client-only.** Called when an entity becomes relevant to the client. This could be if it was just spawned and is relevant, or if it was previously irrelevant and just became relevant. Typically this is where you update client-side data about the entity (eg. adding it to a local list of entities to draw in depth order). This is called after all data in this `Client:process` call has been synchronized, so you can safely refer to data from other entities.

### `Entity:willLeave()`

**Client-only.** Called when an entity becomes irrelevant to the client. This could be if it was just despawned and while relevant, or if it was previously relevant and just became irrelevant. Typically this is where you update client-side data about the entity (eg. removing it from a local list of entities to draw in depth order). This is called before destroying any entity data in this `Client:process` call, so you can safely refer to data from this or other entities.

### `Entity:willSync(data, dt)`

**Client-only.** Called when an entity is receiving new synchronizaton data from a server. `data` contains all the members of the entity on the server. So, for example, if you set `self.x` and `self.y` on the server, they would be `data.x` and `data.y`. `dt` is the time in seconds that elapsed since this snapshot was recorded on the server. `dt` is provided because the snapshot usually takes time to travel over the network. This way you could predict the correct values to use locally (eg. `self.x = data.x + data.vx * dt` to set X-axis position based on X-axis velocity).

This method is called in the process of synchronizing entities, so it may be that the data of other entities is still old (hasn't been synchronized yet). This may matter if, for example, a `Player` instance has a `self.axeId` to refer to their axe, but the axe hasn't been constructed yet and will be constructed as the synchronization continues in the same `Client:process` call.

### `Entity:didSync()`

**Client-only.** Called after entity data has been synchronized from the server. This is called after all data in this `Client:process` call has been synchronized, so you can safely refer to data from other entities.

### `Entity:didConstruct(...)`

**Client and server.** Called when an instance of this entity has been constructed, whether on the server or the client. On the server this is called before `:didSpawn`. On clients this is called before `:didEnter`.

This method is called in the process of synchronizing entities, so it may be that the data of other entities is still old (hasn't been synchronized yet). This may matter if, for example, a `Player` instance has a `self.axeId` to refer to their axe, but the axe hasn't been constructed yet and will be constructed as the synchronization continues in the same `Client:process` call.

### `Entity:willDestruct()`

**Client and server.** Called when an instance of this entity will be destroyed. This is called after `:willDespawn` on the server, and after `:willLeave` on the client.
