"""Designs the Cambridge map: a compact old city with the countryside and villages round it.

Run it with:  python3 tools/cambridge_layout.py      (needs shapely and Pillow: pip install shapely pillow)
It writes:
  src/server/CambridgeLayout.luau   the roads, river, railway, areas and villages, as data for the game
  docs/cambridge-layout.png          a picture of it
and prints any problems it finds (roads crossing without a junction, junctions too close together).

The plan (agreed with Lewis, 18 Oct 2026): a Cambridge-style map with a bit of city and a bit of countryside
and lots of different places in between, like Birmingham Vehicle Simulator but more varied. Squeezed from the
real Cambridge so it's quick to drive round, but laid out like it:
  - the old centre on the River Cam: colleges, the Market Square, King's Parade, the Backs, stone bridges
  - an inner ring road with traffic lights and a big roundabout, and Parker's Piece with the police station
  - radial roads out of town: Huntingdon Road, Histon Road, Milton Road, Newmarket Road, Mill Road, Hills
    Road, Trumpington Road, Barton Road and Madingley Road
  - the station, the Mill Road terraces, the retail park and football ground on Newmarket Road, the hospital,
    the science park and the bus depot by Cambridge North
  - the M11 (three lanes, hard shoulders) down the west side and the A14 across the north, with proper slip
    roads, roundabouts and bridges at every junction
  - villages out in the fields (Grantchester, Girton, Histon, Milton, Fen Ditton, Cherry Hinton, Fulbourn,
    Coton, Madingley, Barton, Trumpington) joined by country lanes
Roads use the sizes of the AHDEV UK road pack Lewis bought (12.5-stud lanes, 7-stud pavements).

Coordinates are in studs: x runs west to east, z runs north to south (north is -z), y is height. The Market
Square is at (0, 0).
"""

from __future__ import annotations

import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon, box as shape_box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------------------------
# Road types. Widths in studs. Lanes are the AHDEV pack's 12.5 studs; town pavements its 7.
#   lanes: lanes each way, parking: a strip along each kerb where cars park
#   res: central reservation width (dual carriageways), shoulder: hard shoulder, edge: tarmac outside the edge
#   line, side: "pavement" or "verge" beyond the kerb, sideWidth: how wide, oneway: slip roads
# ---------------------------------------------------------------------------------------------
PROFILES = {
    # Old city streets: narrow, stone-paved pavements, 20 mph
    "city": dict(lanes=1, lane=11.5, parking=0, res=0, shoulder=0, edge=0, side="pavement", sideWidth=9, limit=20, rank=1),
    # Town streets, exactly the AHDEV single carriageway (25 studs of road, 7 of pavement each side)
    "town": dict(lanes=1, lane=12.5, parking=0, res=0, shoulder=0, edge=0, side="pavement", sideWidth=7, limit=30, rank=1),
    # Terraced and suburban streets with cars parked along both kerbs
    "terrace": dict(lanes=1, lane=12.5, parking=7, res=0, shoulder=0, edge=0, side="pavement", sideWidth=7, limit=20, rank=0),
    # High streets (Mill Road, village high streets): parking and wide pavements
    "high": dict(lanes=1, lane=12.5, parking=7, res=0, shoulder=0, edge=0, side="pavement", sideWidth=12, limit=20, rank=2),
    # The ring road and the big radial roads: two lanes each way, like the AHDEV 2-lane pack
    "main": dict(lanes=2, lane=12.5, parking=0, res=0, shoulder=0, edge=0, side="pavement", sideWidth=8, limit=30, rank=3),
    # Main roads out of town: one lane each way, edge lines, grass verges, 40-60 mph
    "aroad": dict(lanes=1, lane=13, parking=0, res=0, shoulder=0, edge=1.5, side="verge", sideWidth=10, limit=50, rank=2),
    # Country lanes: narrow, no pavement, grass verges and hedges, national speed limit
    "lane": dict(lanes=1, lane=10.5, parking=0, res=0, shoulder=0, edge=0, side="verge", sideWidth=6, limit=60, rank=0),
    # The A14: a dual carriageway, three lanes each way, a barrier down the middle
    "dual": dict(lanes=3, lane=12.5, parking=0, res=8, shoulder=0, edge=2, side="verge", sideWidth=14, limit=70, rank=4, barrier=True),
    # The M11: three lanes each way plus hard shoulders
    "motorway": dict(lanes=3, lane=12.5, parking=0, res=9, shoulder=10, edge=0, side="verge", sideWidth=14, limit=70, rank=5),
    # Slip roads and the roads across the motorway between junction roundabouts
    "slip": dict(lanes=1, lane=13, parking=0, res=0, shoulder=0, edge=2, side="verge", sideWidth=8, limit=70, rank=3, oneway=True),
    "link": dict(lanes=1, lane=13, parking=0, res=0, shoulder=0, edge=1.5, side="verge", sideWidth=6, limit=40, rank=3),
}


def half_width(profile: dict) -> float:
    """Distance from the middle of the road to the kerb."""
    if profile.get("oneway"):
        return profile["lanes"] * profile["lane"] / 2 + profile["edge"]
    return profile["res"] / 2 + profile["lanes"] * profile["lane"] + profile.get("parking", 0) + profile["shoulder"] + profile["edge"]


KERB_WIDTH = 0.75  # the kerb stone between road and pavement, as in the AHDEV pack


def outer_width(profile: dict) -> float:
    """Distance from the middle of the road to the back of the pavement or verge."""
    kerb = KERB_WIDTH if profile["side"] == "pavement" else 0
    return half_width(profile) + kerb + profile["sideWidth"]


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
    kind: str = "junction"  # junction, lights, roundabout, mini, end, attach
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
    gaps: list = field(default_factory=list)  # (side, s0, s1): breaks in the edge line where slips join
    taper: str = ""  # slip roads: "start" or "end" is where they meet the main carriageway
    taper_from: tuple = ()


nodes: dict[str, Node] = {}
roads: list[Road] = []


def node(id, x, z, kind="junction", radius=0.0, island=0.0, name="", y=0.0):
    nodes[id] = Node(id, x, z, y, kind, radius, island, name)
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


def split_road(r: Road, nid: str):
    """Splits road r in two at node nid (which sits on it), for a T-junction or crossroads."""
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
        return length(sub((v[0], v[1]), (nd.x, nd.z))) > 30

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


def family(rid):
    """A road and the pieces it's been split into (their ids start with its own)."""
    return [r for r in roads if r.id == rid or r.id.startswith(rid + "_")]


