package systems

import "core:math"

// ════════════════════════════════════════════════════════════════════════════
// game_data.odin — Odin port of the TS client's
//   src/constants/{races,classes,skills,classSkills,jobSkillValues,debuffs}.ts
//
// DESIGN SCAFFOLD. The type schema is final; sample data is illustrative and
// will be replaced by the full Odin-source tables in B3–B5. Each load-bearing
// decision is tagged [Dn] inline.
//
// ── DECISIONS ───────────────────────────────────────────────────────────────
//  D1  Content (jobs / races / skills / items) is identified by a human-
//      memorable string ("warrior", "Slice", "human") in source; a generic
//      Registry (see registry.odin) interns each name to a distinct u16 ID at
//      load, so runtime lookups are O(1) and the four overlapping job schemes
//      of the TS client collapse to ONE. The distinct ID types (Job_Id,
//      Race_Id, Skill_Id) can't be mixed at compile time. Closed sets
//      (Base_Class, Sub_Category, Stat, Weapon_Type, effect kinds) stay as
//      enums.
//  D2  Buffs and debuffs are ONE model: an Effect_Spec union (tagged by type)
//      wrapped in Apply_Effect that carries a Polarity (.BUFF/.DEBUFF).
//      Scalar buffs (move/attack speed, block/crit/debuff resist) fold into
//      Stat_Mod targeting a Stat.
//  D3  Skills hold an ordered list of Outcome (tagged union) — cleanly models
//      combo skills that deal damage AND apply an effect (Stun, Flaming Arrow).
//  D4  reqPoints (int threshold) / cross-tree prereqs / reqLevel unify into one
//      Skill_Req union (distinct u8 types disambiguate Level vs Points).
//  D5  Scattered gating flags (weapon types, shield, block-only, self-only,
//      stationary, mounted, consumable) collapse into Skill_Requirements.
//  D6  statTieredValues (two-level SPI × proficiency gating) is modelled
//      explicitly as Tiered_Mod + a resolver.
//  D7  Boolean toggles (blocking_stance, prevent_spell_cast, curse, …) live in
//      a Status_Flag_Set bitfield via the .Special variant.
//  D8  Dash / Sprint / Spurt stay three distinct Skill_Defs (combo chain).
// ════════════════════════════════════════════════════════════════════════════


// ── closed-set enums ──────────────────────────────────────────────────────

Base_Class :: enum u8 { WARRIOR, SCOUT, ACOLYTE, MAGE }

// The 20 proficiency axes — also the base-class skill-tree leaves. A closed
// set, so it stays an enum (its member names ARE the memorable names).
Sub_Category :: enum u8 {
	SLASH, THRUST, CLEAVE, BASH, DEFEND,
	SHOT, ALCHEMY, ASSASSINATION, TRAP, DODGE,
	GRACE, BLESSING, EXORCISM, HYMN,
	ELEMENTAL, INVOCATION, DARKNESS, CONFUSION,
	RACIAL, HORSEMANSHIP,
}
SUB_CATEGORY_COUNT :: len(Sub_Category)

// Parent skill categories — each sub-category belongs to one. Category-level
// skills (Slash, Bash, Backstep, etc.) check the SUM of all sub-categories in
// their parent category, not a single sub-category.
Skill_Category :: enum u8 { MELEE, TECHNIQUE, PRAYER, MAGIC, SPECIAL }

sub_category_to_category :: proc "contextless" (sc: Sub_Category) -> Skill_Category {
	#partial switch sc {
	case .SLASH, .THRUST, .CLEAVE, .BASH, .DEFEND:
		return .MELEE
	case .SHOT, .ALCHEMY, .ASSASSINATION, .TRAP, .DODGE:
		return .TECHNIQUE
	case .GRACE, .BLESSING, .EXORCISM, .HYMN:
		return .PRAYER
	case .ELEMENTAL, .INVOCATION, .DARKNESS, .CONFUSION:
		return .MAGIC
	case .RACIAL, .HORSEMANSHIP:
		return .SPECIAL
	case:
		return .MELEE
	}
}

// Sum of allocated skill points across all sub-categories in a parent category.
category_total :: proc(p: ^Local_Player, cat: Skill_Category) -> i32 {
	total: i32
	for sc in Sub_Category {
		if sub_category_to_category(sc) == cat {
			total += p.allocated_skill_points[sc]
		}
	}
	return total
}

// Anything a Stat_Mod can target: the 6 primary attributes + derived combat
// quantities + defensive chances. Widened so scalar buffs share one variant.
Stat :: enum u8 {
	STA, STR, AGI, DEX, SPI, INT,
	ATTACK, DEFENSE, SPEED, MAGIC_ATTACK,
	ACCURACY, DODGE, CRIT_CHANCE, CRIT_RESIST,
	CAST_SPEED, ATTACK_SPEED, MOVE_SPEED,
	BLOCK_CHANCE, DEBUFF_RESIST, MAGIC_RESIST,
	MAX_HEALTH, MAX_MANA,
}
STAT_COUNT :: len(Stat)

Weapon_Type :: enum u8 {
	SWORD_1H, SWORD_2H, AXE, AXE_2H, BLUNT, BLUNT_2H,
	SPEAR, DAGGER, KNUCKLES, BOW, CROSSBOW, WAND,
}
WEAPON_TYPE_COUNT :: len(Weapon_Type)
MAX_REQ_WEAPONS :: 8 // most skills allow ≤3 weapons; generous cap

// The 6 primary attributes a player allocates stat points into (the TS
// StatPoints: STA/STR/AGI/DEX/SPI/INT). Separate from the wider Stat enum
// (which also covers derived quantities) so allocations index a tight array.
Attr :: enum u8 {
	STA,
	STR,
	AGI,
	DEX,
	SPI,
	INT,
}
ATTR_COUNT :: len(Attr)

attr_from_name :: proc(s: string) -> (Attr, bool) {
	switch s {
	case "STA": return .STA, true
	case "STR": return .STR, true
	case "AGI": return .AGI, true
	case "DEX": return .DEX, true
	case "SPI": return .SPI, true
	case "INT": return .INT, true
	case:      return .STA, false
	}
}

attr_name :: proc(a: Attr) -> string {
	switch a {
	case .STA: return "STA"
	case .STR: return "STR"
	case .AGI: return "AGI"
	case .DEX: return "DEX"
	case .SPI: return "SPI"
	case .INT: return "INT"
	}
	return "STA"
}

// Sub-category name (TS "Slash", "Thrust", …) ↔ Sub_Category enum.
sub_category_from_name :: proc(s: string) -> (Sub_Category, bool) {
	switch s {
	case "Slash":         return .SLASH, true
	case "Thrust":        return .THRUST, true
	case "Cleave":        return .CLEAVE, true
	case "Bash":          return .BASH, true
	case "Defend":        return .DEFEND, true
	case "Shot":          return .SHOT, true
	case "Alchemy":       return .ALCHEMY, true
	case "Assassination": return .ASSASSINATION, true
	case "Trap":          return .TRAP, true
	case "Dodge":         return .DODGE, true
	case "Grace":         return .GRACE, true
	case "Blessing":      return .BLESSING, true
	case "Exorcism":      return .EXORCISM, true
	case "Hymn":          return .HYMN, true
	case "Elemental":     return .ELEMENTAL, true
	case "Invocation":    return .INVOCATION, true
	case "Darkness":      return .DARKNESS, true
	case "Confusion":     return .CONFUSION, true
	case "Racial":        return .RACIAL, true
	case "Horsemanship":  return .HORSEMANSHIP, true
	case:                return .SLASH, false
	}
}

sub_category_name :: proc(sc: Sub_Category) -> string {
	switch sc {
	case .SLASH:         return "Slash"
	case .THRUST:        return "Thrust"
	case .CLEAVE:        return "Cleave"
	case .BASH:          return "Bash"
	case .DEFEND:        return "Defend"
	case .SHOT:          return "Shot"
	case .ALCHEMY:       return "Alchemy"
	case .ASSASSINATION: return "Assassination"
	case .TRAP:          return "Trap"
	case .DODGE:         return "Dodge"
	case .GRACE:         return "Grace"
	case .BLESSING:      return "Blessing"
	case .EXORCISM:      return "Exorcism"
	case .HYMN:          return "Hymn"
	case .ELEMENTAL:     return "Elemental"
	case .INVOCATION:    return "Invocation"
	case .DARKNESS:      return "Darkness"
	case .CONFUSION:     return "Confusion"
	case .RACIAL:        return "Racial"
	case .HORSEMANSHIP:  return "Horsemanship"
	}
	return "Slash"
}


// ── content ID types (distinct u16, interned by their registries) ──────────

Race_Id  :: distinct u16
Job_Id   :: distinct u16
Skill_Id :: distinct u16

INVALID_RACE_ID  :: Race_Id(INVALID_INDEX)
INVALID_JOB_ID   :: Job_Id(INVALID_INDEX)
INVALID_SKILL_ID :: Skill_Id(INVALID_INDEX)


// ── damage / heal / targeting ──────────────────────────────────────────────

Damage_Type :: enum u8 { PHYSICAL, MAGICAL }

Damage_Sub_Type :: enum u8 {
	SLASH, THRUST, CLEAVE, BASH, RANGED, // physical
	FIRE, ICE, LIGHTNING, DARK, HOLY, POISON, ARCANE, // magical
}

Damage_Params :: struct {
	damage_type:      Damage_Type, // default .PHYSICAL
	sub_type:         Damage_Sub_Type,
	base_power:       f32, // 0 ⇒ no damage component
	base_hits:        u8, // default 1; Slice=2, Triple Stab=3, Quadruple Stab=4
	elemental_power:  f32, // hybrid phys+elemental (Flaming Arrow)
	ignore_armor:     bool,
	bonus_vs_low_def: bool, // Subvert
	recoil_on_miss:   f32, // Fatal Scratch / Dragon Tail
	knockback:        u8,
}

Heal_Scope :: enum u8 { SINGLE, PARTY, SELF }

Heal_Params :: struct {
	scope:       Heal_Scope, // default .SINGLE
	base_amount: f32,
	stat_mult:   [Stat]f32, // e.g. stat_mult[.SPI]=0.3, [.INT]=0.6
	prof_stat:   Sub_Category, // default .GRACE
	prof_mult:   f32,
}

AOE_Mode :: enum u8 {
	NONE,             // single-target
	SELF_CENTERED,    // centered on caster
	TARGET_CENTERED,  // centered on target
	GROUND_TARGETED,  // player picks a ground point
	FRONTAL_CONE,     // Heave / Assault
}

Targeting :: struct {
	aoe_mode:          AOE_Mode, // default .NONE
	aoe_radius:        f32, // 0 ⇒ single target
	range:             f32, // 0 ⇒ melee reach
	pulse_count:       u8, // Arrow Rain = 3
	pulse_interval_ms: u32,
}

Skill_Requirements :: struct { // [D5]
	weapon:       [MAX_REQ_WEAPONS]Weapon_Type, // allowed weapons; empty ⇒ any
	weapon_count: u8,
	shield:       bool, // shieldRequired
	block_only:   bool, // usable only while blocking
	self_only:    bool, // selfBuffOnly
	stationary:   bool, // caster must be stationary
	mounted:      bool, // requires mount
	consumable:   string, // item id consumed ("trap", "holy_water")
	consume_qty:  u8,
}


// ── unified buff/debuff model [D2] ─────────────────────────────────────────

Polarity :: enum u8 { BUFF, DEBUFF }

DOT_Element :: enum u8 { POISON, SEVERE_POISON, BLEED, MP_DRAIN, BURN }

CC_Kind :: enum u8 {
	STUN, TRIP, FREEZE, SLEEP, SILENCE, KNOCKDOWN, KNOCKBACK, ROOT,
}

Stat_Mod :: struct {
	stat:  Stat,
	delta: f32, // additive (def +5); 0 ⇒ none
	mult:  f32, // multiplicative; 1.0 ⇒ none (attackSpeed 1.3, critResist 0.7)
}

DOT_Effect :: struct {
	element:         DOT_Element,
	potency:         f32,
	hp_percent:      f32,
	tick_interval_s: f32,
	spi_base:        f32,
	spi_max:         f32,
	spi_cap:         f32,
	mp_drain:        f32,
}

CC_Effect :: struct {
	kind:           CC_Kind,
	duration_s:     f32,
	knockback_dist: f32,
	chance:         f32, // 1.0 ⇒ guaranteed
}

Hot_Effect :: struct {
	base:      f32,
	spi_scale: f32,
	prof_stat: Sub_Category, // default .GRACE
}

Mp_Regen_Effect :: struct {
	base:       f32,
	stat_scale: Stat, // default .SPI
	prof_stat:  Sub_Category, // default .EXORCISM
	prof_mult:  f32,
}

Invisible_Effect :: struct { stationary_only: bool, mp_cost_per_sec: f32 }
Weapon_Aura :: struct { element: DOT_Element, formula: string }

// Two-level tiering: gate on a primary Stat, then on a proficiency. [D6]
Tier_Prof_Tier :: struct { prof_threshold: f32, deltas: [Stat]f32 }
Tier_Stat_Tier :: struct { stat_threshold: f32, prof_tiers: [8]Tier_Prof_Tier }
Tiered_Mod :: struct {
	stat:      Stat, // default .SPI
	prof_stat: Sub_Category, // default .BLESSING
	tiers:     [6]Tier_Stat_Tier,
}

Status_Flags :: enum u8 { // [D7]
	BLOCKING_STANCE,
	DEFENSIVE_MARCH,
	SHIELD_CHARGE,
	EXTRA_HIT,
	CONSUMABLE_ON_ATTACK,
	PREVENT_FIELD_SPELLS,
	PREVENT_SPELL_CAST,
	PREVENT_RESURRECT,
	PREVENT_EQUIPMENT,
	REVEAL_INVISIBLE,
	DISABLE_PHYSICAL_ATTACKS,
	ATTACK_HALVED,
	CURSE,
	REMOVE_RESIST_BUFFS,
	DAMAGE_REDIRECT,
	DISPEL,
}
Status_Flag_Set :: bit_set[Status_Flags]

Effect_Spec :: union {
	Stat_Mod,
	DOT_Effect,
	CC_Effect,
	Hot_Effect,
	Mp_Regen_Effect,
	Invisible_Effect,
	Weapon_Aura,
	Tiered_Mod,
	Status_Flag_Set,
}

// Wrapper: where the effect goes + how long + the body. Carried by Outcome.
Apply_Effect :: struct {
	polarity:   Polarity, // default .BUFF
	to_self:    bool, // true ⇒ caster, false ⇒ target
	duration_s: f32, // 0 ⇒ instant
	effect:     Effect_Spec,
}


// ── outcomes [D3] ──────────────────────────────────────────────────────────

Create_Item :: struct {
	item_id:  string,
	quantity: u8, // default 1
	consume:  [4]struct { item_id: string, quantity: u8 }, // ingredients
}

Outcome :: union {
	Damage_Params,
	Heal_Params,
	Apply_Effect, // buff/debuff (to_self inside the wrapper)
	Create_Item,
	// Summon / Teleport / Swap(Mana|Soul) / Sacrifice_Heal / Provoke — add as needed
}

MAX_SKILL_OUTCOMES :: 4

// Default radius (world units) for ground-targeted skills whose own radius is
// unset — matches the TS DEFAULT_AOE_RADIUS.
DEFAULT_AOE_RADIUS :: 5.0

Skill_Kind :: enum u8 {
	PASSIVE, DAMAGE_PHYSICAL, DAMAGE_MAGICAL, BUFF, DEBUFF, HEAL,
	PARTY_HEAL, HP_BUFF, MP_RESTORE, REVIVE, FIELD_SPELL, PROVOKE, UTILITY,
}

Skill_Source :: enum u8 { TREE, CLASS_KIT }

// A cross-tree prerequisite: `points` of proficiency required in sub-category
// `sub_cat` (TS reqPoints array form, e.g. Swing needs {Slash:60, Dodge:15}).
Prereq :: struct {
	sub_cat: Sub_Category,
	points: int,
}

// Distinct types so the union can tell Level and Points apart. [D4]
Skill_Level_Req  :: distinct u8 // class-kit skill: required character level
Skill_Points_Req :: distinct u8 // tree skill: proficiency threshold in its sub-cat

Skill_Req :: union {
	Skill_Level_Req,
	Skill_Points_Req,
	[4]Prereq, // cross-tree proficiency prereqs (sub_cat == a sentinel ⇒ unused)
}

Skill_Def :: struct {
	name:            string,
	source:          Skill_Source,
	sub_cat:         Sub_Category,
	kind:            Skill_Kind,
	description:     string,
	req:             Skill_Req,
	cost_mp:         u16,
	cast_time_s:     f32,
	cooldown_s:      f32,
	duration_s:      f32,
	targeting:       Targeting,
	requires:        Skill_Requirements,
	outcomes:        [MAX_SKILL_OUTCOMES]Outcome,
	outcome_count:   u8,
	category_level:  bool, // true = reqPoints checks parent category total, not single sub-cat
}


// ── races / jobs / proficiency ─────────────────────────────────────────────

Stat_Block :: struct { sta, str, agi, dex, spi, intel: f32 }

Race_Passive :: struct { id, name, description: string }

Race_Def :: struct {
	name:        string, // display name; the registry key is the wire id
	description: string,
	model_file:  string, // race model — any race can be any class
	base_stats:  Stat_Block,
	passives:    [3]Race_Passive, // exactly 3 choices per race in TS
}

// Fields mirror the TS JobDefinition (jobs.ts) so the full table drops in
// directly. Identity comes from the registry (key = wire jobId); `parent` is
// the registry id of the prerequisite job (INVALID_JOB_ID when none).
Job_Proficiency :: struct {
	min_adeptness: u8, // floor to invest any points in this sub-category
	max_potential: u8, // cap
}

Job_Def :: struct {
	name:          string,
	base_class:    Base_Class,
	tier:          u8, // 1 | 2 | 3
	parent:        Job_Id,
	description:   string,
	base_stat_mods:[Stat]f32, // partial; keyed by Stat (STA/STR/AGI/DEX/SPI/INT)
	lp_base:       f32,
	lp_per_level:  f32,
	lp_per_sta:    f32,
	mp_base:       f32,
	mp_per_level:  f32,
	mp_per_spi:    f32,
	proficiency:   [Sub_Category]Job_Proficiency, // per-sub-cat caps for this job
	kit_skill_ids: [dynamic]Skill_Id, // class-kit skills this job knows
}


// ── master registries ──────────────────────────────────────────────────────
// Populated by init_game_data. Contiguous item arrays indexed by the distinct
// u16 IDs; by_key gives the human-memorable string → id lookup.

race_registry:  Registry(Race_Def, Race_Id)
job_registry:   Registry(Job_Def, Job_Id)
skill_registry: Registry(Skill_Def, Skill_Id)
// Tree skills grouped by their sub-category (class-kit skills are reached via
// Job_Def.kit_skill_ids instead).
tree_skills: [Sub_Category][dynamic]Skill_Id

game_data_loaded: bool


// ── lookups ────────────────────────────────────────────────────────────────

get_skill :: proc(name: string) -> ^Skill_Def {
	id, ok := registry_lookup(&skill_registry, name)
	if !ok do return nil
	return registry_get(&skill_registry, id)
}

job_by_name :: proc(name: string) -> (Job_Id, bool) {
	return registry_lookup(&job_registry, name)
}

race_by_name :: proc(name: string) -> (Race_Id, bool) {
	return registry_lookup(&race_registry, name)
}

// Resolve a Skill_Def's level requirement (class-kit skills), or 0 if it's
// proficiency-gated (tree skills).
skill_req_level :: proc(sk: ^Skill_Def) -> u8 {
	#partial switch v in sk.req {
	case Skill_Level_Req: return u8(v)
	case:                 return 0
	}
}

// Resolve a Skill_Def's proficiency-point threshold in its own sub-category
// (tree skills with a flat point req), or 0 otherwise.
skill_req_points :: proc(sk: ^Skill_Def) -> u8 {
	#partial switch v in sk.req {
	case Skill_Points_Req: return u8(v)
	case:                 return 0
	}
}

// Whether the player currently meets a skill's requirement — level for kit
// skills, sub-category adeptness (and cross-tree prereqs) for tree skills.
skill_req_met :: proc(sk: ^Skill_Def, p: ^Local_Player) -> bool {
	#partial switch v in sk.req {
	case Skill_Level_Req:
		return p.stats.level >= int(v)
	case Skill_Points_Req:
		if sk.category_level {
			return category_total(p, sub_category_to_category(sk.sub_cat)) >= i32(v)
		}
		return p.allocated_skill_points[sk.sub_cat] >= i32(v)
	case [4]Prereq:
		for i in 0 ..< len(v) {
			pr := v[i]
			if pr.points == 0 do continue
			if p.allocated_skill_points[pr.sub_cat] < i32(pr.points) do return false
		}
		return true
	case:
		return true
	}
}

