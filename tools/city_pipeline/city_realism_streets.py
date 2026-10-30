"""Eight street pieces for the city realism library (same ids and footprints as the existing street kit; foot-centred, base on y=0, front -Z in glTF).
Blender coordinates: front = +Y. Real construction: slabs with settlement and joints, steel strips and plates with bolts, kerb with drain throat,
lamp with base plate/hand-hole/arm/luminaire, planter + slatted bench, bins in a steel frame, conduit bundle with brackets and junction boxes."""
import math

import city_realism_parts as P
from city_realism_parts import bx, cylv, cylx, cyly, strut


def build_sidewalk_panel(c):
    """6 x 4 m, 0.18 m: six inset slabs with settled heights, hairline joints, expansion strip, service plate and tactile studs."""
    bx(c, -3.0, 3.0, -2.0, 2.0, 0.0, 0.06, "concrete")                              # sub-base
    k = 0
    for ix in range(3):
        for iy in range(2):
            x0, x1 = -3.0 + ix * 2.0 + 0.02, -1.0 + ix * 2.0 - 0.02
            y0, y1 = -2.0 + iy * 2.0 + 0.02, iy * 2.0 - 0.02
            h = 0.17 + c.r(-0.012, 0.01)
            bx(c, x0, x1, y0, y1, 0.06, h, "paving")
            k += 1
    bx(c, -0.04, 0.04, -2.0, 2.0, 0.06, 0.19, "steel_structure")                    # bolted steel expansion strip
    for yy in (-1.8, -1.0, -0.2, 0.6, 1.4):
        cylv(c, 0.0, yy, 0.19, 0.205, 0.016, "equipment_steel", seg=6)
    bx(c, 1.0, 1.9, 0.2, 0.9, 0.17, 0.195, "equipment_steel")                       # service plate with hinge + lifting slot
    bx(c, 1.35, 1.55, 0.5, 0.58, 0.195, 0.205, "steel_structure")
    for xx in (1.05, 1.85):
        for yy in (0.25, 0.85):
            cylv(c, xx, yy, 0.195, 0.21, 0.014, "steel_structure", seg=6)
    for i in range(10):                                                                # tactile studs along the kerb side
        cylv(c, -2.4 + i * 0.12, 1.88, 0.17, 0.19, 0.03, "cladding_patch", seg=8)
        cylv(c, -2.4 + i * 0.12, 1.76, 0.17, 0.19, 0.03, "cladding_patch", seg=8)
    bx(c, -2.9, -1.2, -1.1, -0.2, 0.17, 0.18, "cladding_patch")                      # bright replacement patch
    c.dirty.append((-2.0, -0.6, 0.18, 0.6, 0.3))
    c.dirty.append((2.2, 1.0, 0.18, 0.5, 0.4))


def build_curb_segment(c):
    """6 m kerb: stone face with chamfer, gutter lip, steel edge angle, joint every 2 m and a paint stripe."""
    bx(c, -3.0, 3.0, -0.1, 0.1, 0.0, 0.2, "concrete")
    bx(c, -3.0, 3.0, 0.08, 0.1103, 0.0, 0.17, "paving")                              # gutter-side lip
    bx(c, -3.0, 3.0, -0.1, -0.06, 0.2, 0.2205, "steel_structure")                   # steel angle on the top edge
    for x in (-2.0, 0.0, 2.0):
        bx(c, x - 0.012, x + 0.012, -0.1, 0.11, 0.0, 0.2205, "plastic_rubber")      # joints
    for x in (-2.7, -1.3, 0.7, 2.4):
        cylv(c, x, -0.08, 0.2205, 0.226, 0.014, "equipment_steel", seg=6)
    bx(c, 0.35, 1.75, 0.1, 0.112, 0.05, 0.19, "cladding_patch")                      # yellow no-parking paint
    bx(c, -1.9, -1.4, -0.1, 0.0, 0.2205, 0.223, "cladding_patch")


