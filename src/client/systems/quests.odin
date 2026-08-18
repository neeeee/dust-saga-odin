package systems

import "core:fmt"
import rl "vendor:raylib"

// ── quest log state (mirrors shared/src/types/quests.ts ActiveQuest) ───────

Quest_Status :: enum u8 {
	AVAILABLE,
	IN_PROGRESS,
	COMPLETED,
	TURNED_IN,
}

quest_status_from_string :: proc "contextless" (s: string) -> Quest_Status {
	switch s {
	case "available":   return .AVAILABLE
	case "in_progress": return .IN_PROGRESS
	case "completed":   return .COMPLETED
	case "turned_in":   return .TURNED_IN
	case:               return .IN_PROGRESS
	}
}

Quest_Objective :: struct {
	type_str:    [16]u8,
	type_len:    int,
	target_name: [64]u8,
	target_len:  int,
	required:    int,
	current:     int,
}

Active_Quest :: struct {
	quest_id:        [64]u8,
	quest_id_len:    int,
	title:           [96]u8,
	title_len:       int,
	description:     [192]u8,
	description_len: int,
	status:          Quest_Status,
	objectives:      [dynamic]Quest_Objective,
}

objective_name_string :: proc "contextless" (o: ^Quest_Objective) -> string {
	return string(o.target_name[:o.target_len])
}

objective_type_string :: proc "contextless" (o: ^Quest_Objective) -> string {
	return string(o.type_str[:o.type_len])
}

objective_complete :: proc "contextless" (o: ^Quest_Objective) -> bool {
	return o.current >= o.required
}

quest_id_string :: proc "contextless" (q: ^Active_Quest) -> string {
	return string(q.quest_id[:q.quest_id_len])
}

quest_title_string :: proc "contextless" (q: ^Active_Quest) -> string {
	return string(q.title[:q.title_len])
}

quest_description_string :: proc "contextless" (q: ^Active_Quest) -> string {
	return string(q.description[:q.description_len])
}

quest_find :: proc(p: ^Local_Player, quest_id: string) -> ^Active_Quest {
	if len(quest_id) == 0 do return nil
	for i in 0 ..< len(p.quests) {
		q := &p.quests[i]
		if quest_id_string(q) == quest_id do return q
	}
	return nil
}

clear_quest_list :: proc(list: ^[dynamic]Active_Quest) {
	for i in 0 ..< len(list^) {
		delete(list^[i].objectives)
	}
	clear(list)
}

parse_quest_objective :: proc(oo: JSON_Object, out: ^Quest_Objective) {
	out^ = {}
	copy_string_to_buffer(out.type_str[:], &out.type_len, get_string(oo, "type"))
	copy_string_to_buffer(out.target_name[:], &out.target_len, get_string(oo, "targetName"))
	out.required = get_int(oo, "requiredCount", 1)
	out.current = get_int(oo, "currentCount")
}

quest_from_object :: proc(qo: JSON_Object) -> Active_Quest {
	q: Active_Quest
	q.objectives = make([dynamic]Quest_Objective)
	copy_string_to_buffer(q.quest_id[:], &q.quest_id_len, get_string(qo, "questId"))
	copy_string_to_buffer(q.title[:], &q.title_len, get_string(qo, "title"))
	copy_string_to_buffer(q.description[:], &q.description_len, get_string(qo, "description"))
	q.status = quest_status_from_string(get_string(qo, "status", "in_progress"))
	objs := as_dyn(get_array(qo, "objectives"))
	for j in 0 ..< len(objs) {
		obj: Quest_Objective
		parse_quest_objective(obj_of(objs[j]), &obj)
		append(&q.objectives, obj)
	}
	return q
}

// Replace the quest log with the server's `quests` array payload.
parse_quest_array :: proc(arr: JSON_Array, list: ^[dynamic]Active_Quest) {
	clear_quest_list(list)
	dyn := as_dyn(arr)
	for i in 0 ..< len(dyn) {
		append(list, quest_from_object(obj_of(dyn[i])))
	}
}

