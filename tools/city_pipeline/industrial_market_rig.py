"""Capsule-bone linear-blend skinning for the Human Base Meshes bodies (numpy only; no Blender armature).

Weights are a pure function of the rest-pose position, so clothing / boots / hair built in the rest pose deform with the body.
FK poses come from 2-bone IK (arms and legs), a spine lean, head tilt, foot yaw and per-finger curls; the result is baked.
"""
import math

import numpy as np

import industrial_market_humans as HU

unit, rot_axis, rot_between, frame_rot = HU.unit, HU.rot_axis, HU.rot_between, HU.frame_rot
REST_CURL = (0.28, 0.40, 0.30)
IDT = (np.eye(3), np.zeros(3))
MIR = np.array([-1, 1, 1.0])


def compose(A, B):
    return (A[0] @ B[0], A[0] @ B[1] + A[1])


def about(R, c):
    return (R, c - R @ c)


def ik2(S, W, a, b, pole):
    S, W, pole = np.asarray(S, float), np.asarray(W, float), np.asarray(pole, float)
    d = W - S
    Ld = min(np.linalg.norm(d), a + b - 1e-3)
    dv = unit(d)
    x = (a * a - b * b + Ld * Ld) / (2 * Ld)
    h = math.sqrt(max(a * a - x * x, 1e-8))
    perp = pole - dv * (pole @ dv)
    perp = unit(perp) if np.linalg.norm(perp) > 1e-6 else np.array([0, 0, 1.0])
    return S + dv * x + perp * h, S + dv * Ld


def analyse_hand(base):
    """Rest-pose hand frame of the +X hand."""
    P, s = base.P, base.s
    W = base.L["W1"]
    Q = P[(P[:, 0] > 0.30 * s) & (P[:, 2] < W[2] + 0.01)]
    tip = Q[np.argmax(np.linalg.norm(Q - W, axis=1))]
    hd = unit(tip - W)
    rel = Q - W
    b1 = unit(np.array([0, 1.0, 0]) - hd * hd[1])
    b2 = np.cross(hd, b1)
    return dict(W=W, hd=hd, Lh=float((rel @ hd).max()), Q=Q, a=rel @ hd, c1=rel @ b1, c2=rel @ b2, b1=b1, b2=b2)


