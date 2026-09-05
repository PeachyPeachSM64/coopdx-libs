# OSync

`osync` is a small library to handle reliable sync objects spawning without duplication in player code or object behavior code.<br>
**sm64coopdx v1.5.1 or later is required.**

> [!IMPORTANT]
> This library is using the hook `HOOK_ON_PACKET_RECEIVE`!<br>
> Packets with the field `osync` are handled by this library and should be ignored by other hooks.<br>
> Example code:
```lua
local function on_packet_receive(packet)
    if packet.osync then
        return
    end

    -- Not an osync packet
    -- ...
end
```

---

## Installation

1. Download the [libraries](https://github.com/PeachyPeachSM64/coopdx-libs/archive/refs/heads/master.zip).
2. Copy the `lib` directory from `osync` into your mod's directory. Your mod hierarchy should look like this:
```
your-mod/
  ├─ lib/
  │   └─ osync.lua
  ├─ main.lua
  └─ ...
```
3. Import the library at the top of your script:
```lua
local osync = require("/lib/osync")
```

---

## Functions

### `create_context (context, func, contextScope, timeToLive)`

Create a context for spawning sync objects.

Params:
- `context`: `string` - Name of the context. It must be unique.
- `func`: `function` - Function to run inside the context.
- `contextScope`: `integer` - *Optional*. Scope of the context.
- `timeToLive`: `integer` - *Optional*. Lifetime of the context after its objects have been spawned.

```lua
osync.create_context(context, func, contextScope, timeToLive)
```

<br>

### `spawn_sync_object (behaviorId, modelId, x, y, z, objSetupFunction)`

Create a sync object. Parameters are the same as the regular `spawn_sync_object`. The difference is that it doesn't return any object.

Params:
- `behaviorId`: `BehaviorId` - Behavior ID of the object.
- `modelId`: `ModelExtendedId` - Model ID of the object.
- `x`: `number` - Starting X position of the object.
- `y`: `number` - Starting Y position of the object.
- `z`: `number` - Starting Z position of the object.
- `objSetupFunction`: `function (Object)` - *Optional*. Setup function for the object.

```lua
osync.spawn_sync_object(behaviorId, modelId, x, y, z, objSetupFunction)
```

---

## Usage

Sync objects must be spawned inside a context. This context is the key to track which object has been spawned.

<br>

### The most basic example

Create a context with `osync.create_context`, then pass in a function that calls `osync.spawn_sync_object`.

```lua
osync.create_context("spawn_goomba", function ()
    osync.spawn_sync_object(id_bhvGoomba, E_MODEL_GOOMBA, x, y, z, nil)
end)
```

Pretty simple, isn't it?

But now, there is a problem. If you try to call that code again, a second Goomba won't spawn, until all players leave the level.<br>
That's intended. Remember, the context determines what has spawned: the game already processed the context `spawn_goomba`, so you can't reuse it again, even when changing areas.

<br>

### Context scope

Each context can define a *scope*, i.e. when it should be cleared to be used again.

There are three different values:
- `CONTEXT_SCOPE_LEVEL`: If set, the context is automatically cleared as soon as there is no player in the current level.
- `CONTEXT_SCOPE_AREA`: If set, the context is automatically cleared as soon as there is no player in the current area.
- `CONTEXT_SCOPE_ACT`: If set, the context is automatically cleared as soon as there is no player in the current act.

You can combine them to make contexts less persistent. By default, all contexts are `CONTEXT_SCOPE_LEVEL | CONTEXT_SCOPE_ACT`, which means they can't spawn their objects again as long as there is one player in the level and act (it's similar to how vanilla objects can't respawn until all players leave the level, even between areas).

To make the previous context able to spawn a Goomba in all areas, its code should be changed to:

```lua
osync.create_context("spawn_goomba", function ()
    osync.spawn_sync_object(id_bhvGoomba, E_MODEL_GOOMBA, x, y, z, nil)
end, osync.CONTEXT_SCOPE_LEVEL | osync.CONTEXT_SCOPE_AREA | osync.CONTEXT_SCOPE_ACT)
```

That's great, but what if I want to create the same context *multiple times*?

<br>

### Time to live

Last parameter of the `create_context` function is `timeToLive`. When set to a positive value, it allows the lib to clear the context after the specified duration, **starting from the moment the sync objects are spawned**.

To make a Goomba generator from the previous example, we can set a TTL:

```lua
osync.create_context("spawn_goomba", function ()
    osync.spawn_sync_object(id_bhvGoomba, E_MODEL_GOOMBA, x, y, z, nil)
end, osync.CONTEXT_SCOPE_LEVEL | osync.CONTEXT_SCOPE_AREA | osync.CONTEXT_SCOPE_ACT, 90)
```

It will make the context `spawn_goomba` usable again after at most 90 frames, no matter what.

---

## Configuration

You can configure various parameters of the `osync` library depending on your needs.

Here are the different parameters and their default value:

- `osync.config.requestTimeout`
  - The maximum allowed time a requester has to spawn sync objects when the lib allows it to do.
  - Default value is `30` frames (1 second).
- `osync.config.contextScope`
  - The default scope of a context.
  - Default value is `osync.CONTEXT_SCOPE_LEVEL | osync.CONTEXT_SCOPE_ACT`, i.e. a context is discarded if there is no player in the current level and act.
- `osync.config.debugLogs`
  - Show debug logs in console if enabled. Enable only during development.
  - Default value is `false`.

---

## Examples

[King Bob-omb v2](https://github.com/PeachyPeachSM64/coopdx-libs/tree/master/osync/example/king-bobomb-v2)
