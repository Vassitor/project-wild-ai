class_name WildBaseState
extends RefCounted
## 基地与单局物资的同一保存单元，含可重放收据和准备前回滚快照。

var player_id: String
var currency: int
var phase: WildRunFlow.Phase = WildRunFlow.Phase.BASE
var active_run: Dictionary = {}
var containers: Dictionary[String, WildInventoryContainer] = {}
var receipts: Dictionary = {}
var world: WildWorldData
var survival: WildSurvivalState
var pending: Array[Dictionary] = []
var last_settlement: Dictionary = {}
var skills: WildSkillProfile = WildSkillProfile.new()


func _init(owner: String, config: WildGameConfig) -> void:
	player_id = owner
	currency = config.starting_currency
	containers["warehouse"] = WildInventoryContainer.new("warehouse", owner, config.warehouse_grid, config.warehouse_capacity_l)
	containers["backpack"] = WildInventoryContainer.new("backpack", owner, config.backpack_grid, config.backpack_capacity_l)
	containers["backpack"].carried = true
	for slot: String in ["main_hand", "off_hand", "armor"]:
		var container := WildInventoryContainer.new(slot, owner, Vector2i.ONE, 0.0)
		container.carried = true
		container.equipment_slot = true
		containers[slot] = container
	containers["main_hand"].accepted_categories = PackedStringArray(["tool", "weapon"])
	containers["off_hand"].accepted_categories = PackedStringArray(["tool", "container"])
	containers["armor"].accepted_categories = PackedStringArray(["armor"])


func carried_weight(catalog: WildItemCatalog, config: WildGameConfig, actor: String = "") -> float:
	var owner: String = player_id if actor.is_empty() else actor
	var total: float = config.backpack_empty_weight_kg
	for container: WildInventoryContainer in containers.values():
		if container.carried and container.owner_id == owner:
			total += container.weight(catalog)
	return total


func record() -> Dictionary:
	var inventory: Dictionary = {}
	for id: String in containers:
		inventory[id] = containers[id].record()
	var run: Dictionary = active_run.duplicate(true)
	if world != null:
		run["world"] = world.record()
	if survival != null: run["survival"] = survival.record()
	return {"save_version": 1, "player_id": player_id, "currency": currency, "phase": phase, "active_run": run, "containers": inventory, "receipts": receipts.duplicate(true),"pending":pending.duplicate(true),"last_settlement":last_settlement.duplicate(true),"skills":skills.record()}


func copy(config: WildGameConfig) -> WildBaseState:
	var duplicate := WildBaseState.new(player_id, config)
	duplicate.currency = currency
	duplicate.skills = skills.copy()
	duplicate.phase = phase
	duplicate.active_run = active_run.duplicate(true)
	duplicate.receipts = receipts.duplicate(true)
	duplicate.world = world.copy() if world != null else null
	duplicate.survival = survival.copy() if survival != null else null
	duplicate.pending.assign(pending.duplicate(true))
	duplicate.last_settlement = last_settlement.duplicate(true)
	duplicate.containers.clear()
	for id: String in containers:
		duplicate.containers[id] = containers[id].copy()
	return duplicate
