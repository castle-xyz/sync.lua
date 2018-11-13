# *sync.lua* reference manual

**NOTE**: This is a work in progress, more to come soon...

## Contents

  * [Module](#module)
  * [Clients and servers](#clients-and-servers)
     * [Creation](#creation)
        * [sync.newServer(options)](#syncnewserveroptions)
        * [sync.newClient(options)](#syncnewclientoptions)
     * [Disconnection](#disconnection)
        * [Client:disconnect()](#clientdisconnect)
     * [Querying entities](#querying-entities)
        * [Common.all](#commonall)
        * [Common:byId(id)](#commonbyidid)
        * [Common:byType(typeName)](#commonbytypetypename)
     * [Spawning and despawning entities](#spawning-and-despawning-entities)
        * [Server:spawn(typeName, ...)](#serverspawntypename-)
        * [Server:despawn(entOrId)](#serverdespawnentorid)
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

## Clients and servers

*sync.lua* synchronizes state using a client / server architecture. The *server* is the authority over all state. *clients* connect to the server and receive state updates from it. Clients usually connect to a sever running on a different computer over the network. A client can also connect to a server on the same computer or in the same process, which is useful for testing or to allow one of the players of a game to host a server.

### Creation

#### `sync.newServer(options)`

Creates a new *sync.lua* server instance.

##### Arguments

- **`options` (table, required)**: A table of options:
  - **`options.address` (string, optional)**: If set, an address form `'<ipaddress>:<port>'`, `'<hostname>:<port>'` or `'*:<port>'` (the `'*'` form uses the default host for this computer). If not set, defaults to `'*:22122'`.
  - **`options.controllerTypeName` (string, required)**: Should be the name of the type used to instantiate controller entities for clients that connect to this server.

##### Returns

Returns the `Server` instance created, which supports methods prefixed with `Server:` or `Common:` below.

#### `sync.newClient(options)`

Creates a new *sync.lua* client instance.

##### Arguments

- **`options` (table, required)**: A table of options:
  - **`options.address` (string, required)**: An address of the form `'<ipaddress>:<port>'` or `'<hostname>:<port>'` to connect to.

##### Returns

Returns the `Client` instance created, which supports methods prefixed with `Client:` or `Common:` below.

### Disconnection

#### `Client:disconnect()`

Disconnect from the server this client is connected to.

### Querying entities

#### `Common.all`

A table of all entities, where the keys are the ids of the entities and the values are the corresponding entities. This table is used internally by *sync.lua*, so *make sure not to modify* this table.

#### `Common:byId(id)`

Find an entity by id.

##### Arguments

- **`id` (number or nil)**: The id of the entity to look for.

##### Returns

Returns the entity that has the id given, or `nil` if the id is `nil` or if there is no entity with this id.

#### `Common:byType(typeName)`

Find entities by type.

##### Arguments

- **`typeName` (string)**: The name of the type to search by.

##### Returns

Returns a table of all the entities of the named type, where the keys are the ids of the entities and the values are the corresponding entities. Returns a direct reference to a table used internally by *sync.lua*, so *make sure not to modify* this table.

### Spawning and despawning entities

#### `Server:spawn(typeName, ...)`

Create an entity of the given type. Automatically synchronizes the entity to all connected clients for which the entity is relevant (the actual synchronization is sent on the next `:process` call).

##### Arguments

- **`typeName` (string)**: The name of the type of entity to spawn.
- **`...`**: Extra parameters to pass to the type's constructor and entity's `:didConstruct` and `:didSpawn` methods.

##### Returns

- **`id` (number)**: The id of the entity created.
- **`ent` (entity)**: The entity itself.

#### `Server:despawn(entOrId)`

Destroy an entity. Automatically removes the entity from all connected clients for which the entity is relevant (the actual synchronization is sent on the next `:process` call).

##### Arguments

- **`entOrId` (entity or id)**: The entity or the id of the entity to despawn.

##### Returns

Nothing.

### Synchronizing entities

#### `Common:sync(entOrId)`

Mark an entity as needing synchronization.

On server instances the state of the entity is sent to all clients for which the entity is relevant (the actual synchronization is sent on the next `:process` call). On client instances this doesn't send any synchronizations, but the method is still provided so that you can call `:sync` in shared code without causing an error.

Typically this needs to be called on an entity when any of its members change that clients need to be aware of, or if its return value for `:isRelevant` may have changed for any controller.

##### Arguments

- **`entOrId` (entity or id)**: The entity or the id of the entity to mark as needing synchronization.

##### Returns

Nothing.

### Processing

#### `Common:process()`

Send and receive synchronization data over the network. This method needs to be called on server and client instances periodically to keep them up to date. Typically you just call this method in `love.update`.

If you notice that calling this method every frame causes too much overhead and reduces your game's frame rate, you could try calling it every other frame or even less often than that. The trade-off is that the less often you call this method, the higher the latency in clients receiving network updates from the server.

##### Arguments

None.

##### Returns

Nothing.

### Controllers

#### `Client.controller`

The controller for this client. This is a local replica synchronized from the server, so all members are copied from the server, just like other replicated entities. The added specialty of the controller entity is that method calls on the client entity are sent to the server to be executed remotely. This allows clients to influence server state, while allowing the server to control what each client can influence.

### Time

#### `Client:serverTime()`

Get expected value returned by `love.timer.getTime()` as called on the server at this moment. *sync.lua* computes this value by synchronizing the client-server time difference periodically while accounting for network delay.
