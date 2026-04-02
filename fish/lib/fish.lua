--[[

    File Share, aka FiSh 🐟

    filename: fish.lua
    version: v2.0
    author: PeachyPeach
    required: sm64coopdx v1.4 or later

    A small library to share ModFS files over the network.

    <!> Important note <!>
    This library is using HOOK_ON_PACKET_BYTESTRING_RECEIVE!
    Packets starting with magic PACKET_MAGIC (4 bytes, "<I4") are
    handled by this library and should be ignored by other hooks.

--]]

---------------
-- constants --
---------------

local PACKET_MAGIC              = 0x46695368

local PACKET_TYPE_FILE_HEADER   = 1
local PACKET_TYPE_FILE_PART     = 2
local PACKET_TYPE_ACK           = 3

local MAX_PACKET_SIZE           = (PACKET_LENGTH - 25)
local MAX_FILE_PART_SIZE        = (MAX_PACKET_SIZE - 32)
local MAX_ACKS_PER_PACKET       = math.floor((MAX_PACKET_SIZE - 32) / 8)

------------
-- config --
------------

--- @alias 🐟ConfigName
--- | "MAX_FILE_SIZE"
--- | "MAX_FILES_PER_PLAYER"
--- | "MAX_PACKETS_PER_PLAYER"
--- | "MAX_PACKETS_PER_FRAME"
--- | "TIMEOUT_FRAMES"
--- | "MAX_RETRIES"
--- | "DEBUG"

--- @class 🐟Config
--- @field MAX_FILE_SIZE integer
--- @field MAX_FILES_PER_PLAYER integer
--- @field MAX_PACKETS_PER_PLAYER integer
--- @field MAX_PACKETS_PER_FRAME integer 
--- @field TIMEOUT_FRAMES integer
--- @field MAX_RETRIES integer
--- @field DEBUG boolean

--- @type 🐟Config
local DEFAULT_CONFIG       = {
    MAX_FILE_SIZE          = 0x100000, -- 1MB
    MAX_FILES_PER_PLAYER   = 10,
    MAX_PACKETS_PER_PLAYER = 500,
    MAX_PACKETS_PER_FRAME  = 50,
    TIMEOUT_FRAMES         = 60, -- 2 seconds
    MAX_RETRIES            = 3,
    DEBUG                  = false,
}

--- @type 🐟Config
local sConfig              = {
    MAX_FILE_SIZE          = DEFAULT_CONFIG.MAX_FILE_SIZE,
    MAX_FILES_PER_PLAYER   = DEFAULT_CONFIG.MAX_FILES_PER_PLAYER,
    MAX_PACKETS_PER_PLAYER = DEFAULT_CONFIG.MAX_PACKETS_PER_PLAYER,
    MAX_PACKETS_PER_FRAME  = DEFAULT_CONFIG.MAX_PACKETS_PER_FRAME,
    TIMEOUT_FRAMES         = DEFAULT_CONFIG.TIMEOUT_FRAMES,
    MAX_RETRIES            = DEFAULT_CONFIG.MAX_RETRIES,
    DEBUG                  = DEFAULT_CONFIG.DEBUG,
}

--- @param name 🐟ConfigName
--- @return boolean|integer
local function config_get(name)
    return sConfig[name]
end

--- @param name 🐟ConfigName
--- @param value boolean|integer|nil
local function config_set(name, value)
    if sConfig[name] ~= nil then
        if value ~= nil then
            sConfig[name] = value
        else
            sConfig[name] = DEFAULT_CONFIG[name]
        end
    end
end

-----------
-- debug --
-----------

--- @param msg string
local function log_message(msg)
    if sConfig.DEBUG then
        local dt = get_date_and_time()
        print(string.format(
            "🐟 [%04d-%02d-%02d %02d:%02d:%02d] ",
            dt.year + 1900,
            dt.month + 1,
            dt.day,
            dt.hour,
            dt.minute,
            dt.second
        ) .. msg)
    end
end

--- @param fmt string
local function log_info(fmt, ...)
    log_message(string.format(fmt, ...))
end

--- @param fmt string
local function log_warning(fmt, ...)
    log_message("(Warning) " .. string.format(fmt, ...))
end

--- @param fmt string
local function log_error(fmt, ...)
    log_message("<<ERROR>> " .. string.format(fmt, ...))
end

----------------------
-- input validation --
----------------------

--- @param value any
--- @param expectedType string
--- @return boolean
local function check_type(value, expectedType)
    if expectedType == "integer" then
        return type(value) == "integer" or (type(value) == "number" and math.floor(value) == value)
    end
    return type(value) == expectedType
