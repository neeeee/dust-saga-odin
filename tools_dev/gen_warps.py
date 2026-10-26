"""One-shot: add teleporters/playerSpawn/ground/fog to the Pandora map JSONs
in src/client/assets/maps and generate the ZONE_DATABASE block for zones.ts.

Zone ids are the numeric Pandora map ids (the client loads
assets/maps/<zone_id>.json, and the converted definition files are named that
way). Warp topology is a design choice (no warp table ships with the original
data); adjust NB below and re-run to re-lay pads. Pads sit 10% inside the GLB
footprint edge in the slot direction (0=S 1=E 2=N 3=W), y=0 (walkable floor).
"""
import json, math

MAPS = r"C:\Users\desktop\dust-saga-odin\src\client\assets\maps"
OUT = r"C:\Users\desktop\dust-saga-odin\tools_dev\_new_zones_block.txt"

# id -> (area code, GLB footprint (minx, maxx, minz, maxz)) from glb bounds dump
Z = {
    '99999999': ('F01',    (-976, 976, -832, 868)),
    '1001001': ('T01_01', (-216, 193, -155, 259)),
    '1001002': ('T01_02', (-168, 208, -173, 237)),
    '1001003': ('T01_03', (-171, 201, -222, 188)),
    '1001004': ('T01_04', (-170, 171, -217, 169)),
    '1002001': ('T02',    (-133, 145, -145, 147)),
    '1003001': ('T03',    (-216, 216, -240, 265)),
    '1004001': ('T04',    (-312, 142, -228, 229)),
    '2002001': ('F02_01', (-612, 505, -1228, 1225)),
    '2002002': ('F02_02', (-792, 793, -1117, 1117)),
    '2002003': ('F02_03', (-684, 829, -945, 1117)),
    '2003001': ('F03_01', (-1044, 1045, -531, 563)),
    '2003002': ('F03_02', (-1116, 1120, -612, 721)),
    '2003003': ('F03_03', (-849, 793, -900, 961)),
    '2004001': ('F04_01', (-612, 721, -1260, 1369)),
    '2004002': ('F04_02', (-882, 847, -1420, 1423)),
    '2004003': ('F04_03', (-1044, 1081, -1044, 1009)),
    '2005000': ('F05',    (-1056, 1057, -925, 937)),
    '2006001': ('F06_01', (-1620, 1621, -1188, 1297)),
    '2007001': ('F07_01', (-1062, 1135, -846, 919)),
    '3001001': ('D01_01', (-312, 289, -504, 505)),
    '3001002': ('D01_02', (-168, 241, -264, 337)),
    '3001003': ('D01_03', (-480, 481, -480, 481)),
    '3001004': ('D01_04', (-480, 481, -288, 217)),
    '3001005': ('D01_05', (-528, 505, -288, 361)),
    '3001006': ('D01_06', (-384, 313, -288, 217)),
    '9001001': ('E01_01', (-424, 135, -343, 415)),
}

# neighbors: zone -> ordered list of (target, slot)
NB = {
    '99999999': [('astir_central', 0), ('1001001', 1), ('1004001', 2)],
    '1001001': [('99999999', 0), ('1001002', 1), ('9001001', 2)],
    '1004001': [('99999999', 0)],
    '1001002': [('1001001', 0), ('1001003', 1)],
    '1001003': [('1001002', 0), ('1001004', 1)],
    '1001004': [('1001003', 0), ('2002001', 1)],
    '9001001': [('1001001', 0)],
    '2002001': [('1001004', 0), ('2002002', 1)],
    '2002002': [('2002001', 0), ('2002003', 1), ('3001001', 2)],
    '2002003': [('2002002', 0), ('2003001', 1)],
    '3001001': [('2002002', 0), ('3001002', 1)],
    '3001002': [('3001001', 0), ('3001003', 1)],
    '3001003': [('3001002', 0), ('3001004', 1)],
    '3001004': [('3001003', 0), ('3001005', 1)],
    '3001005': [('3001004', 0), ('3001006', 1)],
    '3001006': [('3001005', 0)],
    '2003001': [('2002003', 0), ('2003002', 1)],
    '2003002': [('2003001', 0), ('2003003', 1), ('1003001', 2)],
    '1003001': [('2003002', 0)],
    '2003003': [('2003002', 0), ('2004001', 1)],
    '2004001': [('2003003', 0), ('2004002', 1)],
    '2004002': [('2004001', 0), ('2004003', 1)],
    '2004003': [('2004002', 0), ('2005000', 1)],
    '2005000': [('2004003', 0), ('2006001', 1)],
    '2006001': [('2005000', 0), ('2007001', 1)],
    '2007001': [('2006001', 0), ('1002001', 1)],
    '1002001': [('2007001', 0)],
}

