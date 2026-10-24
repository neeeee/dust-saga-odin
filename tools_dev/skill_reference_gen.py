"""Generate skill_reference.md — a decoded, single-header-row rendering of
src/client/assets/skill.csv (UTF-16LE, two-row Japanese headers).

Column map verified against data:
  0-6   id, name, behavior, target side, MP, cast delay (s), recovery (s)
  7     range
  8     learnable-by-growth flag
  9     level requirement
  10-37 class learn flags (28 classes, 4 families x 7 tiers)
  38-65 auto-attack class flags (CN-support duplicate of 38-51; first 14 only)
  66-69 potential-skill acquisition reference + requirements
  70-75 proficiency / skill-line requirements (75 = line name, e.g. MELEE_DEFENSE)
  76-90 weapon usability flags (BareHAND,1H_SWORD,2H_SWORD,LANCE,POLE_ARM,
        1H_AXE,2H_AXE,1H_BLUNT,2H_BLUNT,1H_TRUMP,2H_TRUMP,BOW,CROSSBOW,WAND,STAFF)
        — verified: col87 BOW-only skills, col85 = daggers (1H_TRUMP),
        col78 = 2H swords, col91 set by Blocking
  91    shield-required flag
  92    cast marker (#キャスト)
  93-93 interruptible / usable-sheathed / alignment / chant-type region (raw)
  97-113 buff-effect / user-buff / log / icon / display plumbing (raw)
  114-115 unlock skill ids
  116-117 description lines
"""
import csv, re

SRC = 'src/client/assets/skill.csv'
OUT = 'skill_reference.md'

CLASSES = ['Warrior','Gladiator','Knight','Juggernaut','Dragoon','General','Paladin',
           'Scout','Archer','Agent','Vigilance','Predator','Assassin','Disturbance',
           'Acolyte','Priest','Ascetic','Cleric','Enchanter','Monk','Exorcist',
           'Mage','Wizard','Darklore','Warlock','Conjurer','Jester','Calamity']
WEAPONS = ['BareHAND','1H_SWORD','2H_SWORD','LANCE','POLE_ARM','1H_AXE','2H_AXE',
           '1H_BLUNT','2H_BLUNT','1H_TRUMP','2H_TRUMP','BOW','CROSSBOW','WAND','STAFF']
W_COL = 76   # first weapon flag column
C_COL = 10   # first class flag column

with open(SRC, encoding='utf-16') as f:
    rows = list(csv.reader(f))

data = [r for r in rows[11:] if r and r[0].strip().isdigit() and len(r[0].strip()) >= 9]

def cell(r, i):
    return r[i].strip() if i < len(r) else ''

def decode_flags(r, start, names):
    on = [n for k, n in enumerate(names) if cell(r, start + k) not in ('', '0')]
    if not on or len(on) == len(names):
        return 'ALL' if len(on) == len(names) else 'any'
    return ', '.join(on)

# unlock ids -> names (second pass over the table itself)
id_to_name = {r[0].strip(): cell(r, 1) for r in data}

out = []
w = out.append
w('# Skill reference (decoded `src/client/assets/skill.csv`)')
w('')
w('Generated from the shipped UTF-16 table; regenerate with')
w('`python tools_dev/skill_reference_gen.py` after changing the CSV.')
w('')
w('## Column map (the two header rows, translated)')
w('')
w('| Cols | Meaning | Notes |')
w('|---|---|---|')
w('| 0–6 | SerialID · skill name · behavior · target side · MP cost · cast delay (s) · recovery (s) | behavior values: ENEMY, MYSELF, PARTY_SINGLE, PARTY_ALL, ALLY, TOGGLE, TOGGLE_RADIATION, RADIATION, PASSIVE, BREATH, BOLT, GBOLT, SPHBOLT, SPHERE, CIRCLE, CLAN, POINT; "recovery" (ベンチタイム) is the post-use cooldown |')
w('| 7 | Range | 2500 seen on ranged skills — engine units, melee = 0 |')
w('| 8 | Learnable by growth (1/0) | |')
w('| 9 | Level requirement | |')
w('| 10–37 | Class learn flags (28) | Warrior/Gladiator/Knight/Juggernaut/Dragoon/General/Paladin · Scout/Archer/Agent/Vigilance/Predator/Assassin/Disturbance · Acolyte/Priest/Ascetic/Cleric/Enchanter/Monk/Exorcist · Mage/Wizard/Darklore/Warlock/Conjurer/Jester/Calamity |')
w('| 38–65 | Auto-attack class flags (CN-support) | same 28-class order; only the first 14 (melee+scout families) ever set |')
w('| 66–69 | Potential-skill acquisition reference + required potential values | |')
w('| 70–75 | Skill-line / proficiency requirement | col 75 holds the line name (e.g. `MELEE_DEFENSE`) |')
w('| 76–90 | Weapon usability flags | BareHAND, 1H_SWORD, 2H_SWORD, LANCE, POLE_ARM, 1H_AXE, 2H_AXE, 1H_BLUNT, 2H_BLUNT, 1H_TRUMP (daggers), 2H_TRUMP, BOW, CROSSBOW, WAND, STAFF — none set = any weapon |')
w('| 91 | Shield required flag | set by Blocking and the shield skills |')
w('| 92 | Cast marker (#キャスト) | values 1/2, client anim hint |')
w('| 93–96 | Interruptible · usable-while-sheathed · alignment · chant type | raw codes (e.g. `MELEE_NONE`) |')
w('| 97–113 | Buff effect IDs ×5 · user buff IDs ×5 · effect log ID · caster log ID · icon ID · display flag · BEFORE_CAST · shield-move motion · fx-swap · special log | plumbing, mostly empty |')
w('| 114–115 | Unlocks skill IDs | resolved to names in the table |')
w('| 116–117 | Description | |')
w('')
w('## Skills (%d rows, file order)' % len(data))
w('')
w('| ID | Name | Behavior | Target | MP | Cast | Recovery | Range | Lv | Classes | Weapons | Shield | Unlocks | Description |')
w('|---|---|---|---|---:|---:|---:|---:|---:|---|---|:-:|---|---|')

for r in data:
    unlocks = ' / '.join(id_to_name.get(cell(r, c), cell(r, c)) for c in (114, 115) if cell(r, c))
    desc = cell(r, 116) or cell(r, 117)
    desc = desc.replace('|', '\\|')
    w('| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |' % (
        cell(r, 0), cell(r, 1), cell(r, 2), cell(r, 3), cell(r, 4), cell(r, 5),
        cell(r, 6), cell(r, 7), cell(r, 9),
        decode_flags(r, C_COL, CLASSES),
        decode_flags(r, W_COL, WEAPONS),
        '✓' if cell(r, 91) not in ('', '0') else '',
        unlocks, desc,
    ))

with open(OUT, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out) + '\n')
print(f"wrote {OUT}: {len(data)} skills, {len(out)} lines")
