"""People for the industrial market benchmark: a Human Base Meshes adult body (see industrial_market_figure) wearing fitted garments.

build_person() fits the garment shells / boots / hair to the rest-pose anatomy, adds hand-made details (collars, apron, pockets, headband)
that sample the clothed body, unwraps the skin, and finally poses everything with the capsule rig (see industrial_market_rig).
thick_sheet() is the shared cloth-with-thickness sheet builder used by industrial_market_dress.
"""
import math

import numpy as np
from mathutils import Vector

import industrial_market_figure as FG

V = Vector
g = FG.g
unit = FG.unit


# ----------------------------------------------------------------------------------------- thick sheets
def thick_sheet(m, grid_fn, nu, nv, thick, mat, flip=False, uv_scale=2.0):
    """grid_fn(i,j)->Vector on the outer surface (i in 0..nu, j in 0..nv). Builds front + back + edge strips (cloth with thickness)."""
    outer = [[grid_fn(i, j) for i in range(nu + 1)] for j in range(nv + 1)]
    inner = []
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            du = outer[j][min(i + 1, nu)] - outer[j][max(i - 1, 0)]
            dv = outer[min(j + 1, nv)][i] - outer[max(j - 1, 0)][i]
            nrm = du.cross(dv)
            nrm = nrm.normalized() if nrm.length > 1e-9 else V((0, 1, 0))
            if flip:
                nrm = -nrm
            row.append(outer[j][i] - nrm * thick)
        inner.append(row)
    uvf = lambda ri, cj, nr, nc: (cj / (nc - 1) * uv_scale, ri / (nr - 1) * uv_scale)
    m.surface(outer, False, mat, smooth=True, uv_fn=uvf, flip=flip)
    m.surface(inner, False, mat, smooth=True, uv_fn=uvf, flip=not flip)
    edges = [[outer[0][i] for i in range(nu + 1)], [outer[nv][i] for i in range(nu + 1)]]
    inedges = [[inner[0][i] for i in range(nu + 1)], [inner[nv][i] for i in range(nu + 1)]]
    for e, ie, fl in ((edges[0], inedges[0], False), (edges[1], inedges[1], True)):
        m.surface([e, ie], False, mat, smooth=False, flip=fl)
    le = [outer[j][0] for j in range(nv + 1)]
    lie = [inner[j][0] for j in range(nv + 1)]
    re_ = [outer[j][nu] for j in range(nv + 1)]
    rie = [inner[j][nu] for j in range(nv + 1)]
    m.surface([le, lie], False, mat, smooth=False, flip=True)
    m.surface([re_, rie], False, mat, smooth=False, flip=False)


# ---------------------------------------------------------------------------------------------- person
def build_person(m, P):
    """P: person spec dict (see build_industrial_market.person_specs). Returns an info dict incl. the Figure and the baked pose frames."""
    H = P["H"]
    fig = FG.Figure(m, P["body"], H, P["seed"])
    s = fig.s
    L = fig.base.L
    pm = P["mat"]
    top, trou, leather, hair, skin = pm["top"], pm["trousers"], pm["leather"], pm["hair"], pm["skin"]
    hem_z, neck_z = P["hem"] * H, P["neck_cut"] * H
    cuff_z, legs_top = P["cuff"] * H, 0.60 * H
    reg_top = fig.region_top(hem_z, neck_z, P["sleeve_t"])
    reg_legs = fig.region_legs(legs_top, cuff_z)

    # ---- trousers (under) then the top garment (over); snap planes give clean hems / cuffs / neck
    z_ax = np.array([0, 0, 1.0])
    snaps_legs = [((0, 0, cuff_z), z_ax), ((0, 0, legs_top), z_ax)]
    kn = lambda k: L[f"knee{k}"]
    jt_legs = [(kn(sd), z_ax, 0.024 * s, 0.0042, 0.06 * s, np.array([0, 1.0, 0])) for sd in (1, -1)]
    ease_t = P["trousers_ease"]

    def ease_legs(Pq, Nq, idx):
        return ease_t * (1 + 0.15 * g(Pq[:, 2] - 0.30 * H, 0.2)) + 0.012 * g(Pq[:, 2] - cuff_z, 0.045)
    fig.shell(reg_legs, trou, ease_legs, fig.folds_fn(joints=jt_legs, amp=P["fold_amp"]), snaps_legs, rim=1)
    snaps_top = [((0, 0, hem_z), z_ax), ((0, 0, neck_z), z_ax)]
    jt_arm = []
    for sd in (1, -1):
        E, W = L[f"E{sd}"], L[f"W{sd}"]
        ax = unit(W - E)
        snaps_top.append((E + (W - E) * P["sleeve_t"], ax))
        jt_arm.append((E, ax, 0.021 * s, 0.0048, 0.05 * s, np.array([0, -1.0, 0])))
    e_top = P["top_ease"]

    def ease_top(Pq, Nq, idx):
        belly = 1 + P["top_drop"] * g(Pq[:, 2] - 0.60 * H, 0.1 * H) * (np.abs(Pq[:, 0]) < 0.17 * s)
        sleeve = np.where(np.isin(fig.dom[idx], ["upperR", "upperL", "foreR", "foreL"]), 0.75, 1.0)
        return e_top * belly * sleeve + 0.010 * g(Pq[:, 2] - hem_z, 0.04) * (1 - 0.5 * (sleeve < 1))
    fig.shell(reg_top, top, ease_top, fig.folds_fn(hem_z=hem_z, joints=jt_arm, amp=P["fold_amp"]), snaps_top, rim=1)
    fig.hide_covered(reg_top | reg_legs, margin=3)

    # ---- boots / shoes
    for sd in (1, -1):
        fig.boot(sd, leather, shaft_top=P["boot_top"] * H if P.get("boot_top") else 0.0, ease=P["boot_ease"], shaft_ease=P.get("shaft_ease"))
    # ---- hair (scalp skin underneath is dropped)
    ok = fig.hair(hair, thick=P["hair_thick"], ponytail=P.get("ponytail", False), back_len=P.get("hair_back", 0.0), front=P.get("hairline", 0.072))
    fig.hide_covered(ok, margin=1)
    # ---- skin + UVs
    fig.skin(skin, drop_below=cuff_z + 0.01)
    fig.skin_uv()
    # ---- hand-made garment details sampled on the clothed rest body
    P["dress"](fig, m, P)
    return fig


def neck_ring(fig, z):
    """Centre / radii of the neck column at height z (rest)."""
    p = fig.P[(np.abs(fig.P[:, 2] - z) < 0.008 * fig.s) & (np.abs(fig.P[:, 0]) < 0.075 * fig.s)]
    c = 0.5 * (p.min(0) + p.max(0))
    return V((c[0], c[1], z)), 0.5 * (p[:, 0].max() - p[:, 0].min()), 0.5 * (p[:, 1].max() - p[:, 1].min())
