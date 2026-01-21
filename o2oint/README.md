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
`projectile`


