--[[

    File Share

    filename: fileshare.lua
    version: v1.0
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

local PACKET_MAGIC              = 0xF5465321

local PACKET_TYPE_SEND_FILE     = 1
local PACKET_TYPE_RETRY_FILE    = 2
local PACKET_TYPE_REQUEST_RETRY = 3

local FILE_STATE_PENDING        = 0
local FILE_STATE_COMPLETED      = 1
local FILE_STATE_CANCELED       = 2

local MAX_FILE_SIZE             = 0x100000 -- 1MB
local MAX_FILE_PART_SIZE        = (PACKET_LENGTH - 500)
local MAX_REQUESTS_PER_FRAME    = 10
local TIMEOUT_FRAMES            = 30
local MAX_RETRIES               = 3
local VERBOSE                   = false

------------
-- config --
------------

--- @class FS_Config
--- @field MAX_FILE_SIZE integer
--- @field MAX_REQUESTS_PER_FRAME integer 
--- @field TIMEOUT_FRAMES integer
--- @field MAX_RETRIES integer
--- @field VERBOSE boolean

--- @type FS_Config
local sConfig = {
    MAX_FILE_SIZE = MAX_FILE_SIZE,
    MAX_REQUESTS_PER_FRAME = MAX_REQUESTS_PER_FRAME,
    TIMEOUT_FRAMES = TIMEOUT_FRAMES,
    MAX_RETRIES = MAX_RETRIES,
    VERBOSE = VERBOSE,
}

--- @type FS_Config
local sConfigDefault = {
    MAX_FILE_SIZE = MAX_FILE_SIZE,
    MAX_REQUESTS_PER_FRAME = MAX_REQUESTS_PER_FRAME,
    TIMEOUT_FRAMES = TIMEOUT_FRAMES,
    MAX_RETRIES = MAX_RETRIES,
    VERBOSE = VERBOSE,
}

local function config_get(name)
    return sConfig[name]
end

local function config_set(name, value)
    if sConfig[name] ~= nil then
        if value ~= nil then
            sConfig[name] = value
        else
            sConfig[name] = sConfigDefault[name]
        end
    end
end

-----------
-- utils --
-----------

--- @return string
local function get_date_and_time_string()
    local dt = get_date_and_time()
    return string.format(
        "[%04d-%02d-%02d %02d:%02d:%02d]",
        dt.year + 1900,
        dt.month + 1,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second
    )
end

--- @param msg string
local function log_message(msg)
    if sConfig.VERBOSE then
        print(get_date_and_time_string() .. " " .. msg)
    end
end

--- @param msg string
local function log_error(msg)
    if sConfig.VERBOSE then
        print(get_date_and_time_string() .. " [[ERROR]] " .. msg)
    end
end

--- @param t table
--- @param n integer
--- @return table
local function removeN(t, n)
    local t2 = {}
    for i = n + 1, #t do
        t2[i - n] = t[i]
    end
    return t2
end

--------------
-- requests --
--------------

--- @class FS_Request
--- @field toLocalIndex integer
--- @field packet string
local FS_Request = {}

--- @type table<integer, FS_Request>
local sRequests = {}

--- @param toLocalIndex integer
--- @param packet string
--- @return FS_Request
function FS_Request.new(toLocalIndex, packet)
    return {
        toLocalIndex = toLocalIndex,
        packet = packet,
    }
end

local function handle_requests()
    for i = 1, #sRequests do
        local request = sRequests[i]
        if request.toLocalIndex == 0 then -- broadcast
            network_send_bytestring(true, request.packet)
        else
            network_send_bytestring_to(request.toLocalIndex, true, request.packet)
        end
        if i == sConfig.MAX_REQUESTS_PER_FRAME then
            sRequests = removeN(sRequests, sConfig.MAX_REQUESTS_PER_FRAME)
            return
        end
    end
    sRequests = {}
end

hook_event(HOOK_UPDATE, handle_requests)

-----------
-- files --
-----------

--- @class FS_PendingFile
--- @field modPath string
--- @field filename string
--- @field size integer
--- @field numParts integer
--- @field sender integer
--- @field parts table<integer, string>
--- @field timestamp integer
--- @field lastTick integer
--- @field retries integer
--- @field state integer
local FS_PendingFile = {}

--- @type table<string, FS_PendingFile>
local sPendingFiles = {}

--- @param modPath string
--- @param filename string
--- @param size integer
--- @param numParts integer
--- @param sender integer
--- @param timestamp integer
--- @return FS_PendingFile
function FS_PendingFile.new(modPath, filename, size, numParts, sender, timestamp)
    return {
        modPath = modPath,
        filename = filename,
        size = size,
        numParts = numParts,
        sender = sender,
        parts = {},
        timestamp = timestamp,
        lastTick = get_global_timer(),
        retries = 0,
        state = FILE_STATE_PENDING,

        get_completion = FS_PendingFile.get_completion,
        get_data = FS_PendingFile.get_data,
    }
end

--- @param pending FS_PendingFile
--- @return number
function FS_PendingFile.get_completion(pending)
    local completed = 0
    for _, part in pairs(pending.parts) do
        completed = completed + #part
    end
    return completed / pending.size
end

--- @param pending FS_PendingFile
--- @return string
function FS_PendingFile.get_data(pending)
    local data = ''
    for _, part in ipairs(pending.parts) do
        data = data .. part
    end
    return data
end

--- @class FS_File
--- @field sender integer
--- @field modPath string
--- @field filename string
--- @field size number
--- @field completion number|nil
--- @field data string|nil
local FS_File = {}

--- @param sender integer
--- @param modPath string
--- @param filename string
--- @param size number
--- @param completion number|nil
--- @param data string|nil
--- @return FS_File
function FS_File.new(sender, modPath, filename, size, completion, data)
    return {
        sender = sender,
        modPath = modPath,
        filename = filename,
        size = size,
        completion = completion,
        data = data,
    }
end

------------
-- packet --
------------

--- @class FS_Packet
--- @field data string
--- @field offset integer
local FS_Packet = {}

--- @param packet string
--- @return FS_Packet
function FS_Packet.new(packet)
    return {
        data = packet,
        offset = 1,

        unpack = FS_Packet.unpack,
    }
end

--- @param p FS_Packet
--- @param fmt string
--- @return any
function FS_Packet.unpack(p, fmt)
    local value
    value, p.offset = string.unpack(fmt, p.data, p.offset)
    return value
end

----------
-- send --
----------

--- @param toLocalIndex integer Local index of the player to send the file to.
--- @param modPath string Name of the ModFS file.
--- @param filename string Name of the file to send.
--- @param partIndex? integer Part index of the file to send. Optional. If not provided, sends the whole file.
--- @param isRetry? boolean retry
--- @return boolean
--- Sends a file to a remote player. Returns `true` on success.
local function send(toLocalIndex, modPath, filename, partIndex, isRetry)
    if toLocalIndex < 0 or toLocalIndex >= MAX_PLAYERS then
        log_error(string.format("send: Invalid local index: %d", toLocalIndex))
        return false
    end

    local modFs = mod_fs_get(modPath)
    if not modFs then
        log_error(string.format("send: ModFS not found: %s", modPath))
        return false
    end

    local file = modFs:get_file(filename)
    if not file then
        log_error(string.format("send: File not found: %s/%s", modPath, filename))
        return false
    end

    if file.size > sConfig.MAX_FILE_SIZE then
        log_error(string.format("send: File too big (%d > %d): %s/%s", file.size, sConfig.MAX_FILE_SIZE, modPath, filename))
        return false
    end

    local timestamp = get_time()
    local globalIndex = network_global_index_from_local(0)
    local numParts = math.ceil(file.size / MAX_FILE_PART_SIZE)
    local minPart = partIndex and partIndex or 1
    local maxPart = partIndex and partIndex or numParts

    file:set_text_mode(false)
    file:seek((minPart - 1) * MAX_FILE_PART_SIZE, FILE_SEEK_SET)

    for i = minPart, maxPart do
        local length = math.min(MAX_FILE_PART_SIZE, file.size - file.offset)
        local bytes = file:read_bytes(length)
        local packet = ''
            .. string.pack("<I4", PACKET_MAGIC)
            .. string.pack("<B", isRetry and PACKET_TYPE_RETRY_FILE or PACKET_TYPE_SEND_FILE)
            .. string.pack("<I8", timestamp)
            .. string.pack("<B", globalIndex)
            .. string.pack("<s", modPath)
            .. string.pack("<s", filename)
            .. string.pack("<L", file.size)
            .. string.pack("<H", numParts)
            .. string.pack("<H", i)
            .. string.pack("<H", length)
            .. bytes

        sRequests[#sRequests+1] = FS_Request.new(
            toLocalIndex,
            packet
        )
        log_message(string.format("send: Sending file part %d to local index %d: %s/%s", i, toLocalIndex, modPath, filename))
    end

    return true
end

--- @param pending FS_PendingFile
--- @param parts table<integer, integer>
local function send_retry(pending, parts)
    if pending.state == FILE_STATE_PENDING then
        if pending.retries < sConfig.MAX_RETRIES then
            local timestamp = get_time()
            local globalIndex = network_global_index_from_local(0)
            for _, partIndex in ipairs(parts) do
                local packet = ''
                    .. string.pack("<I4", PACKET_MAGIC)
                    .. string.pack("<B", PACKET_TYPE_REQUEST_RETRY)
                    .. string.pack("<I8", timestamp)
                    .. string.pack("<B", globalIndex)
                    .. string.pack("<s", pending.modPath)
                    .. string.pack("<s", pending.filename)
                    .. string.pack("<H", partIndex)

                sRequests[#sRequests+1] = FS_Request.new(
                    network_local_index_from_global(pending.sender),
                    packet
                )
                log_message(string.format("send_retry: Sending retry for file part %d: %s/%s", partIndex, pending.modPath, pending.filename))
            end
            pending.retries = pending.retries + 1
            pending.lastTick = get_global_timer()
        else
            log_error(string.format("send_retry: File %s/%s: Exceeded number of retries", pending.modPath, pending.filename))
            pending.state = FILE_STATE_CANCELED
            pending.timestamp = get_time() + 1
        end
    end
end

--- @param p FS_Packet
local function retry_send_file(p)
    local timestamp = p:unpack("<I8")
    local sender    = p:unpack("<B")
    local modPath   = p:unpack("<s")
    local filename  = p:unpack("<s")
    local partIndex = p:unpack("<H")

    send(network_local_index_from_global(sender), modPath, filename, partIndex, true)
end

-------------
-- receive --
-------------

--- @param p FS_Packet
--- @param isRetry boolean
local function receive_file_part(p, isRetry)
    local timestamp = p:unpack("<I8")
    local sender    = p:unpack("<B")
    local modPath   = p:unpack("<s")
    local filename  = p:unpack("<s")
    local size      = p:unpack("<L")
    local numParts  = p:unpack("<H")
    local partIndex = p:unpack("<H")
    local length    = p:unpack("<H")
    local bytes     = string.sub(p.data, p.offset)
    local fullname  = string.format("%s/%s", modPath, filename)

    if sPendingFiles[fullname] == nil then
        if isRetry then
            log_message(string.format("receive_file_part: File %s: File part ignored, because file is not in pending", fullname))
            return
        end
        sPendingFiles[fullname] = FS_PendingFile.new(
            modPath,
            filename,
            size,
            numParts,
            sender,
            timestamp
        )
    end

    local pending = sPendingFiles[fullname]

    -- Check timestamp
    if timestamp < pending.timestamp then
        log_message(string.format("receive_file_part: File %s: File part ignored, because it is too old: %d < %d", fullname, timestamp, pending.timestamp))
        return
    end

    -- Check state
    if pending.state == FILE_STATE_COMPLETED then
        log_message(string.format("receive_file_part: File %s: File part ignored, because file is already completed", fullname))
        return
    end
    if pending.state == FILE_STATE_CANCELED then
        if isRetry then
            log_message(string.format("receive_file_part: File %s: File part ignored, because file is canceled", fullname))
            return
        end

        -- Reset file
        sPendingFiles[fullname] = FS_PendingFile.new(
            modPath,
            filename,
            size,
            numParts,
            sender,
            timestamp
        )
        pending = sPendingFiles[fullname]
    end
    if pending.state ~= FILE_STATE_PENDING then
        log_error(string.format("receive_file_part: File %s: File is not in pending state", fullname, pending.state))
        sPendingFiles[fullname] = nil
        return
    end

    -- Check sender
    if sender ~= pending.sender then
        log_error(string.format("receive_file_part: File %s: Invalid sender: %d, should be %d", fullname, sender, pending.sender))
        send_retry(pending, { partIndex })
        return
    end

    -- Check size
    if size ~= pending.size then
        log_error(string.format("receive_file_part: File %s: Invalid size: %d, should be %d", fullname, size, pending.size))
        send_retry(pending, { partIndex })
        return
    end

    -- Check num parts
    if numParts ~= pending.numParts then
        log_error(string.format("receive_file_part: File %s: Invalid num parts: %d, should be %d", fullname, numParts, pending.numParts))
        send_retry(pending, { partIndex })
        return
    end

    -- Check part length
    if #bytes ~= length then
        log_error(string.format("receive_file_part: File %s: Invalid file part length: %d, should be %d", fullname, #bytes, length))
        send_retry(pending, { partIndex })
        return
    end

    pending.lastTick = get_global_timer()
    pending.parts[partIndex] = bytes
    log_message(string.format("receive_file_part: File %s: Received file part %d of length %d", fullname, partIndex, length))
end

--- @return table<integer, FS_File>, table<integer, FS_File>
--- Receives files. Returns two lists:
--- - Successfully received files. Each file has the following fields: `sender: integer`, `modPath: string`, `filename: string`, `size: integer`, `data: string`.
--- - Pending files which are being downloaded. Each pending file has the following fields: `sender: integer`, `modPath: string`, `filename: string`, `size: integer`, `completion: number`.
local function receive()
    local receivedFiles = {}
    local pendingFiles = {}
    local completed = {}

    for fullname, pending in pairs(sPendingFiles) do
        if pending.state == FILE_STATE_COMPLETED then
            receivedFiles[#receivedFiles+1] = FS_File.new(
                pending.sender,
                pending.modPath,
                pending.filename,
                pending.size,
                nil,
                pending:get_data()
            )
            completed[#completed+1] = fullname
        elseif pending.state == FILE_STATE_PENDING then
            pendingFiles[#pendingFiles+1] = FS_File.new(
                pending.sender,
                pending.modPath,
                pending.filename,
                pending.size,
                pending:get_completion(),
                nil
            )
        end
    end

    -- Removed received files from pending list
    for _, fullname in ipairs(completed) do
        sPendingFiles[fullname] = nil
    end

    return receivedFiles, pendingFiles
end

local function update_receive()
    local timer = get_global_timer()
    for fullname, pending in pairs(sPendingFiles) do

        -- Update file state when all parts are here
        local missingParts = {}
        for i = 1, pending.numParts do
            if pending.parts[i] == nil then
                missingParts[#missingParts+1] = i
            end
        end
        if #missingParts == 0 then
            pending.state = FILE_STATE_COMPLETED
            log_message(string.format("update_receive: Successfully received file: %s", fullname))
        end

        -- If timed out, send a retry for each missing part
        if pending.state == FILE_STATE_PENDING and timer - pending.lastTick > sConfig.TIMEOUT_FRAMES then
            log_error(string.format("update_receive: File %s has timed out, sending retry", fullname))
            send_retry(pending, missingParts)
        end
    end
end

hook_event(HOOK_UPDATE, update_receive)

----------
-- save --
----------

--- @param f FS_File A file received from the `receive` function.
--- @param destFilename? string An optional destination filename. If not provided, file will be saved to path `<f.modPath>/<f.filename>`.
--- @return boolean
--- Saves file to ModFS.
local function save(f, destFilename)
    if not f.data then
        log_error("save: Cannot save an empty file")
        return false
    end

    local modFs = mod_fs_get() or mod_fs_create()
    if not modFs then
        log_error("save: Unable to open ModFS")
        return false
    end

    destFilename = destFilename or string.format("%s/%s", f.modPath, f.filename)
    if modFs:get_file(destFilename) then
        modFs:delete_file(destFilename)
    end
    local file = modFs:create_file(destFilename, false)
    if not file then
        log_error(string.format("save: Unable to create file: %s", destFilename))
        return false
    end

    if not file:write_bytes(f.data) then
        log_error(string.format("save: Unable to write to file: %s", destFilename))
        return false
    end

    if not modFs:save() then
        log_error(string.format("save: Unable to save ModFS: %s", modFs.modPath))
        return false
    end

    return true
end

-------------
-- packets --
-------------

local sPacketTypes = {
    [PACKET_TYPE_SEND_FILE] = function (p) return receive_file_part(p, false) end,
    [PACKET_TYPE_RETRY_FILE] = function (p) return receive_file_part(p, true) end,
    [PACKET_TYPE_REQUEST_RETRY] = retry_send_file,
}

--- @param packet string
local function on_packet_bytestring_receive(packet)
    local p = FS_Packet.new(packet)

    local magic = p:unpack("<I4")
    if magic ~= PACKET_MAGIC then
        return
    end

    local ptype = p:unpack("<B")
    if sPacketTypes[ptype] ~= nil then
        sPacketTypes[ptype](p)
    end
end

hook_event(HOOK_ON_PACKET_BYTESTRING_RECEIVE, on_packet_bytestring_receive)

---------
-- lib --
---------

local _fileshare = {

    -- constants and default values
    PACKET_MAGIC = PACKET_MAGIC,
    MAX_FILE_SIZE = MAX_FILE_SIZE,
    MAX_REQUESTS_PER_FRAME = MAX_REQUESTS_PER_FRAME,
    TIMEOUT_FRAMES = TIMEOUT_FRAMES,
    MAX_RETRIES = MAX_RETRIES,
    VERBOSE = VERBOSE,

    -- functions
    send    = function (toLocalIndex, modPath, filename) return send(toLocalIndex, modPath, filename) end,
    receive = function () return receive() end,
    save    = function (f, destFilename) return save(f, destFilename) end,
    config  = {
        MAX_FILE_SIZE = "MAX_FILE_SIZE",
        MAX_REQUESTS_PER_FRAME = "MAX_REQUESTS_PER_FRAME",
        TIMEOUT_FRAMES = "TIMEOUT_FRAMES",
        MAX_RETRIES = "MAX_RETRIES",
        VERBOSE = "VERBOSE",
        get = function (name) return config_get(name) end,
        set = function (name, value) return config_set(name, value) end,
    }
}

--- @class config
--- @field get fun(name: string): integer|boolean
--- @field set fun(name: string, value: integer|boolean)
--- @field MAX_FILE_SIZE string
--- @field MAX_REQUESTS_PER_FRAME string
--- @field TIMEOUT_FRAMES string
--- @field MAX_RETRIES string
--- @field VERBOSE string

--- @class fileshare
--- @field PACKET_MAGIC integer
--- @field MAX_FILE_SIZE integer
--- @field MAX_REQUESTS_PER_FRAME integer
--- @field TIMEOUT_FRAMES integer
--- @field MAX_RETRIES integer
--- @field VERBOSE boolean
--- @field send fun(toLocalIndex: integer, modPath: string, filename: string): boolean
--- @field receive fun(): table<integer, FS_File>, table<integer, FS_File>
--- @field save fun(f: FS_File, destFilename?: string): boolean
--- @field config config
local fileshare = setmetatable({}, {
    __index = _fileshare,
    __newindex = function () end,
    __metatable = false
})

return fileshare