end

--- @param func string
--- @param inputName string
--- @param inputValue any
--- @param expectedType string
--- @param optional boolean
--- @return boolean
local function validate_input(func, inputName, inputValue, expectedType, optional)
    if optional and type(inputValue) == "nil" then
        return true
    end
    if not check_type(inputValue, expectedType) then
        log_error("%s: Invalid type for input `%s`: %s (should be %s)", func, inputName, type(inputValue), expectedType)
        return false
    end
    return true
end

--- @param func string
--- @param inputs table
--- @return boolean
local function validate_inputs(func, inputs)
    for _, input in ipairs(inputs) do
        if not validate_input(func, input.name, input.value, input.type, input.optional) then
            return false
        end
    end
    return true
end

-------------
-- packets --
-------------

--- @class 🐟Packet_FileHeader
--- @field type integer
--- @field uid integer
--- @field sender integer -- global index
--- @field fileUid integer
--- @field modPath string
--- @field filename string
--- @field annotation string
--- @field fileSize integer
--- @field numParts integer

local PACKET_TYPE_FILE_HEADER_STRUCTURE = {
    { name = "uid",        fmt = "<I8" },
    { name = "sender",     fmt = "<I1" },
    { name = "fileUid",    fmt = "<I8" },
    { name = "modPath",    fmt = "<s"  },
    { name = "filename",   fmt = "<s"  },
    { name = "annotation", fmt = "<s"  },
    { name = "fileSize",   fmt = "<I4" },
    { name = "numParts",   fmt = "<I2" },
}

--- @class 🐟Packet_FilePart
--- @field type integer
--- @field uid integer
--- @field sender integer -- global index
--- @field fileUid integer
--- @field index integer
--- @field length integer
--- @field data string

local PACKET_TYPE_FILE_PART_STRUCTURE = {
    { name = "uid",     fmt = "<I8" },
    { name = "sender",  fmt = "<I1" },
    { name = "fileUid", fmt = "<I8" },
    { name = "index",   fmt = "<I2" },
    { name = "length",  fmt = "<I4" },
    { name = "data",    fmt = "RAW" },
}

--- @class 🐟Packet_Ack
--- @field type integer
--- @field uid integer
--- @field sender integer -- global index
--- @field numPackets integer
--- @field packetUids table<integer>

local PACKET_TYPE_ACK_STRUCTURE = {
    { name = "uid",        fmt = "<I8" },
    { name = "sender",     fmt = "<I1" },
    { name = "numPackets", fmt = "<I2" },
    { name = "packetUids", fmt = "<I8", count = function (packet) return packet.numPackets end },
}

local PACKET_STRUCTURES = {
    [PACKET_TYPE_FILE_HEADER] = PACKET_TYPE_FILE_HEADER_STRUCTURE,
    [PACKET_TYPE_FILE_PART] = PACKET_TYPE_FILE_PART_STRUCTURE,
    [PACKET_TYPE_ACK] = PACKET_TYPE_ACK_STRUCTURE,
}

