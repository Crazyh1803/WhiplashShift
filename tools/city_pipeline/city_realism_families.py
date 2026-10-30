"""Eight building families for the city realism conversion. Blender coordinates: x across the frontage, y front(+)/back(-), z up; the facade
plane is y=0 and the body occupies y in [-D, 0]. Each build_<id>(ctx) returns nothing; LOD1[id] lists simplified masses of the same footprint."""
import math

import city_realism_parts as P
from city_realism_parts import bx, cylv, cylx, cyly, strut

T = 0.3          # exterior wall thickness


def windows_grid(c, cols_x, floors, z0, fh, ww, wh, sill, y, mat_skip=(), kinds=None, openings=None, frame="steel_structure"):
    """Window grid: returns openings list; draws windows after the wall is cut. cols_x are window centres."""
    ops = []
    for fi in range(floors):
        zb = z0 + fi * fh + sill
        for ci, x in enumerate(cols_x):
            if (fi, ci) in mat_skip:
                continue
            ops.append((x - ww / 2, x + ww / 2, zb, zb + wh, fi, ci))
    return ops


def draw_windows(c, ops, y, kinds=None, frame="steel_structure"):
    for (a, b, z0, z1, fi, ci) in ops:
        k = kinds.get((fi, ci)) if kinds else None
        P.window(c, a, b, z0, z1, y, k, frame, T)


def hull(c, W, D, z1, mat):
    bx(c, -W / 2, W / 2, -D, -T, 0.0, z1, mat)
    bx(c, -W / 2, W / 2, -T, 0.08, 0.0, 0.3, "concrete")                      # plinth course under the cut front wall


def sides(c, W, D, z1, mat):
    for sx in (-1, 1):
        bx(c, sx * W / 2 - (0.12 if sx > 0 else 0), sx * W / 2 + (0 if sx > 0 else 0.12), -D, 0.0, 0.0, z1, mat)


def floor_band(c, x0, x1, z, y=0.0, h=0.28, proj=0.1, mat="concrete"):
    bx(c, x0, x1, y - T, y + proj, z - h / 2, z + h / 2, mat)


# ================================================================================================ 1 habitation_workshop
def build_habitation_workshop(c):
    W, D, GH, FH = 24.0, 18.0, 4.2, 3.0
    top = GH + 3 * FH
    hull(c, W, D, top, "brick")
    sides(c, W, D, top, "brick")
    # --- ground floor steel frame, four 6 m bays
    cols = [-11.7 + 6.0 * i for i in range(5)]
    cols[4] = 11.7
    for i, x in enumerate(cols):
        P.column_h(c, x, 0.15, 0.0, GH - 0.3, 0.32, plinth=0.3)
    P.beam_i(c, -W / 2 + 0.3, W / 2 - 0.3, 0.15, GH - 0.15, 0.32)
    for x in cols[:4]:
        P.knee_brace(c, x + 0.17, 0.15, GH - 0.3, 0.7, 1)
    # bay 1: roller shutter half raised
    P.wall(c, -12, -6, 0.3, GH - 0.3, 0.0, T, "cladding_corrugated", openings=[(-10.2, -7.8, 0.3, 3.1)])
    P.roller_shutter(c, -9.0, 0.3, 0.0, 2.4, 2.8, raised=1.1)
    P.sign_board(c, 8, -9.0, 0.15, GH + 0.45, 3.2, 0.8)
    P.crate_stack(c, -11.5, 0.35, 0.3, 2, 2)
    P.gas_cylinder(c, -6.5, 0.55, 0.3)
    P.gas_cylinder(c, -6.25, 0.5, 0.3)
    # bay 2: display window with bars + door
    P.wall(c, -6, 0, 0.3, GH - 0.3, 0.0, T, "cladding_corrugated", openings=[(-5.2, -2.6, 0.9, 2.6), (-1.8, -0.5, 0.3, 2.4)])
    P.window(c, -5.2, -2.6, 0.9, 2.6, 0.0, "bars", t=T)
    bx(c, -5.4, -2.4, 0.0, 0.45, 0.3, 0.9, "concrete")
    P.personnel_door(c, -1.15, 0.3, 0.0, 1.0, 2.1)
    P.tyre_stack(c, -3.6, 0.8, 0.3, 4)
    # bay 3: closed bay, corrugated ribs and a bolted repair patch
    P.corrugated(c, 0.2, 5.8, 0.3, GH - 0.3, 0.0)
    P.patch(c, 1.3, 3.1, 0.7, 2.3, 0.02)
    P.patch(c, 3.9, 4.6, 1.8, 3.3, 0.02, "brick", bolts=False)
    P.rivets(c, 0.3, 5.7, 1.6, 0.0, 0.5)
    for z in (1.2, 2.2, 3.2):
        P.lap_joint(c, 0.2, 5.8, z, 0.0)
    P.junction_box(c, 5.2, 0.0, 1.2, 0.34, 0.5, 0.15)
    P.meter_cluster(c, 5.2, 0.0, 2.0, 3)
    # bay 4: wide shutter + door to the stair
    P.wall(c, 6, 12, 0.3, GH - 0.3, 0.0, T, "cladding_corrugated", openings=[(6.6, 9.4, 0.3, 3.1), (10.1, 11.2, 0.3, 2.4)])
    P.roller_shutter(c, 8.0, 0.3, 0.0, 2.8, 2.8, raised=0.0)
    P.personnel_door(c, 10.65, 0.3, 0.0, 1.0, 2.1)
    P.sign_board(c, 14, 8.0, 0.15, GH + 0.45, 3.0, 0.75)
    for x in (-3.6, 3.0, 9.6):
        P.bollard(c, x, 1.4, 0.0)
    P.bollard(c, -9.0, 1.6, 0.0)
    # --- upper housing: render with brick infill repairs, window grid, balconies
    cx = [-10.0 + 4.0 * i for i in range(6)]
    ops = windows_grid(c, cx, 3, GH, FH, 1.3, 1.45, 0.85, 0.0)
    P.wall(c, -W / 2, W / 2, GH, top, 0.0, T, "render_plaster", openings=[o[:4] for o in ops])
    for z in (GH, GH + FH, GH + 2 * FH):
        floor_band(c, -W / 2, W / 2, z, proj=0.12)
    kinds = {(0, 1): "ac", (1, 3): "ac", (2, 0): "shutter", (2, 4): "bars", (1, 5): "blind"}
    draw_windows(c, ops, 0.0, kinds)
    P.patch(c, -4.6, -3.0, GH + 3.2, GH + 5.2, 0.0, "brick", bolts=False)
    P.patch(c, 6.0, 7.6, GH + 0.5, GH + 2.5, 0.0, "brick", bolts=False)
    P.patch(c, 2.1, 3.0, GH + 5.8, GH + 8.0, 0.0, "cladding_patch")
    for bi, bxc in enumerate((-6.0, 6.0)):
        zb = GH + FH
        bx(c, bxc - 1.5, bxc + 1.5, 0.0, 1.25, zb - 0.1, zb + 0.08, "concrete")
        bx(c, bxc - 1.5, bxc + 1.5, 1.25, 1.3, zb + 0.08, zb + 0.5, "cladding_corrugated")
        P.railing(c, bxc - 1.5, bxc + 1.5, 1.22, zb + 0.08, 1.0, 0.75, infill=True)
        cylx(c, bxc - 1.3, bxc + 1.3, 1.05, zb + 1.85, 0.008, "plastic_rubber", seg=4)
        for k in range(4):
            bx(c, bxc - 1.2 + k * 0.62, bxc - 0.8 + k * 0.62, 1.04, 1.07, zb + 1.35, zb + 1.85, "fabric_awning")
        P.crate_stack(c, bxc + 0.7, 0.3, zb + 0.08, 1, 1)
        c.anchor("window", (bxc, 0.5, zb + 1.0), (0, 1, 0), (1.0, 0.75, 0.4), 4.0, 0.5)
    for xd in (-11.6, 11.6):
        P.downspout(c, xd, 0.12, 0.0, top)
    P.pipe_run(c, [(7.9, 0.1, GH - 0.2), (7.9, 0.1, top - 0.3)], 0.05, "equipment_steel", 1.0)
    P.blade_sign(c, 7, 11.0, 0.1, GH + 2.2)
    # --- roof
    P.parapet(c, -W / 2, W / 2, 0.0, -D, top, 0.6, "brick", T, scuppers=(-9, 0, 9))
    P.water_tank(c, -7.5, -6.0, top, 1.0, 1.6)
    P.water_tank(c, -4.5, -8.0, top, 0.8, 1.3)
    P.hvac_box(c, 6.0, -5.0, top, 1.8, 1.1, 1.0)
    P.vent_stack(c, 1.5, -4.0, top, 1.3)
    P.vent_stack(c, 3.0, -9.0, top, 1.0)
    P.antenna(c, 10.0, -3.0, top, 3.2)
    P.ladder(c, 11.2, -0.35, top - 3.0, top + 0.8)
    c.anchor("street", (-11.5, 0.8, 3.4), (0.2, 1, -0.4), (1.0, 0.78, 0.45), 9.0, 1.2)
    c.anchor("street", (11.5, 0.8, 3.4), (-0.2, 1, -0.4), (1.0, 0.78, 0.45), 9.0, 1.2)
    c.anchor("shop_spot", (-9.0, 1.4, 3.9), (0, 1, -0.6), (1.0, 0.85, 0.6), 10.0, 1.6, True)