// ── stat-point cost (port of races.ts STAT_POINT_COSTS / getStatPointCost) ──
// The server prices each raise off the stat's TOTAL value (race+job base +
// allocated). Tiers: ≤30→2, ≤50→3, ≤70→4, ≤90→5, else→6 unspent points.
stat_point_cost :: proc "contextless" (current_total: int) -> int {
	idx := current_total + 1 // STAT_POINT_COSTS is 1-indexed
	switch {
	case idx <= 30: return 2
	case idx <= 50: return 3
	case idx <= 70: return 4
	case idx <= 90: return 5
	case:           return 6
	}
}

// Race base + job modifier for an attribute (the non-allocated portion the
// server folds into currentValue). Mirrors calculateDerivedStats' baseStats.
attr_base :: proc(p: ^Local_Player, a: Attr) -> int {
	if p.race == INVALID_RACE_ID || p.job_id == INVALID_JOB_ID do return 0
	race := registry_get(&race_registry, p.race)
	job := registry_get(&job_registry, p.job_id)
	base: f32
	#partial switch a {
	case .STA: base = race.base_stats.sta
	case .STR: base = race.base_stats.str
	case .AGI: base = race.base_stats.agi
	case .DEX: base = race.base_stats.dex
	case .SPI: base = race.base_stats.spi
	case .INT: base = race.base_stats.intel
	}
	return int(base + job.base_stat_mods[cast(Stat)(u8(a))])
}

// Total (base + allocated) for an attribute.
attr_total :: proc(p: ^Local_Player, a: Attr) -> int {
	return attr_base(p, a) + int(p.allocated_stats[a])
}

// Cost in unspent points of the next raise for an attribute.
attr_next_cost :: proc(p: ^Local_Player, a: Attr) -> int {
	return stat_point_cost(attr_total(p, a))
}

// String ↔ Base_Class (the TS BaseClass is a string union: 'warrior' etc.).
base_class_from_string :: proc(s: string) -> Base_Class {
	switch s {
	case "warrior":  return .WARRIOR
	case "scout":    return .SCOUT
	case "acolyte":  return .ACOLYTE
	case "mage":     return .MAGE
	case:           return .WARRIOR
	}
}

base_class_name :: proc(bc: Base_Class) -> string {
	switch bc {
	case .WARRIOR: return "Warrior"
	case .SCOUT:   return "Scout"
	case .ACOLYTE: return "Acolyte"
	case .MAGE:    return "Mage"
	}
	return "Warrior"
}

// One proficiency cap entry (sub-category, min adeptness to invest, max cap).
Prof_Entry :: struct {
	sc:    Sub_Category,
	min_a: u8,
	max_p: u8,
}

// Set a job's non-zero proficiency caps. Pairs cover only the sub-categories
// that job can invest in; the rest stay at the {0,0} zero value (unusable).
set_prof :: proc(job_key: string, pairs: ..Prof_Entry) {
	jid, ok := job_by_name(job_key)
	if !ok do return
	j := registry_get(&job_registry, jid)
	for p in pairs {
		j.proficiency[p.sc].min_adeptness = p.min_a
		j.proficiency[p.sc].max_potential = p.max_p
	}
}

// Populate every job's per-sub-category proficiency caps from
// src/constants/jobSkillValues.ts (mapped by job name — my Job_Id indices
// intentionally don't match the TS design-ids, so the lookup is by key).
populate_proficiency :: proc() {
	set_prof("warrior",
		{.SLASH, 5, 25}, {.THRUST, 2, 25}, {.CLEAVE, 5, 25}, {.BASH, 2, 20}, {.DEFEND, 4, 25}, {.DODGE, 0, 5})
	set_prof("gladiator",
		{.SLASH, 5, 55}, {.THRUST, 2, 45}, {.CLEAVE, 5, 55}, {.BASH, 2, 45}, {.DEFEND, 4, 25},
		{.SHOT, 1, 15}, {.ALCHEMY, 0, 20}, {.ASSASSINATION, 0, 25}, {.TRAP, 0, 20}, {.DODGE, 0, 10})
	set_prof("juggernaut",
		{.SLASH, 5, 90}, {.THRUST, 2, 90}, {.CLEAVE, 5, 90}, {.BASH, 2, 45}, {.DEFEND, 4, 35},
		{.SHOT, 1, 20}, {.DODGE, 0, 20}, {.HORSEMANSHIP, 0, 10})
	set_prof("dragoon",
		{.SLASH, 5, 60}, {.THRUST, 2, 90}, {.CLEAVE, 5, 60}, {.BASH, 2, 30}, {.DEFEND, 4, 50},
		{.SHOT, 1, 20}, {.DODGE, 0, 20}, {.HORSEMANSHIP, 0, 70})
	set_prof("knight",
		{.SLASH, 5, 35}, {.THRUST, 2, 55}, {.CLEAVE, 5, 25}, {.BASH, 2, 35}, {.DEFEND, 4, 55},
		{.SHOT, 1, 5}, {.DODGE, 0, 15}, {.GRACE, 0, 15})
	set_prof("warlord",
		{.SLASH, 5, 50}, {.THRUST, 2, 80}, {.CLEAVE, 5, 60}, {.BASH, 2, 60}, {.DEFEND, 4, 90},
		{.SHOT, 1, 20}, {.DODGE, 0, 10}, {.GRACE, 0, 15}, {.HORSEMANSHIP, 0, 15})
	set_prof("paladin",
		{.SLASH, 5, 80}, {.THRUST, 2, 55}, {.CLEAVE, 5, 25}, {.BASH, 2, 45}, {.DEFEND, 4, 60},
		{.SHOT, 1, 5}, {.DODGE, 0, 10}, {.GRACE, 0, 55}, {.EXORCISM, 0, 25}, {.HORSEMANSHIP, 0, 40})
	set_prof("scout",
		{.SLASH, 4, 10}, {.DEFEND, 0, 10}, {.SHOT, 5, 25}, {.ALCHEMY, 4, 20},
		{.ASSASSINATION, 3, 25}, {.TRAP, 0, 20}, {.DODGE, 3, 20})
	set_prof("archer",
		{.SLASH, 4, 30}, {.DEFEND, 0, 10}, {.SHOT, 5, 55}, {.ALCHEMY, 4, 20},
		{.ASSASSINATION, 3, 30}, {.TRAP, 0, 25}, {.DODGE, 3, 50})
	set_prof("sniper",
		{.SLASH, 4, 25}, {.DEFEND, 0, 10}, {.SHOT, 5, 90}, {.ALCHEMY, 4, 50},
		{.ASSASSINATION, 3, 30}, {.TRAP, 0, 40}, {.DODGE, 3, 90},
		{.DARKNESS, 5, 30}, {.HORSEMANSHIP, 0, 20})
	set_prof("hunter",
		{.SLASH, 4, 30}, {.DEFEND, 0, 10}, {.SHOT, 5, 70}, {.ALCHEMY, 4, 90},
		{.ASSASSINATION, 3, 30}, {.TRAP, 0, 70}, {.DODGE, 3, 50}, {.HORSEMANSHIP, 0, 50})
	set_prof("provocateur",
		{.SLASH, 4, 30}, {.DEFEND, 0, 20}, {.SHOT, 5, 30}, {.ALCHEMY, 4, 25},
		{.ASSASSINATION, 3, 55}, {.TRAP, 0, 50}, {.DODGE, 3, 40})
	set_prof("assassin",
		{.SLASH, 4, 65}, {.DEFEND, 0, 20}, {.SHOT, 5, 30}, {.ALCHEMY, 4, 50},
		{.ASSASSINATION, 3, 90}, {.TRAP, 0, 50}, {.DODGE, 3, 65}, {.HORSEMANSHIP, 0, 20})
	set_prof("saboteur",
		{.SLASH, 4, 45}, {.DEFEND, 0, 25}, {.SHOT, 5, 45}, {.ALCHEMY, 4, 60},
		{.ASSASSINATION, 3, 55}, {.TRAP, 0, 90}, {.DODGE, 3, 55},
		{.CONFUSION, 0, 15}, {.HORSEMANSHIP, 0, 10})
	set_prof("acolyte",
		{.BASH, 2, 20}, {.DEFEND, 2, 20}, {.DODGE, 0, 5},
		{.GRACE, 5, 25}, {.BLESSING, 5, 25}, {.EXORCISM, 5, 25})
	set_prof("priest",
		{.BASH, 2, 35}, {.DEFEND, 2, 30}, {.DODGE, 0, 5},
		{.GRACE, 5, 55}, {.BLESSING, 5, 55}, {.EXORCISM, 5, 30})
	set_prof("cleric",
		{.CLEAVE, 0, 15}, {.BASH, 2, 50}, {.DEFEND, 2, 40}, {.DODGE, 0, 5},
		{.GRACE, 5, 90}, {.BLESSING, 5, 55}, {.EXORCISM, 5, 40}, {.HYMN, 0, 45},
		{.INVOCATION, 0, 10}, {.HORSEMANSHIP, 0, 15})
	set_prof("enchanter",
		{.BASH, 2, 45}, {.DEFEND, 2, 35}, {.DODGE, 0, 5},
		{.GRACE, 5, 55}, {.BLESSING, 5, 90}, {.EXORCISM, 5, 30}, {.HYMN, 0, 65},
		{.INVOCATION, 0, 30}, {.HORSEMANSHIP, 0, 20})
	set_prof("ascetic",
		{.CLEAVE, 0, 15}, {.BASH, 2, 50}, {.DEFEND, 2, 20}, {.DODGE, 0, 5},
		{.GRACE, 5, 25}, {.BLESSING, 5, 25}, {.EXORCISM, 5, 55})
	set_prof("monk",
		{.CLEAVE, 0, 15}, {.BASH, 2, 90}, {.DEFEND, 2, 25}, {.DODGE, 0, 55},
		{.GRACE, 5, 30}, {.BLESSING, 5, 25}, {.EXORCISM, 5, 60}, {.HORSEMANSHIP, 0, 10})
	set_prof("exorcist",
		{.CLEAVE, 0, 15}, {.BASH, 2, 70}, {.DEFEND, 2, 30}, {.DODGE, 0, 10},
		{.GRACE, 5, 45}, {.BLESSING, 5, 30}, {.EXORCISM, 5, 90}, {.HYMN, 0, 10},
		{.INVOCATION, 0, 40}, {.HORSEMANSHIP, 0, 10})
	set_prof("mage",
		{.SLASH, 2, 15}, {.DEFEND, 2, 15}, {.DODGE, 0, 5},
		{.ELEMENTAL, 5, 25}, {.INVOCATION, 5, 40}, {.DARKNESS, 0, 20}, {.CONFUSION, 0, 25})
	set_prof("wizard",
		{.SLASH, 2, 20}, {.DEFEND, 2, 30}, {.DODGE, 0, 5},
		{.GRACE, 0, 10}, {.BLESSING, 0, 10}, {.EXORCISM, 0, 20},
		{.ELEMENTAL, 5, 55}, {.INVOCATION, 5, 50}, {.DARKNESS, 0, 20}, {.CONFUSION, 5, 30})
	set_prof("warlock",
		{.SLASH, 2, 30}, {.BASH, 2, 30}, {.DODGE, 0, 5},
		{.GRACE, 0, 25}, {.BLESSING, 0, 10}, {.EXORCISM, 0, 40},
		{.ELEMENTAL, 5, 90}, {.INVOCATION, 5, 50}, {.DARKNESS, 0, 30}, {.CONFUSION, 5, 40},
		{.HORSEMANSHIP, 0, 10})
	set_prof("conjurer",
		{.SLASH, 2, 25}, {.BASH, 2, 30}, {.TRAP, 0, 20}, {.DODGE, 0, 5},
		{.GRACE, 0, 10}, {.BLESSING, 0, 20}, {.EXORCISM, 0, 20},
		{.ELEMENTAL, 5, 60}, {.INVOCATION, 5, 90}, {.DARKNESS, 0, 40}, {.CONFUSION, 5, 50},
		{.HORSEMANSHIP, 0, 10})
	set_prof("sorcerer",
		{.SLASH, 2, 25}, {.DEFEND, 2, 15}, {.ALCHEMY, 0, 15}, {.ASSASSINATION, 0, 20}, {.DODGE, 0, 10},
		{.ELEMENTAL, 5, 30}, {.INVOCATION, 5, 25}, {.DARKNESS, 0, 55}, {.CONFUSION, 5, 55})
	set_prof("corruptor",
		{.SLASH, 2, 30}, {.BASH, 2, 15}, {.ALCHEMY, 0, 45}, {.ASSASSINATION, 0, 20}, {.DODGE, 0, 40},
		{.ELEMENTAL, 5, 30}, {.INVOCATION, 5, 50}, {.DARKNESS, 0, 70}, {.CONFUSION, 5, 90})
	set_prof("shadowblade",
		{.SLASH, 2, 65}, {.BASH, 2, 15}, {.ALCHEMY, 0, 15}, {.ASSASSINATION, 0, 30}, {.DODGE, 0, 25},
		{.ELEMENTAL, 5, 30}, {.INVOCATION, 5, 25}, {.DARKNESS, 0, 90}, {.CONFUSION, 5, 55},
		{.HORSEMANSHIP, 0, 50})
}

// Register a job from its scalar fields. `parent_key` is the wire id of the
// prerequisite job (looked up — must already be registered) or "" for tier-1.
// base_stat_mods is left zero; the caller sets the handful of non-zero entries.
// (Races own models, not jobs — any race can be any class.)
job_add :: proc(
	key, display: string, bc: Base_Class, tier: u8, parent_key, desc: string,
	lp_base, lp_per_level, lp_per_sta, mp_base, mp_per_level, mp_per_spi: f32,
) -> ^Job_Def {
	j, _ := registry_reserve(&job_registry, key)
	j.name = display
	j.base_class = bc
	j.tier = tier
	j.parent = INVALID_JOB_ID
	if len(parent_key) > 0 {
		if pid, ok := job_by_name(parent_key); ok do j.parent = pid
	}
	j.description = desc
	j.lp_base = lp_base
	j.lp_per_level = lp_per_level
	j.lp_per_sta = lp_per_sta
	j.mp_base = mp_base
	j.mp_per_level = mp_per_level
	j.mp_per_spi = mp_per_spi
	j.kit_skill_ids = make([dynamic]Skill_Id)
	return j
}

// Register a tree skill with a single physical damage outcome — the common case
// for melee/ranged tree skills. Returns the skill pointer for the caller to add
// AOE mode, knockback, cross-tree prereqs, etc.
tree_phys :: proc(
	key, desc: string, sub: Sub_Category, sub_type: Damage_Sub_Type,
	pts: u8, mp: u16, cast_s, cd: f32, power: f32, hits: u8,
) -> ^Skill_Def {
	s, _ := registry_reserve(&skill_registry, key)
	s.source = .TREE
	s.sub_cat = sub
	s.kind = .DAMAGE_PHYSICAL
	s.description = desc
	s.req = Skill_Points_Req(pts)
	s.cost_mp = mp
	s.cast_time_s = cast_s
	s.cooldown_s = cd
	s.outcomes[0] = Damage_Params{sub_type = sub_type, base_power = power, base_hits = hits}
	s.outcome_count = 1
	return s
}

// Register a passive tree skill (no outcomes).
	tree_passive :: proc(key, desc: string, sub: Sub_Category, pts: u8) {
	s, _ := registry_reserve(&skill_registry, key)
	s.source = .TREE
	s.sub_cat = sub
	s.kind = .PASSIVE
	s.description = desc
	s.req = Skill_Points_Req(pts)
}

// As tree_phys but for MAGICAL damage (traps, holy/arcanne spells, etc.).
tree_mag :: proc(
	key, desc: string, sub: Sub_Category, sub_type: Damage_Sub_Type,
	pts: u8, mp: u16, cast_s, cd: f32, power: f32, hits: u8,
) -> ^Skill_Def {
	s, _ := registry_reserve(&skill_registry, key)
	s.source = .TREE
	s.sub_cat = sub
	s.kind = .DAMAGE_MAGICAL
	s.description = desc
	s.req = Skill_Points_Req(pts)
	s.cost_mp = mp
	s.cast_time_s = cast_s
	s.cooldown_s = cd
	s.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = sub_type, base_power = power, base_hits = hits}
	s.outcome_count = 1
	return s
}

// Register a class-kit skill (gated by character level, not proficiency).
kit_skill :: proc(
	key, desc: string, kind: Skill_Kind, lvl: u8, mp: u16, cast_s, cd, dur: f32,
) -> ^Skill_Def {
	s, _ := registry_reserve(&skill_registry, key)
	s.source = .CLASS_KIT
	s.kind = kind
	s.description = desc
	s.req = Skill_Level_Req(lvl)
	s.cost_mp = mp
	s.cast_time_s = cast_s
	s.cooldown_s = cd
	s.duration_s = dur
	return s
}

// Link a job to its class-kit skills by name (resolves via the registry).
kit :: proc(job_key: string, names: ..string) {
	jid, ok := job_by_name(job_key)
	if !ok do return
	j := registry_get(&job_registry, jid)
	for name in names {
		if sid, ok := skill_registry.by_key[name]; ok do append(&j.kit_skill_ids, sid)
	}
}

// Resolve a Tiered_Mod against a character's gating stat + proficiency. Returns
// the merged delta vector (length STAT_COUNT). Demonstrates the [D6] resolver.
resolve_tiered :: proc(t: ^Tiered_Mod, gate_stat_value: f32, proficiency_value: f32) -> [Stat]f32 {
	out: [Stat]f32
	stat_tier: ^Tier_Stat_Tier = nil
	for i in 0 ..< len(t.tiers) {
		if gate_stat_value >= t.tiers[i].stat_threshold do stat_tier = &t.tiers[i]
	}
	if stat_tier == nil do return out
	best: ^Tier_Prof_Tier = nil
	for i in 0 ..< len(stat_tier.prof_tiers) {
		pt := &stat_tier.prof_tiers[i]
		if proficiency_value >= pt.prof_threshold do best = pt
	}
	if best == nil do return out
	out = best.deltas
	return out
}


