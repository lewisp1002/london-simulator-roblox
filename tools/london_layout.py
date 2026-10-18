"""Designs the London map's roads and writes them out for the game.

Run it with:  python3 tools/london_layout.py      (needs shapely and Pillow: pip install shapely pillow)
It writes:
  src/server/LondonLayout.luau   the road network as data (RoadNetwork builds it in the game)
  src/server/LondonFill.luau     every building, garden, wall and tree (made by london_fill.py)
  docs/map-layout.png            a picture of the roads, and docs/map-fill.png with the buildings
and prints any problems it finds (roads crossing without a junction, junctions too close together).

The map is compact and packed, like Birmingham Vehicle Simulator: about 5,400 by 4,600 studs, with no
empty fields. The main roads are drawn by hand below (a dual carriageway ring road round the West End and
the City, the Thames with four bridges, high streets and avenues). Then every big block between them is
filled with back streets in a grid, the way real terraced streets are laid out, and london_fill.py lines
every street with buildings.

Coordinates are in studs: x runs west to east, z runs north to south (north is -z), y is height.
"""

from __future__ import annotations

import math
import random
import sys
from dataclasses import dataclass, field
from pathlib import Path

from shapely.geometry import LineString, MultiLineString, Point, Polygon, box as shape_box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent

# The whole map's outline is OUTLINE (below). Roads stay inside it; the strip round the outside is filled
# with buildings and trees so you never see the edge of the world.

# ---------------------------------------------------------------------------------------------
# Road types. Widths in studs (a lane is about 12 studs, like Birmingham Vehicle Simulator).
#   lanes: lanes each way, parking: a strip along each kerb where cars park
#   res: central reservation width (dual carriageways), edge: tarmac outside the edge line
#   side: "pavement" or "verge" beyond the kerb, sideWidth: how wide
# ---------------------------------------------------------------------------------------------
PROFILES = {
    # Wide, like BVS: even the back streets have room for a car parked each side and two passing
    "back": dict(lanes=1, lane=14, parking=9, res=0, shoulder=0, edge=0, side="pavement", sideWidth=12, limit=20, rank=0),
    "street": dict(lanes=1, lane=15, parking=9, res=0, shoulder=0, edge=0, side="pavement", sideWidth=13, limit=30, rank=1),
    "main": dict(lanes=1, lane=16, parking=9, res=0, shoulder=0, edge=0, side="pavement", sideWidth=15, limit=30, rank=2),
    "high": dict(lanes=1, lane=16, parking=9, res=0, shoulder=0, edge=0, side="pavement", sideWidth=20, limit=20, rank=2),
    "dual": dict(lanes=2, lane=14, parking=0, res=16, shoulder=0, edge=0, side="pavement", sideWidth=15, limit=40, rank=3),
    # A big dual carriageway like the North and South Circular: two wide lanes each way and a broad grassy
    # central reservation with trees, and a grass verge before the pavement. Big roundabouts at junctions.
    "arterial": dict(lanes=2, lane=15, parking=0, res=28, shoulder=0, edge=1, side="pavement", sideWidth=20, limit=50, rank=4),
}


def half_width(profile: dict) -> float:
    """Distance from the middle of the road to the kerb."""
    if profile.get("oneway"):
        return profile["lanes"] * profile["lane"] / 2 + profile["edge"]
    return profile["res"] / 2 + profile["lanes"] * profile["lane"] + profile.get("parking", 0) + profile["shoulder"] + profile["edge"]


def outer_width(profile: dict) -> float:
    """Distance from the middle of the road to the back of the pavement."""
    return half_width(profile) + profile["sideWidth"]


# ---------------------------------------------------------------------------------------------
# Geometry: rounded paths through control points (matches RoadKit.path in the game exactly)
# ---------------------------------------------------------------------------------------------