# ================================================================================================ 2 market_habitat
def build_market_habitat(c):
    W, D, GH, FH = 18.0, 16.0, 4.0, 3.2
    top = GH + 2 * FH
    hull(c, W, D, top, "brick")
    sides(c, W, D, top, "brick")
    # arcade: columns on the front line, recessed back wall with doors, ceiling slab with a front beam
    xs = [-8.4 + 4.2 * i for i in range(5)]
    for x in xs:
        P.column_h(c, x, 0.2, 0.0, GH - 0.3, 0.3, plinth=0.25)
    P.beam_i(c, -W / 2 + 0.3, W / 2 - 0.3, 0.2, GH - 0.15, 0.34)
    bx(c, -W / 2, W / 2, -2.6, 0.0, GH - 0.3, GH, "concrete")
    ops = [(-7.9, -5.5, 0.5, 2.5), (-3.9, -1.7, 0.5, 2.2), (2.5, 4.8, 0.5, 2.6), (6.3, 7.6, 0.3, 2.3)]
    P.wall(c, -W / 2, W / 2, 0.0, GH - 0.3, -2.3, 0.3, "brick", openings=[o for o in ops])
    for o in ops[:3]:
        P.window(c, o[0], o[1], o[2] + 0.5, o[3], -2.3, "bars", t=0.3)
        bx(c, o[0] - 0.05, o[1] + 0.05, -2.3, -1.9, 0.0, o[2] + 0.5, "concrete")
    P.personnel_door(c, 6.95, 0.0, -2.3, 1.1, 2.2, canopy=False)
    # stalls: counters with produce, tarps, canopies each in a different cloth
    stalls = [(-8.4, -4.2), (-4.2, 0.0), (0.0, 4.2), (4.2, 8.4)]
    for i, (a, b) in enumerate(stalls):
        P.awning(c, a + 0.1, b - 0.1, 0.25, 3.55 - 0.1 * (i % 2), proj=1.6, drop=0.55 + 0.1 * (i % 3))
        bx(c, a + 0.35, b - 0.45, 0.35, 1.15, 0.0, 0.85, "cladding_corrugated" if i % 2 else "concrete")
        bx(c, a + 0.3, b - 0.4, 0.3, 1.2, 0.85, 0.92, "equipment_steel")
        P.crate_stack(c, a + 0.55, 0.45, 0.92, 2, 1, 0.5, 0.4, 0.28)
        P.crate_stack(c, a + 1.7, 0.45, 0.92, 1, 2, 0.5, 0.4, 0.26)
        P.crate_stack(c, a + 0.6, 1.5, 0.0, 1, 3, 0.55, 0.45, 0.3)
        c.anchor("shop_spot", ((a + b) / 2, 0.9, 3.4), (0, 0.3, -1), (1.0, 0.8, 0.5), 6.5, 1.0, i == 1)
    for x in (-6.0, -1.0, 3.0, 7.0):                                                     # bulb strings
        P.cable_sag(c, (x - 2.0, 0.3, 3.5), (x + 2.0, 0.3, 3.5), 0.3)
        for k in range(4):
            xx = x - 1.5 + k
            bx(c, xx - 0.04, xx + 0.04, 0.28, 0.36, 3.12 + 0.05 * (k % 2), 3.26 + 0.05 * (k % 2), "lamp_glass")
    P.blade_sign(c, 0, -8.2, 0.2, 3.1)
    P.blade_sign(c, 2, 8.5, 0.2, 3.1)
    P.sign_board(c, 15, 0.0, 0.0, GH + 0.42, 2.4, 0.6)
    c.entrance("arcade", -2.1, 0.0, 4.0, 3.5)
    c.entrance("arcade", 2.1, 0.0, 4.0, 3.5)
    # upper floors
    cx = [-6.75 + 2.25 * i for i in range(7)]
    wo = windows_grid(c, cx, 2, GH, FH, 1.2, 1.6, 0.8, 0.0)
    P.wall(c, -W / 2, W / 2, GH, top, 0.0, T, "brick", openings=[o[:4] for o in wo])
    for z in (GH, GH + FH):
        floor_band(c, -W / 2, W / 2, z, proj=0.1)
    draw_windows(c, wo, 0.0, {(0, 2): "blind", (0, 5): "ac", (1, 1): "ac", (1, 4): "shutter", (0, 0): "bars", (1, 6): "bars"})
    P.patch(c, -2.1, -0.8, GH + 1.0, GH + 3.0, 0.0, "render_plaster", bolts=False)
    P.patch(c, 5.2, 6.4, GH + 3.6, GH + 5.5, 0.0, "cladding_patch")
    for bxc in (-2.25, 6.75):                                                            # laundry lines on pole brackets
        zb = GH + FH + 2.4
        cylx(c, bxc - 1.0, bxc + 1.0, 0.7, zb, 0.008, "plastic_rubber", seg=4)
        for k in range(5):
            bx(c, bxc - 0.9 + k * 0.4, bxc - 0.6 + k * 0.4, 0.69, 0.72, zb - 0.55, zb - 0.0, "fabric_awning")
        for sx in (-1.0, 1.0):
            strut(c, (bxc + sx, 0.0, zb), (bxc + sx, 0.7, zb), 0.012, "steel_structure")
    for xd in (-8.7, 8.7):
        P.downspout(c, xd, 0.12, 0.0, top)
    P.pipe_run(c, [(0.6, 0.1, 0.5), (0.6, 0.1, top - 0.2)], 0.045, "equipment_steel", 1.0)
    P.parapet(c, -W / 2, W / 2, 0.0, -D, top, 0.5, "brick", T, scuppers=(-6, 6))
    P.water_tank(c, -5.0, -6.0, top, 1.1, 1.8)
    P.water_tank(c, 0.0, -9.0, top, 0.9, 1.4)
    P.hvac_box(c, 5.5, -5.5, top, 1.8, 1.1, 0.9)
    P.vent_stack(c, 7.5, -3.0, top, 1.2)
    P.vent_stack(c, -2.0, -4.0, top, 1.0)
    # pergola with tarp on the roof
    for x in (2.0, 4.6):
        for y in (-12.0, -9.5):
            cylv(c, x, y, top, top + 2.2, 0.05, "steel_structure", seg=6)
    bx(c, 1.9, 4.7, -12.1, -9.4, top + 2.2, top + 2.25, "fabric_awning")
    c.anchor("street", (-8.7, 1.0, 3.3), (0.2, 1, -0.4), (1.0, 0.8, 0.5), 9.0, 1.1)