def join_at(rid, x, z, nid=None, kind="junction"):
    """Puts a junction on road `rid` (or one of its split pieces) nearest (x, z), splitting it there, and
    returns the junction's id."""
    best = None
    for r in family(rid):
        pts, samples, dist, stations = sampled(r)
        line = LineString(samples)
        d = line.distance(Point(x, z))
        if best is None or d < best[1]:
            best = (r, d, line)
    r, d, line = best
    q = line.interpolate(line.project(Point(x, z)))
    nid = nid or f"J_{rid}_{round(q.x)}_{round(q.y)}"
    node(nid, q.x, q.y, kind)
    split_road(r, nid)
    return nid


_counter = [0]


def crescent(rid, a_xy, b_xy, bulge, profile="terrace", name=""):
    """A crescent: a street leaving road `rid` near a_xy and rejoining it near b_xy, bowing out `bulge` studs to
    the left of the line from a to b (negative bulges go right). No dead ends, like a British estate."""
    _counter[0] += 1
    a = join_at(rid, *a_xy)
    b = join_at(rid, *b_xy)
    pa, pb = (nodes[a].x, nodes[a].z), (nodes[b].x, nodes[b].z)
    d = unit(sub(pb, pa))
    side = left_of(d)
    p1 = add(add(pa, mul(d, 70)), mul(side, bulge))
    p2 = add(add(pb, mul(d, -70)), mul(side, bulge))
    road(f"cres{_counter[0]}", profile, a, b, via=[p1, p2], radius=90, name=name)


def ladder(rid_a, rid_b, xs_or_zs, along="x", profile="terrace", names=()):
    """Straight streets between two roads that run roughly side by side (like terraced streets between
    Mill Road and Coldham's Lane): one street at each x (or z) in `xs_or_zs`."""
    for k, c in enumerate(xs_or_zs):
        _counter[0] += 1
        la = unary_union([LineString(sampled(r)[1]) for r in family(rid_a)])
        lb = unary_union([LineString(sampled(r)[1]) for r in family(rid_b)])
        if along == "x":
            probe = LineString([(c, -20000), (c, 20000)])
        else:
            probe = LineString([(-20000, c), (20000, c)])
        qa, qb = probe.intersection(la), probe.intersection(lb)
        if qa.is_empty or qb.is_empty:
            print(f"  note: ladder street at {c} misses a road")
            continue
        qa = qa if qa.geom_type == "Point" else list(qa.geoms)[0]
        qb = qb if qb.geom_type == "Point" else list(qb.geoms)[0]
        a = join_at(rid_a, qa.x, qa.y)
        b = join_at(rid_b, qb.x, qb.y)
        road(f"rung{_counter[0]}", profile, a, b, name=names[k] if k < len(names) else "")


# ---------------------------------------------------------------------------------------------
# Motorway junctions, like most of the M11's: one big two-lane roundabout raised up over the motorway, which
# runs underneath through its open middle. Slip roads climb up to it from each carriageway, and the local roads
# ramp up to it from the fields either side.
# ---------------------------------------------------------------------------------------------
BRIDGE_Y = 16  # how high the raised roundabouts and bridges over the motorway are
SLIP_LENGTH = 420  # how far before and after the junction the slip roads leave and join
TAPER = 150  # the length of the wedge where a slip road meets the motorway
APPROACH = 300  # how far out from the roundabout's edge the local roads start climbing


def interchange(jid, main_id, at, name, arms=((90, "link"), (-90, "link")), radius=120, island=86):
    """Builds a junction on motorway or dual carriageway `main_id` at the point nearest `at`: a raised
    roundabout over it, four slip roads, and a ramped road out to each of `arms` (angle in degrees, 0 = the
    main road's direction from its first node to its last, 90 = to its left; and the ramp's road type, or None
    to leave that arm for a road that joins the roundabout itself). Returns the roundabout's id and the id of
    the node at the foot of each arm's ramp (None for the arms left alone), in order."""
    main = road_by_id(main_id)
    pts, samples, dist, stations = sampled(main)
    line = LineString(samples)
    s = line.project(Point(at))
    p, d = point_at(samples, dist, s)
    n = left_of(d)
    prof = PROFILES[main.profile]
    hw = half_width(prof)
    slip_hw = half_width(PROFILES["slip"])
    rb = f"{jid}"
    node(rb, p[0], p[1], "roundabout", radius, island, name=name, y=BRIDGE_Y)

    def edge(station, side, extra):
        q, _ = point_at(samples, dist, station)
        return add(q, mul(n, side * (hw + extra)))

    for side in (1, -1):
        # Traffic on the left carriageway (side 1) runs the main road's way: it leaves before the junction
        # (smaller s) and joins after it. Traffic on the right carriageway runs the other way.
        for kind in ("off", "on"):
            before = (kind == "off") == (side == 1)
            station = s - SLIP_LENGTH if before else s + SLIP_LENGTH
            attach = f"{jid}_{kind}{side}"
            ap = edge(station, side, slip_hw)
            node(attach, ap[0], ap[1], "attach")
            # Out from the motorway a little, half way up, then into the roundabout
            towards = s - 200 if before else s + 200
            mid = edge(towards, side, slip_hw + 34)
            beyond = station - TAPER if before else station + TAPER
            taper_from = edge(beyond, side, 0)
            if kind == "off":
                r = road(f"{jid}_{kind}{side}", "slip", attach, rb, via=[(mid[0], mid[1], BRIDGE_Y * 0.55)], radius=160)
                r.taper = "start"
            else:
                r = road(f"{jid}_{kind}{side}", "slip", rb, attach, via=[(mid[0], mid[1], BRIDGE_Y * 0.55)], radius=160)
                r.taper = "end"
            r.taper_from = taper_from
            g0, g1 = sorted((station, beyond))
            main.gaps.append((side, round(g0 - 5, 1), round(g1 + 5, 1)))
    feet = []
    for k, (angle, profile) in enumerate(arms):
        if profile is None:
            feet.append(None)
            continue
        a = math.radians(angle)
        direction = add(mul(d, math.cos(a)), mul(n, math.sin(a)))
        foot = add(p, mul(direction, radius + APPROACH))
        fid = f"{jid}_arm{k}"
        node(fid, foot[0], foot[1], "join")
        road(f"{jid}_ramp{k}", profile, fid, rb, radius=200, name=name)
        feet.append(fid)
    return rb, feet


# =============================================================================================
# THE MAP
# =============================================================================================

# The edge of the map: an uneven outline. Beyond it, fields and woods fade into the haze.
OUTLINE = [
    (-6200, -4500), (-4600, -5000), (-2600, -4900), (-800, -5100), (1200, -4900), (3200, -4700), (5000, -4300),
    (6300, -3800), (6500, -1800), (6300, 300), (6400, 2200), (5700, 3600), (3800, 4700), (1500, 5000),
    (-800, 4800), (-2800, 4900), (-4600, 4300), (-6000, 3200), (-6400, 1200), (-6500, -1500),
]
OUTLINE_SHAPE = Polygon(OUTLINE).buffer(-300, join_style=1).buffer(300, join_style=1)
MIN_X, MIN_Z, MAX_X, MAX_Z = -6600, -5200, 6600, 5100

