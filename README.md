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

### Starting fresh: open the ready-made game file

`starter.project.json` builds a complete place file with every script plus a ground and spawn point already in it:

    rojo build starter.project.json -o LondonSimulator.rbxlx

Open it in Studio (double-click it, or **File → Open from File**) and press **Play**. Use this only to start a brand-new place. Once you've built a map, update the code with the installer below so your map isn't replaced.

### Install (or update) the game code

1. Open Roblox Studio, click **New**, pick **Baseplate**.
2. Open [INSTALL.luau](INSTALL.luau) on GitHub and click the **Copy raw file** button (two overlapping squares, top-right of the code).
3. In Studio, open the **Command Bar**: **View** tab → **Command Bar** (in newer Studio it may be under the **Window** menu). A long box appears at the bottom of the screen.
4. Click in that box, paste (Ctrl+V, or Cmd+V on a Mac) and press **Enter**.
5. The **Output** window (View tab → Output) says *London Simulator installed 5 scripts*.

Whenever the code changes, do steps 2–4 again. It replaces the old scripts with the new ones.

### Test it

Press **Play**. After a few seconds you should see **£500** in the top-right corner.

A yellow warning about saving in Output is normal until you turn on saving (below).

To see a paycheque straight away, change `PaychequeIntervalSeconds` in **Config** (ReplicatedStorage → Shared → Config) to `10`. A green **+£100** pops up and your cash goes up. Set it back to `300` when you're done.

If something doesn't work, check the **Output** window. Errors show in red. Copy them back to Claude.

### Turn on saving (once)

1. **File → Publish to Roblox**, call it *London Simulator*.
2. Open **Game Settings** (Home tab) → **Security** → turn on **Enable Studio Access to API Services** → **Save**.

### Where everything goes

The installer does this for you, but if you ever add a script by hand, every file in `src/` becomes one script in Studio.

| Folder in this repo | Folder in Studio |
| --- | --- |
| `src/shared` | ReplicatedStorage → **Shared** |
| `src/server` | ServerScriptService → **Server** |
| `src/client` | StarterPlayer → StarterPlayerScripts → **Client** |

| File ends in | Script type |
| --- | --- |
| `.server.luau` | **Script** |
| `.client.luau` | **LocalScript** |
| `.luau` (anything else) | **ModuleScript** |

The name in Studio is the file name without the ending: `Main.server.luau` → `Main`.

After changing anything in `src/`, rebuild the installer with `python3 tools/build_installer.py`.

## Switching to Rojo later

This repo is already laid out the way [Rojo](https://rojo.space) expects (see `default.project.json`), so nothing needs moving:

1. Install the Rojo extension in VS Code and the Rojo plugin in Studio.
2. In Studio, delete the **Shared**, **Server** and **Client** folders the installer made, so there aren't two copies.
3. Run `rojo serve` in this folder and click **Connect** in the Studio plugin.

Rojo only syncs code. The map and models stay in the published Studio place.
