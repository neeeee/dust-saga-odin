"""Replicate the game's armor transfer math on the Fornid cuisses.

Game formula (chara_avatar_update_armor): for each armor bone b,
  boneMatrices[b] = pose_char[remap(b)] * inv(bind_armor[b])
vertex deform (column-vector): v' = boneMatrices[bone(v)] * v  (weighted)

pose_char = sampled glTF animation clip "..._0001" (idle) at t=0, globalized
down the node hierarchy exactly like raylib's BuildPoseFromParentJoints +
animation sampling.
"""
import sys, json, struct
sys.path.insert(0, 'tools_dev')
from glb_inspect import load_glb, node_matrix, mmul, quat_to_mat

def read_accessor(gltf, bc, idx):
    acc = gltf["accessors"][idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    n = acc["count"]
    comp = acc["componentType"]
    typ = acc["type"]
    ncomp = {"SCALAR":1, "VEC2":2, "VEC3":3, "VEC4":4, "MAT4":16}[typ]
    fmt = {5120:"b", 5121:"B", 5122:"h", 5123:"H", 5125:"I", 5126:"f"}[comp]
    out = []
    if typ == "SCALAR":
        return [struct.unpack_from("<"+fmt*n, bc, off+i*n*struct.calcsize(fmt))[0] for i in range(n)]
    for i in range(n):
        out.append(struct.unpack_from("<"+fmt*ncomp, bc, off + i*ncomp*struct.calcsize(fmt)))
    return out

def find_idle_clip(gltf):
    for ai, a in enumerate(gltf["animations"]):
        if a.get("name", "").endswith("_0001"):
            return ai, a
    return 0, gltf["animations"][0]

def sample_clip(gltf, bc, anim, t, node_count):
    # local transforms per node at time t (nearest keyframe ~ frame 0 use t=0)
    local = [node_matrix(gltf["nodes"][i]) for i in range(node_count)]
    for ch in anim["channels"]:
        samp = anim["samplers"][ch["sampler"]]
        times = read_accessor(gltf, bc, samp["input"])
        # find bracket
        ti = 0
        for k in range(len(times)-1):
            if times[k] <= t <= times[k+1]:
                ti = k
                break
        else:
            ti = len(times)-1 if times[-1] <= t else 0
        vals = read_accessor(gltf, bc, samp["output"])
        v0, v1 = vals[ti], vals[min(ti+1, len(vals)-1)]
        t0, t1 = times[ti], times[min(ti+1, len(times)-1)]
        a = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
        path = ch["target"]["path"]
        ni = ch["target"]["node"]
        node = gltf["nodes"][ni]
        if path == "translation":
            if "translation" not in node: continue
            v = [v0[j] + (v1[j]-v0[j])*a for j in range(3)]
            M = node_matrix(node)
            for j in range(3): M[j][3] = v[j]
            local[ni] = M
        elif path == "rotation":
            if "rotation" not in node: continue
            q = [v0[j] + (v1[j]-v0[j])*a for j in range(4)]
            nq = (sum(x*x for x in q)) ** 0.5
            q = [x/nq for x in q]
            M = node_matrix(node)
            R = quat_to_mat(q)
            s = [ (M[0][0]**2+M[1][0]**2+M[2][0]**2)**0.5,
                  (M[0][1]**2+M[1][1]**2+M[2][1]**2)**0.5,
                  (M[0][2]**2+M[1][2]**2+M[2][2]**2)**0.5 ]
            M = [[R[0][0]*s[0], R[0][1]*s[1], R[0][2]*s[2], M[0][3]],
                 [R[1][0]*s[0], R[1][1]*s[1], R[1][2]*s[2], M[1][3]],
                 [R[2][0]*s[0], R[2][1]*s[1], R[2][2]*s[2], M[2][3]],
                 [0,0,0,1]]
            local[ni] = M
        elif path == "scale":
            if "scale" not in node: continue
            v = [v0[j] + (v1[j]-v0[j])*a for j in range(3)]
            M = node_matrix(node)
            R = [[M[r][c] / ( [ (M[0][0]**2+M[1][0]**2+M[2][0]**2)**0.5,
                                (M[0][1]**2+M[1][1]**2+M[2][1]**2)**0.5,
                                (M[0][2]**2+M[1][2]**2+M[2][2]**2)**0.5 ][c] ) for c in range(3)] for r in range(3)]
            local[ni] = [[R[0][0]*v[0], R[0][1]*v[1], R[0][2]*v[2], M[0][3]],
                         [R[1][0]*v[0], R[1][1]*v[1], R[1][2]*v[2], M[1][3]],
                         [R[2][0]*v[0], R[2][1]*v[1], R[2][2]*v[2], M[2][3]],
                         [0,0,0,1]]
    return local

def globals_from_local(gltf, local):
    nodes = gltf["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    g = {}
    def visit(i, M):
        g[i] = mmul(M, local[i])
        for c in nodes[i].get("children", []):
            visit(c, g[i])
    for r in [i for i in range(len(nodes)) if i not in parent]:
        visit(r, [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]])
    return g

def inv(M):
    A = [row[:] + [1.0 if i==j else 0.0 for j in range(4)] for i,row in enumerate(M)]
    for c in range(4):
        p = max(range(c,4), key=lambda r: abs(A[r][c]))
        A[c], A[p] = A[p], A[c]
        pv = A[c][c]
        A[c] = [v/pv for v in A[c]]
        for r in range(4):
            if r != c and A[r][c]:
                f = A[r][c]
                A[r] = [a - f*b for a,b in zip(A[r], A[c])]
    return [row[4:] for row in A]

def deform(path_char, path_armor, t=0.0):
    char, cb = load_glb(path_char)
    armor, ab = load_glb(path_armor)
    ai, anim = find_idle_clip(char)
    print(f"idle clip {ai}: {anim.get('name')}")
    local = sample_clip(char, cb, anim, t, len(char["nodes"]))
    cg = globals_from_local(char, local)     # char global pose
    bg = globals_from_local(armor, [node_matrix(n) for n in armor["nodes"]])  # armor bind globals

    # remap: armor joint name -> char node index (game maps by bone name)
    char_by_name = {char["nodes"][i].get("name",""): i for i in range(len(char["nodes"]))}
    skin = armor["skins"][0]
    joints = skin["joints"]
    bone_matrices = []
    unmapped = []
    for ji, node_i in enumerate(joints):
        name = armor["nodes"][node_i].get("name","")
        ci = char_by_name.get(name, -1)
        if ci < 0:
            # walk up like the game
            j = node_i
            par = {c:p for p,n in enumerate(armor["nodes"]) for c in n.get("children",[])}
            while j in par:
                j = par[j]
                nm = armor["nodes"][j].get("name","")
                if nm in char_by_name:
                    ci = char_by_name[nm]
                    break
        if ci < 0:
            unmapped.append(name)
            bone_matrices.append([[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]])
        else:
            bone_matrices.append(mmul(cg[ci], inv(bg[node_i])))
    if unmapped:
        print("unmapped joints:", unmapped[:10])

    # deform the armor mesh (first prim)
    mesh = armor["meshes"][0]
    prim = mesh["primitives"][0]
    pos = read_accessor(armor, ab, prim["attributes"]["POSITION"])
    joints_acc = read_accessor(armor, ab, prim["attributes"]["JOINTS_0"])
    weights = read_accessor(armor, ab, prim["attributes"]["WEIGHTS_0"])
    lo = [1e9]*3; hi = [-1e9]*3
    for vi, p in enumerate(pos):
        out = [0.0, 0.0, 0.0]
        for k in range(4):
            w = weights[vi][k]
            if w == 0: continue
            bm = bone_matrices[joints_acc[vi][k]]
            for r in range(3):
                out[r] += w * sum(bm[r][c]*p[c] for c in range(3)) + w*bm[r][3]
        for r in range(3):
            lo[r] = min(lo[r], out[r]); hi[r] = max(hi[r], out[r])
    print(f"deformed bounds min=({lo[0]:+.3f},{lo[1]:+.3f},{lo[2]:+.3f}) max=({hi[0]:+.3f},{hi[1]:+.3f},{hi[2]:+.3f})")
    print(f"bind    bounds min=({min(p[0] for p in pos):+.3f},{min(p[1] for p in pos):+.3f},{min(p[2] for p in pos):+.3f}) max=({max(p[0] for p in pos):+.3f},{max(p[1] for p in pos):+.3f},{max(p[2] for p in pos):+.3f})")
    # char foot bone positions under idle pose
    for nm in ("Bip01 L Foot", "Bip01 R Foot", "Bip01 L Calf", "Bip01 L Thigh"):
        for i, n in enumerate(char["nodes"]):
            if n.get("name") == nm:
                t3 = [cg[i][r][3] for r in range(3)]
                print(f"char pose {nm}: ({t3[0]:+.4f},{t3[1]:+.4f},{t3[2]:+.4f})")

if __name__ == "__main__":
    deform('src/client/assets/chara/chara_012.glb', 'src/client/assets/item/EM_013203_03_012.glb')