# The River Cam: up from Grantchester, round the Backs behind the colleges, then east past Jesus Green and
# Midsummer Common and out past Fen Ditton
RIVER_WIDTH = 46
RIVER_RADIUS = 260
RIVER = [
    (-2350, 5200), (-2150, 4200), (-1950, 3200), (-1600, 2300), (-1250, 1500), (-1080, 950), (-960, 400),
    (-920, -250), (-830, -760), (-520, -1050), (0, -1150), (600, -1300), (1250, -1420), (2000, -1700),
    (2800, -2200), (3600, -2650), (4600, -3050), (5600, -3450), (6800, -3800),
]

# The railway: in from the south, the station east of the centre, Cambridge North, and out to the north
RAILWAY = [(1700, 5200), (1600, 3600), (1480, 2500), (1420, 1700), (1450, 600), (1560, -600), (1760, -1550),
           (2100, -2600), (2350, -3400), (2650, -4600), (2850, -5400)]
STATIONS = [("Cambridge", 1420, 1700), ("Cambridge North", 2120, -2700)]

# ---- The city centre ------------------------------------------------------------------------
# The inner ring road
node("RG_SW", -1250, 760, "lights", name="Fen Causeway")
node("RG_W", -1250, -650, "lights", name="Northampton Street")
node("RG_NW", -960, -1160, "lights", name="Castle Hill")
node("RG_N", -150, -1560, "roundabout", 52, 26, name="Mitcham's Corner")
node("RG_NE", 1260, -1830, "roundabout", 50, 25, name="Elizabeth Way")
node("RG_E", 1150, -950, "roundabout", 62, 32, name="Newmarket Road")
node("RG_SE", 1060, 720, "lights", name="Mill Road")
node("RG_S", 250, 880, "lights", name="Hills Road")
node("RG_S2", -650, 930, "lights", name="Trumpington Street")

road("queens", "main", "RG_SW", "RG_W", via=[(-1265, 60)], name="Queen's Road")
road("northampton", "main", "RG_W", "RG_NW", via=[(-1180, -960)], radius=150, name="Northampton Street")
road("chesterton", "main", "RG_NW", "RG_N", via=[(-620, -1460)], radius=300, name="Chesterton Road")
road("chesterton2", "main", "RG_N", "RG_NE", via=[(520, -1760)], radius=400, name="Chesterton Road")
road("elizabeth", "main", "RG_NE", "RG_E", via=[(1270, -1380)], radius=300, name="Elizabeth Way")
road("eastrd", "main", "RG_E", "RG_SE", via=[(1090, -250)], radius=400, name="East Road")
road("gonville", "main", "RG_SE", "RG_S", via=[(700, 840)], radius=300, name="Gonville Place")
road("lensfield", "main", "RG_S", "RG_S2", via=[(-200, 960)], radius=300, name="Lensfield Road")
road("fencauseway", "main", "RG_S2", "RG_SW", via=[(-960, 960)], radius=250, name="Fen Causeway")

# The old streets inside the ring: a loose grid of three north-south and three east-west streets
node("C1", -480, -650, name="Round Church")
node("C2", -120, -650, name="Sidney Street")
node("C3", 250, -650, name="Jesus Lane")
node("C4", -480, 60, name="King's Parade")
node("C5", -120, 60, "mini", name="Market Square")
node("C6", 250, 60, name="Parkside")
node("C7", -480, 450, name="Silver Street")
node("C8", -120, 450, name="Downing Street")
node("C9", 250, 450, name="Regent Street")
road("trinity", "city", "C1", "C4", via=[(-500, -300)], name="Trinity Street")
road("kingsparade", "city", "C4", "C7", via=[(-470, 250)], name="King's Parade")
road("trumpingtonst", "city", "C7", "RG_S2", via=[(-560, 700)], name="Trumpington Street")
road("sidney", "city", "C2", "C5", name="Sidney Street")
road("standrews", "city", "C5", "C8", name="St Andrew's Street")
road("parker", "city", "C3", "C6", name="Parker Street")
road("regent", "town", "C6", "C9", name="Regent Street")
road("regent2", "town", "C9", "RG_S", via=[(250, 700)], name="Regent Street")
road("jesuslane", "city", "C1", "C2", name="Bridge Street")
road("jesuslane2", "city", "C2", "C3", name="Jesus Lane")
road("maids", "town", "C3", "RG_E", via=[(700, -820)], radius=200, name="Maids Causeway")
road("market", "city", "C4", "C5", name="Market Street")
road("pettycury", "city", "C5", "C6", name="Petty Cury")
road("downing", "city", "C7", "C8", name="Pembroke Street")
road("downing2", "city", "C8", "C9", name="Downing Street")
road("bridgest", "town", "C1", "RG_NW", via=[(-700, -900)], radius=150, name="Bridge Street")
pk = join_at("eastrd", 1075, 60, "E_PK")
nodes[pk].name = "Parkside"
road("parkside", "town", "C6", pk, via=[(650, 60)], name="Parkside")
q_ss = join_at("queens", -1258, 430, "Q_SS")
road("silver", "city", "C7", q_ss, via=[(-800, 435)], name="Silver Street")

# ---- Radial roads ---------------------------------------------------------------------------
# Huntingdon Road to Girton and the A14 / M11 junction (finished below)
node("HU1", -1900, -2150, name="Huntingdon Road")
node("GIRTON", -2700, -2850, "mini", name="Girton")
road("huntingdon", "aroad", "RG_NW", "HU1", via=[(-1400, -1680)], radius=500, name="Huntingdon Road")
road("huntingdon2", "aroad", "HU1", "GIRTON", radius=500, name="Huntingdon Road")

# Histon Road north to the A14 and Histon
node("HR1", -830, -2300, "lights", name="King's Hedges Road")
road("histonrd", "aroad", "RG_NW", "HR1", via=[(-880, -1700)], radius=500, name="Histon Road")

# Milton Road: the science park, Cambridge North and the bus depot, then the A14 and Milton
node("MI1", 420, -2350, "lights", name="Science Park")
road("miltonrd", "main", "RG_N", "MI1", via=[(80, -1950)], radius=500, name="Milton Road")
road("kingshedges", "town", "HR1", "MI1", via=[(-200, -2420)], radius=600, name="King's Hedges Road")
node("COWLEY", 1700, -2560, "end", name="Cowley Road")
road("cowley", "town", "MI1", "COWLEY", via=[(1000, -2480)], radius=400, name="Cowley Road")

