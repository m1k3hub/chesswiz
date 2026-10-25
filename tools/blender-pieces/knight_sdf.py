# Knight head as a signed distance field, meshed with surface nets.
# Pure numpy (runs inside Blender's Python). Coordinates match the GL
# piece data: Z up, base centre at the origin, the horse looks toward -Y,
# X is the width of the head.
import numpy as np

# ---------------------------------------------------------------- helpers

def catmull_rom(pts, n=8, closed=True):
    p = np.asarray(pts, float)
    if closed:
        p = np.vstack([p[-1], p, p[0], p[1]])
    else:
        p = np.vstack([p[0], p, p[-1]])
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    if not closed:
        out.append(p[-2])
    return np.array(out)


def sd_polygon(P, V):
    """Signed distance from 2D points P (N,2) to closed polygon V (M,2)."""
    d = np.sum((P - V[0]) ** 2, axis=1)
    s = np.ones(len(P))
    j = len(V) - 1
    for i in range(len(V)):
        e = V[j] - V[i]
        w = P - V[i]
        b = w - e * np.clip((w @ e) / (e @ e), 0, 1)[:, None]
        d = np.minimum(d, np.sum(b * b, axis=1))
        c1 = P[:, 1] >= V[i, 1]
        c2 = P[:, 1] < V[j, 1]
        c3 = e[0] * w[:, 1] > e[1] * w[:, 0]
        flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
        s[flip] *= -1
        j = i
    return s * np.sqrt(d)


def sd_polyline(P, V):
    """Unsigned distance to an open polyline plus arc-length parameter."""
    best = np.full(len(P), 1e9)
    par = np.zeros(len(P))
    acc = 0.0
    for i in range(len(V) - 1):
        e = V[i + 1] - V[i]
        L = np.sqrt(e @ e)
        w = P - V[i]
        t = np.clip((w @ e) / (L * L), 0, 1)
        b = w - e * t[:, None]
        dd = np.sqrt(np.sum(b * b, axis=1))
        m = dd < best
        best[m] = dd[m]
        par[m] = acc + t[m] * L
        acc += L
    return best, par, acc


