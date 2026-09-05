--[[

    Reliable spawn sync objects

    filename: osync.lua
    version: v2.0
    author: PeachyPeach
    required: sm64coopdx v1.5.1 or later

    A small library to handle reliable sync objects spawning
    without duplication in player code or object behavior code.
    Packets used by this lib have the field "osync" and should
    be ignored by mods `HOOK_ON_PACKET_RECEIVE` hooks.
--]]

local mfloor = math.floor
local tconcat = table.concat
local tinsert = table.insert
local tremove = table.remove
local tunpack = table.unpack
local sformat = string.format
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local get_global_timer = get_global_timer
local network_player_connected_count = network_player_connected_count
local network_global_index_from_local = network_global_index_from_local
local network_local_index_from_global = network_local_index_from_global
local network_send_to = network_send_to
local spawn_sync_object = spawn_sync_object

local OSYNC_PACKET_MAGIC        = "osync"
local OSYNC_PACKET_TYPE_REQUEST = 1
local OSYNC_PACKET_TYPE_SPAWN   = 2
local OSYNC_PACKET_TYPE_ACK     = 3
local OSYNC_PACKET_TYPE_CLEAR   = 4

local OSYNC_CONTEXT_SCOPE_LEVEL = 0x100
local OSYNC_CONTEXT_SCOPE_AREA  = 0x010
local OSYNC_CONTEXT_SCOPE_ACT   = 0x001

local OSYNC_IS_HEADLESS = gServerSettings.headlessServer and gServerSettings.headlessServer ~= 0 and network_is_server()

---@alias list<T> table<integer, T>

------------
-- Config --
------------

---@class OSyncConfig
---@field requestTimeout integer
---@field contextScope   integer
---@field debugLogs      boolean

---@type OSyncConfig
local sOSyncConfig = {
    requestTimeout = 30,
    contextScope = OSYNC_CONTEXT_SCOPE_LEVEL | OSYNC_CONTEXT_SCOPE_ACT,
    debugLogs = false,
}

-------------------
-- Host contexts --
-------------------

---@alias OSyncContextId string

---@class OSyncContextRequester
---@field globalIndex integer
---@field timestamp   integer

---@class OSyncContext
---@field levelNum       integer|LevelNum
---@field areaIndex      integer
---@field actNum         integer
---@field contextScope   integer
---@field timeToLive     integer
---@field requesters     list<OSyncContextRequester>
---@field spawnSent      boolean
---@field objectsSpawned boolean
---@field timestamp      integer

---@type table<OSyncContextId, OSyncContext>
local sOSyncContexts = {}

------------------
-- Sync objects --
------------------

---@class OSyncObject
---@field behaviorId       BehaviorId
---@field modelId          ModelExtendedId
---@field x                number
---@field y                number
---@field z                number
---@field objSetupFunction fun(o: Object)|nil

---@class OSyncObjects
---@field levelNum     integer|LevelNum
---@field areaIndex    integer
---@field actNum       integer
---@field contextScope integer
---@field timeToLive   integer
---@field objects      list<OSyncObject>
---@field timestamp    integer
---@field requestSent  boolean

---@type table<OSyncContextId, OSyncObjects>
local sOSyncObjects = {}

------------------
-- Packet types --
------------------

---@class OSyncPacketRequest
---@field globalIndex  integer
---@field timestamp    integer
---@field contextId    OSyncContextId
---@field contextScope integer
---@field timeToLive   integer

---@class OSyncPacketSpawn
---@field globalIndex integer
---@field timestamp   integer
---@field contextId   OSyncContextId

---@class OSyncPacketAck
---@field globalIndex    integer
---@field contextId      OSyncContextId
---@field objectsSpawned boolean

---@class OSyncPacketClear
---@field globalIndex integer
---@field contextId   OSyncContextId

---@alias OSyncPacket OSyncPacketRequest|OSyncPacketSpawn|OSyncPacketAck|OSyncPacketClear

