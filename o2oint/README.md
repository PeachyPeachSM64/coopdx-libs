# Object to object interactions

`o2oint` is a small library to handle object to object interactions with ease.<br>
**sm64coopdx v1.4 or later is required.**

The goal is to simplify the definition of interactions between objects.<br>
Super Mario 64 handles them really poorly outside of Mario's interactions, which makes coding interactions for custom objects (a custom projectile for example) very tedious and unnecessarily complex. This library aims to fix that issue.

<br>

## Installation

1. Download the [libraries](https://github.com/PeachyPeachSM64/coopdx-libs/archive/refs/heads/master.zip).
2. Copy the `lib` directory from `o2oint` into your mod's directory.
3. Import the library at the top of your script:
```lua
local o2oint = require("lib/o2oint")
```

<br>

## Usage

First, you need to define a table of interactions.<br>
It's a table with the following structure:
```lua
local interactionsTable = {

    -- The different object lists the interactions will be performed on.
    -- If this field is not provided, it will use all (but spawner and unimportant) objects lists by default.
    -- More info about object lists here:
    --   https://github.com/coop-deluxe/sm64coopdx/blob/main/src/game/object_list_processor.h#L32
    objectLists = {
        ... OBJ_LIST_ constants ...
        -- for example:
        --   OBJ_LIST_DEFAULT,
        --   OBJ_LIST_GENACTOR,
        --   OBJ_LIST_SURFACE,
        --   etc...
    },

    -- The list of user-defined interactions.
    interactions = {

        -- Each interaction is a table with the following fields:
        -- - targets (mandatory)
        -- - interact (mandatory)
        -- - ignoreIntangible (optional)
        {
            -- What will define if an object is targeted by the interaction.
            -- Can be either a behavior id, a function or a table combining both types.
            targets = {

                -- A behavior id...
                id_bhvYellowCoin,

                -- A builtin function...
                obj_is_coin,

                -- A user-defined function (named or lambda)...
                function (obj)
                    return obj_is_coin(obj) or obj_is_secret(obj)
                end
            },

            -- The interaction function. It is called if the object is valid for interaction,
            -- has its hitbox overlapping with the interactor and is targeted by the interaction.
            -- It has 3 parameters:
            -- - interactor: it's the thing that interacts with the objects around it,
            --               the first parameter of the `process_interactions` function (see later).
            -- - interactee: the object that is interacted with.
            -- - context:    used-defined data passed to the `process_interactions` function (see later).
            interact = function (interactor, interactee, context)

                -- Code the interaction here.
                -- No return value is required, but if the function returns true,
                -- it will stop here and not process all remaining interactions or objects.

            end,

            -- Optional flag.
            -- If set to true, the interaction will ignore the intangibility state of the objects.
            ignoreIntangible = true
        },

        ...
    }
}
```

Then, you can create an `Interactions` object with the following code:
```lua
local interactions = o2oint.Interactions(interactionsTable)
```

This object has only one method: `process_interactions`.<br>
As the name suggests, it will be used to process the defined interactions.

Its signature is the following:<br>
`process_interactions(interactor: Object|table, context: table|nil) -> table[Object]`
- `interactor` is the object that interacts with the "targets". It can be either an `Object` (like `m.marioObj`) or a table with the following fields:
  - `oPosX`: the X coordinate of the interactor hitbox position.
  - `oPosY`: the Y coordinate of the interactor hitbox position.
  - `oPosZ`: the Z coordinate of the interactor hitbox position.
  - `hitboxRadius`: the radius of the interactor hitbox.
  - `hitboxHeight`: the height of the interactor hitbox.
  - `hitboxDownOffset`: the down offset of the interactor hitbox.
- `context` is a table which can hold anything and passed to the `interact` function of interactions. It can be used to transfer data that is not available by default (like a `MarioState` for example). Set it to `nil` if not needed.
- This method returns a list (table) of the interacted `Object`s.

In code, it is used like this:
```lua
local interactedObjects = interactions:process_interactions(interactor, context)
```

<br>

## Caveats

- Each behavior id and function can be used only once as `targets`.<br>The following example is therefore impossible, and the library will throw an error during the creation of the `Interactions` object:
```lua
local interactionsTable = {
    interactions = {
        {
            targets = {
                id_bhvYellowCoin,
                obj_is_coin,
            },
            interact = interact_func_1,
        },
        {
            targets = id_bhvYellowCoin, -- id_bhvYellowCoin is already assigned to interact_func_1.
            interact = interact_func_2,
        },
        {
            targets = obj_is_coin, -- obj_is_coin is already assigned to interact_func_1.
            interact = interact_func_3,
        }
    }
}
```
- Objects lists in `objectLists` are processed in the order they are defined, not the order the game normally processes them.<br>In the following example, objects from lists `OBJ_LIST_DEFAULT`, `OBJ_LIST_LEVEL` and `OBJ_LIST_PLAYER` will be processed in that order:
```lua
local interactionsTable = {
    objectLists = {
        OBJ_LIST_DEFAULT,
        OBJ_LIST_LEVEL,
        OBJ_LIST_PLAYER,
    },
    interactions = {
        ...
    }
}
```
- Interactions in `interactions` are processed in the order they are defined, **except for behavior ids `targets`, which are always processed first**.<br>In the following example, the library will check if the currently processed object has the behavior id `id_bhvYellowCoin` first, even though it is defined in a second interaction:
```lua
local interactionsTable = {
    interactions = {
        {
            targets = obj_is_coin,
            interact = interact_func_1,
        },
        {
            -- If the currently processed object has the behavior id id_bhvYellowCoin,
            -- interact_func_2 will be called, even if obj_is_coin would have returned true.
            targets = id_bhvYellowCoin,
            interact = interact_func_2,
        }
    }
}
```
- Only one `interact` function is called per object, no matter the return value.<br>In the following example, only `interact_func_1` is called:
```lua
-- object's behavior is bhvYellowCoin

local interactionsTable = {
    interactions = {
        -- Interaction 1 is more generic, but since bhvYellowCoin is a valid target,
        -- interact_func_1 is called.
        {
            targets = function (obj)
                return get_object_list_from_behavior(obj.behavior) == OBJ_LIST_LEVEL
            end,
            interact = interact_func_1,
        },
        -- Interaction 2 is more specific to coins, but since interact_func_1 was already called,
        -- interact_func_2 is skipped.
        {
            targets = obj_is_coin,
            interact = interact_func_2,
        }
    }
}
```

<br>

## Example 1

Here is a simple example:<br>
`We want Mario to attract nearby coins.`

<br>

1. First, define the `Interactions` object:
```lua
local o2oint = require("lib/o2oint")

local coinMagnetInteractions = o2oint.Interactions({
    objectLists = {
        OBJ_LIST_LEVEL -- All coin behaviors are defined in this list. No need for other ones.
    },
    interactions = {
        {
            targets = obj_is_coin, -- The function that will tell if an object is a coin.
            interact = function (interactor, interactee, context)

                -- Move the coin towards the interactor, at a max speed of `pullSpeed` units.
                local v = {
                    x = interactor.oPosX - interactee.oPosX,
                    y = interactor.oPosY - interactee.oPosY,
                    z = interactor.oPosZ - interactee.oPosZ,
                }
                local len = vec3f_length(v)
                vec3f_set_magnitude(v, min(len, context.pullSpeed))
                interactee.oPosX = interactee.oPosX + v.x
                interactee.oPosY = interactee.oPosY + v.y
                interactee.oPosZ = interactee.oPosZ + v.z
            end
        }
    }
})
```

<br>

2. Then, process the interactions during a Mario update:
```lua
local function mario_update_attract_coins(m)

    -- We don't want inactive Marios to attract coins.
    if is_player_active(m) == 0 then
        return
    end

    -- The coin magnet "object".
    -- It doesn't have to be a real object,
    -- only the 6 following fields are needed.
    local coinMagnet = {
        oPosX = m.pos.x,
        oPosY = m.pos.y,
        oPosZ = m.pos.z,
        hitboxRadius = 1000,
        hitboxHeight = 1000,
        hitboxDownOffset = 500
    }

    -- Attract coins around the magnet.
    coinMagnetInteractions:process_interactions(coinMagnet, { pullSpeed = 50 })
end
```

<br>

3. Finally, hook that function:
```lua
hook_event(HOOK_MARIO_UPDATE, mario_update_attract_coins)
```

<br>

And you're done!<br>
Mario will now attract all coins in a 1000 units radius around him.

<br>

## Example 2

A more complex example:<br>
`Throw a fireball in front of Mario when pressing the X button, that attacks enemies and collect coins.`

<br>

1. Let's define the `Interactions` object:
```lua
local o2oint = require("lib/o2oint")

local function bhv_fireball_despawn(o)
    spawn_mist_particles_with_sound(SOUND_OBJ_DEFAULT_DEATH)
    obj_mark_for_deletion(o)
end

local sFireballInteractions = o2oint.Interactions({
    objectLists = {
        OBJ_LIST_LEVEL, -- Coins
        OBJ_LIST_GENACTOR, -- Common enemies
        OBJ_LIST_PUSHABLE, -- Goombas, Koopas, Lakitus
        OBJ_LIST_DESTRUCTIVE, -- Bob-ombs, breakable boxes
        OBJ_LIST_SURFACE, -- Boxes
    },
    interactions = {

        -- Behavior for coins: collect the coin.
        {
            targets = {
                obj_is_coin,
            },
            interact = function (interactor, interactee, context)
                interact_coin(context.m, INTERACT_COIN, interactee)
            end,
            ignoreIntangible = false
        },

        -- Default behavior for most of the enemies: attack the enemy.
        {
            targets = {
                id_bhvBobomb,
                obj_is_attackable,
                obj_is_exclamation_box,
            },
            interact = function (interactor, interactee, context)
                interactee.oInteractStatus = interactee.oInteractStatus | ATTACK_PUNCH | INT_STATUS_WAS_ATTACKED | INT_STATUS_INTERACTED | INT_STATUS_TOUCHED_BOB_OMB
                bhv_fireball_despawn(interactor) -- Despawn the fireball on hit.
            end,
            ignoreIntangible = false
        },

        -- Behavior for breakable boxes: break the box.
        {
            targets = {
                obj_is_breakable_object,
            },
            interact = function (interactor, interactee, context)
                interactee.oInteractStatus = interactee.oInteractStatus | ATTACK_KICK_OR_TRIP | INT_STATUS_INTERACTED | INT_STATUS_WAS_ATTACKED | INT_STATUS_STOP_RIDING -- "broken" status, specific to breakable boxes.
                bhv_fireball_despawn(interactor) -- Despawn the fireball on hit.
            end,
            ignoreIntangible = false
        },

        -- Behavior for bullies: repel the bully.
        {
            targets = {
                obj_is_bully,
            },
            interact = function (interactor, interactee, context)
                interactee.oMoveAngleYaw = obj_angle_to_object(interactor, interactee)
                interactee.oForwardVel = 3392.0 / interactee.hitboxRadius
                interactee.oInteractStatus = interactee.oInteractStatus | ATTACK_PUNCH | INT_STATUS_WAS_ATTACKED | INT_STATUS_INTERACTED
                bhv_fireball_despawn(interactor) -- Despawn the fireball on hit.
            end,
            ignoreIntangible = false
        }
    }
})
```

<br>

2. Then, define the fireball behavior:
```lua

-- Initialization function for the fireball behavior.
-- Set hitbox and tangibility for interactions,
-- move yaw, forward vel and friction for movement,
-- offset, scale and billboard for graphics.
local function bhv_fireball_init(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE | OBJ_FLAG_MOVE_XZ_USING_FVEL
    o.hitboxRadius = 50
    o.hitboxHeight = 80
    o.oWallHitboxRadius = 30
    o.oIntangibleTimer = 0
    o.oMoveAngleYaw = o.oFaceAngleYaw
    o.oForwardVel = 30
    o.oFriction = 1.0
    o.oGraphYOffset = 40
    obj_scale(o, 4)
    obj_set_billboard(o)
end

-- Update function for the fireball behavior.
local function bhv_fireball_update(o)

    -- Despawn the fireball after some time.
    if o.oTimer > 150 then
        bhv_fireball_despawn(o)
        return
    end

    -- Move the fireball.
    local stepResult = object_step()

    -- Despawn the fireball if it hits a wall.
    if stepResult & OBJ_COL_FLAG_HIT_WALL ~= 0 then
        bhv_fireball_despawn(o)
        return
    end

    -- Despawn the fireball if it touches water.
    if stepResult & OBJ_COL_FLAG_UNDERWATER ~= 0 then
        bhv_fireball_despawn(o)
        play_sound(SOUND_GENERAL_FLAME_OUT, o.header.gfx.cameraToObject)
        return
    end

    -- Process interactions.
    -- Pass the MarioState of the owner of the fireball as context for the coin interaction.
    local m = gMarioStates[network_local_index_from_global(o.globalPlayerIndex)]
    sFireballInteractions:process_interactions(o, { m = m })

    -- Animate the fireball.
    if o.oTimer % 2 == 0 then
        o.oAnimState = o.oAnimState + 1

        -- Spawn a trail of smaller flames for a sweet graphical effect.
        spawn_non_sync_object(id_bhvSparkle, E_MODEL_RED_FLAME, o.oPosX, o.oPosY + 40, o.oPosZ, function (obj)
            obj_scale(obj, 2)
            obj_set_billboard(obj)
            obj.oAnimState = math.random(0, 3)
        end)
    end
end

-- Hook the fireball behavior.
id_bhvFireball = hook_behavior(nil, OBJ_LIST_GENACTOR, true, bhv_fireball_init, bhv_fireball_update, "bhvFireball")
```

<br>

3. Finally, add a Mario update hook to spawn a fireball when X is pressed:
```lua
hook_event(HOOK_MARIO_UPDATE, function (m)
    if m.controller.buttonPressed & X_BUTTON ~= 0 then
        spawn_non_sync_object(id_bhvFireball, E_MODEL_RED_FLAME, m.pos.x, m.pos.y + 60, m.pos.z, function (o)
            o.oFaceAngleYaw = m.faceAngle.y
            o.globalPlayerIndex = network_global_index_from_local(0)
        end)
        play_sound(SOUND_OBJ_FLAME_BLOWN, m.marioObj.header.gfx.cameraToObject)
    end
end)
```

<br>

And that's it!<br>
Press X to throw a fireball that attacks enemies and collect coins.

<br>