# ================================================================================================ 3 service_tenement
def build_service_tenement(c):
    W, D, GH, FH = 12.0, 14.0, 3.6, 2.9
    nf = 4
    top = GH + nf * FH
    hull(c, W, D, top, "brick")
    sides(c, W, D, top, "brick")
    # ground floor: shop shutter + stair door, concrete pilasters
    P.wall(c, -W / 2, W / 2, 0.0, GH, 0.0, T, "brick", openings=[(-4.6, -1.4, 0.0, 2.9), (1.0, 2.1, 0.0, 2.3)])
    P.roller_shutter(c, -3.0, 0.0, 0.0, 3.2, 2.9, raised=0.0, mat="cladding_corrugated")
    P.personnel_door(c, 1.55, 0.0, 0.0, 1.1, 2.3, mat="steel_structure")
    for x in (-5.7, -0.2, 3.0):
        bx(c, x - 0.25, x + 0.25, 0.0, 0.14, 0.0, GH, "concrete")
    bx(c, -W / 2, W / 2, -0.1, 0.12, 0.0, 0.5, "concrete")
    P.patch(c, 3.6, 5.6, 0.8, 2.6, 0.0, "cladding_patch")
    P.meter_cluster(c, 2.9, 0.0, 1.2, 3)
    P.sign_board(c, 2, -3.0, 0.1, 3.3, 3.4, 0.7)
    P.crate_stack(c, -5.8, 0.4, 0.0, 2, 2)
    P.barrel(c, 5.0, 0.7, 0.0)
    P.bollard(c, -0.2, 1.3, 0.0)
    # upper facade: tall windows, stringcourses, cornice brackets
    cx = [-3.9, -1.3, 1.3, 3.9]
    ops = windows_grid(c, cx, nf, GH, FH, 1.1, 1.75, 0.8, 0.0)
    P.wall(c, -W / 2, W / 2, GH, top, 0.0, T, "brick", openings=[o[:4] for o in ops])
    kinds = {(0, 0): "ac", (1, 2): "shutter", (2, 1): "ac", (3, 3): "bars", (2, 3): "blind", (1, 0): "blind", (3, 0): "bars"}
    draw_windows(c, ops, 0.0, kinds)
    for fi in range(nf + 1):
        floor_band(c, -W / 2, W / 2, GH + fi * FH - 0.0, proj=0.1, h=0.22)
    P.patch(c, -1.0, 0.0, GH + 3.3, GH + 5.8, 0.0, "render_plaster", bolts=False)
    P.patch(c, 4.7, 5.7, GH + 7.2, GH + 9.6, 0.0, "cladding_patch")
    for x in (-5.5, 0.0, 5.5):                                                           # cornice corbels
        bx(c, x - 0.15, x + 0.15, 0.0, 0.32, top - 0.7, top - 0.2, "concrete")
    bx(c, -W / 2 - 0.1, W / 2 + 0.1, -0.05, 0.35, top - 0.2, top + 0.0, "concrete")
    # external steel fire stair on the right edge: landings at each floor, flights between, stringers + treads + rails
    sx0 = 3.0
    for fi in range(1, nf + 1):
        zl = GH + fi * FH - 0.25
        bx(c, sx0, W / 2 - 0.15, 0.0, 1.25, zl - 0.06, zl, "steel_structure")
        P.railing(c, sx0, W / 2 - 0.15, 1.22, zl, 1.0, 0.8)
        for xp in (sx0 + 0.1, W / 2 - 0.25):
            strut(c, (xp, 0.5, zl), (xp, 0.5, zl - 0.7), 0.03, "steel_structure")
    for fi in range(nf):
        z0 = (GH + fi * FH - 0.25) if fi else 0.2
        z1 = GH + (fi + 1) * FH - 0.25
        if fi == 0:
            z0 = 0.2
        # stair flight from low z0 (left) to z1 (right) at y=1.45
        xa, xb = sx0 + 0.15, sx0 + 0.15
    for fi in range(nf):
        zlow = 0.2 if fi == 0 else GH + fi * FH - 0.25
        zhigh = GH + (fi + 1) * FH - 0.25
        xa, xb = (sx0 + 0.2, W / 2 - 0.35)
        if fi % 2:
            xa, xb = xb, xa
        yv = 1.45 + 0.0
        # flight is along x at y=1.45 (outer) - stringers are diagonal
        for dy in (-0.0,):
            strut(c, (xa, yv, zlow), (xb, yv, zhigh), 0.04, "steel_structure")
        n = 9
        for k in range(n):
            tk = (k + 0.5) / n
            xx = xa + (xb - xa) * tk
            zz = zlow + (zhigh - zlow) * tk
            bx(c, xx - 0.14, xx + 0.14, yv - 0.55, yv + 0.0, zz - 0.02, zz + 0.02, "steel_structure")
        strut(c, (xa, yv - 0.55, zlow), (xb, yv - 0.55, zhigh), 0.04, "steel_structure")
        strut(c, (xa, yv - 0.0, zlow + 0.95), (xb, yv - 0.0, zhigh + 0.95), 0.014, "steel_structure")
    # stair outer posts to ground
    for xp in (sx0 + 0.1, W / 2 - 0.25):
        cylv(c, xp, 1.2, 0.0, GH + 0.2, 0.04, "steel_structure", seg=6)
    P.column_h(c, W / 2 - 0.25, 1.2, 0.0, 0.01, 0.2, plinth=0.15, gussets=False)
    P.downspout(c, -5.7, 0.14, 0.0, top)
    P.pipe_run(c, [(-4.6, 0.1, 0.9), (-4.6, 0.1, top - 0.4), (-3.4, 0.1, top - 0.4)], 0.04, "equipment_steel", 1.0)
    P.blade_sign(c, 7, -5.8, 0.15, GH + 2.2, 0.7, 0.9)
    # roof: parapet, chimney stacks, tank, aerials
    P.parapet(c, -W / 2, W / 2, 0.0, -D, top, 0.55, "brick", T, scuppers=(-5.0, 5.0))
    for x, y in ((-3.0, -5.0), (-1.0, -5.0), (3.0, -8.0)):
        bx(c, x - 0.4, x + 0.4, y - 0.4, y + 0.4, top, top + 1.5, "brick")
        bx(c, x - 0.5, x + 0.5, y - 0.5, y + 0.5, top + 1.5, top + 1.62, "concrete")
        for dx in (-0.2, 0.2):
            cylv(c, x + dx, y, top + 1.62, top + 1.95, 0.1, "equipment_steel", seg=8)
    P.water_tank(c, 2.0, -3.0, top, 0.85, 1.2)
    P.antenna(c, -4.5, -10.0, top, 2.2)
    P.ladder(c, 4.8, -0.35, top - 2.5, top + 0.6)
    c.anchor("street", (-5.2, 0.9, 3.3), (0.2, 1, -0.5), (1.0, 0.78, 0.45), 8.0, 1.1)
    c.anchor("window", (-1.3, 0.3, GH + 1.6), (0, 1, 0), (1.0, 0.8, 0.5), 3.5, 0.4)