// ── sample population (exercises every branch of the schema) ───────────────

	init_game_data :: proc() {
	if game_data_loaded do return
	game_data_loaded = true

	registry_init(&race_registry)
	registry_init(&job_registry)
	registry_init(&skill_registry)
	for sc in Sub_Category do tree_skills[sc] = make([dynamic]Skill_Id)
	init_item_defs()

	// Races (data from src/constants/races.ts RACE_DATA). Models are per-race.
	registry_add(&race_registry, "human", Race_Def{
		name = "Human",
		description = "Versatile and adaptable. Well-rounded in all disciplines.",
		model_file = "Adventurer.glb",
		base_stats = {5, 5, 5, 5, 5, 5},
		passives = {
			{id = "fighting_spirit", name = "Fighting Spirit", description = "+10 melee skill (1H)"},
			{id = "adaptability", name = "Adaptability", description = "Ailment duration -50%"},
			{id = "brewer", name = "Brewer", description = "Potion effectiveness +15%"},
		},
	})
	registry_add(&race_registry, "elf", Race_Def{
		name = "Elf",
		description = "Graceful and magical. Natural affinity for ranged combat and spellcraft.",
		model_file = "Hoodie Character.glb",
		base_stats = {3, 3, 6, 4, 7, 7},
		passives = {
			{id = "hawkeye", name = "Hawkeye", description = "+3 ranged range"},
			{id = "natures_harmony", name = "Nature's Harmony", description = "Spell MP cost -15%"},
			{id = "steadfastness", name = "Steadfastness", description = "Charm resistance +20"},
		},
	})
	registry_add(&race_registry, "dwarf", Race_Def{
		name = "Dwarf",
		description = "Sturdy and resilient. Masters of heavy weapons and unwavering defense.",
		model_file = "Business Man.glb",
		base_stats = {6, 7, 5, 6, 3, 3},
		passives = {
			{id = "stronghearted", name = "Stronghearted", description = "1% chance take fatal damage for party member"},
			{id = "dwarf_spirit", name = "Dwarf Spirit", description = "Axe/blunt damage +10%"},
			{id = "filial_piety", name = "Filial Piety", description = "3% survive fatal with 1HP"},
		},
	})
	registry_add(&race_registry, "myrine", Race_Def{
		name = "Myrine",
		description = "Quick and elusive. Gifted with heightened reflexes and evasion.",
		model_file = "Casual Character.glb",
		base_stats = {5, 5, 9, 6, 3, 2},
		passives = {
			{id = "acute_senses", name = "Acute Senses", description = "Crit chance +5%"},
			{id = "sharpness", name = "Sharpness", description = "5% dodge"},
			{id = "calmness", name = "Calmness", description = "Chance convert damage to MP"},
		},
	})
	registry_add(&race_registry, "enkidu", Race_Def{
		name = "Enkidu",
		description = "Powerful and tough. A beast-like race with immense physical presence.",
		model_file = "Worker.glb",
		base_stats = {8, 6, 4, 4, 6, 2},
		passives = {
			{id = "stone_skin", name = "Stone Skin", description = "Physical damage taken -10%"},
			{id = "strong_arm", name = "Strong Arm", description = "2H weapon damage +10%"},
			{id = "lapin_support", name = "Lapin Support", description = "Boost Lapin party members' physical defense"},
		},
	})
	registry_add(&race_registry, "lapin", Race_Def{
		name = "Lapin",
		description = "Gentle and magically attuned. A rabbit-like race with strong mystical affinity.",
		model_file = "Farmer.glb",
		base_stats = {3, 1, 6, 5, 9, 6},
		passives = {
			{id = "magic_resistance", name = "Magic Resistance", description = "Magic resistance +10%"},
			{id = "inner_light", name = "Inner Light", description = "MP regen +15%"},
			{id = "enkidu_support", name = "Enkidu Support", description = "Boost Enkidu party members' magic defense"},
		},
	})

	// ── jobs (data from src/constants/jobs.ts JOB_DEFINITIONS) ───────────
	// Registered tier-1 → tier-2 → tier-3 so parents resolve before children.
	// proficiency is left zeroed here; the full per-sub-category matrix and
	// kit_skill_ids land with the skills pass (B5).

	// Warrior tree.
	j := job_add("warrior", "Warrior", .WARRIOR, 1, "",
		"A mighty fighter with high health and physical power.",
		98, 5.847, 15.5, 16, 44.55, 48.3)
	j.base_stat_mods[.STR] = 3
	j.base_stat_mods[.STA] = 2
	j = job_add("gladiator", "Gladiator", .WARRIOR, 2, "warrior",
		"An offensive warrior specializing in two-handed weapons and raw damage.",
		148, 3.188, 8.465, 28, 36.7, 39.5)
	j.base_stat_mods[.STR] = 4
	j.base_stat_mods[.STA] = 2
	j.base_stat_mods[.DEX] = 1
	j = job_add("knight", "Knight", .WARRIOR, 2, "warrior",
		"A defensive warrior specializing in shields and party protection.",
		149, 2.975, 7.881, 118, 29.15, 31.4)
	j.base_stat_mods[.STR] = 2
	j.base_stat_mods[.STA] = 4
	j.base_stat_mods[.SPI] = 1
	j = job_add("juggernaut", "Juggernaut", .WARRIOR, 3, "gladiator",
		"An unstoppable force of destruction with devastating power.",
		298, 1.9601, 2.2836, 98, 32.2, 34.8)
	j.base_stat_mods[.STR] = 6
	j.base_stat_mods[.STA] = 3
	j.base_stat_mods[.DEX] = 2
	j = job_add("dragoon", "Dragoon", .WARRIOR, 3, "gladiator",
		"A lance-wielding warrior with superior mounted combat abilities.",
		149, 2.0033, 3.572, 98, 30.9, 33.3)
	j.base_stat_mods[.STR] = 5
	j.base_stat_mods[.STA] = 3
	j.base_stat_mods[.AGI] = 2
	j = job_add("warlord", "Warlord", .WARRIOR, 3, "knight",
		"A commanding presence on the battlefield with supreme leadership abilities.",
		498, 1.1493, 2.0618, 179, 25.8, 20.589)
	j.base_stat_mods[.STR] = 3
	j.base_stat_mods[.STA] = 5
	j.base_stat_mods[.SPI] = 3
	j = job_add("paladin", "Paladin", .WARRIOR, 3, "knight",
		"A holy knight combining strong defense with healing abilities.",
		398, 1.4285, 2.2322, 178, 24.7, 19.94)
	j.base_stat_mods[.STR] = 3
	j.base_stat_mods[.STA] = 5
	j.base_stat_mods[.SPI] = 3

	// Scout tree.
	j = job_add("scout", "Scout", .SCOUT, 1, "",
		"A swift hunter with ranged attacks and survival skills.",
		84, 7.23, 19.2, 44, 37.2, 40)
	j.base_stat_mods[.AGI] = 3
	j.base_stat_mods[.DEX] = 2
	j = job_add("archer", "Archer", .SCOUT, 2, "scout",
		"A ranged specialist with mastery of bows and crossbows.",
		109, 4.4, 11.67, 48, 31.2, 33.3)
	j.base_stat_mods[.AGI] = 4
	j.base_stat_mods[.DEX] = 3
	j.base_stat_mods[.STR] = 1
	j = job_add("provocateur", "Provocateur", .SCOUT, 2, "scout",
		"A cunning agent specializing in stealth and subterfuge.",
		109, 4.007, 10.63, 48, 33.1, 35.97)
	j.base_stat_mods[.AGI] = 5
	j.base_stat_mods[.DEX] = 2
	j = job_add("sniper", "Sniper", .SCOUT, 3, "archer",
		"An elite marksman with devastating precision at extreme range.",
		198, 3.333, 3.803, 69, 21.95, 20.146)
	j.base_stat_mods[.AGI] = 5
	j.base_stat_mods[.DEX] = 4
	j.base_stat_mods[.STR] = 2
	j = job_add("hunter", "Hunter", .SCOUT, 3, "archer",
		"A skilled tracker with traps and survival expertise.",
		151, 3.111, 4.464, 56, 22.6, 19.7)
	j.base_stat_mods[.AGI] = 5
	j.base_stat_mods[.DEX] = 3
	j.base_stat_mods[.STR] = 2
	j = job_add("assassin", "Assassin", .SCOUT, 3, "provocateur",
		"A deadly shadow operative with lethal critical hits.",
		149, 2.123, 3.922, 53, 24.44, 20.58)
	j.base_stat_mods[.AGI] = 7
	j.base_stat_mods[.DEX] = 3
	j.base_stat_mods[.STR] = 2
	j = job_add("saboteur", "Saboteur", .SCOUT, 3, "provocateur",
		"A master of traps and disruption tactics.",
		205, 2.53, 3.773, 59, 22.6, 17.92)
	j.base_stat_mods[.AGI] = 5
	j.base_stat_mods[.DEX] = 3
	j.base_stat_mods[.INT] = 3

	// Acolyte tree.
	j = job_add("acolyte", "Acolyte", .ACOLYTE, 1, "",
		"A devout healer with holy magic and support abilities.",
		73, 8.16, 21.51, 58, 18.06, 19.48)
	j.base_stat_mods[.SPI] = 3
	j.base_stat_mods[.INT] = 2
	j = job_add("priest", "Priest", .ACOLYTE, 2, "acolyte",
		"A holy healer with powerful restoration and blessing magic.",
		88, 4.475, 11.874, 198, 14, 15.08)
	j.base_stat_mods[.SPI] = 5
	j.base_stat_mods[.INT] = 3
	j = job_add("ascetic", "Ascetic", .ACOLYTE, 2, "acolyte",
		"A martial artist combining physical power with spiritual energy.",
		89, 3.883, 10.298, 163, 16.72, 18)
	j.base_stat_mods[.SPI] = 3
	j.base_stat_mods[.STR] = 3
	j.base_stat_mods[.AGI] = 2
	j = job_add("cleric", "Cleric", .ACOLYTE, 3, "priest",
		"A supreme healer with divine resurrection and protection magic.",
		199, 2.75, 3.745, 235, 8.875, 9.897)
	j.base_stat_mods[.SPI] = 7
	j.base_stat_mods[.INT] = 5
	j = job_add("enchanter", "Enchanter", .ACOLYTE, 3, "priest",
		"A mystic who strengthens allies with powerful support enchantments.",
		197, 3.33, 3.745, 253, 8.24, 8.861)
	j.base_stat_mods[.SPI] = 5
	j.base_stat_mods[.INT] = 4
	j.base_stat_mods[.DEX] = 2
	j = job_add("monk", "Monk", .ACOLYTE, 3, "ascetic",
		"An ascetic warrior with devastating chi-enhanced strikes.",
		299, 1.961, 2.681, 189, 12.9, 14)
	j.base_stat_mods[.SPI] = 4
	j.base_stat_mods[.STR] = 5
	j.base_stat_mods[.AGI] = 3
	j = job_add("exorcist", "Exorcist", .ACOLYTE, 3, "ascetic",
		"A spiritual warrior who purifies evil with sacred combat arts.",
		203, 2.578, 3.83, 197, 8.5, 9.16)
	j.base_stat_mods[.SPI] = 5
	j.base_stat_mods[.INT] = 4
	j.base_stat_mods[.STR] = 3

	// Mage tree.
	j = job_add("mage", "Mage", .MAGE, 1, "",
		"A powerful spellcaster with devastating magical abilities.",
		59, 8.44, 22.48, 89, 17.6, 18.9)
	j.base_stat_mods[.INT] = 3
	j.base_stat_mods[.SPI] = 2
	j = job_add("wizard", "Wizard", .MAGE, 2, "mage",
		"A master of elemental magic with devastating area spells.",
		73, 5.753, 15.28, 253, 10.57, 11.41)
	j.base_stat_mods[.INT] = 5
	j.base_stat_mods[.SPI] = 3
	j = job_add("sorcerer", "Sorcerer", .MAGE, 2, "mage",
		"A dark caster wielding forbidden arcane powers.",
		73, 4.86, 12.88, 119, 12.63, 13.63)
	j.base_stat_mods[.INT] = 4
	j.base_stat_mods[.SPI] = 2
	j.base_stat_mods[.AGI] = 2
	j = job_add("warlock", "Warlock", .MAGE, 3, "wizard",
		"An arcane supreme with mastery over all elements.",
		148, 4.006, 5.405, 254, 5.915, 6.366)
	j.base_stat_mods[.INT] = 7
	j.base_stat_mods[.SPI] = 5
	j = job_add("conjurer", "Conjurer", .MAGE, 3, "wizard",
		"A wise scholar combining magic with support summoning.",
		142, 3.756, 4.95, 254, 7.45, 8.016)
	j.base_stat_mods[.INT] = 6
	j.base_stat_mods[.SPI] = 6
	j.base_stat_mods[.DEX] = 2
	j = job_add("corruptor", "Corruptor", .MAGE, 3, "sorcerer",
		"A dark summoner who corrupts and weakens enemies.",
		166, 3.53, 4.84, 203, 9.4, 12.3)
	j.base_stat_mods[.INT] = 6
	j.base_stat_mods[.SPI] = 4
	j.base_stat_mods[.AGI] = 2
	j = job_add("shadowblade", "Shadowblade", .MAGE, 3, "sorcerer",
		"A hybrid of shadow magic and blade arts.",
		151, 3.339, 5.26, 195, 11.23, 10.14)
	j.base_stat_mods[.INT] = 5
	j.base_stat_mods[.AGI] = 3
	j.base_stat_mods[.DEX] = 3

	// Per-job proficiency caps (jobSkillValues.ts) — gates skill-point limits.
	populate_proficiency()

	// ── Slash tree (melee) — full sub-category, data from skills.ts ──────
	// (tree_skills grouping is built by a post-registration scan below, so no
	// per-skill appends are needed.)
	slice_p, _ := registry_reserve(&skill_registry, "Slice")
	slice_p.source = .TREE
	slice_p.sub_cat = .SLASH
	slice_p.kind = .DAMAGE_PHYSICAL
	slice_p.description = "Double attack (1H weapons)"
	slice_p.req = Skill_Points_Req(8)
	slice_p.cost_mp = 15
	slice_p.cooldown_s = 10
	slice_p.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 1, base_hits = 2}
	slice_p.outcome_count = 1

	ws_p, _ := registry_reserve(&skill_registry, "Whirling Strike")
	ws_p.source = .TREE
	ws_p.sub_cat = .SLASH
	ws_p.kind = .DAMAGE_PHYSICAL
	ws_p.description = "360 AOE knockback melee attack (2H swords)"
	ws_p.req = Skill_Points_Req(12)
	ws_p.cost_mp = 28
	ws_p.cooldown_s = 15
	ws_p.targeting.aoe_mode = .SELF_CENTERED
	ws_p.targeting.aoe_radius = 1
	ws_p.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 2, knockback = 2}
	ws_p.outcome_count = 1

	// Parry: a defensive stance (block + counter-stun resolved server-side).
	parry_p, _ := registry_reserve(&skill_registry, "Parry")
	parry_p.source = .TREE
	parry_p.sub_cat = .SLASH
	parry_p.kind = .BUFF
	parry_p.description = "Block enemy attacks and stun target if blocked (2H weapons, dagger)"
	parry_p.req = Skill_Points_Req(21)
	parry_p.cost_mp = 9
	parry_p.cooldown_s = 10
	parry_p.duration_s = 2

	conc_p, _ := registry_reserve(&skill_registry, "Concentration")
	conc_p.source = .TREE
	conc_p.sub_cat = .SLASH
	conc_p.kind = .BUFF
	conc_p.description = "Increased accuracy of next attack"
	conc_p.req = Skill_Points_Req(26)
	conc_p.cost_mp = 18
	conc_p.cooldown_s = 20
	conc_p.duration_s = 120
	conc_p.requires.self_only = true
	conc_p.outcomes[0] = Apply_Effect{
		polarity = .BUFF, to_self = true, duration_s = 120,
		effect = Stat_Mod{stat = .ACCURACY, delta = 50},
	}
	conc_p.outcomes[1] = Apply_Effect{
		polarity = .BUFF, to_self = true, duration_s = 120,
		effect = Status_Flag_Set{.CONSUMABLE_ON_ATTACK},
	}
	conc_p.outcome_count = 2

	brutal_p, _ := registry_reserve(&skill_registry, "Brutal Strike")
	brutal_p.source = .TREE
	brutal_p.sub_cat = .SLASH
	brutal_p.kind = .DAMAGE_PHYSICAL
	brutal_p.description = "100% chance to ignore armor (melee weapons)"
	brutal_p.req = Skill_Points_Req(41)
	brutal_p.cost_mp = 14
	brutal_p.cooldown_s = 10
	brutal_p.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 1, ignore_armor = true}
	brutal_p.outcome_count = 1

	// Swing: cross-tree proficiency prereq (60 Slash + 15 Dodge).
	swing_p, _ := registry_reserve(&skill_registry, "Swing")
	swing_p.source = .TREE
	swing_p.sub_cat = .SLASH
	swing_p.kind = .DAMAGE_PHYSICAL
	swing_p.description = "360 AOE melee attack (no knockback) that grants +100 dodge for a short duration (sword)"
	swing_p.req = [4]Prereq{{.SLASH, 60}, {.DODGE, 15}, {}, {}}
	swing_p.cost_mp = 16
	swing_p.targeting.aoe_mode = .SELF_CENTERED
	swing_p.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 1}
	swing_p.outcomes[1] = Apply_Effect{
		polarity = .BUFF, to_self = true, duration_s = 2,
		effect = Stat_Mod{stat = .DODGE, delta = 100},
	}
	swing_p.outcome_count = 2

	mastery_p, _ := registry_reserve(&skill_registry, "Sword Mastery (Passive)")
	mastery_p.source = .TREE
	mastery_p.sub_cat = .SLASH
	mastery_p.kind = .PASSIVE
	mastery_p.description = "Increased damage with swords and daggers (sword, dagger)"
	mastery_p.req = Skill_Points_Req(61)

	dice_p, _ := registry_reserve(&skill_registry, "Dice")
	dice_p.source = .TREE
	dice_p.sub_cat = .SLASH
	dice_p.kind = .DAMAGE_PHYSICAL
	dice_p.description = "Replaces Slice, dealing three swift strikes with a chance to bleed (1H weapons and 2H swords)"
	dice_p.req = Skill_Points_Req(71)
	dice_p.cost_mp = 15
	dice_p.cooldown_s = 10
	dice_p.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 1, base_hits = 3}
	dice_p.outcome_count = 1

	maxshoot_p, _ := registry_reserve(&skill_registry, "Maximum Shoot")
	maxshoot_p.source = .TREE
	maxshoot_p.sub_cat = .SLASH
	maxshoot_p.kind = .DAMAGE_PHYSICAL
	maxshoot_p.description = "Replaces Brutal Strike, higher damage with chance to knockdown (melee weapons)"
	maxshoot_p.req = Skill_Points_Req(81)
	maxshoot_p.cost_mp = 14
	maxshoot_p.cooldown_s = 15
	maxshoot_p.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 1}
	maxshoot_p.outcome_count = 1

	tws_p, _ := registry_reserve(&skill_registry, "True Whirling Strike")
	tws_p.source = .TREE
	tws_p.sub_cat = .SLASH
	tws_p.kind = .DAMAGE_PHYSICAL
	tws_p.description = "Replaces Whirling Strike, higher damage and wider range (2H swords)"
	tws_p.req = Skill_Points_Req(81)
	tws_p.cost_mp = 28
	tws_p.cooldown_s = 15
	tws_p.targeting.aoe_mode = .SELF_CENTERED
	tws_p.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 2}
	tws_p.outcome_count = 1

	finish_p, _ := registry_reserve(&skill_registry, "Finish Detonate")
	finish_p.source = .TREE
	finish_p.sub_cat = .SLASH
	finish_p.kind = .DAMAGE_PHYSICAL
	finish_p.description = "Strong single-target attack with a long cooldown and high MP cost"
	finish_p.req = Skill_Points_Req(90)
	finish_p.cost_mp = 94
	finish_p.cooldown_s = 180
	finish_p.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 4}
	finish_p.outcome_count = 1

	// ── Thrust tree (melee) ──────────────────────────────────────────────
	s := tree_phys("Heave", "Pierces through all enemies in front of you", .THRUST, .THRUST, 8, 16, 2, 10, 1, 1)
	s.targeting.aoe_mode = .FRONTAL_CONE
	tree_phys("Triple Stab", "Triple attack (spear)", .THRUST, .THRUST, 26, 22, 0, 30, 1, 3)
	s = tree_phys("Dismounting Stab", "Attack with a buff that gives a chance to dismount target", .THRUST, .THRUST, 35, 28, 0, 90, 2, 1)
	s.duration_s = 60
	tree_phys("Spear Volley", "Ranged attack with spear", .THRUST, .THRUST, 41, 24, 1, 30, 1, 1)
	tree_phys("Quadruple Stab", "Quadruple attack (spear), bonus damage if comboed with Triple Stab", .THRUST, .THRUST, 54, 43, 0, 16, 2, 4)
	s = tree_phys("Sonic Sting", "Ranged spear attack", .THRUST, .THRUST, 0, 39, 1.5, 31, 2, 1)
	s.req = [4]Prereq{{.THRUST, 60}, {.SHOT, 15}, {}, {}}
	s = tree_phys("Neck Press", "Interrupts enemy casting", .THRUST, .THRUST, 0, 39, 0, 30, 1, 1)
	s.req = [4]Prereq{{.THRUST, 60}, {.DEFEND, 15}, {}, {}}
	tree_passive("Lance Mastery (Passive)", "Increased attack range with spears", .THRUST, 61)
	tree_phys("Horse Assault", "Bonus damage vs mounted enemies and chance to dismount enemies (spear)", .THRUST, .THRUST, 71, 13, 0, 7, 1, 1)
	s = tree_phys("Assault", "Rush forward and deal multiple hits of damage in a frontal cone AOE", .THRUST, .THRUST, 81, 24, 0, 15, 1, 1)
	s.targeting.aoe_mode = .FRONTAL_CONE
	s = tree_phys("Godlike", "Strong single target attack with knockback", .THRUST, .THRUST, 90, 52, 1.5, 30, 3, 1)
	s.outcomes[0] = Damage_Params{sub_type = .THRUST, base_power = 3, knockback = 4}

	// ── Cleave tree (melee) ──────────────────────────────────────────────
	tree_phys("Clobber", "Attack + increased chance of a critical hit (axe, unusable by ascetics)", .CLEAVE, .CLEAVE, 8, 19, 0, 25, 1, 1)
	// Riposte: immobile counter-attack stance (counter resolved server-side).
	riposte_p, _ := registry_reserve(&skill_registry, "Riposte")
	riposte_p.source = .TREE
	riposte_p.sub_cat = .CLEAVE
	riposte_p.kind = .BUFF
	riposte_p.description = "Immobile defensive stance that counter attacks if hit during the duration (2H weapons)"
	riposte_p.req = Skill_Points_Req(12)
	riposte_p.cost_mp = 12
	riposte_p.cast_time_s = 0.5
	riposte_p.cooldown_s = 10
	riposte_p.duration_s = 2
	riposte_p.requires.stationary = true
	roar_p, _ := registry_reserve(&skill_registry, "Roar")
	roar_p.source = .TREE
	roar_p.sub_cat = .CLEAVE
	roar_p.kind = .BUFF
	roar_p.description = "Increased critical hit rate (axe)"
	roar_p.req = Skill_Points_Req(21)
	roar_p.cost_mp = 30
	roar_p.cooldown_s = 120
	roar_p.duration_s = 60
	roar_p.requires.self_only = true
	s = tree_phys("Split", "Short range frontal AOE attack (axe)", .CLEAVE, .CLEAVE, 41, 22, 0, 20, 1, 1)
	s.targeting.aoe_mode = .FRONTAL_CONE
	s = tree_phys("Full Swing", "360 AOE melee attack (no knockback) that grants +100 dodge for a short duration (axe)", .CLEAVE, .CLEAVE, 0, 16, 0, 10, 1, 1)
	s.req = [4]Prereq{{.CLEAVE, 60}, {.DODGE, 15}, {}, {}}
	s.targeting.aoe_mode = .SELF_CENTERED
	s.outcomes[1] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 2, effect = Stat_Mod{stat = .DODGE, delta = 100}}
	s.outcome_count = 2
	tree_passive("Axe Mastery (Passive)", "Increased critical damage with axes", .CLEAVE, 61)
	tree_phys("Desperate Strike", "Attack with a chance to stun target, stuns you on failure", .CLEAVE, .CLEAVE, 71, 36, 0, 15, 2, 1)
	s = tree_phys("Grand Quake", "Short ranged AOE attack with 100% chance to interrupt casting", .CLEAVE, .CLEAVE, 0, 198, 0, 40, 8, 1)
	s.req = [4]Prereq{{.CLEAVE, 78}, {.BASH, 26}, {}, {}}
	s = tree_phys("Dragon Tail", "Frontal AOE cleave that deals a small amount of damage as recoil", .CLEAVE, .CLEAVE, 81, 120, 0, 60, 5, 1)
	s.targeting.aoe_mode = .FRONTAL_CONE
	s = tree_phys("Fatal Scratch", "A strong 360 AOE attack that deals damage as recoil if missed", .CLEAVE, .CLEAVE, 90, 175, 0, 300, 7, 1)
	s.targeting.aoe_mode = .SELF_CENTERED

	// ── Bash tree (melee) — Stun is registered further down as a sample ──
	tree_phys("Ground Shock", "Attack + chance to interrupt casting (blunt, axe, wand)", .BASH, .BASH, 26, 38, 0, 18, 2, 1)
	s = tree_phys("Stun Hammer", "Attack and AOE stun (blunt, 2H blunt)", .BASH, .BASH, 0, 30, 0, 15, 2, 1)
	s.req = [4]Prereq{{.BASH, 41}, {.EXORCISM, 21}, {}, {}}
	s.targeting.aoe_mode = .SELF_CENTERED
	tree_phys("Shatter Armor", "Attack with a chance to break enemy armor and interrupt casting (blunt, 2H blunt, wand)", .BASH, .BASH, 50, 30, 0, 15, 2, 1)
	// Shield Break: utility (breaks block) — no damage component.
	shieldbreak_p, _ := registry_reserve(&skill_registry, "Shield Break")
	shieldbreak_p.source = .TREE
	shieldbreak_p.sub_cat = .BASH
	shieldbreak_p.kind = .UTILITY
	shieldbreak_p.description = "Knock target out of blocking or defensive march"
	shieldbreak_p.req = Skill_Points_Req(61)
	shieldbreak_p.cost_mp = 22
	shieldbreak_p.cooldown_s = 10
	s = tree_phys("Subvert", "Attack that scales with enemy defense", .BASH, .BASH, 71, 69, 0.5, 25, 3, 1)
	s.outcomes[0] = Damage_Params{sub_type = .BASH, base_power = 3, bonus_vs_low_def = true}
	tree_phys("Rock Crash", "Strong single target attack", .BASH, .BASH, 81, 120, 2.5, 60, 5, 1)

	// ── Defend tree (melee) — blocking/defensive buffs + shield skills ───
	blocking_p, _ := registry_reserve(&skill_registry, "Blocking")
	blocking_p.source = .TREE
	blocking_p.sub_cat = .DEFEND
	blocking_p.kind = .BUFF
	blocking_p.description = "Stationary blocking mode"
	blocking_p.req = Skill_Points_Req(8)
	blocking_p.cost_mp = 5
	blocking_p.cooldown_s = 2
	blocking_p.requires.self_only = true
	blocking_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, effect = Status_Flag_Set{.BLOCKING_STANCE}}
	blocking_p.outcome_count = 1
	s = tree_phys("Shield Bash", "Trip enemies who attack you while blocking", .DEFEND, .BASH, 12, 14, 0, 10, 1, 1)
	s.duration_s = 2
	s.requires.block_only = true
	// Parapet: +crit resist, -dodge.
	parapet_p, _ := registry_reserve(&skill_registry, "Parapet")
	parapet_p.source = .TREE
	parapet_p.sub_cat = .DEFEND
	parapet_p.kind = .BUFF
	parapet_p.description = "Increase critical hit resistance, lowers dodge"
	parapet_p.req = Skill_Points_Req(21)
	parapet_p.cost_mp = 25
	parapet_p.cast_time_s = 2
	parapet_p.cooldown_s = 30
	parapet_p.duration_s = 120
	parapet_p.requires.self_only = true
	parapet_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 120, effect = Stat_Mod{stat = .CRIT_RESIST, mult = 0.7}}
	parapet_p.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = true, duration_s = 120, effect = Stat_Mod{stat = .DODGE, delta = -50}}
	parapet_p.outcome_count = 2
	// Auto-guard: chance to reduce damage (shield).
	autoguard_p, _ := registry_reserve(&skill_registry, "Auto-guard")
	autoguard_p.source = .TREE
	autoguard_p.sub_cat = .DEFEND
	autoguard_p.kind = .BUFF
	autoguard_p.description = "Chance to reduce damage taken (shield)"
	autoguard_p.req = Skill_Points_Req(26)
	autoguard_p.cost_mp = 20
	autoguard_p.cooldown_s = 30
	autoguard_p.duration_s = 120
	autoguard_p.requires.self_only = true
	autoguard_p.requires.shield = true
	autoguard_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 120, effect = Stat_Mod{stat = .BLOCK_CHANCE, mult = 0.3}}
	autoguard_p.outcome_count = 1
	// Shield Charge: charge + knockdown (block-only).
	s = tree_phys("Shield Charge", "Charge forward and knockdown enemies in your path", .DEFEND, .BASH, 31, 18, 0, 10, 1, 1)
	s.requires.block_only = true
	s.outcomes[1] = Apply_Effect{polarity = .BUFF, to_self = true, effect = Status_Flag_Set{.SHIELD_CHARGE}}
	s.outcome_count = 2
	// Defensive March: move while blocking.
	dmarch_p, _ := registry_reserve(&skill_registry, "Defensive March")
	dmarch_p.source = .TREE
	dmarch_p.sub_cat = .DEFEND
	dmarch_p.kind = .BUFF
	dmarch_p.description = "Move while blocking"
	dmarch_p.req = Skill_Points_Req(41)
	dmarch_p.cost_mp = 10
	dmarch_p.cooldown_s = 5
	dmarch_p.requires.self_only = true
	dmarch_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, effect = Status_Flag_Set{.DEFENSIVE_MARCH}}
	dmarch_p.outcome_count = 1
	// Guardian: take damage for a party member.
	guardian_p, _ := registry_reserve(&skill_registry, "Guardian")
	guardian_p.source = .TREE
	guardian_p.sub_cat = .DEFEND
	guardian_p.kind = .BUFF
	guardian_p.description = "Take all damage for a party member"
	guardian_p.req = Skill_Points_Req(54)
	guardian_p.cost_mp = 16
	guardian_p.cast_time_s = 4
	guardian_p.cooldown_s = 10
	guardian_p.duration_s = 300
	guardian_p.requires.self_only = true
	guardian_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 300, effect = Status_Flag_Set{.DAMAGE_REDIRECT}}
	guardian_p.outcome_count = 1
	// Eternal Dirge: AOE that prevents all skills while active.
	etdirge_p, _ := registry_reserve(&skill_registry, "Eternal Dirge")
	etdirge_p.source = .TREE
	etdirge_p.sub_cat = .DEFEND
	etdirge_p.kind = .DEBUFF
	etdirge_p.description = "AOE that prevents all skills from being used while active"
	etdirge_p.req = Skill_Points_Req(61)
	etdirge_p.cost_mp = 74
	etdirge_p.cooldown_s = 20
	etdirge_p.targeting.aoe_mode = .SELF_CENTERED
	etdirge_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = Status_Flag_Set{.PREVENT_SPELL_CAST}}
	etdirge_p.outcome_count = 1

	// ── Shot tree (technique) — ranged phys, mostly bow/crossbow ────────
	// Flaming Arrow: physical + fire element.
	s = tree_phys("Flaming Arrow", "Ranged attack with a chance to burn (bow, crossbow)", .SHOT, .FIRE, 8, 12, 0, 30, 1, 1)
	s.requires.weapon[0] = .BOW; s.requires.weapon[1] = .CROSSBOW; s.requires.weapon_count = 2
	s.outcomes[0] = Damage_Params{sub_type = .FIRE, base_power = 1, elemental_power = 1}
	s = tree_phys("Cobra Arrow", "Ranged attack with a chance to poison (bow, crossbow)", .SHOT, .RANGED, 12, 12, 0, 30, 1, 1)
	s.requires.weapon[0] = .BOW; s.requires.weapon[1] = .CROSSBOW; s.requires.weapon_count = 2
	s = tree_phys("Arrow Rain", "AOE attack over target (bow)", .SHOT, .RANGED, 26, 15, 1, 5, 1, 1)
	s.targeting = {aoe_mode = .TARGET_CENTERED, aoe_radius = 5, pulse_count = 3, pulse_interval_ms = 1000}
	s.requires.weapon[0] = .BOW; s.requires.weapon_count = 1
	s = tree_phys("Multi Shot", "Fire five arrows at once (crossbow)", .SHOT, .RANGED, 0, 20, 0, 30, 1, 1)
	s.req = [4]Prereq{{.SHOT, 41}, {.TRAP, 21}, {}, {}}
	s.requires.weapon[0] = .CROSSBOW; s.requires.weapon_count = 1
	s = tree_phys("Charge Shot", "Deal damage and knockback target (bow, crossbow)", .SHOT, .RANGED, 0, 18, 0, 30, 1, 1)
	s.req = [4]Prereq{{.SHOT, 50}, {.TRAP, 21}, {}, {}}
	s.outcomes[0] = Damage_Params{sub_type = .RANGED, base_power = 1, knockback = 3}
	s.requires.weapon[0] = .BOW; s.requires.weapon[1] = .CROSSBOW; s.requires.weapon_count = 2
	// Silence Arrow: damage + silence debuff.
	s = tree_phys("Silence Arrow", "Shoot arrow with a chance to silence target (bow)", .SHOT, .RANGED, 54, 33, 0, 10, 2, 1)
	s.requires.weapon[0] = .BOW; s.requires.weapon_count = 1
	s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 5, effect = CC_Effect{kind = .SILENCE}}
	s.outcome_count = 2
	s = tree_phys("Arrow Storm", "AOE attack over target (bow), replaces Arrow Rain", .SHOT, .RANGED, 61, 15, 1, 5, 2, 1)
	s.targeting = {aoe_mode = .TARGET_CENTERED, aoe_radius = 5, pulse_count = 3, pulse_interval_ms = 1000}
	s.requires.weapon[0] = .BOW; s.requires.weapon_count = 1
	// Pinning Arrow: utility (root from behind) — no damage component.
	pin_p, _ := registry_reserve(&skill_registry, "Pinning Arrow")
	pin_p.source = .TREE; pin_p.sub_cat = .SHOT; pin_p.kind = .UTILITY
	pin_p.description = "Pin target in place if hit from the back (bow, crossbow)"
	pin_p.req = Skill_Points_Req(71); pin_p.cost_mp = 49; pin_p.cooldown_s = 30
	pin_p.requires.weapon[0] = .BOW; pin_p.requires.weapon[1] = .CROSSBOW; pin_p.requires.weapon_count = 2
	s = tree_phys("Piercing Shot", "Shoot an arrow that pierces the target", .SHOT, .RANGED, 81, 22, 0, 8, 1, 1)
	s.requires.weapon[0] = .BOW; s.requires.weapon[1] = .CROSSBOW; s.requires.weapon_count = 2
	s = tree_phys("Cataract", "Deal increased damage to the front of target, reduce damage taken from the front, but increase damage taken from the back. reduces movement speed", .SHOT, .RANGED, 90, 54, 0, 90, 3, 1)
	s.requires.weapon[0] = .BOW; s.requires.weapon[1] = .CROSSBOW; s.requires.weapon_count = 2

	// ── Alchemy tree (technique) — item crafting + weapon poison ────────
	poisonmk_p, _ := registry_reserve(&skill_registry, "Poison Making")
	poisonmk_p.source = .TREE; poisonmk_p.sub_cat = .ALCHEMY; poisonmk_p.kind = .UTILITY
	poisonmk_p.description = "Creates Poison vials (Deadly Nightshade x1, Container x1)"
	poisonmk_p.req = Skill_Points_Req(8); poisonmk_p.cost_mp = 3; poisonmk_p.cast_time_s = 1
	poisonmk_p.outcomes[0] = Create_Item{item_id = "poison_vial", quantity = 1, consume = {{"deadly_nightshade", 1}, {"container", 1}, {}, {}}}
	poisonmk_p.outcome_count = 1
	toxify_p, _ := registry_reserve(&skill_registry, "Toxify")
	toxify_p.source = .TREE; toxify_p.sub_cat = .ALCHEMY; toxify_p.kind = .BUFF
	toxify_p.description = "Coat weapon with poison"
	toxify_p.req = Skill_Points_Req(12); toxify_p.cost_mp = 15; toxify_p.cast_time_s = 2; toxify_p.cooldown_s = 10; toxify_p.duration_s = 120
	toxify_p.requires.self_only = true
	toxify_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 120, effect = Weapon_Aura{element = .POISON, formula = "toxify"}}
	toxify_p.outcome_count = 1
	serum_p, _ := registry_reserve(&skill_registry, "Serum")
	serum_p.source = .TREE; serum_p.sub_cat = .ALCHEMY; serum_p.kind = .UTILITY
	serum_p.description = "Create an antidote to remove poison (Antidote Herb x1, Container x1)"
	serum_p.req = Skill_Points_Req(26); serum_p.cost_mp = 3; serum_p.cast_time_s = 1
	serum_p.outcomes[0] = Create_Item{item_id = "antidote", quantity = 1, consume = {{"antidote_herb", 1}, {"container", 1}, {}, {}}}
	serum_p.outcome_count = 1
	potion_p, _ := registry_reserve(&skill_registry, "Potion Crafting")
	potion_p.source = .TREE; potion_p.sub_cat = .ALCHEMY; potion_p.kind = .UTILITY
	potion_p.description = "Create a mysterious potion to cure disease, silence, and burn (Moonlight Herb x1, Aquilegia x1, Container x1)"
	potion_p.req = Skill_Points_Req(41); potion_p.cost_mp = 3
	potion_p.outcomes[0] = Create_Item{item_id = "mysterious_potion", quantity = 1, consume = {{"moonlight_herb", 1}, {"aquilegia", 1}, {"container", 1}, {}}}
	potion_p.outcome_count = 1
	// Befuddle: reduce target casting speed.
	befuddle_p, _ := registry_reserve(&skill_registry, "Befuddle")
	befuddle_p.source = .TREE; befuddle_p.sub_cat = .ALCHEMY; befuddle_p.kind = .DEBUFF
	befuddle_p.description = "Strike to reduce target's casting speed"
	befuddle_p.req = Skill_Points_Req(50); befuddle_p.cost_mp = 31; befuddle_p.cooldown_s = 0; befuddle_p.duration_s = 150
	befuddle_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 150, effect = Stat_Mod{stat = .CAST_SPEED, mult = 0.85}}
	befuddle_p.outcome_count = 1
	tree_passive("Toxic Aura (Passive)", "Increased damage with poison when using Toxify", .ALCHEMY, 61)
	// Surveillance: see enemy traps.
	surv_p, _ := registry_reserve(&skill_registry, "Surveillance")
	surv_p.source = .TREE; surv_p.sub_cat = .ALCHEMY; surv_p.kind = .BUFF
	surv_p.description = "See enemy traps for 10 seconds"
	surv_p.req = Skill_Points_Req(71); surv_p.cost_mp = 44; surv_p.cast_time_s = 0.5; surv_p.cooldown_s = 20; surv_p.duration_s = 10
	surv_p.requires.self_only = true
	// Sniper's Serum: accuracy + crit immunity buff.
	sniper_p, _ := registry_reserve(&skill_registry, "Sniper's Serum")
	sniper_p.source = .TREE; sniper_p.sub_cat = .ALCHEMY; sniper_p.kind = .BUFF
	sniper_p.description = "Drink a mysterious potion to gain a temporary buff, increase accuracy, prevent taking critical hits"
	sniper_p.req = Skill_Points_Req(81); sniper_p.cost_mp = 1; sniper_p.cooldown_s = 60; sniper_p.duration_s = 30
	sniper_p.requires.self_only = true
	// Overdose: party heal on potion drink.
	overdose_p, _ := registry_reserve(&skill_registry, "Overdose")
	overdose_p.source = .TREE; overdose_p.sub_cat = .ALCHEMY; overdose_p.kind = .PARTY_HEAL
	overdose_p.description = "Drinking a potion will heal the party for a large amount"
	overdose_p.req = Skill_Points_Req(90); overdose_p.cost_mp = 25; overdose_p.cooldown_s = 45

	// ── Assassination tree (technique) — dagger/knuckles burst ──────────
	tree_phys("Backstab", "Attack enemy from behind", .ASSASSINATION, .SLASH, 8, 15, 0, 30, 1, 1)
	s = tree_phys("Dagger Throw", "Throw a dagger at target (dagger)", .ASSASSINATION, .RANGED, 12, 10, 0, 5, 1, 1)
	s.targeting.range = 12; s.requires.weapon[0] = .DAGGER; s.requires.weapon_count = 1
	// Rush: each attack hits twice (extra hit) but take more damage.
	rush_p, _ := registry_reserve(&skill_registry, "Rush")
	rush_p.source = .TREE; rush_p.sub_cat = .ASSASSINATION; rush_p.kind = .BUFF
	rush_p.description = "Each attack hits twice, caster takes more damage (dagger, knuckles)"
	rush_p.req = Skill_Points_Req(26); rush_p.cost_mp = 30; rush_p.cooldown_s = 90; rush_p.duration_s = 20
	rush_p.requires.self_only = true
	rush_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 20, effect = Status_Flag_Set{.EXTRA_HIT}}
	rush_p.outcome_count = 1
	// Blindside: damage + trip.
	s = tree_phys("Blindside", "While cloaked, trips target, does not remove cloak", .ASSASSINATION, .SLASH, 41, 15, 0, 10, 1, 1)
	s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 2, effect = CC_Effect{kind = .TRIP}}
	s.outcome_count = 2
	s = tree_phys("Pierce Armor", "Attack that ignores armor, bonus damage against knocked down targets", .ASSASSINATION, .SLASH, 54, 15, 0, 10, 1, 1)
	s.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 1, ignore_armor = true}
	tree_phys("Double-Cross", "Attack back of target to reset all skill cooldowns (dagger, knuckles), only against other players", .ASSASSINATION, .SLASH, 71, 58, 0, 55, 3, 1)
	tree_phys("Killing Time", "Can be used while hiding, deals a heavy blow from behind", .ASSASSINATION, .SLASH, 81, 20, 0, 15, 3, 1)
	// Overkill: killed target cannot be revived.
	overkill_p, _ := registry_reserve(&skill_registry, "Overkill")
	overkill_p.source = .TREE; overkill_p.sub_cat = .ASSASSINATION; overkill_p.kind = .DAMAGE_PHYSICAL
	overkill_p.description = "Killed target cannot be revived"
	overkill_p.req = Skill_Points_Req(90); overkill_p.cost_mp = 70; overkill_p.cooldown_s = 60
	overkill_p.outcomes[0] = Damage_Params{sub_type = .SLASH, base_power = 3}
	overkill_p.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = Status_Flag_Set{.PREVENT_RESURRECT}}
	overkill_p.outcome_count = 2

	// ── Trap tree (technique) — magical traps, consume 'trap' item ──────
	// Disarm: remove nearby traps (ground-targeted, no damage).
	disarm_p, _ := registry_reserve(&skill_registry, "Disarm")
	disarm_p.source = .TREE; disarm_p.sub_cat = .TRAP; disarm_p.kind = .UTILITY
	disarm_p.description = "Remove nearby traps"
	disarm_p.req = Skill_Points_Req(8); disarm_p.cost_mp = 10; disarm_p.cast_time_s = 1; disarm_p.cooldown_s = 10
	disarm_p.targeting.aoe_mode = .GROUND_TARGETED
	// Tangled Legs: root (consumes trap).
	tangled_p, _ := registry_reserve(&skill_registry, "Tangled Legs")
	tangled_p.source = .TREE; tangled_p.sub_cat = .TRAP; tangled_p.kind = .DEBUFF
	tangled_p.description = "Root target for 3 seconds (Trap x1)"
	tangled_p.req = Skill_Points_Req(16); tangled_p.cost_mp = 20; tangled_p.cast_time_s = 1.5; tangled_p.cooldown_s = 3
	tangled_p.requires.consumable = "trap"; tangled_p.requires.consume_qty = 1
	tangled_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 3, effect = CC_Effect{kind = .ROOT}}
	tangled_p.outcome_count = 1
	// Plant Mine: magical fire AOE trap.
	plantmine_p, _ := registry_reserve(&skill_registry, "Plant Mine")
	plantmine_p.source = .TREE; plantmine_p.sub_cat = .TRAP; plantmine_p.kind = .DAMAGE_MAGICAL
	plantmine_p.description = "Plant a mine that explodes on target (Trap x1)"
	plantmine_p.req = Skill_Points_Req(26); plantmine_p.cost_mp = 30; plantmine_p.cast_time_s = 1.5; plantmine_p.cooldown_s = 3
	plantmine_p.targeting.aoe_mode = .SELF_CENTERED; plantmine_p.targeting.aoe_radius = 3
	plantmine_p.requires.consumable = "trap"; plantmine_p.requires.consume_qty = 1
	plantmine_p.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = .FIRE, base_power = 2}
	plantmine_p.outcome_count = 1
	worm_p, _ := registry_reserve(&skill_registry, "Worm Bomb")
	worm_p.source = .TREE; worm_p.sub_cat = .TRAP; worm_p.kind = .DAMAGE_MAGICAL
	worm_p.description = "Trap that crawls forward and explodes on target (Trap x1)"
	worm_p.req = Skill_Points_Req(41); worm_p.cost_mp = 33; worm_p.cast_time_s = 3; worm_p.cooldown_s = 5
	worm_p.requires.consumable = "trap"; worm_p.requires.consume_qty = 1
	worm_p.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = .FIRE, base_power = 2}
	worm_p.outcome_count = 1
	// Safe Zone: field preventing field spells.
	safezone_p, _ := registry_reserve(&skill_registry, "Safe Zone")
	safezone_p.source = .TREE; safezone_p.sub_cat = .TRAP; safezone_p.kind = .BUFF
	safezone_p.description = "Create a field that prevents field spells from being used or doing damage"
	safezone_p.req = Skill_Points_Req(50); safezone_p.cost_mp = 46; safezone_p.cast_time_s = 1.5; safezone_p.cooldown_s = 8
	safezone_p.targeting.aoe_mode = .SELF_CENTERED; safezone_p.targeting.aoe_radius = 2
	safezone_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, effect = Status_Flag_Set{.PREVENT_FIELD_SPELLS}}
	safezone_p.outcome_count = 1
	stoneprison_p, _ := registry_reserve(&skill_registry, "Stone Prison")
	stoneprison_p.source = .TREE; stoneprison_p.sub_cat = .TRAP; stoneprison_p.kind = .UTILITY
	stoneprison_p.description = "Create a stone prison around mounted target (Trap x1)"
	stoneprison_p.req = Skill_Points_Req(61); stoneprison_p.cost_mp = 48; stoneprison_p.cast_time_s = 1.5; stoneprison_p.cooldown_s = 3
	stoneprison_p.targeting.aoe_mode = .GROUND_TARGETED
	stoneprison_p.requires.consumable = "trap"; stoneprison_p.requires.consume_qty = 1
	// Mind Warp: reduce target MP.
	mindwarp_p, _ := registry_reserve(&skill_registry, "Mind Warp")
	mindwarp_p.source = .TREE; mindwarp_p.sub_cat = .TRAP; mindwarp_p.kind = .DEBUFF
	mindwarp_p.description = "Trap that reduces target's MP (Trap x1)"
	mindwarp_p.req = Skill_Points_Req(71); mindwarp_p.cost_mp = 48; mindwarp_p.cast_time_s = 1.5; mindwarp_p.cooldown_s = 3
	mindwarp_p.requires.consumable = "trap"; mindwarp_p.requires.consume_qty = 1
	mindwarp_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = DOT_Effect{element = .MP_DRAIN, mp_drain = 50}}
	mindwarp_p.outcome_count = 1
	// Poison Bomb: magical + poison DOT.
	poisonbomb_p, _ := registry_reserve(&skill_registry, "Poison Bomb")
	poisonbomb_p.source = .TREE; poisonbomb_p.sub_cat = .TRAP; poisonbomb_p.kind = .DAMAGE_MAGICAL
	poisonbomb_p.description = "Trap that explodes on target, deals damage and poisons (Trap x1)"
	poisonbomb_p.req = Skill_Points_Req(81); poisonbomb_p.cost_mp = 48; poisonbomb_p.cast_time_s = 8; poisonbomb_p.cooldown_s = 3
	poisonbomb_p.requires.consumable = "trap"; poisonbomb_p.requires.consume_qty = 1
	poisonbomb_p.outcomes[0] = Damage_Params{damage_type = .MAGICAL, base_power = 2}
	poisonbomb_p.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = DOT_Effect{element = .POISON}}
	poisonbomb_p.outcome_count = 2
	// Oil Bomb: magical fire + burn.
	oilbomb_p, _ := registry_reserve(&skill_registry, "Oil Bomb")
	oilbomb_p.source = .TREE; oilbomb_p.sub_cat = .TRAP; oilbomb_p.kind = .DAMAGE_MAGICAL
	oilbomb_p.description = "Trap that moves forward and explodes on target, deals damage (Trap x1)"
	oilbomb_p.req = Skill_Points_Req(90); oilbomb_p.cost_mp = 62; oilbomb_p.cast_time_s = 6; oilbomb_p.cooldown_s = 30
	oilbomb_p.requires.consumable = "trap"; oilbomb_p.requires.consume_qty = 1
	oilbomb_p.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = .FIRE, base_power = 3}
	oilbomb_p.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 5, effect = DOT_Effect{element = .BURN}}
	oilbomb_p.outcome_count = 2

	// ── Dodge tree (technique) — evasion + the Dash/Sprint/Spurt chain ──
	// Backstep: +100 dodge for 1s.
	backstep_p, _ := registry_reserve(&skill_registry, "Backstep")
	backstep_p.category_level = true
	backstep_p.source = .TREE; backstep_p.sub_cat = .DODGE; backstep_p.kind = .BUFF
	backstep_p.description = "Step back and increase dodge by 100 for 1 second"
	backstep_p.req = Skill_Points_Req(3); backstep_p.cost_mp = 5; backstep_p.cooldown_s = 3; backstep_p.duration_s = 1
	backstep_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 1, effect = Stat_Mod{stat = .DODGE, delta = 100}}
	backstep_p.outcome_count = 1
	// Dash (move-speed buff) — already registered as a sample below; the
	// Dodge-tree entry is identical (combo chain with Sprint/Spurt).
	// Quick Step: +13 dodge.
	qstep_p, _ := registry_reserve(&skill_registry, "Quick Step")
	qstep_p.source = .TREE; qstep_p.sub_cat = .DODGE; qstep_p.kind = .BUFF
	qstep_p.description = "Increased dodge"
	qstep_p.req = Skill_Points_Req(16); qstep_p.cost_mp = 35; qstep_p.cast_time_s = 0.5; qstep_p.cooldown_s = 90; qstep_p.duration_s = 60
	qstep_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 60, effect = Stat_Mod{stat = .DODGE, delta = 13}}
	qstep_p.outcome_count = 1
	// Tangled Fingers: reduce target accuracy.
	tfingers_p, _ := registry_reserve(&skill_registry, "Tangled Fingers")
	tfingers_p.source = .TREE; tfingers_p.sub_cat = .DODGE; tfingers_p.kind = .DEBUFF
	tfingers_p.description = "Reduce target's accuracy"
	tfingers_p.req = Skill_Points_Req(21); tfingers_p.cost_mp = 22; tfingers_p.cast_time_s = 0.8; tfingers_p.cooldown_s = 30; tfingers_p.duration_s = 30
	tfingers_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 30, effect = Stat_Mod{stat = .ACCURACY, mult = 0.85}}
	tfingers_p.outcome_count = 1
	tree_passive("Reinforce (Passive)", "Knockdown/Knockback/Freeze resistance", .DODGE, 26)
	// Avoidance: increased dodge until hit twice.
	avoid_p, _ := registry_reserve(&skill_registry, "Avoidance")
	avoid_p.source = .TREE; avoid_p.sub_cat = .DODGE; avoid_p.kind = .BUFF
	avoid_p.description = "Increased dodge until hit by two physical attacks"
	avoid_p.req = Skill_Points_Req(41); avoid_p.cost_mp = 38; avoid_p.cast_time_s = 0.5; avoid_p.cooldown_s = 30
	avoid_p.requires.self_only = true
	tree_passive("Intuition (Passive)", "Chance to dodge magic", .DODGE, 50)
	// Bolster / Move Stream: Dash on target / party (move-speed 200).
	bolster_p, _ := registry_reserve(&skill_registry, "Bolster")
	bolster_p.source = .TREE; bolster_p.sub_cat = .DODGE; bolster_p.kind = .BUFF
	bolster_p.description = "Cast Dash on target"
	bolster_p.req = Skill_Points_Req(66); bolster_p.cost_mp = 29; bolster_p.cast_time_s = 1; bolster_p.cooldown_s = 1.5; bolster_p.duration_s = 2
	bolster_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = false, duration_s = 2, effect = Stat_Mod{stat = .MOVE_SPEED, mult = 200}}
	bolster_p.outcome_count = 1
	mstream_p, _ := registry_reserve(&skill_registry, "Move Stream")
	mstream_p.source = .TREE; mstream_p.sub_cat = .DODGE; mstream_p.kind = .BUFF
	mstream_p.description = "Cast Dash on all party members in range"
	mstream_p.req = Skill_Points_Req(81); mstream_p.cost_mp = 60; mstream_p.cooldown_s = 25; mstream_p.duration_s = 2
	mstream_p.targeting.aoe_mode = .SELF_CENTERED; mstream_p.targeting.aoe_radius = 8
	mstream_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = false, duration_s = 2, effect = Stat_Mod{stat = .MOVE_SPEED, mult = 200}}
	mstream_p.outcome_count = 1
	// Sprint & Spurt: the Dash combo chain (reqPoints 90, identical to Dash).
	sprint_p, _ := registry_reserve(&skill_registry, "Sprint")
	sprint_p.source = .TREE; sprint_p.sub_cat = .DODGE; sprint_p.kind = .BUFF
	sprint_p.description = "Dash forward"
	sprint_p.req = Skill_Points_Req(90); sprint_p.cost_mp = 18; sprint_p.cooldown_s = 30; sprint_p.duration_s = 2
	sprint_p.requires.self_only = true
	sprint_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 2, effect = Stat_Mod{stat = .MOVE_SPEED, mult = 200}}
	sprint_p.outcome_count = 1
	spurt_p, _ := registry_reserve(&skill_registry, "Spurt")
	spurt_p.source = .TREE; spurt_p.sub_cat = .DODGE; spurt_p.kind = .BUFF
	spurt_p.description = "Dash forward"
	spurt_p.req = Skill_Points_Req(90); spurt_p.cost_mp = 18; spurt_p.cooldown_s = 30; spurt_p.duration_s = 2
	spurt_p.requires.self_only = true
	spurt_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 2, effect = Stat_Mod{stat = .MOVE_SPEED, mult = 200}}
	spurt_p.outcome_count = 1

	// ── Grace tree (prayer) — healing + cleansing ───────────────────────
	firstaid_p, _ := registry_reserve(&skill_registry, "First Aid")
	firstaid_p.source = .TREE; firstaid_p.sub_cat = .GRACE; firstaid_p.kind = .HEAL
	firstaid_p.description = "Restore HP based on level, expertise, and INT"
	firstaid_p.req = Skill_Points_Req(8); firstaid_p.cost_mp = 28; firstaid_p.cast_time_s = 1; firstaid_p.cooldown_s = 4
	hp0: Heal_Params; hp0.scope = .SINGLE; hp0.base_amount = 50; hp0.stat_mult[.SPI] = 0.3; hp0.stat_mult[.INT] = 0.6
	firstaid_p.outcomes[0] = hp0; firstaid_p.outcome_count = 1
	cleanse_p, _ := registry_reserve(&skill_registry, "Cleanse")
	cleanse_p.source = .TREE; cleanse_p.sub_cat = .GRACE; cleanse_p.kind = .UTILITY
	cleanse_p.description = "Cure Poison"
	cleanse_p.req = Skill_Points_Req(12); cleanse_p.cost_mp = 15; cleanse_p.cast_time_s = 1; cleanse_p.cooldown_s = 3
	regen_p, _ := registry_reserve(&skill_registry, "Regenerate")
	regen_p.source = .TREE; regen_p.sub_cat = .GRACE; regen_p.kind = .BUFF
	regen_p.description = "Every few seconds, restore a party member's HP based on SPI and class specialty"
	regen_p.req = Skill_Points_Req(21); regen_p.cost_mp = 40; regen_p.cast_time_s = 1.5; regen_p.cooldown_s = 5; regen_p.duration_s = 120
	regen_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = false, duration_s = 120, effect = Hot_Effect{base = 15, spi_scale = 0.8, prof_stat = .GRACE}}
	regen_p.outcome_count = 1
	vivify_p, _ := registry_reserve(&skill_registry, "Vivify")
	vivify_p.source = .TREE; vivify_p.sub_cat = .GRACE; vivify_p.kind = .UTILITY
	vivify_p.description = "Cure sleep/knock out/freeze"
	vivify_p.req = Skill_Points_Req(26); vivify_p.cost_mp = 18; vivify_p.cast_time_s = 1; vivify_p.cooldown_s = 3
	restor_p, _ := registry_reserve(&skill_registry, "Restoration")
	restor_p.source = .TREE; restor_p.sub_cat = .GRACE; restor_p.kind = .PARTY_HEAL
	restor_p.description = "Restore party HP over time based on SPI and class specialty"
	restor_p.req = Skill_Points_Req(41); restor_p.cost_mp = 90; restor_p.cast_time_s = 3; restor_p.cooldown_s = 20; restor_p.duration_s = 120
	restor_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = false, duration_s = 120, effect = Hot_Effect{base = 15, spi_scale = 0.8, prof_stat = .GRACE}}
	restor_p.outcome_count = 1
	haura_p, _ := registry_reserve(&skill_registry, "Healing Aura")
	haura_p.source = .TREE; haura_p.sub_cat = .GRACE; haura_p.kind = .PARTY_HEAL
	haura_p.description = "Heal party members in range"
	haura_p.req = Skill_Points_Req(54); haura_p.cost_mp = 256; haura_p.cast_time_s = 1; haura_p.cooldown_s = 30
	haura_p.targeting.aoe_mode = .SELF_CENTERED; haura_p.targeting.aoe_radius = 12
	hp1: Heal_Params; hp1.scope = .PARTY; hp1.base_amount = 500
	haura_p.outcomes[0] = hp1; haura_p.outcome_count = 1
	purify_p, _ := registry_reserve(&skill_registry, "Purify")
	purify_p.source = .TREE; purify_p.sub_cat = .GRACE; purify_p.kind = .BUFF
	purify_p.description = "Cures all debuffs and increases resistance to debuffs for 15 seconds"
	purify_p.req = Skill_Points_Req(71); purify_p.cost_mp = 76; purify_p.cast_time_s = 1.5; purify_p.cooldown_s = 35; purify_p.duration_s = 15
	purify_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 15, effect = Status_Flag_Set{.DISPEL}}
	purify_p.outcomes[1] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 15, effect = Stat_Mod{stat = .DEBUFF_RESIST, mult = 0.5}}
	purify_p.outcome_count = 2
	sac_p, _ := registry_reserve(&skill_registry, "Sacrifice")
	sac_p.source = .TREE; sac_p.sub_cat = .GRACE; sac_p.kind = .PARTY_HEAL
	sac_p.description = "Sacrifice self to restore a party member's HP, consumes 5 Holy Waters"
	sac_p.req = Skill_Points_Req(81); sac_p.cooldown_s = 300
	sac_p.requires.consumable = "holy_water"; sac_p.requires.consume_qty = 5

	// ── Blessing tree (prayer) — Lapis Mediow is registered below as a
	//    sample; the rest of the tree is here ────────────────────────────
	velox_p, _ := registry_reserve(&skill_registry, "Velox")
	velox_p.source = .TREE; velox_p.sub_cat = .BLESSING; velox_p.kind = .BUFF
	velox_p.description = "Increase player's attack speed"
	velox_p.req = Skill_Points_Req(8); velox_p.cost_mp = 26; velox_p.cast_time_s = 0.5; velox_p.cooldown_s = 1.5; velox_p.duration_s = 480
	velox_p.requires.self_only = true
	velox_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 480, effect = Stat_Mod{stat = .ATTACK_SPEED, mult = 1.3}}
	velox_p.outcome_count = 1
	impend_p, _ := registry_reserve(&skill_registry, "Impedimentia")
	impend_p.source = .TREE; impend_p.sub_cat = .BLESSING; impend_p.kind = .DEBUFF
	impend_p.description = "Reduce target's movement speed"
	impend_p.req = Skill_Points_Req(21); impend_p.cost_mp = 33; impend_p.cast_time_s = 1.5; impend_p.cooldown_s = 10; impend_p.duration_s = 10
	impend_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 10, effect = Stat_Mod{stat = .MOVE_SPEED, mult = 0.85}}
	impend_p.outcome_count = 1
	gbarrier_p, _ := registry_reserve(&skill_registry, "Group Barrier")
	gbarrier_p.source = .TREE; gbarrier_p.sub_cat = .BLESSING; gbarrier_p.kind = .BUFF
	gbarrier_p.description = "Physical damage reduction on all party members in range. Reduction based on caster's Blessing proficiency"
	gbarrier_p.req = Skill_Points_Req(26); gbarrier_p.cost_mp = 70; gbarrier_p.cast_time_s = 1; gbarrier_p.cooldown_s = 1.5; gbarrier_p.duration_s = 120
	gbarrier_p.targeting.aoe_mode = .SELF_CENTERED
	aquael_p, _ := registry_reserve(&skill_registry, "Aqua Elimus")
	aquael_p.source = .TREE; aquael_p.sub_cat = .BLESSING; aquael_p.kind = .UTILITY
	aquael_p.description = "Craft one Holy Water (Container x1)"
	aquael_p.req = Skill_Points_Req(41); aquael_p.cost_mp = 4; aquael_p.cast_time_s = 1
	aquael_p.outcomes[0] = Create_Item{item_id = "holy_water", quantity = 1, consume = {{"container", 1}, {}, {}, {}}}
	aquael_p.outcome_count = 1
	saltio_p, _ := registry_reserve(&skill_registry, "Saltio")
	saltio_p.source = .TREE; saltio_p.sub_cat = .BLESSING; saltio_p.kind = .BUFF
	saltio_p.description = "Cut base cast time of all skills by 50%"
	saltio_p.req = Skill_Points_Req(54); saltio_p.cost_mp = 37; saltio_p.cooldown_s = 5; saltio_p.duration_s = 90
	saltio_p.requires.self_only = true
	saltio_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 90, effect = Stat_Mod{stat = .CAST_SPEED, mult = 2.0}}
	saltio_p.outcome_count = 1
	bprayer_p, _ := registry_reserve(&skill_registry, "Battle Prayer")
	bprayer_p.source = .TREE; bprayer_p.sub_cat = .BLESSING; bprayer_p.kind = .BUFF
	bprayer_p.description = "Increase player's STR, AGI, and INT"
	bprayer_p.req = Skill_Points_Req(61); bprayer_p.cost_mp = 78; bprayer_p.cast_time_s = 0.5; bprayer_p.cooldown_s = 1.5; bprayer_p.duration_s = 480
	bprayer_p.requires.self_only = true
	bprayer_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 480, effect = Stat_Mod{stat = .STR, delta = 9}}
	bprayer_p.outcomes[1] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 480, effect = Stat_Mod{stat = .AGI, delta = 9}}
	bprayer_p.outcomes[2] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 480, effect = Stat_Mod{stat = .INT, delta = 9}}
	bprayer_p.outcome_count = 3
	locom_p, _ := registry_reserve(&skill_registry, "Locomitigation")
	locom_p.source = .TREE; locom_p.sub_cat = .BLESSING; locom_p.kind = .BUFF
	locom_p.description = "Reduce party members' critical damage taken"
	locom_p.req = Skill_Points_Req(81); locom_p.cost_mp = 100; locom_p.cast_time_s = 1; locom_p.cooldown_s = 10; locom_p.duration_s = 120
	locom_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = false, duration_s = 120, effect = Stat_Mod{stat = .CRIT_RESIST, mult = 0.3}}
	locom_p.outcome_count = 1
	spirit_p, _ := registry_reserve(&skill_registry, "Spirit Protection")
	spirit_p.source = .TREE; spirit_p.sub_cat = .BLESSING; spirit_p.kind = .BUFF
	spirit_p.description = "Reduce party members' aura damage taken"
	spirit_p.req = Skill_Points_Req(90); spirit_p.cost_mp = 143; spirit_p.cast_time_s = 1; spirit_p.cooldown_s = 30; spirit_p.duration_s = 90
	spirit_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = false, duration_s = 90, effect = Stat_Mod{stat = .MAGIC_RESIST, mult = 0.5}}
	spirit_p.outcome_count = 1

	// ── Exorcism tree (prayer) — holy magical + banishment ──────────────
	tree_mag("Pure Arrow", "Shoot a holy projectile", .EXORCISM, .HOLY, 8, 18, 1, 5, 1, 1)
	// Elemental Absorption: resist buff (element-specific resist mods deferred).
	elemabs_p, _ := registry_reserve(&skill_registry, "Elemental Absorption")
	elemabs_p.source = .TREE; elemabs_p.sub_cat = .EXORCISM; elemabs_p.kind = .BUFF
	elemabs_p.description = "Reduce elemental damage taken"
	elemabs_p.req = Skill_Points_Req(12); elemabs_p.cost_mp = 60; elemabs_p.cast_time_s = 0.8; elemabs_p.cooldown_s = 10; elemabs_p.duration_s = 60
	elemabs_p.requires.self_only = true
	// Bless Weapon: holy weapon aura (spi-tiered damage — schema gap: holy not
	// a DOT_Element; modelled as a self buff, aura tiers deferred).
	blesswpn_p, _ := registry_reserve(&skill_registry, "Bless Weapon")
	blesswpn_p.source = .TREE; blesswpn_p.sub_cat = .EXORCISM; blesswpn_p.kind = .BUFF
	blesswpn_p.description = "Embue weapon with holy aura"
	blesswpn_p.req = Skill_Points_Req(26); blesswpn_p.cost_mp = 30; blesswpn_p.cast_time_s = 1.5; blesswpn_p.cooldown_s = 1.5; blesswpn_p.duration_s = 480
	blesswpn_p.requires.self_only = true
	remed_p, _ := registry_reserve(&skill_registry, "Remedium")
	remed_p.source = .TREE; remed_p.sub_cat = .EXORCISM; remed_p.kind = .UTILITY
	remed_p.description = "Dispel a single disorder"
	remed_p.req = Skill_Points_Req(41); remed_p.cost_mp = 26; remed_p.cast_time_s = 1; remed_p.cooldown_s = 5
	s = tree_mag("Holy Rays", "Rain holy beams from above", .EXORCISM, .HOLY, 54, 132, 6, 60, 6, 1)
	s.targeting = {aoe_mode = .GROUND_TARGETED, aoe_radius = 7, pulse_count = 5, pulse_interval_ms = 1000}
	banish_p, _ := registry_reserve(&skill_registry, "Banish")
	banish_p.source = .TREE; banish_p.sub_cat = .EXORCISM; banish_p.kind = .UTILITY
	banish_p.description = "Banish a summoned object or monster"
	banish_p.req = Skill_Points_Req(61); banish_p.cast_time_s = 5; banish_p.cooldown_s = 10
	banish_p.targeting.aoe_mode = .GROUND_TARGETED; banish_p.targeting.aoe_radius = 5
	s = tree_mag("Devotion", "All MP costs of targeted party member are taken from your MP pool", .EXORCISM, .HOLY, 0, 50, 3, 0.5, 0, 1)
	s.kind = .BUFF; s.req = [4]Prereq{{.EXORCISM, 61}, {.BLESSING, 26}, {}, {}}; s.duration_s = 300
	s.outcome_count = 0
	s = tree_mag("Silent Void", "Create a field that negates all field spells, targeted and non-targeted", .EXORCISM, .HOLY, 61, 93, 5, 12, 0, 1)
	s.kind = .DEBUFF; s.duration_s = 120
	s.targeting.aoe_mode = .GROUND_TARGETED; s.targeting.aoe_radius = 5
	s.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 120, effect = Status_Flag_Set{.PREVENT_FIELD_SPELLS}}
	tree_mag("Twinkle Extreme", "Implant a holy bomb in target, delayed explosion does large damage based on INT", .EXORCISM, .HOLY, 81, 110, 3, 10, 5, 1)
	s = tree_mag("Abstention", "Prevent target from using field spells until debuff expires", .EXORCISM, .HOLY, 90, 77, 3, 60, 0, 1)
	s.kind = .DEBUFF
	s.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = Status_Flag_Set{.PREVENT_FIELD_SPELLS}}

	// ── Hymn tree (prayer) — songs (AOE buffs/damage) ───────────────────
	// Green Song: tiered accuracy+dodge for those in range.
	greensong_p, _ := registry_reserve(&skill_registry, "Green Song")
	greensong_p.source = .TREE; greensong_p.sub_cat = .HYMN; greensong_p.kind = .BUFF
	greensong_p.description = "Increase accuracy and dodge for those in song range"
	greensong_p.req = Skill_Points_Req(8); greensong_p.cost_mp = 30; greensong_p.cooldown_s = 5
	greensong_p.targeting.aoe_mode = .SELF_CENTERED; greensong_p.targeting.aoe_radius = 3
	gstm: Tiered_Mod
	gstm.stat = .SPI; gstm.prof_stat = .BLESSING
	gstm.tiers[0].stat_threshold = 33
	gstm.tiers[0].prof_tiers[0] = {prof_threshold = 8};  gstm.tiers[0].prof_tiers[0].deltas[.ACCURACY] = 1; gstm.tiers[0].prof_tiers[0].deltas[.DODGE] = 1
	gstm.tiers[0].prof_tiers[1] = {prof_threshold = 16}; gstm.tiers[0].prof_tiers[1].deltas[.ACCURACY] = 2; gstm.tiers[0].prof_tiers[1].deltas[.DODGE] = 2
	gstm.tiers[0].prof_tiers[2] = {prof_threshold = 24}; gstm.tiers[0].prof_tiers[2].deltas[.ACCURACY] = 3; gstm.tiers[0].prof_tiers[2].deltas[.DODGE] = 3
	gstm.tiers[0].prof_tiers[3] = {prof_threshold = 31}; gstm.tiers[0].prof_tiers[3].deltas[.ACCURACY] = 4; gstm.tiers[0].prof_tiers[3].deltas[.DODGE] = 4
	gstm.tiers[0].prof_tiers[4] = {prof_threshold = 39}; gstm.tiers[0].prof_tiers[4].deltas[.ACCURACY] = 5; gstm.tiers[0].prof_tiers[4].deltas[.DODGE] = 5
	gstm.tiers[0].prof_tiers[5] = {prof_threshold = 47}; gstm.tiers[0].prof_tiers[5].deltas[.ACCURACY] = 6; gstm.tiers[0].prof_tiers[5].deltas[.DODGE] = 6
	gstm.tiers[0].prof_tiers[6] = {prof_threshold = 54}; gstm.tiers[0].prof_tiers[6].deltas[.ACCURACY] = 7; gstm.tiers[0].prof_tiers[6].deltas[.DODGE] = 7
	gstm.tiers[0].prof_tiers[7] = {prof_threshold = 62}; gstm.tiers[0].prof_tiers[7].deltas[.ACCURACY] = 8; gstm.tiers[0].prof_tiers[7].deltas[.DODGE] = 8
	greensong_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = false, effect = gstm}
	greensong_p.outcome_count = 1
	tree_passive("Luminous Chant (Passive)", "Gain ability to move while chanting", .HYMN, 12)
	// Blue Song: +magical damage, -cooldowns in range.
	bluesong_p, _ := registry_reserve(&skill_registry, "Blue Song")
	bluesong_p.source = .TREE; bluesong_p.sub_cat = .HYMN; bluesong_p.kind = .BUFF
	bluesong_p.description = "Increase magical damage and decrease skill cooldowns for all in song range"
	bluesong_p.req = [4]Prereq{{.HYMN, 30}, {.BLESSING, 71}, {}, {}}; bluesong_p.cost_mp = 33; bluesong_p.cooldown_s = 5
	bluesong_p.targeting.aoe_mode = .SELF_CENTERED; bluesong_p.targeting.aoe_radius = 3
	// Yellow Song: damage immunity threshold in range.
	yellowsong_p, _ := registry_reserve(&skill_registry, "Yellow Song")
	yellowsong_p.description = "Players in song range gain immunity to damage below a certain threshold"
	yellowsong_p.source = .TREE; yellowsong_p.sub_cat = .HYMN; yellowsong_p.kind = .BUFF
	yellowsong_p.req = [4]Prereq{{.HYMN, 20}, {.GRACE, 61}, {}, {}}; yellowsong_p.cost_mp = 33; yellowsong_p.cooldown_s = 5
	yellowsong_p.targeting.aoe_mode = .SELF_CENTERED; yellowsong_p.targeting.aoe_radius = 3
	// Red Song: damages LP+MP of enemies in range each pulse.
	s = tree_mag("Red Song", "Damage LP and MP for all enemies in range each pulse", .HYMN, .HOLY, 0, 100, 0, 6, 2, 1)
	s.req = [4]Prereq{{.HYMN, 30}, {.EXORCISM, 30}, {}, {}}
	s.targeting.aoe_mode = .SELF_CENTERED; s.targeting.aoe_radius = 3

	// ── Elemental tree (magic) — ice/lightning/fire AOE nukes ───────────
	tree_mag("Hailstone", "Hurl a ball of ice at the enemy, dealing ice damage", .ELEMENTAL, .ICE, 8, 18, 0.3, 2, 0.1, 1).duration_s = 4
	s = tree_mag("Thunder Ball", "Launch a ball of lightning that damages all enemies in range", .ELEMENTAL, .LIGHTNING, 12, 50, 2, 5, 1.4, 1)
	s.targeting.aoe_mode = .SELF_CENTERED
	tree_mag("Ice Spear", "Hurl a spear of ice at the enemy, dealing ice damage", .ELEMENTAL, .ICE, 21, 59, 1.5, 5, 3, 1)
	s = tree_mag("Firestorm", "Summon a firestorm that damages all enemies in range", .ELEMENTAL, .FIRE, 26, 100, 6, 30, 3, 1)
	s.targeting = {aoe_mode = .GROUND_TARGETED, aoe_radius = 6, pulse_count = 5, pulse_interval_ms = 1000}; s.duration_s = 5
	// Resist Fire / Ice / Lightning: element-specific resist buffs (per-element
	// resist not modelled as distinct Stats; captured as self buffs).
	rfire_p, _ := registry_reserve(&skill_registry, "Resist Fire")
	rfire_p.source = .TREE; rfire_p.sub_cat = .ELEMENTAL; rfire_p.kind = .BUFF
	rfire_p.description = "Reduce fire damage taken, increase ice and lightning damage taken"
	rfire_p.req = Skill_Points_Req(33); rfire_p.cost_mp = 32; rfire_p.cast_time_s = 1.5; rfire_p.cooldown_s = 3.5; rfire_p.duration_s = 20
	rfire_p.requires.self_only = true
	rice_p, _ := registry_reserve(&skill_registry, "Resist Ice")
	rice_p.source = .TREE; rice_p.sub_cat = .ELEMENTAL; rice_p.kind = .BUFF
	rice_p.description = "Reduce ice damage taken, increase fire and lightning damage taken"
	rice_p.req = Skill_Points_Req(35); rice_p.cost_mp = 32; rice_p.cast_time_s = 1.5; rice_p.cooldown_s = 3.5; rice_p.duration_s = 20
	rice_p.requires.self_only = true
	rlight_p, _ := registry_reserve(&skill_registry, "Resist Lightning")
	rlight_p.source = .TREE; rlight_p.sub_cat = .ELEMENTAL; rlight_p.kind = .BUFF
	rlight_p.description = "Reduce lightning damage taken, increase fire and ice damage taken"
	rlight_p.req = Skill_Points_Req(41); rlight_p.cost_mp = 32; rlight_p.cast_time_s = 1.5; rlight_p.cooldown_s = 3.5; rlight_p.duration_s = 20
	rlight_p.requires.self_only = true
	s = tree_mag("Ice Storm", "Summon a storm of ice that damages all enemies in range", .ELEMENTAL, .ICE, 54, 112, 7.5, 20, 1, 1)
	s.targeting = {aoe_mode = .GROUND_TARGETED, aoe_radius = 6, pulse_count = 3, pulse_interval_ms = 1000}
	s.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = .ICE, base_power = 1, knockback = 2}
	tree_mag("Delay Bomb", "Implant a bomb in target, delayed explosion does large damage based on INT", .ELEMENTAL, .ARCANE, 61, 61, 2, 6, 2, 1)
	s = tree_mag("Thunderstorm", "Call down a storm of lightning bolts in an area", .ELEMENTAL, .LIGHTNING, 0, 227, 20, 20, 4, 1)
	s.req = [4]Prereq{{.ELEMENTAL, 61}, {.EXORCISM, 40}, {}, {}}
	s.targeting = {aoe_mode = .GROUND_TARGETED, aoe_radius = 8, pulse_count = 10, pulse_interval_ms = 1000}
	s = tree_mag("Meteor Storm", "Unleash a massive meteor storm, dealing heavy damage to all enemies nearby", .ELEMENTAL, .FIRE, 0, 312, 20, 20, 4, 1)
	s.req = [4]Prereq{{.ELEMENTAL, 61}, {.INVOCATION, 40}, {}, {}}
	s.targeting = {aoe_mode = .GROUND_TARGETED, aoe_radius = 10, pulse_count = 10, pulse_interval_ms = 1000}
	s = tree_mag("Despair Swamp", "Summon a swamp that damages, slows, and poisons all enemies in range", .ELEMENTAL, .DARK, 0, 256, 21, 20, 2, 1)
	s.req = [4]Prereq{{.ELEMENTAL, 61}, {.CONFUSION, 40}, {}, {}}
	s.targeting = {aoe_mode = .GROUND_TARGETED, aoe_radius = 7, pulse_count = 12, pulse_interval_ms = 1000}
	s = tree_mag("Ice Tempest", "Summon a storm of ice that damages and knocks back all enemies in range", .ELEMENTAL, .ICE, 71, 287, 7.5, 20, 5, 1)
	s.targeting = {aoe_mode = .GROUND_TARGETED, aoe_radius = 8, pulse_count = 10, pulse_interval_ms = 1000}
	s.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = .ICE, base_power = 5, knockback = 2}
	s = tree_mag("Cremation", "Big damage to all enemies in range", .ELEMENTAL, .FIRE, 81, 650, 4, 50, 3, 1)
	s.targeting.aoe_mode = .SELF_CENTERED
	// Glitter Discharge: lightning shield on caster.
	glitter_p, _ := registry_reserve(&skill_registry, "Glitter Discharge")
	glitter_p.source = .TREE; glitter_p.sub_cat = .ELEMENTAL; glitter_p.kind = .BUFF
	glitter_p.description = "Lightning shield on caster"
	glitter_p.req = Skill_Points_Req(90); glitter_p.cost_mp = 132; glitter_p.cast_time_s = 1; glitter_p.cooldown_s = 120
	glitter_p.requires.self_only = true

	// ── Invocation tree (magic) — summons + utility ─────────────────────
	soulbr_p, _ := registry_reserve(&skill_registry, "Soul Bright")
	soulbr_p.source = .TREE; soulbr_p.sub_cat = .INVOCATION; soulbr_p.kind = .BUFF
	soulbr_p.description = "Reveal nearby invisible enemies"
	soulbr_p.req = Skill_Points_Req(8); soulbr_p.cost_mp = 14; soulbr_p.cast_time_s = 1; soulbr_p.cooldown_s = 6
	soulbr_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, effect = Status_Flag_Set{.REVEAL_INVISIBLE}}
	soulbr_p.outcome_count = 1
	manash_p, _ := registry_reserve(&skill_registry, "Mana Shield")
	manash_p.source = .TREE; manash_p.sub_cat = .INVOCATION; manash_p.kind = .BUFF
	manash_p.description = "Damage taken is reduced, taking some damage as MP"
	manash_p.req = Skill_Points_Req(21); manash_p.cost_mp = 24; manash_p.cast_time_s = 3; manash_p.cooldown_s = 10
	manash_p.requires.self_only = true
	clearmind_p, _ := registry_reserve(&skill_registry, "Clear Mind")
	clearmind_p.source = .TREE; clearmind_p.sub_cat = .INVOCATION; clearmind_p.kind = .BUFF
	clearmind_p.description = "Increased spell interrupt resistance"
	clearmind_p.req = Skill_Points_Req(31); clearmind_p.cost_mp = 59; clearmind_p.cast_time_s = 5; clearmind_p.cooldown_s = 1.5; clearmind_p.duration_s = 80
	clearmind_p.requires.self_only = true
	s = tree_mag("Psychic Blades", "Release 3 blades of energy that pierce enemies in a cone. Deals bonus damage based on enemy defense", .INVOCATION, .ARCANE, 41, 39, 3.5, 10, 2, 1)
	s.targeting.aoe_mode = .FRONTAL_CONE
	s.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = .ARCANE, base_power = 2, bonus_vs_low_def = true}
	// Summon Wall / Plant / Wyvern / Turtle / Sandman: FIELD_SPELL summons
	// (ground-targeted; summon-object details deferred — no Summon outcome yet).
	summon_field :: proc(key, desc: string, pts: u8, mp: u16, cast_s, cd, dur: f32, radius: f32) {
		sp, _ := registry_reserve(&skill_registry, key)
		sp.source = .TREE; sp.sub_cat = .INVOCATION; sp.kind = .FIELD_SPELL
		sp.description = desc; sp.req = Skill_Points_Req(pts); sp.cost_mp = mp
		sp.cast_time_s = cast_s; sp.cooldown_s = cd; sp.duration_s = dur
		sp.targeting.aoe_mode = .GROUND_TARGETED; sp.targeting.aoe_radius = radius
	}
	summon_field("Summon Wall", "Create a wall that blocks all damage", 50, 79, 5, 90, 180, 1)
	// Summon Sandman: damage + sleep AOE.
	ssand_p, _ := registry_reserve(&skill_registry, "Summon Sandman")
	ssand_p.source = .TREE; ssand_p.sub_cat = .INVOCATION; ssand_p.kind = .DAMAGE_MAGICAL
	ssand_p.description = "Summon a sandstorm that knocks back enemies, sleeping, and damaging them"
	ssand_p.req = Skill_Points_Req(61); ssand_p.cost_mp = 58; ssand_p.cast_time_s = 7; ssand_p.cooldown_s = 30; ssand_p.duration_s = 10
	ssand_p.targeting.aoe_mode = .GROUND_TARGETED
	ssand_p.outcomes[0] = Damage_Params{damage_type = .MAGICAL, base_power = 3, knockback = 3}
	ssand_p.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 3, effect = CC_Effect{kind = .SLEEP}}
	ssand_p.outcome_count = 2
	summon_field("Summon Plant", "Summon an elemental plant turret that fires bolts at nearby enemies. Element matches weapon used when summoning.", 71, 192, 2, 60, 180, 1)
	// Regia Blaze: fire weapon aura buff.
	regia_p, _ := registry_reserve(&skill_registry, "Regia Blaze")
	regia_p.source = .TREE; regia_p.sub_cat = .INVOCATION; regia_p.kind = .BUFF
	regia_p.description = "Fire damage aura"
	regia_p.req = [4]Prereq{{.INVOCATION, 78}, {.ELEMENTAL, 40}, {}, {}}; regia_p.cost_mp = 60; regia_p.cast_time_s = 1.5; regia_p.cooldown_s = 5; regia_p.duration_s = 30
	regia_p.requires.self_only = true
	regia_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 30, effect = Weapon_Aura{element = .BURN, formula = "regia_blaze"}}
	regia_p.outcome_count = 1
	summon_field("Summon Wyvern", "Summon a wyvern that damages all enemies in frontal cone, moving freely on the battlefield. Disappears after 60 seconds.", 81, 520, 10, 60, 60, 1)
	summon_field("Summon Turtle", "Summon a turtle that damages all enemies in a circle around it. Disappears after 60 seconds.", 90, 700, 15, 300, 60, 1)

	// ── Darkness tree (magic) — poison/dark DoTs + dispels ──────────────
	poison_p, _ := registry_reserve(&skill_registry, "Poison")
	poison_p.source = .TREE; poison_p.sub_cat = .DARKNESS; poison_p.kind = .DEBUFF
	poison_p.description = "Poison the target, dealing damage over time"
	poison_p.req = Skill_Points_Req(8); poison_p.cost_mp = 24; poison_p.cast_time_s = 2; poison_p.cooldown_s = 5; poison_p.duration_s = 60
	poison_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 60, effect = DOT_Effect{element = .POISON, tick_interval_s = 2, spi_base = 0.05, spi_max = 0.1, spi_cap = 110}}
	poison_p.outcome_count = 1
	// Gloom: dark weapon aura (recoil).
	gloom_p, _ := registry_reserve(&skill_registry, "Gloom")
	gloom_p.source = .TREE; gloom_p.sub_cat = .DARKNESS; gloom_p.kind = .BUFF
	gloom_p.description = "Embue weapon with dark aura, damaging yourself with recoil"
	gloom_p.req = Skill_Points_Req(12); gloom_p.cost_mp = 38; gloom_p.cast_time_s = 2; gloom_p.cooldown_s = 10; gloom_p.duration_s = 120
	gloom_p.requires.self_only = true
	gloom_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 120, effect = Weapon_Aura{element = .BURN, formula = "gloom"}}
	gloom_p.outcome_count = 1
	bdrain_p, _ := registry_reserve(&skill_registry, "Blood Drain")
	bdrain_p.source = .TREE; bdrain_p.sub_cat = .DARKNESS; bdrain_p.kind = .UTILITY
	bdrain_p.description = "Drain life from the target and heal yourself"
	bdrain_p.req = Skill_Points_Req(21); bdrain_p.cost_mp = 32; bdrain_p.cast_time_s = 1; bdrain_p.cooldown_s = 10
	mindvenom_p, _ := registry_reserve(&skill_registry, "Mind Venom")
	mindvenom_p.source = .TREE; mindvenom_p.sub_cat = .DARKNESS; mindvenom_p.kind = .DEBUFF
	mindvenom_p.description = "Poison the target's mind, dealing damage over time"
	mindvenom_p.req = Skill_Points_Req(26); mindvenom_p.cost_mp = 33; mindvenom_p.cast_time_s = 2.5; mindvenom_p.cooldown_s = 10; mindvenom_p.duration_s = 30
	mindvenom_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 30, effect = DOT_Effect{element = .SEVERE_POISON, tick_interval_s = 3, mp_drain = 5, spi_base = 0.1, spi_max = 0.15, spi_cap = 110}}
	mindvenom_p.outcome_count = 1
	dispel_p, _ := registry_reserve(&skill_registry, "Dispel")
	dispel_p.source = .TREE; dispel_p.sub_cat = .DARKNESS; dispel_p.kind = .DEBUFF
	dispel_p.description = "Dispel a buff from target"
	dispel_p.req = Skill_Points_Req(33); dispel_p.cost_mp = 26; dispel_p.cast_time_s = 1; dispel_p.cooldown_s = 15
	dispel_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = Status_Flag_Set{.DISPEL}}
	dispel_p.outcome_count = 1
	rmalice_p, _ := registry_reserve(&skill_registry, "Resist Malice")
	rmalice_p.source = .TREE; rmalice_p.sub_cat = .DARKNESS; rmalice_p.kind = .BUFF
	rmalice_p.description = "Reduce dark damage taken, greatly reducing charm resistance"
	rmalice_p.req = Skill_Points_Req(35); rmalice_p.cost_mp = 32; rmalice_p.cast_time_s = 1.5; rmalice_p.cooldown_s = 3.5; rmalice_p.duration_s = 20
	rmalice_p.requires.self_only = true
	undermine_p, _ := registry_reserve(&skill_registry, "Undermine")
	undermine_p.source = .TREE; undermine_p.sub_cat = .DARKNESS; undermine_p.kind = .DEBUFF
	undermine_p.description = "Increase damage of the next attack on target"
	undermine_p.req = Skill_Points_Req(41); undermine_p.cost_mp = 26; undermine_p.cast_time_s = 0.5; undermine_p.cooldown_s = 10; undermine_p.duration_s = 8
	s = tree_mag("Pestilence", "Deal poison damage to all enemies in range", .DARKNESS, .POISON, 54, 62, 1, 10, 3, 1)
	s.targeting = {aoe_mode = .GROUND_TARGETED, aoe_radius = 2, pulse_count = 3, pulse_interval_ms = 1000}
	tree_passive("Equalize (Passive)", "Chance to remove a buff from target on hit", .DARKNESS, 61)
	s = tree_mag("Dark Frenzy", "Pulses of darkness that deal both magical and physical damage to all enemies in range", .DARKNESS, .DARK, 71, 122, 3, 10, 3, 1)
	s.duration_s = 6; s.targeting = {aoe_mode = .SELF_CENTERED, aoe_radius = 6, pulse_count = 5, pulse_interval_ms = 1000}
	s = tree_phys("Ramkyado", "Slice enemy with weapon", .DARKNESS, .DARK, 0, 15, 0, 8, 1, 1)
	s.kind = .DAMAGE_MAGICAL; s.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = .DARK, base_power = 1}
	s.req = [4]Prereq{{.DARKNESS, 78}, {.SLASH, 26}, {}, {}}
	// Bind Criminal: AOE movement lock.
	bindcr_p, _ := registry_reserve(&skill_registry, "Bind Criminal")
	bindcr_p.source = .TREE; bindcr_p.sub_cat = .DARKNESS; bindcr_p.kind = .DEBUFF
	bindcr_p.description = "Bind targets in large AOE, preventing them from moving"
	bindcr_p.req = Skill_Points_Req(81); bindcr_p.cost_mp = 30; bindcr_p.cooldown_s = 90
	bindcr_p.targeting.aoe_mode = .SELF_CENTERED
	bindcr_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = Stat_Mod{stat = .MOVE_SPEED, mult = 0.1}}
	bindcr_p.outcome_count = 1
	tree_mag("Sins Genocide", "Use the magic sword called from the abyss to skewer your opponent", .DARKNESS, .DARK, 90, 48, 0, 30, 2, 1)

	// ── Confusion tree (magic) — debuffs + MP damage + fear ─────────────
	weakness_p, _ := registry_reserve(&skill_registry, "Weakness")
	weakness_p.source = .TREE; weakness_p.sub_cat = .CONFUSION; weakness_p.kind = .DEBUFF
	weakness_p.description = "Reduce target's attack"
	weakness_p.req = Skill_Points_Req(8); weakness_p.cost_mp = 18; weakness_p.cast_time_s = 1; weakness_p.cooldown_s = 5; weakness_p.duration_s = 120
	weakness_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 120, effect = Stat_Mod{stat = .ATTACK, mult = 0.85}}
	weakness_p.outcome_count = 1
	s = tree_mag("Sandstorm", "Summon a sandstorm that puts target to sleep", .CONFUSION, .ARCANE, 12, 51, 2, 20, 3, 1)
	s.duration_s = 20; s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 2, effect = CC_Effect{kind = .SLEEP}}; s.outcome_count = 2
	s = tree_mag("Psionic Blast", "Deal damage to target's MP", .CONFUSION, .ARCANE, 21, 25, 1.5, 5, 1, 1)
	s.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = .ARCANE, base_power = 1}; s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = DOT_Effect{element = .MP_DRAIN}}
	s.outcome_count = 2
	weaken_p, _ := registry_reserve(&skill_registry, "Weaken")
	weaken_p.source = .TREE; weaken_p.sub_cat = .CONFUSION; weaken_p.kind = .DEBUFF
	weaken_p.description = "Reduce target's defense"
	weaken_p.req = Skill_Points_Req(26); weaken_p.cost_mp = 18; weaken_p.cast_time_s = 1; weaken_p.cooldown_s = 5; weaken_p.duration_s = 120
	weaken_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 120, effect = Stat_Mod{stat = .DEFENSE, mult = 0.85}}
	weaken_p.outcome_count = 1
	impede_p, _ := registry_reserve(&skill_registry, "Impede")
	impede_p.source = .TREE; impede_p.sub_cat = .CONFUSION; impede_p.kind = .DEBUFF
	impede_p.description = "Reduce target's dodge"
	impede_p.req = Skill_Points_Req(33); impede_p.cost_mp = 28; impede_p.cast_time_s = 2; impede_p.cooldown_s = 5; impede_p.duration_s = 120
	impede_p.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 120, effect = Stat_Mod{stat = .DODGE, mult = 0.5}}
	impede_p.outcome_count = 1
	rcharm_p, _ := registry_reserve(&skill_registry, "Resist Charm")
	rcharm_p.source = .TREE; rcharm_p.sub_cat = .CONFUSION; rcharm_p.kind = .BUFF
	rcharm_p.description = "Increase charm resistance, greatly reducing dark resistance"
	rcharm_p.req = Skill_Points_Req(35); rcharm_p.cost_mp = 32; rcharm_p.cast_time_s = 1.5; rcharm_p.cooldown_s = 3.5; rcharm_p.duration_s = 7
	rcharm_p.requires.self_only = true
	// Icy Strike: ice damage + freeze/slow.
	s = tree_mag("Icy Strike", "Freeze target, slowing them", .CONFUSION, .ICE, 41, 44, 0.3, 12, 1, 1)
	s.duration_s = 15
	s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 5, effect = CC_Effect{kind = .FREEZE}}
	s.outcomes[2] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 15, effect = Stat_Mod{stat = .MOVE_SPEED, mult = 0.7}}
	s.outcome_count = 3
	s = tree_mag("Wasteland", "Summon a poison wasteland that damages and slows all enemies in range", .CONFUSION, .POISON, 54, 44, 0.5, 30, 2, 1)
	s.duration_s = 30; s.targeting = {aoe_mode = .GROUND_TARGETED, aoe_radius = 8}
	s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 30, effect = DOT_Effect{element = .POISON, tick_interval_s = 2, spi_base = 0.05, spi_max = 0.1, spi_cap = 110}}
	s.outcomes[2] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 30, effect = Stat_Mod{stat = .MOVE_SPEED, mult = 0.5}}
	s.outcome_count = 3
	s = tree_mag("Siren Storm", "Damage MP of all enemies in AOE", .CONFUSION, .ARCANE, 61, 87, 4.5, 15, 4, 1)
	s.targeting.aoe_mode = .SELF_CENTERED
	s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = DOT_Effect{element = .MP_DRAIN}}
	s.outcome_count = 2
	s = tree_mag("Cursed Bolt", "Curse target, preventing resurrection", .CONFUSION, .DARK, 71, 69, 2, 20, 3, 1)
	s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = Status_Flag_Set{.PREVENT_RESURRECT}}
	s.outcome_count = 2
	// Hallucination: AOE fear (no FEAR in CC_Kind; modelled as AOE debuff).
	hallu_p, _ := registry_reserve(&skill_registry, "Hallucination")
	hallu_p.source = .TREE; hallu_p.sub_cat = .CONFUSION; hallu_p.kind = .DEBUFF
	hallu_p.description = "AOE fear, forcefully sending enemies running"
	hallu_p.req = Skill_Points_Req(90); hallu_p.cost_mp = 65; hallu_p.cast_time_s = 1; hallu_p.cooldown_s = 60
	hallu_p.targeting.aoe_mode = .SELF_CENTERED

	// ── Category-level basics (gated by overall category adeptness, not a
	//    single sub-category; modelled as tree skills with the closest
	//    sub_cat — the req-threshold semantics is a refinement for when a
	//    consumer exists) ────────────────────────────────────────────────
	s = tree_phys("Slash", "Quick combo strike that gives the enemy no chance to evade.", .SLASH, .SLASH, 3, 10, 0, 10, 1, 1)
	s.category_level = true
	s = tree_phys("Bash", "A heavy blow that knocks the target back and may stun.", .BASH, .BASH, 35, 18, 0, 10, 2, 1)
	s.category_level = true
	s.outcomes[0] = Damage_Params{sub_type = .BASH, base_power = 2, knockback = 2}
	s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = CC_Effect{kind = .STUN}}
	s.outcome_count = 2
	misd_p, _ := registry_reserve(&skill_registry, "Misdirection")
	misd_p.source = .TREE; misd_p.sub_cat = .SLASH; misd_p.kind = .UTILITY
	misd_p.description = "Distract nearby foes, removing their target on you."
	misd_p.category_level = true
	misd_p.req = Skill_Points_Req(70); misd_p.cost_mp = 10; misd_p.cooldown_s = 60
	// Unpain: immune to KD/slow/immobilize, but attack halved.
	unpain_p, _ := registry_reserve(&skill_registry, "Unpain")
	unpain_p.source = .TREE; unpain_p.sub_cat = .SLASH; unpain_p.kind = .BUFF
	unpain_p.description = "Become immune to knockdown, slow, and immobilize, but your attack is halved."
	unpain_p.category_level = true
	unpain_p.req = Skill_Points_Req(100); unpain_p.cost_mp = 24; unpain_p.cooldown_s = 30; unpain_p.duration_s = 10
	unpain_p.requires.self_only = true
	unpain_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 10, effect = Status_Flag_Set{.DISABLE_PHYSICAL_ATTACKS}}
	unpain_p.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = true, duration_s = 10, effect = Status_Flag_Set{.ATTACK_HALVED}}
	unpain_p.outcome_count = 2
	// Revidium: dispel one harmful magical effect.
	revid_p, _ := registry_reserve(&skill_registry, "Revidium")
	revid_p.source = .TREE; revid_p.sub_cat = .BLESSING; revid_p.kind = .UTILITY
	revid_p.description = "Dispels one harmful magical effect from the target."
	revid_p.category_level = true
	revid_p.req = Skill_Points_Req(35); revid_p.cost_mp = 14; revid_p.cast_time_s = 2; revid_p.cooldown_s = 15
	revid_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = false, effect = Status_Flag_Set{.DISPEL}}
	revid_p.outcome_count = 1
	// Physical / Magic Barrier: block one attack.
	physbar_p, _ := registry_reserve(&skill_registry, "Physical Barrier")
	physbar_p.source = .TREE; physbar_p.sub_cat = .BLESSING; physbar_p.kind = .BUFF
	physbar_p.description = "Shield the target with a barrier that fully blocks one physical attack."
	physbar_p.category_level = true
	physbar_p.req = Skill_Points_Req(102); physbar_p.cost_mp = 128; physbar_p.cast_time_s = 2; physbar_p.cooldown_s = 10; physbar_p.duration_s = 60
	magicbar_p, _ := registry_reserve(&skill_registry, "Magic Barrier")
	magicbar_p.source = .TREE; magicbar_p.sub_cat = .BLESSING; magicbar_p.kind = .BUFF
	magicbar_p.description = "Shield the target with a barrier that fully blocks one magical attack."
	magicbar_p.category_level = true
	magicbar_p.req = Skill_Points_Req(102); magicbar_p.cost_mp = 128; magicbar_p.cast_time_s = 2; magicbar_p.cooldown_s = 10; magicbar_p.duration_s = 60

	// ── Horsemanship tree (special) ─────────────────────────────────────
	summhorse_p, _ := registry_reserve(&skill_registry, "Summon Horse")
	summhorse_p.source = .TREE; summhorse_p.sub_cat = .HORSEMANSHIP; summhorse_p.kind = .FIELD_SPELL
	summhorse_p.description = "Summon a horse"
	summhorse_p.req = Skill_Points_Req(20); summhorse_p.cost_mp = 22; summhorse_p.cast_time_s = 3; summhorse_p.cooldown_s = 180
	hguard_p, _ := registry_reserve(&skill_registry, "Horse Guardian")
	hguard_p.source = .TREE; hguard_p.sub_cat = .HORSEMANSHIP; hguard_p.kind = .BUFF
	hguard_p.description = "Take damage for your horse"
	hguard_p.req = Skill_Points_Req(31); hguard_p.cost_mp = 5
	tree_passive("Horse Charge (Passive)", "Charge at target, dealing damage", .HORSEMANSHIP, 40)

	// ── other-tree samples (ported ahead of their full batches) ──────────
	// Skill — damage + debuff combo (Stun). Exercises Outcome.Apply with a CC.
	stun_p, _ := registry_reserve(&skill_registry, "Stun")
	stun_p.source = .TREE
	stun_p.sub_cat = .BASH
	stun_p.kind = .DAMAGE_PHYSICAL
	stun_p.description = "Attack + 30% chance to stun (blunt, 2H blunt, wand)"
	stun_p.req = Skill_Points_Req(8)
	stun_p.cost_mp = 15
	stun_p.cooldown_s = 8
	stun_p.requires.weapon[0] = .BLUNT
	stun_p.requires.weapon[1] = .BLUNT_2H
	stun_p.requires.weapon[2] = .WAND
	stun_p.requires.weapon_count = 3
	stun_p.outcomes[0] = Damage_Params{sub_type = .BASH, base_power = 1}
	stun_p.outcomes[1] = Apply_Effect{
		polarity = .DEBUFF, to_self = false, duration_s = 0,
		effect = CC_Effect{kind = .STUN, chance = 0.3},
	}
	stun_p.outcome_count = 2

	// Skill 3 — two-level tiered buff (Lapis Mediow). Exercises Tiered_Mod. [D6]
	lapis_p, _ := registry_reserve(&skill_registry, "Lapis Mediow")
	lapis_p.source = .TREE
	lapis_p.sub_cat = .BLESSING
	lapis_p.kind = .BUFF
	lapis_p.description = "Increase player's defense"
	lapis_p.req = Skill_Points_Req(12)
	lapis_p.cost_mp = 22
	lapis_p.duration_s = 480
	lapis_p.cast_time_s = 0.5
	tm: Tiered_Mod
	tm.stat = .SPI
	tm.prof_stat = .BLESSING
	// Stat threshold → (prof threshold → def bonus). 5 SPI tiers × 4 prof tiers.
	tm.tiers[0].stat_threshold = 33
	tm.tiers[0].prof_tiers[0] = {prof_threshold = 24.9}; tm.tiers[0].prof_tiers[0].deltas[.DEFENSE] = 5
	tm.tiers[0].prof_tiers[1] = {prof_threshold = 25};   tm.tiers[0].prof_tiers[1].deltas[.DEFENSE] = 6
	tm.tiers[0].prof_tiers[2] = {prof_threshold = 50};   tm.tiers[0].prof_tiers[2].deltas[.DEFENSE] = 7
	tm.tiers[0].prof_tiers[3] = {prof_threshold = 75};   tm.tiers[0].prof_tiers[3].deltas[.DEFENSE] = 8
	tm.tiers[1].stat_threshold = 34
	tm.tiers[1].prof_tiers[0] = {prof_threshold = 24.9}; tm.tiers[1].prof_tiers[0].deltas[.DEFENSE] = 6
	tm.tiers[1].prof_tiers[1] = {prof_threshold = 25};   tm.tiers[1].prof_tiers[1].deltas[.DEFENSE] = 7
	tm.tiers[1].prof_tiers[2] = {prof_threshold = 50};   tm.tiers[1].prof_tiers[2].deltas[.DEFENSE] = 8
	tm.tiers[1].prof_tiers[3] = {prof_threshold = 75};   tm.tiers[1].prof_tiers[3].deltas[.DEFENSE] = 9
	tm.tiers[2].stat_threshold = 67
	tm.tiers[2].prof_tiers[0] = {prof_threshold = 24.9}; tm.tiers[2].prof_tiers[0].deltas[.DEFENSE] = 7
	tm.tiers[2].prof_tiers[1] = {prof_threshold = 25};   tm.tiers[2].prof_tiers[1].deltas[.DEFENSE] = 8
	tm.tiers[2].prof_tiers[2] = {prof_threshold = 50};   tm.tiers[2].prof_tiers[2].deltas[.DEFENSE] = 9
	tm.tiers[2].prof_tiers[3] = {prof_threshold = 75};   tm.tiers[2].prof_tiers[3].deltas[.DEFENSE] = 10
	tm.tiers[3].stat_threshold = 100
	tm.tiers[3].prof_tiers[0] = {prof_threshold = 24.9}; tm.tiers[3].prof_tiers[0].deltas[.DEFENSE] = 8
	tm.tiers[3].prof_tiers[1] = {prof_threshold = 25};   tm.tiers[3].prof_tiers[1].deltas[.DEFENSE] = 9
	tm.tiers[3].prof_tiers[2] = {prof_threshold = 50};   tm.tiers[3].prof_tiers[2].deltas[.DEFENSE] = 10
	tm.tiers[3].prof_tiers[3] = {prof_threshold = 75};   tm.tiers[3].prof_tiers[3].deltas[.DEFENSE] = 11
	tm.tiers[4].stat_threshold = 134
	tm.tiers[4].prof_tiers[0] = {prof_threshold = 24.9}; tm.tiers[4].prof_tiers[0].deltas[.DEFENSE] = 9
	tm.tiers[4].prof_tiers[1] = {prof_threshold = 25};   tm.tiers[4].prof_tiers[1].deltas[.DEFENSE] = 10
	tm.tiers[4].prof_tiers[2] = {prof_threshold = 50};   tm.tiers[4].prof_tiers[2].deltas[.DEFENSE] = 11
	tm.tiers[4].prof_tiers[3] = {prof_threshold = 75};   tm.tiers[4].prof_tiers[3].deltas[.DEFENSE] = 12
	lapis_p.outcomes[0] = Apply_Effect{
		polarity = .BUFF, to_self = true, duration_s = 480,
		effect = tm,
	}
	lapis_p.outcome_count = 1

	// Skill 4 — move-speed self buff (Dash). Exercises Stat_Mod on MOVE_SPEED. [D8]
	dash_p, _ := registry_reserve(&skill_registry, "Dash")
	dash_p.source = .TREE
	dash_p.sub_cat = .DODGE
	dash_p.kind = .BUFF
	dash_p.description = "Dash forward"
	dash_p.req = Skill_Points_Req(8)
	dash_p.cost_mp = 18
	dash_p.cooldown_s = 30
	dash_p.duration_s = 2
	dash_p.requires.self_only = true
	dash_p.outcomes[0] = Apply_Effect{
		polarity = .BUFF, to_self = true, duration_s = 2,
		effect = Stat_Mod{stat = .MOVE_SPEED, mult = 1.0},
	}
	dash_p.outcome_count = 1

	// ── class-kit skills for the Warrior kit (from classSkills.ts) ──────────
	// These are flat per-job skills (gated by character level, not proficiency),
	// and get linked to the job via kit_skill_ids.
	provoke_p, provoke_id := registry_reserve(&skill_registry, "Provoke")
	provoke_p.source = .CLASS_KIT
	provoke_p.kind = .PROVOKE
	provoke_p.description = "Provoke target to attack you"
	provoke_p.req = Skill_Level_Req(5)
	provoke_p.cooldown_s = 15
	provoke_p.duration_s = 1

	brewer_p, _ := registry_reserve(&skill_registry, "Brewer (Passive)")
	brewer_p.source = .CLASS_KIT
	brewer_p.kind = .PASSIVE
	brewer_p.description = "12% more potion effectiveness"
	brewer_p.req = Skill_Level_Req(12)

	lunge_p, _ := registry_reserve(&skill_registry, "Lunge")
	lunge_p.source = .CLASS_KIT
	lunge_p.kind = .BUFF
	lunge_p.description = "Increased attack speed with melee weapons"
	lunge_p.req = Skill_Level_Req(15)
	lunge_p.cost_mp = 25
	lunge_p.cooldown_s = 30
	lunge_p.duration_s = 120
	lunge_p.requires.self_only = true
	lunge_p.outcomes[0] = Apply_Effect{
		polarity = .BUFF, to_self = true, duration_s = 120,
		effect = Stat_Mod{stat = .ATTACK_SPEED, mult = 1.2},
	}
	lunge_p.outcome_count = 1

	// Group tree skills by sub-category (auto — keeps bulk porting append-free).
	for i in 0 ..< registry_count(&skill_registry) {
		s := &skill_registry.items[i]
		if s.source == .TREE do append(&tree_skills[s.sub_cat], Skill_Id(u16(i)))
	}

	// ── class-kit skills (from classSkills.ts) — per-job, level-gated ───
	// Provoke / Brewer / Lunge registered above as the warrior-kit sample.
	// Warrior-tree kits.
	kit_skill("Empower (Passive)", "Increase attack power of melee weapons", .PASSIVE, 18, 0, 0, 0, 0)
	s = kit_skill("Leg Sweep", "Attack and reduce target's movement speed", .DAMAGE_PHYSICAL, 20, 21, 0, 10, 5)
	s.outcomes[0] = Damage_Params{base_power = 1}
	s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 5, effect = Stat_Mod{stat = .MOVE_SPEED, mult = 0.5}}
	s.outcome_count = 2
	kit_skill("Obscene Gesture", "Provoke target to attack you", .PROVOKE, 20, 0, 0, 15, 10)
	kit_skill("Jousting (Passive)", "Can use skills and charge on horseback", .PASSIVE, 45, 0, 0, 0, 0)
	// Scout-tree kits.
	kit_skill("Invigorate", "Increase movement speed", .BUFF, 5, 16, 0, 10, 180)
	kit_skill("Hide", "Stationary invisibility (2MP per second)", .UTILITY, 18, 24, 0, 3, 0)
	kit_skill("Hawkeye (Passive)", "Increase accuracy", .PASSIVE, 20, 0, 0, 0, 0)
	kit_skill("Shifty (Passive)", "Dodge rate buff", .PASSIVE, 20, 0, 0, 0, 0)
	kit_skill("Cloak", "Mobile invisibility (3MP per second)", .UTILITY, 20, 45, 2, 20, 0)
	kit_skill("Third Eye", "Accuracy buff", .BUFF, 28, 48, 0.5, 1.5, 480)
	kit_skill("Accelerate", "Increase movement speed of target", .BUFF, 28, 16, 0.5, 1.5, 480)
	// Mage-tree kits.
	kit_skill("Fire Bolt", "Fire a bolt of fire at target", .DAMAGE_MAGICAL, 1, 28, 0.8, 2, 0)
	s = kit_skill("Shock", "Trip the target with electricity", .DAMAGE_MAGICAL, 12, 44, 0.5, 20, 0)
	s.outcomes[0] = Damage_Params{damage_type = .MAGICAL, sub_type = .LIGHTNING, base_power = 1}
	s.outcomes[1] = Apply_Effect{polarity = .DEBUFF, to_self = false, effect = CC_Effect{kind = .KNOCKDOWN}}
	s.outcome_count = 2
	kit_skill("Scholar (Passive)", "Increased magical damage", .PASSIVE, 20, 0, 0, 0, 0)
	kit_skill("Shadow Garments (Passive)", "Fire, Ice, and Lightning resistance increase when gear is enhanced with dark", .PASSIVE, 20, 0, 0, 0, 0)
	// Acolyte-tree kits.
	kit_skill("Meditation (Passive)", "Increase MP regen", .PASSIVE, 5, 0, 0, 0, 0)
	hp_kit: Heal_Params
	hp_kit.scope = .SINGLE
	kit_skill("Heal", "Heal target", .HEAL, 18, 62, 2, 3, 0).outcomes[0] = hp_kit
	kit_skill("Inspiration (Passive)", "Increase SPI based on Prayer proficiency", .PASSIVE, 20, 0, 0, 0, 0)
	kit_skill("Blessed Garments (Passive)", "Poison, Charm, and Magic resistance increase when gear is enhanced with holy", .PASSIVE, 20, 0, 0, 0, 0)
	kit_skill("Tranquil Mind", "Increase MP regen for party", .BUFF, 20, 50, 5, 20, 120)
	kit_skill("Divine Aid", "Increase LP for party, 15% of base LP + 250", .HP_BUFF, 28, 89, 4, 1.54, 480)
	s = kit_skill("Thunder Crash", "AOE damage", .DAMAGE_MAGICAL, 28, 32, 0, 5, 0)
	s.outcomes[0] = Damage_Params{damage_type = .MAGICAL, base_power = 1}; s.targeting.aoe_mode = .SELF_CENTERED
	kit_skill("Mana Restore", "Restore MP over time", .MP_RESTORE, 20, 32, 1.5, 10, 210)
	// Speedy Gale: tiered dodge buff (SPI × Exorcism, 4 stat tiers × 6 prof).
	sg_p := kit_skill("Speedy Gale", "Increase dodge rate", .BUFF, 28, 55, 0, 1, 480)
	sg_p.requires.self_only = true
	sgtm: Tiered_Mod
	sgtm.stat = .SPI; sgtm.prof_stat = .EXORCISM
	sgtm.tiers[0].stat_threshold = 33
	sgtm.tiers[0].prof_tiers[0] = {prof_threshold = 8};  sgtm.tiers[0].prof_tiers[0].deltas[.DODGE] = 13
	sgtm.tiers[0].prof_tiers[1] = {prof_threshold = 16}; sgtm.tiers[0].prof_tiers[1].deltas[.DODGE] = 18
	sgtm.tiers[0].prof_tiers[2] = {prof_threshold = 24}; sgtm.tiers[0].prof_tiers[2].deltas[.DODGE] = 24
	sgtm.tiers[0].prof_tiers[3] = {prof_threshold = 31}; sgtm.tiers[0].prof_tiers[3].deltas[.DODGE] = 30
	sgtm.tiers[0].prof_tiers[4] = {prof_threshold = 39}; sgtm.tiers[0].prof_tiers[4].deltas[.DODGE] = 37
	sgtm.tiers[0].prof_tiers[5] = {prof_threshold = 47}; sgtm.tiers[0].prof_tiers[5].deltas[.DODGE] = 43
	sgtm.tiers[1].stat_threshold = 50
	sgtm.tiers[1].prof_tiers[0] = {prof_threshold = 8};  sgtm.tiers[1].prof_tiers[0].deltas[.DODGE] = 16
	sgtm.tiers[1].prof_tiers[1] = {prof_threshold = 16}; sgtm.tiers[1].prof_tiers[1].deltas[.DODGE] = 22
	sgtm.tiers[1].prof_tiers[2] = {prof_threshold = 24}; sgtm.tiers[1].prof_tiers[2].deltas[.DODGE] = 28
	sgtm.tiers[1].prof_tiers[3] = {prof_threshold = 31}; sgtm.tiers[1].prof_tiers[3].deltas[.DODGE] = 35
	sgtm.tiers[1].prof_tiers[4] = {prof_threshold = 39}; sgtm.tiers[1].prof_tiers[4].deltas[.DODGE] = 41
	sgtm.tiers[1].prof_tiers[5] = {prof_threshold = 47}; sgtm.tiers[1].prof_tiers[5].deltas[.DODGE] = 48
	sgtm.tiers[2].stat_threshold = 67
	sgtm.tiers[2].prof_tiers[0] = {prof_threshold = 8};  sgtm.tiers[2].prof_tiers[0].deltas[.DODGE] = 20
	sgtm.tiers[2].prof_tiers[1] = {prof_threshold = 16}; sgtm.tiers[2].prof_tiers[1].deltas[.DODGE] = 26
	sgtm.tiers[2].prof_tiers[2] = {prof_threshold = 24}; sgtm.tiers[2].prof_tiers[2].deltas[.DODGE] = 33
	sgtm.tiers[2].prof_tiers[3] = {prof_threshold = 31}; sgtm.tiers[2].prof_tiers[3].deltas[.DODGE] = 40
	sgtm.tiers[2].prof_tiers[4] = {prof_threshold = 39}; sgtm.tiers[2].prof_tiers[4].deltas[.DODGE] = 46
	sgtm.tiers[2].prof_tiers[5] = {prof_threshold = 47}; sgtm.tiers[2].prof_tiers[5].deltas[.DODGE] = 53
	sgtm.tiers[3].stat_threshold = 100
	sgtm.tiers[3].prof_tiers[0] = {prof_threshold = 8};  sgtm.tiers[3].prof_tiers[0].deltas[.DODGE] = 24
	sgtm.tiers[3].prof_tiers[1] = {prof_threshold = 16}; sgtm.tiers[3].prof_tiers[1].deltas[.DODGE] = 30
	sgtm.tiers[3].prof_tiers[2] = {prof_threshold = 24}; sgtm.tiers[3].prof_tiers[2].deltas[.DODGE] = 37
	sgtm.tiers[3].prof_tiers[3] = {prof_threshold = 31}; sgtm.tiers[3].prof_tiers[3].deltas[.DODGE] = 44
	sgtm.tiers[3].prof_tiers[4] = {prof_threshold = 39}; sgtm.tiers[3].prof_tiers[4].deltas[.DODGE] = 51
	sgtm.tiers[3].prof_tiers[5] = {prof_threshold = 47}; sgtm.tiers[3].prof_tiers[5].deltas[.DODGE] = 58
	sg_p.outcomes[0] = Apply_Effect{polarity = .BUFF, to_self = true, duration_s = 480, effect = sgtm}
	sg_p.outcome_count = 1
	kit_skill("Revive", "Revive a fallen ally, restoring them with partial HP. Consumes 3 Holy Water.", .REVIVE, 35, 65, 5, 30, 0).requires.consumable = "holy_water"
	kit_skill("Equine Charge", "Charge at target with your spear", .DAMAGE_PHYSICAL, 45, 19, 0, 9, 0)
	kit_skill("Charge", "Mounted Charge/Dash/Rush (Spear)", .DAMAGE_PHYSICAL, 50, 41, 0, 20, 0)
	kit_skill("Desperado", "Attack Power increased, damage taken increased", .BUFF, 45, 39, 0, 35, 60)
	kit_skill("Skill Focus", "Sacrifice 30% of your current HP to cut CDs by 50%", .UTILITY, 50, 3, 0, 0, 0)
	kit_skill("Deflect (Passive)", "Automatically deflects charge damage when blocking (Shield)", .PASSIVE, 45, 0, 0, 0, 0)
	kit_skill("Bore Brunt", "Take damage for up to three party members", .UTILITY, 50, 16, 4, 1, 300)
	kit_skill("Strong Stance (Passive)", "Can use shield to block magic", .PASSIVE, 45, 0, 0, 0, 0)
	kit_skill("Defensive Attack (Passive)", "Can use offensive skills while blocking", .PASSIVE, 50, 0, 0, 0, 0)
	s = kit_skill("Snipers Nest", "Attack Power, Accuracy, Range buff while stationary (Bow, Crossbow)", .BUFF, 45, 45, 2, 5, 0)
	s.requires.stationary = true
	kit_skill("Kindling Arrow", "AOE fire field (bow)", .FIELD_SPELL, 50, 41, 1, 15, 0)
	kit_skill("Watchful Eye", "Become stationary to see and attack invisible targets", .UTILITY, 45, 44, 2, 20, 0)
	kit_skill("Horse Archer", "Allows you to use certain skills while mounted", .UTILITY, 45, 0, 0, 90, 0)
	kit_skill("Arrow Fusillade (Passive)", "+2 range and double attack with crossbow", .PASSIVE, 50, 0, 0, 0, 0)
	kit_skill("Furtive Steps (Passive)", "No cloaked movement penalty, minor MP regen buff", .PASSIVE, 45, 0, 0, 0, 0)
	kit_skill("Counterpunch", "Weak counter attack with knuckles", .DAMAGE_PHYSICAL, 50, 0, 0, 90, 0)
	kit_skill("Treachery (Passive)", "Can remain cloaked while placing traps", .PASSIVE, 45, 0, 0, 0, 0)
	hp_sanct: Heal_Params; hp_sanct.scope = .PARTY
	kit_skill("Sanctuary", "AOE LP regen", .PARTY_HEAL, 45, 87, 5, 60, 0).outcomes[0] = hp_sanct
	kit_skill("Merciful Blessing (Passive)", "Increase strength of heals, First Aid is instant cast", .PASSIVE, 50, 0, 0, 0, 0)
	kit_skill("Enchantment", "Aura power buff and magical attack power buff", .BUFF, 45, 68, 0.5, 1.5, 480)
	kit_skill("Karmic Aura (Passive)", "Toggle to enable AOE buffs", .PASSIVE, 50, 0, 0, 0, 0)
	kit_skill("Sound Mind (Passive)", "Reduce duration of magic debuffs", .PASSIVE, 45, 0, 0, 0, 0)
	s = kit_skill("Paralyzing Bond", "Root target in place. Both you and target are immobile", .DEBUFF, 50, 47, 0, 30, 10)
	s.outcomes[0] = Apply_Effect{polarity = .DEBUFF, to_self = false, duration_s = 10, effect = CC_Effect{kind = .ROOT}}
	s.outcome_count = 1
	kit_skill("Mana Swap", "Swap MP with target", .UTILITY, 45, 16, 2, 10, 0)
	kit_skill("Soul Swap", "Swap buffs with target", .UTILITY, 50, 21, 1, 10, 0)
	kit_skill("Teleport", "Teleport to target", .UTILITY, 45, 62, 3, 15, 0)
	kit_skill("Memorize", "Cast time reduced, damage increased for next spell", .BUFF, 45, 0, 0, 60, 480)
	s = kit_skill("Intelleto", "Increase INT of all allies", .BUFF, 50, 100, 1, 20, 480)
	s.targeting.aoe_mode = .SELF_CENTERED
	kit_skill("Supreme Mind (Passive)", "INT bonus from gear is doubled", .PASSIVE, 50, 0, 0, 0, 0)
	s = kit_skill("Magical Aid", "Increase magical damage and decrease skill cooldowns", .BUFF, 35, 28, 2, 60, 480)
	s.targeting.aoe_mode = .SELF_CENTERED
	kit_skill("Discomfort (Passive)", "Increase INT based on Darkness proficiency", .PASSIVE, 20, 0, 0, 0, 0)
	kit_skill("Dark Shield (Passive)", "Reduce recoil damage from Gloom", .PASSIVE, 45, 0, 0, 0, 0)
	kit_skill("Median Riding (Passive)", "Gain ability to cast spells while mounted", .PASSIVE, 45, 0, 0, 0, 0)
	// A few more referenced by kits (War Cry / Providence / Rapid Fire / Raging
	// Soul) — buffs without specified magnitudes.
	kit_skill("War Cry", "Increase attack power of all allies", .BUFF, 28, 35, 0.5, 1.5, 480)
	kit_skill("Providence", "+25 magic resistance for yourself and party", .BUFF, 28, 62, 0.5, 1.5, 480)
	kit_skill("Rapid Fire", "Increase attack speed (crossbow)", .BUFF, 35, 45, 0, 45, 0)
	kit_skill("Raging Soul", "Increase attack power of next attack", .BUFF, 35, 35, 0, 60, 30)

	// ── link each job to its class-kit skills (classSkills.ts
	// JOB_TO_CLASS_SKILLS_INDEX → JOB_SKILL_NAMES) ──────────────────────
	kit("warrior",    "Provoke", "Brewer (Passive)", "Lunge")
	kit("gladiator",  "Provoke", "Brewer (Passive)", "Lunge", "Empower (Passive)", "Leg Sweep", "War Cry", "Raging Soul")
	kit("juggernaut", "Provoke", "Brewer (Passive)", "Lunge", "Empower (Passive)", "Leg Sweep", "War Cry", "Raging Soul", "Desperado", "Skill Focus")
	kit("dragoon",    "Provoke", "Brewer (Passive)", "Lunge", "Empower (Passive)", "Leg Sweep", "War Cry", "Raging Soul", "Equine Charge", "Jousting (Passive)", "Charge")
	kit("knight",     "Provoke", "Brewer (Passive)", "Lunge", "Obscene Gesture", "Providence")
	kit("warlord",    "Provoke", "Brewer (Passive)", "Lunge", "Obscene Gesture", "Providence")
	kit("paladin",    "Provoke", "Brewer (Passive)", "Lunge", "Obscene Gesture", "Providence", "Strong Stance (Passive)", "Jousting (Passive)", "Defensive Attack (Passive)")
	kit("scout",      "Invigorate", "Hide")
	kit("archer",     "Invigorate", "Hide", "Hawkeye (Passive)", "Accelerate", "Rapid Fire")
	kit("sniper",     "Invigorate", "Hide", "Hawkeye (Passive)", "Accelerate", "Rapid Fire", "Snipers Nest", "Kindling Arrow")
	kit("hunter",     "Invigorate", "Hide", "Hawkeye (Passive)", "Accelerate", "Rapid Fire", "Watchful Eye", "Horse Archer", "Arrow Fusillade (Passive)")
	kit("provocateur","Invigorate", "Hide", "Shifty (Passive)", "Cloak", "Third Eye")
	kit("assassin",   "Invigorate", "Hide", "Shifty (Passive)", "Cloak", "Third Eye", "Furtive Steps (Passive)", "Counterpunch")
	kit("saboteur",   "Invigorate", "Hide", "Shifty (Passive)", "Cloak", "Third Eye", "Treachery (Passive)")
	kit("acolyte",    "Meditation (Passive)", "Heal")
	kit("priest",     "Meditation (Passive)", "Heal", "Inspiration (Passive)", "Tranquil Mind", "Divine Aid", "Revive")
	kit("cleric",     "Meditation (Passive)", "Heal", "Inspiration (Passive)", "Tranquil Mind", "Divine Aid", "Revive", "Sanctuary", "Merciful Blessing (Passive)")
	kit("enchanter",  "Meditation (Passive)", "Heal", "Inspiration (Passive)", "Tranquil Mind", "Revive", "Enchantment", "Karmic Aura (Passive)")
	kit("ascetic",    "Meditation (Passive)", "Heal", "Blessed Garments (Passive)", "Mana Restore", "Speedy Gale")
	kit("monk",       "Meditation (Passive)", "Heal", "Blessed Garments (Passive)", "Mana Restore", "Speedy Gale", "Sound Mind (Passive)", "Paralyzing Bond")
	kit("exorcist",   "Meditation (Passive)", "Heal", "Blessed Garments (Passive)", "Mana Restore", "Speedy Gale", "Mana Swap", "Soul Swap")
	kit("mage",       "Fire Bolt", "Shock")
	kit("wizard",     "Fire Bolt", "Shock", "Scholar (Passive)", "Thunder Crash")
	kit("warlock",    "Fire Bolt", "Shock", "Scholar (Passive)", "Thunder Crash", "Magical Aid")
	kit("conjurer",   "Fire Bolt", "Shock", "Scholar (Passive)", "Thunder Crash", "Teleport", "Memorize", "Intelleto", "Supreme Mind (Passive)")
	kit("sorcerer",   "Fire Bolt", "Shock", "Shadow Garments (Passive)")
	kit("corruptor",  "Fire Bolt", "Shock", "Shadow Garments (Passive)", "Discomfort (Passive)")
	kit("shadowblade","Fire Bolt", "Shock", "Shadow Garments (Passive)", "Dark Shield (Passive)", "Median Riding (Passive)")
}

