"""Fix playerSpawn/size for the zones registered by gen_missing_zones.py.

v1 of that script misread the world scale: the map JSONs claim centimeter
units, but the exported terrain/wall data is ~100x smaller (F05_01's
footprint spans only ~±700 around the origin). Spawning "furthest from
walls" therefore landed kilometers off-map in the void.

This script rewrites playerSpawn and size for every generated entry
(7-digit ids with size > 10000) from the zone's real footprint:

- size        : ceil(max x/z extent of the wall cloud) + 10% margin
- playerSpawn : rasterize move-blocking walls into a fine grid, BFS distance
                transform for clearance, then take the eligible cell
                (clearance >= 3) closest to the footprint centroid with the
                most wall detail nearby (density => definitely on-terrain)
- zones without wall data (2005104): footprint read from the terrain GLB's
                POSITION accessors; spawn = footprint center
"""

import json
import math
import os
import re
import struct
from collections import deque

ROOT = r'C:/Users/laptop/dust-saga-odin/src'
MAPS = os.path.join(ROOT, 'client/assets/maps')
TS_PATH = os.path.join(ROOT, 'shared/src/constants/zones.ts')
ZW_PATH = os.path.join(ROOT, 'server/data/zone_walls.json')

ts = open(TS_PATH, encoding='utf-8').read()

targets = []
for m in re.finditer(r"^  '(\d{7})': \{\n(?:    .*\n)*?    size: (\d+),\n", ts, re.M):
    if int(m.group(2)) > 10000:
        targets.append((m.group(1), int(m.group(2))))
assert targets, 'no generated entries found'
print('rewriting %d entries: %s' % (len(targets), ', '.join(i for i, _ in targets)))

zw = json.load(open(ZW_PATH, encoding='utf-8'))


def glb_bounds(path):
    """x/z footprint + y range of a GLB from its POSITION accessor min/max."""
    with open(path, 'rb') as f:
        data = f.read(64 * 1024 * 1024)
    magic, ver, length = struct.unpack_from('<III', data, 0)
    assert magic == 0x46546C67
    clen, ctype = struct.unpack_from('<II', data, 12)
    gj = json.loads(data[20:20 + clen])
    boxes = [a for a in gj.get('accessors', [])
             if 'min' in a and 'max' in a and len(a['min']) == 3]
    if not boxes:
        return None
    return (min(a['min'][0] for a in boxes), max(a['max'][0] for a in boxes),
            min(a['min'][2] for a in boxes), max(a['max'][2] for a in boxes))


def spawn_from_walls(segs):
    move = [s for s in segs if (s[6] if len(s) > 6 else 1) != 0]
    xs = [v for s in segs for v in (s[0], s[2])]
    zs = [v for s in segs for v in (s[1], s[3])]
    minx, maxx, minz, maxz = min(xs), max(xs), min(zs), max(zs)
    cx, cz = (minx + maxx) / 2, (minz + maxz) / 2
    size = int(math.ceil(max(maxx - minx, maxz - minz) * 1.1 / 20) * 20)

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
    # BFS distance transform (in cells) from every blocked cell
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

    # integral image over the blocked raster: window sum in O(1) per cell
    def window_sum(r, c, rad=12):
        r0, r1 = max(0, r - rad), min(rows - 1, r + rad)
        c0, c1 = max(0, c - rad), min(cols - 1, c + rad)
        return ii[(r1 + 1) * cols + c1 + 1] - ii[r0 * cols + c1 + 1] \
            - ii[(r1 + 1) * cols + c0] + ii[r0 * cols + c0]

    ii = [0] * ((cols + 1) * (rows + 1))
    for r in range(rows):
        rowsum = 0
        for c in range(cols):
            rowsum += blocked[r * cols + c]
            ii[(r + 1) * cols + c + 1] = ii[r * cols + c + 1] + rowsum

    best, best_score = None, -1e18
    for r in range(rows):
        for c in range(cols):
            d = dist[r * cols + c]
            if d < 4:  # < ~4 cells (~3.5m) from any move-blocking wall
                continue
            px, pz = minx + c * cell, minz + r * cell
            score = (min(d, 12) * 10
                     + min(window_sum(r, c), 400) * 0.5
                     - math.hypot(px - cx, pz - cz))
            if score > best_score:
                best_score = score
                best = (px, pz, d)
    return {'x': round(best[0], 1), 'y': 0, 'z': round(best[1], 1)}, size, best[2]


def spawn_from_glb(map_id):
    d = json.load(open(os.path.join(MAPS, map_id + '.json'), encoding='utf-8'))
    glb = d.get('source', {}).get('terrain_glb', '')
    name = glb.replace('\\', '/').split('/')[-1]
    path = os.path.join(MAPS, name)
    if not os.path.exists(path):
        # some zones lack the visual bake but ship the terrain-only sidecar
        alt = os.path.join(MAPS, name.replace('.glb', '_ground.glb'))
        path = alt if os.path.exists(alt) else None
    if not path:
        return {'x': 0, 'y': 0, 'z': 0}, 2000
    b = glb_bounds(path)
    if not b:
        return {'x': 0, 'y': 0, 'z': 0}, 2000
    minx, maxx, minz, maxz = b
    size = int(math.ceil(max(maxx - minx, maxz - minz) * 1.1 / 20) * 20)
    return {'x': round((minx + maxx) / 2, 1), 'y': 0,
            'z': round((minz + maxz) / 2, 1)}, size


for map_id, old_size in targets:
    if map_id in zw['zones']:
        spawn, size, clear = spawn_from_walls(zw['lists'][zw['zones'][map_id]])
        note = 'clearance=%.1f cells' % clear
    else:
        spawn, size = spawn_from_glb(map_id)
        note = 'from GLB bounds'
    block_re = re.compile(
        r"(^  '%s': \{\n(?:    .*\n)*?)    size: \d+,\n((?:    .*\n)*?)    playerSpawn: \{ x: [-0-9.]+, y: 0, z: [-0-9.]+ \},\n"
        % re.escape(map_id), re.M)
    m = block_re.search(ts)
    assert m, 'entry not found for %s' % map_id
    ts = ts[:m.start()] + m.group(1) + ('    size: %d,\n' % size) + \
        m.group(2) + ('    playerSpawn: { x: %s, y: 0, z: %s },\n' % (spawn['x'], spawn['z'])) + \
        ts[m.end():]
    print('%s  spawn=(%s, %s) size=%d  [%s]' % (map_id, spawn['x'], spawn['z'], size, note))

open(TS_PATH, 'w', encoding='utf-8', newline='\n').write(ts)
print('zones.ts updated')