def build_drain_cover(c):
    """1.2 x 0.7 m cast frame, parallel bars, sump below, lifting eyes."""
    bx(c, -0.6, 0.6, -0.35, 0.35, 0.0, 0.05, "concrete")
    bx(c, -0.6, 0.6, -0.35, -0.27, 0.04, 0.066, "steel_structure")
    bx(c, -0.6, 0.6, 0.27, 0.35, 0.04, 0.066, "steel_structure")
    bx(c, -0.6, -0.52, -0.27, 0.27, 0.04, 0.066, "steel_structure")
    bx(c, 0.52, 0.6, -0.27, 0.27, 0.04, 0.066, "steel_structure")
    bx(c, -0.52, 0.52, -0.27, 0.27, 0.0, 0.02, "plastic_rubber")                      # dark sump
    for i in range(11):
        bx(c, -0.48 + i * 0.096, -0.44 + i * 0.096, -0.27, 0.27, 0.025, 0.06, "equipment_steel")
    for y in (-0.15, 0.15):
        cylx(c, -0.5, 0.5, y, 0.05, 0.012, "steel_structure", seg=5)
    bx(c, -0.1, 0.1, 0.2, 0.26, 0.05, 0.066, "cladding_patch")
    c.dirty.append((0.0, 0.0, 0.06, 0.5, 0.6))


def build_street_lamp(c):
    """7.9 m column: base plate + anchor bolts + plinth, hand-hole door, tapered pole in two sections, banner bracket, cranked arm, luminaire."""
    bx(c, -0.35, 0.35, -0.35, 0.35, 0.0, 0.25, "concrete")
    bx(c, -0.28, 0.28, -0.28, 0.28, 0.25, 0.29, "steel_structure")
    for sx in (-1, 1):
        for sy in (-1, 1):
            cylv(c, sx * 0.22, sy * 0.22, 0.29, 0.36, 0.014, "equipment_steel", seg=6)
            cylv(c, sx * 0.22, sy * 0.22, 0.31, 0.33, 0.026, "equipment_steel", seg=6)
    c.m.cyl((0, 0, 0.29), (0, 0, 4.0), 0.14, 0.1, "steel_structure", seg=12, smooth=False)
    cylv(c, 0, 0, 3.9, 4.1, 0.115, "equipment_steel", seg=12)                         # sleeve joint
    c.m.cyl((0, 0, 4.0), (0, 0, 7.6), 0.1, 0.07, "steel_structure", seg=12, smooth=False)
    bx(c, -0.07, 0.07, 0.1, 0.13, 0.7, 1.3, "equipment_steel")                       # hand-hole cover
    for z in (0.75, 1.25):
        cyly(c, 0.0, 0.13, 0.15, z, 0.012, "steel_structure", seg=6)
    bx(c, -0.05, 0.05, 0.1, 0.12, 2.0, 2.15, "cladding_patch")                       # asset tag
    bx(c, -0.05, 0.05, 0.08, 0.5, 6.0, 6.05, "steel_structure")                       # banner bracket
    bx(c, -0.04, 0.04, 0.45, 0.5, 5.2, 6.05, "steel_structure")
    c.m.tube([(0, 0, 7.4), (0, 0.35, 7.7), (0, 1.1, 7.85), (0, 1.75, 7.78)], [0.05, 0.045, 0.04, 0.038], "steel_structure", seg=8, samples=12, round_ends=(False, False))
    bx(c, -0.1, 0.1, 1.55, 1.9, 7.7, 7.85, "steel_structure")                         # luminaire housing
    bx(c, -0.14, 0.14, 1.5, 1.85, 7.62, 7.7, "steel_structure")
    bx(c, -0.1, 0.1, 1.55, 1.8, 7.58, 7.62, "lamp_glass")                             # lens
    bx(c, -0.03, 0.03, 1.55, 1.9, 7.85, 7.88, "equipment_steel")
    P.junction_box(c, 0.0, 0.1, 1.9, 0.14, 0.2, 0.06)
    c.anchor("street", (0.0, 1.7, 7.5), (0, 0.15, -1), (1.0, 0.82, 0.55), 14.0, 2.4, False)
    c.dirty.append((0, 0, 0.3, 0.9, 0.5))


