"""Dump glTF/GLB skeleton + mesh placement info for the chara armor debugging.

No numpy — plain python 4x4 math, small files only.
Usage: python glb_inspect.py file1.glb [file2.glb ...] [pattern,pattern,...]
"""
import json, struct, sys

def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not glb"
    off = 12
    js = None
    bin_chunk = None
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off+clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            bin_chunk = chunk
        off += clen
    return js, bin_chunk

def mmul(A, B):
    # column-major glTF semantics: A @ B in math terms, stored row-lists here
    return [[sum(A[i][k]*B[k][j] for k in range(4)) for j in range(4)] for i in range(4)]

def quat_to_mat(q):
    x, y, z, w = q
    return [
        [1-2*(y*y+z*z), 2*(x*y-z*w),   2*(x*z+y*w)],
        [2*(x*y+z*w),   1-2*(x*x+z*z), 2*(y*z-x*w)],
        [2*(x*z-y*w),   2*(y*z+x*w),   1-2*(x*x+y*y)],
    ]

def node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]  # column-major 16
        return [[m[0], m[4], m[8],  m[12]],
                [m[1], m[5], m[9],  m[13]],
                [m[2], m[6], m[10], m[14]],
                [m[3], m[7], m[11], m[15]]]
    t = node.get("translation", [0,0,0])
    r = node.get("rotation", [0,0,0,1])
    s = node.get("scale", [1,1,1])
    R = quat_to_mat(r)
    return [[R[0][0]*s[0], R[0][1]*s[1], R[0][2]*s[2], t[0]],
            [R[1][0]*s[0], R[1][1]*s[1], R[1][2]*s[2], t[1]],
            [R[2][0]*s[0], R[2][1]*s[1], R[2][2]*s[2], t[2]],
            [0, 0, 0, 1]]

def global_mats(gltf):
    nodes = gltf["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    g = {}
    def visit(i, M):
        g[i] = mmul(M, node_matrix(nodes[i]))
        for c in nodes[i].get("children", []):
            visit(c, g[i])
    roots = [i for i in range(len(nodes)) if i not in parent]
    for r in roots:
        visit(r, [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]])
    return g

def inspect(path, patterns, dump_nodes=False):
    gltf, bin_chunk = load_glb(path)
    print(f"== {path}")
    nodes = gltf.get("nodes", [])
    print(f"  nodes={len(nodes)} meshes={len(gltf.get('meshes',[]))} skins={len(gltf.get('skins',[]))} anims={len(gltf.get('animations',[]))}")
    g = global_mats(gltf)
    for i, n in enumerate(nodes):
        name = n.get("name", "")
        if patterns and not any(p.lower() in name.lower() for p in patterns):
            continue
        M = g[i]
        t = (M[0][3], M[1][3], M[2][3])
        sx = (M[0][0]**2 + M[1][0]**2 + M[2][0]**2) ** 0.5
        print(f"  node {i:3d} '{name}' parent={next((p for p,nn in enumerate(nodes) if i in nn.get('children',[])), -1)} "
              f"global t=({t[0]:+.4f},{t[1]:+.4f},{t[2]:+.4f}) sx={sx:.4f}")
    for si, skin in enumerate(gltf.get("skins", [])):
        print(f"  skin {si}: joints={len(skin['joints'])} skeleton_root={skin.get('skeleton')}")
    for mi, mesh in enumerate(gltf.get("meshes", [])):
        for pi, prim in enumerate(mesh["primitives"]):
            pos_i = prim["attributes"]["POSITION"]
            mn = gltf["accessors"][pos_i].get("min")
            mx = gltf["accessors"][pos_i].get("max")
            owners = [f"{i}:'{nodes[i].get('name','?')}'" for i in range(len(nodes)) if nodes[i].get("mesh") == mi]
            skinned = "JOINTS_0" in prim["attributes"]
            print(f"  mesh {mi} ({'skinned' if skinned else 'rigid'}) nodes=[{', '.join(owners)}] "
                  f"min=({mn[0]:+.3f},{mn[1]:+.3f},{mn[2]:+.3f}) max=({mx[0]:+.3f},{mx[1]:+.3f},{mx[2]:+.3f})")
    if dump_nodes:
        for i, n in enumerate(nodes):
            print(f"    {i:3d} '{n.get('name','?')}'")

if __name__ == "__main__":
    args = sys.argv[1:]
    patterns = []
    paths = []
    for a in args:
        if a.lower().endswith(".glb"):
            paths.append(a)
        else:
            patterns = a.split(",")
    dump = "--all" in patterns
    patterns = [p for p in patterns if p != "--all"]
    for p in paths:
        inspect(p, patterns, dump)
