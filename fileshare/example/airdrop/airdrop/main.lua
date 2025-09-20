-- name: Airdrop

mod_fs_clear(mod_fs_get() or mod_fs_create())

local fileshare = require("fileshare")

local showTimer = 0
local showTexture = nil

hook_chat_command("clear", " ", function (msg)
    mod_fs_clear(mod_fs_get() or mod_fs_create())
    return true
end)

hook_chat_command("list", "<modPath>", function (msg)
    local modFs = mod_fs_get(msg)
    if modFs then
        djui_chat_message_create("--- Files in " .. msg .. ": ---")
        for i = 1, modFs.numFiles do
            djui_chat_message_create(tostring(mod_fs_get_filename(modFs, i - 1)))
        end
    end
    return true
end)

hook_chat_command("show", "<modPath>/<filename>", function (msg)
    local sep = string.find(msg, "/")
    if sep then
        local modPath = string.sub(msg, 1, sep - 1)
        local filename = string.sub(msg, sep + 1)
        if mod_fs_get(modPath) == nil or mod_fs_get_file(mod_fs_get(modPath), filename) == nil then
            djui_chat_message_create("No such file: " .. msg)
            return true
        end
        showTexture = get_texture_info(string.format(MOD_FS_URI_FORMAT, modPath, filename))
        if showTexture then
            showTimer = 60
        end
    end
    return true
end)

hook_chat_command("send", "<modPath>/<filename>", function (msg)
    local sep = string.find(msg, "/")
    if sep then
        local modPath = string.sub(msg, 1, sep - 1)
        local filename = string.sub(msg, sep + 1)
        if fileshare.send(0, modPath, filename) then
            djui_chat_message_create("Sending file: " .. msg)
        end
    end
    return true
end)

hook_event(HOOK_UPDATE, function ()
    local receivedFiles, pendingFiles = fileshare.receive()
    for _, pendingFile in ipairs(pendingFiles) do
        djui_chat_message_create(string.format("Receiving file %s/%s: %d%%...",
            pendingFile.modPath,
            pendingFile.filename,
            math.ceil(pendingFile.completion * 100)
        ))
    end
    for _, receivedFile in ipairs(receivedFiles) do
        djui_chat_message_create(string.format("Received file: %s/%s",
            receivedFile.modPath,
            receivedFile.filename
        ))
        fileshare.save(receivedFile)
    end
end)

hook_event(HOOK_ON_HUD_RENDER, function ()
    if showTimer > 0 then
        djui_hud_set_resolution(RESOLUTION_N64)
        djui_hud_set_color(255, 255, 255, math.clamp(math.lerp(0, 255, showTimer / 30), 0, 255))
        local x = (djui_hud_get_screen_width() - showTexture.width / 2) / 2
        local y = (djui_hud_get_screen_height() - showTexture.height / 2) / 2
        djui_hud_render_texture(showTexture, x, y, 0.5, 0.5)
        showTimer = showTimer - 1
    end
end)

hook_event(HOOK_MARIO_UPDATE, function (m)
    if m.action == ACT_IDLE then
        m.actionTimer = 0
    end
end)