class Rig:
    def __init__(self, base):
        self.b = base
        s, L = base.s, base.L
        self.bones = {}

        def add(n, a, b, r):
            self.bones[n] = (np.asarray(a, float), np.asarray(b, float), r * s)
        add("pelvis", 0.5 * (L["hip1"] + L["hip-1"]), L["waist"], 0.17)
        add("chest", L["waist"], L["neck_base"], 0.19)
        add("neck", L["neck_base"], L["head_base"], 0.055)
        add("head", L["head_base"] - np.array([0, 0, 0.02 * s]), L["head_top"], 0.12)
        for sd, k in ((1, "R"), (-1, "L")):
            add(f"thigh{k}", L[f"hip{sd}"], L[f"knee{sd}"], 0.085)
            add(f"shin{k}", L[f"knee{sd}"], L[f"ankle{sd}"], 0.052)
            add(f"foot{k}", L[f"ankle{sd}"], L[f"toe{sd}"], 0.05)
            add(f"upper{k}", L[f"S{sd}"], L[f"E{sd}"], 0.048)
            add(f"fore{k}", L[f"E{sd}"], L[f"W{sd}"], 0.040)
        self.hand = analyse_hand(base)
        self._build_hand()
        self.names = list(self.bones.keys())

    def _build_hand(self):
        s = self.b.s
        h = self.hand
        W, hd, Lh, Q, a, c1 = h["W"], h["hd"], h["Lh"], h["Q"], h["a"], h["c1"]
        zone = a > 0.60 * Lh
        x = c1[zone]
        cen = np.quantile(x, [0.12, 0.37, 0.63, 0.88])
        for _ in range(25):
            lab = np.argmin(np.abs(x[:, None] - cen[None, :]), 1)
            cen = np.array([x[lab == k].mean() if (lab == k).any() else cen[k] for k in range(4)])
        allc = np.argmin(np.abs(c1[:, None] - cen[None, :]), 1)
        thumbm = (c1 > cen.max() + 0.02 * s) & (a > 0.15 * Lh) & (a < 0.75 * Lh)
        fingers = []
        for k in range(4):
            sel = (allc == k) & (a > 0.46 * Lh) & (~thumbm)
            pts = []
            for fr in (0.46, 0.64, 0.80, 0.99):
                sl = sel & (np.abs(a - fr * Lh) < 0.045 * Lh)
                if sl.sum() < 2:
                    sl = sel & (np.abs(a - fr * Lh) < 0.12 * Lh)
                pts.append(Q[sl].mean(0) if sl.any() else W + hd * fr * Lh + cen[k] * h["b1"])
            fingers.append(pts)
        T = Q[thumbm]
        tc = T.mean(0)
        ax = np.linalg.svd(T - tc, full_matrices=False)[2][0]
        ax = ax if (ax @ hd) > 0 else -ax
        tp = (T - tc) @ ax
        b0, t1 = tc + ax * tp.min(), tc + ax * tp.max()
        thumb = [b0 + (t1 - b0) * f for f in (0.0, 0.42, 0.74, 1.0)]
        self.fingers_rest, self.thumb_rest, self.thumb_mask = fingers, thumb, int(thumbm.sum())
        palm_end = np.mean([f[0] for f in fingers], 0)
        self.bones["palmR"] = (W, palm_end, 0.045 * s)
        for k, f in enumerate(fingers):
            for j in range(3):
                self.bones[f"fing{k}_{j}R"] = (f[j], f[j + 1], 0.0095 * s * (1.0 - 0.1 * j))
        for j in range(3):
            self.bones[f"thumb{j}R"] = (thumb[j], thumb[j + 1], 0.012 * s * (1.0 - 0.1 * j))
        for n in [n for n in self.bones if n.endswith("R") and (n.startswith(("palm", "fing", "thumb")))]:
            a_, b_, r_ = self.bones[n]
            self.bones[n[:-1] + "L"] = (a_ * MIR, b_ * MIR, r_)
        n_rest = unit(h["b2"] * (-1 if h["b2"][0] > 0 else 1))
        self.hf_rest = {"R": (hd, n_rest), "L": (hd * MIR, n_rest * MIR)}

    def weights(self, pts, alpha=1.6, keep=4):
        pts = np.asarray(pts, float)
        D = np.zeros((len(pts), len(self.names)))
        for i, n in enumerate(self.names):
            a, b, r = self.bones[n]
            ab = b - a
            t = np.clip(((pts - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
            D[:, i] = np.linalg.norm(pts - (a + t[:, None] * ab), axis=1) / r
        S = D ** 2
        idx = np.argsort(S, 1)[:, :keep]
        rows = np.arange(len(pts))[:, None]
        sel = S[rows, idx]
        W = np.zeros_like(S)
        W[rows, idx] = np.exp(-alpha * (sel - sel[:, :1]))
        return W / W.sum(1, keepdims=True)

    def transforms(self, pose):
        L = self.b.L
        T = {n: IDT for n in self.names}
        lean = pose.get("lean_angle", 0.0)
        sh = np.asarray(pose.get("pelvis_shift", (0, 0, 0)), float)
        hipm = 0.5 * (L["hip1"] + L["hip-1"])
        T_pel = compose((np.eye(3), sh), about(rot_axis([0, 0, 1], pose.get("pelvis_yaw", 0.0)) @ rot_axis([0, 1, 0], pose.get("pelvis_roll", 0.0)), hipm))
        T_chest = compose(T_pel, about(rot_axis([1, 0, 0], lean), L["waist"]))
        hp, hy = pose.get("head_tilt", (0.0, 0.0))
        T["pelvis"], T["chest"] = T_pel, T_chest
        T["neck"] = compose(T_chest, about(rot_axis([1, 0, 0], hp * 0.4) @ rot_axis([0, 0, 1], hy * 0.4), L["neck_base"]))
        T["head"] = compose(T_chest, about(rot_axis([1, 0, 0], hp) @ rot_axis([0, 0, 1], hy), L["head_base"]))
        info = {"T_chest": T_chest, "T_pel": T_pel}
        for sd, k in ((1, "R"), (-1, "L")):
            H0, K0, A0 = L[f"hip{sd}"], L[f"knee{sd}"], L[f"ankle{sd}"]
            Hn = T_pel[0] @ H0 + T_pel[1]
            fx, fy, fyaw = pose["feet"][k]
            An = np.array([fx, fy, A0[2] + pose.get("ankle_lift", 0.0)])
            Kn, _ = ik2(Hn, An, np.linalg.norm(K0 - H0), np.linalg.norm(A0 - K0), (0, 1, 0))
            Ru = rot_between(T_pel[0] @ (K0 - H0), Kn - Hn) @ T_pel[0]
            Rs = rot_between(Ru @ (A0 - K0), An - Kn) @ Ru
            T[f"thigh{k}"] = (Ru, Hn - Ru @ H0)
            T[f"shin{k}"] = (Rs, Kn - Rs @ K0)
            rest_yaw = math.atan2(-(L[f"toe{sd}"][0] - L[f"heel{sd}"][0]), L[f"toe{sd}"][1] - L[f"heel{sd}"][1])
            Rf = rot_axis([0, 0, 1], fyaw - rest_yaw)
            T[f"foot{k}"] = (Rf, An - Rf @ A0)
            info[f"knee{k}"], info[f"ankle{k}"], info[f"hip{k}"] = Kn, An, Hn
        for sd, k in ((1, "R"), (-1, "L")):
            arm = pose["arms"][k]
            S0, E0, W0 = L[f"S{sd}"], L[f"E{sd}"], L[f"W{sd}"]
            Sn = T_chest[0] @ S0 + T_chest[1]
            En, Wn = ik2(Sn, arm["wrist"], np.linalg.norm(E0 - S0), np.linalg.norm(W0 - E0), arm["pole"])
            Ru = rot_between(T_chest[0] @ (E0 - S0), En - Sn) @ T_chest[0]
            Rf = rot_between(Ru @ (W0 - E0), Wn - En) @ Ru
            T[f"upper{k}"] = (Ru, Sn - Ru @ S0)
            T[f"fore{k}"] = (Rf, En - Rf @ E0)
            hd = arm["hand"]
            f0, n0 = self.hf_rest[k]
            Rh = frame_rot(hd["f"], hd["n"]) @ frame_rot(f0, n0).T
            Tp = (Rh, Wn - Rh @ W0)
            T[f"palm{k}"] = Tp
            info[f"elbow{k}"], info[f"wrist{k}"], info[f"shoulder{k}"] = En, Wn, Sn
            mir = np.ones(3) if sd == 1 else MIR
            axis_rest = unit(np.cross(f0, n0))
            for fi in range(4):
                joints = [self.fingers_rest[fi][j] * mir for j in range(4)]
                cur = Tp
                for j in range(3):
                    cur = compose(cur, about(rot_axis(axis_rest, hd["curls"][fi][j] - REST_CURL[j]), joints[j]))
                    T[f"fing{fi}_{j}{k}"] = cur
            thj = [self.thumb_rest[j] * mir for j in range(4)]
            cur = Tp
            for j in range(3):
                cd = cur[0] @ (thj[j + 1] - thj[j])
                Rt = rot_between(cd, unit(cd * 0.4 + unit(hd["thumb"][j]) * 0.6))
                cur = compose(about(Rt, cur[0] @ thj[j] + cur[1]), cur)
                T[f"thumb{j}{k}"] = cur
        self.info = info
        return T

    def apply(self, pts, W, T):
        out = np.zeros_like(pts)
        for i, n in enumerate(self.names):
            w = W[:, i]
            if w.any():
                R, t = T[n]
                out += w[:, None] * (pts @ R.T + t)
        return out
