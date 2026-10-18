"""Fills every block of the London map: buildings along every street, corner shops and pubs, back gardens,
yards, walls in the gaps, and buildings and trees round the edge so you never see the end of the world.

It runs straight after london_layout.py (which calls it), and writes:
  src/server/LondonFill.luau   everything it placed, as data (LondonMap builds it in the game)
  docs/map-fill.png            a picture of it, to check by eye that nothing is left empty

How a block is filled:
  1. Its edge is split into frontages (the stretches facing a road) and backs (facing the river, a park or
     the edge of the map).
  2. Where two frontages meet at a corner, a corner building goes in (a pub, a corner shop, an office).
  3. Each frontage is lined with buildings: houses and shops from the bought building kit where the
     district has them, and buildings made from parts (Georgian terraces, mansion blocks, offices,
     warehouses...) everywhere else and in the gaps, so the street is lined edge to edge.
  4. Behind the houses go back gardens with fences; behind shops and offices, paved yards.
  5. Whatever is left becomes yard, car park or trees. Blocks on the edge of the map get a backdrop of
     taller buildings and trees behind their frontage.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon, box as shape_box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union
from shapely.strtree import STRtree

import london_layout as L

ROOT = Path(__file__).resolve().parent.parent
rng = random.Random(2026)

# The bought building kit (ServerStorage.BuildingKit in the place file), measured in Studio on 17 Oct 2026:
# name: (kind, width, depth, height, how often to use it)
KIT = {
    "terrace_a": ("terrace", 98.9, 36.8, 30.8, 4),
    "terrace_b": ("terrace", 98.8, 28.0, 30.8, 4),
    "semi_a": ("semi", 52.3, 28.2, 27.6, 3),
    "semi_b": ("semi", 52.3, 28.2, 27.6, 3),
    "semi_c": ("semi", 64.1, 41.3, 28.3, 2),
    "detached_a": ("detached", 32.6, 30.8, 27.5, 2),
    "detached_b": ("detached", 51.4, 31.0, 27.5, 2),
    "detached_c": ("detached", 24.2, 27.9, 27.5, 1),
    "detached_d": ("detached", 26.9, 27.9, 27.5, 1),
    "gosford": ("detached", 17.8, 29.0, 32.0, 1),
    "gosford_double": ("semi", 35.3, 29.0, 32.0, 1),
    "mitchell": ("large", 34.9, 32.4, 31.0, 1),
    "windsor": ("large", 34.9, 32.4, 31.0, 1),
    "darwick": ("large", 35.5, 29.3, 31.0, 1),
    "morton": ("large", 26.9, 29.0, 32.0, 1),
    "duggen": ("large", 28.8, 32.0, 27.2, 1),
    "shop_1": ("shop", 14.7, 34.2, 38.7, 3),
    "shop_2": ("shop", 14.7, 34.2, 38.7, 3),
    "shop_3": ("shop", 14.7, 34.2, 38.7, 3),
    "shop_4": ("shop", 14.7, 34.2, 38.7, 3),
    "shop_5": ("shopwide", 41.1, 28.0, 38.3, 2),
    "shop_6": ("shop", 19.4, 36.9, 34.4, 2),
    "shop_7": ("shopwide", 41.2, 28.1, 39.5, 2),
}

# Built from parts in the game (CityBuildings.luau). Any width; depth and storeys from these ranges.
#   style: (depth range, storeys range)
STYLES = {
    "georgian": ((30, 40), (3, 5)),  # brick or white stucco terraces with tall sash windows and black railings
    "victorian": ((28, 34), (2, 3)),  # two-up two-down terraced houses with bay windows
    "shops": ((30, 38), (2, 4)),  # a row of shops with flats above
    "mansion": ((40, 60), (5, 7)),  # red-brick mansion blocks with stone bands
    "stone": ((45, 70), (5, 8)),  # Portland stone offices and government buildings
    "office": ((50, 90), (6, 26)),  # glass and steel offices
    "concrete": ((40, 70), (5, 14)),  # 1960s concrete offices and flats
    "warehouse": ((40, 70), (4, 6)),  # brick warehouses (docks, old industry)
    "shed": ((50, 90), (2, 2)),  # industrial units
    "council": ((30, 40), (8, 18)),  # council tower blocks
    "pub": ((30, 40), (3, 3)),  # a corner pub
    "corner": ((30, 40), (3, 4)),  # a corner shop with flats above
    "backdrop": ((40, 70), (4, 12)),  # plain blocks round the edge of the map
}

# What lines the streets in each district. Each entry: (what, weight). "kit:<kind>" is a kit building.
FRONTAGE = {
    "terraces": [("kit:terrace", 8), ("victorian", 2), ("kit:semi", 1)],
    "terraces_main": [("kit:shop", 2), ("kit:shopwide", 1), ("shops", 2), ("georgian", 2), ("victorian", 2), ("kit:terrace", 3)],
    "suburb": [("kit:semi", 4), ("kit:detached", 3), ("kit:large", 3)],
    "suburb_main": [("kit:shop", 2), ("kit:shopwide", 1), ("kit:semi", 3), ("shops", 2)],
    "westend": [("shops", 4), ("kit:shop", 3), ("kit:shopwide", 2), ("mansion", 3), ("georgian", 2)],
    "mansions": [("georgian", 5), ("mansion", 4), ("shops", 1)],
    "westminster": [("stone", 5), ("georgian", 3), ("mansion", 2)],
    "city": [("office", 6), ("stone", 3), ("concrete", 1)],
    "southbank": [("concrete", 3), ("office", 2), ("mansion", 2), ("shops", 2)],
    "docklands": [("warehouse", 5), ("office", 2), ("concrete", 1)],
    "estate": [("council", 5), ("concrete", 2), ("victorian", 1)],
    "industrial": [("shed", 6), ("warehouse", 2)],
    "canary": [("office", 8), ("concrete", 1)],
}
HIGH_STREET = [("kit:shop", 5), ("kit:shopwide", 2), ("shops", 4)]

# Gaps beside detached and semi-detached houses (driveways), filled with a fence, gate or hedge
KIT_GAPS = {"semi": (6, 10), "detached": (7, 12), "large": (8, 14)}

# How deep the back garden or yard behind a building is, by district
BACK_DEPTH = {"canary": 14, "terraces": 34, "suburb": 50, "estate": 40, "westend": 20, "mansions": 22, "westminster": 20, "city": 14,
              "southbank": 20, "docklands": 22, "industrial": 30}

CORNER_SIZE = {"canary": 60, "terraces": 34, "suburb": 0, "estate": 0, "westend": 44, "mansions": 44, "westminster": 50, "city": 56,
               "southbank": 46, "docklands": 46, "industrial": 0}

# ---------------------------------------------------------------------------------------------
# Output lists
# ---------------------------------------------------------------------------------------------
buildings = []  # dict(kind, style or kit, x, z, deg, w, d, floors, seed)
gardens = []  # dict(x, z, deg, w, d, kind)  kind: lawn, yard, carpark
walls = []  # dict(x0, z0, x1, z1, kind)  kind: brick, fence, hedge, railing
trees = []  # dict(x, z, s)

footprints = []  # shapely polygons of everything solid placed so far (buildings, gardens)
_fp_tree = None
_fp_dirty = 0


def add_footprint(poly):
    global _fp_dirty
    footprints.append(poly)
    _fp_dirty += 1


def overlaps(poly, slack=0.6):
    """Whether `poly` overlaps anything already placed (by more than a sliver)."""
    global _fp_tree, _fp_dirty
    if _fp_tree is None or _fp_dirty > 40:
        _fp_tree = STRtree(footprints) if footprints else None
        _fp_dirty = 0
        _recent.clear()
    shrunk = poly.buffer(-slack)
    if shrunk.is_empty:
        return False
    if _fp_tree is not None:
        for i in _fp_tree.query(shrunk):
            if footprints[i].intersects(shrunk):
                return True
    for i in range(len(footprints) - _fp_dirty, len(footprints)):
        if footprints[i].intersects(shrunk):
            return True
    return False


_recent = []


def rect(front_mid, facing, w, d):
    """The footprint of a building whose front edge is centred on `front_mid`, facing `facing`, w wide, d deep."""
    across = (facing[1], -facing[0])
    back = L.mul(facing, -d)
    a = L.add(front_mid, L.mul(across, w / 2))
    b = L.add(front_mid, L.mul(across, -w / 2))
    return Polygon([a, b, L.add(b, back), L.add(a, back)])


def deg_of(facing):
    """Turn (degrees about the vertical) for a building whose front faces `facing`: 0 faces north (-z)."""
    return round(math.degrees(math.atan2(-facing[0], -facing[1])), 1)


def pick(options):
    total = sum(w for _, w in options)
    roll = rng.random() * total
    for what, w in options:
        roll -= w
        if roll <= 0:
            return what
    return options[-1][0]


def kits_of(kind, room):
    return [(name, v) for name, v in KIT.items() if v[0] == kind and v[1] <= room]


def place_building(kind, style, front_mid, facing, w, d, floors, block):
    poly = rect(front_mid, facing, w, d)
    if not poly.buffer(-0.8).within(block):
        return None
    if overlaps(poly):
        return None
    across = (facing[1], -facing[0])
    centre = L.add(front_mid, L.mul(facing, -d / 2))
    buildings.append(dict(kind=kind, style=style, x=round(front_mid[0], 1), z=round(front_mid[1], 1), deg=deg_of(facing),
                          w=round(w, 1), d=round(d, 1), floors=floors, seed=rng.randint(1, 9999)))
    add_footprint(poly)
    return poly


# ---------------------------------------------------------------------------------------------
# Block edges: frontages and corners
# ---------------------------------------------------------------------------------------------

def road_kind_near(point, lines):
    best = None
    p = Point(point)
    for r, line in lines:
        dd = line.distance(p)
        if best is None or dd < best[0]:
            best = (dd, r)
    return best[1] if best and best[0] < 70 else None


def block_runs(block, road_zone, lines):
    """The block's edge as runs of frontage: each a list of points along the edge (in order, block on the
    left) with the road it faces. Edges that don't face a road are left out."""
    ring = orient(block, 1.0).exterior.simplify(0.8)
    pts = list(ring.coords)[:-1]
    n = len(pts)
    edges = []
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        seg = L.sub(b, a)
        ln = L.length(seg)
        if ln < 0.5:
            continue
        d = L.unit(seg)
        outward = (d[1], -d[0])  # right of the edge = outside for an anticlockwise ring
        mid = L.add(a, L.mul(seg, 0.5))
        probe = L.add(mid, L.mul(outward, 7))
        if not block.contains(Point(L.add(mid, L.mul(outward, -1.5)))):
            outward = L.mul(outward, -1)
            probe = L.add(mid, L.mul(outward, 7))
        facing_road = road_zone.contains(Point(probe))
        r = road_kind_near(L.add(mid, L.mul(outward, 30)), lines) if facing_road else None
        edges.append(dict(a=a, b=b, d=d, out=outward, len=ln, road=r))
    if not edges:
        return [], []
    # Start at an edge that follows a corner, so runs don't wrap round the start
    start = 0
    for i in range(len(edges)):
        prev = edges[i - 1]
        if L.dot(prev["d"], edges[i]["d"]) < math.cos(math.radians(30)) or (prev["road"] is None) != (edges[i]["road"] is None):
            start = i
            break
    edges = edges[start:] + edges[:start]
    runs = []
    corners = []
    current = None
    for i, e in enumerate(edges):
        prev = edges[i - 1]
        turn_ok = L.dot(prev["d"], e["d"]) >= math.cos(math.radians(30))
        same = current is not None and turn_ok and e["road"] is not None and (prev["road"] is not None) and prev["road"].profile == e["road"].profile
        if e["road"] is None:
            current = None
            continue
        if same:
            current["pts"].append(e["b"])
            current["edges"].append(e)
        else:
            current = dict(pts=[e["a"], e["b"]], edges=[e], road=e["road"])
            runs.append(current)
            # A corner where this run meets the one before it (both facing roads, turning outwards)
            if prev["road"] is not None and not turn_ok:
                cross = prev["d"][0] * e["d"][1] - prev["d"][1] * e["d"][0]
                if cross > 0:  # a left turn on an anticlockwise ring: the corner sticks out into the junction
                    corners.append(dict(c=e["a"], din=prev["d"], dout=e["d"], out_in=prev["out"], out_out=e["out"],
                                        run_before=runs[-2] if len(runs) > 1 else None, run_after=current))
    # The first run may join the last one round the start
    return runs, corners


