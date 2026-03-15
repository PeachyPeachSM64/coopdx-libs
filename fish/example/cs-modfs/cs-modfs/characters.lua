local CHARACTER_DATA_MAX_SIZE = 0x100000 -- 1MB

local function is_character_filepath(s)
    return (
        string.endswith(s, ".json") or
        string.endswith(s, ".bin") or
        string.endswith(s, ".png") or
        string.endswith(s, ".tex") or
        string.endswith(s, ".aiff") or
        string.endswith(s, ".mp3") or
        string.endswith(s, ".ogg")
    )
end

function load_character_data(modPath, jsonPath, dataOnly)
    local character = dataOnly and {} or {
        modPath = modPath,
        jsonPath = jsonPath,
        files = {},
        data = nil,
    }

    local modFs = mod_fs_get(modPath)
    local characterData = read_json_file(modFs, jsonPath)
    if characterData then
        local totalSize = modFs:get_file(jsonPath).size
        if not dataOnly then
            character.files[jsonPath] = true
        end

        -- Search for files
        table.walk(characterData, function (_, _, filename)
            if type(filename) == "string" and is_character_filepath(filename) then
                local file = modFs:get_file(filename)
                if not dataOnly then
                    if file then
                        totalSize = totalSize + file.size
                        character.files[filename] = true
                    else
                        log_message("File not found: " .. string.format("%s/%s", modPath, filename))
                    end
                end
            end
        end)

        -- baseChar
        characterData.baseChar = _G[characterData.baseChar]

        -- palette
        if type(characterData.palette) == "table" then
            local palette = {}
            for playerPart, color in pairs(characterData.palette) do
                palette[_G[playerPart]] = color
            end
            characterData.palette = palette
        end

        -- voices
        if type(characterData.voices) == "table" then
            voices = {}
            for charSound, voice in pairs(characterData.voices) do
                voices[_G[charSound]] = voice
            end
            characterData.voices = voices
        end

        -- check total size
        if not dataOnly and totalSize > CHARACTER_DATA_MAX_SIZE then
            log_message("Max size exceeded for character " .. characterData.name .. string.format(" -> rejected (size is %u > %u)", totalSize, CHARACTER_DATA_MAX_SIZE))
            return nil
        end

        character.name = characterData.name
        character.data = characterData
    end

    return character
end

function is_character_loaded(charName)
    local character = gCharacterData[charName]
    if character and character.modelId ~= nil then
        return true
    end
    return false
end

function is_character_data_loaded(charName)
    local character = gCharacterData[charName]
    if character and character.data ~= nil then
        return true
    end
    return false
end

function load_character(charName)
    local character = gCharacterData[charName]
    if character == nil then
        log_message(string.format("/!\\ Attempting to load missing character: %s", charName))
        return false
    end

    -- Already loaded
    if character.modelId ~= nil then
        return true
    end

    local trueModPath = character.modPath

    -- Load character data
    if character.data == nil then

        -- Store files in modfs
        for filename, _ in pairs(character.files) do
            local cfile = find_character_file(character.modPath, filename)
            if not cfile then
                log_message(string.format("/!\\ Attempting to load missing file \"%s\" for character: %s", filename, charName))
                return false
            end
            local filepath = character.modPath .. "/" .. filename
            local file = gModFs:get_file(filepath) or gModFs:create_file(filepath, false)
            file:set_text_mode(false)
            file:rewind()
            file:erase(file.size)
            file:write_bytes(cfile.data)
        end

        -- Load character data
        local jsonPath = character.modPath .. "/" .. character.jsonPath
        local characterData = load_character_data(gModFs.modPath, jsonPath, true)
        if characterData == nil then
            log_message(string.format("/!\\ Unable to load character data: %s", charName))
            return false
        end
        character.data = characterData.data

        -- Change filepaths
        table.walk(character.data, function (t, k, filename)
            if type(filename) == "string" and is_character_filepath(filename) then
                t[k] = character.modPath .. "/" .. filename
            end
        end)
        trueModPath = gModFs.modPath
    end

    -- Update filepaths to modfs
    table.walk(character.data, function (t, k, filename)
        if type(filename) == "string" and is_character_filepath(filename) and not string.startswith(filename, MOD_FS_URI_PREFIX) then
            t[k] = string.format(MOD_FS_URI_FORMAT, trueModPath, filename)
        end
    end)

    -- Load CS character
    local modelId = add_character_to_char_select(character.data)
    if modelId == nil then
        log_message(string.format("/!\\ Unable to add character to Character Select: %s", charName))
        return false
    end

    character.modelId = modelId
    log_message(string.format("Successfully loaded character to Character Select: %s", charName))
    return true
end

function add_character_to_char_select(characterData)

    -- model
    local modelId
    if type(characterData.model) == "string" then
        modelId = smlua_model_util_get_id(characterData.model)
    end
    if modelId == nil or modelId == E_MODEL_ERROR_MODEL then
        return nil
    end

    -- icon
    local characterIcon = characterData.icon and get_texture_info(characterData.icon) or nil

    -- character
    _G.charSelect.character_add(
        characterData.name,
        characterData.description,
        characterData.credit,
        characterData.color,
        modelId,
        characterData.baseChar,
        characterIcon,
        characterData.camScale
    )

    -- palette
    if type(characterData.palette) == "table" then
        _G.charSelect.character_add_palette_preset(
            modelId,
            characterData.palette
        )
    end

    -- caps
    if type(characterData.caps) == "table" then
        local caps = {}
        for k, v in pairs(characterData.caps) do
            caps[k] = smlua_model_util_get_id(v)
        end
        _G.charSelect.character_add_caps(
            modelId,
            caps
        )
    end

    -- voice
    if type(characterData.voices) == "table" then
        for charSound, voice in pairs(characterData.voices) do
            if type(voice) == "table" then
                for i, voiceClip in ipairs(voice) do
                    characterData.voices[charSound][i] = audio_sample_load(voiceClip)
                end
            elseif type(voice) == "string" then
                characterData.voices[charSound] = audio_sample_load(voice)
            end
        end
        _G.charSelect.character_add_voice(
            modelId,
            characterData.voices
        )
        _G.charSelect.config_character_sounds()
    end

    return modelId
end
