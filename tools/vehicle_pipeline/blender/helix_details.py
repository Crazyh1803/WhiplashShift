"""Source-driven surface detail: carapace tendons and fender bolts."""
import bmesh

import helix_prims as P
import helix_trace as T
from helix_body import SIDES, SN, Surface


def build(builder, hull, surf):
    for s in SIDES:
        for j, frac in enumerate((0.55, 0.78)):
            path = []
            for k in range(26):
                x = T.X(326 + 5.2 * k)
                y = s * T.half_w(x) * frac
                path.append((x, y, surf.top_z(x, y) + 0.026))
            P.tube(builder, f"Body_Tendon{j}_{SN[s]}", path, [0.0145 * min(1.0, 0.25 + 0.75 * min(k, 25 - k) / 4) for k in range(26)], "rubber", sides=10, ribs=26, rib_depth=0.18)
        fender = builder.cols["HELIX_SOURCE"].objects[f"Body_Fender_{SN[s]}"]
        fs = Surface(fender)
        bm = bmesh.new()
        for row in (-0.085, 0.085):
            for k in range(1, 8):
                x = T.X(334 + 16.0 * k)
                y = s * (T.TRACK_Y + row)
                z = fs.top_z(x, y)
                if z is not None:
                    P.bm_cyl(bm, (x, y, z), (0, 0, 1), 0.014, 0.014, sides=8)
        P.bm_object(builder, f"Fine_Bolts_{SN[s]}", bm, "hardware")