def run_length(run):
    return sum(L.length(L.sub(run["pts"][k], run["pts"][k - 1])) for k in range(1, len(run["pts"])))


def run_at(run, s):
    """Point, direction along, and outward normal at distance s along a run."""
    pts = run["pts"]
    acc = 0.0
    for k in range(1, len(pts)):
        seg = L.sub(pts[k], pts[k - 1])
        ln = L.length(seg)
        if acc + ln >= s or k == len(pts) - 1:
            f = 0 if ln < 1e-9 else max(0.0, min(1.0, (s - acc) / ln))
            d = L.unit(seg)
            return L.add(pts[k - 1], L.mul(seg, f)), d, run["edges"][k - 1]["out"]
        acc += ln
    return pts[-1], run["edges"][-1]["d"], run["edges"][-1]["out"]


def straight_enough(run, s0, s1, limit_deg=8):
    _, d0, _ = run_at(run, s0)
    _, d1, _ = run_at(run, s1)
    return L.dot(d0, d1) >= math.cos(math.radians(limit_deg))


def frontage_options(district, road, edge_block=False):
    kind = road.profile
    if district == "canary":
        return FRONTAGE["canary"]
    if edge_block and kind != "high":
        return FRONTAGE["suburb"] if district == "suburb" else FRONTAGE["terraces"] if district in ("terraces", "estate") else FRONTAGE.get(district, FRONTAGE["terraces"])
    if kind == "high":
        return HIGH_STREET
    if kind in ("main", "dual", "arterial") and district in ("terraces", "suburb"):
        return FRONTAGE[district + "_main"]
    return FRONTAGE.get(district, FRONTAGE["terraces"])


