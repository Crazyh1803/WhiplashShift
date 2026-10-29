"""Reusable human-scale detail for the inhabited City kit: stylised people, neon shop signs with pictograms, load-bearing piers.

Pure Kit-primitive code (no bpy): every function takes the workshop Kit `k` and works in whatever frame is current, so the
same helpers serve market_habitat, service_tenement and freight_depot. People face local +Y at rot=0 (static sculpture, no rig).
Face-local signs follow the workshop face_frame convention: wall surface y=0, local +x reads left-to-right, +y toward the street.
"""
import math
from math import cos, pi, sin

from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------- palettes (multiply the semantic material base)

SKIN = [(1.0, 0.82, 0.68), (0.95, 0.7, 0.52), (0.82, 0.58, 0.42), (0.62, 0.43, 0.31), (0.46, 0.31, 0.23), (1.0, 0.78, 0.7)]
SHIRT = [(0.9, 0.25, 0.2), (0.2, 0.66, 0.62), (0.95, 0.7, 0.2), (0.5, 0.6, 0.25), (0.55, 0.25, 0.5), (0.25, 0.42, 0.8),
         (0.95, 0.9, 0.8), (0.85, 0.42, 0.2), (0.3, 0.5, 0.35)]
TROUSER = [(0.7, 0.75, 0.9), (1.0, 0.85, 0.6), (0.6, 0.6, 0.6), (0.9, 0.7, 0.55), (0.55, 0.7, 0.75)]
HAIR = [("steel", (0.6, 0.6, 0.6)), ("machinery", (1.0, 0.6, 0.4)), ("machinery", (0.55, 0.4, 0.3)), ("trim", (1.0, 1.0, 1.0)),
        ("sinew", (0.9, 1.1, 1.0)), ("machinery", (1.0, 1.0, 1.0))]
BOOT = (1.0, 0.72, 0.52)

ROLES = ("stand", "shopper", "walker", "worker")


# ---------------------------------------------------------------------------- primitives

def elathe(k, prof, mat, seg=8):
    """Ellipsoidal lathe about local z: prof = [(rx, ry, z)...] ascending z; a zero radius is a pole."""
    rings, faces, verts = [], [], []
    for rx, ry, z in prof:
        if rx < 1e-6:
            rings.append([len(verts)])
            verts.append((0.0, 0.0, z))
        else:
            rings.append([len(verts) + i for i in range(seg)])
            verts += [(rx * cos(2 * pi * i / seg), ry * sin(2 * pi * i / seg), z) for i in range(seg)]
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1:
                faces.append((a[0], b[j], b[i]))
            elif len(b) == 1:
                faces.append((a[i], a[j], b[0]))
            else:
                faces.append((a[i], a[j], b[j], b[i]))
    if len(rings[0]) > 1:
        faces.append(tuple(reversed(rings[0])))
    if len(rings[-1]) > 1:
        faces.append(tuple(rings[-1]))
    k._mk(verts, faces, mat, fix="trust")


def limb(k, a, b, ra, rb, mat, seg=6):
    with k.along(a, b) as length:
        k.lathe([(ra, 0.0), (rb, length)], mat, seg, False)


def solve2(s, t, l1, l2, pole):
    """Two-bone IK: elbow/knee point for root s, end target t, lengths l1/l2, bend toward `pole`. Returns (joint, end)."""
    s, t, pole = Vector(s), Vector(t), Vector(pole)
    d = t - s
    dist = min(max(d.length, 1e-4), (l1 + l2) * 0.998)
    dirn = d.normalized()
    t = s + dirn * dist
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    perp = pole - dirn * pole.dot(dirn)
    perp = perp.normalized() if perp.length > 1e-6 else Vector((0, 1, 0)).cross(dirn).normalized()
    return s + dirn * a + perp * h, t


def _skin(rng):
    return rng.choice(SKIN)


# ---------------------------------------------------------------------------- person parts