// ── NPC dialog state (from the NPC_DIALOG payload) ─────────────────────────

Dialog_Mode :: enum u8 {
	NPC_PAGE,
	QUEST_OFFER,
	QUEST_ACTIVE,
}

MAX_DIALOG_PAGE_OPTIONS :: 6
MAX_DIALOG_OFFERS :: 6
MAX_DIALOG_ACTIVES :: 8
MAX_DIALOG_OBJECTIVES :: 6
MAX_DIALOG_SHOP_ENTRIES :: 24

Dialog_Page_Option :: struct {
	label:         [96]u8,
	label_len:     int,
	next_id:       [64]u8,
	next_id_len:   int,
	has_next:      bool,
	action:        [32]u8,
	action_len:    int,
	quest_id:      [64]u8,
	quest_id_len:  int,
}

dialog_option_label_string :: proc "contextless" (o: ^Dialog_Page_Option) -> string {
	return string(o.label[:o.label_len])
}

dialog_option_next_string :: proc "contextless" (o: ^Dialog_Page_Option) -> string {
	return string(o.next_id[:o.next_id_len])
}

dialog_option_action_string :: proc "contextless" (o: ^Dialog_Page_Option) -> string {
	return string(o.action[:o.action_len])
}

dialog_option_quest_string :: proc "contextless" (o: ^Dialog_Page_Option) -> string {
	return string(o.quest_id[:o.quest_id_len])
}

Dialog_Offer :: struct {
	quest_id:       [64]u8,
	quest_id_len:   int,
	title:          [96]u8,
	title_len:      int,
	text:           [512]u8,
	text_len:       int,
	rewards:        [160]u8,
	rewards_len:    int,
	required_level: int,
}

dialog_offer_id_string :: proc "contextless" (o: ^Dialog_Offer) -> string {
	return string(o.quest_id[:o.quest_id_len])
}

dialog_offer_title_string :: proc "contextless" (o: ^Dialog_Offer) -> string {
	return string(o.title[:o.title_len])
}

dialog_offer_text_string :: proc "contextless" (o: ^Dialog_Offer) -> string {
	return string(o.text[:o.text_len])
}

dialog_offer_rewards_string :: proc "contextless" (o: ^Dialog_Offer) -> string {
	return string(o.rewards[:o.rewards_len])
}

Dialog_Active :: struct {
	quest_id:       [64]u8,
	quest_id_len:   int,
	title:          [96]u8,
	title_len:      int,
	status:         Quest_Status,
	turn_in_ready:  bool,
	objectives:     [MAX_DIALOG_OBJECTIVES]Quest_Objective,
	objective_count: int,
	text:           [512]u8,
	text_len:       int,
}

dialog_active_id_string :: proc "contextless" (a: ^Dialog_Active) -> string {
	return string(a.quest_id[:a.quest_id_len])
}

dialog_active_title_string :: proc "contextless" (a: ^Dialog_Active) -> string {
	return string(a.title[:a.title_len])
}

dialog_active_text_string :: proc "contextless" (a: ^Dialog_Active) -> string {
	return string(a.text[:a.text_len])
}

Dialog_State :: struct {
	open:              bool,
	mode:              Dialog_Mode,
	rect:              rl.Rectangle,
	npc_id:            [64]u8,
	npc_id_len:        int,
	npc_name:          [96]u8,
	npc_name_len:      int,
	page_text:         [768]u8,
	page_text_len:     int,
	page_options:      [MAX_DIALOG_PAGE_OPTIONS]Dialog_Page_Option,
	page_option_count: int,
	offers:            [MAX_DIALOG_OFFERS]Dialog_Offer,
	offer_count:       int,
	actives:           [MAX_DIALOG_ACTIVES]Dialog_Active,
	active_count:      int,
	selected_offer:    int,
	selected_active:   int,
	abandon_confirm:   bool,
	shop_entries:      [MAX_DIALOG_SHOP_ENTRIES]Shop_Entry,
	shop_count:        int,
}

dialog_close :: proc(d: ^Dialog_State) {
	d.open = false
}