# Newmarket Road: the retail park, the football ground, the airport roundabout, then out into the fields
node("NR1", 1850, -930, "lights", name="Retail Park")
node("NR2", 2400, -870, "lights", name="Coldham's Lane")
node("NR3", 3350, -960, "roundabout", 56, 28, name="Airport Way")
node("NR4", 4500, -820, name="Teversham turn")
node("NR_E", 6200, -700, "end", name="to Newmarket")
road("newmarket", "main", "RG_E", "NR1", via=[(1500, -960)], radius=500, name="Newmarket Road")
road("newmarket2", "main", "NR1", "NR2", name="Newmarket Road")
road("newmarket3", "aroad", "NR2", "NR3", via=[(2900, -900)], radius=600, name="Newmarket Road")
road("newmarket4", "aroad", "NR3", "NR4", via=[(3950, -860)], radius=800, name="Newmarket Road")
road("newmarket5", "aroad", "NR4", "NR_E", via=[(5400, -760)], radius=900, name="Newmarket Road")

# Mill Road: the terraces and corner shops of Romsey, over the railway, on to Cherry Hinton and Fulbourn
node("MR1", 2100, 1000, "lights", name="Romsey")
node("MR2", 2850, 1180, "mini", name="Brooks Road")
node("CH", 3700, 1500, "mini", name="Cherry Hinton")
node("FUL", 5050, 1650, "mini", name="Fulbourn")
node("FUL_E", 6150, 1900, "end", name="to Balsham")
road("millrd", "high", "RG_SE", "MR1", via=[(1500, 850)], radius=600, name="Mill Road")
road("millrd2", "high", "MR1", "MR2", name="Mill Road")
road("cherryhintonhigh", "town", "MR2", "CH", via=[(3300, 1300)], radius=500, name="Cherry Hinton High Street")
road("fulbournrd", "aroad", "CH", "FUL", via=[(4300, 1520)], radius=700, name="Fulbourn Road")
road("fulbourn_e", "lane", "FUL", "FUL_E", via=[(5600, 1700)], radius=400, name="Balsham Road")
road("coldhams", "town", "NR2", "MR2", via=[(2750, 100)], radius=700, name="Coldham's Lane")
# Teversham Lane from Newmarket Road down to Fulbourn
road("teversham", "lane", "NR4", "FUL", via=[(4700, 100), (5000, 900)], radius=400, name="Teversham Lane")

# Hills Road: the station, the hospital, out to the south east
node("H1", 470, 1480, "lights", name="Station Road")
node("H2", 820, 2150, "lights", name="Cherry Hinton Road")
node("AD", 1150, 2860, "roundabout", 56, 28, name="Addenbrooke's")
node("STATION", 1330, 1640, "end", name="Station")
node("BAB_E", 3300, 4300, "end", name="to Babraham")
road("hillsrd", "main", "RG_S", "H1", via=[(330, 1150)], radius=500, name="Hills Road")
road("hillsrd2", "main", "H1", "H2", radius=500, name="Hills Road")
road("hillsrd3", "main", "H2", "AD", via=[(1000, 2500)], radius=500, name="Hills Road")
road("stationrd", "town", "H1", "STATION", via=[(900, 1560)], radius=300, name="Station Road")
road("cherryhintonrd", "town", "H2", "MR2", via=[(1700, 2120), (2500, 1800)], radius=500, name="Cherry Hinton Road")
road("babraham", "aroad", "AD", "BAB_E", via=[(1800, 2980), (2600, 3500)], radius=800, name="Babraham Road")
node("HOSP", 950, 3350, "end", name="Hospital")
road("hospital", "town", "AD", "HOSP", via=[(1100, 3150)], radius=200, name="Hills Road")

# Trumpington Road south to Trumpington, Long Road across to Hills Road
node("TR1", -560, 1850, name="Brooklands Avenue")
node("TR2", -470, 2620, "lights", name="Long Road")
node("TP", -450, 3120, "mini", name="Trumpington")
road("trumpingtonrd", "main", "RG_S2", "TR1", via=[(-640, 1350)], radius=500, name="Trumpington Road")
road("trumpingtonrd2", "main", "TR1", "TR2", radius=500, name="Trumpington Road")
road("trumpingtonrd3", "town", "TR2", "TP", radius=500, name="Trumpington Road")
hl = join_at("hillsrd3", 960, 2560, "H_LONG", "lights")
road("longrd", "town", "TR2", hl, via=[(300, 2560)], radius=500, name="Long Road")
road("brooklands", "town", "TR1", "H1", via=[(0, 1750)], radius=500, name="Brooklands Avenue")

# Barton Road west, Grantchester Road south to Grantchester
node("BR1", -1780, 790, name="Grantchester Road")
node("BR2", -2600, 820, name="Barton Road")
road("bartonrd", "town", "RG_SW", "BR1", name="Barton Road")
road("bartonrd2", "aroad", "BR1", "BR2", radius=600, name="Barton Road")
node("GRANT", -2080, 2660, "mini", name="Grantchester")
road("grantchesterrd", "lane", "BR1", "GRANT", via=[(-1900, 1700)], radius=400, name="Grantchester Road")
road("grantchester_tp", "lane", "GRANT", "TP", via=[(-1600, 2900), (-900, 3080)], radius=350, name="Grantchester Road")

# Madingley Road west past the university's science sites
node("MD1", -2350, -760, name="West Cambridge")
road("madingleyrd", "main", "RG_W", "MD1", via=[(-1800, -700)], radius=600, name="Madingley Road")

# ---- The A14 across the north and the M11 down the west -------------------------------------
node("A14_W", -6300, -3650, "end", name="A14 west")
node("A14_E", 6350, -3550, "end", name="A14 east")
a14 = road("a14", "dual", "A14_W", "A14_E", radius=3000, name="A14", via=[
    (-4800, -3560), (-3450, -3460), (-750, -3410), (1100, -3380), (1800, -3365, 0), (2200, -3350, BRIDGE_Y),
    (2480, -3340, BRIDGE_Y), (2880, -3320, 0), (3420, -3300), (4800, -3360),
])
# Girton: the M11 ends at the A14's roundabout (from the south); Huntingdon Road comes in from the south east
gi, (gi_n, gi_hunt) = interchange("GI", "a14", (-3450, -3460), "Girton Interchange", arms=((90, "link"), (-52, "link")), radius=150, island=114)
hj, (hj_n, hj_s) = interchange("HJ", "a14", (-750, -3410), "Histon")
mj, (mj_n, mj_s) = interchange("MJ", "a14", (1100, -3380), "Milton")
aj, (aj_n, aj_s) = interchange("AJ", "a14", (3420, -3300), "Fen Ditton")

