class_name WildCoopMaterials
extends RefCounted
## 公共材料源由房主显式绑定；预留从动作推导，不能将公共箱冒充私人背包。
const ACTIONS: Array[String] = ["build","upgrade","craft","cook","fuel","trap_bait","trap_maintain"]

static func bind(room: WildCoopState, actor: String, box_id: String) -> void:
	var personal: WildBaseState = room.members[actor]
	personal.material_sources.clear()
	personal.material_reserved.clear()
	if room.boxes.has(box_id): personal.material_sources[box_id] = room.boxes[box_id]
	for other: String in room.survival.actions:
		if other == actor: continue
		for reserved: Dictionary in room.survival.actions[other]["reservations"]:
			personal.material_reserved[reserved["id"]] = int(personal.material_reserved.get(reserved["id"],0))+int(reserved["quantity"])

static func bind_actions(room: WildCoopState) -> void:
	for actor: String in room.members: bind(room,actor,str(room.survival.actions.get(actor,{}).get("materials_box","")))

static func locked(room: WildCoopState, item_id: String) -> bool:
	for action: Dictionary in room.survival.actions.values():
		for reserved: Dictionary in action["reservations"]:
			if reserved["id"] == item_id: return true
	return false

static func valid(room: WildCoopState) -> bool:
	var totals: Dictionary = {}
	for actor: String in room.survival.actions:
		for reserved: Dictionary in room.survival.actions[actor]["reservations"]:
			var id: String = reserved["id"]
			var found: Dictionary = WildInventoryOperations.find(room.members[actor],id)
			if found.is_empty(): return false
			totals[id] = int(totals.get(id,0))+int(reserved["quantity"])
			if totals[id] > (found["item"] as WildItemInstance).quantity: return false
	return true