TOWN_IDS = {'1001001', '1001002', '1001003', '1001004', '1002001', '1003001', '1004001'}
DUNGEON_IDS = {f'300100{i}' for i in range(1, 7)} | {'9001001'}
LEVEL = {
    '99999999': (1, 10), '2002001': (10, 20), '2002002': (10, 20), '2002003': (10, 20),
    '2003001': (20, 30), '2003002': (20, 30), '2003003': (20, 30),
    '2004001': (30, 40), '2004002': (30, 40), '2004003': (30, 40),
    '2005000': (40, 50), '2006001': (45, 55), '2007001': (50, 60),
    '9001001': (20, 40),
}
for i in range(1, 7):
    LEVEL[f'300100{i}'] = (25, 45)
for t in TOWN_IDS:
    LEVEL[t] = (1, 60)


def ztype(zid):
    if zid in TOWN_IDS:
        return 'SAFE'
    if zid in DUNGEON_IDS:
        return 'DUNGEON'
    return 'PVE'


def pad_pos(zid, slot):
    minx, maxx, minz, maxz = Z[zid][1]
    cx, cz = (minx + maxx) / 2, (minz + maxz) / 2
    dx, dz = maxx - minx, maxz - minz
    if slot == 0:
        return round(cx), round(minz + 0.10 * dz)    # south
    if slot == 1:
        return round(maxx - 0.10 * dx), round(cz)    # east
    if slot == 2:
        return round(cx), round(maxz - 0.10 * dz)    # north
    return round(minx + 0.10 * dx), round(cz)        # west


def label_of(zid):
    return 'Astir Central Plaza' if zid == 'astir_central' else Z[zid][0]


def teleporters(zid):
    tps = []
    for target, slot in NB[zid]:
        x, zz = pad_pos(zid, slot)
        tps.append({
            "id": "tp_to_" + target,
            "position": {"x": x, "y": 0, "z": zz},
            "targetZone": target,
            "targetSpawn": "tp_from_" + zid,
            "radius": 3,
            "label": "To " + label_of(target),
        })
    return tps


def env_from(d, zid):
    """fog color/density + ground tint + plane size (fallback rendering)."""
    fog = d.get('environment', {}).get('fog', {})
    c = fog.get('color', [0.7, 0.8, 0.9])
    far = fog.get('far') or 30000.0
    density = max(0.0008, min(0.02, 2.0 / far))
    if not fog.get('enable', 1):
        density = 0.0008
    fogc = {'r': round(c[0], 4), 'g': round(c[1], 4), 'b': round(c[2], 4)}
    gnd = {'r': round(c[0] * 0.75, 4), 'g': round(c[1] * 0.75, 4), 'b': round(c[2] * 0.75, 4)}
    minx, maxx, minz, maxz = Z[zid][1]
    size = int(math.ceil(max(abs(minx), abs(maxx), abs(minz), abs(maxz)) * 2 / 20.0) * 20)
    return fogc, round(density, 5), gnd, size


def add_client_keys(d, zid):
    fogc, density, gnd, size = env_from(d, zid)
    minx, maxx, minz, maxz = Z[zid][1]
    d['name'] = Z[zid][0]
    d['ground'] = {'color': gnd, 'size': size, 'heightVariation': 0}
    d['fog'] = {'color': fogc, 'density': density}
    d['playerSpawn'] = {'x': round((minx + maxx) / 2), 'y': 0, 'z': round((minz + maxz) / 2)}
    d['teleporters'] = teleporters(zid)


CLIENT_KEYS = ('name', 'ground', 'fog', 'playerSpawn', 'teleporters')