node("M11_S", 650, 5050, "end", name="M11 south")
m11 = road("m11", "motorway", gi, "M11_S", radius=2600, name="M11", via=[
    (-3520, -2600, 0), (-3550, -850), (-3480, 780), (-3200, 2300), (-2300, 3520), (-750, 4060), (250, 4500),
])
j13, (j13_e, j13_w) = interchange("J13", "m11", (-3550, -850), "Junction 13")
j12, (j12_e, j12_w) = interchange("J12", "m11", (-3480, 780), "Junction 12")
j11, (j11_n, j11_s) = interchange("J11", "m11", (-750, 4060), "Junction 11")

# Radial roads onto the junctions
road("huntingdon3", "aroad", "GIRTON", gi_hunt, radius=500, name="Huntingdon Road")
road("histonrd2", "aroad", "HR1", hj_s, via=[(-780, -2900)], radius=600, name="Histon Road")
node("HISTON", -700, -4300, "mini", name="Histon")
road("histonrd3", "town", hj_n, "HISTON", via=[(-720, -3950)], radius=400, name="Histon Road")
road("miltonrd2", "main", "MI1", mj_s, via=[(820, -2900)], radius=600, name="Milton Road")
node("MILTON", 1350, -4250, "mini", name="Milton")
road("miltonrd3", "town", mj_n, "MILTON", via=[(1250, -3950)], radius=400, name="Milton High Street")
node("FD", 3250, -2050, "mini", name="Fen Ditton")
road("airportway", "aroad", "NR3", "FD", via=[(3300, -1500)], radius=600, name="Airport Way")
road("horningsea", "aroad", "FD", aj_s, via=[(3320, -2700)], radius=500, name="Horningsea Road")
node("HORN", 3700, -4250, "mini", name="Horningsea")
road("horningsea2", "lane", aj_n, "HORN", via=[(3550, -3900)], radius=400, name="Horningsea Road")
road("buttlane", "lane", "HISTON", "MILTON", via=[(200, -4500)], radius=500, name="Butt Lane")
road("miltonhorn", "lane", "MILTON", "HORN", via=[(2500, -4500)], radius=500, name="Clayhithe Road")
node("OAK", -3700, -4700, "end", name="to Oakington")
road("oakington", "lane", gi_n, "OAK", via=[(-3500, -4200)], radius=400, name="Oakington Road")
node("DITTON_W", 2350, -2200, name="Ditton Lane")
road("dittonlane", "lane", "FD", "DITTON_W", via=[(2800, -2000)], radius=400, name="Fen Ditton High Street")
road("dittonwalk", "town", "DITTON_W", "NR1", via=[(2050, -1500)], radius=400, name="Ditton Walk")

road("madingleyrd2", "aroad", "MD1", j13_e, via=[(-2950, -820)], radius=600, name="Madingley Road")
node("MADINGLEY", -5000, -1350, "mini", name="Madingley")
road("madingleyrd3", "aroad", j13_w, "MADINGLEY", via=[(-4300, -1100)], radius=700, name="Madingley Road")
node("MAD_W", -6350, -1500, "end", name="to St Neots")
road("madingley_w", "lane", "MADINGLEY", "MAD_W", via=[(-5700, -1450)], radius=500, name="Madingley Road")
node("COTON", -4400, -150, "mini", name="Coton")
road("cotonrd", "lane", j13_w, "COTON", via=[(-4100, -600)], radius=400, name="Coton Road")
road("bartonrd3", "aroad", "BR2", j12_e, via=[(-3050, 800)], radius=600, name="Barton Road")
node("BARTON", -4800, 960, "mini", name="Barton")
road("bartonrd4", "aroad", j12_w, "BARTON", via=[(-4200, 870)], radius=700, name="Barton Road")
node("BARTON_W", -6400, 1050, "end", name="to Comberton")
road("barton_w", "lane", "BARTON", "BARTON_W", via=[(-5600, 1000)], radius=500, name="Comberton Road")
road("cotonbarton", "lane", "COTON", "BARTON", via=[(-4650, 450)], radius=400, name="Barton Lane")
road("hauxton", "aroad", "TP", j11_n, via=[(-500, 3600)], radius=500, name="Hauxton Road")
node("HAUX", -1200, 4700, "end", name="to Hauxton")
road("hauxton2", "lane", j11_s, "HAUX", via=[(-1000, 4400)], radius=400, name="Hauxton Road")
road("grantchester_m", "lane", "GRANT", "BR2", via=[(-2550, 2000), (-2700, 1300)], radius=400, name="Barton Road")

# ---- Streets in the suburbs and villages (crescents and terraces, never dead ends) ----------
# Mill Road terraces: streets between Mill Road and Coldham's Lane / Cherry Hinton Road
road("romsey_back", "terrace", "MR1", "NR2", via=[(2250, 400)], radius=500, name="Coleridge Road")
ladder("millrd2", "cherryhintonrd", [2350, 2600], along="x", names=("Coleridge Road", "Marshall Road"))
crescent("coldhams", (2560, -420), (2700, 0), 160, name="Vinery Road")
# Chesterton: crescents off Chesterton Road and Milton Road
crescent("chesterton2", (250, -1700), (900, -1790), -170, name="De Freville Avenue")
crescent("miltonrd", (-30, -1800), (200, -2150), 180, name="Gilbert Road")
crescent("kingshedges", (-650, -2350), (100, -2420), -200, name="Arbury Road")
crescent("histonrd", (-900, -1450), (-860, -2000), 190, name="Victoria Road")
crescent("huntingdon", (-1250, -1550), (-1650, -1900), -170, name="Storey's Way")
# Newnham: off Barton Road and Grantchester Road
crescent("bartonrd2", (-1980, 795), (-2380, 808), 170, name="Newnham Road")
crescent("grantchesterrd", (-1820, 1100), (-1880, 1550), 180, name="Grange Road")
# South: off Hills Road, Long Road, Trumpington Road, Cherry Hinton Road
crescent("trumpingtonrd2", (-580, 2050), (-530, 2450), 200, name="Chaucer Road")
crescent("longrd", (-200, 2580), (500, 2570), 190, name="Long Road")
crescent("cherryhintonrd", (1750, 2115), (2150, 2010), 200, name="Perne Road")
crescent("hillsrd2", (560, 1650), (720, 1980), -170, name="Glebe Road")
crescent("brooklands", (-380, 1820), (180, 1720), 160, name="Brooklands Avenue")
# Cherry Hinton, Fulbourn and Trumpington estates
crescent("fulbournrd", (3950, 1520), (4500, 1560), -220, name="Fulbourn Old Drift")
crescent("cherryhintonhigh", (3100, 1250), (3550, 1420), 170, name="High Street")
crescent("trumpingtonrd3", (-465, 2760), (-455, 2990), 220, name="Anstey Way")
crescent("hauxton", (-460, 3250), (-500, 3520), -220, name="Clay Farm")
# Villages: a loop round each green
crescent("histonrd3", (-706, -3960), (-700, -4180), 170, "high", name="Histon High Street")
crescent("miltonrd3", (1290, -3870), (1335, -4130), -190, "high", name="Milton High Street")
crescent("huntingdon2", (-2150, -2350), (-2500, -2650), 200, "high", name="Girton High Street")
crescent("grantchester_tp", (-1950, 2750), (-1650, 2890), 160, name="Mill Way")
crescent("madingleyrd3", (-4450, -1180), (-4850, -1300), -170, name="Madingley High Street")
crescent("bartonrd4", (-4250, 890), (-4650, 940), 160, name="Barton High Street")
crescent("fulbourn_e", (5200, 1680), (5550, 1700), 170, name="Fulbourn High Street")

