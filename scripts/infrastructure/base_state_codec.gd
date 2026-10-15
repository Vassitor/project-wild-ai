class_name WildBaseStateCodec
extends RefCounted
## 把 JSON 基础字段恢复为领域对象。几何 / 体积 / 重量重新校验，绝不信任存档容量。


static func decode(data: Dictionary, owner: String, config: WildGameConfig, catalog: WildItemCatalog) -> WildBaseState:
	if data.get("save_version", 0) != 1 or data.get("player_id", "") != owner:
		return null
	if not whole(data.get("currency", -1)) or float(data["currency"]) < 0.0 or not whole(data.get("phase", -1)):
		return null
	var phase_value: int = int(data["phase"])
	if phase_value not in [WildRunFlow.Phase.BASE, WildRunFlow.Phase.PREPARATION, WildRunFlow.Phase.WILDERNESS]:
		return null
	if not data.get("containers", null) is Dictionary or not data.get("active_run", null) is Dictionary or not data.get("receipts", null) is Dictionary:
		return null
	var state := WildBaseState.new(owner, config)
	state.skills = WildSkillCodec.decode(data.get("skills",null),config.skill_rules)
	if state.skills == null: return null
	state.currency = int(data["currency"])
	state.phase = phase_value as WildRunFlow.Phase
	state.active_run = (data["active_run"] as Dictionary).duplicate(true)
	state.receipts = (data["receipts"] as Dictionary).duplicate(true)
	if not data.get("pending",[]) is Array or not data.get("last_settlement",{}) is Dictionary: return null
	state.last_settlement = data.get("last_settlement",{}).duplicate(true)
	if not state.last_settlement.is_empty():
		var summary: Dictionary = state.last_settlement
		if not summary.get("run_id",null) is String or summary["run_id"].is_empty() or not summary.get("won",null) is bool or not summary.get("reason",null) is String: return null
		if not whole(summary.get("reward",null)) or summary["reward"] < 0 or not number(summary.get("elapsed_seconds",null)) or summary["elapsed_seconds"] < 0 or not whole(summary.get("pending_count",null)) or summary["pending_count"] < 0: return null
		if summary.has("report") and not WildExpeditionReport.valid(summary["report"],int(summary["reward"]),summary["won"]): return null
	var records: Dictionary = data["containers"]
	if records.size() != state.containers.size():
		return null
	var instance_ids: Dictionary = {}
	for id: String in state.containers:
		if not records.get(id, null) is Dictionary:
			return null
		var stored: Dictionary = records[id]
		if stored.get("id", "") != id or not whole(stored.get("version", -1)) or float(stored["version"]) < 0.0 or not stored.get("entries", null) is Array:
			return null
		var container: WildInventoryContainer = state.containers[id]
		for entry: Variant in stored["entries"]:
			if not entry is Dictionary or not entry.get("item", null) is Dictionary or not entry.get("position", null) is Array or not entry.get("rotated", null) is bool:
				return null
			var raw: Dictionary = entry["item"]
			if not WildItemInstance.metadata_valid(raw): return null
			var position: Array = entry["position"]
			if position.size() != 2 or not whole(position[0]) or not whole(position[1]) or not whole(raw.get("quantity", 0)):
				return null
			for field: String in ["durability", "freshness_hours", "water_l"]:
				if not number(raw.get(field, null)):
					return null
			if not raw.get("clean_water", null) is bool or not raw.get("free_supply", null) is bool:
				return null
			var item: WildItemInstance = WildItemInstance.from_record(raw)
			if instance_ids.has(item.instance_id):
				return null
			var cell := Vector2i(int(position[0]), int(position[1]))
			var valid: WildOperationResult = WildInventoryRules.can_place(state, catalog, config, owner, container, item, cell, entry["rotated"])
			if not valid.successful:
				return null
			instance_ids[item.instance_id] = true
			container.placements[item.instance_id] = {"item": item, "position": cell, "rotated": entry["rotated"]}
		container.version = int(stored["version"])
	for raw: Variant in data.get("pending",[]):
		if not WildSurvivalCodec.item_record_valid(raw,catalog) or instance_ids.has(raw["id"]): return null
		instance_ids[raw["id"]] = true
		state.pending.append(raw.duplicate(true))
	for receipt: Variant in state.receipts.values():
		if not receipt is Dictionary or not receipt.get("signature", null) is String or not receipt.get("successful", null) is bool or not receipt.get("code", null) is String or not receipt.get("payload", null) is Dictionary:
			return null
	if phase_value == WildRunFlow.Phase.BASE:
		if not state.active_run.is_empty():
			return null
	else:
		if str(state.active_run.get("run_id", "")).is_empty() or not state.active_run.get("origin_containers", null) is Dictionary:
			return null
		var origin: Dictionary = {"save_version": 1, "player_id": owner, "currency": state.currency, "phase": WildRunFlow.Phase.BASE, "active_run": {}, "receipts": {}, "containers": state.active_run["origin_containers"]}
		if decode(origin, owner, config, catalog) == null:
			return null
		if state.active_run.has("seed") and not WildWorldGenerator.valid_seed(state.active_run["seed"]):
			return null
		if phase_value == WildRunFlow.Phase.WILDERNESS:
			if state.active_run.has("world"):
				if not state.active_run["world"] is Dictionary or (state.active_run.get("exploration_only", false) != true and not state.active_run.has("survival")):
					return null
				state.world = WildWorldCodec.decode(state.active_run["world"], config)
				if state.world == null or not state.world.players.has(owner) or state.world.seed_text != state.active_run.get("seed", ""):
					return null
				state.active_run.erase("world")
				if state.active_run.has("survival"):
					if not state.active_run["survival"] is Dictionary: return null
					state.survival = WildSurvivalCodec.decode(state.active_run["survival"],state,config,catalog)
					if state.survival == null: return null
					state.active_run.erase("survival")
					for output: Dictionary in state.survival.outputs.values():
						for raw: Dictionary in output["items"]:
							if instance_ids.has(raw["id"]): return null
							instance_ids[raw["id"]] = true
			elif state.active_run.get("prototype_only", false) != true:
				return null
		elif state.active_run.has("world"):
			return null
	if not WildCoopProfileRules.restore(data.get("cooperation",null),state,config,catalog): return null
	return state


static func number(value: Variant) -> bool:
	return WildDataValidation.number(value)


static func whole(value: Variant) -> bool:
	return WildDataValidation.whole(value)