def head(k, rng, skin, hair_style, hair, hat, hat_tint, female):
    """Local head frame: chin at z=0, crown at ~0.235, face toward +y."""
    with k.look(1.0, skin):
        elathe(k, [(0.046, 0.05, 0.0), (0.078, 0.088, 0.055), (0.09, 0.1, 0.125), (0.07, 0.082, 0.205), (0.0, 0.0, 0.238)],
               "ceramic", 8)
        # nose: wedge in the yz plane, cheeks/brows read from the side
        k.prism([(0.088, 0.075), (0.138, 0.07), (0.092, 0.108)], -0.014, 0.014, "ceramic", "yz")
        for sx in (-1, 1):
            k.box(sx * 0.094 - 0.009, sx * 0.094 + 0.009, -0.01, 0.022, 0.095, 0.145, "ceramic", skip=("yn", "zn"))      # ear
    with k.look(0.5):
        for sx in (-0.04, 0.04):
            k.box(sx - 0.011, sx + 0.011, 0.09, 0.1, 0.118, 0.133, "cavity", skip=("yn", "zn", "zp", "xn", "xp"))         # eye
        k.box(-0.022, 0.022, 0.093, 0.101, 0.07, 0.078, "sinew", skip=("yn", "zn", "zp", "xn", "xp"))                    # mouth
    br = hair if hair else ("steel", (0.6, 0.6, 0.6))
    if hat == "hardhat":
        with k.look(1.0, hat_tint):
            elathe(k, [(0.1, 0.112, 0.14), (0.098, 0.11, 0.2), (0.07, 0.085, 0.25), (0.0, 0.0, 0.262)], "ceramic", 8)
            k.box(-0.012, 0.012, 0.0, 0.16, 0.205, 0.26, "ceramic")                                                      # ridge
            k.box(-0.11, 0.11, 0.085, 0.17, 0.14, 0.15, "ceramic")                                                       # brim
        return
    if hat == "wide":
        with k.look(1.0, hat_tint):
            elathe(k, [(0.185, 0.185, 0.17), (0.1, 0.11, 0.185), (0.098, 0.108, 0.24), (0.0, 0.0, 0.25)], "trim", 8)
        return
    if hat == "cap":
        with k.look(1.0, hat_tint):
            elathe(k, [(0.096, 0.108, 0.15), (0.094, 0.106, 0.215), (0.05, 0.062, 0.25), (0.0, 0.0, 0.255)], "ceramic", 8)
            k.box(-0.08, 0.08, 0.09, 0.19, 0.152, 0.162, "ceramic")                                                      # visor
        return
    if hat == "beanie":
        with k.look(1.0, hat_tint):
            elathe(k, [(0.096, 0.108, 0.14), (0.097, 0.108, 0.2), (0.06, 0.07, 0.25), (0.0, 0.0, 0.262)], "ceramic", 8)
        return
    if hat == "wrap":
        with k.look(1.0, hat_tint):
            elathe(k, [(0.096, 0.108, 0.17), (0.097, 0.108, 0.215), (0.06, 0.07, 0.245), (0.0, 0.0, 0.255)], "ceramic", 8)
            k.box(0.02, 0.1, -0.12, -0.085, 0.14, 0.2, "ceramic")
        return
    with k.look(1.0, br[1]):
        if hair_style == "bald":
            return
        elathe(k, [(0.093, 0.104, 0.15), (0.085, 0.098, 0.215), (0.0, 0.0, 0.25)], br[0], 8)
        k.box(-0.095, 0.095, -0.108, -0.06, 0.12, 0.215, br[0], skip=("yn",))                                           # back of head
        if hair_style == "long":
            k.box(-0.1, 0.1, -0.12, -0.07, -0.12, 0.12, br[0], skip=("yn",))
            for sx in (-1, 1):
                k.box(sx * 0.1, sx * 0.1 + 0.028, -0.08, 0.04, -0.06, 0.18, br[0])
        elif hair_style == "bun":
            k.joint(0.0, -0.095, 0.2, 0.05, br[0], 6)
        elif hair_style == "pony":
            k.pipe((0.0, -0.1, 0.2), (0.0, -0.17, 0.06), 0.03, br[0], 5)


def boot(k, ankle, yaw, tint):
    """Boot: shaft up the shin plus a wedge foot (heel/sole/toe) rotated by yaw about z."""
    with k.look(1.0, tint):
        with k.at(ankle[0], ankle[1], 0.0, rz=yaw):
            k.prism([(-0.075, ankle[2] - 0.09), (0.2, ankle[2] - 0.09), (0.2, ankle[2] - 0.045), (0.12, ankle[2] + 0.015),
                     (-0.075, ankle[2] + 0.015)], -0.052, 0.052, "steel", "yz")


def hand(k, wrist, direction, skin, grip=True):
    d = Vector(direction).normalized()
    with k.look(1.0, skin):
        end = Vector(wrist) + d * 0.1
        with k.along(wrist, end):
            elathe(k, [(0.0, 0.0, -0.01), (0.034, 0.018, 0.03), (0.03, 0.015, 0.075), (0.0, 0.0, 0.1)], "ceramic", 6)
        if grip:
            base = Vector(wrist) + d * 0.025
            limb(k, base, base + (d + Vector((0.0, 0.6, 0.0))).normalized() * 0.065, 0.014, 0.011, "ceramic", 4)


# ---------------------------------------------------------------------------- the person

def person(k, x, y, z, rng, rot=0.0, seated=False, tone=None, role=None, stool=False, reach=0.55, scale=None):
    """Stylised static person (~0.6-0.8k tris): shaped head/face/hair or headwear, neck, shoulders, waist, bent clothed limbs,
    hands and boots. role: stand | shopper | walker | worker | vendor | diner (seated). Faces local +Y at rot=0; the seated pose
    puts the pelvis 0.46 m above `z` with hands resting `reach` m ahead at table height (0.78)."""
    role = role or ("diner" if seated else rng.choice(ROLES))
    seated = seated or role == "diner"
    s = scale or rng.uniform(0.94, 1.05)
    skin = _skin(rng)
    shirt = rng.choice(SHIRT)
    trou = rng.choice(TROUSER)
    hair = rng.choice(HAIR)
    female = rng.random() < 0.5
    style = rng.choice(("short", "long", "bun", "pony", "bald") if female else ("short", "short", "bald", "pony"))
    hat = {"worker": "hardhat", "vendor": rng.choice(("wrap", "cap")), "shopper": rng.choice((None, "wide", "beanie", None)),
           "walker": rng.choice((None, "cap", "beanie")), "stand": rng.choice((None, "cap", "wrap", None)),
           "diner": rng.choice((None, "cap", None))}[role]
    hat_tint = rng.choice(SHIRT)
    side = rng.choice((-1, 1))
    k.stack.append(k.stack[-1] @ Matrix.Translation((x, y, z)) @ Matrix.Rotation(rot, 4, "Z") @ Matrix.Diagonal((s, s, s, 1.0)))
    try:
        with k.part(".people"):
            _build(k, rng, role, seated, side, skin, shirt, trou, hair, style, female, hat, hat_tint, reach, stool)
    finally:
        k.stack.pop()


