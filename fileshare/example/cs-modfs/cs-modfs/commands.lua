
local function check_cs()
    if not _G.charSelectExists then
        djui_popup_create("\\#ffffa0\\[CS] ModFS requires\nCharacter Select to be enabled.\n\nPlease rehost with it enabled.", 4)
        return false
    end
    return true
end

local function on_chat_command_loadchar(modPath)
    if not check_cs() then
        return true
    end

    local modFs = mod_fs_get(modPath)
    if not modFs then
        djui_chat_message_create("\\#ffa0a0\\There is no ModFS at path: " .. modPath)
        return true
    end

    -- Look for the first json file found in modPath
    for i = 0, modFs.numFiles - 1 do
        local filename = modFs:get_filename(i)
        if string.endswith(filename, ".json") then
            local character = load_character_data(modPath, filename, false)
            if character then
                local charName = character.name
                if gCharacterData[charName] then
                    log_message(string.format("Character already exists in list: %s", charName))
                    return true
                end

                character.globalIndex = network_global_index_from_local(0)
                gCharacterData[charName] = character
                log_message("Added character: " .. charName)
                print_character_data(character)
                send_character(character)
            end
            return true
        end
    end

    djui_chat_message_create("\\#ffa0a0\\There is no \"character.json\" file in ModFS at path: " .. modPath)
    return true
end

hook_event(HOOK_ON_MODS_LOADED, check_cs)

hook_chat_command("loadchar", "[modPath] - Loads a character from ModFS and send it to other players", on_chat_command_loadchar)