# ---------------------------------------------------------------------------------------------
# Areas, for the buildings: (kind, polygon corners). The first one that covers a spot wins; everywhere
# outside them and the villages is countryside (fields, hedges, woods).
# ---------------------------------------------------------------------------------------------
AREAS = [
    ("colleges", [(-900, -1000), (-500, -1000), (-500, 800), (-900, 800)]),
    ("oldcity", [(-500, -900), (1000, -900), (1000, 850), (-500, 850)]),
    ("backs", [(-1220, -600), (-900, -600), (-900, 720), (-1220, 720)]),
    ("station", [(450, 1300), (1400, 1300), (1400, 2100), (450, 2100)]),
    ("terraces", [(1100, 300), (3000, 300), (3000, 2000), (1100, 2000)]),
    ("retail", [(1600, -1500), (2800, -1500), (2800, -400), (1600, -400)]),
    ("hospital", [(650, 2950), (1450, 2950), (1450, 3700), (650, 3700)]),
    ("sciencepark", [(-150, -3150), (650, -3150), (650, -2450), (-150, -2450)]),
    ("industrial", [(900, -2900), (2000, -2900), (2000, -2200), (900, -2200)]),
    ("westcam", [(-2800, -1100), (-1400, -1100), (-1400, -300), (-2800, -300)]),
    ("suburb", [(-1500, -2600), (1250, -2600), (1250, -1250), (-1500, -1250)]),
    ("suburb", [(-1700, 700), (-300, 700), (-300, 3300), (-1700, 3300)]),
    ("suburb", [(-300, 900), (1500, 900), (1500, 2900), (-300, 2900)]),
    ("suburb", [(2000, 900), (4000, 900), (4000, 2400), (2000, 2400)]),
    ("suburb", [(1100, -1300), (2400, -1300), (2400, -400), (1100, -400)]),
]

# Villages: (name, centre x, centre z, radius). Houses, a church, a pub and a green; fields all round.
VILLAGES = [
    ("Grantchester", -1950, 2780, 420), ("Girton", -2500, -2650, 450), ("Histon", -700, -4050, 450),
    ("Milton", 1320, -4000, 420), ("Fen Ditton", 2900, -2050, 350), ("Horningsea", 3700, -4250, 300),
    ("Cherry Hinton", 3500, 1450, 500), ("Fulbourn", 5300, 1680, 420), ("Coton", -4400, -150, 300),
    ("Madingley", -4800, -1280, 350), ("Barton", -4600, 930, 350), ("Trumpington", -350, 3300, 500),
]

# Special places that aren't plain buildings: (kind, min x, min z, max x, max z)
SITES = [
    ("parkerspiece", 330, 160, 885, 750),
    ("jesusgreen", -380, -1080, 250, -760),
    ("midsummer", 300, -1250, 1050, -1000),
    ("christspieces", 20, -560, 220, -260),
    ("marketsquare", -100, -110, 110, 40),
    ("kingscollege", -900, 120, -520, 420),
    ("coldhamscommon", 2450, -700, 3050, -150),
    ("stadium", 1900, -800, 2300, -450),
    ("coefen", -1180, 1050, -700, 1650),
    ("sheepsgreen", -1220, 450, -980, 740),
    ("botanic", -330, 1100, 285, 1500),
    ("airport", 3560, -700, 4500, 600),
    ("lakes", -60, -3080, 250, -2850),
]

# Sites that face a road: (kind, road id, how far along it (0 to 1), side (1 = left of the road's direction),
# width along the road, depth back from it). The game builds them facing the road. These are the team depots.
FRONT_SITES = [
    ("petrol", "newmarket2", 0.5, 1, 240, 170),
    ("busgarage", "cowley", 0.75, -1, 320, 260),
    ("police", "parkside", 0.55, 1, 220, 150),
]


# ---------------------------------------------------------------------------------------------
# Shapes with shapely
# ---------------------------------------------------------------------------------------------

def river_samples():
    s, _, _ = fillet_path([(x, z, 0) for x, z in RIVER], RIVER_RADIUS)
    return s


def river_shape(extra=0.0):
    return LineString(river_samples()).buffer(RIVER_WIDTH / 2 + extra, cap_style=2)


def railway_samples():
    s, _, _ = fillet_path([(x, z, 0) for x, z in RAILWAY], 900)
    return s


_front_cache = []


def front_frames():
    """Each front site as (kind, front middle (x, z), facing (towards the road), width, depth, corners)."""
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


def level_crossings():
    """Where roads cross the railway at ground level: (x, z, road id)."""
    rail = LineString(railway_samples())
    out = []
    for r in roads:
        pts, samples, dist, stations = sampled(r)
        line = LineString(samples)
        x = line.intersection(rail)
        if x.is_empty:
            continue
        for q in ([x] if x.geom_type == "Point" else [g for g in getattr(x, "geoms", []) if g.geom_type == "Point"]):
            if height_near(r, (q.x, q.y)) < 8:
                out.append((round(q.x, 1), round(q.y, 1), r.id))
    return out


def height_near(r: Road, xy, reach=90):
    """How high road r is at the point on it nearest xy, going up and down evenly between its control
    points like the game does (bridges are high). `reach` is unused, kept for older calls."""
    pts, samples, dist, stations = sampled(r)
    s = LineString(samples).project(Point(xy))
    for i in range(1, len(stations)):
        if s <= stations[i] or i == len(stations) - 1:
            s0, s1 = stations[i - 1], stations[i]
            f = 0 if s1 - s0 < 1e-6 else max(0.0, min(1.0, (s - s0) / (s1 - s0)))
            return pts[i - 1][2] + (pts[i][2] - pts[i - 1][2]) * f
    return pts[-1][2]


# ---------------------------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------
# Estates: the suburbs filled with crescents. The hand-placed streets above leave big empty blocks, so this walks
# along every street and main road through the suburbs and adds a crescent off it wherever one fits: clear of
# other roads, junctions, the river, the railway and the special sites, and inside the suburb. A second pass adds
# crescents off those crescents, so the estates go a couple of streets deep. Still no dead ends.
# ---------------------------------------------------------------------------------------------
ESTATE_AREAS = ("suburb", "terraces")
ESTATE_HOSTS = ("main", "town", "terrace", "high", "aroad", "city")