def _build(k, rng, role, seated, side, skin, shirt, trou, hair, style, female, hat, hat_tint, reach, stool):
    hip_z = 0.46 if seated else 0.93
    lean = -0.12 if seated else (-0.08 if role == "worker" else 0.0)        # negative = lean toward the front (+Y)
    if role == "walker":
        lean = -0.06
    hip = Vector((0.0, -0.02 if seated else 0.0, hip_z + (0.0 if seated else 0.0)))
    R = Matrix.Rotation(lean, 3, "X")

    def up(p):                                    # torso-frame point -> person frame
        return hip + R @ Vector(p)

    sh = {-1: up((-0.2, 0.0, 0.5)), 1: up((0.2, 0.0, 0.5))}
    hp = {-1: hip + Vector((-0.095, 0.0, 0.0)), 1: hip + Vector((0.095, 0.0, 0.0))}
    # --- target poses (person frame) ----------------------------------------------------------------------------------
    ank = 0.085
    feet = {-1: Vector((-0.115, 0.02, ank)), 1: Vector((0.115, 0.02, ank))}
    yaws = {-1: -0.12, 1: 0.12}
    hands = {-1: Vector((-0.27, 0.03, 0.82)), 1: Vector((0.27, 0.03, 0.82))}
    pole_a = {-1: Vector((-1, -0.7, -0.4)), 1: Vector((1, -0.7, -0.4))}
    head_yaw, head_tilt = rng.uniform(-0.35, 0.35), rng.uniform(-0.05, 0.1)
    prop = None
    if seated:
        feet = {-1: Vector((-0.12, 0.44, ank)), 1: Vector((0.12, 0.40, ank))}
        yaws = {-1: 0.1, 1: -0.08}
        hands = {-1: Vector((-0.17, reach, 0.79)), 1: Vector((0.19, reach - 0.05, 0.81))}
        pole_a = {-1: Vector((-1, -0.3, -0.6)), 1: Vector((1, -0.3, -0.6))}
        prop = "cup" if rng.random() < 0.6 else None
    elif role == "vendor":
        feet = {-1: Vector((-0.12, 0.0, ank)), 1: Vector((0.13, 0.04, ank))}
        hands = {-1: Vector((-0.2, 0.46, 1.04)), 1: Vector((0.22, 0.42, 1.2))}
        pole_a = {-1: Vector((-1, -0.2, -0.6)), 1: Vector((1, -0.2, -0.6))}
        prop = "bowl"
        head_yaw = rng.uniform(-0.25, 0.25)
    elif role == "shopper":
        hands = {side: Vector((0.30 * side, 0.08, 0.80)), -side: Vector((-0.17 * side, 0.3, 1.22))}
        pole_a = {side: Vector((side, -0.5, -0.5)), -side: Vector((-side * 0.6, -0.6, -0.8))}
        feet = {-1: Vector((-0.1, -0.03, ank)), 1: Vector((0.13, 0.1, ank))}
        prop = "bag"
    elif role == "walker":
        stride = 0.24
        feet = {-1: Vector((-0.1, stride, ank)), 1: Vector((0.1, -stride, ank + 0.05))}
        hands = {-1: Vector((-0.2, -0.14, 0.88)), 1: Vector((0.22, 0.2, 0.9))}
        pole_a = {-1: Vector((-1, -1, -0.3)), 1: Vector((1, 0.4, -0.5))}
        if rng.random() < 0.5:
            feet = {-s_: Vector((-s_ * 0.1, -v.y, v.z)) for s_, v in feet.items()}
            hands = {-s_: Vector((-s_ * 0.2, -v.y, v.z)) for s_, v in hands.items()}
        prop = "bag" if rng.random() < 0.5 else None
    elif role == "worker":
        hands = {side: Vector((0.18 * side, 0.45, 1.18)), -side: Vector((-0.34 * side, 0.08, 1.0))}
        pole_a = {side: Vector((side, -0.3, -0.5)), -side: Vector((-side * 1.0, -0.8, -0.2))}
        feet = {-1: Vector((-0.17, 0.0, ank)), 1: Vector((0.17, 0.12, ank))}
        prop = "wrench"
    else:                                                                    # stand: one hand on hip, one relaxed
        hands = {side: Vector((0.23 * side, 0.05, 1.0)), -side: Vector((-0.26 * side, 0.12, 0.84))}
        pole_a = {side: Vector((side, -0.3, 0.1)), -side: Vector((-side, -0.7, -0.4))}
        feet = {-1: Vector((-0.12, 0.0, ank)), 1: Vector((0.1, 0.1, ank))}
    # --- legs ------------------------------------------------------------------------------------------------------
    for sd in (-1, 1):
        knee, ankle = solve2(hp[sd], feet[sd], 0.42, 0.40, Vector((sd * 0.12, 1.0, 0.1)))
        with k.look(1.0, trou):
            limb(k, hp[sd], knee, 0.082, 0.064, "machinery", 6)
            limb(k, knee, ankle, 0.064, 0.05, "machinery", 6)
        with k.look(1.0, BOOT):
            limb(k, ankle + (knee - ankle).normalized() * 0.17, ankle, 0.056, 0.063, "steel", 6)
        boot(k, ankle, yaws[sd], BOOT)
    # --- stool -----------------------------------------------------------------------------------------------------
    if seated and stool:
        k.cyl(0.0, -0.02, 0.0, 0.17, 0.02, "steel", seg=8)
        k.cyl(0.0, -0.02, 0.02, 0.03, 0.34, "steel", seg=6)
        k.cyl(0.0, -0.02, 0.36, 0.18, 0.04, "machinery", seg=8)
    # --- pelvis + torso (shirt over waist, trousers below) -----------------------------------------------------------
    with k.at(hip.x, hip.y, hip.z, rx=lean):
        with k.look(1.0, trou):
            elathe(k, [(0.14, 0.1, -0.1), (0.175, 0.118, 0.0), (0.16, 0.108, 0.1)], "machinery", 8)
        with k.look(1.0, shirt):
            if role == "vendor" or (female and not seated and rng.random() < 0.3):
                elathe(k, [(0.255, 0.17, -0.33), (0.2, 0.14, -0.1), (0.15, 0.105, 0.08)], "ceramic", 8)      # tunic skirt
            elathe(k, [(0.15, 0.105, 0.05), (0.168, 0.112, 0.18), (0.2, 0.12, 0.33), (0.205, 0.108, 0.46), (0.1, 0.07, 0.535)],
                   "ceramic", 8)
            for sd in (-1, 1):
                with k.at(sd * 0.2, 0.0, 0.49):                                        # flattened shoulder cap
                    elathe(k, [(0.0, 0.0, -0.04), (0.065, 0.06, 0.0), (0.0, 0.0, 0.03)], "ceramic", 6)
        with k.look(1.0, skin):
            limb(k, (0, 0.0, 0.5), (0, 0.01, 0.585), 0.044, 0.04, "ceramic", 6)        # neck
        if role == "vendor":
            with k.look(1.0, (0.95, 0.9, 0.8)):
                k.box(-0.15, 0.15, 0.1, 0.13, -0.12, 0.42, "ceramic")                   # apron bib + skirt
            for sd in (-1, 1):
                k.beam((sd * 0.14, 0.1, 0.42), (sd * 0.05, 0.0, 0.55), 0.025, 0.012, "ceramic")
        with k.at(0.0, 0.015, 0.575, rx=head_tilt, rz=head_yaw):
            head(k, rng, skin, style, hair, hat, hat_tint, female)
    # --- arms ------------------------------------------------------------------------------------------------------
    sleeve_long = rng.random() < 0.65
    for sd in (-1, 1):
        elbow, wrist = solve2(sh[sd], hands[sd], 0.29, 0.26, pole_a[sd])
        with k.look(1.0, shirt):
            limb(k, sh[sd], elbow, 0.052, 0.042, "ceramic", 6)
            k.joint(elbow.x, elbow.y, elbow.z, 0.044, "ceramic", 6)
        with k.look(1.0, shirt if sleeve_long else skin):
            limb(k, elbow, wrist, 0.042, 0.033, "ceramic", 6)
        hand(k, wrist, (wrist - elbow), skin, grip=prop is not None or role != "walker")
    # --- props -----------------------------------------------------------------------------------------------------
    hsd = {"shopper": side, "walker": 1, "worker": side, "vendor": 1}.get(role, 1)
    hp_ = hands[hsd]
    if prop == "bag":
        c = rng.choice(SHIRT)
        with k.look(1.0, c):
            k.box(hp_.x - 0.1, hp_.x + 0.1, hp_.y - 0.07, hp_.y + 0.07, hp_.z - 0.42, hp_.z - 0.1, "ceramic")
        with k.look(1.0, (0.4, 0.35, 0.3)):
            for xx in (-0.06, 0.06):
                k.pipe((hp_.x + xx, hp_.y, hp_.z - 0.1), (hp_.x + xx * 0.3, hp_.y, hp_.z + 0.0), 0.007, "steel", 4)
        with k.look(1.0, (0.45, 0.7, 0.3)):
            k.cyl(hp_.x - 0.04, hp_.y, hp_.z - 0.1, 0.03, 0.2, "ceramic", seg=5)
        with k.look(1.0, (0.9, 0.7, 0.4)):
            k.cyl(hp_.x + 0.05, hp_.y, hp_.z - 0.1, 0.02, 0.28, "trim", seg=5)
    elif prop == "bowl":
        wb = hands[1]
        with k.look(1.0, (0.95, 0.9, 0.85)):
            with k.at(wb.x, wb.y + 0.04, wb.z + 0.02):
                k.lathe([(0.0, -0.05), (0.06, -0.05), (0.1, 0.0), (0.12, 0.05)], "ceramic", 8, True)
    elif prop == "wrench":
        wb = hands[side]
        with k.look(1.0, (0.8, 0.8, 0.8)):
            k.beam((wb.x, wb.y - 0.05, wb.z - 0.14), (wb.x + 0.03 * side, wb.y + 0.14, wb.z + 0.2), 0.03, 0.014, "machinery")
    elif prop == "cup":
        wc = hands[1]
        k.cyl(wc.x, wc.y, wc.z - 0.01, 0.034, 0.075, "ceramic", seg=6)


