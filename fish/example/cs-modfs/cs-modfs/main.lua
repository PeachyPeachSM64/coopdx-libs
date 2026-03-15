-- name: [CS] ModFS
-- description: Inject your custom characters directly in Character Select, using ModFS!

gModFs = mod_fs_get() or mod_fs_create()
if network_is_server() then
    gModFs:clear()
end

gCharacterList = {}

gCharacterData = {}

gCharacterFiles = {}