# ================================================================================================ 4 freight_depot
def build_freight_depot(c):
    W, D, EH = 24.0, 22.0, 8.0
    ridge = 9.8
    DOCK = 1.1
    # dock platform and ramp
    bx(c, -W / 2, W / 2, 0.0, 3.2, 0.0, DOCK, "concrete")
    bx(c, -W / 2, W / 2, 3.2, 3.3, 0.0, DOCK, "steel_structure")
    centres = [-8.8, -2.9, 2.9, 8.8]
    ops = [(x - 1.7, x + 1.7, DOCK, DOCK + 3.4) for x in centres]
    bx(c, -W / 2, W / 2, -D, -9.0, DOCK, EH, "cladding_corrugated")                          # rear mass
    bx(c, -W / 2, W / 2, -D, 0.0, 0.0, DOCK, "concrete")                                      # dock body under the loading floor
    P.wall(c, -W / 2, W / 2, DOCK, EH, 0.0, 9.0, "cladding_corrugated", openings=ops)         # front 9 m with real door tunnels
    bx(c, -W / 2, W / 2, -9.0, 0.0, DOCK, DOCK + 0.04, "paving")                              # shed floor
    sides(c, W, D, EH, "cladding_corrugated")
    # roof sheet as a ridge profile (front slope, back slope)
    c.m.extrude_profile([(0.5, EH - 0.05), (-D / 2, ridge), (-D - 0.5, EH - 0.05), (-D - 0.5, EH - 0.35), (-D / 2, ridge - 0.3), (0.5, EH - 0.35)], -W / 2 - 0.4, W / 2 + 0.4, "roof_membrane", plane="YZ")
    # steel portal frame visible on the facade
    xs = [-11.7 + 5.85 * i for i in range(5)]
    for x in xs:
        P.column_h(c, x, 0.2, DOCK, EH - 0.5, 0.36, plinth=0.15)
        P.knee_brace(c, x + 0.2, 0.2, EH - 0.5, 0.9, 1)
        P.knee_brace(c, x - 0.2, 0.2, EH - 0.5, 0.9, -1)
    P.beam_i(c, -W / 2 + 0.3, W / 2 - 0.3, 0.2, EH - 0.25, 0.5)
    # cladding upper: ribs
    for a, b in zip(xs, xs[1:]):
        P.corrugated(c, a + 0.25, b - 0.25, DOCK + 3.6, EH - 0.5, 0.0, pitch=0.22)
        P.lap_joint(c, a + 0.25, b - 0.25, DOCK + 3.6, 0.0)
    P.patch(c, -6.4, -4.8, DOCK + 3.8, DOCK + 4.9, 0.0, "cladding_patch")
    P.patch(c, 4.0, 5.6, DOCK + 4.1, DOCK + 5.2, 0.0, "equipment_steel", bolts=True)
    # four dock doors (3 shutters at different heights + one open bay with stacked pallets)
    for i, x in enumerate(centres):
        if i == 2:
            bx(c, x - 1.6, x + 1.6, -D * 0.6, -0.4, DOCK, DOCK + 0.01, "plastic_rubber")
            for k in range(3):
                P.pallet(c, x - 1.4 + k * 1.0, -2.5 - k * 0.2, DOCK)
                bx(c, x - 1.3 + k * 1.0, x - 0.4 + k * 1.0, -2.4 - k * 0.2, -1.7 - k * 0.2, DOCK + 0.12, DOCK + 1.1 + 0.3 * (k % 2), "cladding_patch")
            c.entrance("dock", x, 0.0, 3.4, 3.4)
            c.anchor("shop_spot", (x, -1.5, DOCK + 3.2), (0, 1, -0.5), (0.9, 0.95, 1.0), 9.0, 1.5, True)
        else:
            P.roller_shutter(c, x, DOCK, 0.0, 3.4, 3.4, raised=[0.0, 1.0, 0, 2.2][i], mat="cladding_corrugated")
        # dock bumpers, leveller plate, seal, bay number plate
        for sx in (-1.5, 1.5):
            bx(c, x + sx - 0.12, x + sx + 0.12, 3.3, 3.45, DOCK + 0.2, DOCK + 0.9, "plastic_rubber")
        bx(c, x - 1.1, x + 1.1, 0.0, 1.2, DOCK, DOCK + 0.05, "equipment_steel")
        bx(c, x - 0.15, x + 0.15, 0.0, 0.04, DOCK + 3.5, DOCK + 3.8, "steel_structure")
        P.lamp_fixture(c, x, 0.05, DOCK + 3.9, 0.55, shadow=(i == 0), rng_m=10.0)
    # dock canopy: cantilever steel canopy on tie rods
    zc = DOCK + 4.4
    bx(c, -W / 2, W / 2, 0.0, 3.0, zc, zc + 0.12, "cladding_corrugated")
    P.beam_i(c, -W / 2, W / 2, 3.0, zc - 0.05, 0.22, endplates=False, stiffeners=False)
    for x in xs:
        strut(c, (x, 0.2, DOCK + 5.6), (x, 3.0, zc), 0.035, "steel_structure")
        strut(c, (x, 3.0, zc), (x, 3.0, zc - 0.2), 0.03, "steel_structure")
    P.sign_board(c, 3, -2.9 + 2.9, 0.1, DOCK + 5.9 + 0.6, 4.0, 1.0)
    # office annex at the left: windows + door
    P.window(c, -11.2, -9.6, DOCK + 4.1, DOCK + 5.2, 0.0, "plain", t=T)
    # steps and stair to dock
    for x in (-10.6, -6.0, 0.0, 6.0, 10.6):
        P.bollard(c, x, 3.7, 0.0, 1.0)
    P.crate_stack(c, -11.4, 1.0, DOCK, 2, 3, 0.7, 0.6, 0.35)
    P.barrel(c, 11.3, 1.2, DOCK)
    P.barrel(c, 10.5, 1.5, DOCK)
    P.pallet(c, -7.0, 1.4, DOCK)
    P.junction_box(c, 5.9, 0.0, DOCK + 1.5, 0.36, 0.5, 0.16)
    P.meter_cluster(c, -5.9, 0.0, DOCK + 1.4, 3)
    P.downspout(c, -11.95, 0.2, DOCK, EH)
    P.downspout(c, 11.95, 0.2, DOCK, EH)
    # gutter + ridge ventilator + rooflights + roof access
    cylx(c, -W / 2, W / 2, 0.55, EH - 0.1, 0.07, "equipment_steel", seg=8)
    bx(c, -6.0, 6.0, -D / 2 - 0.5, -D / 2 + 0.5, ridge - 0.1, ridge + 0.55, "steel_structure")
    bx(c, -6.2, 6.2, -D / 2 - 0.7, -D / 2 + 0.7, ridge + 0.55, ridge + 0.65, "cladding_corrugated")
    for x in (-8.0, 0.0, 8.0):
        bx(c, x - 1.0, x + 1.0, -6.5, -4.5, EH + 0.7, EH + 0.8, "glass_window")
    c.anchor("street", (-12.0, 1.0, 5.6), (0.3, 1, -0.5), (0.9, 0.95, 1.0), 11.0, 1.2)
    c.anchor("street", (12.0, 1.0, 5.6), (-0.3, 1, -0.5), (0.9, 0.95, 1.0), 11.0, 1.2)