# ---------------------------------------------------------------------------- neon text and pictograms

FONT57 = {
    "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110", "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01110 10001 10000 10111 10001 10001 01110", "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "11111 00100 00100 00100 00100 00100 11111", "K": "10001 10010 10100 11000 10100 10010 10001",
    "L": "10000 10000 10000 10000 10000 10000 11111", "M": "10001 11011 10101 10101 10001 10001 10001",
    "N": "10001 11001 10101 10011 10001 10001 10001", "O": "01110 10001 10001 10001 10001 10001 01110",
    "P": "11110 10001 10001 11110 10000 10000 10000", "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 01010 01010 00100",
    "W": "10001 10001 10001 10101 10101 11011 10001", "Y": "10001 10001 01010 00100 00100 00100 00100",
    "&": "01100 10010 10100 01000 10101 10010 01101", "-": "00000 00000 00000 11111 00000 00000 00000",
    " ": "00000 00000 00000 00000 00000 00000 00000",
}


def text_width(text, px):
    return len(text) * 6 * px - px


def neon_text(k, text, x, z, px, y, mat="glow_cyan", rng=None):
    """Emissive 5x7 letters (front faces only, row runs merged) starting at x, baseline z, standing at y."""
    cx = x
    for ch in text:
        rows = FONT57[ch].split()
        for r, row in enumerate(rows):
            c = 0
            while c < 5:
                if row[c] == "1":
                    e = c
                    while e < 5 and row[e] == "1":
                        e += 1
                    k.box(cx + c * px, cx + e * px, y, y + 0.008, z + (6 - r) * px, z + (7 - r) * px, mat,
                          skip=("yn", "zn", "zp", "xn", "xp"))
                    c = e
                else:
                    c += 1
        cx += 6 * px
    return cx - x - px


def glyph_row(k, n, x, z, px, y, mat, rng):
    """Short invented glyph row (not Latin letters): chunky strokes on a 3x5 grid, drawn as front-face rectangles."""
    cx = x
    for _ in range(n):
        cells = set()
        for _ in range(rng.randint(3, 4)):
            kind = rng.choice(("h", "v", "d"))
            a = rng.randrange(5 if kind == "v" else 3)
            if kind == "h":
                cells |= {(c, a * 2) for c in range(rng.randint(0, 1), 3)}
            elif kind == "v":
                c = rng.randrange(3)
                cells |= {(c, r) for r in range(a, min(5, a + rng.randint(2, 3)))}
            else:
                cells |= {(c, c * 2 + a % 2) for c in range(3)}
        for c, r in cells:
            k.box(cx + c * px, cx + (c + 1) * px, y, y + 0.008, z + (4 - r) * px, z + (5 - r) * px, mat,
                  skip=("yn", "zn", "zp", "xn", "xp"))
        cx += 4 * px
    return cx - x - px