def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def mul(a, s):
    return (a[0] * s, a[1] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def length(a):
    return math.hypot(a[0], a[1])


def unit(a):
    l = length(a)
    return (a[0] / l, a[1] / l) if l > 1e-9 else (0.0, 0.0)


def left_of(d):
    """The direction 90 degrees to the left of d (x east, z south): north-facing d=(0,-1) gives west (-1,0)."""
    return (d[1], -d[0])


def fillet_path(points, radius, max_step=math.radians(6)):
    """A path through `points` (x, z, y) with corners rounded to `radius`.
    Returns (samples, dist, stations): samples are (x, z), dist the distance along the path to each sample,
    and stations[i] the distance along the path that control point i belongs to."""
    pts = [(p[0], p[1]) for p in points]
    n = len(pts)
    out = [pts[0]]
    control_at = [0]
    for i in range(1, n - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        d1, d2 = unit(sub(b, a)), unit(sub(c, b))
        turn = math.acos(max(-1.0, min(1.0, dot(d1, d2))))
        if turn < math.radians(0.5):
            out.append(b)
            control_at.append(len(out) - 1)
            continue
        t = radius * math.tan(turn / 2)
        limit = 0.48 * min(length(sub(b, a)), length(sub(c, b)))
        r = radius
        if t > limit:
            t = limit
            r = t / math.tan(turn / 2)
        start = sub(b, mul(d1, t))
        end = add(b, mul(d2, t))
        side = left_of(d1)
        towards = side if dot(side, d2) > 0 else mul(side, -1)
        centre = add(start, mul(towards, r))
        a0 = math.atan2(start[1] - centre[1], start[0] - centre[0])
        a1 = math.atan2(end[1] - centre[1], end[0] - centre[0])
        sweep = a1 - a0
        while sweep > math.pi:
            sweep -= 2 * math.pi
        while sweep < -math.pi:
            sweep += 2 * math.pi
        steps = max(1, math.ceil(abs(sweep) / max_step))
        out.append(start)
        mid_index = None
        for k in range(1, steps):
            ang = a0 + sweep * k / steps
            out.append((centre[0] + r * math.cos(ang), centre[1] + r * math.sin(ang)))
            if k == steps // 2:
                mid_index = len(out) - 1
        out.append(end)
        control_at.append(mid_index if mid_index is not None else len(out) - 1)
    out.append(pts[-1])
    control_at.append(len(out) - 1)
    dist = [0.0]
    for k in range(1, len(out)):
        dist.append(dist[-1] + length(sub(out[k], out[k - 1])))
    stations = [dist[i] for i in control_at]
    return out, dist, stations


def point_at(samples, dist, s):
    """Position and direction at distance s along a sampled path."""
    s = max(0.0, min(dist[-1], s))
    for k in range(1, len(samples)):
        if dist[k] >= s or k == len(samples) - 1:
            seg = dist[k] - dist[k - 1]
            f = 0 if seg < 1e-9 else (s - dist[k - 1]) / seg
            p = add(samples[k - 1], mul(sub(samples[k], samples[k - 1]), f))
            return p, unit(sub(samples[k], samples[k - 1]))
    return samples[-1], unit(sub(samples[-1], samples[-2]))


# ---------------------------------------------------------------------------------------------
# The network
# ---------------------------------------------------------------------------------------------

@dataclass
class Node:
    id: str
    x: float
    z: float
    y: float = 0.0
    kind: str = "junction"  # junction, lights, roundabout, mini, end
    radius: float = 0.0  # roundabouts: outer kerb radius
    island: float = 0.0  # roundabouts: central island radius
    name: str = ""


@dataclass
class Road:
    id: str
    profile: str
    a: str
    b: str
    via: list = field(default_factory=list)  # (x, z) or (x, z, y)
    radius: float = 120.0
    name: str = ""
    gaps: list = field(default_factory=list)
    laybys: list = field(default_factory=list)  # (side, s0, s1)


nodes: dict[str, Node] = {}
roads: list[Road] = []


def node(id, x, z, kind="junction", radius=0.0, island=0.0, name=""):
    nodes[id] = Node(id, x, z, 0.0, kind, radius, island, name)
    return id


def road(id, profile, a, b, via=(), radius=120.0, name=""):
    r = Road(id, profile, a, b, list(via), radius, name)
    roads.append(r)
    return r


def road_by_id(rid):
    return next(x for x in roads if x.id == rid)


def control_points(r: Road):
    a, b = nodes[r.a], nodes[r.b]
    pts = [(a.x, a.z, a.y)]
    for v in r.via:
        pts.append((v[0], v[1], v[2] if len(v) > 2 else None))
    pts.append((b.x, b.z, b.y))
    last = pts[0][2]
    filled = []
    for p in pts:
        y = p[2] if p[2] is not None else last
        filled.append((p[0], p[1], y))
        last = y
    return filled


def sampled(r: Road):
    pts = control_points(r)
    samples, dist, stations = fillet_path(pts, r.radius)
    return pts, samples, dist, stations


def split_road(rid, nid):
    """Splits road `rid` in two at node `nid` (which sits on it), for a T-junction."""
    r = road_by_id(rid)
    nd = nodes[nid]
    pts = control_points(r)
    best, best_i = 1e18, 1
    for i in range(1, len(pts)):
        p, q = (pts[i - 1][0], pts[i - 1][1]), (pts[i][0], pts[i][1])
        seg = sub(q, p)
        L2 = seg[0] ** 2 + seg[1] ** 2
        f = max(0, min(1, ((nd.x - p[0]) * seg[0] + (nd.z - p[1]) * seg[1]) / L2))
        d = length(sub(add(p, mul(seg, f)), (nd.x, nd.z)))
        if d < best:
            best, best_i = d, i

    def away(v):
        return length(sub((v[0], v[1]), (nd.x, nd.z))) > 5

    via_before = [v for v in r.via[: best_i - 1] if away(v)]
    via_after = [v for v in r.via[best_i - 1:] if away(v)]
    taken = {x.id for x in roads}
    k = 2
    while f"{r.id}_{k}" in taken:
        k += 1
    second = Road(f"{r.id}_{k}", r.profile, nid, r.b, via_after, r.radius, r.name)
    r.b = nid
    r.via = via_before
    roads.insert(roads.index(r) + 1, second)
    if best > 25:
        print(f"  note: node {nid} is {best:.0f} studs off road {rid}")


# ---------------------------------------------------------------------------------------------
# The edge of the map: an uneven outline, not a square. Everything outside it is distant city in the haze.
# ---------------------------------------------------------------------------------------------
OUTLINE = [
    (-2650, -1750), (-1950, -2320), (-900, -2500), (250, -2400), (1250, -2540), (2350, -2280), (3080, -1580),
    (3520, -680), (3760, 350), (3720, 1300), (3330, 2280), (2250, 2600), (1000, 2500), (-300, 2700),
    (-1500, 2450), (-2450, 2000), (-2980, 1150), (-3120, 250), (-3020, -850),
]
# Rounded off so the edge curves instead of having corners
OUTLINE_SHAPE = Polygon(OUTLINE).buffer(-260, join_style=1).buffer(260, join_style=1).buffer(220, join_style=1).buffer(-220, join_style=1)
_b = OUTLINE_SHAPE.bounds
MIN_X, MIN_Z, MAX_X, MAX_Z = math.floor(_b[0] / 50) * 50 - 50, math.floor(_b[1] / 50) * 50 - 50, math.ceil(_b[2] / 50) * 50 + 50, math.ceil(_b[3] / 50) * 50 + 50

# ---------------------------------------------------------------------------------------------
# The river Thames, west to east, with a big loop round the Isle of Dogs in the east like the real one
# ---------------------------------------------------------------------------------------------
RIVER_WIDTH = 200
RIVER_RADIUS = 420
RIVER = [
    (-3700, 520), (-2700, 610), (-1750, 750), (-1000, 560), (-300, 450), (500, 430), (1200, 560), (1750, 720),
    (2250, 770), (2560, 1080), (2620, 1580), (2950, 1880), (3290, 1680), (3420, 1100), (3620, 640), (4400, 480),
]
RIVER_WALK = 24  # riverside walk and wall beside each bank

# ---------------------------------------------------------------------------------------------
# Main roads, by hand. They spread out from the middle and curve, like London's, instead of a grid.
# ---------------------------------------------------------------------------------------------

# --- The ring road (dual carriageway) round the West End and the City ---
node("MB", -1850, -1500, "roundabout", radius=82, island=50, name="Marylebone")
node("GP", -1100, -1520, "lights", name="Great Portland Street")
node("EU", -600, -1540, "lights", name="Euston")
node("KX", 350, -1530, "roundabout", radius=82, island=50, name="King's Cross")
node("OS", 1350, -1450, "roundabout", radius=82, island=50, name="Old Street")
node("AG", 1500, -420, "roundabout", radius=82, island=50, name="Aldgate")
node("MA", -1850, -950, "roundabout", radius=72, island=44, name="Marble Arch")
node("HPC", -1850, -160, "roundabout", radius=76, island=46, name="Hyde Park Corner")
road("marylebone", "dual", "MB", "GP", via=[(-1480, -1530)], radius=600, name="Marylebone Road")
road("euston1", "dual", "GP", "EU", name="Euston Road")
road("euston2", "dual", "EU", "KX", via=[(-120, -1570)], radius=700, name="Euston Road")
road("pentonville", "dual", "KX", "OS", via=[(900, -1560)], radius=500, name="Pentonville Road")
road("cityroad", "dual", "OS", "AG", via=[(1480, -950)], radius=500, name="Bishopsgate")
road("parklane", "dual", "MA", "HPC", via=[(-1880, -560)], radius=600, name="Park Lane")
road("edgware", "dual", "MB", "MA", via=[(-1830, -1230)], radius=400, name="Edgware Road")

# --- The Thames bridges and the embankments along the north bank ---
node("CH", -1850, 545, "lights", name="Chelsea")
node("WM", -800, 330, "lights", name="Westminster")
node("BF", 450, 250, "lights", name="Blackfriars")
node("MN", 1150, 350, "junction", name="Monument")
node("TH", 1700, 515, "lights", name="Tower Hill")
node("LE", 2550, 450, "lights", name="Limehouse")
road("millbank", "dual", "CH", "WM", via=[(-1500, 290)], radius=450, name="Millbank")
road("embankment", "dual", "WM", "BF", via=[(-150, 255)], radius=500, name="Victoria Embankment")
road("thames", "main", "BF", "MN", via=[(800, 310)], radius=400, name="Upper Thames Street")
road("thames2", "main", "MN", "TH", via=[(1450, 420)], radius=400, name="Lower Thames Street")
road("highway", "dual", "TH", "LE", via=[(2150, 480)], radius=400, name="The Highway")
road("minories", "dual", "AG", "TH", via=[(1620, 50)], radius=400, name="Minories")

node("CS", -1850, 935, "lights", name="Battersea")
node("WS", -800, 720, "lights", name="Lambeth")
node("BS", 450, 645, "lights", name="Southwark")
node("TS", 1700, 905, "lights", name="Tower Bridge Road")
road("chelseabr", "main", "CH", "CS", name="Chelsea Bridge")
road("westminsterbr", "main", "WM", "WS", name="Westminster Bridge")
road("blackfriarsbr", "main", "BF", "BS", name="Blackfriars Bridge")
road("towerbr", "main", "TH", "TS", name="Tower Bridge")

# --- Westminster and the West End ---
node("TR", -800, -110, "roundabout", radius=64, island=40, name="Trafalgar Square")
node("PC", -950, -560, "lights", name="Piccadilly Circus")
node("OC", -1150, -950, "lights", name="Oxford Circus")
node("TC", -560, -950, "lights", name="Tottenham Court Road")
road("whitehall", "main", "TR", "WM", name="Whitehall")
road("mall", "main", "TR", "HPC", via=[(-1350, -130)], radius=400, name="The Mall")
road("piccadilly", "main", "HPC", "PC", via=[(-1400, -420)], radius=400, name="Piccadilly")
road("haymarket", "main", "PC", "TR", via=[(-880, -330)], radius=250, name="Haymarket")
road("regent", "main", "OC", "PC", via=[(-1080, -760)], radius=260, name="Regent Street")
road("oxford1", "high", "MA", "OC", via=[(-1500, -975)], radius=600, name="Oxford Street")
road("oxford2", "high", "OC", "TC", via=[(-850, -935)], radius=600, name="Oxford Street")
road("portland", "main", "OC", "GP", via=[(-1120, -1250)], radius=400, name="Portland Place")
road("tcr", "main", "TC", "EU", via=[(-590, -1250)], radius=400, name="Tottenham Court Road")
road("charing", "main", "TR", "TC", via=[(-640, -520)], radius=300, name="Charing Cross Road")
road("sloane", "main", "HPC", "CH", via=[(-1880, 200)], radius=500, name="Sloane Street")

# --- Holborn and the City ---
node("HB", 250, -900, "lights", name="Holborn")
node("AW", 200, -170, "lights", name="Aldwych")
node("SP", 700, -230, "lights", name="St Paul's")
node("BK", 1000, -520, "lights", name="Bank")
road("holborn", "main", "TC", "HB", via=[(-150, -930)], radius=500, name="High Holborn")
road("kingsway", "main", "HB", "AW", name="Kingsway")
road("strand", "high", "TR", "AW", via=[(-300, -150)], radius=400, name="The Strand")
road("fleet", "main", "AW", "SP", name="Fleet Street")
road("cheapside", "main", "SP", "BK", name="Cheapside")
road("newgate", "main", "HB", "BK", via=[(650, -800)], radius=300, name="Holborn Viaduct")
road("queenvic", "main", "BK", "BF", via=[(700, -20)], radius=300, name="Queen Victoria Street")
road("kingwilliam", "main", "BK", "MN", via=[(1080, -100)], radius=300, name="King William Street")
road("leadenhall", "main", "BK", "AG", via=[(1250, -500)], radius=500, name="Leadenhall Street")
road("moorgate", "main", "BK", "OS", via=[(1120, -1000)], radius=300, name="Moorgate")
road("grays", "street", "HB", "KX", via=[(300, -1200)], radius=200, name="Gray's Inn Road")

# --- The north: roads fanning out to the edge, and the road that curves along it ---
node("P1", -2380, -1600, "roundabout", radius=96, island=60, name="Westbourne Park")
node("P2", -1850, -2080, "roundabout", radius=96, island=60, name="Maida Vale")
node("CT", -700, -1960, "mini", name="Camden Town")
node("P3", -900, -2260, "roundabout", radius=96, island=60, name="Chalk Farm")
node("AN", 330, -1920, "lights", name="Angel")
node("P4", 260, -2180, "roundabout", radius=96, island=60, name="Highbury")
node("HK", 1430, -1960, "mini", name="Dalston")
node("P5", 1250, -2310, "roundabout", radius=96, island=60, name="Stoke Newington")
node("P6", 2200, -2040, "roundabout", radius=96, island=60, name="Clapton")
road("harrow", "dual", "MB", "P1", via=[(-2120, -1560)], radius=400, name="Harrow Road")
road("maida", "dual", "MB", "P2", via=[(-1920, -1800)], radius=400, name="Maida Vale")
road("camden", "high", "EU", "CT", via=[(-640, -1760)], radius=300, name="Camden High Street")
road("chalkfarm", "main", "CT", "P3", via=[(-800, -2120)], radius=300, name="Chalk Farm Road")
road("upper", "high", "KX", "AN", via=[(370, -1730)], radius=300, name="Upper Street")
road("highbury", "main", "AN", "P4", name="Highbury Corner")
road("kingsland", "dual", "OS", "HK", via=[(1440, -1720)], radius=300, name="Kingsland Road")
road("stokey", "main", "HK", "P5", via=[(1360, -2150)], radius=300, name="Stoke Newington Road")
road("hackney", "dual", "OS", "P6", via=[(1900, -1660)], radius=400, name="Hackney Road")
road("north1", "arterial", "P1", "P2", via=[(-2150, -1900)], radius=500, name="Kilburn Lane")
road("north2", "arterial", "P2", "P3", via=[(-1400, -2240)], radius=600, name="Belsize Road")
road("north3", "arterial", "P3", "P4", via=[(-350, -2300)], radius=600, name="Camden Road")
road("north4", "arterial", "P4", "P5", via=[(750, -2200)], radius=600, name="Essex Road")
road("north5", "arterial", "P5", "P6", via=[(1750, -2280)], radius=600, name="Amhurst Road")

# --- The west: Hyde Park, Notting Hill and Kensington, round to Chelsea ---
node("NH", -2760, -950, "roundabout", radius=96, island=60, name="Notting Hill Gate")
node("KN", -2880, -160, "roundabout", radius=96, island=60, name="Kensington")
road("west1", "arterial", "P1", "NH", via=[(-2650, -1300)], radius=500, name="Ladbroke Grove")
road("west2", "arterial", "NH", "KN", via=[(-2860, -560)], radius=600, name="Holland Road")
road("west3", "arterial", "KN", "CH", via=[(-2750, 250), (-2300, 460)], radius=500, name="King's Road")
road("bayswater", "main", "MA", "NH", via=[(-2300, -940)], radius=600, name="Bayswater Road")
road("kensington", "main", "HPC", "KN", via=[(-2350, -150)], radius=600, name="Kensington Road")

# --- The east: Whitechapel, Bow and the docks ---
node("WH", 2400, -520, "lights", name="Whitechapel")
node("P7", 2850, -1400, "roundabout", radius=96, island=60, name="Hackney Wick")
node("P8", 3260, -650, "roundabout", radius=96, island=60, name="Bow")
node("P9", 3420, 230, "roundabout", radius=96, island=60, name="Poplar")
node("CM", 2150, 50, "junction", name="Stepney")
road("whitechapel", "dual", "AG", "WH", via=[(2000, -500)], radius=500, name="Whitechapel Road")
road("mileend", "dual", "WH", "P8", via=[(2850, -560)], radius=500, name="Mile End Road")
road("roman", "main", "WH", "P7", via=[(2650, -1000)], radius=500, name="Roman Road")
road("east1", "arterial", "P6", "P7", via=[(2600, -1800)], radius=500, name="Homerton Road")
road("east2", "arterial", "P7", "P8", via=[(3150, -1050)], radius=500, name="Old Ford Road")
road("east3", "arterial", "P8", "P9", via=[(3420, -200)], radius=500, name="Blackwall Road")
road("commercial", "dual", "minories_mid", "CM", name="Commercial Road")  # starts on Minories (see SPLITS)
road("commercial2", "dual", "CM", "LE", via=[(2350, 250)], radius=400, name="Commercial Road")
road("burdett", "street", "WH", "CM", via=[(2250, -250)], radius=400, name="Burdett Road")
road("eastindia", "dual", "LE", "P9", via=[(3000, 380)], radius=500, name="East India Dock Road")

# --- The Isle of Dogs, inside the river's loop, with the Canary Wharf towers ---
node("IN", 2980, 830, "junction", name="Isle of Dogs")
node("IW", 2800, 1250, "junction", name="Millwall")
node("IS", 2960, 1670, "junction", name="Island Gardens")
node("IE", 3200, 1250, "junction", name="Cubitt Town")
road("westferry", "main", "LE", "IN", via=[(2780, 560)], radius=400, name="Westferry Road")
road("dogs1", "main", "IN", "IW", via=[(2810, 1000)], radius=350, name="Westferry Road")
road("dogs2", "main", "IW", "IS", via=[(2840, 1540)], radius=350, name="Westferry Road")
road("dogs3", "main", "IS", "IE", via=[(3150, 1560)], radius=350, name="Manchester Road")
road("dogs4", "main", "IE", "IN", via=[(3230, 1000)], radius=350, name="Manchester Road")
road("canary", "high", "IW", "IE", name="Canary Wharf")

# --- South of the river ---
node("EL", -150, 1400, "roundabout", radius=72, island=46, name="Elephant and Castle")
node("SW", -2650, 920, "roundabout", radius=96, island=60, name="Battersea Park")
node("RH", 2150, 1250, "lights", name="Rotherhithe")
road("southbank1", "main", "SW", "CS", via=[(-2250, 950)], radius=500, name="Battersea Park Road")
road("southbank2", "dual", "CS", "WS", via=[(-1300, 830)], radius=500, name="Albert Embankment")
road("southbank3", "dual", "WS", "BS", via=[(-150, 720)], radius=500, name="Stamford Street")
road("southbank4", "dual", "BS", "TS", via=[(1100, 760)], radius=500, name="Southwark Street")
road("southbank5", "main", "TS", "RH", via=[(2000, 1000)], radius=400, name="Jamaica Road")
road("stgeorge", "dual", "WS", "EL", via=[(-450, 1100)], radius=350, name="St George's Road")
road("blackfriarsrd", "dual", "BS", "EL", via=[(250, 1050)], radius=350, name="Blackfriars Road")

node("P16", -2300, 1780, "roundabout", radius=96, island=60, name="Wandsworth")
node("VX", -1300, 1500, "lights", name="Vauxhall")
node("P15", -1450, 2200, "roundabout", radius=96, island=60, name="Clapham")
node("KE", -300, 2420, "roundabout", radius=96, island=60, name="Kennington")
node("P13", 1000, 2260, "roundabout", radius=96, island=60, name="Camberwell")
node("OK", 1500, 1620, "lights", name="Old Kent Road")
node("P12", 2150, 2350, "roundabout", radius=96, island=60, name="Peckham")
node("P11", 3050, 2090, "roundabout", radius=96, island=60, name="Deptford")
road("south0", "arterial", "SW", "P16", via=[(-2700, 1400)], radius=500, name="Wandsworth Bridge Road")
road("south1", "arterial", "P16", "P15", via=[(-1900, 2050)], radius=600, name="Lavender Hill")
road("south2", "arterial", "P15", "KE", via=[(-850, 2380)], radius=600, name="Clapham Road")
road("south3", "arterial", "KE", "P13", via=[(350, 2380)], radius=600, name="Camberwell Road")
road("south4", "arterial", "P13", "P12", via=[(1600, 2330)], radius=600, name="Peckham Road")
road("south5", "arterial", "P12", "P11", via=[(2650, 2280)], radius=600, name="Evelyn Street")
road("vauxhall", "dual", "CS", "VX", via=[(-1600, 1250)], radius=400, name="Nine Elms Lane")
road("wandsworth", "dual", "VX", "P16", via=[(-1800, 1680)], radius=500, name="Wandsworth Road")
road("clapham", "main", "VX", "P15", via=[(-1350, 1850)], radius=400, name="South Lambeth Road")
road("kenningtonln", "dual", "VX", "EL", via=[(-700, 1450)], radius=400, name="Kennington Lane")
road("kennington", "high", "EL", "KE", via=[(-200, 1900)], radius=500, name="Kennington Road")
road("walworth", "main", "EL", "P13", via=[(400, 1850)], radius=500, name="Walworth Road")
road("oldkent", "dual", "EL", "OK", via=[(700, 1520)], radius=500, name="Old Kent Road")
road("oldkent2", "dual", "OK", "P12", via=[(1900, 1950)], radius=500, name="Old Kent Road")
road("towerbrrd", "main", "RH", "OK", via=[(1800, 1400)], radius=400, name="Tower Bridge Road")
road("lower", "main", "RH", "P11", via=[(2480, 1950)], radius=500, name="Lower Road")

# Roads above that start or end part way along another road: (road to split, node id, x, z, kind, name).
# The node is put on that road nearest (x, z), and the road is cut in two there.
SPLITS = [
    ("minories", "minories_mid", 1600, -120, "junction", ""),
]

# Districts, for the buildings: (kind, min x, min z, max x, max z). The first one that covers a spot wins;
# everywhere else is terraced streets.
DISTRICTS = [
    ("canary", 2650, 760, 3400, 1850),  # Canary Wharf towers on the Isle of Dogs
    ("westminster", -1850, -560, -560, 470),  # St James's, Whitehall, the palace
    ("city", 250, -1450, 1560, 470),  # Holborn to Aldgate: offices and towers
    ("westend", -1850, -1500, -560, -560),  # Oxford Street, Mayfair, Soho
    ("mansions", -560, -1520, 250, -100),  # Bloomsbury and Covent Garden
    ("southbank", -1000, 590, 1700, 1080),  # the South Bank and Southwark
    ("docklands", 1560, -600, 2700, 760),  # Wapping, Stepney and Limehouse
    ("estate", 450, 1150, 1600, 1720),  # council estates off the Old Kent Road
    ("estate", 2700, -1500, 3800, -500),  # Bow
    ("industrial", 1650, 1150, 2700, 2700),  # Rotherhithe and Deptford
    ("suburb", -3200, 1080, -1250, 2800),  # Wandsworth and Clapham
    ("suburb", 1560, -2700, 3200, -1500),  # Hackney and Clapton
]


def district_at(x, z):
    for kind, x0, z0, x1, z1 in DISTRICTS:
        if x0 <= x <= x1 and z0 <= z <= z1:
            return kind
    return "terraces"


# Special sites that aren't plain buildings: (kind, min x, min z, max x, max z)
SITES = [
    ("hydepark", -2410, -905, -1905, -215),
    ("stjames", -1790, -70, -1010, 240),
    ("palace", -1290, 350, -870, 425),
    ("bigwheel", -700, 595, -380, 668),
    ("regentspark", -1760, -1990, -1180, -1560),
    ("kenningtonpark", -720, 1620, -260, 1960),
    ("square", -340, -1360, -180, -1200),
    ("square", 700, -1330, 860, -1170),
]

# Sites that face a road: (kind, road id, how far along it (0 to 1), side (1 = left of the road's direction),
# width along the road, depth back from it). The game builds them facing the road.
FRONT_SITES = [
    ("petrol", "oldkent", 0.62, -1, 240, 170),
    ("busgarage", "oldkent2", 0.5, -1, 320, 260),
    ("police", "kingsway", 0.5, 1, 220, 170),
]

# How far apart the back streets are in each district (between their middle lines), and the smallest gap
# from a block's edge to its first back street. 0 means no back streets there.
STREET_SPACING = {
    "terraces": (270, 140), "suburb": (320, 160), "estate": (420, 200), "westend": (230, 130), "mansions": (240, 130),
    "city": (220, 120), "westminster": (260, 140), "southbank": (260, 140), "docklands": (360, 180), "industrial": (420, 200),
    "canary": (260, 140),
}
MAX_STREET = 700  # back streets longer than this get a cross street first

# ---------------------------------------------------------------------------------------------
# Shapes with shapely: the roads, the river and the blocks of land between them
# ---------------------------------------------------------------------------------------------

def river_samples():
    s, _, _ = fillet_path([(x, z, 0) for x, z in RIVER], RIVER_RADIUS)
    return s


def river_shape(extra=0.0):
    return LineString(river_samples()).buffer(RIVER_WIDTH / 2 + extra, cap_style=2)


def node_reach(n: Node, extra=0.0):
    attached = [r for r in roads if r.a == n.id or r.b == n.id]
    if n.kind == "roundabout":
        return n.radius + 18 + extra
    if not attached:
        return 0
    return max(outer_width(PROFILES[r.profile]) for r in attached) + extra


def roads_shape(extra=0.0):
    """Every road and its pavements as one shape, `extra` studs wider all round."""
    shapes = []
    for r in roads:
        pts, samples, dist, stations = sampled(r)
        shapes.append(LineString(samples).buffer(outer_width(PROFILES[r.profile]) + extra, cap_style=2, join_style=1))
    for n in nodes.values():
        rad = node_reach(n, extra)
        if rad > 0:
            shapes.append(Point(n.x, n.z).buffer(rad, 24))
    return unary_union(shapes)


_front_cache = []


def front_frames():
    """Each front site as (kind, front middle (x, z), facing (towards the road), width, depth, corners).
    Worked out once, before the back streets cut the roads into pieces."""
    if _front_cache:
        return _front_cache
    out = _front_cache
    for kind, rid, fraction, side, width, depth in FRONT_SITES:
        r = road_by_id(rid)
        pts, samples, dist, stations = sampled(r)
        p, d = point_at(samples, dist, dist[-1] * fraction)
        n = left_of(d)
        front = add(p, mul(n, side * (outer_width(PROFILES[r.profile]) + 1)))
        facing = mul(n, -side)
        across = (facing[1], -facing[0])
        back = mul(facing, -depth)
        corners = [add(front, mul(across, width / 2)), add(front, mul(across, -width / 2)),
                   add(add(front, mul(across, -width / 2)), back), add(add(front, mul(across, width / 2)), back)]
        out.append((kind, front, facing, width, depth, corners))
    return out


def sites_shape():
    shapes = [shape_box(x0, z0, x1, z1) for kind, x0, z0, x1, z1 in SITES]
    for kind, front, facing, width, depth, corners in front_frames():
        shapes.append(Polygon(corners))
    return unary_union(shapes)


def land_blocks(extra=2.0):
    """The blocks of land left between the roads, the river and the sites, as a list of polygons."""
    land = OUTLINE_SHAPE.difference(roads_shape(extra)).difference(river_shape(RIVER_WALK)).difference(sites_shape())
    polys = list(land.geoms) if hasattr(land, "geoms") else [land]
    return [p for p in polys if p.area > 400]


def axes_of(poly: Polygon):
    """The long and short directions of a block, from the smallest box that fits round it."""
    rect = poly.minimum_rotated_rectangle
    c = list(rect.exterior.coords)[:4]
    e1, e2 = sub(c[1], c[0]), sub(c[2], c[1])
    if length(e1) >= length(e2):
        return unit(e1), unit(e2), length(e1), length(e2)
    return unit(e2), unit(e1), length(e2), length(e1)


# ---------------------------------------------------------------------------------------------
# Back streets: each block between the main roads gets a grid of streets across it
# ---------------------------------------------------------------------------------------------

STREET_NAMES = [
    "Albert Street", "Victoria Road", "Church Street", "Mill Lane", "Station Road", "Park Road", "Queen's Road",
    "King Street", "George Street", "Granville Road", "Elm Grove", "Cedar Road", "Princes Street", "Union Street",
    "Market Street", "Chapel Road", "Brook Street", "Grove Road", "Manor Road", "Clarence Road", "Wellington Street",
    "Nelson Road", "Alma Road", "Milton Street", "Cromwell Road", "Stanley Road", "Hamilton Road", "Gordon Road",
    "Warwick Street", "Oxford Road", "Cambridge Street", "York Road", "Beaufort Street", "Charlotte Street",
    "Tavistock Road", "Ladbroke Street", "Grafton Road", "Belgrave Road", "Hanover Street", "Arundel Road",
    "Cornwall Road", "Devonshire Street", "Exeter Road", "Fairfield Road", "Glebe Road", "Holly Street",
    "Ivy Road", "Jubilee Street", "Kensal Road", "Linden Grove", "Maple Street", "Northfield Road", "Orchard Street",
    "Priory Road", "Rectory Lane", "St John's Road", "Tower Street", "Vicarage Road", "Willow Walk", "Yew Street",
    "Abbey Road", "Bedford Street", "Carlton Road", "Dorset Street", "Eaton Road", "Frith Street", "Gower Street",
    "Hereford Road", "Inverness Street", "Judd Street", "Kent Street", "Lansdowne Road", "Mornington Street",
    "Newton Road", "Ossulston Street", "Pembroke Road", "Regency Street", "Sutton Road", "Talbot Road",
    "Upper Grove", "Vernon Road", "Wharf Road", "Acton Street", "Brunswick Road", "Calthorpe Street",
]
_name_index = 0


def next_name():
    global _name_index
    _name_index += 1
    return STREET_NAMES[(_name_index - 1) % len(STREET_NAMES)]


_road_lines: dict[str, tuple] = {}


def refresh_lines():
    _road_lines.clear()
    for r in roads:
        pts, samples, dist, stations = sampled(r)
        _road_lines[r.id] = (LineString(samples), samples, dist)


def nearest_road(point, max_dist):
    """The road whose middle line is nearest `point` (within max_dist): (road, distance, station)."""
    p = Point(point)
    best = None
    for rid, (line, samples, dist) in _road_lines.items():
        d = line.distance(p)
        if d <= max_dist and (best is None or d < best[1]):
            best = (road_by_id(rid), d, line.project(p))
    return best


def nodes_near(point, radius):
    return [n for n in nodes.values() if length(sub((n.x, n.z), point)) < radius]


def find_end(inner, outward):
    """Where a new street leaving a block at `inner` (on the block's edge), heading `outward`, would join a road.
    Returns ("node", node id, point) to join an existing junction, ("new", host road, point) for a new
    T-junction, or None if there's no road to join (or it's too close to another junction)."""
    ray = LineString([inner, add(inner, mul(outward, 90))])
    hit = None
    for rid, (line, samples, dist) in _road_lines.items():
        x = ray.intersection(line)
        if x.is_empty:
            continue
        pts = [x] if x.geom_type == "Point" else [g for g in getattr(x, "geoms", []) if g.geom_type == "Point"]
        for q in pts:
            d = length(sub((q.x, q.y), inner))
            if hit is None or d < hit[1]:
                hit = (road_by_id(rid), d, (q.x, q.y), line)
    if hit is None:
        return None
    host, d, point, host_line = hit
    # Not across the river or through a park to get there
    if LineString([inner, point]).intersects(_blockers):
        return None
    # Join an existing junction on that road if one is close (makes a crossroads, with a slight bend in the
    # new street)
    close = sorted(nodes_near(point, 150), key=lambda n: length(sub((n.x, n.z), point)))
    for n in close:
        if length(sub((n.x, n.z), point)) < 70 and n.kind in ("junction", "mini") and (host.a == n.id or host.b == n.id):
            return ("node", n.id, (n.x, n.z))
    # Otherwise a new T-junction, slid along the road (up to 60 studs) to keep clear of other junctions
    s0 = host_line.project(Point(point))
    for shift in (0, 20, -20, 40, -40, 60, -60):
        s = s0 + shift
        if s < 0 or s > host_line.length:
            continue
        q = host_line.interpolate(s)
        cand = (q.x, q.y)
        if nodes_near(cand, 150):
            continue
        if host.profile in ("dual", "arterial") and any(length(sub(cand, (nodes[e].x, nodes[e].z))) < 260 for e in (host.a, host.b)):
            continue
        return ("new", host, cand)
    return None


_street_rng = random.Random(7)


def bend_for(poly, pa, pb, bend, profile):
    """A middle point that bows the street sideways by `bend` studs, if it still fits inside the block."""
    span = length(sub(pb, pa))
    if abs(bend) < 1 or span < 220:
        return []
    d = unit(sub(pb, pa))
    side = left_of(d)
    inner = poly.buffer(-(outer_width(PROFILES[profile]) + 8))
    for scale in (1.0, 0.6, 0.35):
        amount = bend * scale * min(1.0, span / 450)
        mid = add(mul(add(pa, pb), 0.5), mul(side, amount))
        samples, dist, _ = fillet_path([(pa[0], pa[1], 0), (mid[0], mid[1], 0), (pb[0], pb[1], 0)], 100)
        middle = [p for p, s_ in zip(samples, dist) if 70 < s_ < dist[-1] - 70]
        if middle and all(inner.contains(Point(p)) for p in middle[::2]):
            return [mid]
    return []


def add_street(poly: Polygon, a, b, profile, tag, bend=0.0):
    """Adds a street across block `poly` along the line a-b (which runs edge to edge), bowed sideways by
    `bend` studs so the blocks aren't all rectangles. Returns True if added."""
    line = LineString([a, b]).intersection(poly)
    if line.is_empty:
        return False
    if line.geom_type == "MultiLineString":
        line = max(line.geoms, key=lambda g: g.length)
    if line.geom_type != "LineString" or line.length < 140:
        return False
    c = list(line.coords)
    p0, p1 = c[0], c[-1]
    d = unit(sub(p1, p0))
    plans = []
    for k, (inner, outward) in enumerate(((p0, mul(d, -1)), (p1, d))):
        found = find_end(inner, outward)
        if found is None:
            # A dead end, pulled back into the block
            plans.append(("end", add(inner, mul(outward, -70))))
        else:
            plans.append(found)
    if plans[0][0] == "end" or plans[1][0] == "end":
        return False  # no dead ends: every street goes somewhere, like BVS
    pts = [pl[2] if pl[0] != "end" else pl[1] for pl in plans]
    if length(sub(pts[0], pts[1])) < 150:
        return False
    # Both new junctions on the same road would make a loop of nothing
    if plans[0][0] == "new" and plans[1][0] == "new" and plans[0][1].id == plans[1][1].id:
        return False
    # Its pavements mustn't cut across a park, a depot or the river
    reach = outer_width(PROFILES[profile]) - 3
    if LineString([pts[0], pts[1]]).buffer(reach).intersects(_blockers):
        return False
    via = bend_for(poly, pts[0], pts[1], bend, profile)
    if via:
        curve, _, _ = fillet_path([(pts[0][0], pts[0][1], 0), (via[0][0], via[0][1], 0), (pts[1][0], pts[1][1], 0)], 180)
        if LineString(curve).buffer(reach).intersects(_blockers):
            via = []
    ids = []
    for k, pl in enumerate(plans):
        if pl[0] == "node":
            ids.append(pl[1])
        elif pl[0] == "end":
            nid = f"E{tag}_{k}"
            node(nid, pl[1][0], pl[1][1], "end")
            ids.append(nid)
        else:
            host = pl[1]
            # The host may have been cut in two by the other end already: find the piece under the point
            refresh_lines()
            under = nearest_road(pl[2], 3)
            nid = f"J{tag}_{k}"
            node(nid, pl[2][0], pl[2][1], "junction")
            split_road(under[0].id if under else host.id, nid)
            ids.append(nid)
    road(f"s{tag}", profile, ids[0], ids[1], via=via, radius=180, name=next_name())
    refresh_lines()
    return True


def lattice_positions(lo, hi, spacing, margin):
    """Evenly spread positions between lo+margin and hi-margin, about `spacing` apart, lined up on a grid
    across the whole map so streets on either side of a main road tend to meet head on."""
    first = math.ceil((lo + margin) / spacing) * spacing
    out = []
    u = first
    while u <= hi - margin:
        out.append(u)
        u += spacing
    return out


_blockers = None


def fill_blocks_with_streets(rounds=6):
    global _blockers
    _blockers = unary_union([sites_shape(), river_shape(RIVER_WALK)])
    edge = OUTLINE_SHAPE.exterior.buffer(3)
    made = 0
    for rnd in range(rounds):
        changed = False
        blocks = sorted(land_blocks(), key=lambda p: -p.area)
        for bi, poly in enumerate(blocks):
            if poly.intersects(edge):
                continue  # the strip round the outside of the map: buildings and trees, no streets
            c = poly.representative_point()
            district = district_at(c.x, c.y)
            spacing, margin = STREET_SPACING.get(district, (0, 0))
            if not spacing:
                continue
            u, v, long_len, short_len = axes_of(poly)
            # Each block's streets bow the same way (like streets laid out round a hill), some more than others
            bend = 0.0 if _street_rng.random() < 0.2 else _street_rng.uniform(-70, 70)
            coords = list(poly.exterior.coords)
            us = [dot(p, u) for p in coords]
            vs = [dot(p, v) for p in coords]
            umin, umax, vmin, vmax = min(us), max(us), min(vs), max(vs)
            # Too wide for streets straight across: put a cross street through the middle first
            if short_len > MAX_STREET and rnd < 2:
                mid = (vmin + vmax) / 2
                a = add(mul(u, umin - 200), mul(v, mid))
                b = add(mul(u, umax + 200), mul(v, mid))
                if add_street(poly, a, b, "street", f"{rnd}x{bi}", bend * 0.6):
                    made += 1
                    changed = True
                continue
            if short_len < margin * 2 + 60:
                continue
            for k, pos in enumerate(lattice_positions(umin, umax, spacing, margin)):
                a = add(mul(u, pos), mul(v, vmin - 200))
                b = add(mul(u, pos), mul(v, vmax + 200))
                if add_street(poly, a, b, "back", f"{rnd}b{bi}_{k}", bend + _street_rng.uniform(-12, 12)):
                    made += 1
                    changed = True
        if not changed:
            break
    print(f"  back streets: {made} added")


# ---------------------------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------------------------

def check():
    problems = 0
    lines = {}
    for r in roads:
        pts, samples, dist, stations = sampled(r)
        lines[r.id] = LineString(samples)
    ids = [r.id for r in roads]
    by_id = {r.id: r for r in roads}
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            ra, rb = by_id[ids[i]], by_id[ids[j]]
            la, lb = lines[ra.id], lines[rb.id]
            if not la.intersects(lb):
                continue
            x = la.intersection(lb)
            pts = [x] if x.geom_type == "Point" else [g for g in getattr(x, "geoms", []) if g.geom_type == "Point"]
            shared = {ra.a, ra.b} & {rb.a, rb.b}
            for q in pts:
                if any(length(sub((q.x, q.y), (nodes[n].x, nodes[n].z))) < 120 for n in shared):
                    continue
                print(f"  CROSSING: {ra.id} and {rb.id} cross at ({q.x:.0f}, {q.y:.0f})")
                problems += 1
    counts = {nid: 0 for nid in nodes}
    for r in roads:
        counts[r.a] += 1
        counts[r.b] += 1
    for nid, c in counts.items():
        if c == 0:
            print(f"  UNUSED NODE: {nid}")
            problems += 1
    ids = list(nodes)
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, b = nodes[ids[i]], nodes[ids[j]]
            gap = length(sub((a.x, a.z), (b.x, b.z)))
            if gap < 120 and counts[a.id] and counts[b.id]:
                print(f"  NODES CLOSE: {a.id} and {b.id} are {gap:.0f} apart")
    # Roads running through the river (other than bridges) or sites
    river = river_shape(0)
    sites = sites_shape()
    for r in roads:
        if lines[r.id].intersects(sites.buffer(-4)):
            print(f"  ROAD {r.id} runs through a site")
            problems += 1
    total = sum(l.length for l in lines.values())
    print(f"  {len(roads)} roads, {len(nodes)} nodes, {total:,.0f} studs of road ({total * 0.28 / 1609:.1f} miles)")
    return problems


# ---------------------------------------------------------------------------------------------
# Picture
# ---------------------------------------------------------------------------------------------
SCALE = 0.36


def picture():
    from PIL import Image, ImageDraw
    W, H = int((MAX_X - MIN_X) * SCALE), int((MAX_Z - MIN_Z) * SCALE)
    img = Image.new("RGB", (W, H), (96, 140, 76))
    return img, ImageDraw.Draw(img)


def P(x, z):
    return ((x - MIN_X) * SCALE, (z - MIN_Z) * SCALE)


def draw_shape(g, shape, fill, outline=None):
    polys = list(shape.geoms) if hasattr(shape, "geoms") else [shape]
    for poly in polys:
        if poly.geom_type != "Polygon" or poly.is_empty:
            continue
        g.polygon([P(*c) for c in poly.exterior.coords], fill=fill, outline=outline)
        for hole in poly.interiors:
            g.polygon([P(*c) for c in hole.coords], fill=(96, 140, 76))


def draw_roads(g, labels=True):
    from PIL import ImageFont
    draw_shape(g, shape_box(MIN_X, MIN_Z, MAX_X, MAX_Z).difference(OUTLINE_SHAPE), (52, 70, 48))
    draw_shape(g, river_shape(0), (60, 100, 140))
    for kind, x0, z0, x1, z1 in SITES:
        col = {"palace": (220, 200, 140), "bigwheel": (230, 230, 240), "square": (70, 130, 60)}.get(kind, (70, 130, 60))
        g.rectangle([P(x0, z0), P(x1, z1)], fill=col)
    for kind, front, facing, width, depth, corners in front_frames():
        g.polygon([P(*c) for c in corners], fill={"petrol": (60, 160, 90), "police": (40, 60, 160), "busgarage": (200, 40, 40)}[kind])
    order = sorted(roads, key=lambda r: PROFILES[r.profile]["rank"])
    for pass_ in ("side", "road"):
        for r in order:
            prof = PROFILES[r.profile]
            pts, samples, dist, stations = sampled(r)
            w = outer_width(prof) if pass_ == "side" else half_width(prof)
            col = (205, 200, 190) if pass_ == "side" else ((120, 120, 128) if r.profile not in ("dual", "arterial") else (90, 92, 104))
            draw_shape(g, LineString(samples).buffer(w, cap_style=2), col)
    for nd in nodes.values():
        if nd.kind == "roundabout":
            g.ellipse([P(nd.x - nd.radius, nd.z - nd.radius), P(nd.x + nd.radius, nd.z + nd.radius)], fill=(120, 120, 128))
            g.ellipse([P(nd.x - nd.island, nd.z - nd.island), P(nd.x + nd.island, nd.z + nd.island)], fill=(80, 140, 70))
    if labels:
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
        except OSError:
            font = None
        for nd in nodes.values():
            if nd.name and not nd.id.startswith(("J", "E")):
                x, z = P(nd.x, nd.z)
                g.text((x + 5, z - 14), nd.name, fill=(255, 255, 255), font=font)


# ---------------------------------------------------------------------------------------------
# Luau output
# ---------------------------------------------------------------------------------------------

def lua_value(v, indent=1):
    pad = "\t" * indent
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        if isinstance(v, float):
            v = round(v, 2)
            if v == int(v):
                return str(int(v))
        return str(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, (list, tuple)):
        if all(isinstance(x, (int, float, str)) for x in v):
            return "{ " + ", ".join(lua_value(x) for x in v) + " }"
        inner = ",\n".join(pad + "\t" + lua_value(x, indent + 1) for x in v)
        return "{\n" + inner + ",\n" + pad + "}" if v else "{}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        parts = [f"{k} = {lua_value(x, indent + 1)}" for k, x in v.items()]
        line = "{ " + ", ".join(parts) + " }"
        if len(line) < 140:
            return line
        inner = ",\n".join(pad + "\t" + p for p in parts)
        return "{\n" + inner + ",\n" + pad + "}"
    raise TypeError(type(v))


def emit(path: Path):
    out = {
        "bounds": [MIN_X, MIN_Z, MAX_X, MAX_Z],
        "outline": [[round(x, 1), round(z, 1)] for x, z in list(OUTLINE_SHAPE.exterior.simplify(4).coords)[:-1]],
        "profiles": {k: dict(v) for k, v in PROFILES.items()},
        "nodes": [
            {k: v for k, v in dict(id=n.id, x=round(n.x, 1), z=round(n.z, 1), y=n.y, kind=n.kind, radius=n.radius, island=n.island, name=n.name).items()
             if not (k in ("radius", "island", "y") and v == 0) and not (k == "name" and v == "")}
            for n in nodes.values()
        ],
        "roads": [],
        "river": {"width": RIVER_WIDTH, "radius": RIVER_RADIUS, "walk": RIVER_WALK, "points": [list(p) for p in RIVER]},
        "districts": [list(d) for d in DISTRICTS],
        "sites": [list(s) for s in SITES],
        "frontSites": [
            dict(kind=kind, x=round(front[0], 1), z=round(front[1], 1), fx=round(facing[0], 4), fz=round(facing[1], 4), width=width, depth=depth)
            for kind, front, facing, width, depth, corners in front_frames()
        ],
    }
    for r in roads:
        entry = dict(id=r.id, profile=r.profile, a=r.a, b=r.b, radius=r.radius)
        if r.name:
            entry["name"] = r.name
        if r.via:
            entry["via"] = [[round(c, 1) for c in v] for v in r.via]
        if r.laybys:
            entry["laybys"] = [list(l) for l in r.laybys]
        out["roads"].append(entry)
    text = (
        "--!nocheck\n"
        "-- The London map's road network, as data. MADE BY tools/london_layout.py: change that and run it again,\n"
        "-- don't edit this file by hand. LondonMap and RoadNetwork turn it into roads in the game.\n\n"
        "return " + lua_value(out, 0) + "\n"
    )
    path.write_text(text)
    print(f"  wrote {path.relative_to(ROOT)} ({len(text) // 1024} KB)")


# ---------------------------------------------------------------------------------------------
# Build it
# ---------------------------------------------------------------------------------------------

def build():
    for rid, nid, x, z, kind, name in SPLITS:
        node(nid, x, z, kind, name=name)
    # Snap each split node onto its road, then cut the road there
    refresh_lines()
    for rid, nid, x, z, kind, name in SPLITS:
        line, samples, dist = _road_lines[rid]
        q = line.interpolate(line.project(Point(x, z)))
        nodes[nid].x, nodes[nid].z = q.x, q.y
        split_road(rid, nid)
        refresh_lines()
    front_frames()
    fill_blocks_with_streets()


build()

if __name__ == "__main__":
    problems = check()
    img, g = picture()
    draw_roads(g)
    img.save(ROOT / "docs" / "map-layout.png")
    print("  picture: docs/map-layout.png")
    emit(ROOT / "src" / "server" / "LondonLayout.luau")
    if problems:
        print(f"{problems} problem(s) to fix")
    try:
        sys.modules["london_layout"] = sys.modules["__main__"]  # so london_fill uses this same layout
        import london_fill
        london_fill.run()
    except ImportError as e:
        print(f"  (london_fill not run: {e})")
    if problems:
        sys.exit(1)