# ================================================================================================ 5 redline_shop
def build_redline_shop(c):
    W, D = 12.0, 12.0
    GH, UH = 4.1, 3.0
    top = GH + UH
    # hollow ground-floor kitchen (2.8 m deep, visible through the counter opening) under a solid body
    bx(c, -W / 2, W / 2, -D, -2.8, 0.0, GH, "cladding_corrugated")
    bx(c, -W / 2, W / 2, -D, -T, GH, top, "cladding_corrugated")
    bx(c, -W / 2, W / 2, -T, 0.08, 0.0, 0.3, "concrete")
    for sx in (-1, 1):
        bx(c, sx * W / 2 - (0.15 if sx > 0 else 0), sx * W / 2 + (0 if sx > 0 else 0.15), -2.8, 0.0, 0.0, GH, "cladding_corrugated")
    bx(c, -W / 2, W / 2, -2.8, 0.0, 0.0, 0.12, "paving")                                                   # kitchen floor
    bx(c, -W / 2, W / 2, -2.8, -T, GH - 0.3, GH, "steel_structure")                                          # ceiling slab
    bx(c, -W / 2 + 0.2, W / 2 - 0.2, -2.72, -2.6, 0.12, 2.6, "equipment_steel")                              # back wall panel
    for z in (0.9, 1.5, 2.1):                                                                                # shelves with crates and hanging pots
        bx(c, -4.8, -1.2, -2.7, -2.2, z, z + 0.04, "steel_structure")
        P.crate_stack(c, -4.6, -2.65, z + 0.04, 4, 1, 0.8, 0.4, 0.22)
    for k in range(4):
        cylv(c, 1.4 + k * 0.45, -2.45, 1.7, 2.4, 0.012, "steel_structure", seg=4)
        cylv(c, 1.4 + k * 0.45, -2.45, 1.4, 1.7, 0.1, "equipment_steel", seg=10)
    bx(c, 3.6, 5.5, -2.7, -1.8, 0.12, 0.9, "steel_structure")                                                 # prep fridge
    bx(c, 3.65, 5.45, -1.8, -1.77, 0.15, 0.85, "equipment_steel")
    bx(c, -0.8, 0.8, -2.1, -1.9, GH - 0.34, GH - 0.3, "lamp_glass")                                          # strip light in the kitchen
    c.anchor("window", (0.0, -2.0, GH - 0.45), (0, 0.2, -1), (1.0, 0.9, 0.7), 5.0, 1.0)
    c.entrance("service_counter", 0.0, 0.0, 6.8, 1.9, 1.2)
    # steel frame: two counter-wide H columns on plinths with a header I-beam and knee braces (same anatomy as the approved benchmark)
    for x in (-5.2, 5.2):
        P.column_h(c, x, 0.3, 0.0, GH - 0.3, 0.32, plinth=0.3)
    P.beam_i(c, -5.4, 5.4, 0.3, GH - 0.15, 0.36)
    P.knee_brace(c, -5.0, 0.3, GH - 0.3, 0.8, 1)
    P.knee_brace(c, 5.0, 0.3, GH - 0.3, 0.8, -1)
    # counter opening (x -3.6..3.2) and side door; left/right cladding panels with a bolted repair
    ops = [(-3.6, 3.2, 1.2, 3.1), (4.0, 4.9, 0.3, 2.4)]
    P.wall(c, -5.4, 5.4, 0.3, GH - 0.3, 0.0, T, "cladding_corrugated", openings=ops)
    P.corrugated(c, -5.05, -3.7, 0.3, GH - 0.3, 0.02)
    P.corrugated(c, 5.0, 5.4, 0.3, GH - 0.3, 0.02)
    P.patch(c, -5.0, -3.9, 0.6, 1.8, 0.04, "cladding_patch")
    bx(c, -3.6, 3.2, -1.6, 0.0, 0.0, 1.2, "cladding_corrugated")                                 # counter carcass
    bx(c, -3.75, 3.35, -1.6, 0.18, 1.14, 1.2, "equipment_steel")                                 # counter top, rolled lip
    bx(c, -3.75, 3.35, 0.1, 0.18, 1.0, 1.2, "equipment_steel")
    bx(c, -3.4, 2.8, -0.0, 0.14, 0.0, 0.15, "plastic_rubber")                                    # toe kick
    patch_x = (0.6, 2.2)
    P.patch(c, patch_x[0], patch_x[1], 0.25, 1.0, 0.0, "cladding_patch")
    P.personnel_door(c, 4.45, 0.3, 0.0, 0.9, 2.1, canopy=False)
    # cooking line behind the counter: stock pot, boiler, hood with duct up the wall, gas cylinders
    cylv(c, -2.0, -0.7, 1.2, 1.55, 0.3, "equipment_steel", seg=14)
    cylv(c, -2.0, -0.7, 1.55, 1.58, 0.32, "steel_structure", seg=14)
    bx(c, -0.9, 0.6, -1.2, -0.3, 1.2, 1.55, "equipment_steel")
    cylv(c, 0.2, -0.75, 1.55, 1.7, 0.16, "equipment_steel", seg=10)
    bx(c, -2.6, 0.9, -1.4, -0.4, 2.5, 2.85, "equipment_steel")                                   # extraction hood
    bx(c, -1.2, -0.7, -1.3, -0.8, 2.85, top + 1.4, "equipment_steel")                            # duct up past the roof
    for z in (3.4, 4.8, 6.0):
        bx(c, -1.3, -0.6, -1.35, -0.75, z, z + 0.05, "steel_structure")
    P.gas_cylinder(c, 3.9, -0.6, 0.0)
    P.gas_cylinder(c, 4.3, -0.6, 0.0)
    pipe = [(3.9, -0.6, 1.2), (3.9, -0.6, 1.5), (3.0, -0.35, 1.5)]
    P.pipe_run(c, pipe, 0.015, "plastic_rubber", 2.0, seg=5)
    P.crate_stack(c, 3.3, -1.3, 1.2, 1, 2, 0.5, 0.4, 0.3)
    c.anchor("shop_spot", (0.0, -0.4, 2.9), (0, 1, -0.6), (1.0, 0.85, 0.6), 6.0, 1.4, True)
    # awning (sagging, scalloped valance) over the counter and sign
    P.awning(c, -3.9, 3.5, 0.15, 3.35, proj=1.7, drop=0.6)
    P.sign_board(c, 0, 0.0, 0.1, GH + 0.8, 4.4, 1.1)
    P.blade_sign(c, 0, 5.7, 0.2, 3.0, 0.8, 0.8)
    # upper flat: window with AC, balcony rail, repair, services
    uo = [(-4.2, -2.6, GH + 0.9, GH + 2.3), (1.6, 3.4, GH + 0.9, GH + 2.3)]
    P.wall(c, -W / 2, W / 2, GH, top, 0.0, T, "cladding_corrugated", openings=uo)
    P.window(c, *uo[0][:2], uo[0][2], uo[0][3], 0.0, "ac", t=T)
    P.window(c, *uo[1][:2], uo[1][2], uo[1][3], 0.0, "plain", t=T)
    P.patch(c, -1.2, 0.8, GH + 0.6, GH + 2.2, 0.0, "cladding_patch")
    P.corrugated(c, 4.0, 5.9, GH + 0.1, top - 0.1, 0.02)
    floor_band(c, -W / 2, W / 2, GH, proj=0.1)
    P.downspout(c, -5.75, 0.12, 0.0, top)
    P.junction_box(c, 5.65, 0.0, 1.3, 0.3, 0.4, 0.13)
    P.meter_cluster(c, -4.4, 0.0, 2.4, 2)
    P.parapet(c, -W / 2, W / 2, 0.0, -D, top, 0.5, "concrete", T, scuppers=(-5.0, 5.0))
    P.hvac_box(c, 3.0, -5.0, top, 1.6, 1.0, 0.9)
    P.vent_stack(c, -3.0, -4.0, top, 1.0)
    P.water_tank(c, 2.0, -9.0, top, 0.8, 1.3)
    P.ladder(c, 5.2, -0.35, top - 2.5, top + 0.5)
    for sx in (-2.6, -0.9, 0.8, 2.5):                                                           # customer stools on the pavement
        cylv(c, sx, 1.45, 0.0, 0.62, 0.025, "steel_structure", seg=6)
        cylv(c, sx, 1.45, 0.62, 0.68, 0.17, "plastic_rubber", seg=10)
        for a in (0.0, 2.1, 4.2):
            strut(c, (sx, 1.45, 0.25), (sx + math.cos(a) * 0.17, 1.45 + math.sin(a) * 0.17, 0.0), 0.012, "steel_structure")
    for sx in (-2.4, 0.2, 2.8):                                                                 # paper lanterns under the awning
        cylv(c, sx, 1.3, 2.2, 2.5, 0.13, "lamp_glass", seg=8)
        cylv(c, sx, 1.3, 2.5, 2.54, 0.09, "steel_structure", seg=8)
        cylv(c, sx, 1.3, 2.54, 2.8, 0.006, "plastic_rubber", seg=4)
    bx(c, -3.3, -1.5, 0.19, 0.23, 1.25, 2.15, "steel_structure")                                  # menu board frame on the counter front
    bx(c, -3.25, -1.55, 0.23, 0.245, 1.3, 2.1, "render_plaster")
    for k in range(4):
        bx(c, -3.1, -1.7, 0.245, 0.255, 1.4 + k * 0.17, 1.46 + k * 0.17, "equipment_steel")
    cylv(c, 2.6, 0.5, 1.2, 1.28, 0.2, "equipment_steel", seg=12)                                  # tea urn
    cylv(c, 2.6, 0.5, 1.28, 1.5, 0.15, "equipment_steel", seg=12)
    for k in range(5):
        cylv(c, -3.0 + k * 0.3, 0.55, 1.2, 1.25 + 0.04 * k, 0.1, "render_plaster", seg=10)        # stacked bowls
    P.lamp_fixture(c, -4.6, 0.05, GH - 0.55, 0.4, rng_m=8.0)
    P.lamp_fixture(c, 4.6, 0.05, 3.0, 0.4, rng_m=8.0)
    c.anchor("street", (0.0, 1.2, GH + 0.2), (0, 1, -0.5), (1.0, 0.45, 0.25), 9.0, 1.3)


# ================================================================================================ 6 row_workshop
def build_row_workshop(c):
    W, D, EH = 24.0, 16.0, 5.6
    hull(c, W, D, EH, "brick")
    sides(c, W, D, EH, "brick")
    bx(c, -W / 2, W / 2, 0.0, 2.4, 0.0, 0.12, "concrete")                                          # shared forecourt slab
    unit_x = [-9.0, -3.0, 3.0, 9.0]
    # pilasters between the units
    for x in (-12.0, -6.0, 0.0, 6.0, 12.0):
        bx(c, x - 0.3, x + 0.3, 0.0, 0.2, 0.0, EH + 0.5, "concrete")
        bx(c, x - 0.35, x + 0.35, 0.0, 0.26, EH + 0.5, EH + 0.6, "concrete")
    # unit 1: wide shutter + sign
    P.wall(c, -11.7, -6.3, 0.0, EH, 0.0, T, "brick", openings=[(-10.8, -7.2, 0.0, 3.4)])
    P.roller_shutter(c, -9.0, 0.0, 0.0, 3.6, 3.4, raised=0.0)
    P.sign_board(c, 8, -9.0, 0.1, 4.5, 3.4, 0.85)
    P.tyre_stack(c, -11.2, 1.0, 0.1, 4)
    P.barrel(c, -7.0, 1.0, 0.1)
    # unit 2: double personnel doors under a canopy + big window
    P.wall(c, -5.7, -0.3, 0.0, EH, 0.0, T, "brick", openings=[(-5.2, -3.6, 0.9, 3.0), (-2.9, -0.8, 0.0, 2.5)])
    P.window(c, -5.2, -3.6, 0.9, 3.0, 0.0, "bars", t=T)
    P.personnel_door(c, -2.4, 0.0, 0.0, 1.0, 2.3, canopy=True)
    P.personnel_door(c, -1.2, 0.0, 0.0, 0.9, 2.3, canopy=False, lamp=False)
    P.sign_board(c, 1, -3.0, 0.1, 4.55, 3.2, 0.8)
    P.crate_stack(c, -5.2, 0.5, 0.1, 3, 1)
    # unit 3: shutter raised halfway: workbench and hanging tools visible
    P.wall(c, 0.3, 5.7, 0.0, EH, 0.0, T, "cladding_corrugated", openings=[(0.9, 5.1, 0.0, 3.3)])
    P.roller_shutter(c, 3.0, 0.0, 0.0, 4.2, 3.3, raised=1.7, mat="cladding_corrugated")
    bx(c, 1.2, 4.8, -2.2, -1.4, 0.0, 0.95, "steel_structure")
    bx(c, 1.1, 4.9, -2.3, -1.3, 0.95, 1.02, "equipment_steel")
    cylx(c, 1.2, 4.6, -1.8, 1.4, 0.05, "equipment_steel", seg=8)
    P.sign_board(c, 10, 3.0, 0.1, 4.55, 3.2, 0.8)
    P.gas_cylinder(c, 5.25, 0.5, 0.1)
    P.gas_cylinder(c, 5.5, 0.45, 0.1)
    # unit 4: shop window + door, patched cladding
    P.wall(c, 6.3, 11.7, 0.0, EH, 0.0, T, "cladding_corrugated", openings=[(6.8, 9.0, 0.9, 2.8), (9.6, 10.6, 0.0, 2.3)])
    P.window(c, 6.8, 9.0, 0.9, 2.8, 0.0, "plain", t=T)
    P.personnel_door(c, 10.1, 0.0, 0.0, 1.0, 2.3, canopy=True)
    P.sign_board(c, 14, 9.0, 0.1, 4.55, 3.2, 0.8)
    P.patch(c, 10.8, 11.5, 3.2, 5.0, 0.02, "cladding_patch")
    pipes = [(6.9, 1.3, 0.1)]
    for i in range(5):
        cyly(c, 7.0 + i * 0.22, 0.5, 1.9, 0.18 + (i % 2) * 0.22, 0.09, "equipment_steel", seg=8)
    for fx in (-12, 12):
        P.downspout(c, fx * 0.99, 0.12, 0.0, EH)
    # sawtooth roof: four teeth over the depth, glazing facing back; flues
    teeth = 4
    th = D / teeth
    prof = [(0.4, EH)]
    for i in range(teeth):                                        # each tooth: sloped sheet up to a vertical glazed face, then back down to the eave line
        y0 = 0.4 - i * th
        prof += [(y0 - th + 0.2, EH + 1.3), (y0 - th + 0.2, EH)]
    prof += [(-D, EH - 0.3), (0.4, EH - 0.3)]
    for ux in (-12.0, -6.0, 0.0, 6.0):
        c.m.extrude_profile(prof, ux + 0.35, ux + 5.65, "cladding_corrugated", plane="YZ")
        for i in range(teeth):
            y0 = 0.4 - i * th
            bx(c, ux + 0.6, ux + 5.4, y0 - th + 0.2, y0 - th + 0.26, EH + 0.02, EH + 1.25, "glass_window")
    for x, y in ((-9.5, -5.0), (3.5, -7.0), (-1.5, -2.5)):
        cylv(c, x, y, EH + 1.0, EH + 3.0, 0.2, "equipment_steel", seg=10)
        cylv(c, x, y, EH + 3.0, EH + 3.08, 0.3, "steel_structure", seg=10)
    c.anchor("street", (-3.0, 1.1, 3.8), (0, 1, -0.5), (1.0, 0.8, 0.5), 9.0, 1.1)
    c.anchor("street", (9.0, 1.1, 3.8), (0, 1, -0.5), (1.0, 0.8, 0.5), 9.0, 1.1)
    c.anchor("shop_spot", (3.0, 0.8, 3.2), (0, 0.3, -1), (1.0, 0.7, 0.4), 6.0, 1.2, True)


