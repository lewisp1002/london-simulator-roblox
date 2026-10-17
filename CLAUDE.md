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

- `Main.server.luau` starts everything: lighting, player data, cars, the test town, and a placeholder paycheque.
- `PlayerData` saves cash in a DataStore. A failed load never overwrites a real save.
- `Cars` builds the placeholder block car, spawns it, and gives the driver network ownership. `Driving.client.luau` drives only cars with the `ArcadeHandling` attribute, so bought A-Chassis cars keep their own scripts.
- `Speedometer.client.luau` shows mph, reading the speed limit from the `SpeedLimit` attribute on road parts.
- `TestTown` builds a stand-in street grid at runtime. Turn it off with `Config.BuildTestTown` once a real map is in.
- `LightingSetup` sets grey British daylight. `Lighting.Technology = Future` can't be set from code, so it's set in the place file.
- All tuning numbers live in `src/shared/Config.luau`.

## Getting code into Studio

In order of preference:

1. **Roblox Studio MCP** (Studio → Assistant → … → Manage MCP Servers → Enable Studio as MCP server), when this session runs on the same computer as Studio. Write scripts with `multi_edit` in the same places as the table above, then playtest with `start_stop_play`, `get_console_output` and `screen_capture` to check it actually works. Keep `src/` in this repo in sync with what's in Studio; the repo is the source of truth.
2. **`INSTALL.luau`**: one block pasted into Studio's Command Bar (Window → Command Bar) that creates or replaces every script. Regenerate it with `python3 tools/build_installer.py` after any change to `src/`.
3. **`starter.project.json`**: `rojo build starter.project.json -o LondonSimulator.rbxlx` builds a fresh place with the scripts, ground, spawn and Future lighting. Use it only for a brand-new place, because it doesn't contain the owner's map.

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
