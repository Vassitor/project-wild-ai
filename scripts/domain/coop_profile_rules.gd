class_name WildCoopProfileRules
extends RefCounted
## 个人档案的物资租约 / 单调收据。世界接收前先锁物资，断线不自动归还。
const SLOTS: Array[String] = ["backpack","main_hand","off_hand","armor"]

static func blocked(state: WildBaseState) -> bool:
	return not state.cooperation["active"].is_empty()

static func execute(state: WildBaseState, operation: String, data: Dictionary, config: WildGameConfig, catalog: WildItemCatalog) -> WildOperationResult:
	if state.phase != WildRunFlow.Phase.BASE: return WildOperationResult.reject(&"INVALID_PHASE")
	if operation == "coop.reserve":
		if blocked(state):
			var existing: Dictionary = state.cooperation["active"]["manifest"]
			return WildOperationResult.accept({"manifest":existing.duplicate(true)}) if data.get("room_id","") == existing["room_id"] and data.get("run_id","") == existing["run_id"] else WildOperationResult.reject(&"COOP_RESERVED")
		for key: String in ["room_id","run_id"]:
			if not data.get(key,null) is String or data[key].is_empty() or data[key].length() > 128: return WildOperationResult.reject(&"INVALID_REQUEST")
		var manifest: Dictionary = {"version":1,"room_id":data["room_id"],"run_id":data["run_id"],"owner":state.player_id,"lease_id":WildStableId.create("lease"),"skills":state.skills.record(),"currency":state.currency,"slots":{}}
		for slot: String in SLOTS:
			manifest["slots"][slot] = state.containers[slot].record()
			state.containers[slot].placements.clear()
			state.containers[slot].version += 1
		manifest["hash"] = digest(manifest)
		state.cooperation["active"] = {"manifest":manifest,"seq":0,"hash":"","terminal":false}
		return WildOperationResult.accept({"manifest":manifest.duplicate(true)})
	if operation == "coop.apply_event": return apply_event(state,data,config,catalog)
	return WildOperationResult.reject(&"UNKNOWN_COMMAND")

static func digest(data: Dictionary) -> String:
	var copy: Dictionary = data.duplicate(true)
	copy.erase("hash")
	return WildCanonicalData.digest(copy)

## 用已有库存 / 技能解码器检查个人提交，仓库与已结算收据从不发送到房主。
static func manifest_state(packet: Variant, config: WildGameConfig, catalog: WildItemCatalog) -> WildBaseState:
	if not packet is Dictionary or packet.get("version",0) != 1 or not packet.get("hash",null) is String or digest(packet) != packet["hash"]: return null
	for key: String in ["room_id","run_id","owner","lease_id"]:
		if not packet.get(key,null) is String or packet[key].is_empty() or packet[key].length() > 128: return null
	if not packet.get("slots",null) is Dictionary or packet["slots"].size() != 4: return null
	var raw: Dictionary = WildBaseState.new(packet["owner"],config).record()
	raw["skills"] = packet.get("skills",null)
	raw["currency"] = packet.get("currency",null)
	for slot: String in SLOTS:
		if not packet["slots"].get(slot,null) is Dictionary: return null
		raw["containers"][slot] = packet["slots"][slot]
	return WildBaseStateCodec.decode(raw,packet["owner"],config,catalog)

static func event_valid(event: Variant, config: WildGameConfig, catalog: WildItemCatalog) -> bool:
	if not event is Dictionary or event.get("version",0) != 1 or not event.get("hash",null) is String or digest(event) != event["hash"]: return false
	for key: String in ["room_id","run_id","owner","lease_id","event_id","reason"]:
		if not event.get(key,null) is String or event[key].length() > 256 or (event[key].is_empty() and key != "reason"): return false
	if not WildDataValidation.whole(event.get("seq",null)) or event["seq"] < 1 or event.get("kind","") not in ["accepted","growth","release","settlement"]: return false
	if event["event_id"] != "%s:%d" % [event["lease_id"],event["seq"]]: return false
	if not WildDataValidation.whole(event.get("reward",null)) or event["reward"] < 0 or event["reward"] > config.success_base_reward+190 or not event.get("won",null) is bool or not WildDataValidation.number(event.get("elapsed_seconds",null)) or event["elapsed_seconds"] < 0: return false
	if not event.get("items",null) is Array or WildSkillCodec.decode(event.get("skills",null),config.skill_rules) == null: return false
	if event["kind"] != "settlement" and (event["reward"] != 0 or not event["items"].is_empty() or event["won"]): return false
	if event["kind"] == "settlement" and not event["won"] and (event["reward"] != 0 or not event["items"].is_empty()): return false
	if event.has("report") and (event["kind"] != "settlement" or not WildExpeditionReport.valid(event["report"],int(event["reward"]),event["won"])): return false
	var ids: Dictionary = {}
	var units: int = 0
	for entry: Variant in event["items"]:
		if not entry is Dictionary or not entry.get("rotated",null) is bool or not WildSurvivalCodec.item_record_valid(entry.get("item",null),catalog) or ids.has(entry["item"]["id"]): return false
		ids[entry["item"]["id"]] = true
		units += int(entry["item"]["quantity"])
	if event.has("report") and (event["report"]["returned_units"] != units or event["report"]["returned_stacks"] != event["items"].size()): return false
	return true