local OSYNC_PACKET_TYPE_NAMES = {
    [OSYNC_PACKET_TYPE_REQUEST] = "OSYNC_PACKET_TYPE_REQUEST",
    [OSYNC_PACKET_TYPE_SPAWN]   = "OSYNC_PACKET_TYPE_SPAWN",
    [OSYNC_PACKET_TYPE_ACK]     = "OSYNC_PACKET_TYPE_ACK",
    [OSYNC_PACKET_TYPE_CLEAR]   = "OSYNC_PACKET_TYPE_CLEAR",
}

-----------
-- Debug --
-----------

local _timeOffset = 0
local _prevSecond = 0
hook_event(HOOK_UPDATE, function ()
    if _timeOffset == 0 then
        local s = get_date_and_time().second
        if _prevSecond == 0 then
            _prevSecond = s
        elseif _prevSecond ~= s then
            _timeOffset = clock_elapsed_f64()
        end
    end
end)

---@return integer
local function _get_time_ms()
    return mfloor((clock_elapsed_f64() - _timeOffset) * 1000) % 1000
end

---@param fmt string
---@param ... any
local function _print_debug_log(fmt, ...)
    if sOSyncConfig.debugLogs then
        local dt = get_date_and_time()
        print(sformat(
            "{osync} [%04d-%02d-%02d %02d:%02d:%02d.%03d] ",
            dt.year + 1900,
            dt.month + 1,
            dt.day,
            dt.hour,
            dt.minute,
            dt.second,
            _get_time_ms()
        ) .. sformat(fmt, ...))
    end
end

---@param received boolean
---@param globalIndex integer
---@param packet OSyncPacket|table<string, any>
local function _print_packet_debug_log(received, globalIndex, packet)
    if sOSyncConfig.debugLogs then
        local packetType = packet.type
        local packetTypeName = OSYNC_PACKET_TYPE_NAMES[packetType]
        local msg =
            received and
            sformat("<<<<< Received packet type %s from global index %d with params:", packetTypeName, globalIndex) or
            sformat(">>>>> Sent packet type %s to global index %d with params:", packetTypeName, globalIndex)
        for k, v in pairs(packet) do
            if k ~= OSYNC_PACKET_MAGIC and k ~= "type" and k ~= "globalIndex" then
                msg = msg .. " " .. k .. "=" .. tostring(v)
            end
        end
        _print_debug_log(msg)
    end
end

-----------
-- Utils --
-----------

---@param np NetworkPlayer
---@param context string
---@return OSyncContextId
local function osync_get_context_id(np, context)
    return tconcat({np.currLevelNum, np.currAreaIndex, np.currActNum, context}, "_")
end

---@param contextId OSyncContextId
---@return integer|LevelNum? levelNum
---@return integer? areaIndex
---@return integer? actNum
local function osync_get_level_area_act_from_context_id(contextId)
    local levelNum, areaIndex, actNum = contextId:match("^([^_]*)_([^_]*)_([^_]*)_.*$")
    return tonumber(levelNum), tonumber(areaIndex), tonumber(actNum)
end

---@param contextId OSyncContextId
---@return boolean
---@return integer|LevelNum? levelNum
---@return integer? areaIndex
---@return integer? actNum
local function osync_check_context_id(contextId)
    local levelNum, areaIndex, actNum = osync_get_level_area_act_from_context_id(contextId)
    if not levelNum or not areaIndex or not actNum then
        _print_debug_log("[ERROR] Invalid context ID: %s", contextId)
        return false
    end
    return true, levelNum, areaIndex, actNum
end

-------------
-- Packets --
-------------

local OSYNC_PACKET_CALLBACKS

---@param packet table<string, any>
local function osync_receive_packet(packet)
    if packet[OSYNC_PACKET_MAGIC] then
        local callback = OSYNC_PACKET_CALLBACKS[packet.type]
        if not callback then
            _print_debug_log("[ERROR] Invalid packet type received: %d", packet.type)
        elseif callback.host and not network_is_server() then
            _print_debug_log("[ERROR] Received a host-only packet type: %d", packet.type)
        else
            callback.func(packet)
        end
    end
end