def build_bollard(c):
    """0.34 x 1.1 m crash bollard: baseplate with bolts, concrete-filled steel tube, reflective band, dented cap."""
    bx(c, -0.17, 0.17, -0.17, 0.17, 0.0, 0.03, "steel_structure")
    for sx in (-1, 1):
        for sy in (-1, 1):
            cylv(c, sx * 0.13, sy * 0.13, 0.03, 0.06, 0.016, "equipment_steel", seg=6)
    cylv(c, 0, 0, 0.03, 1.05, 0.1, "concrete", seg=12)
    cylv(c, 0, 0, 0.03, 0.2, 0.108, "steel_structure", seg=12)
    cylv(c, 0, 0, 0.55, 0.7, 0.106, "cladding_patch", seg=12)
    cylv(c, 0, 0, 1.05, 1.11, 0.105, "steel_structure", seg=12)
    c.m.cyl((0, 0, 1.11), (0, 0, 1.115), 0.08, 0.06, "equipment_steel", seg=12, smooth=False)
    c.dirty.append((0, 0, 0.03, 0.4, 0.4))


def build_bench_planter(c):
    """3.8 m concrete planter with a steel-frame slatted bench on one side, soil, a shrub and a rail-lipped edge."""
    bx(c, -1.9, 0.5, -0.6, 0.6, 0.0, 0.7, "concrete")
    bx(c, -1.95, 0.55, -0.65, 0.65, 0.7, 0.78, "concrete")
    bx(c, -1.7, 0.3, -0.4, 0.4, 0.6, 0.72, "plastic_rubber")                          # soil
    for i, (x, y, r) in enumerate(((-1.2, 0.0, 0.32), (-0.5, 0.15, 0.26), (-0.1, -0.1, 0.22))):
        for k, (dx, dy, dz, sc) in enumerate(((0, 0, 0, 1.0), (0.12, 0.08, 0.1, 0.7), (-0.1, -0.07, 0.07, 0.75))):
            c.m.sphere((x + dx, y + dy, 0.92 + dz), r * sc, "render_plaster", scale=(1, 1, 0.8), seg=10, rings=6, smooth=True)
        c.tints.append((x, y, 0.95, r * 1.6, (0.42, 0.95, 0.38)))
        cylv(c, x, y, 0.7, 0.9, 0.025, "plastic_rubber", seg=5)
    for x in (0.65, 1.85):                                                             # bench frame
        bx(c, x - 0.03, x + 0.03, -0.55, 0.55, 0.0, 0.45, "steel_structure")
        bx(c, x - 0.03, x + 0.03, -0.55, -0.5, 0.45, 0.95, "steel_structure")
        bx(c, x - 0.05, x + 0.05, -0.6, 0.6, 0.0, 0.03, "steel_structure")
    for i in range(6):                                                                 # seat slats
        bx(c, 0.55, 1.95, -0.5 + i * 0.17, -0.5 + i * 0.17 + 0.14, 0.45, 0.5, "cladding_patch" if i == 3 else "plastic_rubber")
    for i in range(3):
        bx(c, 0.55, 1.95, -0.58, -0.55, 0.62 + i * 0.12, 0.7 + i * 0.12, "plastic_rubber")
    bx(c, 0.1, 0.5, 0.2, 0.5, 0.78, 0.8, "plastic_rubber")                            # cup litter on the lip
    bx(c, -1.9, 1.9, 0.6, 0.75, 0.0, 0.02, "paving")


