local fileshare = require("fileshare")

local PACKET_MAGIC = 0x11223344

local PACKET_HOST_REQUEST_FILE_LIST = 1
local PACKET_HOST_REQUEST_FILE_DATA = 2
local PACKET_HOST_CHARACTER_DATA = 3

local PACKET_GUEST_CHARACTER = 101
local PACKET_GUEST_FILE_LIST = 102
local PACKET_GUEST_REQUEST_CHARACTER_DATA = 103
local PACKET_GUEST_REQUEST_FILE_DATA = 104

local PACKET_FMT_STRING = "<s"
local PACKET_FMT_MAGIC = "<I4"
local PACKET_FMT_PTYPE = "<B"
local PACKET_FMT_GLOBAL_INDEX = "<B"
local PACKET_FMT_NUM_FILES = "<I2"

local CHARACTER_FILE_TIMEOUT_FRAMES = 90

------------
-- packet --
------------

--- @class Packet
--- @field data string
--- @field offset integer
local Packet = {}

--- @param ptype integer
--- @return Packet
function Packet.new(ptype)
    return {
        data = string.pack(PACKET_FMT_MAGIC, PACKET_MAGIC) .. string.pack(PACKET_FMT_PTYPE, ptype),
        offset = 1,

        read = Packet.read,
        pack = Packet.pack,
        unpack = Packet.unpack,
    }
end

--- @param packet string
--- @return Packet
function Packet.read(packet)
    local p = Packet.new(0)
    p.data = packet
    return p
end

--- @param p Packet
--- @param fmt string
--- @param value any
function Packet.pack(p, fmt, value)
    p.data = p.data .. string.pack(fmt, value)
end

--- @param p Packet
--- @param fmt string
--- @return any
function Packet.unpack(p, fmt)
    local value
    value, p.offset = string.unpack(fmt, p.data, p.offset)
    return value
end

----------
-- list --
----------

