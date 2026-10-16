# London Simulator

A UK driving and roleplay game for Roblox, set in London.

## Roadmap

- [x] **1. Foundation** – money that saves between visits, shown on screen
- [ ] **2. Driving** – spawn a car and drive it, speedometer in mph, speed limits
- [ ] **3. The map** – London streets and landmarks (built in Studio)
- [ ] **4. Taxi job** – pick up NPC passengers and drive them where they want to go
- [ ] **5. Bus job** – double-deckers, routes, stops and timetables
- [ ] **6. Emergency services** – police, ambulance and fire callouts ("Press T to respond")
- [ ] **7. Road rules** – speeding and red lights, with police that come after you
- [ ] **8. Vehicle shop and wraps**
- [ ] **9. Minimap and in-game clock**

## Getting the code into Roblox Studio

### One-time setup

1. Open Roblox Studio, click **New**, pick **Baseplate**.
2. **File → Publish to Roblox**, call it *London Simulator*. Saving player data only works once the game is published.
3. Open **Game Settings** (Home tab) → **Security** → turn on **Enable Studio Access to API Services** → **Save**.
4. On the **View** tab, turn on **Explorer**, **Properties** and **Output**.

### How files map to Studio

Every file in `src/` becomes one script in Studio.

**The folder decides where it goes:**

| Folder in this repo | Folder in Studio |
| --- | --- |
| `src/shared` | ReplicatedStorage → **Shared** |
| `src/server` | ServerScriptService → **Server** |
| `src/client` | StarterPlayer → StarterPlayerScripts → **Client** |

**The ending decides what type of script:**

| File ends in | Make a |
| --- | --- |
| `.server.luau` | **Script** |
| `.client.luau` | **LocalScript** |
| `.luau` (anything else) | **ModuleScript** |

**The name** is the file name without the ending: `PlayerData.luau` → `PlayerData`, `Main.server.luau` → `Main`.

Names are case-sensitive: `Shared`, not `shared`.

### Adding a script

1. In Explorer, hover over where it goes and click the **⊕** button.
2. Pick the type (Folder, Script, LocalScript or ModuleScript).
3. Rename it (right-click → Rename, or F2).
4. Double-click it, delete everything in it, and paste in the file.

Make the three folders (**Shared**, **Server**, **Client**) first.

### Current files

| File | In Studio |
| --- | --- |
| `src/shared/Config.luau` | ModuleScript **Config** in ReplicatedStorage → Shared |
| `src/shared/Format.luau` | ModuleScript **Format** in ReplicatedStorage → Shared |
| `src/server/PlayerData.luau` | ModuleScript **PlayerData** in ServerScriptService → Server |
| `src/server/Main.server.luau` | Script **Main** in ServerScriptService → Server |
| `src/client/Hud.client.luau` | LocalScript **Hud** in StarterPlayer → StarterPlayerScripts → Client |

### Testing

Press **Play**. You should see **£500** in the top-right corner.

To see a paycheque straight away, change `PaychequeIntervalSeconds` in **Config** to `10`. A green **+£100** pops up and your cash goes up. Set it back to `300` when you're done.

If something doesn't work, check the **Output** window. Errors show in red. Copy them back to Claude.

## Switching to Rojo later

This repo is already laid out the way [Rojo](https://rojo.space) expects (see `default.project.json`), so nothing needs moving:

1. Install the Rojo extension in VS Code and the Rojo plugin in Studio.
2. Delete the scripts you pasted in by hand, so there aren't two copies.
3. Run `rojo serve` in this folder and click **Connect** in the Studio plugin.

Rojo only syncs code. The map and models stay in the published Studio place.