# ================================================================================================ 7 utility_substation
def build_utility_substation(c):
    W, D, H = 18.0, 20.0, 7.0
    xb0, xb1 = -9.0, 1.2                                              # control building
    bx(c, xb0, xb1, -D, -T, 0.0, H, "brick")
    bx(c, xb0, xb0 + 0.12, -D, 0.0, 0.0, H, "brick")
    bx(c, xb1 - 0.12, xb1, -D, 0.0, 0.0, H, "brick")
    ops = [(-7.6, -4.4, 0.0, 3.3), (-2.0, -0.2, 0.0, 2.4)]
    # louvre ventilation openings (real slats) and double blast door
    ops2 = [(-3.4, -2.2, 3.7, 5.7)]
    P.wall(c, xb0, xb1, 0.0, H, 0.0, T, "brick", openings=ops + ops2)
    bx(c, xb0, xb1, -T, 0.12, 0.0, 0.35, "concrete")
    bx(c, -7.5, -4.5, -0.3 - 0.0, -0.1, 0.0, 3.2, "steel_structure")
    for xx in (-6.0,):
        bx(c, xx - 0.03, xx + 0.03, -0.1, 0.06, 0.0, 3.2, "equipment_steel")
    for k in range(4):                                                                 # door stiffening ribs
        bx(c, -7.4 + k * 0.78, -7.25 + k * 0.78, -0.1, 0.03, 0.15, 3.1, "steel_structure")
    bx(c, -7.75, -4.25, -0.1, 0.12, 3.2, 3.3, "steel_structure")
    c.entrance("service", -6.0, 0.0, 3.0, 3.2)
    P.personnel_door(c, -1.1, 0.0, 0.0, 1.0, 2.3, canopy=False, lamp=True)
    for i in range(10):                                                                 # louvres
        bx(c, -3.4, -2.2, -0.1, 0.12, 3.7 + i * 0.2, 3.7 + i * 0.2 + 0.03, "steel_structure")
    bx(c, -3.45, -2.15, -T, -0.2, 3.65, 5.75, "plastic_rubber")
    P.sign_board(c, 4, -6.0, 0.05, 5.0, 2.6, 0.7, lit=True)
    P.hazard_stripe(c, -7.6, -4.4, 0.13, 0.0, 0.25, 8)
    for yy in (0.0,):
        bx(c, xb0 + 0.3, xb0 + 2.2, 0.0, 0.1, 1.6, 2.2, "cladding_patch")               # HV warning plate
    P.patch(c, -8.7, -7.9, 4.0, 6.0, 0.0, "concrete", bolts=False)
    P.junction_box(c, -0.5, 0.0, 3.0, 0.4, 0.6, 0.16)
    # outdoor LV cabinet, cable ladder rack with cables into the wall, conduit risers, cable trench cover
    bx(c, -4.3, -3.1, 0.0, 0.55, 0.0, 1.7, "equipment_steel")
    bx(c, -4.25, -3.15, 0.55, 0.58, 0.1, 1.6, "steel_structure")
    for k in range(5):
        bx(c, -4.2 + k * 0.2, -4.1 + k * 0.2, 0.55, 0.57, 0.9, 1.55, "equipment_steel")
    cylv(c, -3.3, 0.5, 1.7, 1.78, 0.2, "steel_structure", seg=8)
    bx(c, -0.9, 0.9, 0.0, 0.3, 4.3, 4.34, "steel_structure")                                     # cable ladder along the wall head
    for k in range(9):
        bx(c, -0.9 + k * 0.2, -0.86 + k * 0.2, 0.0, 0.3, 4.3, 4.45, "steel_structure")
    for yy in (0.08, 0.16, 0.24):
        cylx(c, -0.9, 0.9, yy, 4.38, 0.035, "plastic_rubber", seg=6)
    bx(c, -7.8, -4.2, 0.6, 1.8, 0.0, 0.05, "paving")                                             # forecourt slab and cable trench cover
    for k in range(7):
        bx(c, -7.6 + k * 0.5, -7.4 + k * 0.5, 0.65, 1.0, 0.05, 0.08, "equipment_steel")
    cable_x = [-8.3, -8.0, -7.7]
    for i, x in enumerate(cable_x):                                                    # cable bundle up the wall into the roof
        cylv(c, x, 0.07, 0.4, H - 0.1, 0.03, "plastic_rubber", seg=6)
    bx(c, -8.45, -7.55, 0.02, 0.1, 1.2, 1.26, "steel_structure")
    bx(c, -8.45, -7.55, 0.02, 0.1, 3.0, 3.06, "steel_structure")
    bx(c, -8.45, -7.55, 0.02, 0.1, 5.0, 5.06, "steel_structure")
    # control building roof: slab, upstand, ducts, lightning rod
    P.parapet(c, xb0, xb1, 0.0, -D, H, 0.4, "brick", 0.25, scuppers=(-8.0, 0.8))
    for x in (-5.0, -2.0):
        bx(c, x - 0.6, x + 0.6, -6.0, -4.8, H, H + 0.9, "equipment_steel")
        cylv(c, x, -5.4, H + 0.9, H + 1.0, 0.45, "steel_structure", seg=12)
    cylv(c, -7.0, -12.0, H, H + 2.2, 0.04, "steel_structure", seg=6)
    P.vent_stack(c, -3.0, -10.0, H, 1.0)
    # fenced transformer yard (x 1.2 .. 9) with a transformer, gantry and floodlight
    fy = 0.4
    P.fence_panel(c, 1.4, 8.9, fy, 0.0, 2.2)
    bx(c, 1.2, 9.0, -D, 0.4, 0.0, 0.12, "concrete")
    # gate
    bx(c, 4.6, 6.8, fy - 0.02, fy + 0.05, 0.1, 2.0, "steel_structure")
    for k in range(10):
        cylv(c, 4.65 + k * 0.23, fy + 0.05, 0.1, 2.0, 0.012, "steel_structure", seg=4)
    P.sign_board(c, 4, 5.7, fy + 0.1, 2.7, 1.6, 0.4, lit=True)
    # transformer (tank + radiator fins + conservator + bushings with ribbed insulators)
    tx, ty = 5.0, -5.0
    bx(c, tx - 2.2, tx + 2.2, ty - 1.5, ty + 1.5, 0.12, 0.5, "concrete")
    bx(c, tx - 1.8, tx + 1.8, ty - 1.1, ty + 1.1, 0.5, 2.9, "equipment_steel")
    bx(c, tx - 1.9, tx + 1.9, ty - 1.2, ty + 1.2, 2.9, 3.0, "steel_structure")
    for k in range(10):
        bx(c, tx - 1.7 + k * 0.38, tx - 1.55 + k * 0.38, ty + 1.1, ty + 1.65, 0.8, 2.6, "steel_structure")
        bx(c, tx - 1.7 + k * 0.38, tx - 1.55 + k * 0.38, ty - 1.65, ty - 1.1, 0.8, 2.6, "steel_structure")
    cylx(c, tx - 1.6, tx + 1.6, ty - 0.6, 3.5, 0.35, "equipment_steel", seg=14)
    for k, bxn in enumerate((-1.2, 0.0, 1.2)):
        cylv(c, tx + bxn, ty + 0.5, 3.0, 3.35, 0.12, "steel_structure", seg=8)
        for j in range(6):
            cylv(c, tx + bxn, ty + 0.5, 3.35 + j * 0.22, 3.35 + j * 0.22 + 0.12, 0.13 + 0.03 * (j % 2), "concrete", seg=10)
        cylv(c, tx + bxn, ty + 0.5, 4.7, 4.85, 0.06, "equipment_steel", seg=8)
    bx(c, tx - 0.6, tx + 0.6, ty + 1.2, ty + 1.3, 1.3, 2.0, "cladding_patch")
    # steel gantry across the yard with insulator strings
    for gx in (2.0, 8.2):
        P.column_h(c, gx, -9.5, 0.12, 7.4, 0.3, plinth=0.3)
    P.beam_i(c, 1.8, 8.4, -9.5, 7.4, 0.35)
    for gx in (3.0, 5.0, 7.0):
        for j in range(5):
            cylv(c, gx, -9.5, 6.95 - j * 0.15, 6.95 - j * 0.15 - 0.1, 0.1, "concrete", seg=8)
        cylv(c, gx, -9.5, 6.2, 7.2, 0.02, "steel_structure", seg=4)
    P.cable_sag(c, (3.0, -9.5, 6.2), (5.0, -9.5, 6.2), 0.4, 0.02, "steel_structure")
    P.cable_sag(c, (5.0, -9.5, 6.2), (7.0, -9.5, 6.2), 0.4, 0.02, "steel_structure")
    # cable tray along the yard, floodlight pole
    bx(c, 1.4, 8.8, -13.5, -13.2, 0.5, 0.56, "steel_structure")
    for x in (2.0, 4.0, 6.0, 8.0):
        bx(c, x - 0.03, x + 0.03, -13.5, -13.2, 0.12, 0.5, "steel_structure")
    cylv(c, 8.2, -2.5, 0.12, 6.0, 0.07, "steel_structure", seg=6)
    bx(c, 7.8, 8.6, -2.6, -2.3, 6.0, 6.2, "steel_structure")
    bx(c, 7.85, 8.55, -2.3, -2.2, 6.0, 6.18, "lamp_glass")
    c.anchor("fixture", (8.2, -2.0, 5.9), (-0.3, 1, -0.7), (0.85, 0.9, 1.0), 12.0, 1.8, True)
    c.anchor("street", (-7.0, 0.6, 3.5), (0, 1, -0.4), (0.9, 0.95, 1.0), 9.0, 1.0)
    P.bollard(c, -8.0, 1.4, 0.0)
    P.bollard(c, -4.0, 1.4, 0.0)
    P.bollard(c, 0.4, 1.4, 0.0)
    P.bollard(c, 4.0, 1.4, 0.0)
    P.bollard(c, 8.0, 1.4, 0.0)


