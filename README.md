# Space Conquest

Roblox game managed with [Rojo](https://rojo.space). The source of truth is `src/` + `default.project.json`.

## Layout

| Folder | Roblox location |
| --- | --- |
| `src/ServerScriptService` | Server scripts (`*.server.luau`) and server modules |
| `src/ReplicatedStorage` | Shared modules (ship classes, weapons, fittings, skies) |
| `src/StarterPlayer/StarterPlayerScripts` | Client scripts (`*.client.luau`) and client modules |
| `src/Workspace` | Map / models, stored as `.rbxm` |
| `src/Lighting` | Lighting effects (`.model.json`) |

Service properties (Lighting, etc.) live in `default.project.json` under `$properties`.

File naming: `Name.server.luau` = Script, `Name.client.luau` = LocalScript, `Name.luau` = ModuleScript.

## Working in Studio

1. Install Rojo: `rokit install` (uses `rokit.toml`), or `cargo install rojo --version 7.7.0`.
2. Install the Rojo plugin in Studio: `rojo plugin install`.
3. From this folder run `rojo serve`, then click **Connect** in the Rojo plugin.

Script edits in `src/` sync live into Studio. Edits made to scripts inside Studio are **not** written
back automatically, so make code changes in the files here.

If you change models/map in Studio, save the place to a file and pull the changes back with:

```sh
rojo syncback --input path/to/place.rbxl
```

## Build a place file

```sh
rojo build -o build/spaceconquest.rbxl
```
