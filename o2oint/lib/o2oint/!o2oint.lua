--[[

    Object to object interactions

    filename: !o2oint.lua
    version: v1.0
    author: PeachyPeach
    required: sm64coopdx v1.0.0 or later

    A small library to handle object to object interactions with ease.

--]]

-- If this file exists in the main directory, but already loaded with require, skip it.
if _G.libLoaded_o2oint then
    return
end

local type = type
local pairs = pairs
local ipairs = ipairs
local unpack = table.unpack
local strfind = string.find
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
    OBJ_LIST_SPAWNER,
    OBJ_LIST_UNIMPORTANT,
}

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
    for _, interaction in ipairs(interactions.interactions) do
        local ignoreIntangible = interaction.ignoreIntangible
        local behaviorIds = interaction.behaviorIds
        local functions = interaction.functions
        local interact = interaction.interact

        for _, objList in ipairs(objLists) do
            local obj = obj_get_first(objList)
            while obj do

                -- Check if the object is valid for interaction
                if ignoreIntangible or obj_is_valid_for_interaction(obj) then

                    -- Check the behavior id
                    if behaviorIds[get_id_from_behavior(obj.behavior)] then
                        goto process_interaction
                    end

                    -- Check the "obj is..." functions
                    for _, func in ipairs(functions) do
                        if func(obj) then
                            goto process_interaction
                        end
                    end

                    goto no_interaction

                    ---------------------------------------------------

                    ::process_interaction::

                    if check_hitbox_overlap(obj, unpack(args)) then
                        interacted[#interacted+1] = obj
                        if interact(interactor, obj, context) then
                            return interacted
                        end
                    end

                    ::no_interaction::
                end

                obj = obj_get_next(obj)
            end
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
        process_interactions = process_interactions,
    }

    -- Object lists
    if type(interactions.objectLists) == "table" then
        t.objectLists = {}

        -- Discard keys, we don't need those
        for _, objList in pairs(interactions.objectLists) do
            table.insert(t.objectLists, objList)
        end
    else
        t.objectLists = DEFAULT_OBJ_LISTS
    end

    -- Interactions
    t.interactions = {}
    if type(interactions.interactions) == "table" then

        -- Discard keys, we don't need those
        for _, interaction in pairs(interactions.interactions) do
            local int = {
                behaviorIds = {},
                functions = {},
            }

            -- Mandatory key: 'targets'
            if not interaction.targets then
                goto next_interaction
            end
            local targets = type(interaction.targets) == "table" and interaction.targets or {interaction.targets}
            for _, target in pairs(targets) do

                -- Allowed types for target: number (behavior id), function
                if type(target) == "number" then
                    int.behaviorIds[target] = true
                elseif type(target) == "function" then
                    table.insert(int.functions, target)
                end
            end
            if #int.behaviorIds == 0 and #int.functions == 0 then
                goto next_interaction
            end

            -- Mandatory key: 'interact'
            if type(interaction.interact) ~= "function" then
                goto next_interaction
            end
            int.interact = interaction.interact

            -- Optional key: 'ignoreIntangible'
            int.ignoreIntangible = interaction.ignoreIntangible

            table.insert(t.interactions, int)

            ::next_interaction::
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

-- For compatibility with sm64coopdx versions below v1.4.0, which don't have the require keyword,
-- this file can be used in the main directory.
-- In that case, even for newer versions, 'require' must be overridden to return this lib
-- (and not load it accidentally twice).
local _require = _G.require
_G.require = function (modname)
    if strfind(modname, "!o2oint") then
        return o2oint
    end
    if _require then
        return _require(modname)
    end
end
_G.libLoaded_o2oint = true

return o2oint