def smin(a, b, k):
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def sd_ellipsoid(X, Y, Z, c, r):
    x = (X - c[0]) / r[0]
    y = (Y - c[1]) / r[1]
    z = (Z - c[2]) / r[2]
    k0 = np.sqrt(x * x + y * y + z * z)
    k1 = np.sqrt((x / r[0]) ** 2 + (y / r[1]) ** 2 + (z / r[2]) ** 2)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_round_cone(X, Y, Z, a, b, ra, rb):
    """Capsule from a (radius ra) to b (radius rb), approximate."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ba = b - a
    L2 = ba @ ba
    px, py, pz = X - a[0], Y - a[1], Z - a[2]
    t = np.clip((px * ba[0] + py * ba[1] + pz * ba[2]) / L2, 0, 1)
    dx, dy, dz = px - ba[0] * t, py - ba[1] * t, pz - ba[2] * t
    return np.sqrt(dx * dx + dy * dy + dz * dz) - (ra + (rb - ra) * t)


# ---------------------------------------------------------------- design

# Side silhouette (y, z): horse looks toward -y. Traced counter-clockwise
# from the bottom of the chest.
PROFILE = [
    (-0.150, 0.215),   # chest, inside the plinth
    (-0.175, 0.300),
    (-0.190, 0.370),   # breast
    (-0.170, 0.430),
    (-0.120, 0.475),   # throat latch
    (-0.120, 0.505),
    (-0.165, 0.510),   # under the jaw
    (-0.215, 0.500),   # chin groove
    (-0.255, 0.493),   # lower lip
    (-0.282, 0.512),
    (-0.290, 0.545),   # muzzle front
    (-0.285, 0.585),
    (-0.262, 0.622),   # nose bridge
    (-0.205, 0.672),
    (-0.135, 0.725),   # forehead
    (-0.070, 0.775),
    (-0.010, 0.805),   # poll (between the ears)
    (0.050, 0.800),
    (0.105, 0.765),    # crest of the neck
    (0.150, 0.700),
    (0.180, 0.610),
    (0.195, 0.500),
    (0.200, 0.380),
    (0.190, 0.270),
    (0.170, 0.215),
]

# Line the mane follows: just inside the rear silhouette, poll to withers.
MANE = [
    (-0.030, 0.800),
    (0.040, 0.795),
    (0.100, 0.760),
    (0.145, 0.700),
    (0.175, 0.610),
    (0.190, 0.500),
    (0.194, 0.390),
    (0.188, 0.300),
]


def half_width(Y, Z):
    """Half thickness of the extruded silhouette (x direction)."""
    neck = 0.115 + 0.055 * smoothstep(0.52, 0.24, Z)        # thicker low down
    head = 0.098 - 0.135 * np.clip(-Y - 0.04, 0, 0.26)      # taper to muzzle
    head = head - 0.012 * smoothstep(0.70, 0.80, Z)         # narrower forehead
    t = smoothstep(0.44, 0.56, Z) * smoothstep(0.02, -0.10, Y)
    return neck * (1 - t) + head * t


def knight_sdf(X, Y, Z):
    # 2D quantities on the (y, z) plane are evaluated once per column
    Y2 = Y[0]
    Z2 = Z[0]
    P = np.stack([Y2.ravel(), Z2.ravel()], axis=1)
    prof = catmull_rom(PROFILE, n=10)
    d2 = sd_polygon(P, prof).reshape(Y2.shape)
    mane = catmull_rom(MANE, n=10, closed=False)
    dm, tm, Lm = sd_polyline(P, mane)
    dm = dm.reshape(Y2.shape)
    tm = tm.reshape(Y2.shape)
    w = half_width(Y2, Z2)

    ax = np.abs(X)
    r = 0.040
    qx = d2[None] + r
    qy = ax - w[None] + r
    body = (np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
            + np.minimum(np.maximum(qx, qy), 0) - r)

    # cheek / round jowl, both sides
    for sx in (-1, 1):
        jowl = sd_ellipsoid(X, Y, Z, (sx * 0.040, -0.075, 0.565), (0.060, 0.085, 0.072))
        body = smin(body, jowl, 0.04)

    # muzzle: slightly bulbous nose and lips
    nose = sd_ellipsoid(X, Y, Z, (0.0, -0.255, 0.555), (0.072, 0.050, 0.060))
    body = smin(body, nose, 0.03)

    # mane crest: a raised ribbon along the back with carved tufts
    t = tm[None]
    crest = np.sqrt(np.maximum(dm[None] - 0.022, 0) ** 2 + np.maximum(ax - 0.050, 0) ** 2) - 0.012
    crest = np.where(dm[None] < 0.022, np.maximum(ax - 0.050, -1) - 0.012, crest)
    body = smin(body, crest, 0.025)
    # tufts: diagonal grooves across the mane, deeper near the crest line
    near = smoothstep(0.075, 0.015, dm[None]) * smoothstep(0.0, 0.04, t) * smoothstep(Lm, Lm - 0.06, t)
    phase = (t / 0.042 + ax / 0.030) * 2 * np.pi
    body = body + near * 0.0065 * (0.5 + 0.5 * np.cos(phase))

    # ears: pointed, leaning slightly back and outward
    for sx in (-1, 1):
        ear = sd_round_cone(X, Y, Z, (sx * 0.040, 0.012, 0.770), (sx * 0.056, 0.045, 0.918), 0.036, 0.009)
        body = smin(body, ear, 0.018)
        # hollow in the front of the ear
        hole = sd_ellipsoid(X, Y, Z, (sx * 0.044, 0.000, 0.850), (0.013, 0.013, 0.045))
        body = smax(body, -hole, 0.006)

    # eyes: brow bulge with a socket, set on the side of the head
    for sx in (-1, 1):
        ex = sx * 0.076
        brow = sd_ellipsoid(X, Y, Z, (ex, -0.110, 0.692), (0.028, 0.038, 0.027))
        body = smin(body, brow, 0.02)
        ball = sd_ellipsoid(X, Y, Z, (sx * 0.097, -0.114, 0.686), (0.012, 0.020, 0.014))
        body = smax(body, -ball, 0.006)
        # nostrils
        nos = sd_ellipsoid(X, Y, Z, (sx * 0.040, -0.300, 0.568), (0.016, 0.016, 0.012))
        body = smax(body, -nos, 0.006)

    # mouth line
    mline = np.sqrt((Z - (0.522 + (Y + 0.32) * 0.07)) ** 2 + 0.0) - 0.0065
    mline = np.maximum(mline, Y + 0.215)
    body = smax(body, -mline, 0.006)

    # cheek line separating the jaw from the neck (subtle carved groove)
    groove = np.abs(np.sqrt((Y + 0.045) ** 2 + (Z - 0.585) ** 2) - 0.080) - 0.0035
    groove = np.maximum(groove, -0.040 - Y)          # rear arc of the jaw only
    groove = np.maximum(groove, Z - 0.64)
    groove = np.maximum(groove, 0.505 - Z)
    groove = np.maximum(groove, -body - 0.012)      # carve the surface only
    body = smax(body, -groove, 0.008)

    # plinth that seats the neck into the base collar
    rr = np.sqrt(X * X + Y * Y)
    plinth = np.maximum(rr - 0.225, np.maximum(Z - 0.262, 0.215 - Z))
    body = smin(body, plinth, 0.07)
    return body


# ---------------------------------------------------------------- meshing

def surface_nets(F, origin, h):
    nx, ny, nz = F.shape
    corners = [(i, j, k) for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    cv = [F[i:nx - 1 + i, j:ny - 1 + j, k:nz - 1 + k] for (i, j, k) in corners]
    edges = [(a, b) for a in range(8) for b in range(a + 1, 8)
             if sum(abs(np.subtract(corners[a], corners[b]))) == 1]
    acc = np.zeros(cv[0].shape + (3,), np.float32)
    cnt = np.zeros(cv[0].shape, np.int16)
    for a, b in edges:
        fa, fb = cv[a], cv[b]
        m = (fa < 0) != (fb < 0)
        t = np.where(m, fa / np.where(m, fa - fb, 1), 0)
        ca = np.array(corners[a], np.float32)
        cb = np.array(corners[b], np.float32)
        acc += m[..., None] * (ca + t[..., None] * (cb - ca))
        cnt += m
    has = cnt > 0
    idx = np.full(cnt.shape, -1, np.int64)
    idx[has] = np.arange(has.sum())
    gi = np.argwhere(has)
    verts = origin + (gi + acc[has] / cnt[has][:, None]) * h

    quads = []
    inside = F < 0
    # x edges
    m = inside[:-1, 1:-1, 1:-1] != inside[1:, 1:-1, 1:-1]
    for i, j, k in np.argwhere(m):
        j += 1; k += 1
        q = [idx[i, j - 1, k - 1], idx[i, j, k - 1], idx[i, j, k], idx[i, j - 1, k]]
        quads.append(q if inside[i, j, k] else q[::-1])
    m = inside[1:-1, :-1, 1:-1] != inside[1:-1, 1:, 1:-1]
    for i, j, k in np.argwhere(m):
        i += 1; k += 1
        q = [idx[i - 1, j, k - 1], idx[i - 1, j, k], idx[i, j, k], idx[i, j, k - 1]]
        quads.append(q if inside[i, j, k] else q[::-1])
    m = inside[1:-1, 1:-1, :-1] != inside[1:-1, 1:-1, 1:]
    for i, j, k in np.argwhere(m):
        i += 1; j += 1
        q = [idx[i - 1, j - 1, k], idx[i, j - 1, k], idx[i, j, k], idx[i - 1, j, k]]
        quads.append(q if inside[i, j, k] else q[::-1])
    return verts, np.array(quads, np.int64)


def build(h=0.0035):
    lo = np.array([-0.17, -0.35, 0.205])
    hi = np.array([0.17, 0.25, 0.94])
    n = np.ceil((hi - lo) / h).astype(int) + 1
    xs = lo[0] + np.arange(n[0]) * h
    ys = lo[1] + np.arange(n[1]) * h
    zs = lo[2] + np.arange(n[2]) * h
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    F = knight_sdf(X, Y, Z)
    # close the bottom (inside the base collar) so the mesh is watertight
    F[:, :, 0] = np.abs(F[:, :, 0]) + h
    F[0] = np.abs(F[0]) + h
    F[-1] = np.abs(F[-1]) + h
    return surface_nets(F, lo, h)


if __name__ == "__main__":
    v, q = build()
    print(len(v), len(q))