dialog_npc_id_string :: proc "contextless" (d: ^Dialog_State) -> string {
	return string(d.npc_id[:d.npc_id_len])
}

dialog_npc_name_string :: proc "contextless" (d: ^Dialog_State) -> string {
	return string(d.npc_name[:d.npc_name_len])
}

dialog_page_text_string :: proc "contextless" (d: ^Dialog_State) -> string {
	return string(d.page_text[:d.page_text_len])
}

// Append `s` to a fixed buffer, optionally separated by `sep` when the buffer
// already holds content. Truncates silently when full.
append_to_buffer :: proc "contextless" (dst: []u8, dst_len: ^int, s: string, sep: string) {
	if dst_len^ >= len(dst) do return
	if len(sep) > 0 && dst_len^ > 0 {
		n := min(len(sep), len(dst) - dst_len^)
		copy(dst[dst_len^:dst_len^ + n], transmute([]u8)sep[:n])
		dst_len^ += n
	}
	n := min(len(s), len(dst) - dst_len^)
	copy(dst[dst_len^:dst_len^ + n], transmute([]u8)s[:n])
	dst_len^ += n
}

append_dialog_pages :: proc(dst: []u8, dst_len: ^int, pages: JSON_Array) {
	dyn := as_dyn(pages)
	for i in 0 ..< len(dyn) {
		po := obj_of(dyn[i])
		append_to_buffer(dst, dst_len, get_string(po, "text"), " ")
	}
}

dialog_append_rewards_line :: proc(dst: []u8, dst_len: ^int, rew: JSON_Object) {
	xp := get_int(rew, "experience")
	gold := get_int(rew, "gold")
	append_to_buffer(dst, dst_len, fmt.tprintf("%d XP", xp), "")
	items := as_dyn(get_array(rew, "items"))
	for i in 0 ..< len(items) {
		it := obj_of(items[i])
		qty := get_int(it, "quantity")
		name := item_name(get_string(it, "itemId"))
		if qty > 1 {
			append_to_buffer(dst, dst_len, fmt.tprintf(", %s x%d", name, qty), "")
		} else {
			append_to_buffer(dst, dst_len, fmt.tprintf(", %s", name), "")
		}
	}
	if gold > 0 {
		append_to_buffer(dst, dst_len, fmt.tprintf(", %d gold", gold), "")
	}
}

shop_category_from_item_type :: proc "contextless" (t: string) -> Shop_Category {
	switch t {
	case "weapon":                                       return .WEAPONS
	case "armor", "helmet", "boots", "gloves", "legs", "shield":
		return .ARMOR
	case "consumable":                                   return .CONSUMABLES
	case "material", "quest":                            return .MATERIALS
	case "ring", "necklace", "belt", "earring", "accessory":
		return .ACCESSORIES
	case:                                                return .ALL
	}
}

shop_rarity_from_string :: proc "contextless" (s: string) -> Shop_Rarity {
	switch s {
	case "uncommon":  return .UNCOMMON
	case "rare":      return .RARE
	case "epic":      return .EPIC
	case "legendary": return .LEGENDARY
	case:             return .COMMON
	}
}