def fill_run(run, s0, s1, district, block, edge_block=False):
    """Lines one frontage run with buildings between distances s0 and s1 along it. Returns the stretches
    left empty (as (s0, s1) pairs) so walls can go there."""
    road = run["road"]
    options = frontage_options(district, road, edge_block)
    s = s0
    empty = []
    proc_style = next((what for what, _ in options if not what.startswith("kit:")), "georgian")
    pending_gap_from = None
    while s < s1 - 4:
        room = s1 - s
        what = pick(options)
        placed = False
        if what.startswith("kit:"):
            kind = what[4:]
            choices = kits_of(kind, room)
            if choices:
                total = sum(v[4] for _, v in choices)
                roll = rng.random() * total
                name, v = choices[-1]
                for nm, vv in choices:
                    roll -= vv[4]
                    if roll <= 0:
                        name, v = nm, vv
                        break
                w, d = v[1], v[2]
                if straight_enough(run, s, s + w):
                    p0, dir0, out0 = run_at(run, s)
                    p1, dir1, out1 = run_at(run, s + w)
                    mid = L.mul(L.add(p0, p1), 0.5)
                    chord = L.sub(p1, p0)
                    facing = L.unit((chord[1], -chord[0]))
                    if L.dot(facing, out0) < 0:
                        facing = L.mul(facing, -1)
                    if place_building("kit", name, mid, facing, L.length(chord), d, 0, block):
                        placed = True
                        gap = 0
                        if v[0] in KIT_GAPS:
                            lo, hi = KIT_GAPS[v[0]]
                            gap = rng.uniform(lo, hi)
                            if s + w + gap < s1:
                                empty.append((s + w, s + w + gap, "side"))
                        s += w + gap
        if not placed:
            # A building made from parts: any width, so it can fill what's left exactly
            style = what if not what.startswith("kit:") else proc_style
            (dlo, dhi), (flo, fhi) = STYLES[style]
            w = min(room, rng.uniform(26, 70) if style not in ("office", "concrete", "council", "shed", "warehouse") else rng.uniform(45, 95))
            if room - w < 18:
                w = room  # don't leave a sliver
            # Short pieces on bends so they follow the curve
            while w > 16 and not straight_enough(run, s, s + w, 10):
                w *= 0.7
            if w < 8:
                empty.append((s, s1, "end"))
                break
            d = rng.uniform(dlo, dhi)
            floors = rng.randint(flo, fhi)
            if district == "canary" and style == "office":
                floors = rng.randint(14, 36)  # Canary Wharf's towers
            p0, dir0, out0 = run_at(run, s)
            p1, dir1, out1 = run_at(run, s + w)
            mid = L.mul(L.add(p0, p1), 0.5)
            chord = L.sub(p1, p0)
            facing = L.unit((chord[1], -chord[0]))
            if L.dot(facing, out0) < 0:
                facing = L.mul(facing, -1)
            ok = None
            for scale in (1.0, 0.8, 0.62, 0.48, 0.36):
                ok = place_building("proc", style, mid, facing, L.length(chord), max(10, d * scale), floors, block)
                if ok:
                    break
            if ok:
                s += w
                if district == "estate" and style in ("council", "concrete"):
                    # Towers stand apart on the grass, with open space between (no wall)
                    gap = rng.uniform(35, 70)
                    if s + gap < s1:
                        empty.append((s, s + gap, "open"))
                    s += gap
            else:
                empty.append((s, min(s1, s + max(w, 8)), "skip"))
                s += max(w, 8)
    return empty