## 收据先校验租约与序号，再原子应用技能 / 返仓 / 奖励。旧收据不会覆盖较新成长。
static func apply_event(state: WildBaseState, event: Dictionary, config: WildGameConfig, catalog: WildItemCatalog) -> WildOperationResult:
	if not event_valid(event,config,catalog) or event["owner"] != state.player_id: return WildOperationResult.reject(&"INVALID_DELIVERY")
	var lease: String = event["lease_id"]
	var active: Dictionary = state.cooperation["active"]
	var history: Dictionary = state.cooperation["history"].get(lease,{})
	var record: Dictionary = active if not active.is_empty() and active["manifest"]["lease_id"] == lease else history
	if record.is_empty(): return WildOperationResult.reject(&"UNKNOWN_LEASE")
	var identity: Dictionary = record.get("manifest",record)
	if event["room_id"] != identity["room_id"] or event["run_id"] != identity["run_id"]: return WildOperationResult.reject(&"WRONG_SESSION")
	if int(event["seq"]) <= int(record["seq"]):
		if int(event["seq"]) == int(record["seq"]) and event["hash"] != record["hash"]: return WildOperationResult.reject(&"REQUEST_ID_CONFLICT")
		return WildOperationResult.accept({"event_id":event["event_id"]})
	if record["terminal"]: return WildOperationResult.reject(&"LEASE_CLOSED")
	var profile: WildSkillProfile = WildSkillCodec.decode(event["skills"],config.skill_rules)
	for branch: String in WildSkillCatalog.BRANCHES:
		if profile.experience[branch] < state.skills.experience[branch] or profile.levels[branch] < state.skills.levels[branch] or profile.spent_points[branch] < state.skills.spent_points[branch]: return WildOperationResult.reject(&"INVALID_DELIVERY")
	state.skills = profile
	if event["kind"] == "release":
		var prepared: WildBaseState = manifest_state(active["manifest"],config,catalog)
		if prepared == null: return WildOperationResult.reject(&"INVALID_DELIVERY")
		for slot: String in SLOTS: state.containers[slot] = prepared.containers[slot].copy()
	elif event["kind"] == "settlement":
		var returned: Array[Dictionary] = []
		var existing_ids: Dictionary = {}
		for container: WildInventoryContainer in state.containers.values():
			for id: String in container.placements: existing_ids[id] = true
		for item: Dictionary in state.pending: existing_ids[item["id"]] = true
		for entry: Dictionary in event["items"]:
			if existing_ids.has(entry["item"]["id"]): return WildOperationResult.reject(&"INVALID_DELIVERY")
			returned.append({"item":WildItemInstance.from_record(entry["item"]),"rotated":entry["rotated"]})
		WildReturnInventory.apply(state,returned,config,catalog)
		state.currency += int(event["reward"])
		state.last_settlement = {"run_id":event["run_id"],"won":event["won"],"reward":event["reward"],"elapsed_seconds":event["elapsed_seconds"],"reason":event["reason"],"pending_count":state.pending.size()}
		if event.has("report"): state.last_settlement["report"] = event["report"].duplicate(true)
	record["seq"] = int(event["seq"])
	record["hash"] = event["hash"]
	if event["kind"] in ["release","settlement"]:
		state.cooperation["history"][lease] = {"room_id":event["room_id"],"run_id":event["run_id"],"seq":int(event["seq"]),"hash":event["hash"],"terminal":true}
		state.cooperation["active"] = {}
	return WildOperationResult.accept({"event_id":event["event_id"]})

static func restore(raw: Variant, state: WildBaseState, config: WildGameConfig, catalog: WildItemCatalog) -> bool:
	if raw == null: return true
	if not raw is Dictionary or raw.get("version",0) != 1 or not raw.get("active",null) is Dictionary or not raw.get("history",null) is Dictionary: return false
	var active: Dictionary = raw["active"]
	if not active.is_empty():
		var prepared: WildBaseState = manifest_state(active.get("manifest",null),config,catalog)
		if prepared == null or prepared.player_id != state.player_id or state.phase != WildRunFlow.Phase.BASE or not _receipt_valid(active): return false
		if active["terminal"] or raw["history"].has(active["manifest"]["lease_id"]) or (active["seq"] == 0 and active["hash"] != "") or (active["seq"] > 0 and active["hash"].length() != 64): return false
		for branch: String in WildSkillCatalog.BRANCHES:
			if state.skills.experience[branch] < prepared.skills.experience[branch] or state.skills.levels[branch] < prepared.skills.levels[branch]: return false
		for slot: String in SLOTS:
			if not state.containers[slot].placements.is_empty(): return false
		var escrow_ids: Dictionary = {}
		for slot: String in SLOTS:
			for id: String in prepared.containers[slot].placements: escrow_ids[id] = true
		for id: String in state.containers["warehouse"].placements:
			if escrow_ids.has(id): return false
		for item: Dictionary in state.pending:
			if escrow_ids.has(item["id"]): return false
	for key: Variant in raw["history"]:
		var record: Variant = raw["history"][key]
		if not key is String or not record is Dictionary or not _receipt_valid(record) or not record["terminal"] or record["seq"] < 2 or record["hash"].length() != 64 or not record.get("room_id",null) is String or not record.get("run_id",null) is String: return false
	state.cooperation = raw.duplicate(true)
	return true

static func _receipt_valid(record: Dictionary) -> bool:
	return WildDataValidation.whole(record.get("seq",null)) and record["seq"] >= 0 and record.get("hash",null) is String and record.get("terminal",null) is bool