def build_refuse_station(c):
    """3 x 2.2 m steel cage with three wheeled bins, lid hinges, stencilled plates, a hose bib and a drip tray."""
    bx(c, -1.5, 1.5, -0.75, 0.75, 0.0, 0.08, "concrete")
    for x in (-1.45, 1.45):
        for y in (-0.7, 0.7):
            cylv(c, x, y, 0.08, 2.2, 0.04, "steel_structure", seg=6)
    for y in (-0.7, 0.7):
        cylx(c, -1.45, 1.45, y, 2.2, 0.03, "steel_structure", seg=5)
        cylx(c, -1.45, 1.45, y, 0.3, 0.025, "steel_structure", seg=5)
    cyly(c, -1.45, -0.7, 0.7, 2.2, 0.03, "steel_structure", seg=5)
    cyly(c, 1.45, -0.7, 0.7, 2.2, 0.03, "steel_structure", seg=5)
    for k in range(9):                                                                 # back mesh slats
        bx(c, -1.4 + k * 0.35, -1.4 + k * 0.35 + 0.02, -0.72, -0.7, 0.3, 2.15, "steel_structure")
    for i, (x, mat) in enumerate(((-0.95, "plastic_rubber"), (0.0, "cladding_patch"), (0.95, "plastic_rubber"))):
        bx(c, x - 0.4, x + 0.4, -0.45, 0.4, 0.15, 1.0, mat)
        bx(c, x - 0.43, x + 0.43, -0.48, 0.45, 1.0, 1.06, "plastic_rubber")
        c.m.cyl((x - 0.43, -0.48, 1.06), (x + 0.43, -0.48, 1.06), 0.035, 0.035, "steel_structure", seg=6, smooth=False)
        for sx in (-0.33, 0.33):
            cyly(c, x + sx, 0.4, 0.5, 0.2, 0.09, "plastic_rubber", seg=8)
        bx(c, x - 0.15, x + 0.15, 0.4, 0.42, 0.55, 0.8, "equipment_steel")
    cylv(c, 1.2, -0.65, 0.3, 1.0, 0.02, "equipment_steel", seg=6)                     # hose bib
    bx(c, 1.1, 1.3, -0.7, -0.55, 0.95, 1.05, "equipment_steel")
    bx(c, -1.3, 1.3, 0.55, 0.75, 0.08, 0.12, "equipment_steel")
    c.dirty.append((0, 0, 0.1, 1.3, 0.5))


def build_alley_conduit(c):
    """8 m wide alley crossing: gantry frame, conduit bundle and pipes on brackets, junction boxes, sagging cable, warning plate."""
    for sx in (-3.9, 3.9):
        P.column_h(c, sx, 0.0, 0.0, 4.35, 0.26, plinth=0.25)
    P.beam_i(c, -4.0, 4.0, 0.0, 4.35, 0.3)
    P.knee_brace(c, -3.7, 0.0, 4.2, 0.8, 1)
    P.knee_brace(c, 3.7, 0.0, 4.2, 0.8, -1)
    for i, (z, r, mat) in enumerate(((3.9, 0.07, "equipment_steel"), (3.7, 0.05, "plastic_rubber"), (3.55, 0.05, "plastic_rubber"), (3.35, 0.09, "cladding_patch"))):
        cylx(c, -3.9, 3.9, 0.0, z, r, mat, seg=8)
    for x in (-3.0, -1.6, 0.0, 1.5, 3.0):
        bx(c, x - 0.03, x + 0.03, -0.08, 0.08, 3.2, 4.2, "steel_structure")
        for z in (3.9, 3.35):
            bx(c, x - 0.08, x + 0.08, -0.1, 0.1, z - 0.12, z - 0.09, "steel_structure")
    P.junction_box(c, -2.2, 0.05, 2.0, 0.34, 0.5, 0.16)
    P.junction_box(c, 2.6, 0.05, 2.2, 0.3, 0.4, 0.14)
    cylv(c, -2.2, 0.0, 2.5, 3.5, 0.04, "plastic_rubber", seg=6)
    cylv(c, 2.6, 0.0, 2.6, 3.3, 0.04, "plastic_rubber", seg=6)
    P.cable_sag(c, (-3.9, 0.05, 3.1), (3.9, 0.05, 3.1), 0.45, 0.02)
    bx(c, -0.5, 0.5, 0.12, 0.14, 4.0, 4.3, "cladding_patch")
    P.hazard_stripe(c, -4.1, 4.1, 0.17, 4.1, 4.28, 24)
    P.lamp_fixture(c, 0.0, 0.1, 3.0, 0.3, rng_m=7.0)
    c.dirty.append((0, 0, 4.0, 3.0, 0.2))


STREETS = {
    "sidewalk_panel": (build_sidewalk_panel, 6.0, 4.0),
    "curb_segment": (build_curb_segment, 6.0, 0.2),
    "drain_cover": (build_drain_cover, 1.2, 0.7),
    "street_lamp": (build_street_lamp, 0.7, 4.0),
    "bollard": (build_bollard, 0.34, 0.34),
    "bench_planter": (build_bench_planter, 3.8, 1.3),
    "refuse_station": (build_refuse_station, 3.0, 1.5),
    "alley_conduit": (build_alley_conduit, 8.0, 0.6),
}