# ---------------------------------------------------------------------------------------------
# Behind the buildings: gardens, yards and the rest
# ---------------------------------------------------------------------------------------------

def back_fill(block, district):
    """Gardens or yards behind every building in this block that has room behind it."""
    depth = BACK_DEPTH.get(district, 20)
    mine = [b for b in buildings if b.get("_block") is block]
    for b in mine:
        facing = (-math.sin(math.radians(b["deg"])), -math.cos(math.radians(b["deg"])))
        back_mid = L.add((b["x"], b["z"]), L.mul(facing, -b["d"]))
        if district == "estate":
            continue  # the towers stand in open grass
        kind = "lawn" if district in ("terraces", "suburb") and (b["kind"] == "kit" or b["style"] in ("victorian", "georgian")) else "yard"
        for scale in (1.0, 0.75, 0.5, 0.3):
            gd = depth * scale
            if gd < 6:
                break
            poly = rect(back_mid, facing, b["w"], gd)
            if poly.buffer(-0.8).within(block) and not overlaps(poly):
                gardens.append(dict(x=round(back_mid[0], 1), z=round(back_mid[1], 1), deg=b["deg"], w=b["w"], d=round(gd, 1), kind=kind))
                add_footprint(poly)
                if kind == "lawn" and rng.random() < 0.35 and gd > 14:
                    spot = L.add(back_mid, L.mul(facing, -gd * rng.uniform(0.4, 0.8)))
                    plant(spot[0], spot[1], rng.uniform(0.6, 1.0), 1)
                break