local function pack_character_list()
    local s = string.format("%4d", #gCharacterList)
    for _, name in ipairs(gCharacterList) do
        s = s .. string.format("%3d", #name)
        s = s .. name
    end
    return s
end

local function unpack_character_list(s)
    local numChars = tonumber(string.sub(s, 1, 4))
    local offset = 5
    local list = {}
    for i = 1, numChars do
        local len = tonumber(string.sub(s, offset, offset + 2))
        local name = string.sub(s, offset + 3, offset + 2 + len)
        list[#list+1] = name
        offset = offset + 3 + len
    end
    return list
end

local function add_character_to_list(charName)
    for _, name in ipairs(gCharacterList) do
        if name == charName then
            log_message(string.format("Character already exists in list: %s", charName))
            return false
        end
    end
    gCharacterList[#gCharacterList+1] = charName
    return true
end

local function remove_character_from_list(charName)
    for i, name in ipairs(gCharacterList) do
        if name == charName then
            table.remove(gCharacterList, i)
            return true
        end
    end
    return false
end

---------------
-- filepaths --
---------------

-- Due to the 3000 bytes packet limit, we need to shorten data
-- as much as possible to be able to send more data at once
-- Shorten redudant data like common directory names in path and
-- extensions by reducing them to a few characters

local SHORTS = {
    ["^actors/"] = "^A/",
    ["^textures/"] = "^T/",
    ["^sound/"] = "^S/",
    ["/actors/"] = "/A/",
    ["/textures/"] = "/T/",
    ["/sound/"] = "/S/",
    ["%.json$"] = "%.J$",
    ["%.bin$"] = "%.B$",
    ["%.tex$"] = "%.T$",
    ["%.png$"] = "%.P$",
    ["%.aiff$"] = "%.A$",
    ["%.mp3$"] = "%.M$",
    ["%.ogg$"] = "%.O$",
}

local function filepath_replace(filepath, pattern, repl)
    repl = repl:gsub("%%", ""):gsub("%^", ""):gsub("%$", "")
    return string.gsub(filepath, pattern, repl)
end

local function filepath_shorten(filepath)
    for pattern, repl in pairs(SHORTS) do
        filepath = filepath_replace(filepath, pattern, repl)
    end
    return filepath
end

local function filepath_unshorten(filepath)
    for repl, pattern in pairs(SHORTS) do
        filepath = filepath_replace(filepath, pattern, repl)
    end
    return filepath
end

-----------
-- files --
-----------

local function get_modpath_and_filename(modPath, filename)
    if modPath == gModFs.modPath then
        local sep = string.find(filename, "/")
        return filename:sub(1, sep - 1), filename:sub(sep + 1)
    end
    return modPath, filename
end

function find_character_file(modPath, filename)
    for _, cfile in ipairs(gCharacterFiles) do
        if cfile.modPath == modPath and cfile.filename == filename then
            return cfile
        end
    end
    return nil
end

local function find_next_pending_character_file()
    for _, cfile in ipairs(gCharacterFiles) do
        if cfile.pending then
            return nil
        end
        if cfile.data == nil then
            return cfile
        end
    end
    return nil
end

local function check_all_characters_files_received()
    for _, cfile in ipairs(gCharacterFiles) do
        if cfile.data == nil then
            return false
        end
    end
    return true
end

local function check_character_file_list_received(charName)
    for _, cfile in ipairs(gCharacterFiles) do
        if cfile.name == charName then
            return true
        end
    end
    return false
end

local function update_character_files(receivedFiles, pendingFiles, isHost)

    -- Receive files
    for _, file in ipairs(receivedFiles) do
        local modPath, filename = get_modpath_and_filename(file.modPath, file.filename)
        local cfile = find_character_file(modPath, filename)
        if cfile ~= nil then
            cfile.data = file.data
            cfile.pending = false
            log_message(string.format("<-- Received data for file \"%s\" from global index (%d) for character: %s", cfile.filename, cfile.globalIndex, cfile.name))
        end
    end

    -- If no pending, send a request for the next file to receive
    if #pendingFiles == 0 then
        local cfile = find_next_pending_character_file()
        if cfile ~= nil then
            local pRequestFileData = Packet.new(isHost and PACKET_HOST_REQUEST_FILE_DATA or PACKET_GUEST_REQUEST_FILE_DATA)
            if not isHost then
                local globalIndex = network_global_index_from_local(0)
                pRequestFileData:pack(PACKET_FMT_GLOBAL_INDEX, globalIndex)
            end
            pRequestFileData:pack(PACKET_FMT_STRING, cfile.name)
            pRequestFileData:pack(PACKET_FMT_STRING, cfile.filename)
            network_send_bytestring_to(network_local_index_from_global(cfile.globalIndex), true, pRequestFileData.data)
            log_message(string.format("--> Requesting data of file \"%s\" from global index (%d) for character: %s", cfile.filename, cfile.globalIndex, cfile.name))
            cfile.pending = true
            cfile.lastTick = get_global_timer()
        end
    end

    -- Update last tick for pending files
    for _, file in ipairs(pendingFiles) do
        local cfile = find_character_file(file.modPath, file.filename)
        if cfile ~= nil then
            cfile.lastTick = get_global_timer()
        end
    end

    -- Check timeouts
    local timer = get_global_timer()
    local done = false
    while not done do
        done = true
        for _, cfile in ipairs(gCharacterFiles) do
            if cfile.data == nil and cfile.pending and timer > cfile.lastTick + CHARACTER_FILE_TIMEOUT_FRAMES then
                local charName = cfile.name
                log_message(string.format("[!] TIMEOUT: Could not receive in time file \"%s\" from global index (%d) for character: %s", cfile.filename, cfile.globalIndex, charName))

                -- Host: remove all files of character
                if isHost then
                    while true do
                        local j = table.find(gCharacterFiles, function (k, v) return v.name == charName end)
                        if j == nil then break end
                        local cfilej = gCharacterFiles[j]
                        log_message(string.format("[!] Removing file: \"%s\"", cfilej.filename))
                        table.remove(gCharacterFiles, j)
                    end

                    -- Remove character from the lists
                    remove_character_from_list(charName)
                    gCharacterData[charName] = nil
                    log_message(string.format("[!] Character is removed from the list: %s", charName))

                    done = false
                    break
                end

                -- Guest: try again later
                cfile.lastTick = get_global_timer()
                cfile.pending = false
                log_message(string.format("[!] Queueing file \"%s\" again for character: %s", cfile.filename, charName))
            end
        end
    end
end

----------
-- send --
----------

function send_character(character)

    -- Host builds the `gCharacterList`, which will determine the loading order of characters
    if network_is_server() then
        add_character_to_list(character.name)
        return
    end

    -- Guests send their character so host can fill the `gCharacterList`
    local pCharacter = Packet.new(PACKET_GUEST_CHARACTER)
    pCharacter:pack(PACKET_FMT_GLOBAL_INDEX, character.globalIndex)
    pCharacter:pack(PACKET_FMT_STRING, character.name)
    pCharacter:pack(PACKET_FMT_STRING, character.modPath)
    pCharacter:pack(PACKET_FMT_STRING, character.jsonPath)
    network_send_bytestring_to(network_local_index_from_global(0), true, pCharacter.data)
    log_message(string.format("--> Sending character to host: %s", character.name))
end

---------------------
-- receive (guest) --
---------------------

local function on_packet_host_request_file_list(p)
    if network_is_server() then -- shouldn't happen
        return
    end

    -- Send list of files
    local charName = p:unpack(PACKET_FMT_STRING)
    local character = gCharacterData[charName]
    if character ~= nil then
        local numFiles = table.count(character.files)
        local pFileList = Packet.new(PACKET_GUEST_FILE_LIST)
        pFileList:pack(PACKET_FMT_STRING, charName)
        pFileList:pack(PACKET_FMT_NUM_FILES, numFiles)
        for filename, _ in pairs(character.files) do
            pFileList:pack(PACKET_FMT_STRING, filepath_shorten(filename))
        end
        network_send_bytestring_to(network_local_index_from_global(0), true, pFileList.data)
        log_message(string.format("--> Sending list of %d files to host for character: %s", numFiles, charName))
    end
end

local function on_packet_host_request_file_data(p)
    if network_is_server() then -- shouldn't happen
        return
    end

    -- Send file data
    local charName = p:unpack(PACKET_FMT_STRING)
    local character = gCharacterData[charName]
    if character ~= nil then
        local filename = p:unpack(PACKET_FMT_STRING)
        local modPath = character.modPath
        if fileshare.send(network_local_index_from_global(0), modPath, filename) then
            log_message(string.format("--> Sending data of file \"%s\" to host for character: %s", filename, charName))
        end
    end
end

local function on_packet_host_character_data(p)
    if network_is_server() then -- shouldn't happen
        return
    end

    -- Receive character data
    local globalIndex = p:unpack(PACKET_FMT_GLOBAL_INDEX)
    local charName = p:unpack(PACKET_FMT_STRING)
    local modPath = p:unpack(PACKET_FMT_STRING)
    local jsonPath = p:unpack(PACKET_FMT_STRING)
    local numFiles = p:unpack(PACKET_FMT_NUM_FILES)
    local files = {}
    for _ = 1, numFiles do
        local filename = filepath_unshorten(p:unpack(PACKET_FMT_STRING))
        files[filename] = true
    end
    log_message(string.format("<-- Received character data from host for character: %s", charName))

    gCharacterData[charName] = {
        name = charName,
        globalIndex = globalIndex,
        modPath = modPath,
        jsonPath = jsonPath,
        files = files,
        data = nil,
    }

    local character = gCharacterData[charName]
    print_character_data(gCharacterData[charName])

    -- Adds file to pending list
    for filename, _ in pairs(character.files) do
        gCharacterFiles[#gCharacterFiles+1] = {
            name = charName,
            globalIndex = 0, -- request files from the host
            modPath = character.modPath,
            filename = filename,
            data = nil,
            lastTick = get_global_timer(),
            pending = false,
        }
    end
end

--------------------
-- receive (host) --
--------------------

local function on_packet_guest_character(p)
    if not network_is_server() then -- shouldn't happen
        return
    end

    -- Receive character
    local charGlobalIndex = p:unpack(PACKET_FMT_GLOBAL_INDEX)
    local charName = p:unpack(PACKET_FMT_STRING)
    local charModPath = p:unpack(PACKET_FMT_STRING)
    local charJsonPath = p:unpack(PACKET_FMT_STRING)

    -- Check if character already exists
    if not add_character_to_list(charName) then
        return
    end
    log_message(string.format("<-- Received character from global index (%d): %s", charGlobalIndex, charName))

    -- Add entry in gCharacterData
    if gCharacterData[charName] == nil then
        gCharacterData[charName] = {
            name = charName,
            globalIndex = charGlobalIndex,
            modPath = charModPath,
            jsonPath = charJsonPath,
            files = {},
            data = nil,
        }

        -- Request the list of files
        local pRequestFileList = Packet.new(PACKET_HOST_REQUEST_FILE_LIST)
        pRequestFileList:pack(PACKET_FMT_STRING, charName)
        network_send_bytestring_to(network_local_index_from_global(charGlobalIndex), true, pRequestFileList.data)
        log_message(string.format("--> Requesting list of files from globalIndex (%d) for character: %s", charGlobalIndex, charName))
    end
end

local function on_packet_guest_file_list(p)
    if not network_is_server() then -- shouldn't happen
        return
    end

    -- Receive list of files
    local charName = p:unpack(PACKET_FMT_STRING)
    local character = gCharacterData[charName]
    if character ~= nil then
        local numFiles = p:unpack(PACKET_FMT_NUM_FILES)
        for _ = 1, numFiles do
            local filename = filepath_unshorten(p:unpack(PACKET_FMT_STRING))
            character.files[filename] = true

            -- Adds file to pending list
            gCharacterFiles[#gCharacterFiles+1] = {
                name = charName,
                globalIndex = character.globalIndex,
                modPath = character.modPath,
                filename = filename,
                data = nil,
                lastTick = get_global_timer(),
                pending = false,
            }
        end
        log_message(string.format("<-- Received list of %d files for character: %s", numFiles, charName))
        print_character_data(character)
    end
end

local function on_packet_guest_request_character_data(p)
    if not network_is_server() then -- shouldn't happen
        return
    end

    -- Receive request
    local globalIndex = p:unpack(PACKET_FMT_GLOBAL_INDEX)
    local charName = p:unpack(PACKET_FMT_STRING)
    local character = gCharacterData[charName]

    -- Send character data
    local pCharacterData = Packet.new(PACKET_HOST_CHARACTER_DATA)
    pCharacterData:pack(PACKET_FMT_GLOBAL_INDEX, character.globalIndex)
    pCharacterData:pack(PACKET_FMT_STRING, character.name)
    pCharacterData:pack(PACKET_FMT_STRING, character.modPath)
    pCharacterData:pack(PACKET_FMT_STRING, character.jsonPath)
    pCharacterData:pack(PACKET_FMT_NUM_FILES, table.count(character.files))
    for filename, _ in pairs(character.files) do
        pCharacterData:pack(PACKET_FMT_STRING, filepath_shorten(filename))
    end
    network_send_bytestring_to(network_local_index_from_global(globalIndex), true, pCharacterData.data)
    log_message(string.format("--> Sending character data to globalIndex (%d) for character: %s", globalIndex, charName))
end

local function on_packet_guest_request_file_data(p)
    if not network_is_server() then -- shouldn't happen
        return
    end

    -- Send file data
    local globalIndex = p:unpack(PACKET_FMT_GLOBAL_INDEX)
    local charName = p:unpack(PACKET_FMT_STRING)
    local character = gCharacterData[charName]
    if character ~= nil then
        local filename = p:unpack(PACKET_FMT_STRING)
        local modPath = character.modPath
        local filepath = modPath .. "/" .. filename
        if gModFs:get_file(filepath) then
            modPath = gModFs.modPath
        else
            filepath = filename
        end
        if fileshare.send(network_local_index_from_global(globalIndex), modPath, filepath) then
            log_message(string.format("--> Sending data of file \"%s\" to globalIndex (%d) for character: %s", filename, globalIndex, charName))
        end
    end
end

-------------
-- packets --
-------------

local sPacketTable = {

    -- Received by guest
    [PACKET_HOST_REQUEST_FILE_LIST] = on_packet_host_request_file_list,
    [PACKET_HOST_REQUEST_FILE_DATA] = on_packet_host_request_file_data,
    [PACKET_HOST_CHARACTER_DATA] = on_packet_host_character_data,

    -- Received by host
    [PACKET_GUEST_CHARACTER] = on_packet_guest_character,
    [PACKET_GUEST_FILE_LIST] = on_packet_guest_file_list,
    [PACKET_GUEST_REQUEST_CHARACTER_DATA] = on_packet_guest_request_character_data,
    [PACKET_GUEST_REQUEST_FILE_DATA] = on_packet_guest_request_file_data,
}

function on_packet_bytestring_receive(packet)
    local p = Packet.read(packet)
    if p:unpack(PACKET_FMT_MAGIC) ~= PACKET_MAGIC then
        return
    end

    local ptype = p:unpack(PACKET_FMT_PTYPE)
    if sPacketTable[ptype] ~= nil then
        sPacketTable[ptype](p)
    end
end

hook_event(HOOK_ON_PACKET_BYTESTRING_RECEIVE, on_packet_bytestring_receive)

------------
-- update --
------------

local function main_update()
    local isHost = network_is_server()

    local receivedFiles, pendingFiles = fileshare.receive()
    update_character_files(receivedFiles, pendingFiles, isHost)

    -- If all characters files are received, load characters into CS
    if check_all_characters_files_received() then
        local loadedChars = 0
        for i, charName in ipairs(gCharacterList) do
            if not is_character_loaded(charName) and (is_character_data_loaded(charName) or check_character_file_list_received(charName)) then
                if load_character(charName) then
                    loadedChars = loadedChars + 1
                elseif isHost then
                    table.remove(gCharacterList, i)
                end
            end
        end
        if isHost and loadedChars ~= 0 then
            log_message(string.format("--> Sending character list (%d characters) to other players", #gCharacterList))
            gGlobalSyncTable.gCharacterList = pack_character_list()
        end
    end
end

hook_event(HOOK_UPDATE, main_update)

local function on_character_list_change(_, _, new)
    if network_is_server() then
        return
    end
    gCharacterList = unpack_character_list(new)
    log_message(string.format("<-- Received character list (%d characters) from host", #gCharacterList))

    -- For each missing character, request character data
    for _, charName in ipairs(gCharacterList) do
        if gCharacterData[charName] == nil then
            local globalIndex = network_global_index_from_local(0)
            local pRequestCharacterData = Packet.new(PACKET_GUEST_REQUEST_CHARACTER_DATA)
            pRequestCharacterData:pack(PACKET_FMT_GLOBAL_INDEX, globalIndex)
            pRequestCharacterData:pack(PACKET_FMT_STRING, charName)
            network_send_bytestring_to(network_local_index_from_global(0), true, pRequestCharacterData.data)
            log_message(string.format("--> Requesting character data from host for character: %s", charName))
        end
    end
end

hook_on_sync_table_change(gGlobalSyncTable, "gCharacterList", 0, on_character_list_change)