# ---- patch the 26 generated numeric JSONs --------------------------------
patched = []
for zid in Z:
    if zid == '2005000':
        continue  # stub, written below
    path = MAPS + '\\' + zid + '.json'
    with open(path, encoding='utf-8') as f:
        d = json.load(f)
    add_client_keys(d, zid)  # overwrites in place; safe to re-run
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(d, f, indent=1, ensure_ascii=True)
    patched.append(zid)
print('patched numeric JSONs:', len(patched))

# ---- F05 stub (whole-field bake has no map.csv row) -----------------------
stub = {
    "format": "pandora-map-json/1",
    "map_id": 2005000,
    "note": ("Hand-written zone for the whole-field terrain bake map_F05.glb. "
             "F05.vra has no settings/map.csv row (only F05_01..F05_05 are "
             "registered), so id 2005000 is provisional - replace it if an "
             "official id or a vra2json conversion for F05 shows up."),
    "source": {"chip": "F05/F05.vra", "obj": "", "fx": "", "occluder": "",
               "sky": "", "collision": "", "far_view": "", "firework": "",
               "terrain_glb": "map_F05.glb"},
}
add_client_keys(stub, '2005000')
with open(MAPS + '\\2005000.json', 'w', encoding='utf-8', newline='\n') as f:
    json.dump(stub, f, indent=1, ensure_ascii=True)
print('wrote 2005000.json stub')

# ---- astir_central bridge warp -------------------------------------------
with open(MAPS + '\\astir_central.json', encoding='utf-8') as f:
    astir = json.load(f)
if 'tp_to_99999999' not in [t['id'] for t in astir['teleporters']]:
    astir['teleporters'].append({
        "id": "tp_to_99999999",
        "position": {"x": 60, "y": 0, "z": 60},
        "targetZone": "99999999",
        "targetSpawn": "tp_from_astir_central",
        "radius": 2,
        "label": "Frontier - F01",
    })
with open(MAPS + '\\astir_central.json', 'w', encoding='utf-8', newline='\n') as f:
    json.dump(astir, f, indent=1, ensure_ascii=True)
print('astir_central.json: added tp_to_99999999')

# ---- generate ZONE_DATABASE block ---------------------------------------
def cvec(c):
    return "{ r: %s, g: %s, b: %s }" % (c['r'], c['g'], c['b'])


TYPEDESC = {'SAFE': 'town', 'PVE': 'field', 'DUNGEON': 'dungeon'}
lines = []
for zid in sorted(Z, key=int):
    code = Z[zid][0]
    with open(MAPS + '\\' + zid + '.json', encoding='utf-8') as f:
        d = json.load(f)
    fogc, density, gnd, size = env_from(d, zid)
    zt = ztype(zid)
    lo, hi = LEVEL[zid]
    conns = sorted({t for t, _ in NB[zid]}, key=lambda x: int(x) if x.isdigit() else 10 ** 9)
    conn_s = ', '.join("'" + c + "'" for c in conns)
    minx, maxx, minz, maxz = Z[zid][1]
    glb = (d.get('source', {}).get('terrain_glb', '').split('/')[-1]) or ('map_' + code + '.glb')
    extra = ",\n    musicTrack: 'town'" if zt == 'SAFE' else ""
    lines.append(
        "  '%s': {\n"
        "    id: '%s',\n"
        "    name: '%s',\n"
        "    description: 'Pandora Saga area %s (%s; terrain %s).',\n"
        "    type: ZoneType.%s,\n"
        "    levelRange: [%d, %d],\n"
        "    groundColor: %s,\n"
        "    fogColor: %s,\n"
        "    fogDensity: %s,\n"
        "    size: %d,\n"
        "    playerSpawn: { x: %d, y: 0, z: %d },\n"
        "    connections: [%s],\n"
        "    spawns: [],\n"
        "    environmentObjects: [],\n"
        "    isPvpEnabled: false%s\n"
        "  }" % (zid, zid, code, code, TYPEDESC[zt], glb, zt, lo, hi,
                cvec(gnd), cvec(fogc), density, size,
                round((minx + maxx) / 2), round((minz + maxz) / 2),
                conn_s, extra)
    )

with open(OUT, 'w', newline='\n') as f:
    f.write(',\n'.join(lines) + ',\n')
print('wrote _new_zones_block.txt:', len(lines), 'zones')
