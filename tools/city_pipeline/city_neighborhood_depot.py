"""freight_depot for the City neighbourhood kit: a long, low logistics hall with a covered raised loading dock.

Not run directly. build_city_neighborhood.py imports this module and calls register(nb); everything is registered through
nb.building / nb.SHOTS and the shared nb / nb.W components (Kit, Wall, shell, fits, stairs, rails, pipes, colour, export).
Design space: +Y facade (Godot -Z), +Z up, metres. Every box is authored with ordered (min, max) bounds.
"""
import random
from math import atan, pi

from mathutils import Vector

HB = (-20.0, 20.0, -8.0, 5.0)        # main hall block, front wall plane y=5
ZH = 6.2                             # hall roof
ZD = 1.3                             # raised dock deck level
DY1 = 10.5                           # dock deck front edge
BAY_X = (10.0, 15.6, 21.2, 26.8, 32.4)   # bay left edges on the F face (local x = design x + 20)
BAY_W = 4.4
BOOTH = (-19.4, -13.2, 5.0, 10.0)
CL = (-12.0, 12.0, -5.5, 0.5)        # roof clerestory monitor
ZC = 8.4
STAIR_X = 0.6
TG = {}


def register(nb):
    W = nb.W
    k_names = ("Kit", "Wall", "face_frame", "face_len", "armor_field", "stencil", "railing", "column", "xbrace", "deck", "stair",
               "pipe_run", "stand_off", "bezel", "fit_door", "fit_strip", "fit_louvre", "cornice", "truss", "crate", "drum",
               "gas_bottle", "tank_horizontal", "canister", "valve", "gauge", "conduit_bank", "rib_cutaway", "hazard_floor",
               "spine", "CURTAIN_TONES", "DRUM_TONES")
    g = {n: getattr(nb, n) for n in k_names}
    g.update({n: getattr(nb, n) for n in ("shell", "bays", "person", "lamp", "ladder", "cistern", "tendon", "repair_panel",
                                          "sign_plate", "goods", "gallery", "OXIDE", "TEAL", "TONES")})
    globals().update(g)
    pallet_tones = TONES + OXIDE

    def sb(k, x0, x1, y0, y1, z0, z1, mat, skip=()):
        k.box(min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1), min(z0, z1), max(z0, z1), mat, skip=skip)

    def parcel(k, x, y, z, rng, sx=(0.25, 0.55), sz=(0.2, 0.45), tones=None):
        w, d, h = rng.uniform(*sx), rng.uniform(*sx), rng.uniform(*sz)
        with k.look(rng.uniform(0.8, 1.0), rng.choice(tones or pallet_tones)):
            k.box(x - w / 2, x + w / 2, y - d / 2, y + d / 2, z, z + h, rng.choice(("machinery", "trim", "ceramic")))
        k.box(x - 0.01, x + 0.01, y - d / 2 - 0.005, y + d / 2 + 0.005, z, z + h, "steel", skip=("zn",))   # strap
        return h

    def pallet(k, x, y, z, w, d, rng, stack=2, hmax=0.55):
        k.box(x, x + w, y, y + d, z + 0.1, z + 0.18, "machinery")
        for fx in (x, x + w / 2 - 0.05, x + w - 0.1):
            k.box(fx, fx + 0.1, y, y + d, z, z + 0.1, "steel", skip=("zn",))
        zz = z + 0.18
        for s in range(stack):
            hh = rng.uniform(0.35, hmax)
            with k.look(rng.uniform(0.82, 1.0), rng.choice(pallet_tones)):
                k.box(x + 0.04, x + w - 0.04, y + 0.04, y + d - 0.04, zz, zz + hh, rng.choice(("machinery", "trim")))
            for bz in (zz + hh * 0.33, zz + hh * 0.66):
                k.box(x + 0.03, x + w - 0.03, y + 0.03, y + d - 0.03, bz - 0.012, bz + 0.012, "steel", skip=("zn", "zp"))
            zz += hh

    def container(k, x0, x1, y0, y1, z0, z1, rng, ribs=0.45):
        """Ribbed freight container: long walls are corrugated, corner posts and a door frame at the +x end."""
        tone = rng.choice(OXIDE + TEAL)
        with k.look(0.85, tone):
            sb(k, x0, x1, y0, y1, z0, z1, "machinery")
            n = int((x1 - x0) / ribs)
            for i in range(1, n):
                xx = x0 + (x1 - x0) * i / n
                for yy, sg in ((y0, -1), (y1, 1)):
                    sb(k, xx - 0.07, xx + 0.07, yy, yy + sg * 0.035, z0 + 0.2, z1 - 0.2, "machinery", skip=("yn",) if sg > 0 else ("yp",))
        for cx in (x0, x1):
            for cy in (y0, y1):
                sb(k, cx - 0.07, cx + 0.07, cy - 0.07, cy + 0.07, z0, z1, "steel")
        sb(k, x1 - 0.02, x1 + 0.04, y0 + 0.2, y1 - 0.2, z0 + 0.2, z1 - 0.2, "steel", skip=("xn",))
        for yy in (y0 + (y1 - y0) * 0.35, y0 + (y1 - y0) * 0.65):
            sb(k, x1 + 0.04, x1 + 0.1, yy - 0.025, yy + 0.025, z0 + 0.35, z1 - 0.35, "steel", skip=("xn",))

    # ------------------------------------------------------------------------ openings (fits)
    def fit_bay(k, w, h, t, rng, lit=True, frac=0.3, tone=None, kind="conveyor", worker=True, **_):
        """Big ribbed service opening with a working interior. kind: conveyor | racks | hoist | transfer."""
        tone = tone or rng.choice(OXIDE)
        k.box(0, w, -t - 0.02, -t + 0.03, 0, h, "cavity")
        k.box(0, w, -t, 0.2, 0.0, 0.08, "steel")
        W.bezel(k, w, h, top=0.4, side=0.2, sill=0.0, out=0.25, sides=True)
        sb(k, 0.0, w, -t + 0.05, -0.25, h - 0.14, h - 0.02, "steel")                       # lintel / ceiling strip
        if lit:
            sb(k, w * 0.3, w * 0.7, -t * 0.55 - 0.05, -t * 0.55 + 0.05, h - 0.2, h - 0.14, "glow_amber", skip=("zp",))
        by = -t * 0.5
        if kind in ("conveyor", "hoist", "racks"):
            sb(k, 0.3, w - 0.3, by - 0.42, by + 0.42, 0.66, 0.74, "steel")
            for rx in [0.3 + i * (w - 0.6) / 9 for i in range(10)]:
                sb(k, rx - 0.025, rx + 0.025, by - 0.4, by + 0.4, 0.74, 0.8, "machinery")
            for lx in (0.35, w * 0.5, w - 0.4):
                sb(k, lx - 0.035, lx + 0.035, by - 0.4, by - 0.34, 0.0, 0.66, "steel", skip=("zn",))
                sb(k, lx - 0.035, lx + 0.035, by + 0.34, by + 0.4, 0.0, 0.66, "steel", skip=("zn",))
            for sy in (by - 0.45, by + 0.45):
                sb(k, 0.3, w - 0.3, sy - 0.02, sy + 0.02, 0.8, 0.98, "machinery")
            x = 0.6
            while x < w - 0.7:
                parcel(k, x, by, 0.8, rng)
                x += rng.uniform(0.5, 0.8)
        if kind in ("conveyor", "racks", "hoist"):
            for i, zz in enumerate((0.35, 1.25, 2.15)):
                if zz + 0.5 > h - 0.2:
                    continue
                sb(k, 0.12, w - 0.12, -t + 0.05, -t + 0.55, zz, zz + 0.05, "machinery")
                x = 0.25
                while x < w - 0.3:
                    parcel(k, x + 0.15, -t + 0.3, zz + 0.05, rng, (0.2, 0.42), (0.18, 0.5))
                    x += rng.uniform(0.32, 0.55)
            for ux in (0.1, w - 0.15):
                sb(k, ux, ux + 0.05, -t + 0.05, -t + 0.12, 0.0, h - 0.2, "steel", skip=("zn",))
        if kind == "transfer":
            for rx in (w * 0.3, w * 0.7):
                sb(k, rx - 0.03, rx + 0.03, -t + 0.05, 0.4, 0.1, 0.2, "steel")
            for i in range(int((t + 0.4) / 0.3)):
                sb(k, w * 0.3 - 0.2, w * 0.7 + 0.2, -t + 0.1 + i * 0.3, -t + 0.18 + i * 0.3, 0.08, 0.12, "machinery")
            sb(k, w * 0.25, w * 0.75, -t + 0.2, -0.2, 0.2, 0.34, "machinery")
            with k.look(0.9, rng.choice(OXIDE)):
                sb(k, w * 0.28, w * 0.72, -t + 0.25, -0.3, 0.34, 0.4, "trim")
            for i in range(3):
                parcel(k, w * (0.38 + 0.12 * i), -t * 0.5, 0.4, rng, (0.3, 0.6), (0.3, 0.8))
        if kind == "hoist":
            sb(k, 0.15, w - 0.15, by - 0.1, by + 0.1, h - 0.55, h - 0.4, "machinery")
            hx = w * 0.62
            sb(k, hx - 0.18, hx + 0.18, by - 0.15, by + 0.15, h - 0.8, h - 0.55, "steel")
            k.pipe((hx, by, h - 0.8), (hx, by, 1.5), 0.015, "steel", 4)
            k.joint(hx, by, 1.45, 0.07, "steel")
        # roll-up door, drawn raised: ribbed slats and a dark header drum
        drop = h * frac
        if drop > 0.1:
            with k.look(0.9, tone):
                sb(k, 0.05, w - 0.05, -0.34, -0.14, h - drop, h - 0.12, "machinery")
                for i in range(int(drop / 0.22)):
                    zz = h - 0.25 - i * 0.22
                    sb(k, 0.05, w - 0.05, -0.14, -0.09, zz - 0.02, zz + 0.02, "machinery", skip=("yn", "xn", "xp"))
            sb(k, 0.03, w - 0.03, -0.38, -0.1, h - drop - 0.08, h - drop, "steel")
        sb(k, 0.0, 0.1, -0.36, 0.0, 0.0, h - 0.1, "steel")
        sb(k, w - 0.1, w, -0.36, 0.0, 0.0, h - 0.1, "steel")
        sb(k, -0.14, -0.06, 0.1, 0.2, h - 0.5, h - 0.4, "glow_amber")
        sb(k, w + 0.06, w + 0.14, 0.1, 0.2, h - 0.5, h - 0.4, "glow_amber")
        if worker:
            person(k, w * rng.uniform(0.2, 0.8), -0.15, 0.0, rng, pi * 0.5 * rng.choice((-1, 1)))

    def fit_control(k, w, h, t, rng, lit=True, **_):
        """Control-booth window: desk, glowing screens, chair and a seated controller behind mullions."""
        k.box(0, w, -t - 0.02, -t + 0.03, 0, h, "cavity")
        W.bezel(k, w, h, top=0.34, side=0.16, sill=0.1, out=0.16)
        sb(k, 0.1, w - 0.1, -t + 0.05, -t + 0.55, 0.0, 0.1, "steel")
        sb(k, 0.1, w - 0.1, -t + 0.05, -t + 0.6, 0.0, 0.0 + 0.62, "machinery")
        sb(k, 0.05, w - 0.05, -t + 0.02, -t + 0.7, 0.62, 0.68, "steel")
        n = max(2, int(w / 0.9))
        for i in range(n):
            sx = 0.2 + (w - 0.4) * (i + 0.5) / n
            sb(k, sx - 0.28, sx + 0.28, -t + 0.12, -t + 0.17, 0.78, 1.18, "machinery")
            sb(k, sx - 0.22, sx + 0.22, -t + 0.17, -t + 0.2, 0.82, 1.14, "glow_cyan" if i % 2 == 0 else "glow_amber")
            sb(k, sx - 0.05, sx + 0.05, -t + 0.1, -t + 0.3, 0.68, 0.8, "steel")
        sb(k, 0.1, w - 0.1, -t + 0.02, -t + 0.12, 1.5, 1.52, "machinery")
        for i in range(3):
            sb(k, 0.2 + i * 0.35, 0.5 + i * 0.35, -t + 0.04, -t + 0.12, 1.55, 1.9, "trim")
        for i in range(n + 1):
            sb(k, (w * i / n) - 0.035, (w * i / n) + 0.035, -0.1, 0.06, 0.0, h, "machinery", skip=("zn", "zp"))
        person(k, w * 0.55, -t + 1.05, 0.0, rng, pi, True, stool=True)
        sb(k, w * 0.5 - 0.2, w * 0.5 + 0.2, -t + 0.9, -t + 1.3, 0.05, 0.1, "steel")

    # ------------------------------------------------------------------------ parts
    def d_hall(k, rng):
        L = nb.face_len("F", HB)
        wf = [(fit_door, 7.4, 8.7, ZD, ZD + 2.3, dict(awning=False, lamp="glow_cyan"))]
        kinds = ["conveyor", "racks", "hoist", "conveyor", "racks"]
        fracs = [0.45, 0.2, 0.62, 0.0, 0.35]
        for x, kd, fr in zip(BAY_X, kinds, fracs):
            wf.append((fit_bay, x, x + BAY_W, ZD, ZD + 3.5, dict(kind=kd, frac=fr, tone=rng.choice(OXIDE), worker=kd != "racks")))
        wb = [(fit_bay, 17.5, 22.5, 0.0, 4.2, dict(kind="transfer", frac=0.5, worker=False, tone=rng.choice(OXIDE))),
              (fit_door, 28.4, 29.8, 2.4, 4.7, dict(awning=False, lamp="glow_amber"))]
        wb += bays(rng, 0, L, 2.0, 1, 4.2, [("louvre", 3), ("slits", 2), ("bars", 1)], avoid=[(16.5, 23.5), (27.8, 30.5)], margin=1.2,
                   sill=0.9, wh=(1.4, 1.8))
        wl = [(fit_door, 2.0, 3.4, 0.0, 2.6, dict(awning=True, lamp="glow_cyan"))] + bays(
            rng, 4.2, 10.0, 1.4, 1, 4.0, [("louvre", 3), ("bars", 2), ("slits", 1)], margin=0.5, gap=(0.6, 1.2), sill=0.9)
        wr = [(fit_bay, 3.0, 8.0, 0.0, 4.0, dict(kind="racks", frac=0.55, worker=True, tone=rng.choice(OXIDE)))] + bays(
            rng, 8.5, 12.0, 1.4, 1, 4.0, [("louvre", 2), ("bars", 1)], avoid=[(8.8, 11.4)], margin=0.4, gap=(0.5, 1.0), sill=0.9)
        excl = {"R": [(9.0, 11.4, 1.8, 4.6)]}
        excl["F"] = [(14.3 + 5.6 * i, 15.7 + 5.6 * i, 2.0, 3.7) for i in range(4)]
        nb.shell(k, HB, 0.0, ZH, rng, {"F": wf, "B": wb, "L": wl, "R": wr}, t=dict(F=2.0, B=1.4, L=0.8, R=1.4),
                 akw=dict(cov=0.62, repair=0.2, max_rib=2, cw=(2.6, 4.4)), extra_excl=excl, patches=1, patch_rgbs=OXIDE)
        with face_frame(k, "F", HB):
            for i in range(4):
                sx = 14.65 + 5.6 * i
                nb.sign_plate(k, sx, sx + 0.7, 2.0, 2.7, str(i + 1), rng, lit=True)
            for i in range(5):
                lamp(k, BAY_X[i] + BAY_W / 2, 0.55, 5.0, "glow_amber" if i % 2 == 0 else "glow_cyan", 0.05)
        with face_frame(k, "R", HB):                                   # sparse tendon breach, hull ribs showing
            with k.part(".breach"):
                rib_cutaway(k, 9.2, 11.2, 1.9, 4.5, 0.0)
                tendon(k, [(9.3, 0.18, 2.2), (9.9, 0.34, 3.0), (10.4, 0.22, 3.9), (10.9, 0.3, 4.4)], 0.05)
        # clerestory monitor on the hall roof
        wcl = bays(rng, 0, 24.0, ZH, 1, 2.2, [("louvre", 3), ("strip", 2)], margin=0.8, sill=0.55, wh=(1.0, 1.2))
        wcb = bays(rng, 0, 24.0, ZH, 1, 2.2, [("louvre", 2), ("slits", 2)], margin=0.8, sill=0.55, wh=(1.0, 1.2))
        nb.shell(k, CL, ZH, ZC, rng, {"F": wcl, "B": wcb}, t=dict(F=0.5, B=0.5, L=0.4, R=0.4),
                 akw=dict(cov=0.5, repair=0.14, max_rib=1, cw=(2.4, 4.0)), base_cornice=False, corner=False)
        sb(k, CL[0] - 0.3, CL[1] + 0.3, CL[2] - 0.3, CL[3] + 0.3, ZC, ZC + 0.2, "ceramic")

    def d_booth(k, rng):
        """Sheltered staff / control booth on the dock: glazed control strip, side windows, door to the hall and the dock."""
        x0, x1, y0, y1 = BOOTH
        zb0, zb1 = ZD, 4.6
        wf = [(fit_control, 0.9, 5.3, zb0 + 1.2, zb0 + 2.5, dict())]
        wl = [(fit_control, 0.5, 3.3, zb0 + 1.2, zb0 + 2.5, dict())]
        wr = [(fit_door, 1.5, 2.7, zb0, zb0 + 2.3, dict(awning=False, lamp="glow_cyan")), (fit_control, 3.0, 4.6, zb0 + 1.2, zb0 + 2.5, dict())]
        nb.shell(k, BOOTH, zb0, zb1, rng, {"F": wf, "L": wl, "R": wr}, t=dict(F=1.3, B=0.1, L=1.0, R=1.0),
                 akw=dict(cov=0.55, repair=0.18, max_rib=1, cw=(1.8, 3.0)), base_cornice=False, patches=0)
        with face_frame(k, "F", BOOTH):
            nb.sign_plate(k, 0.9, 3.4, zb1 - 0.55, zb1 - 0.05, "CTRL", rng, lit=True)
        with k.part(".booth_roof"):
            sb(k, x0 - 0.15, x1 + 0.15, y0, y1 + 0.15, zb1 + 0.28, zb1 + 0.4, "ceramic")
            sb(k, x0 + 0.8, x0 + 2.0, y0 + 0.6, y0 + 1.6, zb1 + 0.4, zb1 + 1.1, "machinery")
            pipe_run(k, [(x0 + 1.4, y0 + 1.1, zb1 + 0.6), (x0 + 1.4, y0 + 1.1, ZH - 0.6)], 0.09, "machinery", 2.5)
            k.beam((x1 - 0.8, y1 - 1.0, zb1 + 0.4), (x1 - 0.8, y1 - 1.0, zb1 + 1.9), 0.06, 0.06, "steel")
            lamp(k, x1 - 0.8, y1 - 1.0, zb1 + 2.0, "glow_amber", 0.07)
        for xx in (x1 + 0.35,):
            sb(k, xx - 0.3, xx + 0.3, 6.0, 6.6, ZD, ZD + 0.9, "machinery")           # locker bench outside the door
            lamp(k, xx, 6.0, ZD + 0.95, "glow_cyan", 0.05)

    def d_dock(k, rng):
        x0, x1 = -20.0, 17.5
        with k.part(".dock_deck"):
            nb.deck(k, x0, x1, 5.0, DY1, ZD, "machinery", 0.3, True, rng)
            sb(k, x0 + 0.1, x1 - 0.1, 5.1, DY1 - 0.1, 0.05, ZD - 0.4, "cavity")        # open undercroft
            for px in [x0 + 1.5 + i * 3.0 for i in range(13)]:
                sb(k, px - 0.14, px + 0.14, DY1 - 0.3, DY1 - 0.02, 0.0, ZD - 0.3, "steel", skip=("zn",))
                with k.look(0.5, (0.9, 0.7, 0.45)):
                    sb(k, px - 0.3, px + 0.3, DY1 - 0.02, DY1 + 0.2, 0.35, ZD - 0.45, "machinery")        # bumper
            pipe_run(k, [(x0 + 1.0, 8.0, 0.5), (x1 - 1.0, 8.0, 0.5)], 0.07, "machinery", 3.0)
            hazard_floor(k, x0 + 0.2, x1 - 0.2, DY1 - 0.55, DY1 - 0.1, ZD, 38)
        with k.part(".levelers"):
            for face_x in BAY_X:
                x = HB[0] + face_x
                sb(k, x + 0.2, x + BAY_W - 0.2, 5.0, 6.8, ZD, ZD + 0.06, "steel")
                for bx in (x + 0.4, x + BAY_W - 0.4):
                    sb(k, bx - 0.05, bx + 0.05, 6.8, 6.95, ZD, ZD + 0.1, "trim")
                hazard_floor(k, x + 0.25, x + BAY_W - 0.25, 6.8, 7.0, ZD + 0.06, 8)
        with k.part(".canopy"):
            sl = atan((5.95 - 5.3) / 6.6)
            with k.at(x0 - 0.5, 5.0, 5.95, rx=-sl):
                sb(k, 0.0, x1 - x0 + 1.0, 0.0, 6.62, -0.3, 0.0, "ceramic")
                for i in range(int((x1 - x0 + 1.0) / 1.1) + 1):
                    sb(k, i * 1.1 - 0.05, i * 1.1 + 0.05, 0.0, 6.62, 0.0, 0.1, "machinery")
            sb(k, x0 - 0.5, x1 + 0.5, 11.55, 11.75, 4.95, 5.55, "trim")
            for cx in (-17.5, -10.5, -3.5, 3.5, 10.5, 16.8):
                sb(k, cx - 0.14, cx + 0.14, 9.86, 10.14, ZD, 5.3, "steel")
                sb(k, cx - 0.3, cx + 0.3, 9.7, 10.3, ZD, ZD + 0.1, "machinery")
                k.beam((cx, 9.9, 3.9), (cx, 8.3, 5.3), 0.1, 0.1, "steel")
                k.beam((cx, 10.1, 3.9), (cx, 11.5, 5.3), 0.1, 0.1, "steel")
            for a in range(0, 6):
                sb(k, -19.0 + a * 7.0, -18.0 + a * 7.0, 11.3, 11.55, 5.0, 5.4, "glow_amber" if a % 2 else "ceramic")
            # overhead monorail hoist with a slung machinery pod over the dock
            sb(k, -10.6, 15.5, 7.85, 8.15, 4.7, 5.0, "steel")
            for hx in (-9.0, -3.0, 3.0, 9.0, 14.0):
                sb(k, hx - 0.04, hx + 0.04, 7.97, 8.03, 5.0, 5.4, "steel")
            tx = 6.0
            sb(k, tx - 0.35, tx + 0.35, 7.7, 8.3, 4.35, 4.7, "machinery")
            for wx in (tx - 0.3, tx + 0.3):
                k.cyl(wx, 8.0, 4.82, 0.12, 0.05, "steel", seg=6)
            k.pipe((tx, 8.0, 4.35), (tx, 8.0, 3.7), 0.025, "steel", 4)
            k.joint(tx, 8.0, 3.65, 0.09, "steel")
            for sx, sy in ((-0.5, -0.4), (0.5, -0.4), (-0.5, 0.4), (0.5, 0.4)):
                k.beam((tx, 8.0, 3.62), (tx + sx, 8.0 + sy, 3.1), 0.02, 0.02, "steel")
            with k.look(0.9, OXIDE[0]):
                sb(k, tx - 0.55, tx + 0.55, 7.6, 8.4, 2.4, 3.1, "machinery")
            sb(k, tx - 0.5, tx + 0.5, 7.58, 7.6, 2.55, 2.6, "steel", skip=("yp",))
            sb(k, tx - 0.5, tx + 0.5, 7.58, 7.6, 2.95, 3.0, "steel", skip=("yp",))
            lamp(k, tx, 7.56, 2.78, "glow_amber", 0.05)
        with k.part(".dock_stairs"):
            stair(k, (24.0, 8.0, 0.0), pi / 2, 6.5, ZD, 1.3, 0.19)
            nb.railing(k, (x1 - 0.1, 5.2, ZD), (x1 - 0.1, 7.2, ZD), 1.05, 1.0)
            nb.railing(k, (x1 - 0.1, 8.8, ZD), (x1 - 0.1, DY1 - 0.2, ZD), 1.05, 1.0)
            stair(k, (STAIR_X, 15.8, 0.0), pi, 5.3, ZD, 1.3, 0.19)
            nb.railing(k, (STAIR_X - 0.9, DY1 - 0.1, ZD), (-3.5, DY1 - 0.1, ZD), 1.05, 1.5)
            nb.railing(k, (STAIR_X + 0.9, DY1 - 0.1, ZD), (4.5, DY1 - 0.1, ZD), 1.05, 1.5)
        with k.part(".apron"):
            sb(k, -26.0, 27.0, 10.5, 17.2, 0.0, 0.1, "steel")
            for bx in (-14.0, -7.0, 7.0, 14.0):
                sb(k, bx - 0.12, bx + 0.12, 15.0, 15.24, 0.1, 0.9, "steel")
                with k.look(0.9, (1.0, 0.8, 0.4)):
                    sb(k, bx - 0.14, bx + 0.14, 14.98, 15.26, 0.65, 0.8, "trim")
            for x in (-12.0, -6.0, 8.0, 14.0):
                hazard_floor(k, x - 1.5, x + 1.5, 12.2, 12.5, 0.1, 6)
        with k.part(".dock_goods"):
            rr = random.Random("depot_dock")
            # forklift working bay 4
            fx = 9.0
            sb(k, fx - 0.7, fx + 0.7, 8.4, 10.0, ZD + 0.25, ZD + 0.9, "machinery")
            sb(k, fx - 0.7, fx + 0.7, 9.3, 10.0, ZD + 0.9, ZD + 1.15, "steel")                   # counterweight
            for wx in (fx - 0.78, fx + 0.5):
                for wy in (8.8, 9.6):
                    k.cyl(wx, wy, ZD + 0.28, 0.28, 0.28, "steel", axis="x", seg=8)
            for ux in (fx - 0.55, fx + 0.55):
                sb(k, ux - 0.04, ux + 0.04, 8.25, 8.4, ZD + 0.1, ZD + 2.3, "steel", skip=("zn",))
                sb(k, ux - 0.08, ux + 0.08, 7.5, 8.4, ZD + 0.04, ZD + 0.11, "machinery")        # fork
            for cx in (fx - 0.6, fx + 0.6):
                for cy in (8.7, 9.9):
                    sb(k, cx - 0.025, cx + 0.025, cy - 0.025, cy + 0.025, ZD + 0.9, ZD + 1.9, "steel", skip=("zn",))
            sb(k, fx - 0.7, fx + 0.7, 8.65, 9.95, ZD + 1.9, ZD + 1.96, "steel")
            lamp(k, fx, 9.3, ZD + 2.05, "glow_amber", 0.07)
            person(k, fx, 9.15, ZD + 0.9, rr, pi, True)
            pallet(k, fx - 0.7, 7.45, ZD + 0.05, 1.4, 0.9, rr, 2, 0.6)
            # staged pallets and crated machinery
            pallet(k, -11.3, 6.6, ZD, 1.2, 1.0, rr, 3)
            pallet(k, -11.3, 8.4, ZD, 1.2, 1.0, rr, 2)
            pallet(k, 0.9, 6.0, ZD, 1.4, 1.0, rr, 2)
            pallet(k, 13.2, 6.0, ZD, 1.2, 1.0, rr, 3)
            pallet(k, 14.9, 6.2, ZD, 1.2, 1.0, rr, 2, 0.4)
            for cx, cy, cw, cd, ch in ((-6.3, 9.0, 1.4, 1.0, 1.1), (-4.8, 9.1, 0.9, 0.9, 0.7), (12.2, 8.8, 1.5, 1.1, 1.0)):
                crate(k, cx, cy, ZD, cw, cd, ch, rr)
                sb(k, cx, cx + cw, cy - 0.02, cy, ZD + 0.1, ZD + ch - 0.1, "steel", skip=("yp",))
            drum(k, -7.2, 7.6, ZD, rr, 0.3, 0.9)
            drum(k, -6.6, 7.9, ZD, rr, 0.3, 0.9)
            for gx in (12.9, 13.2, 13.5):
                gas_bottle(k, gx, 9.8, ZD)
            person(k, -2.3, 7.4, ZD, rr, 1.0)
            person(k, 5.2, 9.0, ZD, rr, 4.0)
            # hand truck and loose parcels at bay 2
            sb(k, -2.9, -2.7, 8.2, 8.26, ZD, ZD + 1.2, "steel", skip=("zn",))
            sb(k, -2.9, -2.7, 8.0, 8.2, ZD + 0.1, ZD + 0.14, "steel")
            for i in range(4):
                parcel(k, -3.4 + 0.1 * i, 8.0, ZD + 0.14 + 0.28 * (i % 2), rr)
            for lx in (-12.4, 17.1):
                lamp(k, lx, 5.12, ZD + 3.0, "glow_amber", 0.05)

    def d_rear(k, rng):
        rr = random.Random("depot_rear")
        # spur track with sleepers, flat car and containers
        with k.part(".track"):
            for x in [-25.0 + i * 0.85 for i in range(61)]:
                sb(k, x - 0.14, x + 0.14, -16.1, -13.35, 0.0, 0.12, "machinery")
            for yy in (-14.0, -15.45):
                sb(k, -25.0, 26.0, yy - 0.09, yy + 0.09, 0.12, 0.2, "steel")
                sb(k, -25.0, 26.0, yy - 0.025, yy + 0.025, 0.2, 0.36, "steel")
                sb(k, -25.0, 26.0, yy - 0.07, yy + 0.07, 0.36, 0.43, "steel")
            for x in (-24.9, 25.9):
                sb(k, x - 0.1, x + 0.1, -16.0, -13.4, 0.12, 0.9, "machinery")
        with k.part(".flatcar"):
            sb(k, -16.0, 8.5, -16.0, -13.45, 1.0, 1.2, "machinery")
            sb(k, -16.0, 8.5, -16.1, -16.0, 1.2, 1.5, "steel")
            for bx in (-14.0, -9.0, 5.0):
                for yy in (-14.0, -15.45):
                    k.cyl(bx - 0.5, yy, 0.62, 0.38, 0.08, "steel", axis="x", seg=10)
                    k.cyl(bx + 0.5, yy, 0.62, 0.38, 0.08, "steel", axis="x", seg=10)
                sb(k, bx - 0.8, bx + 0.8, -15.85, -13.6, 0.8, 1.0, "steel")
            container(k, -15.5, -9.8, -15.75, -13.65, 1.2, 3.8, rr)
            container(k, -9.4, -3.7, -15.75, -13.65, 1.2, 3.8, rr)
            sb(k, -2.9, 2.5, -15.7, -13.7, 1.2, 1.5, "machinery")
            sb(k, 3.2, 8.0, -15.7, -13.7, 1.2, 2.3, "machinery")
            for i in range(3):
                parcel(k, -2.2 + 1.5 * i, -14.7, 1.5, rr, (0.7, 1.1), (0.7, 1.4))
        with k.part(".gantry"):
            gx0, gx1, gy0, gy1, gz = 10.5, 17.0, -11.4, -17.8, 7.0
            for lx in (gx0, gx1):
                for ly in (gy0, gy1):
                    sb(k, lx - 0.22, lx + 0.22, ly - 0.22, ly + 0.22, 0.0, gz, "machinery")
                    sb(k, lx - 0.4, lx + 0.4, ly - 0.4, ly + 0.4, 0.0, 0.12, "steel")
            for ly in (gy0, gy1):
                sb(k, gx0 - 0.6, gx1 + 0.6, ly - 0.3, ly + 0.3, gz, gz + 0.5, "machinery")
                nb.xbrace(k, (gx0, ly, 0.6), (gx1, ly, gz - 0.2), (gx1, ly, 0.6), (gx0, ly, gz - 0.2), 0.1)
            for lx in (gx0, gx1):
                nb.xbrace(k, (lx, gy0, 0.6), (lx, gy1, gz - 0.2), (lx, gy1, 0.6), (lx, gy0, gz - 0.2), 0.1)
            bx = 13.7
            sb(k, bx - 0.4, bx + 0.4, gy1 - 0.6, gy0 + 0.6, gz + 0.5, gz + 1.2, "steel")       # bridge girder across the track
            for i in range(10):
                yy = gy1 + 0.4 + i * 0.6
                k.beam((bx, yy, gz + 0.55), (bx, yy + 0.3, gz + 1.15), 0.06, 0.08, "machinery")
            ty = -14.7
            sb(k, bx - 0.6, bx + 0.6, ty - 0.5, ty + 0.5, gz + 0.1, gz + 0.5, "machinery")  # trolley
            sb(k, bx - 0.4, bx + 0.4, ty - 0.4, ty + 0.4, gz + 1.2, gz + 1.9, "steel")      # operator pod on the bridge
            sb(k, bx - 0.32, bx + 0.32, ty + 0.38, ty + 0.4, gz + 1.35, gz + 1.8, "glow_cyan")
            k.pipe((bx, ty, gz + 0.1), (bx, ty, 4.9), 0.03, "steel", 4)
            k.joint(bx, ty, 4.85, 0.1, "steel")
            for sx, sy in ((-0.9, -0.5), (0.9, -0.5), (-0.9, 0.5), (0.9, 0.5)):
                k.beam((bx, ty, 4.8), (bx + sx, ty + sy, 4.1), 0.025, 0.025, "steel")
            container(k, bx - 1.2, bx + 1.2, ty - 1.0, ty + 1.0, 2.3, 4.1, rr, 0.35)
            ladder(k, gx0 - 0.5, gy0 + 0.25, 0.0, gz + 0.1, 0.45, "x", cage=True)
            for lx in (gx0 + 0.2, gx1 - 0.2):
                lamp(k, lx, gy1 - 0.35, gz + 0.62, "glow_amber", 0.07)
            lamp(k, bx, ty, gz + 1.95, "glow_amber", 0.08)
        with k.part(".rear_services"):
            # rear apron, hazard threshold at the transfer door
            sb(k, -4.4, 4.4, -12.4, -8.3, 0.0, 0.1, "steel")
            hazard_floor(k, -3.0, 3.0, -9.0, -8.5, 0.1, 10)
            # upper door platform and stair
            nb.deck(k, -10.6, -7.4, -11.0, -8.0, 2.4, "machinery", 0.2, True, rr)
            nb.railing(k, (-10.5, -11.0, 2.4), (-7.5, -11.0, 2.4), 1.05, 1.5)
            nb.railing(k, (-10.5, -11.0, 2.4), (-10.5, -8.3, 2.4), 1.05, 1.5)
            for sx in (-10.5, -7.5):
                column(k, sx, -10.9, 0.0, 2.2, 0.18)
            stair(k, (-7.4, -17.0, 0.0), 0.0, 6.0, 2.4, 1.1, 0.19)
            # power-cell bank
            for r in range(2):
                for c in range(6):
                    cx, cz = -19.0 + c * 1.0, 0.3 + r * 1.2
                    with k.look(0.9, rr.choice(OXIDE + TEAL)):
                        k.cyl(cx, -9.5, cz, 0.3, 0.95, "machinery", seg=8)
                    k.cyl(cx, -9.5, cz + 0.95, 0.1, 0.1, "steel", seg=6)
                    sb(k, cx - 0.02, cx + 0.02, -9.2, -9.17, cz + 0.2, cz + 0.7, "glow_cyan" if (r + c) % 3 else "glow_amber")
            for r in range(3):
                sb(k, -19.5, -13.3, -10.0, -9.0, 1.15 * r + 0.02 + 0.12 * r, 1.15 * r + 0.2 + 0.12 * r, "steel")
            for c in (-19.5, -13.3):
                sb(k, c - 0.06, c + 0.06, -10.0, -9.9, 0.0, 2.9, "steel")
                sb(k, c - 0.06, c + 0.06, -9.1, -9.0, 0.0, 2.9, "steel")
            tendon(k, [(-16.2, -8.4, 2.9), (-16.0, -8.5, 3.6), (-16.4, -8.4, 4.1)], 0.05)
            # lockers
            for i in range(7):
                lx = 3.0 + i * 0.75
                with k.look(0.88, rr.choice(TEAL + OXIDE)):
                    sb(k, lx, lx + 0.7, -9.0, -8.45, 0.0, 2.1, "machinery")
                for vz in (1.65, 1.75, 1.85):
                    sb(k, lx + 0.12, lx + 0.58, -9.03, -9.0, vz, vz + 0.03, "cavity", skip=("yp",))
                sb(k, lx + 0.58, lx + 0.64, -9.05, -9.0, 0.95, 1.2, "steel")
                if i % 3 == 0:
                    lamp(k, lx + 0.35, -9.04, 2.0, "glow_amber", 0.03)
            sb(k, 2.9, 8.35, -9.15, -8.4, 2.1, 2.18, "steel")
            # transformer
            with k.look(0.85, OXIDE[1]):
                sb(k, -23.2, -21.0, -2.0, 0.6, 0.0, 2.1, "machinery")
            for i in range(9):
                sb(k, -23.5, -23.2, -1.9 + i * 0.28, -1.75 + i * 0.28, 0.2, 1.9, "steel")
            for i in range(3):
                with k.at(-22.5 + i * 0.6, -0.4, 2.1):
                    k.lathe([(0.1, 0), (0.1, 0.2), (0.16, 0.25), (0.12, 0.45), (0.12, 0.6), (0.0, 0.66)], "ceramic", 8, True)
            lamp(k, -21.0, -0.7, 1.6, "glow_cyan", 0.05)

    def d_sides_roof(k, rr0):
        rr = random.Random("depot_roof")
        with k.part(".left_services"):
            for y, r in ((1.0, 0.16), (2.4, 0.11)):
                pipe_run(k, [(-20.45, y, 0.5), (-20.45, y, ZH + 0.1)], r, "machinery", 2.6)
                for z in (1.5, 3.5, 5.5):
                    stand_off(k, Vector((-20.45, y, z)), "x", -20.0, r)
            conduit_bank(k, -20.7, -5.5, 0.3, ZH - 0.3, 3, 0.07, rr)
            ladder(k, -20.7, -3.8, 0.0, ZH + 0.1, 0.45, "y", cage=True)
            canister(k, -21.6, 3.8, 0.0, 3.2, 0.5)
            canister(k, -21.6, 2.2, 0.0, 3.2, 0.5)
            cistern(k, -22.0, -4.8, 0.0, 0.75, 2.4, rr)
            tendon(k, [(-20.15, 0.2, 4.3), (-20.4, 1.0, 4.6), (-20.2, 1.9, 4.2), (-20.35, 2.9, 4.7)], 0.05)
        with k.part(".right_services"):
            sb(k, 20.0, 25.0, -4.2, 4.6, 0.0, 0.08, "steel")
            hazard_floor(k, 20.2, 24.5, -3.5, 2.5, 0.08, 10, True)
            pallet(k, 22.0, 0.8, 0.0, 1.2, 1.0, rr, 3)
            pallet(k, 22.0, -1.2, 0.0, 1.2, 1.0, rr, 2)
            crate(k, 21.2, -3.3, 0.0, 1.0, 0.9, 1.4, rr)
            drum(k, 21.0, 3.6, 0.0, rr, 0.3, 0.9)
            person(k, 22.0, 2.2, 0.0, rr, -pi / 2)
            pipe_run(k, [(20.4, 4.3, 0.4), (20.4, 4.3, ZH + 0.1)], 0.14, "machinery", 2.6)
            for z in (1.5, 3.5, 5.5):
                stand_off(k, Vector((20.4, 4.3, z)), "x", 20.0, 0.14)
            lamp(k, 20.15, 4.4, 4.5, "glow_cyan", 0.05)
        with k.part(".roof"):
            rr2 = random.Random("depot_roof2")
            sb(k, -20.3, 20.3, -8.3, 5.3, ZH, ZH + 0.12, "ceramic")
            # HVAC and extract units
            for hx in (14.0, 17.2):
                sb(k, hx - 1.1, hx + 1.1, -6.6, -3.4, ZH + 0.12, ZH + 1.6, "machinery")
                for i in range(7):
                    sb(k, hx - 1.0, hx + 1.0, -6.65, -6.6, ZH + 0.45 + i * 0.12, ZH + 0.5 + i * 0.12, "cavity")
                k.cyl(hx, -3.4, ZH + 1.6, 0.6, 0.12, "steel", seg=10)
                sb(k, hx - 0.5, hx + 0.5, -3.6, -3.2, ZH + 1.72, ZH + 1.78, "cavity")
            tank_horizontal(k, -16.0, -6.5, -1.5, 0.8, ZH + 1.1, rr2)
            pipe_run(k, [(-14.0, -4.0, ZH + 0.12), (-14.0, -4.0, ZH + 2.6), (-8.0, -4.0, ZH + 2.6), (-8.0, -4.0, ZC + 0.2)], 0.1,
                     "machinery", 2.4)
            for hx in (-11.0, 6.5):
                sb(k, hx - 0.6, hx + 0.6, 2.0, 3.2, ZH + 0.12, ZH + 0.8, "machinery")
            for sx in (-18.0, -14.0):
                with k.at(sx, 3.2, ZH + 0.12):
                    k.lathe([(0.9, 0), (0.9, 0.2), (0.55, 0.5), (0.0, 0.62)], "ceramic", 8, True)
            # caged walkway along the clerestory with rails
            nb.railing(k, (-12.8, 1.4, ZH + 0.12), (12.8, 1.4, ZH + 0.12), 1.05, 2.0)
            sb(k, -12.6, 12.6, 0.6, 1.4, ZH + 0.12, ZH + 0.22, "steel")
            ladder(k, 12.3, 0.55, ZH + 0.12, ZC + 0.1, 0.45, "x")
            # mast, dish, beacon
            with k.at(-10.0, -2.8, ZC + 0.2):
                k.lathe([(0.45, 0), (0.45, 0.4), (0.25, 0.4), (0.25, 4.2), (0.35, 4.2), (0.35, 4.5), (0.2, 4.5)], "steel", 8, True)
            lamp(k, -10.0, -2.8, ZC + 4.9, "glow_amber", 0.09)
            with k.at(8.0, -2.0, ZC + 0.2, rx=-0.9):
                k.lathe([(0.0, 0.0), (0.6, 0.1), (1.1, 0.4), (1.15, 0.45)], "ceramic", 8, True)
                lamp(k, 0, 0, 1.0, "glow_cyan", 0.06)
            tendon(k, [(4.0, -1.0, ZC + 0.2), (4.4, -1.1, ZC + 0.7), (4.2, -1.0, ZC + 1.2)], 0.05)
            # skylight rows over the sorting floor, roof hatch, cable tray and a second vent stack
            for sx0 in (-9.0, -3.0, 3.0, 9.0, 15.0):
                sb(k, sx0, sx0 + 2.4, 2.4, 4.2, ZH + 0.12, ZH + 0.5, "ceramic")
                sb(k, sx0 + 0.2, sx0 + 2.2, 2.6, 4.0, ZH + 0.5, ZH + 0.54, "cavity")
                for i in range(1, 4):
                    sb(k, sx0 + 0.6 * i - 0.025, sx0 + 0.6 * i + 0.025, 2.6, 4.0, ZH + 0.54, ZH + 0.62, "steel")
            sb(k, -19.0, -15.6, -2.4, 0.0, ZH + 0.12, ZH + 0.6, "machinery")
            sb(k, -18.6, -16.0, -2.0, -0.4, ZH + 0.6, ZH + 0.66, "cavity")
            sb(k, 12.6, 19.2, -2.4, -1.8, ZH + 0.12, ZH + 0.3, "machinery")
            for tx in [13.0 + 0.9 * i for i in range(7)]:
                sb(k, tx, tx + 0.08, -2.4, -1.8, ZH + 0.3, ZH + 0.4, "steel")
            tendon(k, [(13.4, -2.1, ZH + 0.42), (15.0, -2.1, ZH + 0.5), (16.4, -2.0, ZH + 0.44), (18.4, -2.1, ZH + 0.5)], 0.04)
            with k.at(-5.5, 3.8, ZH + 0.12):
                k.lathe([(0.35, 0), (0.35, 2.4), (0.5, 2.4), (0.5, 2.6), (0.2, 2.6)], "steel", 8, True)
            lamp(k, -5.5, 3.8, ZH + 2.75, "glow_amber", 0.06)
            drum(k, -12.6, 4.4, ZH + 0.12, rr2, 0.3, 0.9)
            drum(k, -11.9, 4.5, ZH + 0.12, rr2, 0.3, 0.9)

    parts = [d_hall, d_booth, d_dock, d_rear, d_sides_roof]

    @nb.building("freight_depot", cls="building", parts=parts, facade=(HB, 5.0), tint=(1.0, 0.9, 0.68),
                 identity="Long low freight and logistics depot: a covered raised loading dock with ribbed bay openings onto working "
                          "conveyor, rack and hoist interiors, a glazed control booth, monorail hoist, forklift and staged crates, "
                          "a rear rail spur with flat car and portal gantry, power cells and lockers, and a roof service deck.",
                 brief="Faded industrial ochre/oxide accents over chipped bone armour on shared dark steel; sparse tendon breaches; "
                       "tiny amber/cyan warning lamps.")
    def depot_targets(off):
        """Design-space review points: stair foot to the dock, a working bay, and the rear gantry yard."""
        return dict(entry=(STAIR_X, 16.6, 1.3), activity=(BAY_X[2] + BAY_W / 2 - 20.0, 12.4, 2.0), service=(12.0, -19.0, 1.8))

    nb.SHOTS["freight_depot"] = [
        ("front_studio", 0, (0, 84, 11), (0, 0, 3.5), 38, None, (1600, 1200)),
        ("front_three_quarter", -25, (-50, 58, 14), (0, 0, 3.5), 38, None, (1600, 1200)),
        ("entry_street_human", 0, (-6, 27, 1.7), (-1, 6, 2.6), 28, (2.6, 17.5), (1600, 1200)),
        ("activity_dock", 0, (-1, 19, 3.4), (4, 6, 2.6), 30, (1.5, 11.5), (1600, 1200)),
        ("rear_service", 180, (6, -48, 9), (3, -10, 3.5), 34, (-1.5, -12.0), (1600, 1200)),
        ("roof_service", 180, (-28, -32, 33), (0, -1, 5), 36, None, (1600, 1200)),
        ("side_control_booth", -90, (-54, 8, 8), (-14, 6, 3), 34, (-24.0, 8.0), (1600, 1200)),
        ("gantry_closeup", 180, (30, -34, 9), (12, -14, 4.2), 34, None, (1600, 1200)),
    ]