class Spacer:
    """Keeps new trees at least `gap` studs from the ones already placed (a grid of buckets for speed)."""

    def __init__(self, gap):
        self.gap = gap
        self.cells = {}

    def free(self, x, z, gap=None):
        g = gap or self.gap
        cx, cz = int(x // 20), int(z // 20)
        for i in (cx - 1, cx, cx + 1):
            for j in (cz - 1, cz, cz + 1):
                for (px, pz) in self.cells.get((i, j), ()):
                    if (px - x) ** 2 + (pz - z) ** 2 < g * g:
                        return False
        return True

    def add(self, x, z):
        self.cells.setdefault((int(x // 20), int(z // 20)), []).append((x, z))


spacer = Spacer(12)


def plant(x, z, size, form):
    trees.append(dict(x=round(x, 1), z=round(z, 1), s=round(size, 2), f=form))
    spacer.add(x, z)


def random_points(piece, count):
    """`count` random points inside `piece` (tries a few times as many)."""
    from shapely.prepared import prep
    inside = prep(piece)
    x0, z0, x1, z1 = piece.bounds
    out = []
    for _ in range(count * 6):
        if len(out) >= count:
            break
        x, z = rng.uniform(x0, x1), rng.uniform(z0, z1)
        if inside.contains(Point(x, z)):
            out.append((x, z))
    return out


def woods(piece):
    """Thick woodland like the edges of BVS: tall slim trees and big round ones packed close at random, with
    bushes along the edge."""
    inner = piece.buffer(-5)
    if inner.is_empty:
        return
    for x, z in random_points(inner, int(piece.area / 260)):
        if spacer.free(x, z, 14):
            if rng.random() < 0.55:
                plant(x, z, rng.uniform(1.25, 2.0), 2)
            else:
                plant(x, z, rng.uniform(1.0, 1.6), 1)
    # Undergrowth along the edge
    for poly in (list(inner.geoms) if hasattr(inner, "geoms") else [inner]):
        edge = poly.exterior
        d = 0.0
        while d < edge.length:
            if rng.random() < 0.6:
                q = edge.interpolate(d)
                plant(q.x + rng.uniform(-3, 3), q.y + rng.uniform(-3, 3), rng.uniform(0.8, 1.5), 4)
            d += rng.uniform(7, 13)


def parkland(piece, density=1.0):
    """Open grass with clumps of trees and bushes and the odd tree on its own, like a London park."""
    inner = piece.buffer(-6)
    if inner.is_empty:
        return
    from shapely.prepared import prep
    inside = prep(inner)
    clumps = max(1, int(piece.area * density / 7000))
    for cx, cz in random_points(inner, clumps):
        radius = rng.uniform(18, 40)
        for _ in range(rng.randint(3, 9)):
            x, z = cx + rng.gauss(0, radius / 2), cz + rng.gauss(0, radius / 2)
            if inside.contains(Point(x, z)) and spacer.free(x, z, 11):
                plant(x, z, rng.uniform(0.8, 1.35), 3 if rng.random() < 0.4 else 1)
        for _ in range(rng.randint(1, 4)):
            x, z = cx + rng.gauss(0, radius / 1.5), cz + rng.gauss(0, radius / 1.5)
            if inside.contains(Point(x, z)) and spacer.free(x, z, 5):
                plant(x, z, rng.uniform(0.7, 1.3), 4)
    for x, z in random_points(inner, int(piece.area * density / 9000)):
        if spacer.free(x, z, 16):
            plant(x, z, rng.uniform(0.9, 1.4), 3 if rng.random() < 0.5 else 1)


CENTRE = ("city", "westend", "mansions", "westminster", "docklands", "canary", "southbank")


def interior_fill(block, district, edge_block):
    """Whatever is still empty in the block. Like BVS: the middle of town is solid buildings; out of the centre
    the insides of blocks are open grass with trees (parkland round the estates, back-land behind the
    terraces), industrial blocks get yards and car parks, and the edge of the map is thick woodland."""
    taken = unary_union([f for f in footprints if f.intersects(block)]) if footprints else None
    left = block.difference(taken.buffer(1.5)) if taken is not None else block
    pieces = list(left.geoms) if hasattr(left, "geoms") else [left]
    u, v, _, _ = L.axes_of(block)
    for piece in pieces:
        if piece.area < 150:
            continue
        if edge_block:
            woods(piece)
            continue
        if district not in CENTRE and district != "industrial":
            # Big open areas get council tower blocks standing in the grass, like the estates in BVS
            if piece.area > 50000:
                from shapely.prepared import prep
                inside = prep(piece.buffer(-30))
                x0, z0, x1, z1 = piece.bounds
                z = z0 + 90
                while z < z1 - 60:
                    x = x0 + 90 + rng.uniform(-30, 30)
                    while x < x1 - 60:
                        if rng.random() < 0.45 and inside.contains(Point(x, z)):
                            facing = L.unit((rng.uniform(-1, 1), rng.uniform(-1, 1)))
                            w, d = rng.uniform(36, 52), rng.uniform(26, 34)
                            front = L.add((x, z), L.mul(facing, d / 2))
                            poly = rect(front, facing, w, d)
                            if poly.buffer(-0.5).within(piece) and not overlaps(poly.buffer(25)):
                                buildings.append(dict(kind="proc", style="council", x=round(front[0], 1), z=round(front[1], 1), deg=deg_of(facing),
                                                      w=round(w, 1), d=round(d, 1), floors=rng.randint(9, 18), seed=rng.randint(1, 9999), back=False))
                                add_footprint(poly.buffer(12))
                        x += rng.uniform(150, 210)
                    z += rng.uniform(150, 210)
                left2 = piece.difference(unary_union([f for f in footprints if f.intersects(piece)]).buffer(2)) if footprints else piece
                for part in (list(left2.geoms) if hasattr(left2, "geoms") else [left2]):
                    if part.area > 150:
                        parkland(part, 1.2)
                continue
            # Open parkland: grass with clumps of trees
            parkland(piece, 1.3 if district == "estate" else 1.0)
            continue
        # The centre and industrial blocks: a grid of lots, lined up with the block
        coords = list(piece.exterior.coords)
        us = [L.dot(p, u) for p in coords]
        vs = [L.dot(p, v) for p in coords]
        step_u = 60 if edge_block else 50
        step_v = 50 if edge_block else 44
        uu = min(us)
        while uu < max(us):
            vv = min(vs)
            while vv < max(vs):
                w = min(step_u, max(us) - uu)
                dd = min(step_v, max(vs) - vv)
                centre = L.add(L.mul(u, uu + w / 2), L.mul(v, vv + dd / 2))
                if w > 14 and dd > 14:
                    facing = v
                    width, depth = w - 2, dd - 2
                    if edge_block:
                        # Backdrop buildings face into the map, where people will see them from
                        towards = L.unit(L.mul(centre, -1))
                        options = [(u, dd - 2, w - 2), (L.mul(u, -1), dd - 2, w - 2), (v, w - 2, dd - 2), (L.mul(v, -1), w - 2, dd - 2)]
                        facing, width, depth = max(options, key=lambda o: L.dot(o[0], towards))
                    front_mid = L.add(centre, L.mul(facing, depth / 2))
                    poly = rect(front_mid, facing, width, depth)
                    if poly.buffer(-0.5).within(block) and not overlaps(poly):
                        if edge_block or district in ("city", "westend", "mansions", "westminster", "docklands"):
                            style = "backdrop" if edge_block else ("office" if district == "city" else "mansion")
                            (dlo, dhi), (flo, fhi) = STYLES[style]
                            buildings.append(dict(kind="proc", style=style, x=round(front_mid[0], 1), z=round(front_mid[1], 1), deg=deg_of(facing),
                                                  w=round(width, 1), d=round(depth, 1), floors=rng.randint(flo, fhi), seed=rng.randint(1, 9999), back=True))
                            add_footprint(poly)
                        else:
                            kind = "carpark" if rng.random() < 0.5 else "yard"
                            gardens.append(dict(x=round(front_mid[0], 1), z=round(front_mid[1], 1), deg=deg_of(facing), w=round(width, 1), d=round(depth, 1), kind=kind))
                            add_footprint(poly)
                            if kind == "lawn" and rng.random() < 0.5:
                                plant(centre[0], centre[1], rng.uniform(0.7, 1.2), 1)
                vv += step_v
            uu += step_u


# ---------------------------------------------------------------------------------------------
# Gaps along the frontages: walls, fences, hedges
# ---------------------------------------------------------------------------------------------

def gap_walls(run, gaps, district):
    for s0, s1, why in gaps:
        if s1 - s0 < 1.5 or why == "open":
            continue
        p0, _, out0 = run_at(run, s0)
        p1, _, out1 = run_at(run, s1)
        if district == "suburb":
            kind = "hedge"
        elif district in ("industrial", "docklands"):
            kind = "fence"
        elif district in ("city", "westminster", "westend", "mansions"):
            kind = "railing"
        else:
            kind = "brick"
        walls.append(dict(x0=round(p0[0], 1), z0=round(p0[1], 1), x1=round(p1[0], 1), z1=round(p1[1], 1), kind=kind))


# ---------------------------------------------------------------------------------------------
# The whole map
# ---------------------------------------------------------------------------------------------

def run():
    road_zone = L.roads_shape(9)
    lines = []
    for r in L.roads:
        pts, samples, dist, stations = L.sampled(r)
        lines.append((r, LineString(samples)))
    edge = L.OUTLINE_SHAPE.exterior.buffer(3)
    blocks = L.land_blocks(extra=1.0)
    print(f"  filling {len(blocks)} blocks")
    for block in blocks:
        block = block.buffer(0)
        c = block.representative_point()
        district = L.district_at(c.x, c.y)
        edge_block = block.intersects(edge)
        before = len(buildings)
        runs, corners = block_runs(block, road_zone, lines)
        trims = {}
        # Corner buildings first
        size = CORNER_SIZE.get(district, 0)
        for cn in corners:
            if not size or cn["run_before"] is None:
                continue
            cs = size
            # Square on the outgoing street, its front on that street and one side on the incoming one
            facing = cn["out_out"]
            front_mid = L.add(cn["c"], L.mul(cn["dout"], cs / 2))
            style = "pub" if district in ("terraces", "estate") and rng.random() < 0.5 else ("corner" if district in ("terraces", "estate", "suburb") else pick(FRONTAGE.get(district, [("georgian", 1)])))
            if style.startswith("kit:"):
                style = "shops"
            (dlo, dhi), (flo, fhi) = STYLES[style]
            if style in ("office", "stone", "mansion", "concrete", "warehouse"):
                floors = rng.randint(flo, fhi)
            else:
                floors = rng.randint(flo, fhi)
            for sc in (1.0, 0.85, 0.7):
                if place_building("proc", style, front_mid, facing, cs * sc, cs, floors, block):
                    trims[(id(cn["run_after"]), "start")] = cs * sc
                    trims[(id(cn["run_before"]), "end")] = cs
                    # Which side of the building faces the other street: +1 its right (in the game's terms), -1 its left
                    right = (-facing[1], facing[0])
                    buildings[-1]["flank"] = 1 if L.dot(L.sub(cn["c"], front_mid), right) > 0 else -1
                    break
        # Then every frontage
        for rn in runs:
            total = run_length(rn)
            s0 = trims.get((id(rn), "start"), 0.0)
            s1 = total - trims.get((id(rn), "end"), 0.0)
            if s1 - s0 < 8:
                continue
            if rn["road"].profile == "dual" and district in ("terraces", "suburb"):
                pass
            gaps = fill_run(rn, s0, s1, district, block, edge_block)
            gap_walls(rn, gaps, district)
        for b in buildings[before:]:
            b["_block"] = block
        back_fill(block, district)
        interior_fill(block, district, edge_block)
    for b in buildings:
        b.pop("_block", None)
    kinds = {}
    for b in buildings:
        key = b["style"] if b["kind"] == "proc" else "kit:" + KIT[b["style"]][0]
        kinds[key] = kinds.get(key, 0) + 1
    print(f"  {len(buildings)} buildings, {len(gardens)} gardens and yards, {len(walls)} walls, {len(trees)} trees")
    print("  " + ", ".join(f"{k} {v}" for k, v in sorted(kinds.items(), key=lambda kv: -kv[1])))
    draw()
    emit()


# ---------------------------------------------------------------------------------------------
# Picture and output
# ---------------------------------------------------------------------------------------------
COLOURS = {
    "kit:terrace": (176, 110, 86), "kit:semi": (190, 130, 100), "kit:detached": (200, 150, 110), "kit:large": (205, 160, 120),
    "kit:shop": (210, 90, 90), "kit:shopwide": (220, 110, 100), "georgian": (225, 215, 195), "victorian": (165, 100, 80),
    "shops": (200, 100, 120), "mansion": (150, 70, 60), "stone": (230, 225, 205), "office": (110, 150, 190),
    "concrete": (165, 165, 160), "warehouse": (140, 80, 60), "shed": (150, 160, 170), "council": (180, 180, 170),
    "pub": (90, 50, 40), "corner": (120, 60, 90), "backdrop": (120, 120, 125),
}


def draw():
    img, g = L.picture()
    L.draw_roads(g, labels=False)
    for gd in gardens:
        facing = (-math.sin(math.radians(gd["deg"])), -math.cos(math.radians(gd["deg"])))
        poly = rect((gd["x"], gd["z"]), facing, gd["w"], gd["d"])
        col = {"lawn": (110, 160, 90), "yard": (170, 170, 165), "carpark": (120, 120, 125)}[gd["kind"]]
        g.polygon([L.P(*c) for c in poly.exterior.coords], fill=col)
    for b in buildings:
        facing = (-math.sin(math.radians(b["deg"])), -math.cos(math.radians(b["deg"])))
        poly = rect((b["x"], b["z"]), facing, b["w"], b["d"])
        key = b["style"] if b["kind"] == "proc" else "kit:" + KIT[b["style"]][0]
        g.polygon([L.P(*c) for c in poly.exterior.coords], fill=COLOURS.get(key, (200, 200, 200)), outline=(60, 50, 45))
    for w in walls:
        g.line([L.P(w["x0"], w["z0"]), L.P(w["x1"], w["z1"])], fill=(240, 240, 80), width=2)
    for t in trees:
        x, z = L.P(t["x"], t["z"])
        g.ellipse([x - 2, z - 2, x + 2, z + 2], fill=(40, 100, 40))
    img.save(ROOT / "docs" / "map-fill.png")
    print("  picture: docs/map-fill.png")


MAX_SCRIPT = 150_000  # Roblox won't hold more than 200,000 characters in one script, so the data is split


def emit():
    styles = sorted({b["style"] for b in buildings})
    index = {s: i + 1 for i, s in enumerate(styles)}
    rows = {"buildings": [], "gardens": [], "walls": [], "trees": []}
    for b in buildings:
        rows["buildings"].append("{%d,%d,%s,%s,%s,%s,%s,%d,%d,%d,%d}" % (1 if b["kind"] == "kit" else 0, index[b["style"]], b["x"], b["z"], b["deg"], b["w"], b["d"], b["floors"], b["seed"], 1 if b.get("back") else 0, b.get("flank", 0)))
    gk = {"lawn": 1, "yard": 2, "carpark": 3}
    for gd in gardens:
        rows["gardens"].append("{%d,%s,%s,%s,%s,%s}" % (gk[gd["kind"]], gd["x"], gd["z"], gd["deg"], gd["w"], gd["d"]))
    wk = {"brick": 1, "fence": 2, "hedge": 3, "railing": 4}
    for w in walls:
        rows["walls"].append("{%d,%s,%s,%s,%s}" % (wk[w["kind"]], w["x0"], w["z0"], w["x1"], w["z1"]))
    for t in trees:
        rows["trees"].append("{%s,%s,%s,%d}" % (t["x"], t["z"], t["s"], t.get("f", 1)))
    # Pack the rows into data scripts, each under the size limit
    chunks = []
    current, size = {k: [] for k in rows}, 0
    for kind, items in rows.items():
        for item in items:
            if size + len(item) + 2 > MAX_SCRIPT:
                chunks.append(current)
                current, size = {k: [] for k in rows}, 0
            current[kind].append(item)
            size += len(item) + 2
    chunks.append(current)
    server = ROOT / "src" / "server"
    for old in server.glob("LondonFillData*.luau"):
        old.unlink()
    for i, chunk in enumerate(chunks, 1):
        body = ["--!nocheck", f"-- Part {i} of the data in LondonFill. MADE BY tools/london_fill.py: don't edit by hand.", "return {"]
        for kind, items in chunk.items():
            body.append(f"\t{kind} = {{")
            for k in range(0, len(items), 8):
                body.append("\t\t" + ",".join(items[k:k + 8]) + ",")
            body.append("\t},")
        body.append("}")
        (server / f"LondonFillData{i}.luau").write_text("\n".join(body) + "\n")
    lines = [
        "--!nocheck",
        "-- Everything that fills London's blocks, as data. MADE BY tools/london_fill.py (run tools/london_layout.py):",
        "-- don't edit this file by hand. LondonMap builds it. The rows themselves are in LondonFillData1, 2...",
        "--   styles: names used by buildings (kit building names, or CityBuildings styles)",
        "--   buildings: { kit (1) or parts (0), style index, front x, front z, turn (degrees), width, depth, storeys, seed, back (1/0), flank }",
        "--     the front edge is centred on (x, z); turn 0 faces north (-z)",
        "--     flank: on a corner, 1 if the building's right side faces a street too, -1 its left side, 0 neither",
        "--   gardens: { kind (1 lawn, 2 yard, 3 car park), front x, front z, turn, width, depth }",
        "--   walls: { kind (1 brick, 2 fence, 3 hedge, 4 railing), x0, z0, x1, z1 }",
        "--   trees: { x, z, size, form (1 round, 2 tall, 3 wide, 4 bush) }",
        "",
        "local fill = {",
        "\tstyles = { " + ", ".join(f'"{s}"' for s in styles) + " },",
        "\tbuildings = {},",
        "\tgardens = {},",
        "\twalls = {},",
        "\ttrees = {},",
        "}",
        f"for i = 1, {len(chunks)} do",
        "\tlocal part = require(script.Parent:FindFirstChild(\"LondonFillData\" .. i))",
        "\tfor kind, rows in part do",
        "\t\tfor _, row in rows do",
        "\t\t\ttable.insert(fill[kind], row)",
        "\t\tend",
        "\tend",
        "end",
        "return fill",
    ]
    (server / "LondonFill.luau").write_text("\n".join(lines) + "\n")
    total = sum(len(x) for v in rows.values() for x in v)
    print(f"  wrote src/server/LondonFill.luau and {len(chunks)} data scripts ({total // 1024} KB)")


if __name__ == "__main__":
    run()
