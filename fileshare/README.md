# File Share

`fileshare` is a small library to send and receive ModFS files over the network.<br>
**sm64coopdx v1.4.0 or later is required.**

> [!IMPORTANT]
> This library is using the hook `HOOK_ON_PACKET_BYTESTRING_RECEIVE`!<br>
> Packets starting with magic `PACKET_MAGIC` (4 bytes, `"<I4"`) are handled by this library and should be ignored by other hooks.<br>
> Example code:
```lua
local function on_packet_bytestring_receive(packet)
    if string.unpack("<I4", packet) == fileshare.PACKET_MAGIC then
        return
    end

    -- Not a fileshare packet
    -- ...
end
```

<br>

## Installation

1. Download the [libraries](https://github.com/PeachyPeachSM64/coopdx-libs/archive/refs/heads/master.zip).
2. Copy the `lib` directory from `fileshare` into your mod's directory.
3. Import the library at the top of your script:
```lua
local fileshare = require("fileshare")
```

<br>

## Constants

- `PACKET_MAGIC`
  - The magic signature of this library's packets. See important note above.
- `MAX_FILE_SIZE`
  - The maximum file size that can be sent.
  - Default value is `1048576` (1 MB).
- `MAX_REQUESTS_PER_FRAME`
  - The maximum number of requests per game frame the library can handle. Each file is sent in small parts, each part sent is a request.
  - Default value is `10`.
- `TIMEOUT_FRAMES`
  - The maximum allowed time (in game frames) the library can wait before receiving file parts. After this delay, the receiver will send a retry request for each missing file part.
  - Default value is `30` (1 second).
- `MAX_RETRIES`
  - The maximum number of retries allowed. After this number of retries, the file transfer is canceled.
  - Default value is `3`.
- `VERBOSE`
  - If `true`, prints a bunch of useful information in the console.
  - Default value is `false`.

<br>

## Functions

### `send (toLocalIndex, modPath, filename)`

Sends a file to a remote player.

Params:
- `toLocalIndex`: `integer` - Local index of the player to send the file to. If set to `0`, sends to all players instead.
- `modPath`: `string` - Name of the ModFS.
- `filename`: `string` - Name of the file to send.

Returns:
- `boolean` - `true` on success.

```lua
-- Send file at modPath/filename to a remote player
fileshare.send(toLocalIndex, modPath, filename)
```

<br>

### `receive ()`

Receives files.

Returns:
- `list<File>` - Successfully received files. Each file has the following fields: `modPath: string`, `filename: string`, `size: integer`, `data: table`.
- `list<File>` - Pending files which are being downloaded. Each pending file has the following fields: `modPath: string`, `filename: string`, `size: integer`, `completion: number`.

```lua
-- Receive files during a HOOK_UPDATE
hook_event(HOOK_UPDATE, function ()
    local receivedFiles, pendingFiles = fileshare.receive()

    for _, pendingFile in ipairs(pendingFiles) do
        -- pending files...
    end

    for _, receivedFile in ipairs(receivedFiles) do
        -- received files...
    end
end)
```

<br>

### `save (f, destFilename)`

Saves file `f` to ModFS at path `destFilename`.

Params:
- `f`: `File` - File received from the `receive` function.
- `destFilename`: `string` [Optional] - Destination filename. If not provided, file will be saved to path `<f.modPath>/<f.filename>`.

Returns:
- `boolean` - `true` on success.

```lua
-- Save files after receiving them in a HOOK_UPDATE
hook_event(HOOK_UPDATE, function ()
    local receivedFiles, _ = fileshare.receive()

    for _, receivedFile in ipairs(receivedFiles) do
        local filename = "<filename>" -- give it a personalized name or keep it default by
                                      -- omitting the filename parameter in the `save` function
        fileshare.save(receivedFile, filename)
    end
end)
```

<br>

### `config.get (name)`

Retrieves the value of the config `name`.

Params:
- `name`: `string` - Name of the config. Allowed names are:
  - `MAX_FILE_SIZE`
  - `MAX_REQUESTS_PER_FRAME`
  - `TIMEOUT_FRAMES`
  - `MAX_RETRIES`
  - `VERBOSE`

Returns:
- `integer|boolean` - Value of config.

```lua
-- Retrieve current value of MAX_FILE_SIZE
local maxFileSize = fileshare.config.get("MAX_FILE_SIZE")
```

<br>

### `config.set (name, value)`

Sets the value for the config `name`.

Params:
- `name`: `string` - Name of the config. Allowed names are:
  - `MAX_FILE_SIZE`
  - `MAX_REQUESTS_PER_FRAME`
  - `TIMEOUT_FRAMES`
  - `MAX_RETRIES`
  - `VERBOSE`
- `value`: `integer|boolean` - Value to set. If it is `nil`, config `name` is restored to default.

```lua
-- Set value of MAX_FILE_SIZE
fileshare.config.set("MAX_FILE_SIZE", 2000000)
```

<br>

## Example

[Airdrop](https://github.com/PeachyPeachSM64/coopdx-libs/tree/master/fileshare/airdrop)

<video controls>
  <source src="cat.mp4" type="video/mp4">
</video>
