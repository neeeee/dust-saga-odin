"""Re-pick spawns for previously-registered zones whose spawn point fails
the wall_probe check (no heightfield cover, or walk=false at the point):
2003002, 2004002, 2005000, 2006001, 2007001, 2004001, 2001003, 3001006.

Same footprint method as fix_zone_spawns.py: spawn near the wall-cloud
centroid with clearance from move-blocking walls.
"""

import json
import math
import os
import re
import struct
from collections import deque

ROOT = r'C:/Users/laptop/dust-saga-odin/src'
TS_PATH = ROOT + '/shared/src/constants/zones.ts'
MAPS = ROOT + '/client/assets/maps'
ZW = json.load(open(ROOT + '/server/data/zone_walls.json', encoding='utf-8'))

IDS = ['2005000', '2004001', '2001003', '3001006']
# 2003002/2004002/2006001/2007001 have no client map JSON (procedural fallback
# zones — flat plane centered on the origin), so their spawns are fine as-is.


def glb_bounds(path):
    with open(path, 'rb') as f:
        data = f.read(64 * 1024 * 1024)
    assert struct.unpack_from('<I', data, 0)[0] == 0x46546C67
    clen, _ = struct.unpack_from('<II', data, 12)
    gj = json.loads(data[20:20 + clen])
    boxes = [a for a in gj.get('accessors', [])
             if 'min' in a and 'max' in a and len(a['min']) == 3]
    if not boxes:
        return None
    return (min(a['min'][0] for a in boxes), max(a['max'][0] for a in boxes),
            min(a['min'][2] for a in boxes), max(a['max'][2] for a in boxes))


def spawn_from_glb(map_id):
    d = json.load(open(os.path.join(MAPS, map_id + '.json'), encoding='utf-8'))
    glb = d.get('source', {}).get('terrain_glb', '')
    name = glb.replace('\\', '/').split('/')[-1]
    path = os.path.join(MAPS, name)
    if not os.path.exists(path):
        alt = os.path.join(MAPS, name.replace('.glb', '_ground.glb'))
        path = alt if os.path.exists(alt) else None
    if not path:
        return 0.0, 0.0
    b = glb_bounds(path)
    return round((b[0] + b[1]) / 2, 1), round((b[2] + b[3]) / 2, 1)


def spawn_from_walls(segs):
    move = [s for s in segs if (s[6] if len(s) > 6 else 1) != 0]
    xs = [v for s in segs for v in (s[0], s[2])]
    zs = [v for s in segs for v in (s[1], s[3])]
    minx, maxx, minz, maxz = min(xs), max(xs), min(zs), max(zs)
    cx, cz = (minx + maxx) / 2, (minz + maxz) / 2

    cell = 10.0
    cols = int((maxx - minx) / cell) + 3
    rows = int((maxz - minz) / cell) + 3
    blocked = bytearray(cols * rows)
    for s in move:
        c0 = max(0, int((min(s[0], s[2]) - minx) / cell))
        c1 = min(cols - 1, int((max(s[0], s[2]) - minx) / cell) + 1)
        r0 = max(0, int((min(s[1], s[3]) - minz) / cell))
        r1 = min(rows - 1, int((max(s[1], s[3]) - minz) / cell) + 1)
        for r in range(r0, r1 + 1):
            base = r * cols
            for c in range(c0, c1 + 1):
                blocked[base + c] = 1

    ii = [0] * ((cols + 1) * (rows + 1))
    for r in range(rows):
        rowsum = 0
        for c in range(cols):
            rowsum += blocked[r * cols + c]
            ii[(r + 1) * cols + c + 1] = ii[r * cols + c + 1] + rowsum

    INF = 1 << 30
    dist = [INF] * (cols * rows)
    q = deque()
    for i, b in enumerate(blocked):
        if b:
            dist[i] = 0
            q.append(i)
    while q:
        i = q.popleft()
        r, c = divmod(i, cols)
        d2 = dist[i] + 1
        for nr, nc in ((r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)):
            if 0 <= nr < rows and 0 <= nc < cols and dist[nr * cols + nc] > d2:
                dist[nr * cols + nc] = d2
                q.append(nr * cols + nc)

    def window_sum(r, c, rad=12):
        r0, r1 = max(0, r - rad), min(rows - 1, r + rad)
        c0, c1 = max(0, c - rad), min(cols - 1, c + rad)
        return ii[(r1 + 1) * cols + c1 + 1] - ii[r0 * cols + c1 + 1] \
            - ii[(r1 + 1) * cols + c0] + ii[r0 * cols + c0]

    best, best_score = None, -1e18
    for r in range(rows):
        for c in range(cols):
            d = dist[r * cols + c]
            if d < 4:
                continue
            px, pz = minx + c * cell, minz + r * cell
            score = (min(d, 12) * 10
                     + min(window_sum(r, c), 400) * 0.5
                     - math.hypot(px - cx, pz - cz))
            if score > best_score:
                best_score = score
                best = (px, pz)
    return round(best[0], 1), round(best[1], 1)


ts = open(TS_PATH, encoding='utf-8').read()
for map_id in IDS:
    if map_id in ZW['zones']:
        x, z = spawn_from_walls(ZW['lists'][ZW['zones'][map_id]])
        src = 'walls'
    else:
        x, z = spawn_from_glb(map_id)
        src = 'GLB bounds'
    pat = re.compile(r"(^  '%s': \{(?:.*\n)*?)    playerSpawn: \{ x: [-0-9.]+, y: 0, z: [-0-9.]+ \},"
                     % re.escape(map_id), re.M)
    m = pat.search(ts)
    assert m, 'entry not found: ' + map_id
    ts = ts[:m.start()] + m.group(1) + \
        '    playerSpawn: { x: %s, y: 0, z: %s },' % (x, z) + ts[m.end():]
    print('%s -> spawn=(%s, %s) [%s]' % (map_id, x, z, src))
open(TS_PATH, 'w', encoding='utf-8', newline='\n').write(ts)
print('zones.ts updated')