def estates():
    import random as random_module
    rng = random_module.Random(11)
    zones = unary_union([Polygon(c).buffer(-25) for kind, c in AREAS if kind in ESTATE_AREAS])
    blocked = unary_union([shape_box(x0, z0, x1, z1).buffer(20) for kind, x0, z0, x1, z1 in SITES]
                          + [Polygon(f[5]).buffer(20) for f in front_frames()]
                          + [river_shape(60), LineString(railway_samples()).buffer(45)])
    added = 0
    for layer in range(3):
        hosts = [r for r in roads if r.profile in ESTATE_HOSTS and max(p[2] for p in control_points(r)) < 1
                 and (layer == 0 or r.id.startswith("cres"))]
        for host in hosts:
            for side in (1, -1):
                pts, samples, dist, stations = sampled(host)
                total = dist[-1]
                s = 150.0
                tries = 0
                while s < total - 150:
                    # A deep loop first (which the next pass can put crescents off), then an ordinary one
                    deep = tries % 2 == 0
                    tries += 1
                    span = rng.uniform(300, 380) if deep else rng.uniform(240, 340)
                    if s + span > total - 150:
                        if deep:
                            continue
                        break
                    pa, _ = point_at(samples, dist, s)
                    pb, _ = point_at(samples, dist, s + span)
                    d = unit(sub(pb, pa))
                    bulge = side * (rng.uniform(360, 440) if deep else rng.uniform(170, 240))
                    out = left_of(d)
                    p1 = add(add(pa, mul(d, 70)), mul(out, bulge))
                    p2 = add(add(pb, mul(d, -70)), mul(out, bulge))
                    line, _, _ = fillet_path([(pa[0], pa[1], 0), (p1[0], p1[1], 0), (p2[0], p2[1], 0),
                                              (pb[0], pb[1], 0)], 90)
                    shape = LineString(line)
                    # Points every 10 studs (the straight stretches only have their ends)
                    line = [(q.x, q.y) for q in (shape.interpolate(t) for t in range(0, int(shape.length) + 1, 10))]
                    # The part away from the host road, which mustn't come near anything else
                    inner = LineString([q for q in line if min(length(sub(q, pa)), length(sub(q, pb))) > 45])
                    # (Splitting a road drops its bend points near the split, which would change its shape, so the
                    # new junctions keep well clear of them)
                    ok = (zones.contains(shape) and not inner.buffer(40).intersects(blocked)
                          and all(length(sub(q, (n.x, n.z))) > 125 for q in (pa, pb) for n in nodes.values())
                          and all(length(sub(q, (v[0], v[1]))) > 60 for q in (pa, pb)
                                  for r in family(host.id.split("_")[0]) for v in r.via))
                    if ok:
                        # Every other road, and the host road itself (and the rest of it, if it's a crescent that
                        # loops back) away from where the new one leaves it
                        near = [r for r in roads if LineString(sampled(r)[1]).distance(shape) < 200]
                        mine = {r.id for r in family(host.id.split("_")[0])}
                        far = [q for q in line if min(length(sub(q, pa)), length(sub(q, pb))) > 130]
                        for r in near:
                            zone = LineString(sampled(r)[1]).buffer(half_width(PROFILES[r.profile]) + 75)
                            test = (LineString(far) if len(far) > 1 else None) if r.id in mine else inner
                            if test is not None and test.intersects(zone):
                                ok = False
                                break
                    if ok:
                        crescent(host.id, pa, pb, bulge)
                        added += 1
                        s += span + 140
                        tries = 0
                    elif not deep:
                        s += 40
    print(f"  estates: {added} crescents added")


def check():
    problems = 0
    lines = {}
    for r in roads:
        pts, samples, dist, stations = sampled(r)
        lines[r.id] = LineString(samples)
    by_id = {r.id: r for r in roads}
    ids = list(by_id)
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
                if abs(height_near(ra, (q.x, q.y), 200) - height_near(rb, (q.x, q.y), 200)) >= 8:
                    continue  # one goes over the other
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
            if a.kind == "attach" or b.kind == "attach":
                continue
            gap = length(sub((a.x, a.z), (b.x, b.z)))
            if gap < 110 and counts[a.id] and counts[b.id]:
                print(f"  NODES CLOSE: {a.id} and {b.id} are {gap:.0f} apart")
    outline = OUTLINE_SHAPE.buffer(5)
    for r in roads:
        if not outline.contains(lines[r.id]) and not any(nodes[e].kind == "end" for e in (r.a, r.b)):
            print(f"  OUTSIDE: road {r.id} leaves the map")
    # Sites mustn't sit on roads, the river, the railway or each other
    shapes = [(kind, shape_box(x0, z0, x1, z1)) for kind, x0, z0, x1, z1 in SITES]
    shapes += [(kind, Polygon(corners)) for kind, front, facing, width, depth, corners in front_frames()]
    blockers = [(f"road {r.id}", lines[r.id].buffer(half_width(PROFILES[r.profile]))) for r in roads
                if max(p[2] for p in control_points(r)) < 8]
    blockers += [("the river", river_shape()), ("the railway", LineString(railway_samples()).buffer(10))]
    for i, (kind, shape) in enumerate(shapes):
        for other, (kind2, shape2) in enumerate(shapes):
            if other > i and shape.intersection(shape2).area > 1:
                print(f"  SITES OVERLAP: {kind} and {kind2}")
                problems += 1
        for name, blocker in blockers:
            if shape.intersection(blocker).area > 50:
                print(f"  SITE ON {name.upper()}: {kind}")
    total = sum(l.length for l in lines.values())
    print(f"  {len(roads)} roads, {len(nodes)} nodes, {total:,.0f} studs of road ({total * 0.28 / 1609:.1f} miles), "
          f"{len(level_crossings())} level crossings")
    return problems


# ---------------------------------------------------------------------------------------------
# Picture
# ---------------------------------------------------------------------------------------------
SCALE = 0.16
FIELD = (118, 150, 84)


def P(x, z):
    return ((x - MIN_X) * SCALE, (z - MIN_Z) * SCALE)


def draw_shape(g, shape, fill, outline=None, hole=FIELD):
    polys = list(shape.geoms) if hasattr(shape, "geoms") else [shape]
    for poly in polys:
        if poly.geom_type != "Polygon" or poly.is_empty:
            continue
        g.polygon([P(*c) for c in poly.exterior.coords], fill=fill, outline=outline)
        for h in poly.interiors:
            g.polygon([P(*c) for c in h.coords], fill=hole)