destroy_game_data :: proc() {
	// Skill / race / job display names in the sample are string literals (static
	// storage), so only the containers and per-job kit lists need freeing.
	for j in 0 ..< registry_count(&job_registry) {
		delete(registry_get(&job_registry, Job_Id(u16(j))).kit_skill_ids)
	}
	registry_destroy(&race_registry)
	registry_destroy(&job_registry)
	registry_destroy(&skill_registry)
	for sc in Sub_Category do delete(tree_skills[sc])
	game_data_loaded = false
}

// LP/MP growth formulas (port of classes.ts:76-88). Used by B4 once jobs load.
calculate_max_lp :: proc(j: ^Job_Def, level: int, sta: f32) -> f32 {
	level_component := math.ceil(f32(level) * (100.0 / j.lp_per_level))
	sta_mult := math.ceil(100.0 / j.lp_per_sta)
	sta_component := math.ceil(sta * f32(sta_mult))
	return j.lp_base + f32(level_component) + f32(sta_component)
}

calculate_max_mp :: proc(j: ^Job_Def, level: int, spi: f32) -> f32 {
	level_component := math.ceil(f32(level) * (100.0 / j.mp_per_level))
	spi_mult := math.ceil(100.0 / j.mp_per_spi)
	spi_component := math.ceil(spi * f32(spi_mult))
	return j.mp_base + f32(level_component) + f32(spi_component)
}