--- @param data string
--- @param offset integer
--- @param type integer
--- @return 🐟Packet_FileHeader|🐟Packet_FilePart|🐟Packet_Ack|nil
local function read_packet_from_type(data, offset, type)
    local structure = PACKET_STRUCTURES[type]
    if not structure then
        return nil
    end

    local packet = { type = type }
    for _, field in ipairs(structure) do
        local name = field.name
        local fmt = field.fmt
        local count = nil
        if field.count ~= nil then
            count = field.count(packet)
            packet[name] = {}
        end
        for _ = 1, (count or 1) do
            local value
            if fmt == "RAW" then
                value, offset = string.sub(data, offset), #data
            else
                value, offset = string.unpack(fmt, data, offset)
            end
            if count then
                packet[name][#packet[name]+1] = value
            else
                packet[name] = value
            end
        end
    end
    return packet
end

--- @param data string
--- @return 🐟Packet_FileHeader|🐟Packet_FilePart|🐟Packet_Ack|nil
local function read_packet(data)
    local offset = 1

    -- Check magic
    local magic
    magic, offset = string.unpack("<I4", data, offset)
    if magic ~= PACKET_MAGIC then
        return nil
    end

    -- Check type
    local type
    type, offset = string.unpack("<I1", data, offset)
    return read_packet_from_type(data, offset, type)
end

--- @param packet table<string, any>
--- @return string|nil
local function packet_to_bytestring(packet, type)
    local structure = PACKET_STRUCTURES[type]
    if not structure then
        return nil
    end

    local data = ''
        .. string.pack("<I4", PACKET_MAGIC)
        .. string.pack("<I1", type)

    for _, field in ipairs(structure) do
        local name = field.name
        local fmt = field.fmt
        local count = nil
        if field.count ~= nil then
            count = field.count(packet)
        end
        for i = 1, (count or 1) do
            local value
            if count then
                value = packet[name][i]
            else
                value = packet[name]
            end
            if fmt == "RAW" then
                data = data .. value
            else
                data = data .. string.pack(fmt, value)
            end
        end
    end
    return data
end

local sPacketCounter = 0
--- @return integer
local function get_new_packet_uid()
    sPacketCounter = sPacketCounter + 1
    return (sPacketCounter * MAX_PLAYERS) + network_global_index_from_local(0)
end

-----------
-- files --
-----------

--- @class 🐟FileObject
--- @field sender integer -- global index
--- @field fileUid integer
--- @field modPath string
--- @field filename string
--- @field annotation string
--- @field fileSize integer
--- @field numParts integer
--- @field fileParts table<string>

--- @type table<integer, 🐟FileObject>
local sFileObjects = {}

local sFileCounter = 0
--- @return integer
local function get_new_file_uid()
    sFileCounter = sFileCounter + 1
    return (sFileCounter * MAX_PLAYERS) + network_global_index_from_local(0)
end

--- @class 🐟File
--- @field sender integer -- global index
--- @field modPath string
--- @field filename string
--- @field annotation string
--- @field size integer
--- @field data string
--- @field completion number

--- @param file 🐟FileObject
--- @return 🐟File
local function get_pending_file(file)
    local completion = 0
    for _, filePart in pairs(file.fileParts) do
        completion = completion + #filePart
    end
    completion = completion / file.fileSize

    return {
        sender = file.sender,
        modPath = file.modPath,
        filename = file.filename,
        annotation = file.annotation,
        size = file.fileSize,
        data = nil,
        completion = completion,
    }
end

--- @param file 🐟FileObject
--- @return 🐟File
local function get_completed_file(file)
    local data = ""
    for _, filePart in ipairs(file.fileParts) do
        data = data .. filePart
    end

    return {
        sender = file.sender,
        modPath = file.modPath,
        filename = file.filename,
        annotation = file.annotation,
        size = file.fileSize,
        data = data,
        completion = 1.0,
    }
end

--- @param file 🐟File A file received from the `receive` function.
--- @param destFilename? string An optional destination filename. If not provided, file will be saved to path `<file.modPath>/<file.filename>`.
--- @return boolean
--- Saves file to ModFS.
local function save(file, destFilename)
    if not validate_inputs("save", {
        { name = "file", value = file, type = "table" },
        { name = "destFilename", value = destFilename, type = "string", optional = true },
    }) then return false end

    -- check file data
    if not file.data then
        log_error("save: Cannot save an empty file: %s/%s", file.modPath, file.filename)
        return false
    end

    -- check modfs existence
    local modFs = mod_fs_get() or mod_fs_create()
    if not modFs then
        log_error("save: Unable to open ModFS for file: %s/%s", file.modPath, file.filename)
        return false
    end

    -- check file creation
    destFilename = destFilename or string.format("%s/%s", file.modPath, file.filename)
    if modFs:get_file(destFilename) then
        modFs:delete_file(destFilename)
    end
    local modFsFile = modFs:create_file(destFilename, false)
    if not modFsFile then
        log_error(string.format("save: Unable to create file: %s", destFilename))
        return false
    end

    -- try to write data
    if not modFsFile:write_bytes(file.data) then
        log_error(string.format("save: Unable to write to file: %s", destFilename))
        return false
    end

    return true
end

----------
-- acks --
----------

--- @type table<integer, table<integer>>
local sAcksPerPlayer = {}

--- @param playerIndex integer
--- @param packetUid integer
local function queue_ack(playerIndex, packetUid)
    if not sAcksPerPlayer[playerIndex] then
        sAcksPerPlayer[playerIndex] = {}
    end

    sAcksPerPlayer[playerIndex][#sAcksPerPlayer[playerIndex]+1] = packetUid
end

local function send_acks()
    local sender = network_global_index_from_local(0)
    for playerIndex = 1, MAX_PLAYERS - 1 do
        local packetUids = sAcksPerPlayer[playerIndex]
        if gNetworkPlayers[playerIndex].connected and packetUids and #packetUids > 0 then
            local indexStart = 1
            while true do
                local indexEnd = math.min(indexStart + MAX_ACKS_PER_PACKET - 1, #packetUids)
                local numPackets = indexEnd - indexStart + 1
                local uid = get_new_packet_uid()

                local data = packet_to_bytestring({
                    uid = uid,
                    sender = sender,
                    numPackets = numPackets,
                    packetUids = { table.unpack(packetUids, indexStart, indexEnd) },
                }, PACKET_TYPE_ACK)

                -- send ack
                -- this is the only packet that's sent immediately instead of being queued
                if data then
                    network_send_bytestring_to(playerIndex, true, data)
                    log_info("send_acks: Sending ack to player %d for packets: %d", playerIndex, numPackets)
                end

                if indexEnd == #packetUids then
                    break
                end

                indexStart = indexEnd + 1
            end
        end
    end
    sAcksPerPlayer = {}
end

hook_event(HOOK_UPDATE, send_acks)

------------
-- queues --
------------

local PACKET_PRIORITY = {
    PACKET_TYPE_FILE_PART,
    PACKET_TYPE_FILE_HEADER,
}

local PACKET_TYPE_NAMES = {
    [PACKET_TYPE_FILE_HEADER] = "PACKET_TYPE_FILE_HEADER",
    [PACKET_TYPE_FILE_PART]   = "PACKET_TYPE_FILE_PART",
}

--- Table of uid -> packet info
--- @type table<integer, 🐟PacketInfo>
local sPackets = {}

--- List of packet uids by order of insertion
--- @type table<integer>
local sPacketQueue = {}

--- @class 🐟PacketInfo
--- @field type integer
--- @field uid integer
--- @field toLocalIndex integer
--- @field fileUid integer
--- @field data string
--- @field numRetries integer
--- @field lastTick integer

--- @param type integer
--- @param uid integer
--- @param toLocalIndex integer
--- @param fileUid integer
--- @param data string|nil
local function queue_packet(type, uid, toLocalIndex, fileUid, data)
    if not data then
        log_error("queue_packet: Received nil data")
        return
    end

    local packetInfo = {
        type = type,
        uid = uid,
        toLocalIndex = toLocalIndex,
        fileUid = fileUid,
        data = data,
        numRetries = -1,
        lastTick = -sConfig.TIMEOUT_FRAMES,
    }

    sPackets[uid] = packetInfo
    sPacketQueue[#sPacketQueue+1] = uid
end

--- @param predicate fun(info: 🐟PacketInfo): boolean
local function delete_packets_with_predicate(predicate)
    local index = 1
    while index <= #sPacketQueue do
        local uid = sPacketQueue[index]
        local info = sPackets[uid]
        if not info or predicate(info) then
            table.remove(sPacketQueue, index)
            sPackets[uid] = nil
        else
            index = index + 1
        end
    end
end

--- @param playerIndex integer
local function delete_packets_for_player(playerIndex)
    delete_packets_with_predicate(function (info) return info.toLocalIndex == playerIndex end)
end

--- @param fileUid integer
local function delete_packets_for_file_uid(fileUid)
    delete_packets_with_predicate(function (info) return info.fileUid == fileUid end)
end

--- @param state table
--- @param packetType integer
--- @return boolean
local function send_packet(state, packetType)
    local uid = sPacketQueue[state.index]
    local info = sPackets[uid]

    -- inexistent packet
    if not info then
        table.remove(sPacketQueue, state.index)
        return true
    end

    -- not the right packet type
    if info.type ~= packetType then
        state.index = state.index + 1
        return true
    end

    -- too much packets for this frame
    if sConfig.MAX_PACKETS_PER_FRAME > 0 and state.packetsSent >= sConfig.MAX_PACKETS_PER_FRAME then
        return false
    end

    -- check files per player
    if sConfig.MAX_FILES_PER_PLAYER > 0 then
        if not state.filesPerPlayer[info.toLocalIndex] then
            state.filesPerPlayer[info.toLocalIndex] = {
                numFiles = 0,
                fileUids = {}
            }
        end
        local filesPerPlayer = state.filesPerPlayer[info.toLocalIndex]

        -- too much files for this player
        local numFiles = filesPerPlayer.numFiles
        if not filesPerPlayer.fileUids[info.fileUid] and numFiles >= sConfig.MAX_FILES_PER_PLAYER then
            state.index = state.index + 1
            return true
        end

        -- update filesPerPlayer
        if not filesPerPlayer.fileUids[info.fileUid] then
            filesPerPlayer.fileUids[info.fileUid] = true
            filesPerPlayer.numFiles = numFiles + 1
        end
    end

    -- check packets per player
    if sConfig.MAX_PACKETS_PER_PLAYER > 0 then

        -- too much packets for this player
        local numPackets = state.packetsPerPlayer[info.toLocalIndex] or 0
        if numPackets >= sConfig.MAX_PACKETS_PER_PLAYER then
            state.index = state.index + 1
            return true
        end

        -- update packetsPerPlayer
        state.packetsPerPlayer[info.toLocalIndex] = numPackets + 1
    end

    -- check timeout
    if state.currentTick - info.lastTick >= sConfig.TIMEOUT_FRAMES then

        -- too much retries, delete all packets for the same file uid
        if info.numRetries >= sConfig.MAX_RETRIES then
            delete_packets_for_file_uid(info.fileUid)
            -- restart the loop
            state.packetsPerPlayer = {}
            state.index = 1
            log_warning("send_packet: No retries left for %s packet to player %d for file uid: %d - File has been canceled", PACKET_TYPE_NAMES[info.type], info.toLocalIndex, info.fileUid)
            return true
        end

        -- send packet (again)
        network_send_bytestring_to(info.toLocalIndex, true, info.data)
        info.numRetries = info.numRetries + 1
        info.lastTick = state.currentTick
        state.packetsSent = state.packetsSent + 1
        log_info("send_packet: Sending %s packet to player %d for file uid: %d (num retries left: %d)", PACKET_TYPE_NAMES[info.type], info.toLocalIndex, info.fileUid, sConfig.MAX_RETRIES - info.numRetries)
    end

    state.index = state.index + 1
    return true
end

local function send_packets()
    local state = {
        index = 1,
        currentTick = get_global_timer(),
        packetsSent = 0,
        filesPerPlayer = {},
        packetsPerPlayer = {}
    }

    -- remove packets to disconnected players
    for playerIndex = 1, MAX_PLAYERS - 1 do
        if not gNetworkPlayers[playerIndex].connected then
            delete_packets_for_player(playerIndex)
        end
    end

    -- send packets
    for _, packetType in ipairs(PACKET_PRIORITY) do
        state.index = 1
        while state.index <= #sPacketQueue and send_packet(state, packetType) do end
    end

    if state.packetsSent > 0 then
        log_info("send_packets: Sent packets this frame: %d", state.packetsSent)
    end
end

hook_event(HOOK_UPDATE, send_packets)

----------
-- send --
----------

--- @param toLocalIndex integer
--- @param modPath string
--- @param filename string
--- @param annotation? string
--- @return boolean
local function send_file_header(toLocalIndex, modPath, filename, annotation)

    -- check local index
    if toLocalIndex <= 0 or toLocalIndex >= MAX_PLAYERS then
        log_error("send_file_header: Invalid local index: %d", toLocalIndex)
        return false
    end

    -- check player connected
    if not gNetworkPlayers[toLocalIndex].connected then
        log_error("send_file_header: Local index is not connected: %d", toLocalIndex)
        return false
    end

    -- check modfs existence
    local modFs = mod_fs_get(modPath)
    if not modFs then
        log_error("send_file_header: ModFS not found: %s", modPath)
        return false
    end

    -- check file existence
    local file = modFs:get_file(filename)
    if not file then
        log_error("send_file_header: File not found: %s/%s", modPath, filename)
        return false
    end

    -- check file size
    if sConfig.MAX_FILE_SIZE > 0 and file.size > sConfig.MAX_FILE_SIZE then
        log_error("send_file_header: File too big (%d > %d): %s/%s", file.size, sConfig.MAX_FILE_SIZE, modPath, filename)
        return false
    end

    -- adjust annotation size
    local maxAnnotationSize = MAX_PACKET_SIZE - #modPath - #filename - 64
    if annotation and #annotation > maxAnnotationSize then
        log_warning("send_file_header: Annotation too big (%d > %d): it will be truncated", #annotation, maxAnnotationSize)
        annotation = string.sub(annotation, 1, maxAnnotationSize - 1)
    end

    local numParts = math.ceil(file.size / MAX_FILE_PART_SIZE)
    local uid = get_new_packet_uid()
    local fileUid = get_new_file_uid()

    local data = packet_to_bytestring({
        uid = uid,
        sender = network_global_index_from_local(0),
        fileUid = fileUid,
        modPath = modPath,
        filename = filename,
        annotation = annotation or "",
        fileSize = file.size,
        numParts = numParts,
    }, PACKET_TYPE_FILE_HEADER)

    queue_packet(PACKET_TYPE_FILE_HEADER, uid, toLocalIndex, fileUid, data)
    log_info("send_file_header: Queueing file header packet to local index %d for file: %s/%s", toLocalIndex, modPath, filename)

    return true
end

--- @param toLocalIndex integer
--- @param fileUid integer
--- @param modPath string
--- @param filename string
--- @param fileSize integer
--- @param numParts integer
--- @return boolean
local function send_file_parts(toLocalIndex, fileUid, modPath, filename, fileSize, numParts)

    -- check local index
    if toLocalIndex <= 0 or toLocalIndex >= MAX_PLAYERS then
        log_error("send_file_parts: Invalid local index: %d", toLocalIndex)
        return false
    end

    -- check player connected
    if not gNetworkPlayers[toLocalIndex].connected then
        log_error("send_file_parts: Local index is not connected: %d", toLocalIndex)
        return false
    end

    -- check file uid validity
    if fileUid <= 0 then
        log_error("send_file_parts: Invalid file uid: %d", fileUid)
        return false
    end

    -- check modfs existence
    local modFs = mod_fs_get(modPath)
    if not modFs then
        log_error("send_file_parts: ModFS not found: %s", modPath)
        return false
    end

    -- check file existence
    local file = modFs:get_file(filename)
    if not file then
        log_error("send_file_parts: File not found: %s/%s", modPath, filename)
        return false
    end

    -- check matching file sizes
    if file.size ~= fileSize then
        log_error("send_file_parts: Mismatching file sizes: %d (should be %d)", file.size, fileSize)
        return false
    end

    -- check matching num parts
    local fileNumParts = math.ceil(fileSize / MAX_FILE_PART_SIZE)
    if fileNumParts ~= numParts then
        log_error("send_file_parts: Mismatching number of file parts: %d (should be %d)", fileNumParts, numParts)
        return false
    end

    for i = 1, numParts do
        local uid = get_new_packet_uid()
        local partStart = MAX_FILE_PART_SIZE * (i - 1)
        local partLength = math.min(MAX_FILE_PART_SIZE, fileSize - partStart)
        file:seek(partStart, FILE_SEEK_SET)

        local data = packet_to_bytestring({
            uid = uid,
            sender = network_global_index_from_local(0),
            fileUid = fileUid,
            index = i,
            length = partLength,
            data = file:read_bytes(partLength),
        }, PACKET_TYPE_FILE_PART)

        queue_packet(PACKET_TYPE_FILE_PART, uid, toLocalIndex, fileUid, data)
    end

    log_info("send_file_parts: Queueing %d file part packets to local index %d for file: %s/%s", numParts, toLocalIndex, modPath, filename)

    return true
end

--- @param toLocalIndex integer Local index of the player to send the file to.
--- @param modPath string Name of the ModFS file.
--- @param filename string Name of the file to send.
--- @param annotation? string Annotation to help identify the send request. Optional.
--- @return boolean
--- Sends a file to a remote player. Returns `true` on success.
local function send(toLocalIndex, modPath, filename, annotation)
    if not validate_inputs("send", {
        { name = "toLocalIndex", value = toLocalIndex, type = "integer" },
        { name = "modPath", value = modPath, type = "string" },
        { name = "filename", value = filename, type = "string" },
        { name = "annotation", value = annotation, type = "string", optional = true },
    }) then return false end

    if toLocalIndex ~= 0 then
        return send_file_header(toLocalIndex, modPath, filename, annotation)
    end

    -- broadcast
    local result = false
    for playerIndex = 1, MAX_PLAYERS - 1 do
        if gNetworkPlayers[playerIndex].connected then
            result = send_file_header(playerIndex, modPath, filename, annotation) or result
        end
    end
    return result
end

-------------
-- receive --
-------------

--- @return table<🐟File>, table<🐟File>
--- Receives pending and completed files.
local function receive()
    local pendingFiles = {}
    local completedFiles = {}
    local fileUidsToRemove = {}

    for fileUid, file in pairs(sFileObjects) do
        if #file.fileParts == file.numParts then
            completedFiles[#completedFiles+1] = get_completed_file(file)
            fileUidsToRemove[#fileUidsToRemove+1] = fileUid
        else
            pendingFiles[#pendingFiles+1] = get_pending_file(file)
        end
    end

    -- remove completed files
    for _, fileUid in ipairs(fileUidsToRemove) do
        sFileObjects[fileUid] = nil
    end

    return pendingFiles, completedFiles
end

--- @param packet 🐟Packet_FileHeader
local function on_packet_file_header(packet)

    -- check uid validity
    if packet.uid <= 0 then
        log_error("on_packet_file_header: Invalid packet uid: %d", packet.uid)
        return
    end

    -- check sender
    local playerIndex = network_local_index_from_global(packet.sender)
    if playerIndex <= 0 or playerIndex >= MAX_PLAYERS then
        log_error("on_packet_file_header: Invalid player index: %d", playerIndex)
        return
    end
    if not gNetworkPlayers[playerIndex].connected then
        log_error("on_packet_file_header: Player is not connected: %d", playerIndex)
        return
    end

    -- check file uid validity
    if packet.fileUid <= 0 then
        log_error("on_packet_file_header: Invalid file uid: %d", packet.fileUid)
        return
    end

    -- ignore if file uid already exists
    if sFileObjects[packet.fileUid] then
        log_warning("on_packet_file_header: File uid already exists: %d", packet.fileUid)
        queue_ack(playerIndex, packet.uid) -- send ack again in case sender didn't receive it
        return
    end

    -- register new file
    sFileObjects[packet.fileUid] = {
        sender = packet.sender,
        fileUid = packet.fileUid,
        modPath = packet.modPath,
        filename = packet.filename,
        annotation = packet.annotation,
        fileSize = packet.fileSize,
        numParts = packet.numParts,
        fileParts = {}
    }

    -- send ack
    queue_ack(playerIndex, packet.uid)
end

--- @param packet 🐟Packet_FilePart
local function on_packet_file_part(packet)

    -- check uid validity
    if packet.uid <= 0 then
        log_error("on_packet_file_part: Invalid packet uid: %d", packet.uid)
        return
    end

    -- check sender
    local playerIndex = network_local_index_from_global(packet.sender)
    if playerIndex <= 0 or playerIndex >= MAX_PLAYERS then
        log_error("on_packet_file_part: Invalid player index: %d", playerIndex)
        return
    end
    if not gNetworkPlayers[playerIndex].connected then
        log_error("on_packet_file_part: Player is not connected: %d", playerIndex)
        return
    end

    -- check file uid validity
    if packet.fileUid <= 0 then
        log_error("on_packet_file_part: Invalid file uid: %d", packet.fileUid)
        return
    end

    -- check if file exists
    -- as there is no way for a player to receive file parts before the file header,
    -- it would only mean that the file has already been completed
    local file = sFileObjects[packet.fileUid]
    if not file then
        log_warning("on_packet_file_part: File already completed for file uid: %d", packet.fileUid)
        queue_ack(playerIndex, packet.uid) -- send ack to notify sender the file is already received
        return
    end

    -- check file part index validity
    if packet.index <= 0 or packet.index > file.numParts then
        log_error("on_packet_file_part: Invalid file part index: %d (should be between 1 and %d included)", packet.index, file.numParts)
        return
    end

    -- check matching file part lengths
    if #packet.data ~= packet.length then
        log_error("on_packet_file_part: Mismatching file part lengths: %d (should be %d)", #packet.data, packet.length)
        return
    end

    -- ignore if file part has already been received
    if file.fileParts[packet.index] then
        log_warning("on_packet_file_part: File part %d has already been received for file uid: %d", packet.index, packet.fileUid)
        queue_ack(playerIndex, packet.uid) -- send ack again in case sender didn't receive it
        return
    end

    -- fill file part
    file.fileParts[packet.index] = packet.data

    -- send ack
    queue_ack(playerIndex, packet.uid)
end

--- @param packet 🐟Packet_Ack
local function on_packet_ack(packet)

    -- check uid validity
    if packet.uid <= 0 then
        log_error("on_packet_ack: Invalid packet uid: %d", packet.uid)
        return
    end

    -- check sender
    local playerIndex = network_local_index_from_global(packet.sender)
    if playerIndex <= 0 or playerIndex >= MAX_PLAYERS then
        log_error("on_packet_ack: Invalid player index: %d", playerIndex)
        return
    end
    if not gNetworkPlayers[playerIndex].connected then
        log_error("on_packet_ack: Player is not connected: %d", playerIndex)
        return
    end

    -- check num packets
    if packet.numPackets ~= #packet.packetUids then
        log_error("on_packet_ack: Mismatching number of packets: %d (should be %d)", #packet.packetUids, packet.numPackets)
        return
    end

    -- acknowledge and remove packets
    for _, uid in ipairs(packet.packetUids) do
        local info = sPackets[uid]
        if info then

            -- if the packet was PACKET_TYPE_FILE_HEADER, send the file parts
            if info.type == PACKET_TYPE_FILE_HEADER then

                --- @type 🐟Packet_FileHeader
                local fileHeaderPacket = read_packet(info.data)
                if fileHeaderPacket then
                    log_info("on_packet_ack: Received ack for PACKET_TYPE_FILE_HEADER")
                    send_file_parts(
                        playerIndex,
                        fileHeaderPacket.fileUid,
                        fileHeaderPacket.modPath,
                        fileHeaderPacket.filename,
                        fileHeaderPacket.fileSize,
                        fileHeaderPacket.numParts
                    )
                else
                    log_error("on_packet_ack: Unable to retrieve data from PACKET_TYPE_FILE_HEADER packet")
                end
            end

            -- remove packet
            -- don't need to remove the packet from the queue, the update will do it for us
            sPackets[uid] = nil
        end
    end
end

local PACKET_CALLBACKS = {
    [PACKET_TYPE_FILE_HEADER] = on_packet_file_header,
    [PACKET_TYPE_FILE_PART] = on_packet_file_part,
    [PACKET_TYPE_ACK] = on_packet_ack,
}

--- @param data string
local function on_packet_bytestring_receive(data)
    local packet = read_packet(data)
    if not packet then
        return
    end

    local callback = PACKET_CALLBACKS[packet.type]
    if callback then
        callback(packet)
    end
end

hook_event(HOOK_ON_PACKET_BYTESTRING_RECEIVE, on_packet_bytestring_receive)

---------
-- lib --
---------

local _fish = {

    -- magic
    PACKET_MAGIC = PACKET_MAGIC,

    -- default values
    MAX_FILE_SIZE          = DEFAULT_CONFIG.MAX_FILE_SIZE,
    MAX_FILES_PER_PLAYER   = DEFAULT_CONFIG.MAX_FILES_PER_PLAYER,
    MAX_PACKETS_PER_PLAYER = DEFAULT_CONFIG.MAX_PACKETS_PER_PLAYER,
    MAX_PACKETS_PER_FRAME  = DEFAULT_CONFIG.MAX_PACKETS_PER_FRAME,
    TIMEOUT_FRAMES         = DEFAULT_CONFIG.TIMEOUT_FRAMES,
    MAX_RETRIES            = DEFAULT_CONFIG.MAX_RETRIES,

    -- functions
    send    = function (toLocalIndex, modPath, filename, annotation) return send(toLocalIndex, modPath, filename, annotation) end,
    receive = function () return receive() end,
    save    = function (file, destFilename) return save(file, destFilename) end,

    -- config
    config  = {

        -- names
        MAX_FILE_SIZE          = "MAX_FILE_SIZE",
        MAX_FILES_PER_PLAYER   = "MAX_FILES_PER_PLAYER",
        MAX_PACKETS_PER_PLAYER = "MAX_PACKETS_PER_PLAYER",
        MAX_PACKETS_PER_FRAME  = "MAX_PACKETS_PER_FRAME",
        TIMEOUT_FRAMES         = "TIMEOUT_FRAMES",
        MAX_RETRIES            = "MAX_RETRIES",
        DEBUG                  = "DEBUG",

        -- functions
        get = function (name) return config_get(name) end,
        set = function (name, value) return config_set(name, value) end,
    }
}

--- @class config
--- @field get fun(name: 🐟ConfigName): boolean|integer
--- @field set fun(name: 🐟ConfigName, value: boolean|integer|nil)
--- @field MAX_FILE_SIZE 🐟ConfigName
--- @field MAX_FILES_PER_PLAYER 🐟ConfigName
--- @field MAX_PACKETS_PER_PLAYER 🐟ConfigName
--- @field MAX_PACKETS_PER_FRAME 🐟ConfigName
--- @field TIMEOUT_FRAMES 🐟ConfigName
--- @field MAX_RETRIES 🐟ConfigName
--- @field DEBUG 🐟ConfigName

--- @class fish
--- @field PACKET_MAGIC integer
--- @field MAX_FILE_SIZE integer
--- @field MAX_FILES_PER_PLAYER integer
--- @field MAX_PACKETS_PER_PLAYER integer
--- @field MAX_PACKETS_PER_FRAME integer
--- @field TIMEOUT_FRAMES integer
--- @field MAX_RETRIES integer
--- @field send fun(toLocalIndex: integer, modPath: string, filename: string, annotation: string?): boolean
--- @field receive fun(): table<integer, 🐟File>, table<integer, 🐟File>
--- @field save fun(file: 🐟File, destFilename?: string): boolean
--- @field config config
local fish      = setmetatable({}, {
    __index     = _fish,
    __newindex  = function () end,
    __metatable = false
})

return fish
