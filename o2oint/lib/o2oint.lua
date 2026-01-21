--[[

    Object to object interactions

    filename: !o2oint.lua
    version: v1.1
    author: PeachyPeach
    required: sm64coopdx v1.4.0 or later

    A small library to handle object to object interactions with ease.

--]]

local type = type
local pairs = pairs
local ipairs = ipairs
local unpack = table.unpack
local obj_get_first = obj_get_first
local obj_get_next = obj_get_next
local get_id_from_behavior = get_id_from_behavior
local obj_is_valid_for_interaction = obj_is_valid_for_interaction
local obj_check_hitbox_overlap = obj_check_hitbox_overlap
local obj_check_overlap_with_hitbox_params = obj_check_overlap_with_hitbox_params

local DEFAULT_OBJ_LISTS = {
    OBJ_LIST_PLAYER,
    OBJ_LIST_EXT,
    OBJ_LIST_DESTRUCTIVE,
    OBJ_LIST_GENACTOR,
    OBJ_LIST_PUSHABLE,
    OBJ_LIST_LEVEL,
    OBJ_LIST_DEFAULT,
    OBJ_LIST_SURFACE,
    OBJ_LIST_POLELIKE,
}

local function tblfind(t, value, equals)
    for k, v in pairs(t) do
        if (equals and equals(v, value)) or (not equals and v == value) then
            return k
        end
    end
    return nil
end

local function get_function_name(func)
    for k, v in pairs(_G) do
        if v == func then
            return k
        end
    end
    return tostring(func)
end

local function process_interactions(interactions, interactor, context)
    local check_hitbox_overlap, args
    if type(interactor) == "table" then
        check_hitbox_overlap = obj_check_overlap_with_hitbox_params
        args = {
            interactor.oPosX,
            interactor.oPosY,
            interactor.oPosZ,
            interactor.hitboxRadius,
            interactor.hitboxHeight,
            interactor.hitboxDownOffset
        }
    else
        check_hitbox_overlap = obj_check_hitbox_overlap
        args = { interactor }
    end

    local interacted = {}
    local objLists = interactions.objectLists
    local behaviorIds = interactions.behaviorIds
    local functions = interactions.functions
    for _, objList in ipairs(objLists) do
        local obj = obj_get_first(objList)
        while obj do
            local interaction

            -- Check hitbox overlap
            if not check_hitbox_overlap(obj, unpack(args)) then
                goto next_obj
            end

            -- Check behavior id
            interaction = behaviorIds[get_id_from_behavior(obj.behavior)]
            if interaction then
                goto process_interaction
            end

            -- Check "obj is..." functions
            for _, func in ipairs(functions) do
                if func.func(obj) then
                    interaction = func
                    goto process_interaction
                end
            end

            -- No interaction found
            goto next_obj

            ::process_interaction::

            -- Check if the object is valid for interaction
            if interaction.ignoreIntangible or obj_is_valid_for_interaction(obj) then

                -- Process interaction, stop if it returns true
                interacted[#interacted+1] = obj
                if interaction.interact(interactor, obj, context) then
                    return interacted
                end
            end

            ::next_obj::

            obj = obj_get_next(obj)
        end
    end

    return interacted
end

---@class Interactions
---@field process_interactions fun(self, interactor: table|Object, context: table|nil): table Processes interactions for the interactor object and returns a table of interacted objects

---@param interactions table
---@return Interactions
--- Creates a new Interactions object
local function new_interactions(interactions)
    local t = {
        objectLists = {},
        behaviorIds = {},
        functions = {},
        process_interactions = process_interactions,
    }

    -- Object lists
    if type(interactions.objectLists) == "table" then

        -- Discard keys, we don't need those
        for _, objList in pairs(interactions.objectLists) do
            table.insert(t.objectLists, objList)
        end
    else
        t.objectLists = DEFAULT_OBJ_LISTS
    end

    -- Interactions
    if type(interactions.interactions) == "table" then
        for _, interaction in pairs(interactions.interactions) do

            -- Mandatory keys: 'targets' and 'interact'
            if interaction.targets and type(interaction.interact) == "function" then
                local targets = type(interaction.targets) == "table" and interaction.targets or {interaction.targets}
                for _, target in pairs(targets) do

                    -- Allowed types for target: number (behavior id), function
                    if type(target) == "number" then
                        if t.behaviorIds[target] then
                            error("An interaction is already defined for behavior: " .. get_behavior_name_from_id(target))
                        end
                        t.behaviorIds[target] = {
                            interact = interaction.interact,
                            ignoreIntangible = interaction.ignoreIntangible
                        }
                    elseif type(target) == "function" then
                        if tblfind(t.functions, target, function (l, r) return l.func == r end) then
                            error("An interaction is already defined for function: " .. get_function_name(target))
                        end
                        table.insert(t.functions, {
                            func = target,
                            interact = interaction.interact,
                            ignoreIntangible = interaction.ignoreIntangible
                        })
                    end
                end
            end
        end
    end

    return setmetatable({}, {
        __index = t,
        __newindex = function () end,
        __metatable = false
    })
end

local _o2oint = {
    Interactions = new_interactions
}

---@class o2oint
---@field Interactions fun(interactions: table): Interactions Creates a new Interactions object
local o2oint = setmetatable({}, {
    __index = _o2oint,
    __newindex = function () end,
    __metatable = false
})

return o2oint
