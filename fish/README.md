# File Share, aka FiSh 🐟

`fish` is a small library to send and receive ModFS files over the network.<br>
**sm64coopdx v1.4 or later is required.**

> [!IMPORTANT]
> This library is using the hook `HOOK_ON_PACKET_BYTESTRING_RECEIVE`!<br>
> Packets starting with magic `PACKET_MAGIC` (4 bytes, `"<I4"`) are handled by this library and should be ignored by other hooks.<br>
> Example code:
```lua
local function on_packet_bytestring_receive(packet)
    if string.unpack("<I4", packet) == fish.PACKET_MAGIC then
        return
    end

    -- Not a 🐟 packet
    -- ...
end
```

---

## Installation

1. Download the [libraries](https://github.com/PeachyPeachSM64/coopdx-libs/archive/refs/heads/master.zip).
2. Copy the `lib` directory from `fish` into your mod's directory. Your mod hierarchy should look like this:
```
your-mod/
  ├─ lib/
  │   └─ fish.lua
  ├─ main.lua
  └─ ...
```
3. Import the library at the top of your script:
```lua
local fish = require("lib/fish")
```

---

## Usage

<br>

### `send (toLocalIndex, modPath, filename, annotation)`

Sends a file to a remote player.

Params:
- `toLocalIndex`: `integer` - Local index of the player to send the file to. If set to `0`, sends to all players instead.
- `modPath`: `string` - Name of the ModFS.
- `filename`: `string` - Name of the file to send.
- `annotation`: `string` - *Optional*. Annotation to help the receiver to identify the file they receive.

Returns:
- `boolean` - `true` on success.

```lua
-- Send file at modPath/filename to a remote player
fish.send(toLocalIndex, modPath, filename, annotation)
```

<br>

### `receive ()`

Receives files.

Returns:
- `list<🐟File>` - Pending files which are being downloaded. Each pending file has the following fields:
  - `sender`: `integer` - Global index of the player who sent the file.
  - `modPath`: `string` - Name of the ModFS.
  - `filename`: `string` - Name of the file received.
  - `annotation`: `string` - Annotation given to the file.
  - `size`: `integer` - Size of the file in bytes.
  - `completion`: `number` - Percentage of data already received. Ranges from `0` (included) to `1` (excluded, completed files don't appear in this list).
- `list<🐟File>` - Successfully completed files. Each file has the following fields:
  - `sender`: `integer` - Global index of the player who sent the file.
  - `modPath`: `string` - Name of the ModFS.
  - `filename`: `string` - Name of the file received.
  - `annotation`: `string` - Annotation given to the file.
  - `size`: `integer` - Size of the file in bytes.
  - `data`: `string` - File data.

```lua
-- Receive files during a HOOK_UPDATE
hook_event(HOOK_UPDATE, function ()
    local pendingFiles, completedFiles = fish.receive()

    for _, pendingFile in ipairs(pendingFiles) do
        -- pending files...
    end

    for _, completedFile in ipairs(completedFiles) do
        -- completed files...
    end
end)
```

<br>

### `save (file, destFilename)`

Saves file `file` to ModFS at path `destFilename`.

> [!IMPORTANT]
> This function alone does not save the file into persistent storage.<br>
> To physically save the file, one needs to call the `save` function from a ModFS object:
```lua
local modFs = mod_fs_get()
modFs:save()
```

Params:
- `file`: `🐟File` - Completed file received from the `receive` function.
- `destFilename`: `string` *Optional*. Destination filename. If not provided, file will be saved to path `<file.modPath>/<file.filename>`.

Returns:
- `boolean` - `true` on success.

```lua
-- Save files after receiving them in a HOOK_UPDATE
hook_event(HOOK_UPDATE, function ()
    local _, completedFiles = fish.receive()

    for _, completedFile in ipairs(completedFiles) do
        local filename = "<filename>" -- give it a personalized name or keep it default by
                                      -- omitting the filename parameter in the `save` function
        fish.save(completedFile, filename)
    end
end)
```

---

## Configuration

You can configure various parameters of the `fish` library to reduce or increase bandwidth usage depending on your needs and your network capabilities.

Here are the different parameters and their default value:

- `MAX_FILE_SIZE`
  - The maximum file size that can be sent.
  - Default value is `1048576` bytes (1 MB). Set it to `0` to remove this limit.
- `MAX_FILES_PER_PLAYER`
  - The maximum number of files per player the library can handle simultaneously.
  - Default value is `10` files per player. Set it to `0` to remove this limit.
- `MAX_PACKETS_PER_PLAYER`
  - The maximum number of packets per player the library can handle simultaneously.
  - Default value is `500` packets per player. Set it to `0` to remove this limit.
- `MAX_PACKETS_PER_FRAME`
  - The maximum number of packets per frame the library can handle simultaneously.
  - Default value is `50` packets per frame. Set it to `0` to remove this limit.
- `TIMEOUT_FRAMES`
  - The maximum allowed time (in game frames) the library can wait before sending the same packet again if the receiver didn't acknowledge it yet.
  - Default value is `60` frames (2 seconds).
- `MAX_RETRIES`
  - The maximum number of retries allowed per packet. After this number of retries, the whole file transfer is canceled.
  - Default value is `3` retries per packet.
- `DEBUG`
  - If `true` (enabled), prints a bunch of useful information in the console.
  - Default value is `false` (disabled).

<br>

### `config.get (name)`

Retrieves the value of the config `name`.<br>
Can use `config` constants instead of plain strings.

Params:
- `name`: `string` - Name of the config. Allowed names are:
  - `MAX_FILE_SIZE`
  - `MAX_FILES_PER_PLAYER`
  - `MAX_PACKETS_PER_PLAYER`
  - `MAX_PACKETS_PER_FRAME`
  - `TIMEOUT_FRAMES`
  - `MAX_RETRIES`
  - `DEBUG`

Returns:
- `integer|boolean` - Value of config.

```lua
-- Retrieve current value of MAX_FILE_SIZE
local maxFileSize = fish.config.get("MAX_FILE_SIZE")
```

<br>

### `config.set (name, value)`

Sets the value for the config `name`.<br>
Can use `config` constants instead of plain strings.

Params:
- `name`: `string` - Name of the config. Allowed names are:
  - `MAX_FILE_SIZE`
  - `MAX_FILES_PER_PLAYER`
  - `MAX_PACKETS_PER_PLAYER`
  - `MAX_PACKETS_PER_FRAME`
  - `TIMEOUT_FRAMES`
  - `MAX_RETRIES`
  - `DEBUG`
- `value`: `integer|boolean` - Value to set. If it is `nil`, config `name` is restored to default.

```lua
-- Set value of MAX_FILE_SIZE
fish.config.set("MAX_FILE_SIZE", 2000000)
```

---

## Examples

[Airdrop](https://github.com/PeachyPeachSM64/coopdx-libs/tree/master/fish/example/airdrop)

https://github.com/user-attachments/assets/d0284db1-1fb3-40c9-8eb8-574b2b14f95a

[Character Select with ModFS](https://github.com/PeachyPeachSM64/coopdx-libs/tree/master/fish/example/cs-modfs)

https://github.com/user-attachments/assets/f555909f-57a5-48c9-b947-35abd732ca9f
