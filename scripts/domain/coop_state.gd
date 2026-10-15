class_name WildCoopState
extends RefCounted
## 房间事务单元：共享世界只存一份，私人容器按稳定玩家 ID 分开。
## lifecycle 为空保留独立双人验证；完整合作通过持久收据与个人档案交付，世界不写基地文件。

var room_id: String = WildStableId.create("room")
var run_id: String = WildStableId.create("run")
var host_id: String = ""
var started: bool = false
var revision: int = 0
var members: Dictionary[String, WildBaseState] = {}
var names: Dictionary = {}
var token_hashes: Dictionary = {}
var boxes: Dictionary[String, WildInventoryContainer] = {}
var world: WildWorldData
var survival: WildSurvivalState
var receipts: Dictionary = {}
var lifecycle: Dictionary = {} # 空字典保留 P3.5–P6 独立双人验证语义。
var corpses: Dictionary[String, WildInventoryContainer] = {}

func bind_shared() -> void:
	for personal: WildBaseState in members.values():
		personal.world = world
		personal.survival = survival
		personal.phase = WildRunFlow.Phase.WILDERNESS
		personal.active_run = {"run_id":run_id,"seed":world.seed_text}

## 动作规则只看到执行者自己的库存；公共箱仅在显式转移时加入视图。
func view(actor: String, config: WildGameConfig, include_boxes: bool = false) -> WildBaseState:
	var personal: WildBaseState = members[actor]
	if not include_boxes: return personal
	var result := WildBaseState.new(actor,config)
	result.world = world
	result.survival = survival
	result.containers = personal.containers.duplicate()
	for id: String in boxes: result.containers[id] = boxes[id]
	for id: String in corpses: result.containers[id] = corpses[id]
	return result

func record() -> Dictionary:
	var raw: Dictionary = _record()
	raw["lifecycle"] = lifecycle.duplicate(true)
	raw["corpses"] = {}
	for id: String in corpses: raw["corpses"][id] = corpses[id].record()
	return raw

func _record() -> Dictionary:
	var players: Dictionary = {}
	for actor: String in members:
		var inventory: Dictionary = {}
		for id: String in members[actor].containers: inventory[id] = members[actor].containers[id].record()
		players[actor] = {"save_version":1,"player_id":actor,"currency":members[actor].currency,"phase":WildRunFlow.Phase.BASE,"active_run":{},"containers":inventory,"receipts":{}}
		players[actor]["skills"] = members[actor].skills.record()
	var containers: Dictionary = {}
	for id: String in boxes: containers[id] = boxes[id].record()
	return {"coop_save_version":1,"room_id":room_id,"run_id":run_id,"host_id":host_id,"started":started,"revision":revision,"members":players,"names":names.duplicate(true),"token_hashes":token_hashes.duplicate(true),"boxes":containers,"world":world.record(),"survival":survival.record(),"receipts":receipts.duplicate(true)}

func copy(config: WildGameConfig) -> WildCoopState:
	var result := WildCoopState.new()
	result.room_id = room_id
	result.run_id = run_id
	result.host_id = host_id
	result.started = started
	result.revision = revision
	result.names = names.duplicate(true)
	result.token_hashes = token_hashes.duplicate(true)
	result.receipts = receipts.duplicate(true)
	result.lifecycle = lifecycle.duplicate(true)
	result.world = world.copy()
	result.survival = survival.copy()
	for actor: String in members:
		# 不重复深拷贝每人的 128×128 共享地图。
		var personal := WildBaseState.new(actor,config)
		personal.currency = members[actor].currency
		personal.skills = members[actor].skills.copy()
		for id: String in members[actor].containers: personal.containers[id] = members[actor].containers[id].copy()
		result.members[actor] = personal
	for id: String in boxes: result.boxes[id] = boxes[id].copy()
	for id: String in corpses: result.corpses[id] = corpses[id].copy()
	result.bind_shared()
	return result
