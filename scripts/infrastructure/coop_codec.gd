class_name WildCoopCodec
extends RefCounted
## 房主档案严格恢复。复用私人库存 / 世界 / 身体校验，再验证跨人实例守恒。

static func decode(raw: Dictionary, config: WildGameConfig, catalog: WildItemCatalog, content: WildSurvivalContent) -> WildCoopState:
	if raw.get("coop_save_version",0) != 1 or not raw.get("started",null) is bool or not WildDataValidation.whole(raw.get("revision",null)) or raw["revision"] < 0: return null
	for field: String in ["room_id","run_id","host_id"]:
		if not raw.get(field,null) is String or raw[field].is_empty(): return null
	for field: String in ["members","names","token_hashes","boxes","world","survival","receipts"]:
		if not raw.get(field,null) is Dictionary: return null
	if raw["members"].size() not in [1,2] or raw["names"].size() != raw["members"].size() or raw["token_hashes"].size() != raw["members"].size(): return null
	var room := WildCoopState.new()
	room.room_id = raw["room_id"]
	room.run_id = raw["run_id"]
	room.host_id = raw["host_id"]
	room.started = raw["started"]
	room.revision = int(raw["revision"])
	room.world = WildWorldCodec.decode(raw["world"],config)
	if room.world == null: return null
	var ids: Dictionary = {}
	for actor: Variant in raw["members"]:
		if not actor is String or actor.is_empty() or not raw["members"][actor] is Dictionary or not raw["names"].get(actor,null) is String or not raw["token_hashes"].get(actor,null) is String or raw["token_hashes"][actor].length() != 64: return null
		var personal: WildBaseState = WildBaseStateCodec.decode(raw["members"][actor],actor,config,catalog)
		if personal == null or personal.phase != WildRunFlow.Phase.BASE or not room.world.players.has(actor): return null
		for container: WildInventoryContainer in personal.containers.values():
			for id: String in container.placements:
				if ids.has(id): return null
				ids[id] = true
		personal.world = room.world
		room.members[actor] = personal
	if not room.members.has(room.host_id) or room.world.players.size() != room.members.size(): return null
	room.survival = WildSurvivalCodec.decode(raw["survival"],room.members[room.host_id],config,catalog,room.members)
	if room.survival == null: return null
	if (room.started and room.members.size() != 2) or (not room.started and room.survival.elapsed_seconds != 0): return null
	room.bind_shared()
	for actor: String in room.survival.actions:
		if not WildCoopReservations.validate(room.survival,actor,room.survival.actions[actor],content).successful: return null
	for output: Dictionary in room.survival.outputs.values():
		for item: Dictionary in output["items"]:
			if ids.has(item["id"]): return null
			ids[item["id"]] = true
	for id: Variant in raw["boxes"]:
		if not id is String or not id.begins_with("camp_box:"): return null
		var building_id: String = id.trim_prefix("camp_box:")
		if not room.survival.buildings.has(building_id) or room.survival.buildings[building_id]["kind"] != "storage_box": return null
		var stored: Variant = raw["boxes"][id]
		if not stored is Dictionary or stored.get("id",null) != id or not WildDataValidation.whole(stored.get("version",null)) or stored["version"] < 0 or not stored.get("entries",null) is Array: return null
		var box := WildInventoryContainer.new(id,"",config.camp_storage_grid,config.camp_storage_capacity_l)
		box.public_access = true
		for entry: Variant in stored["entries"]:
			if not entry is Dictionary or not WildSurvivalCodec.item_record_valid(entry.get("item"),catalog) or not entry.get("rotated",null) is bool or not entry.get("position",null) is Array or entry["position"].size() != 2: return null
			var position: Array = entry["position"]
			if not WildDataValidation.whole(position[0]) or not WildDataValidation.whole(position[1]): return null
			var item: WildItemInstance = WildItemInstance.from_record(entry["item"])
			if ids.has(item.instance_id) or not WildInventoryRules.can_place(room.members[room.host_id],catalog,config,room.host_id,box,item,Vector2i(position[0],position[1]),entry["rotated"]).successful: return null
			ids[item.instance_id] = true
			box.placements[item.instance_id] = {"item":item,"position":Vector2i(position[0],position[1]),"rotated":entry["rotated"]}
		box.version = int(stored["version"])
		room.boxes[id] = box
	for id: String in room.survival.buildings:
		if room.survival.buildings[id]["kind"] == "storage_box" and not room.boxes.has("camp_box:"+id): return null
	for receipt: Variant in raw["receipts"].values():
		if not receipt is Dictionary or not receipt.get("signature",null) is String or not receipt.get("successful",null) is bool or not receipt.get("code",null) is String or not receipt.get("payload",null) is Dictionary: return null
	room.names = raw["names"].duplicate(true)
	room.token_hashes = raw["token_hashes"].duplicate(true)
	room.receipts = raw["receipts"].duplicate(true)
	return room