def _arc(cx, cy, rx, ry, a0, a1, n):
    return [(cx + rx * cos(a0 + (a1 - a0) * i / n), cy + ry * sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def _steam(u, v0):
    return [(u, v0), (u + 0.1, v0 + 0.18), (u - 0.08, v0 + 0.36), (u + 0.06, v0 + 0.55)]


def _bowl(cv=0.1):
    return [_arc(0, cv, 0.8, 0.7, pi, 2 * pi, 8), [(-0.9, cv), (0.9, cv)], [(-0.32, cv - 0.78), (0.32, cv - 0.78)]]


ICONS = {   # name -> list of (polyline, 'a' primary | 'b' secondary colour) in unit coordinates (-1..1)
    "bowl_leaf": [(p, "a") for p in _bowl()] + [(_steam(-0.35, 0.3), "a"), (_steam(0.0, 0.3), "a"),
                                                 ([(0.5, 0.25), (0.62, 0.6), (0.95, 0.85), (0.86, 0.5), (0.62, 0.32), (0.5, 0.25)], "b"),
                                                 ([(0.5, 0.25), (0.78, 0.62)], "b")],
    "noodles": [(p, "a") for p in _bowl()] + [([(-0.55, 0.1), (-0.42, 0.35), (-0.55, 0.55), (-0.38, 0.8)], "a"),
                                               ([(-0.2, 0.1), (-0.08, 0.35), (-0.2, 0.55), (-0.04, 0.8)], "a"),
                                               ([(0.15, 0.1), (0.27, 0.35), (0.15, 0.55), (0.3, 0.8)], "a"),
                                               ([(0.25, 0.1), (0.95, 0.95)], "b"), ([(0.5, 0.1), (1.05, 0.7)], "b")],
    "cup": [([(-0.55, 0.35), (-0.45, -0.45), (0.45, -0.45), (0.55, 0.35), (-0.55, 0.35)], "a"), ([(-0.85, -0.58), (0.85, -0.58)], "a"),
            (_arc(0.58, -0.05, 0.3, 0.32, -pi / 2, pi / 2, 6), "a"), (_steam(-0.2, 0.5), "a"), (_steam(0.2, 0.5), "a"),
            ([(0.08, 0.25), (-0.15, -0.05), (0.12, -0.05), (-0.1, -0.38)], "b")],
    "basket": [([(-0.85, 0.05), (-0.6, -0.7), (0.6, -0.7), (0.85, 0.05), (-0.85, 0.05)], "a"), ([(-0.3, 0.05), (-0.25, -0.7)], "a"),
               ([(0.3, 0.05), (0.25, -0.7)], "a"), ([(-0.72, -0.3), (0.72, -0.3)], "a"), (_arc(0, 0.05, 0.6, 0.6, 0, pi, 8), "a"),
               (_arc(-0.28, 0.32, 0.22, 0.22, 0, 2 * pi, 8), "b"), ([(-0.28, 0.54), (-0.2, 0.7)], "b"),
               ([(0.15, 0.1), (0.62, 0.5)], "b"), ([(0.1, 0.2), (0.55, 0.62)], "b")],
    "wrench_gear": [(_arc(0, 0.0, 0.42, 0.42, 0, 2 * pi, 12), "a")] +
                   [([(0.42 * cos(a), 0.42 * sin(a)), (0.6 * cos(a), 0.6 * sin(a))], "a") for a in [i * pi / 4 for i in range(8)]] +
                   [(_arc(0, 0, 0.16, 0.16, 0, 2 * pi, 6), "a"),
                    ([(-0.9, -0.9), (0.55, 0.55), (0.45, 0.8), (0.7, 0.95), (0.95, 0.7), (0.8, 0.45)], "b"),
                    ([(0.9, -0.9), (-0.55, 0.55)], "b")],
    "shirt_spool": [([(-0.55, 0.7), (-0.9, 0.45), (-0.78, 0.15), (-0.62, 0.25), (-0.62, -0.65), (0.1, -0.65), (0.1, 0.25),
                      (0.26, 0.15), (0.38, 0.45), (0.03, 0.7), (-0.18, 0.5), (-0.55, 0.7)], "a"),
                    ([(0.5, -0.1), (1.0, -0.1)], "b"), ([(0.5, -0.85), (1.0, -0.85)], "b"), ([(0.6, -0.1), (0.6, -0.85)], "b"),
                    ([(0.9, -0.1), (0.9, -0.85)], "b"), ([(0.6, -0.35), (0.9, -0.5), (0.6, -0.65)], "b")],
    "arrow_up": [([(0.0, -0.8), (0.0, 0.8)], "a"), ([(-0.5, 0.3), (0.0, 0.8), (0.5, 0.3)], "a"),
                 ([(-0.6, -0.8), (-0.6, -0.5), (-0.3, -0.5), (-0.3, -0.2)], "b"), ([(0.6, -0.8), (0.6, -0.5), (0.3, -0.5), (0.3, -0.2)], "b")],
    "drop": [([(0.0, 0.9), (0.55, 0.0), (0.55, -0.3), (0.35, -0.65), (0.0, -0.8), (-0.35, -0.65), (-0.55, -0.3), (-0.55, 0.0),
               (0.0, 0.9)], "a"), ([(-0.25, -0.1), (-0.25, -0.4), (-0.1, -0.55)], "b")],
}


def pictogram(k, name, cx, cz, size, y, mat_a, mat_b, r=0.014):
    """Neon-tube pictogram in the face-local xz plane, centred (cx, cz), half-extent `size`, tubes at y."""
    for pts, col in ICONS[name]:
        m = mat_a if col == "a" else mat_b
        P = [(cx + u * size, y, cz + v * size) for u, v in pts]
        for a, b in zip(P[:-1], P[1:]):
            if (Vector(a) - Vector(b)).length > 1e-4:
                k.pipe(a, b, r * size / 0.3, m, 4)


# ---------------------------------------------------------------------------- shop signs

SHOPS = [   # name, icon, text colour, icon colour, backing tint, glyph row?
    ("ROOT KITCHEN", "bowl_leaf", "glow_amber", "glow_cyan", (0.35, 0.16, 0.12), False),
    ("REDLINE RAMEN", "noodles", "glow_cyan", "glow_amber", (0.3, 0.12, 0.14), True),
    ("BOLT & BREW", "cup", "glow_amber", "glow_cyan", (0.22, 0.2, 0.3), False),
    ("ORBIT PANTRY", "basket", "glow_cyan", "glow_amber", (0.12, 0.25, 0.2), True),
    ("PATCH BAY", "wrench_gear", "glow_amber", "glow_cyan", (0.2, 0.22, 0.28), True),
    ("RETHREAD", "shirt_spool", "glow_cyan", "glow_amber", (0.3, 0.14, 0.26), False),
]
PLAQUES = [("STAIRS", "arrow_up", "glow_amber", "glow_cyan", (0.2, 0.2, 0.2)), ("WATER", "drop", "glow_cyan", "glow_amber", (0.14, 0.22, 0.3))]


def _bracket(k, x, zc, y0, y1, ysoft):
    """Wall flange + stand-off arm + knuckle + lower diagonal gusset."""
    k.box(x - 0.05, x + 0.05, y0, y0 + 0.02, zc - 0.08, zc + 0.08, "steel", skip=("yn", "zn"))
    k.pipe((x, y0 + 0.02, zc), (x, y1, zc), 0.025, "machinery", 5)
    k.beam((x, y0 + 0.02, zc - 0.22), (x, y1 - 0.02, zc - 0.03), 0.03, 0.03, "machinery")


def shop_sign(k, x0, x1, z0, z1, name, icon, col_a, col_b, tint, glyphs, rng, y0=0.0, y1=0.42, hang_to=None):
    """Illuminated fascia: dark backing board, framed, neon name + pictogram (+ glyph row). Mounted on stand-off brackets from
    the wall at y0 (board back at y1), or, with hang_to=z, hung by four rods from an overhead soffit at that height."""
    w, h = x1 - x0, z1 - z0
    yb = y1
    with k.look(1.0, tint):
        k.box(x0, x1, yb, yb + 0.08, z0, z1, "ceramic", skip=("yn",))
    with k.look(0.8):
        for (a, b, c, d) in ((x0 - 0.04, x1 + 0.04, z0 - 0.04, z0), (x0 - 0.04, x1 + 0.04, z1, z1 + 0.04),
                              (x0 - 0.04, x0, z0, z1), (x1, x1 + 0.04, z0, z1)):
            k.box(a, b, yb - 0.01, yb + 0.12, c, d, "steel")
    if hang_to is None:
        for bx in (x0 + 0.25, x1 - 0.25):
            _bracket(k, bx, z0 + h * 0.3, y0, yb, 0)
        for bx in (x0 + 0.25, x1 - 0.25):
            k.pipe((bx, y0 + 0.02, z1 - h * 0.2), (bx, yb, z1 - h * 0.2), 0.02, "machinery", 4)
    else:
        for bx in (x0 + 0.3, x1 - 0.3):
            k.box(bx - 0.07, bx + 0.07, yb - 0.03, yb + 0.11, hang_to - 0.03, hang_to, "steel", skip=("zp",))    # soffit plate
            k.pipe((bx, yb + 0.04, z1 + 0.04), (bx, yb + 0.04, hang_to - 0.03), 0.018, "machinery", 4)
            k.joint(bx, yb + 0.04, z1 + 0.05, 0.035, "steel", 5)
    ys = yb + 0.08
    isz = h * 0.4
    icx = x0 + 0.12 + isz
    pictogram(k, icon, icx, z0 + h / 2, isz, ys + 0.015, col_b, col_a)
    tx0 = icx + isz + 0.2
    avail = x1 - 0.15 - tx0
    px = min(0.034, avail / (len(name) * 6 - 1))
    tw = text_width(name, px)
    ztxt = z0 + h * (0.52 if glyphs else 0.3)
    if not glyphs:
        ztxt = z0 + (h - 7 * px) / 2
    neon_text(k, name, tx0 + (avail - tw) / 2, ztxt, px, ys, col_a)
    if glyphs:
        gpx = 0.026
        gw = 4 * 4 * gpx - gpx
        glyph_row(k, 4, tx0 + (avail - gw) / 2, z0 + 0.075, gpx, ys, col_b, rng)
    # underline tube
    k.pipe((tx0, ys + 0.015, z0 + 0.05), (x1 - 0.15, ys + 0.015, z0 + 0.05), 0.008, col_b, 4)


def blade_sign(k, cx, cy, ztop, zbot, icon, col_a, col_b, tint, rot, deck_z):
    """Hanging pictogram panel (dark tablet with neon tubes on both faces) on two rods from the deck underside."""
    hh = (ztop - zbot) / 2
    zc = (ztop + zbot) / 2
    with k.at(cx, cy, 0.0, rz=rot):
        with k.look(1.0, tint):
            k.box(-0.02, 0.02, -hh, hh, zbot, ztop, "ceramic")
        with k.look(0.8):
            k.box(-0.035, 0.035, -hh - 0.03, hh + 0.03, zbot - 0.03, zbot, "steel")
            k.box(-0.035, 0.035, -hh - 0.03, hh + 0.03, ztop, ztop + 0.03, "steel")
            for sy in (-hh - 0.03, hh):
                k.box(-0.035, 0.035, sy, sy + 0.03, zbot, ztop, "steel")
        for sy in (-hh * 0.7, hh * 0.7):
            k.pipe((0, sy, ztop + 0.03), (0, sy, deck_z), 0.014, "machinery", 5)
            k.joint(0, sy, ztop + 0.03, 0.03, "steel", 6)
        # tubes: icon drawn in the xz plane of a frame whose +y faces out of each panel face
        for sd in (-1, 1):
            with k.at(sd * 0.03, 0.0, 0.0, rz=(-pi / 2 if sd > 0 else pi / 2)):
                pictogram(k, icon, 0.0, zc, hh * 0.78, 0.0, col_a, col_b, 0.014)


# ---------------------------------------------------------------------------- load-bearing pier

def pier(k, x, y, z0, z1, r=0.28, head=0.45, bolts=True):
    """Segmented, grounded pier: footing slab, stepped plinth + base flange with anchor bolts, three drum shafts separated by
    flanged collars, flared capital with gussets and a head plate that meets the deck underside at z1."""
    k.box(x - 0.52, x + 0.52, y - 0.52, y + 0.52, z0, z0 + 0.1, "steel")
    k.frustum(x, y, z0 + 0.1, z0 + 0.42, 0.42, 0.42, 0.33, 0.33, "ceramic")
    k.box(x - 0.36, x + 0.36, y - 0.36, y + 0.36, z0 + 0.42, z0 + 0.5, "machinery")
    if bolts:
        for sx in (-1, 1):
            for sy in (-1, 1):
                k.box(x + sx * 0.3 - 0.035, x + sx * 0.3 + 0.035, y + sy * 0.3 - 0.035, y + sy * 0.3 + 0.035, z0 + 0.5, z0 + 0.57, "steel",
                      skip=("zn",))
    zb, zt = z0 + 0.5, z1 - 0.95
    n = 3
    hh = (zt - zb) / n
    for i in range(n):
        za = zb + i * hh
        with k.at(x, y, za + 0.02):
            k.lathe([(r * 0.9, 0.0), (r, (hh - 0.1) * 0.5), (r * 0.92, hh - 0.1)], "ceramic", 8, True)
        if i < n - 1:
            with k.at(x, y, za + hh - 0.08):
                k.lathe([(r * 1.12, 0.0), (r * 1.12, 0.12)], "machinery", 8, True)
    with k.at(x, y, zt - 0.08):
        k.lathe([(r * 1.14, 0.0), (r * 1.14, 0.1)], "machinery", 8, True)
    k.frustum(x, y, zt + 0.02, z1 - 0.38, r * 0.95, r * 0.95, head * 0.8, head * 0.8, "ceramic")
    k.box(x - head, x + head, y - head, y + head, z1 - 0.38, z1, "ceramic")
    k.box(x - head - 0.03, x + head + 0.03, y - head - 0.03, y + head + 0.03, z1 - 0.46, z1 - 0.38, "steel")
    for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):                                  # gusset ribs: shaft collar -> head plate
        k.beam((x + sx * r * 0.9, y + sy * r * 0.9, zt + 0.05), (x + sx * head * 0.95, y + sy * head * 0.95, z1 - 0.46), 0.07, 0.05,
               "machinery")


# ---------------------------------------------------------------------------- identity-specific stall goods

def _dish(k, x, y, z, r, tint, inner=None, seg=7):
    with k.look(1.0, tint):
        with k.at(x, y, z):
            k.lathe([(0.0, 0.0), (r * 0.5, 0.0), (r, r * 0.75), (r * 1.03, r * 0.85)], "ceramic", seg, False)
    if inner:
        with k.look(1.0, inner):
            with k.at(x, y, z + r * 0.6):
                k.lathe([(0.0, 0.0), (r * 0.95, 0.0)], "sinew", seg, True)


def _pot(k, x, y, z, r, h, tint, lid=True):
    with k.look(1.0, tint):
        with k.at(x, y, z):
            k.lathe([(r * 0.9, 0.0), (r, 0.03), (r, h), (r * 1.06, h + 0.02)], "machinery", 8, True)
            if lid:
                k.lathe([(r * 1.08, h + 0.02), (r * 0.9, h + 0.06), (r * 0.25, h + 0.1)], "steel", 8, False)
                k.cyl(0.0, 0.0, h + 0.1, 0.03, 0.04, "steel", seg=5)
    for sd in (-1, 1):
        k.box(x + sd * r * 1.03 - 0.025, x + sd * r * 1.03 + 0.025 + sd * 0.05, y - 0.02, y + 0.02, z + h * 0.7, z + h * 0.7 + 0.03, "steel")


def shop_goods(k, shop, w, rng, zc=1.02, yc=0.1):
    """Counter and back-shelf goods that match the shop identity (counter top at zc, centre line yc, stall width w)."""
    x = 0.25
    if shop == 0:                                                  # ROOT KITCHEN: pots, stacked bowls, leafy veg basket
        _pot(k, x + 0.2, yc, zc, 0.2, 0.3, (0.7, 0.8, 0.75))
        _pot(k, x + 0.75, yc, zc, 0.16, 0.22, (1.0, 0.8, 0.6))
        for i in range(3):
            _dish(k, x + 1.3, yc, zc + i * 0.06, 0.1, (0.95, 0.9, 0.8))
        k.cyl(x + 1.8, yc, zc, 0.17, 0.12, "machinery", seg=7)
        with k.look(1.0, (0.4, 0.8, 0.35)):
            for i in range(5):
                k.beam((x + 1.8 + 0.06 * (i - 2), yc, zc + 0.1), (x + 1.8 + 0.12 * (i - 2), yc + 0.04, zc + 0.36), 0.05, 0.015, "ceramic")
    elif shop == 1:                                                 # REDLINE RAMEN: bowls with red broth, stock pot, chopstick jar
        _pot(k, x + 0.25, yc, zc, 0.22, 0.34, (0.55, 0.55, 0.6))
        for i in range(4):
            _dish(k, x + 0.85 + 0.26 * i, yc + 0.05, zc, 0.1, (0.95, 0.9, 0.85), (0.9, 0.3, 0.2))
        k.cyl(x + 2.0, yc, zc, 0.06, 0.2, "machinery", seg=6)
        for i in range(5):
            k.beam((x + 2.0 + 0.012 * (i - 2), yc, zc + 0.15), (x + 2.0 + 0.04 * (i - 2), yc + 0.02, zc + 0.42), 0.012, 0.012, "trim")
    elif shop == 2:                                                 # BOLT & BREW: espresso machine, cups, kettle, bean sacks
        k.box(x, x + 0.6, yc - 0.15, yc + 0.15, zc, zc + 0.38, "machinery")
        k.box(x + 0.02, x + 0.58, yc - 0.17, yc + 0.17, zc + 0.38, zc + 0.44, "steel")
        for sx in (0.15, 0.45):
            k.box(x + sx - 0.03, x + sx + 0.03, yc + 0.15, yc + 0.22, zc + 0.15, zc + 0.3, "steel")
            k.cyl(x + sx, yc + 0.2, zc + 0.04, 0.04, 0.06, "ceramic", seg=5)
        k.box(x + 0.22, x + 0.38, yc + 0.152, yc + 0.158, zc + 0.3, zc + 0.36, "glow_amber", skip=("yn",))
        for i in range(5):
            k.cyl(x + 0.85 + 0.15 * i, yc + 0.05, zc, 0.045, 0.08, "ceramic", seg=6)
        _pot(k, x + 1.8, yc, zc, 0.12, 0.2, (0.6, 0.6, 0.65), lid=False)
        with k.look(1.0, (0.75, 0.6, 0.4)):
            k.box(x + 2.15, x + 2.5, yc - 0.1, yc + 0.12, zc, zc + 0.3, "trim")
    elif shop == 3:                                                 # ORBIT PANTRY: crates of fruit, jars, bread, hanging net
        for i in range(2):
            cx0 = x + 0.9 * i
            k.box(cx0, cx0 + 0.7, yc - 0.18, yc + 0.2, zc, zc + 0.2, "machinery")
            for j in range(6):
                with k.look(1.0, rng.choice(((0.95, 0.4, 0.2), (0.6, 0.8, 0.3), (0.95, 0.75, 0.2), (0.85, 0.25, 0.25)))):
                    k.joint(cx0 + 0.12 + 0.11 * (j % 5), yc - 0.07 + 0.14 * (j // 5), zc + 0.24, 0.065, "ceramic", 6)
        for i in range(4):
            with k.look(1.0, rng.choice(((0.9, 0.6, 0.3), (0.5, 0.8, 0.5), (0.9, 0.3, 0.4)))):
                k.cyl(x + 1.95 + 0.14 * i, yc, zc, 0.05, 0.16, "ceramic", seg=6)
        with k.look(1.0, (0.85, 0.65, 0.35)):
            k.beam((x + 2.3, yc - 0.1, zc + 0.05), (x + 2.75, yc + 0.1, zc + 0.09), 0.09, 0.09, "trim")
    elif shop == 4:                                                 # PATCH BAY: gears, wrenches, toolbox, vise, parts bins
        k.box(x, x + 0.55, yc - 0.15, yc + 0.15, zc, zc + 0.2, "steel")
        k.box(x + 0.02, x + 0.53, yc - 0.17, yc + 0.17, zc + 0.2, zc + 0.23, "machinery")
        for i in range(3):
            k.cyl(x + 0.85 + 0.03 * i, yc, zc + 0.04 * i, 0.12 - 0.015 * i, 0.04, "steel", seg=8)
        for i in range(3):
            k.beam((x + 1.4 + 0.09 * i, yc - 0.15, zc + 0.02), (x + 1.4 + 0.09 * i, yc + 0.18, zc + 0.03), 0.035, 0.015, "machinery")
        k.box(x + 1.85, x + 2.15, yc - 0.12, yc + 0.12, zc, zc + 0.14, "machinery")
        k.box(x + 2.0, x + 2.1, yc - 0.12, yc + 0.12, zc + 0.14, zc + 0.2, "steel")
        for i in range(2):
            k.box(x + 2.3 + 0.2 * i, x + 2.45 + 0.2 * i, yc - 0.14, yc + 0.14, zc, zc + 0.11, "trim")
    else:                                                           # RETHREAD: garment rail, folded stacks, fabric bolts, spools
        zr = zc + 0.95
        for sx in (x - 0.1, w - 0.55):
            k.box(sx - 0.02, sx + 0.02, yc - 0.02, yc + 0.02, zc, zr, "steel", skip=("zn",))
        k.pipe((x - 0.1, yc, zr), (w - 0.55, yc, zr), 0.012, "steel", 5)
        n = max(3, int((w - 0.65 - x) / 0.32))
        for i in range(n):
            gx = x + 0.1 + i * (w - 0.8 - x) / n
            with k.look(1.0, rng.choice(SHIRT)):
                k.box(gx, gx + 0.26, yc - 0.015, yc + 0.015, zr - rng.uniform(0.45, 0.62), zr - 0.04, "ceramic")
                k.box(gx - 0.08, gx, yc - 0.012, yc + 0.012, zr - 0.3, zr - 0.06, "ceramic")
                k.box(gx + 0.26, gx + 0.34, yc - 0.012, yc + 0.012, zr - 0.3, zr - 0.06, "ceramic")
        for i in range(3):
            with k.look(1.0, rng.choice(SHIRT)):
                k.box(x + 0.05, x + 0.4, yc - 0.15, yc + 0.15, zc + i * 0.05, zc + 0.05 + i * 0.05, "ceramic")
        for i in range(2):
            with k.look(1.0, rng.choice(SHIRT)):
                k.cyl(x + 0.7 + 0.2 * i, yc + 0.12, zc + 0.1, 0.07, 0.25, "ceramic", seg=6)
