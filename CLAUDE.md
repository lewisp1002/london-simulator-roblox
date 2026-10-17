# London Simulator

A UK driving and roleplay game for Roblox, set in London, inspired by Birmingham Vehicle Simulator: realistic cars, UK roads, jobs (taxi, bus, police, ambulance), wanted stars and arrests. The roadmap is in README.md.

## Who you're working with

The owner is new to Roblox Studio and coding, works on a Mac, and is in the UK. Explain things in plain words, give click-by-click steps, and show results (screenshots, what to press) rather than theory. They care most about the game looking as real as Birmingham Vehicle Simulator.

## Layout

The repo follows Rojo's layout (`default.project.json`), so every file maps to one script in Studio:

| Folder | In Studio |
| --- | --- |
| `src/shared` | ReplicatedStorage → Shared |
| `src/server` | ServerScriptService → Server |
| `src/client` | StarterPlayer → StarterPlayerScripts → Client |

`.server.luau` is a Script, `.client.luau` a LocalScript, any other `.luau` a ModuleScript; the name is the file name without the ending.

The game copies Birmingham Vehicle Simulator's flow and look; `docs/BVS-NOTES.md` has what we saw when we played it (menus, HUD, scale, roads) and how London maps onto it.

- `Main.server.luau` starts everything: lighting, player data, the test town, traffic lights, cars, the garage, and a placeholder paycheque.
- `PlayerData` saves cash, owned vehicles and paint picks in a DataStore, and mirrors them as player attributes (`Cash`, `Owned_<id>`, `Paint_<id>`) for the UI. A failed load never overwrites a real save.
- `shared/Vehicles` lists every vehicle (made-up names, team, price, speed, body style, livery). `CarBuilder` builds them from parts: cars, black cab, buses, Battenburg police and ambulance. `Cars` spawns them at the team's depot (`Workspace.Depots.<team>` with `Spawn` parts), ghosts them for a few seconds, runs lights and indicators, and builds display copies in `ReplicatedStorage.VehicleModels` for the menus.
- `Garage` handles teams, buying and paint. `Remotes` makes all RemoteEvents in `ReplicatedStorage.Remotes`, plus `Remotes.notify` for pop-up messages.
- Client: `Ui` (shared look, settings, toasts), `Menu` (main menu, team picker, vehicle picker filmed at the depot, customise), `Hud` (Menu button, settings, shop, cash), `Dashboard` (speed, limit, clock, minimap, controls list), `Driving` (arcade handling, only for cars with the `ArcadeHandling` attribute, so bought A-Chassis cars keep their own scripts), `VehicleLights`, `MapLife` (big wheel, Belisha beacons).
- `TestTown` builds a stand-in London at runtime (about 3,000 studs, BVS scale) from `TownKit`, `TownProps` and `TownBuildings`, and writes `ReplicatedStorage.MapInfo` (menu camera, showroom spots, minimap roads). A hand-built map needs the same `MapInfo` and `Workspace.Depots`. Turn it off with `Config.BuildTestTown` once a real map is in. Parts over 2048 studs get clamped by Roblox, so use `TownKit.tiles` for big areas.
- `TrafficLights` runs every model tagged `TrafficLight`; `LightingSetup` sets a bright British day. `Lighting.Technology = Future` can't be set from code, so it's set in the place file.
- All tuning numbers live in `src/shared/Config.luau`.

## Getting code into Studio

In order of preference:

1. **Roblox Studio MCP** (Studio → Assistant → … → Manage MCP Servers → Enable Studio as MCP server), when this session runs on the same computer as Studio. Write scripts with `multi_edit` in the same places as the table above, then playtest with `start_stop_play`, `get_console_output` and `screen_capture` to check it actually works. Keep `src/` in this repo in sync with what's in Studio; the repo is the source of truth.
2. **`INSTALL.luau`**: one block pasted into Studio's Command Bar (Window → Command Bar) that creates or replaces every script. Regenerate it with `python3 tools/build_installer.py` after any change to `src/`.
3. **`starter.project.json`**: `rojo build starter.project.json -o LondonSimulator.rbxlx` builds a fresh place with the scripts, ground, spawn and Future lighting. Use it only for a brand-new place, because it doesn't contain the owner's map.

Playtesting through screen control: after typing in the Command Bar, click the game view twice before pressing keys, or Studio keeps the keyboard. Hold Space or F for about 0.3 s, since a tap is too short to register.

## Checks before committing

- Type-check in strict mode with luau-lsp and Roblox's type definitions: `rojo sourcemap default.project.json -o sourcemap.json`, then `luau-lsp analyze --definitions=<globalTypes.d.luau> --sourcemap=sourcemap.json --base-luaurc=<file containing {"languageMode": "strict"}> src/`. Definitions: https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
- With Studio MCP, also playtest and read the Output for errors.

## Rules

- **No real brands in the published game.** No car makers, logos, shop names, "Metropolitan Police" or "NHS". Use made-up names (the reference game calls its BMW-like car "Bayron"). Bought models with real badges get renamed and re-textured.
- **Check every script in bought or free models** for backdoors (`require` of an asset ID, `loadstring`, `getfenv`, HTTP calls, obfuscated text) before it goes in the game.
- **Bought 3D models (CGTrader etc.) mustn't be redistributed.** Never upload them to the Creator Store as public, never commit their files to this repo, and keep the place uncopyable.
- Code comments are short and plain, written for a beginner reading them in Studio. UK spelling in anything players see.

## Shopping list

Candidate car models, maps and street furniture, with prices and notes: https://claude.ai/artifact/BEuTgBs6FoNSv9hETfoDkJ (private to the owner). Current suggestion: start with the CGTrader "Generic Police Hatchback v4" ($59), convert it (simplify for phones, separate wheels, fix materials), import it with Studio's 3D Importer, and make it drivable.
