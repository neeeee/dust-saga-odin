"""Offline mirror of the client's terrain heightfield build (terrain_collision.odin).

Conservative rasterization: a cell is covered when the triangle's XZ
projection comes within a half-cell-diagonal of the cell center; the height
sampled is the plane height at the closest point on the triangle.
"""
import json, math, struct, sys, time
import numpy as np


def parse_glb(path):
    data = open(path, 'rb').read()
    jlen, _jtype = struct.unpack_from('<II', data, 12)
    j = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen, _btype = struct.unpack_from('<II', data, off)
    return j, data[off + 8:off + 8 + blen]


CT = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_accessor(j, b, idx):
    a = j['accessors'][idx]
    bv = j['bufferViews'][a['bufferView']]
    n = a['count']
    nc = NCOMP[a['type']]
    f, _sz = CT[a['componentType']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return np.frombuffer(b, dtype=np.dtype(f), count=n * nc, offset=start).reshape(n, nc)


def node_matrix(n):
    if 'matrix' in n:
        return np.array(n['matrix'], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    if 'translation' in n:
        m[:3, 3] += n['translation']
    if 'rotation' in n:
        x, y, z, w = n['rotation']
        R = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        m[:3, :3] = R @ m[:3, :3]
    if 'scale' in n:
        m[:3, :3] = m[:3, :3] @ np.diag(n['scale'])
    return m


def world_tris(path):
    j, b = parse_glb(path)
    tris = []

    def walk(ni, parent):
        n = j['nodes'][ni]
        M = parent @ node_matrix(n)
        if 'mesh' in n:
            for p in j['meshes'][n['mesh']]['primitives']:
                pos = read_accessor(j, b, p['attributes']['POSITION'])
                w = (np.c_[pos, np.ones(len(pos))] @ M.T)[:, :3]
                if 'indices' in p:
                    idx = read_accessor(j, b, p['indices']).flatten()
                else:
                    idx = np.arange(len(pos))
                for t in range(0, len(idx) - 2, 3):
                    tris.append((w[idx[t]], w[idx[t + 1]], w[idx[t + 2]]))
        for c in n.get('children', []):
            walk(c, M)

    ident = np.eye(4)
    for r in j['scenes'][j.get('scene', 0)]['nodes']:
        walk(r, ident)
    return np.array(tris, dtype=np.float64)


TERRAIN_MAX_SLOPE = 1.15
HF_MAX_CELLS = 8_000_000
# Skip triangles steeper than ~70 deg: never walkable, and their plane
# extrapolation within the half-cell reach would poison neighbor heights.
NY_MIN = 0.34


def build_heightfield(a):
    a = a[np.isfinite(a).all(axis=(1, 2))]
    min_x = a[:, :, 0].min(); max_x = a[:, :, 0].max()
    min_z = a[:, :, 2].min(); max_z = a[:, :, 2].max()
    min_y = a[:, :, 1].min(); max_y = a[:, :, 1].max()
    ex, ez = max_x - min_x, max_z - min_z
    cell = 1.0
    while (ex / cell) * (ez / cell) > HF_MAX_CELLS:
        cell += 1
    cols = int(math.ceil(ex / cell)) + 1
    rows = int(math.ceil(ez / cell)) + 1
    heights = np.zeros(cols * rows)
    valid = np.zeros(cols * rows, bool)
    ox, oz = min_x, min_z
    half_diag2 = 0.5 * cell * cell

    for t in range(len(a)):
        A, B, C = a[t]
        ax, ay, az = A; bx, by, bz = B; cx, cy, cz = C
        n1 = (B - A)
        n2 = (C - A)
        nn = np.cross(n1, n2)
        ln = math.sqrt(nn[0] * nn[0] + nn[1] * nn[1] + nn[2] * nn[2])
        if ln < 1e-12 or abs(nn[1]) / ln < NY_MIN:
            continue
        cmin = max(0, int(math.floor((min(ax, bx, cx) - ox) / cell)) - 1)
        cmax = min(cols - 1, int(math.ceil((max(ax, bx, cx) - ox) / cell)) + 1)
        rmin = max(0, int(math.floor((min(az, bz, cz) - oz) / cell)) - 1)
        rmax = min(rows - 1, int(math.ceil((max(az, bz, cz) - oz) / cell)) + 1)
        if cmin > cmax or rmin > rmax:
            continue
        px = ox + (np.arange(cmin, cmax + 1) + 0.5) * cell
        pz = oz + (np.arange(rmin, rmax + 1) + 0.5) * cell
        PX, PZ = np.meshgrid(px, pz)

        abx, abz = bx - ax, bz - az
        acx, acz = cx - ax, cz - az
        APX, APZ = PX - ax, PZ - az
        d1 = abx * APX + abz * APZ
        d2 = acx * APX + acz * APZ
        BPX, BPZ = PX - bx, PZ - bz
        d3 = abx * BPX + abz * BPZ
        d4 = acx * BPX + acz * BPZ
        CPX, CPZ = PX - cx, PZ - cz
        d5 = abx * CPX + abz * CPZ
        d6 = acx * CPX + acz * CPZ
        va = d3 * d6 - d5 * d4
        vb = d5 * d2 - d1 * d6
        vc = d1 * d4 - d3 * d2

        # Interior barycentrics (used only in the interior region).
        tot = va + vb + vc
        safe = np.where(tot == 0, 1.0, tot)
        v_in = vb / safe
        w_in = vc / safe

        qx = np.full(PX.shape, ax); qz = np.full(PX.shape, az)
        m_ab = (d1 <= 0) & (d2 <= 0)
        m_bc = (~m_ab) & (d3 >= 0) & (d4 <= d3)
        qx[m_bc] = bx; qz[m_bc] = bz
        m_ac = (~m_ab) & (~m_bc) & (d6 >= 0) & (d5 <= d6)
        qx[m_ac] = cx; qz[m_ac] = cz
        m_ab_e = (~m_ab) & (~m_bc) & (~m_ac) & (vc <= 0) & (d1 >= 0) & (d3 <= 0)
        den = np.where((d1 - d3) == 0, 1.0, (d1 - d3))
        v4 = d1 / den
        qx[m_ab_e] = (ax + abx * v4)[m_ab_e]; qz[m_ab_e] = (az + abz * v4)[m_ab_e]
        m_ac_e = (~m_ab) & (~m_bc) & (~m_ac) & (~m_ab_e) & (vb <= 0) & (d2 >= 0) & (d6 <= 0)
        den = np.where((d2 - d6) == 0, 1.0, (d2 - d6))
        w5 = d2 / den
        qx[m_ac_e] = (ax + acx * w5)[m_ac_e]; qz[m_ac_e] = (az + acz * w5)[m_ac_e]
        m_bc_e = (~m_ab) & (~m_bc) & (~m_ac) & (~m_ab_e) & (~m_ac_e) & (va <= 0) & ((d4 - d3) >= 0) & ((d5 - d6) >= 0)
        den = np.where(((d4 - d3) + (d5 - d6)) == 0, 1.0, ((d4 - d3) + (d5 - d6)))
        w6 = (d4 - d3) / den
        qx[m_bc_e] = (bx + (cx - bx) * w6)[m_bc_e]; qz[m_bc_e] = (bz + (cz - bz) * w6)[m_bc_e]
        m_int = (~m_ab) & (~m_bc) & (~m_ac) & (~m_ab_e) & (~m_ac_e) & (~m_bc_e)
        qx[m_int] = (ax + abx * v_in + acx * w_in)[m_int]
        qz[m_int] = (az + abz * v_in + acz * w_in)[m_int]

        # Plane height at the closest point (plane equation via normal —
        # barycentric here would need the 2D (x,z) coordinates, not heights).
        denom_p = (by - cy) * (ax - cx) + (cx - bx) * (az - cz)
        if abs(denom_p) < 1e-9:
            continue
        nx = (by - ay) * (cz - az) - (bz - az) * (cy - ay)
        ny = (bz - az) * (cx - ax) - (bx - ax) * (cz - az)
        nz = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
        dd = -(nx * ax + ny * ay + nz * az)
        Hp = (-dd - nx * qx - nz * qz) / ny
        dist2 = (PX - qx) ** 2 + (PZ - qz) ** 2
        inside = dist2 <= half_diag2

        for ri in range(len(pz)):
            row = inside[ri]
            if not row.any():
                continue
            base = (rmin + ri) * cols
            seg_h = heights[base + cmin:base + cmax + 1]
            seg_v = valid[base + cmin:base + cmax + 1]
            upd = row & (~seg_v | (Hp[ri] > seg_h))
            seg_h[upd] = Hp[ri][upd]
            seg_v[upd] = True
            heights[base + cmin:base + cmax + 1] = seg_h
            valid[base + cmin:base + cmax + 1] = seg_v

    # pinhole fill x2
    for _ in range(2):
        V2 = valid.reshape(rows, cols); H2 = heights.reshape(rows, cols)
        cnt = np.zeros((rows, cols)); ssum = np.zeros((rows, cols))
        for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            Vsh = np.roll(V2, (dr, dc), axis=(0, 1)); Hsh = np.roll(H2, (dr, dc), axis=(0, 1))
            if dr == -1: Vsh[-1, :] = False
            if dr == 1: Vsh[0, :] = False
            if dc == -1: Vsh[:, -1] = False
            if dc == 1: Vsh[:, 0] = False
            cnt += Vsh; ssum += np.where(Vsh, Hsh, 0)
        plug = (~V2) & (cnt >= 3)
        H2[plug] = ssum[plug] / cnt[plug]
        V2[plug] = True
        if not plug.any():
            break

    # slope
    V2 = valid.reshape(rows, cols); H2 = heights.reshape(rows, cols)

    def sh(arr, dr, dc):
        out = np.roll(arr, (dr, dc), axis=(0, 1))
        srcv = np.roll(V2, (dr, dc), axis=(0, 1))
        m = np.zeros_like(V2)
        if dr == -1: m[-1, :] = True
        if dr == 1: m[0, :] = True
        if dc == -1: m[:, -1] = True
        if dc == 1: m[:, 0] = True
        out[m] = 0.0; srcv[m] = False
        return out, srcv

    hl, okl = sh(H2, 0, -1); hr_, okr = sh(H2, 0, 1)
    hu, oku = sh(H2, -1, 0); hd, okd = sh(H2, 1, 0)
    dhx = np.where(okl & okr, (hr_ - hl) / (2 * cell), np.where(okr, (hr_ - H2) / cell, np.where(okl, (H2 - hl) / cell, 0.0)))
    dhz = np.where(oku & okd, (hd - hu) / (2 * cell), np.where(okd, (hd - H2) / cell, np.where(oku, (H2 - hu) / cell, 0.0)))
    walk = V2 & (np.sqrt(dhx ** 2 + dhz ** 2) <= TERRAIN_MAX_SLOPE)

    # erode 1
    ok = walk.copy()
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            Wsh = np.roll(walk, (dr, dc), axis=(0, 1))
            m = np.zeros_like(V2)
            if dr == -1: m[-1, :] = True
            if dr == 1: m[0, :] = True
            if dc == -1: m[:, -1] = True
            if dc == 1: m[:, 0] = True
            Wsh[m] = False
            ok &= Wsh
    return dict(ox=ox, oz=oz, cell=cell, cols=cols, rows=rows, min_y=min_y, max_y=max_y,
                heights=H2, valid=V2, walk=ok)


def sample_h(hf, x, z):
    fx = (x - hf['ox']) / hf['cell'] - 0.5
    fz = (z - hf['oz']) / hf['cell'] - 0.5
    c0 = math.floor(fx); r0 = math.floor(fz)
    tx = fx - c0; tz = fz - r0
    cols = hf['cols']; rows = hf['rows']; H = hf['heights']; V = hf['valid']

    def gv(cc, rr):
        if 0 <= cc < cols and 0 <= rr < rows and V[rr, cc]:
            return H[rr, cc], True
        return 0, False

    h00, ok00 = gv(c0, r0); h10, ok10 = gv(c0 + 1, r0)
    h01, ok01 = gv(c0, r0 + 1); h11, ok11 = gv(c0 + 1, r0 + 1)
    if ok00 and ok10 and ok01 and ok11:
        hA = h00 + (h10 - h00) * tx
        hB = h01 + (h11 - h01) * tx
        return hA + (hB - hA) * tz, True
    return None, False


if __name__ == '__main__':
    for name, spawn in [('map_T01_01.glb', (-12, 52)), ('map_F01_02.glb', (0, 0)), ('map_F06_01.glb', (0, 0))]:
        t0 = time.time()
        a = world_tris(name)
        hf = build_heightfield(a)
        V, W = hf['valid'], hf['walk']
        print(f"{name}: tris={len(a)} grid={hf['cols']}x{hf['rows']} cell={hf['cell']} "
              f"y=[{hf['min_y']:.1f}..{hf['max_y']:.1f}] build={time.time() - t0:.0f}s")
        print(f"  coverage={V.mean() * 100:.1f}%  walkable={W.sum()} ({W.sum() / max(V.sum(), 1) * 100:.1f}% of covered)")
        sx, sz = spawn
        h, ok = sample_h(hf, sx, sz)
        c = int((sx - hf['ox']) / hf['cell']); r = int((sz - hf['oz']) / hf['cell'])
        cw = W[r, c] if (0 <= c < hf['cols'] and 0 <= r < hf['rows']) else 'oob'
        print(f"  spawn({sx},{sz}) -> h={'None' if h is None else round(h, 2)} ok={ok} cellwalk={cw}")