def picture(path: Path):
    from PIL import Image, ImageDraw, ImageFont
    W, H = int((MAX_X - MIN_X) * SCALE), int((MAX_Z - MIN_Z) * SCALE)
    img = Image.new("RGB", (W, H), FIELD)
    g = ImageDraw.Draw(img)
    # Fields in a patchwork, outside the map in dark haze
    import random
    rng = random.Random(3)
    for x in range(MIN_X, MAX_X, 700):
        for z in range(MIN_Z, MAX_Z, 600):
            shade = rng.choice([(118, 150, 84), (132, 158, 88), (150, 160, 92), (170, 165, 96), (108, 140, 78), (196, 186, 92)])
            g.rectangle([P(x + 10, z + 10), P(x + 690, z + 590)], fill=shade)
    draw_shape(g, shape_box(MIN_X, MIN_Z, MAX_X, MAX_Z).difference(OUTLINE_SHAPE), (52, 64, 50))
    colours = {
        "colleges": (214, 196, 150), "oldcity": (200, 170, 140), "backs": (96, 150, 80), "station": (170, 170, 190),
        "terraces": (190, 150, 130), "retail": (180, 180, 200), "hospital": (230, 230, 235), "sciencepark": (160, 200, 210),
        "industrial": (170, 160, 150), "westcam": (170, 190, 200), "suburb": (200, 180, 160),
    }
    for kind, corners in reversed(AREAS):
        g.polygon([P(*c) for c in corners], fill=colours[kind])
    for name, x, z, rad in VILLAGES:
        g.ellipse([P(x - rad, z - rad), P(x + rad, z + rad)], fill=(206, 186, 160))
    site_colours = {"stadium": (90, 160, 90), "marketsquare": (220, 210, 180), "kingscollege": (225, 210, 165),
                    "airport": (150, 170, 120), "lakes": (80, 130, 170)}
    for kind, x0, z0, x1, z1 in SITES:
        g.rectangle([P(x0, z0), P(x1, z1)], fill=site_colours.get(kind, (88, 150, 72)))
    draw_shape(g, river_shape(0), (60, 110, 160))
    rail = LineString(railway_samples())
    g.line([P(*c) for c in rail.coords], fill=(90, 70, 60), width=4)
    for name, x, z in STATIONS:
        g.rectangle([P(x - 60, z - 120), P(x + 60, z + 120)], fill=(240, 240, 240), outline=(60, 60, 60))
    for kind, front, facing, width, depth, corners in front_frames():
        g.polygon([P(*c) for c in corners], fill={"petrol": (60, 160, 90), "police": (40, 60, 160), "busgarage": (200, 40, 40)}[kind])
    order = sorted(roads, key=lambda r: PROFILES[r.profile]["rank"])
    road_colours = {"motorway": (70, 110, 190), "dual": (60, 140, 90), "main": (210, 120, 70), "aroad": (230, 180, 80),
                    "slip": (110, 140, 200), "link": (200, 200, 200), "lane": (250, 250, 250)}
    for pass_ in ("side", "road"):
        for r in order:
            prof = PROFILES[r.profile]
            pts, samples, dist, stations = sampled(r)
            if pass_ == "side":
                w, col = outer_width(prof), (190, 186, 178) if prof["side"] == "pavement" else (130, 160, 96)
            else:
                w, col = half_width(prof), road_colours.get(r.profile, (245, 245, 245))
            draw_shape(g, LineString(samples).buffer(max(w, 6), cap_style=2), col)
    for nd in nodes.values():
        if nd.kind == "roundabout":
            g.ellipse([P(nd.x - nd.radius, nd.z - nd.radius), P(nd.x + nd.radius, nd.z + nd.radius)], fill=(230, 230, 230))
            g.ellipse([P(nd.x - nd.island, nd.z - nd.island), P(nd.x + nd.island, nd.z + nd.island)], fill=(80, 140, 70))
        elif nd.kind == "lights":
            g.ellipse([P(nd.x - 22, nd.z - 22), P(nd.x + 22, nd.z + 22)], fill=(220, 40, 40))
    for x, z, rid in level_crossings():
        g.rectangle([P(x - 25, z - 25), P(x + 25, z + 25)], fill=(250, 220, 0))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 13)
        small = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 10)
    except OSError:
        font = small = None
    for name, x, z, rad in VILLAGES:
        g.text(P(x - 200, z - rad - 120), name, fill=(40, 40, 40), font=font)
    labels = [("City Centre", -350, -350), ("Mill Road", 1700, 760), ("Retail Park", 1750, -1300), ("Hospital", 700, 3400),
              ("Science Park", -150, -3250), ("Station", 1100, 1850), ("Parker's Piece", 400, 400), ("River Cam", -1750, 2200),
              ("M11", -3950, 0), ("A14", -2000, -3700), ("Bus depot", 1300, -2750), ("Police", 450, -150),
              ("Football ground", 1850, -380), ("Airport", 4000, -100)]
    for text, x, z in labels:
        g.text(P(x, z), text, fill=(20, 20, 20), font=font)
    for r in roads:
        if r.profile in ("main", "aroad") and r.name and not r.id[-1].isdigit():
            pts, samples, dist, stations = sampled(r)
            p, d = point_at(samples, dist, dist[-1] * 0.5)
            g.text(P(p[0] + 30, p[1] + 30), r.name, fill=(60, 30, 10), font=small)
    img.save(path)
    print(f"  picture: {path.relative_to(ROOT)}")


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
        "river": {"width": RIVER_WIDTH, "radius": RIVER_RADIUS, "points": [list(p) for p in RIVER]},
        "railway": {"points": [list(p) for p in RAILWAY], "stations": [list(s) for s in STATIONS],
                    "crossings": [list(c) for c in level_crossings()]},
        "areas": [[kind, [list(c) for c in corners]] for kind, corners in AREAS],
        "villages": [list(v) for v in VILLAGES],
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
        if r.gaps:
            entry["gaps"] = [list(gp) for gp in r.gaps]
        if r.taper:
            entry["taper"] = r.taper
            entry["taperFrom"] = [round(c, 1) for c in r.taper_from]
        out["roads"].append(entry)
    text = (
        "--!nocheck\n"
        "-- The Cambridge map's roads, river, railway, areas and villages, as data. MADE BY tools/cambridge_layout.py:\n"
        "-- change that and run it again, don't edit this file by hand.\n\n"
        "return " + lua_value(out, 0) + "\n"
    )
    path.write_text(text)
    print(f"  wrote {path.relative_to(ROOT)} ({len(text) // 1024} KB)")


if __name__ == "__main__":
    front_frames()
    estates()
    problems = check()
    picture(ROOT / "docs" / "cambridge-layout.png")
    emit(ROOT / "src" / "server" / "CambridgeLayout.luau")
    if problems:
        print(f"{problems} problem(s) to fix")
        sys.exit(1)