# ================================================================================================ 8 transit_depot
def build_transit_depot(c):
    W, D, EH, ridge = 24.0, 22.0, 8.4, 10.6
    bay_ops = [(-10.6, -5.2, 0.0, 5.2), (-2.8, 2.6, 0.0, 5.2)]
    bx(c, -12.0, 4.0, -D, -D * 0.8, 0.0, EH, "cladding_corrugated")                           # rear mass behind the 17 m bay tunnels
    P.wall(c, -12.0, 4.0, 0.0, EH, 0.0, D * 0.8, "cladding_corrugated", openings=bay_ops)
    bx(c, 4.0, W / 2, -D, -T, 0.0, EH, "cladding_corrugated")                                  # shelter side mass
    bx(c, 4.0, W / 2, -T, 0.08, 0.0, 0.3, "concrete")
    sides(c, W, D, EH, "cladding_corrugated")
    prof = [(0.4, EH), (-D / 2, ridge), (-D - 0.4, EH), (-D - 0.4, EH - 0.3), (-D / 2, ridge - 0.3), (0.4, EH - 0.3)]
    c.m.extrude_profile(prof, -W / 2 - 0.3, W / 2 + 0.3, "roof_membrane", plane="YZ")
    # main hall front (x -12 .. 4): two vehicle bays with portal frames
    xs = [-11.8, -4.0, 3.8]
    for x in xs:
        P.column_h(c, x, 0.25, 0.0, EH - 0.6, 0.4, plinth=0.3)
    P.beam_i(c, -12.0, 4.0, 0.25, EH - 0.3, 0.6)
    bay = [(-10.6, -5.2), (-2.8, 2.6)]
    P.corrugated(c, -11.6, -10.7, 0.0, 5.2, 0.02, pitch=0.2)
    P.corrugated(c, -5.1, -2.9, 0.0, 5.2, 0.02, pitch=0.2)
    for (a, b) in bay:                                                              # bay interior: dark hull, lit bay, roll-up grille raised, floor slab, inspection pit
        bx(c, a, b, -D * 0.8, 0.0, 0.0, 0.05, "paving")
        bx(c, a + 1.0, b - 1.0, -9.0, -1.0, 0.0, 0.06, "plastic_rubber")                                  # inspection pit
        bx(c, a, a + 0.12, 0.1, 0.18, 0.0, 5.2, "steel_structure")
        bx(c, b - 0.12, b, 0.1, 0.18, 0.0, 5.2, "steel_structure")
        bx(c, a - 0.2, b + 0.2, -0.1, 0.5, 5.2, 5.7, "steel_structure")
        cyly(c, (a + b) / 2, 0.1, 0.45, 5.45, 0.17, "equipment_steel", seg=10)
        for k in range(3):
            bx(c, a + 0.4 + k * 0.4, a + 0.42 + k * 0.4, -3.0, -2.9, 0.1, 2.4, "steel_structure")
        c.entrance("vehicle_bay", (a + b) / 2, 0.0, b - a, 5.2)
        c.anchor("shop_spot", ((a + b) / 2, -2.0, 4.8), (0, 0.2, -1), (0.9, 0.95, 1.0), 10.0, 1.8, a < -5)
        P.lamp_fixture(c, a + 0.3, 0.05, 5.9, 0.5, rng_m=10.0)
        P.lamp_fixture(c, b - 0.3, 0.05, 5.9, 0.5, rng_m=10.0, anchor=False)
        P.hazard_stripe(c, a, b, 0.05, 0.0, 0.2, 14)
    P.patch(c, -4.9, -3.1, 5.9, 7.4, 0.0, "cladding_patch")
    P.patch(c, 0.2, 1.8, 6.1, 7.7, 0.0, "equipment_steel")
    P.sign_board(c, 6, -7.9, 0.1, 6.9, 4.4, 1.0)
    # passenger shelter x 4.3..11.8: cantilevered canopy on three columns, bench, kiosk, route board, bus stop
    bx(c, 4.2, 12.0, 0.0, 0.2, 0.0, EH - 0.5, "brick")
    ko = [(5.0, 7.4, 0.9, 2.4)]
    P.window(c, 5.0, 7.4, 0.9, 2.4, 0.2, "bars", t=0.2)
    P.personnel_door(c, 9.4, 0.0, 0.2, 1.1, 2.3, canopy=False, lamp=False)
    zc = 3.6
    bx(c, 4.2, 12.0, 0.0, 3.4, zc, zc + 0.14, "cladding_corrugated")
    P.beam_i(c, 4.2, 12.0, 3.4, zc - 0.05, 0.25, stiffeners=False)
    for x in (4.6, 8.0, 11.6):
        P.column_h(c, x, 3.2, 0.0, zc - 0.05, 0.22, plinth=0.15, gussets=False)
        strut(c, (x, 0.2, zc + 0.4), (x, 3.2, zc), 0.03, "steel_structure")
    bx(c, 5.0, 8.0, 2.0, 2.45, 0.45, 0.52, "steel_structure")                                   # bench seat/back/legs
    bx(c, 5.0, 8.0, 2.4, 2.45, 0.52, 1.0, "steel_structure")
    for x in (5.2, 7.8):
        bx(c, x - 0.03, x + 0.03, 2.0, 2.45, 0.0, 0.45, "steel_structure")
    bx(c, 9.0, 11.6, 0.3, 1.3, 0.0, 1.0, "cladding_patch")                                        # ticket kiosk
    bx(c, 8.9, 11.7, 0.2, 1.4, 1.0, 1.06, "equipment_steel")
    bx(c, 9.3, 11.3, 0.9, 0.95, 1.06, 2.2, "glass_window")
    bx(c, 9.1, 11.5, 0.3, 1.2, 2.2, 2.3, "steel_structure")
    P.sign_board(c, 6, 7.9, 3.35, zc + 0.9, 3.4, 0.8, lit=True)
    bx(c, 5.1, 7.3, 0.25, 0.35, 1.45, 2.35, "steel_structure")                                    # timetable frame
    bx(c, 5.15, 7.25, 0.35, 0.37, 1.5, 2.3, "render_plaster")
    cylv(c, 12.6, 3.8, 0.0, 3.2, 0.05, "steel_structure", seg=8)                                  # bus-stop pole, flag, clock
    bx(c, 12.35, 12.85, 3.74, 3.8, 2.6, 3.1, "cladding_patch")
    cyly(c, 12.6, 3.65, 3.74, 3.45, 0.22, "equipment_steel", seg=16)
    P.barrel(c, 10.9, 2.4, 0.0, 0.25, 0.8, "plastic_rubber")
    bx(c, 4.2, 12.0, 0.2, 3.4, 0.0, 0.08, "paving")
    P.downspout(c, 12.0 - 0.1, 0.25, 0.0, EH - 0.6)
    P.downspout(c, -11.9, 0.3, 0.0, EH - 0.4)
    P.bollard(c, -1.1, 3.0, 0.0, 1.0)
    P.bollard(c, 3.8, 3.2, 0.0, 1.0)
    P.junction_box(c, 3.2, 0.3, 1.6, 0.34, 0.5, 0.15)
    P.lamp_fixture(c, 8.0, 3.3, zc - 0.05, 0.2, rng_m=8.0)
    # roof: rooflights, ridge vent, stack
    bx(c, -9.0, 9.0, -D / 2 - 0.5, -D / 2 + 0.5, ridge - 0.1, ridge + 0.5, "steel_structure")
    cylv(c, -6.0, -6.0, EH + 1.0, EH + 3.4, 0.22, "equipment_steel", seg=10)
    cylv(c, -6.0, -6.0, EH + 3.4, EH + 3.48, 0.3, "steel_structure", seg=10)
    cylx(c, -W / 2, W / 2, 0.6, EH - 0.1, 0.07, "equipment_steel", seg=8)
    c.anchor("street", (-8.0, 1.0, 5.8), (0.3, 1, -0.5), (0.9, 0.95, 1.0), 11.0, 1.3)
    c.anchor("shop_spot", (8.0, 1.8, 3.4), (0, 0.5, -1), (1.0, 0.9, 0.7), 8.0, 1.6, True)