---@param globalIndex integer
---@param reliable boolean
---@param packetType integer
---@param packet table<string, any>
local function osync_send_packet(globalIndex, reliable, packetType, packet)
    packet[OSYNC_PACKET_MAGIC] = true
    packet.type = packetType
    packet.globalIndex = network_global_index_from_local(0)
    _print_packet_debug_log(false, globalIndex, packet)

    local localIndex = network_local_index_from_global(globalIndex)
    if localIndex == 0 then -- send to self
        osync_receive_packet(packet)
    else
        network_send_to(localIndex, reliable, packet)
    end
end

---@param contextId OSyncContextId
---@param objectsSpawned boolean
local function osync_send_ack(contextId, objectsSpawned)
    osync_send_packet(0, true, OSYNC_PACKET_TYPE_ACK, {
        contextId = contextId,
        objectsSpawned = objectsSpawned
    })
end

---@param packet OSyncPacket|table<string, any>
---@param paramNames list<string>
---@return boolean
---@return any?...
local function osync_get_packet_params(packet, paramNames)
    local packetType = packet.type
    local params = {}
    for _, paramName in ipairs(paramNames) do
        local param = packet[paramName]
        if param == nil then
            _print_debug_log("[ERROR] Missing field `%s` in packet type %s", paramName, OSYNC_PACKET_TYPE_NAMES[packetType])
            return false
        end
        params[#params+1] = param
    end

    _print_packet_debug_log(true, packet.globalIndex, packet)

    return true, tunpack(params)
end

---@param packet OSyncPacketRequest
local function osync_receive_packet_type_request(packet)
    local ok, globalIndex, timestamp, contextId, contextScope, timeToLive = osync_get_packet_params(packet,
        { "globalIndex", "timestamp", "contextId", "contextScope", "timeToLive" }
    )
    if not ok then
        return
    end

    -- Check context ID
    local ok, levelNum, areaIndex, actNum = osync_check_context_id(contextId)
    if not ok then
        return
    end

    -- Add to contexts
    if not sOSyncContexts[contextId] then
        sOSyncContexts[contextId] = {
            levelNum = levelNum,
            areaIndex = areaIndex,
            actNum = actNum,
            contextScope = contextScope,
            timeToLive = timeToLive,
            requesters = {},
            spawnSent = false,
            objectsSpawned = false,
            timestamp = 0,
        }
    end

    ---@type OSyncContext
    local context = sOSyncContexts[contextId]
    if not context.objectsSpawned then
        context.contextScope = contextScope
        context.timeToLive = timeToLive
        tinsert(context.requesters, {
            globalIndex = globalIndex,
            timestamp = timestamp,
        })
    end
end

---@param packet OSyncPacketSpawn
local function osync_receive_packet_type_spawn(packet)
    local ok, globalIndex, timestamp, contextId = osync_get_packet_params(packet,
        { "globalIndex", "timestamp", "contextId" }
    )
    if not ok then
        return
    end

    -- Sender is not the host
    if globalIndex ~= 0 then
        _print_debug_log("[ERROR] Sender is not host, but global index: %d", globalIndex)
        return
    end

    -- Check context ID
    if not osync_check_context_id(contextId) then
        return
    end

    ---@type OSyncObjects
    local syncObjects = sOSyncObjects[contextId]

    -- No sync objects
    if not syncObjects then
        _print_debug_log("(WARNING) Cannot spawn sync objects, context ID doesn't exist: %s", contextId)
        osync_send_ack(contextId, false)
        return
    end

    -- Request not sent
    if not syncObjects.requestSent then
        _print_debug_log("[ERROR] Cannot spawn sync objects, no request sent for context ID: %s", contextId)
        osync_send_ack(contextId, false)
        return
    end

    ---@type NetworkPlayer
    local np = gNetworkPlayers[0]

    -- Levels don't match
    if np.currLevelNum ~= syncObjects.levelNum then
        _print_debug_log("(WARNING) Cannot spawn sync objects, levels don't match (current is %d, should be %d)", np.currLevelNum, syncObjects.levelNum)
        osync_send_ack(contextId, false)
        return
    end

    -- Areas don't match
    if np.currAreaIndex ~= syncObjects.areaIndex then
        _print_debug_log("(WARNING) Cannot spawn sync objects, areas don't match (current is %d, should be %d)", np.currAreaIndex, syncObjects.areaIndex)
        osync_send_ack(contextId, false)
        return
    end

    -- Acts don't match
    if np.currActNum ~= syncObjects.actNum then
        _print_debug_log("(WARNING) Cannot spawn sync objects, acts don't match (current is %d, should be %d)", np.currActNum, syncObjects.actNum)
        osync_send_ack(contextId, false)
        return
    end

    -- Timestamps don't match
    if timestamp ~= syncObjects.timestamp then
        _print_debug_log("(WARNING) Cannot spawn sync objects, timestamps don't match (received is %d, should be %d)", timestamp, syncObjects.timestamp)
        osync_send_ack(contextId, false)
        return
    end

    -- Not sync valid (should not happen)
    if not np.currAreaSyncValid then
        _print_debug_log("[ERROR] Cannot spawn sync objects, current area is not sync valid!")
        osync_send_ack(contextId, false)
        return
    end

    -- Spawn sync objects
    -- Exit on first failure, but might cause duplicates
    for _, syncObject in ipairs(syncObjects.objects) do
        local obj = spawn_sync_object(
            syncObject.behaviorId,
            syncObject.modelId,
            syncObject.x,
            syncObject.y,
            syncObject.z,
            syncObject.objSetupFunction
        )
        if not obj then
            _print_debug_log("[ERROR] Failed to spawn sync object!")
            osync_send_ack(contextId, false)
            sOSyncObjects[contextId] = nil
            return
        end
    end

    osync_send_ack(contextId, true)
    _print_debug_log("Spawned %d sync objects in level %d, area %d, act %d", #syncObjects.objects, np.currLevelNum, np.currAreaIndex, np.currActNum)
    sOSyncObjects[contextId] = nil
end

---@param packet OSyncPacketAck
local function osync_receive_packet_type_ack(packet)
    local ok, globalIndex, contextId, objectsSpawned = osync_get_packet_params(packet,
        { "globalIndex", "contextId", "objectsSpawned" }
    )
    if not ok then
        return
    end

    -- Check context ID
    if not osync_check_context_id(contextId) then
        return
    end

    -- Check if context exists
    ---@type OSyncContext
    local context = sOSyncContexts[contextId]
    if not context then
        _print_debug_log("(WARNING) Context ID doesn't exist: %s", contextId)
        return
    end

    -- Objects already spawned
    if context.objectsSpawned then
        return
    end

    -- Update context with response
    if objectsSpawned then

        -- Send clear packet to other requesters
        for _, requester in ipairs(context.requesters) do
            if requester.globalIndex ~= globalIndex then
                osync_send_packet(requester.globalIndex, false, OSYNC_PACKET_TYPE_CLEAR, {
                    contextId = contextId
                })
            end
        end

        context.requesters = {}
        context.spawnSent = true
        context.objectsSpawned = true
    else

        -- Remove requester from list
        for i, requester in ipairs(context.requesters) do
            if requester.globalIndex == globalIndex then
                context.spawnSent = false
                tremove(context.requesters, i)
                return
            end
        end
        _print_debug_log("(WARNING) Global index %d didn't request context ID: %s", globalIndex, contextId)
    end
end

---@param packet OSyncPacketClear
local function osync_receive_packet_type_clear(packet)
    local ok, globalIndex, contextId = osync_get_packet_params(packet,
        { "globalIndex", "contextId" }
    )
    if not ok then
        return
    end

    -- Sender is not the host
    if globalIndex ~= 0 then
        _print_debug_log("[ERROR] Sender is not host, but global index: %d", globalIndex)
        return
    end

    sOSyncObjects[contextId] = nil
end

OSYNC_PACKET_CALLBACKS = {
    [OSYNC_PACKET_TYPE_REQUEST] = { func = osync_receive_packet_type_request, host = true  },
    [OSYNC_PACKET_TYPE_SPAWN]   = { func = osync_receive_packet_type_spawn,   host = false },
    [OSYNC_PACKET_TYPE_ACK]     = { func = osync_receive_packet_type_ack,     host = true  },
    [OSYNC_PACKET_TYPE_CLEAR]   = { func = osync_receive_packet_type_clear,   host = false },
}

hook_event(HOOK_ON_PACKET_RECEIVE, osync_receive_packet)

----------
-- Host --
----------

---@param contextScope integer
---@param levelNum integer|LevelNum
---@param areaIndex integer
---@param actNum integer
---@return boolean
local function osync_check_context_scope(contextScope, levelNum, areaIndex, actNum)
    for i = 0, network_player_connected_count() do
        local np = gNetworkPlayers[i]
        if (i ~= 0 or not OSYNC_IS_HEADLESS) and
            (contextScope & OSYNC_CONTEXT_SCOPE_LEVEL == 0 or np.currLevelNum == levelNum) and
            (contextScope & OSYNC_CONTEXT_SCOPE_AREA == 0 or np.currAreaIndex == areaIndex) and
            (contextScope & OSYNC_CONTEXT_SCOPE_ACT == 0 or np.currActNum == actNum)
        then
            return true
        end
    end
    return false
end

---@param context OSyncContext
---@return boolean
local function osync_update_context_ttl(context)
    if not context.objectsSpawned then
        return true
    end
    if context.timeToLive > 0 then
        context.timeToLive = context.timeToLive - 1
        return context.timeToLive > 0
    end
    return true
end

local function osync_update_contexts()
    local gtimer = get_global_timer()

    local contextsToClear = {}
    for contextId, context in pairs(sOSyncContexts) do

        -- Clear contexts with no player
        if not osync_check_context_scope(context.contextScope, context.levelNum, context.areaIndex, context.actNum) then
            contextsToClear[#contextsToClear+1] = contextId
            _print_debug_log("[_HOST_] Clearing context ID: %s (no player in scope)", contextId)

        -- Clear contexts with expired TTL
        elseif not osync_update_context_ttl(context) then
            contextsToClear[#contextsToClear+1] = contextId
            _print_debug_log("[_HOST_] Clearing context ID: %s (expired)", contextId)

        -- Skip contexts with already spawned objects
        elseif not context.objectsSpawned then

            -- Send spawn packet to first player in list
            if not context.spawnSent then
                local requester = context.requesters[1]
                if requester then
                    osync_send_packet(requester.globalIndex, true, OSYNC_PACKET_TYPE_SPAWN, {
                        timestamp = requester.timestamp,
                        contextId = contextId,
                    })
                    context.spawnSent = true
                    context.timestamp = gtimer
                end

            -- Remove player from list if no response
            elseif gtimer > context.timestamp + sOSyncConfig.requestTimeout then
                local requester = context.requesters[1]
                if requester then
                    _print_debug_log("(WARNING) [_HOST_] No response received from global index %d for context ID: %s", requester.globalIndex, contextId)
                    tremove(context.requesters, 1)
                    context.spawnSent = true
                    context.timestamp = gtimer
                end
            end

            -- Drop context if no requester
            -- Need to check objectsSpawned again because the code above can change it in a single iteration with:
            -- send spawn -> receive spawn -> spawn objects -> send ack -> receive ack -> set objectsSpawned to true
            if not context.objectsSpawned and #context.requesters == 0 then
                _print_debug_log("(WARNING) [_HOST_] No requester left for context ID: %s", contextId)
                contextsToClear[#contextsToClear+1] = contextId
            end
        end
    end

    -- Clear contexts
    for _, contextId in ipairs(contextsToClear) do
        sOSyncContexts[contextId] = nil
    end
end

---@param m MarioState
local function osync_on_player_disconnected(m)
    local globalIndex = network_global_index_from_local(m.playerIndex)

    -- Remove this player from all requests
    for _, context in pairs(sOSyncContexts) do
        local i = 1
        while i <= #context.requesters do
            if context.requesters[i].globalIndex == globalIndex then
                if i == 1 then
                    context.spawnSent = false
                end
                tremove(context.requesters, i)
            else
                i = i + 1
            end
        end
    end
end

hook_event(HOOK_UPDATE, osync_update_contexts)
hook_event(HOOK_ON_PLAYER_DISCONNECTED, osync_on_player_disconnected)

-----------
-- Local --
-----------

local function osync_update_sync_objects()
    local np = gNetworkPlayers[0]
    local gtimer = get_global_timer()

    local contextsToClear = {}
    for contextId, syncObjects in pairs(sOSyncObjects) do

        -- Check scope
        if (syncObjects.contextScope & OSYNC_CONTEXT_SCOPE_LEVEL ~= 0 and np.currLevelNum ~= syncObjects.levelNum) -- level mismatch
        or (syncObjects.contextScope & OSYNC_CONTEXT_SCOPE_AREA ~= 0 and np.currAreaIndex ~= syncObjects.areaIndex) -- area mismatch
        or (syncObjects.contextScope & OSYNC_CONTEXT_SCOPE_ACT ~= 0 and np.currActNum ~= syncObjects.actNum) -- act mismatch
        then

            -- Schedule for deletion
            contextsToClear[#contextsToClear+1] = contextId

        elseif not syncObjects.requestSent and np.currAreaSyncValid then

            -- Request spawn
            osync_send_packet(0, true, OSYNC_PACKET_TYPE_REQUEST, {
                timestamp = gtimer,
                contextId = contextId,
                contextScope = syncObjects.contextScope,
                timeToLive = syncObjects.timeToLive,
            })
            syncObjects.timestamp = gtimer
            syncObjects.requestSent = true
        end
    end

    -- Clear contexts
    for _, contextId in ipairs(contextsToClear) do
        sOSyncObjects[contextId] = nil
    end
end

hook_event(HOOK_UPDATE, osync_update_sync_objects)

---------
-- API --
---------

local sOSyncContextId = nil

--- @param context string
--- @param func function
--- @param contextScope? integer
--- @param timeToLive? integer
local function osync_create_context(context, func, contextScope, timeToLive)
    if sOSyncContextId then
        _print_debug_log("[ERROR] `create_context` cannot be called inside itself")
        return
    end

    -- Assign context ID
    local np = gNetworkPlayers[0]
    sOSyncContextId = osync_get_context_id(np, context)
    sOSyncObjects[sOSyncContextId] = {
        levelNum = np.currLevelNum,
        areaIndex = np.currAreaIndex,
        actNum = np.currActNum,
        contextScope = contextScope or sOSyncConfig.contextScope,
        timeToLive = timeToLive or -1,
        objects = {},
        timestamp = 0,
        requestSent = false,
    }

    -- Run the context function
    -- This is the only place where mods are allowed
    -- to call osync.spawn_sync_object()
    func()

    -- No object to spawn
    if #sOSyncObjects[sOSyncContextId].objects == 0 then
        sOSyncObjects[sOSyncContextId] = nil
    end

    sOSyncContextId = nil
end

--- @param behaviorId BehaviorId
--- @param modelId ModelExtendedId
--- @param x number
--- @param y number
--- @param z number
--- @param objSetupFunction? fun(o: Object)
local function osync_spawn_sync_object(behaviorId, modelId, x, y, z, objSetupFunction)
    if not sOSyncContextId then
        _print_debug_log("[ERROR] `spawn_sync_object` cannot be called outside of `osync_create_context`")
        return
    end

    -- Headless server doesn't spawn sync objects
    if OSYNC_IS_HEADLESS then
        return
    end

    -- Add sync object to context
    tinsert(sOSyncObjects[sOSyncContextId].objects, {
        behaviorId = behaviorId,
        modelId = modelId,
        x = x,
        y = y,
        z = z,
        objSetupFunction = objSetupFunction,
    })
end

----------------------
--- Sync behaviors ---
----------------------

--- @param behaviorId BehaviorId
--- @param parent Object
--- @return Object|nil
_G.obj_get_first_with_behavior_id_and_parent = function (behaviorId, parent)
    local obj = obj_get_first_with_behavior_id(behaviorId)
    while obj do
        if obj.activeFlags ~= 0 and obj.parentObj == parent then
            return obj
        end
        obj = obj_get_next_with_same_behavior_id(obj)
    end
    return nil
end

--- @param behaviorId BehaviorId
--- @param callbackFunc function
local function osync_register_sync_behavior(behaviorId, callbackFunc)
    hook_behavior(behaviorId, get_object_list_from_behavior(get_behavior_from_id(behaviorId)), false, nil, function (o)
        if o.oSyncID ~= 0 then
            callbackFunc(o)
        end
    end)
end

osync_register_sync_behavior(id_bhvWaterBombCannon, function (o)
    if not obj_get_first_with_behavior_id_and_parent(id_bhvCannonBarrelBubbles, o) then
        o.oAction = 0
    end
end)

osync_register_sync_behavior(id_bhvLllBowserPuzzle, function (o)
    if not obj_get_first_with_behavior_id_and_parent(id_bhvLllBowserPuzzlePiece, o) then
        o.oAction = 0
    end
end)

osync_register_sync_behavior(id_bhvCapSwitch, function (o)
    if not obj_get_first_with_behavior_id_and_parent(id_bhvCapSwitchBase, o) then
        o.oAction = 0
    end
end)

osync_register_sync_behavior(id_bhvExclamationBox, function (o)
    if o.oAction == 1 and not obj_get_first_with_behavior_id_and_parent(id_bhvRotatingExclamationMark, o) then
        o.oPrevAction = 0
    end
end)

osync_register_sync_behavior(id_bhvOpenableGrill, function (o)
    if not obj_get_first_with_behavior_id_and_parent(id_bhvOpenableCageDoor, o) then
        o.oAction = 0
    end
end)

osync_register_sync_behavior(id_bhvLllFloatingWoodBridge, function (o)
    if not obj_get_first_with_behavior_id_and_parent(id_bhvLllWoodPiece, o) then
        o.oAction = 0
    end
end)

osync_register_sync_behavior(id_bhvGiantPole, function (o)
    if not obj_get_first_with_behavior_id_and_parent(id_bhvYellowBall, o) then
        o.oPrevAction = o.oAction + 1
    end
end)

osync_register_sync_behavior(id_bhvWigglerHead, function (o)
    if not obj_get_first_with_behavior_id_and_parent(id_bhvWigglerBody, o) then
        o.oAction = 0
    end
end)

---------
-- lib --
---------

local _osync = {

    -- Constants
    CONTEXT_SCOPE_LEVEL = OSYNC_CONTEXT_SCOPE_LEVEL,
    CONTEXT_SCOPE_AREA = OSYNC_CONTEXT_SCOPE_AREA,
    CONTEXT_SCOPE_ACT = OSYNC_CONTEXT_SCOPE_ACT,

    -- Functions
    create_context = osync_create_context,
    spawn_sync_object = osync_spawn_sync_object,
    register_sync_behavior = osync_register_sync_behavior,

    -- Config
    config = sOSyncConfig,
}

---@class osync
---@field CONTEXT_SCOPE_LEVEL integer Context is removed when changing level.
---@field CONTEXT_SCOPE_AREA integer Context is removed when changing area.
---@field CONTEXT_SCOPE_ACT integer Context is removed when changing act.
---@field create_context fun(context: string, func: fun(), contextScope?: integer, timeToLive?: integer)
---@field spawn_sync_object fun(behaviorId: BehaviorId, modelId: ModelExtendedId, x: number, y: number, z: number, objSetupFunction?: fun(o: Object))
---@field register_sync_behavior fun(behaviorId: BehaviorId, callbackFunc: function)
---@field config OSyncConfig
local osync = setmetatable({}, {
    __index = _osync,
    __newindex = function () end,
    __metatable = false
})

return osync
