# Birmingham Vehicle Simulator: what we're matching

Notes from playing BVS on 17 October 2026, to guide how London Simulator looks and plays. We copy the *ideas and feel*, never their models, images, names or code. Everything in our game is built by us with made-up names.

## How a session flows

1. **Main menu** over a blurred, darkened live view of the city. Logo top-centre, three big cards (Drive, Spawn, Close), two wide buttons under them (Change avatar, Invite friends).
2. **Drive → Select Your Team**: three tall cards with a showroom render of the team's vehicles, an icon + title + one-line description, and a "Current Members · N players" strip of avatar headshots under each card.
   - Car: "Compete in races & provide taxi services"
   - Bus: "Operate routes & transport passengers"
   - Emergency: "Respond to incidents & assist the public" (police cars *and* ambulances)
3. **Vehicle picker** (per team), filmed live in the world: a petrol station forecourt for cars, a city-centre street for emergency. Big vehicle name bottom-left with "Owned" (green) or price, tabs *All / Owned / Not owned* with counts, "Vehicles owned 6 / 23", buttons **Customise** (dark) and **Spawn** (white) or **Buy · price**. A carousel of dark cards along the bottom: render on black, green "✓ Owned" badge or price with a coin icon, ⚡ after electric cars. A gamepass promo card on the left.
4. **Customise**: bottom sheet, tabs Body Colour / Wheel Colour / Window Tints, plus a PRO group (Body Wraps, Underglow, Licence Plate). Row of colour swatches. "Every pick saves straight away". Reset / Back to vehicles.
5. **Spawn** puts you in the car straight away. New cars are ghosts for a few seconds, then a toast says "Collisions on".
6. **Menu** (top-left) asks "Return to the menu? Your vehicle will be despawned" with Stay / Return to menu.

## HUD

- Top-left: Roblox buttons, then a "☰ Menu" pill.
- Top-right: settings cog, shop trolley, money pill ("866 Points" with a coin stack icon).
- Bottom-left, while driving: **minimap panel** (dark, rounded, see-through). Speed big ("59 mph") top-left, the speed-limit roundel next to it, day + time ("Sat 13:49") top-right. Roads drawn as light grey lines over a dark map with building outlines; you're a white arrow, other players blue dots.
- Above the minimap: **callout card** with a countdown bar, e.g. "Graffiti · Grand Central Back · Press [key] to respond". The job location is a red circle marker floating in the world with the distance under it ("1.56 mi").
- Right: **controls list**: label on the left, key in an outlined pill on the right. Swaps to gamepad buttons when you use a controller. Keyboard list: Camera 1-2, Indicators Q-E, Hazards B, Parking Brake Space, Mouse Steering R, Engine M, Horn H, Steering WASD, Jump (get out) F, Taxi Mode T, Lights L, Car Music G. Police adds Switch Siren.
- Toasts: dark card top-centre with a coloured dot, title, one line of text and a progress bar.
- Name tags over players: dark pill with their avatar headshot and name.

## Shop and settings

- Shop: dark modal, tabs Home / Products / Passes / Subscription / Redeem Codes. Points packs (200, 750, 1,000 … 4,500), vehicle passes with round badge art.
- Settings: list of toggles (green when on): Satnav Mute, Shadows, Live Time, Driver Tags, Rain, Radio Mute, Auto Handbrake Release, Enhanced Lighting, Team Uniforms.
- Money is earned slowly just by playing, and from jobs.

## Look and style

- Font: geometric sans (Montserrat-style), white text, regular weight for big titles.
- Panels: near-black (#111318-ish) at ~85% opacity, 12–16 px corners, thin lighter border, no heavy shadows.
- Accent colours from the logo stripes: blue (walk), pink/magenta (car), coral red (bus). Green for "owned"/on.

## Jobs and money

- Emergency players get **callouts** one after another: "Graffiti", "Bus Incident", "Wanted Person", each with a place name ("Grand Central Back", "Jewellery Quarter", "Bull St The Cube"). The card shows how long you have to accept, and the minimap gets a red dot.
- Drive to the red marker → toast "Task completed — Congratulations, you have been awarded with points!" → about **+90 points**.
- A few points (+4) trickle in just for playing, shown as a small blue "+4" pill under the money.
- Some buildings have interiors you can walk into (the police station has corridors, doors and a yard with police cars and ambulances).

## The world

- **Scale**: callouts were 1–1.5 miles away, and crossing from the city centre to the edge took a couple of minutes at 50–90 mph. The map is roughly 2–3 miles across, about **10,000–15,000 studs** (1 mile ≈ 5,750 studs). Our first test town was 600 studs, so about 1/20th as wide.
- Lanes are about 12 studs wide and pavements 10–14 studs. Floors are about 12 studs tall, and buildings run from 3 to 15 storeys.
- Areas: city centre, inner ring road, residential and industrial edges, parks and woodland with tall conifers.
- **Roads**: grainy grey tarmac, crisp white markings: dashed centre lines, give-way lines, painted turn arrows, hatched areas, parking bays, zig-zags at crossings, double yellows. Dual carriageways with grass central reservations and hedges.
- **Junctions**: UK traffic lights (black heads on grey poles, red/amber/green), keep-left signs on islands with yellow/black bollards, pedestrian crossings.
- **Street furniture**: black/white bollards, black railings and blue bridge railings, benches, bins, tall grey lamp posts, bus shelters, green and blue direction signs (map-style roundabout diagrams), yellow speed cameras, roadworks (ROAD CLOSED signs, orange barriers, cones), billboards.
- **Buildings**: proper textured models, not blocks. Glass office towers, concrete 60s towers, a round tower, red-brick terraces and flats, red-brick warehouses, a high street with coloured shop fascias, a multi-storey "CAR PARK", a petrol station with a mini-market.
- **Cars**: detailed real-looking models with made-up names (Valkora, Bayron, Luxor, Autora, Nordic, Javelin, Wolfhart, Kaltblut, Kairo, Setra, Electra), UK plates (yellow back, white front, local prefixes), underglow, police Battenburg livery, yellow-green ambulances, red double-deckers, black cabs.
- **Life**: NPC pedestrians on pavements, other players' cars everywhere.

## What this means for London Simulator

| BVS | London Simulator |
| --- | --- |
| Birmingham city centre, Grand Central, Rotunda-style tower | Westminster/Southbank-style centre: a clock tower, a big wheel, a river with bridges, red phone and post boxes, black cabs |
| Red Birmingham buses | Red London double-deckers with route numbers, "bus stop" flags with the roundel-style sign (made-up operator name) |
| West Midlands police | Made-up "London Police" (no Met branding), Battenburg livery |
| Petrol station showroom | Same idea, at a London forecourt |
| BX plates | London LA–LY plates (already in `Cars.randomPlate`) |
| Points | Pounds (£), which we already show |