BUILDERS = {
    "habitation_workshop": (build_habitation_workshop, 24.0, 18.0),
    "market_habitat": (build_market_habitat, 18.0, 16.0),
    "service_tenement": (build_service_tenement, 12.0, 14.0),
    "freight_depot": (build_freight_depot, 24.0, 22.0),
    "redline_shop": (build_redline_shop, 12.0, 12.0),
    "row_workshop": (build_row_workshop, 24.0, 16.0),
    "utility_substation": (build_utility_substation, 18.0, 20.0),
    "transit_depot": (build_transit_depot, 24.0, 22.0),
}

# LOD1: (x0, x1, y0, y1, z0, z1, role) masses; role -> wall / roof / trim material. Same footprint and height as LOD0.
LOD1 = {
    "habitation_workshop": dict(mats=("render_plaster", "roof_membrane", "steel_structure"), boxes=[
        (-12, 12, -18, 0, 0, 4.2, "trim"), (-12, 12, -18, 0, 4.2, 13.2, "wall"), (-12, 12, -18, 0, 13.2, 13.8, "roof"),
        (-7.5, -4.5, -8, -4, 13.8, 16.0, "trim"), (4.5, 7.5, -6.5, -3.5, 13.8, 14.9, "trim"), (-7.5, -4.5, 0, 1.3, 7.1, 7.3, "wall"),
        (4.5, 7.5, 0, 1.3, 7.1, 7.3, "wall"), (-12, 12, 0, 0.12, 4.0, 4.4, "trim")]),
    "market_habitat": dict(mats=("brick", "roof_membrane", "steel_structure"), boxes=[
        (-9, 9, -16, 0, 0, 4.0, "trim"), (-9, 9, -16, 0, 4.0, 10.4, "wall"), (-9, 9, -16, 0, 10.4, 10.9, "roof"),
        (-6, -4, -7, -5, 10.9, 12.8, "trim"), (-1, 1, -10, -8, 10.9, 12.3, "trim"), (-8.4, 8.4, 0, 1.8, 3.5, 3.6, "wall")]),
    "service_tenement": dict(mats=("brick", "roof_membrane", "steel_structure"), boxes=[
        (-6, 6, -14, 0, 0, 3.6, "wall"), (-6, 6, -14, 0, 3.6, 15.2, "wall"), (-6, 6, -14, 0, 15.2, 15.75, "roof"),
        (3.0, 5.85, 0, 1.45, 3.4, 15.2, "trim"), (-3.4, -2.6, -5.4, -4.6, 15.75, 17.2, "trim"), (2.0, 4.0, -4, -2, 15.75, 16.9, "trim")]),
    "freight_depot": dict(mats=("cladding_corrugated", "roof_membrane", "concrete"), boxes=[
        (-12, 12, 0, 3.3, 0, 1.1, "trim"), (-12, 12, -22, 0, 1.1, 8.0, "wall"), (-12.4, 12.4, -22.5, 0.5, 8.0, 9.8, "roof"),
        (-12, 12, 0, 3.0, 5.5, 5.62, "wall"), (-12, 12, -22, 0, 0, 1.1, "trim")]),
    "redline_shop": dict(mats=("cladding_corrugated", "roof_membrane", "steel_structure"), boxes=[
        (-6, 6, -12, 0, 0, 4.1, "wall"), (-6, 6, -12, 0, 4.1, 7.0, "wall"), (-6, 6, -12, 0, 7.0, 7.5, "roof"),
        (-3.9, 3.5, 0, 1.7, 2.75, 3.35, "trim"), (-2.2, 2.2, 0, 0.25, 4.5, 5.5, "trim"), (-1.3, -0.6, -1.4, -0.7, 7.5, 8.4, "trim")]),
    "row_workshop": dict(mats=("brick", "roof_membrane", "steel_structure"), boxes=[
        (-12, 12, -16, 0, 0, 5.6, "wall"), (-12, 12, -16, 0, 5.6, 6.9, "roof"), (-12, 12, 0, 2.4, 0, 0.12, "trim"),
        (-12.3, 12.3, 0, 0.26, 0, 6.1, "trim")]),
    "utility_substation": dict(mats=("brick", "roof_membrane", "steel_structure"), boxes=[
        (-9, 1.2, -20, 0, 0, 7.0, "wall"), (-9, 1.2, -20, 0, 7.0, 7.4, "roof"), (1.2, 9, -20, 0.4, 0, 0.12, "trim"),
        (2.8, 7.2, -6.1, -3.9, 0.12, 3.0, "trim"), (2.0, 8.2, -9.6, -9.4, 7.0, 7.4, "trim"), (1.4, 8.9, 0.3, 0.5, 0, 2.3, "trim")]),
    "transit_depot": dict(mats=("cladding_corrugated", "roof_membrane", "steel_structure"), boxes=[
        (-12, 12, -22, 0, 0, 8.4, "wall"), (-12.3, 12.3, -22.4, 0.4, 8.4, 10.6, "roof"), (4.2, 12.0, 0, 3.4, 3.6, 3.75, "trim"),
        (4.2, 12.0, 0, 0.2, 0, 3.6, "trim"), (-12, 4, 0, 0.5, 5.2, 5.7, "trim")]),
}
