# Template files for Character Select with ModFS

The following is a guide for creating ModFS compatible characters that can be used with this mod.

## Character directory

- First, create a directory with your character's name (without spaces).

## Actor files, textures and sounds

- In this directory, copy and paste your character `actors`, `textures` and `sound` directories.

The directory should now look like this:

```
character-name/
    actors/
        character_geo.bin
        character_cap_geo.bin
        character_wing_cap_geo.bin
        character_metal_cap_geo.bin
        character_winged_metal_cap_geo.bin
    textures/
        character-icon.tex
    sound/
        character_sound_1.ogg
        character_sound_2.ogg
        ...
```

## `template.json`

- This file describes your character. Copy this file and `properties.json` in your character directory. DO NOT edit `properties.json`.

The directory should now look like this:

```
character-name/
    actors/
        character_geo.bin
        character_cap_geo.bin
        character_wing_cap_geo.bin
        character_metal_cap_geo.bin
        character_winged_metal_cap_geo.bin
    textures/
        character-icon.tex
    sound/
        character_sound_1.ogg
        character_sound_2.ogg
        ...
    template.json
    properties.json
```

Here is a complete view of the template file:

> The character information.<br>
> The following fields are the same as the ones passed to [`charSelect.character_add`](https://github.com/Squishy6094/character-select-coop/wiki/API-Documentation#character_add).
```json
"name": "Character name",
"description": "Character description",
"credit": "Made by this character's author",
"color": {"r": 255, "g": 255, "b": 255},
"baseChar": "CT_MARIO",
"camScale": 1.0,
```

> The base model of the character.<br>
> Must be a filepath to the `.bin` geo file.
```json
"model": "actors/character_geo.bin",
```

> The character icon.<br>
> Must be a filepath to the `.tex` texture file.
```json
"icon": "textures/character-icon.tex",
```

> The character's palette.<br>
> Each color is a string representing an RRGGBB hex color, for example: `"FF0000"` (red).
```json
"palette": {
    "PANTS": "RRGGBB",
    "SHIRT": "RRGGBB",
    "GLOVES": "RRGGBB",
    "SHOES": "RRGGBB",
    "HAIR": "RRGGBB",
    "SKIN": "RRGGBB",
    "CAP": "RRGGBB"
},
```

> The character's caps models.<br>
> Each entry must be a filepath to the corresponding `.bin` geo file.
```json
"caps": {
    "normal": "actors/character_cap_geo.bin",
    "wing": "actors/character_wing_cap_geo.bin",
    "metal": "actors/character_metal_cap_geo.bin",
    "metalWing": "actors/character_winged_metal_cap_geo.bin"
},
```

> The character's voice clips.<br>
> Each character sound must be a filepath or an array of filepaths to audio files.<br>
> The format is the same as the voice table passed to [`charSelect.character_add_voice`](https://github.com/Squishy6094/character-select-coop/wiki/API-Documentation#character_add_voice).<br>
> Check all available character [sounds](https://github.com/coop-deluxe/sm64coopdx/blob/main/docs/lua/constants.md#enum-CharacterSound).
```json
"voices": {
    "CHAR_SOUND_NAME": "sound/char_sound_file.ogg"
}
```

## ModFS

- Finally, once the template is properly filled:
  - Zip all files into an archive named `character-name.zip` (replace character-name with your character's name) and change the extension to `.modfs`
  - Make sure there is no `character-name` directory at the root of the archive! It should look like this:
    ```
    character-name.modfs/
        actors/
            character_geo.bin
            character_cap_geo.bin
            character_wing_cap_geo.bin
            character_metal_cap_geo.bin
            character_winged_metal_cap_geo.bin
        textures/
            character-icon.tex
        sound/
            character_sound_1.ogg
            character_sound_2.ogg
            ...
        template.json
        properties.json
    ```
  - Put the file in your `%AppData%/sm64coopdx/sav` directory.
- Now, load the game with this mod and Character Select and enter the command `/loadchar character-name`.<br>It will load your character into Character Select and send it to other players as well.

## Troubleshooting

- Due to a bug in Character Select, characters loaded after mod initialization don't appear immediately. To fix it, open the Character Select menu and press the <kbd>R</kbd> button twice.