// Fill the dialog state from an NPC_DIALOG payload. An absent/null `dialog`
// field is the server's "conversation closed" signal.
dialog_load_from_packet :: proc(d: ^Dialog_State, o: JSON_Object) {
	dlg_v := field(o, "dialog")
	if is_null(dlg_v) {
		dialog_close(d)
		return
	}
	dlg := obj_of(dlg_v)

	d.open = true
	d.mode = .NPC_PAGE
	d.abandon_confirm = false
	d.selected_offer = 0
	d.selected_active = 0
	copy_string_to_buffer(d.npc_id[:], &d.npc_id_len, get_string(o, "npcId"))
	copy_string_to_buffer(d.npc_name[:], &d.npc_name_len, get_string(o, "npcName"))

	d.page_text_len = 0
	append_to_buffer(d.page_text[:], &d.page_text_len, get_string(dlg, "text"), "")

	d.page_option_count = 0
	opts := as_dyn(get_array(dlg, "options"))
	for i in 0 ..< len(opts) {
		if d.page_option_count >= MAX_DIALOG_PAGE_OPTIONS do break
		oo := obj_of(opts[i])
		po := &d.page_options[d.page_option_count]
		po^ = {}
		copy_string_to_buffer(po.label[:], &po.label_len, get_string(oo, "text"))
		next := get_string(oo, "nextDialogId")
		po.has_next = len(next) > 0
		if po.has_next {
			copy_string_to_buffer(po.next_id[:], &po.next_id_len, next)
		}
		copy_string_to_buffer(po.action[:], &po.action_len, get_string(oo, "action"))
		ad := get_object(oo, "actionData")
		copy_string_to_buffer(po.quest_id[:], &po.quest_id_len, get_string(ad, "questId"))
		d.page_option_count += 1
	}

	d.offer_count = 0
	offers := as_dyn(get_array(o, "availableQuests"))
	for i in 0 ..< len(offers) {
		if d.offer_count >= MAX_DIALOG_OFFERS do break
		fo := obj_of(offers[i])
		of := &d.offers[d.offer_count]
		of^ = {}
		copy_string_to_buffer(of.quest_id[:], &of.quest_id_len, get_string(fo, "id"))
		copy_string_to_buffer(of.title[:], &of.title_len, get_string(fo, "title"))
		of.text_len = 0
		append_dialog_pages(of.text[:], &of.text_len, get_array(fo, "offerDialog"))
		if of.text_len == 0 {
			copy_string_to_buffer(of.text[:], &of.text_len, get_string(fo, "description"))
		}
		of.rewards_len = 0
		dialog_append_rewards_line(of.rewards[:], &of.rewards_len, get_object(fo, "rewards"))
		of.required_level = get_int(fo, "requiredLevel", 1)
		d.offer_count += 1
	}

	d.active_count = 0
	actives := as_dyn(get_array(o, "activeQuests"))
	for i in 0 ..< len(actives) {
		if d.active_count >= MAX_DIALOG_ACTIVES do break
		ao := obj_of(actives[i])
		aq := &d.actives[d.active_count]
		aq^ = {}
		copy_string_to_buffer(aq.quest_id[:], &aq.quest_id_len, get_string(ao, "id"))
		copy_string_to_buffer(aq.title[:], &aq.title_len, get_string(ao, "title"))
		aq.status = quest_status_from_string(get_string(ao, "status", "in_progress"))
		aq.turn_in_ready = get_bool(ao, "turnInReady")
		aq.objective_count = 0
		objs := as_dyn(get_array(ao, "objectives"))
		for j in 0 ..< len(objs) {
			if aq.objective_count >= MAX_DIALOG_OBJECTIVES do break
			parse_quest_objective(obj_of(objs[j]), &aq.objectives[aq.objective_count])
			aq.objective_count += 1
		}
		aq.text_len = 0
		key := aq.turn_in_ready ? "turnInDialog" : "inProgressDialog"
		append_dialog_pages(aq.text[:], &aq.text_len, get_array(ao, key))
		if aq.text_len == 0 {
			copy_string_to_buffer(aq.text[:], &aq.text_len, get_string(ao, "description"))
		}
		d.active_count += 1
	}

	d.shop_count = 0
	shop := as_dyn(get_array(o, "shopItems"))
	for i in 0 ..< len(shop) {
		if d.shop_count >= MAX_DIALOG_SHOP_ENTRIES do break
		so := obj_of(shop[i])
		e := &d.shop_entries[d.shop_count]
		e^ = {}
		copy_string_to_buffer(e.id[:], &e.id_len, get_string(so, "id"))
		copy_string_to_buffer(e.name[:], &e.name_len, get_string(so, "name"))
		e.category = shop_category_from_item_type(get_string(so, "type"))
		e.rarity = shop_rarity_from_string(get_string(so, "rarity"))
		e.price = i64(get_int(so, "sellPrice") * 2)
		d.shop_count += 1
	}
}
