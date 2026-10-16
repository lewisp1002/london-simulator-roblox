# London Simulator

A UK driving and roleplay game for Roblox, set in London.

## Roadmap

- [x] **1. Foundation** – money that saves between visits, shown on screen
- [x] **2. Driving** – spawn a right-hand-drive car with UK plates, speedometer in mph, speed limit signs, controls list, and a test town to drive around
- [ ] **3. Main menu and teams** – Drive / Spawn / Change avatar / Invite friends; pick a team: Car, Bus, Emergency or Police
- [ ] **4. Vehicle showroom** – browse vehicles, buy them with money, owned / not owned, customise, spawn
- [ ] **5. Traffic lights and speed cameras**
- [ ] **6. Wanted stars and arrests** – running red lights and getting caught by speed cameras earns stars (shown above your head); police players can arrest you, and you go to prison for 2 minutes
- [ ] **7. Police job** – find NPC criminals, arrest them and take them back to the prison for money
- [ ] **8. Taxi job** – pick up NPC passengers and drive them where they want to go
- [ ] **9. Bus job** – double-deckers, routes, stops and timetables
- [ ] **10. Emergency callouts** – ambulance and police incidents ("Press T to respond")
- [ ] **11. Minimap and in-game clock**
- [ ] **12. Daily rewards** – a reward for each day you play, 30 days
- [ ] **13. Shop** – money packs and game passes for Robux, redeem codes

Art (not code, built in Studio or Blender, or found on the Creator Store):

- [ ] **The London map** – real streets and landmarks to replace the test town
- [ ] **Vehicle models** – proper cars, buses, police cars and ambulances

## Getting the code into Roblox Studio

### Starting fresh: open the ready-made game file

`starter.project.json` builds a complete place file with every script plus a ground and spawn point already in it:

    rojo build starter.project.json -o LondonSimulator.rbxlx

Open it in Studio (double-click it, or **File → Open from File**) and press **Play**. Use this only to start a brand-new place. Once you've built a map, update the code with the installer below so your map isn't replaced.

### Install (or update) the game code

1. Open Roblox Studio, click **New**, pick **Baseplate**.
2. Open [INSTALL.luau](INSTALL.luau) on GitHub and click the **Copy raw file** button (two overlapping squares, top-right of the code).
3. In Studio, open the **Command Bar**: **Window** menu (top of the screen) → **Command Bar**. In older Studio it's on the **View** tab. A long box appears at the bottom of the screen.
4. Click in that box, paste (Ctrl+V, or Cmd+V on a Mac) and press **Enter**.
5. The **Output** window (**Window** → **Output**) says *London Simulator installed … scripts*.

Whenever the code changes, do steps 2–4 again. It replaces the old scripts with the new ones.

Once per place, switch on Roblox's best lighting (code isn't allowed to change it): in **Explorer** click **Lighting**, then in **Properties** set **Technology** to **Future**. The ready-made game file already has this.

### Test it

Press **Play**. After a few seconds you should see **£500** in the top-right corner, and you'll be standing in a park in the middle of the test town.

Click **🚗 Spawn car** to get in a car. Drive with **W A S D** (or the arrow keys), get out with **Space**. Walk up to your car and press **E** to drive it again; anyone can press **F** to ride as your passenger.

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
