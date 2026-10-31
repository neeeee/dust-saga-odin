"""One-off: register every client map JSON that ZONE_DATABASE lacks.

The Odin client ships assets/maps/<zoneId>.json for 66 zones, but
shared/src/constants/zones.ts only defined a subset, so `/warp <id>`
answered "Unknown zone" for the rest. This script derives a
ZoneDefinition per missing id from its map JSON:

- name        : Pandora chip basename (F05_01); deduped with the id tail
- description : follows the existing "Pandora Saga area ..." wording
- type        : T* -> SAFE town, D*/E* -> DUNGEON, else PVE field
- fog colors  : environment.fog.color (groundColor mirrors it; inert metadata)
- size        : grid span (nums * chip_size) so quest-cell math stays in-range
- playerSpawn : most wall-distant point on a coarse spiral around the origin,
                from server/data/zone_walls.json (origin when no wall data)

Entries are inserted before 'performance_test' in ZONE_DATABASE.
"""

import json
import math
import os
import re

ROOT = r'C:/Users/laptop/dust-saga-odin/src'
MAPS = os.path.join(ROOT, 'client/assets/maps')
TS_PATH = os.path.join(ROOT, 'shared/src/constants/zones.ts')
ZW_PATH = os.path.join(ROOT, 'server/data/zone_walls.json')

ts = open(TS_PATH, encoding='utf-8').read()
db_keys = set(re.findall(r"^\s{2}'([a-z0-9_]+)':\s*\{", ts, re.M))
used_names = set(re.findall(r"^\s{4}name: '([^']+)'", ts, re.M))

zw = json.load(open(ZW_PATH, encoding='utf-8'))

LEVEL = {'F01': (1, 10), 'F02': (10, 20), 'F03': (20, 30), 'F04': (30, 40),
         'F05': (40, 50), 'D01': (25, 45), 'E01': (20, 40),
         'T01': (1, 60), 'T02': (1, 60), 'T03': (1, 60), 'T04': (1, 60)}

SLASH = chr(92)


def dist_pt_seg(px, pz, seg):
    x1, z1, x2, z2 = seg[0], seg[1], seg[2], seg[3]
    dx, dz = x2 - x1, z2 - z1
    l2 = dx * dx + dz * dz
    if l2 == 0:
        return math.hypot(px - x1, pz - z1)
    t = max(0.0, min(1.0, ((px - x1) * dx + (pz - z1) * dz) / l2))
    return math.hypot(px - (x1 + t * dx), pz - (z1 + t * dz))


def open_spawn(map_id, chip_size):
    """Spiral out from the origin, keep the point furthest from any wall."""
    if map_id not in zw['zones']:
        return {'x': 0, 'y': 0, 'z': 0}
    segs = zw['lists'][zw['zones'][map_id]]
    best, best_score = (0.0, 0.0), -1.0
    for ring in range(0, 11):
        r = ring * chip_size
        offs = [(0, 0)] if ring == 0 else \
            [(r * math.cos(a * math.pi / 4), r * math.sin(a * math.pi / 4)) for a in range(8)]
        for ox, oz in offs:
            score = min(dist_pt_seg(ox, oz, s) for s in segs)
            if score > best_score + 1e-9:
                best, best_score = (ox, oz), score
        if best_score >= chip_size * 0.75:
            break
    return {'x': round(best[0], 1), 'y': 0, 'z': round(best[1], 1)}


missing = []
for f in sorted(os.listdir(MAPS)):
    if re.fullmatch(r'[0-9]+[.]json', f) and f[:-5] not in db_keys:
        missing.append(f[:-5])

entries = []
for map_id in sorted(missing):
    d = json.load(open(os.path.join(MAPS, map_id + '.json'), encoding='utf-8'))
    src = d.get('source', {})
    chip = os.path.splitext(os.path.basename((src.get('chip') or '').replace(SLASH, '/')))[0]
    area = chip.split('_')[0] if chip else 'F01'
    env = d.get('environment', {})
    fog = env.get('fog', {}).get('color') or [0.7, 0.8, 0.9]
    grid = d.get('grid', {})
    size = int(grid.get('nums', 0) * grid.get('chip_size', 0)) or \
        int(d.get('minimap', {}).get('world_size', [2000])[0]) or 2000

    kind = 'dungeon' if area[0] in 'DE' else ('town' if area[0] == 'T' else 'field')
    ztype = {'dungeon': 'ZoneType.DUNGEON', 'town': 'ZoneType.SAFE', 'field': 'ZoneType.PVE'}[kind]
    lvl = LEVEL.get(area, (1, 99))

    name = chip or map_id
    if name in used_names:
        name = '%s_%s' % (name, map_id[-3:])
    used_names.add(name)

    spawn = open_spawn(map_id, int(grid.get('chip_size', 2400) or 2400))

    def c(v):
        return '{ r: %s, g: %s, b: %s }' % (round(v[0], 4), round(v[1], 4), round(v[2], 4))

    entries.append("""  '%s': {
    id: '%s',
    name: '%s',
    description: 'Pandora Saga area %s (%s; terrain map_%s.glb).',
    type: %s,
    levelRange: [%d, %d],
    groundColor: %s,
    fogColor: %s,
    fogDensity: 0.0008,
    size: %d,
    playerSpawn: { x: %s, y: 0, z: %s },
    connections: [],
    spawns: [],
    environmentObjects: [],
    isPvpEnabled: false
  }""" % (map_id, map_id, name, name, kind, name, ztype, lvl[0], lvl[1],
          c(fog), c(fog), size, spawn['x'], spawn['z']))

block = ',\n'.join(entries) + ',\n\n'
anchor = "  'performance_test': {"
assert anchor in ts and ts.count(anchor) == 1
ts = ts.replace(anchor, block + anchor)
open(TS_PATH, 'w', encoding='utf-8', newline='\n').write(ts)
print('inserted %d entries' % len(entries))
for m in re.findall(r"^  '([a-z0-9_]+)': \{|^    name: '([^']+)'", block, re.M):
    print('  ' + (m[0] or '  -> ' + m[1]))
