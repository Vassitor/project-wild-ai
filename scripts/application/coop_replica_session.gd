class_name WildCoopReplicaSession
extends WildLocalSession
## 展示层的只读会话适配，复用原世界 / 人物 / 交互显示。业务命令异步交给网络。

var network: WildENetRoom
var actor_id: String
var _config: WildGameConfig
var _catalog: WildItemCatalog
var _positions: Dictionary[String, Vector2] = {}
var _targets: Dictionary[String, Vector2] = {}

func configure(room_network: WildENetRoom, actor: String, config: WildGameConfig, catalog: WildItemCatalog) -> void:
	network = room_network
	actor_id = actor
	_config = config
	_catalog = catalog
	_mode = WildSessionPolicy.Mode.COOPERATIVE
	if not network.snapshot_received.is_connected(_on_snapshot):
		network.snapshot_received.connect(_on_snapshot)
		network.command_completed.connect(_on_command_completed)

func _on_command_completed(request: String, result: WildOperationResult) -> void:
	resolve_command(request,result)

func _on_snapshot(data: Dictionary) -> void:
	for id: String in data.get("players",{}):
		var raw: Array = data["players"][id]["position"]
		_targets[id] = Vector2(raw[0],raw[1])
		if not _positions.has(id): _positions[id] = _targets[id]
	world_content_changed.emit()
	base_state_changed.emit()

func interpolate(seconds: float) -> void:
	for id: String in _targets:
		var distance: float = _positions[id].distance_to(_targets[id])
		_positions[id] = _targets[id] if distance > 96 else _positions[id].lerp(_targets[id],1-exp(-15*seconds))

func reset_view() -> void:
	_positions.clear()
	_targets.clear()

func world_snapshot(_actor_id: String) -> Dictionary:
	return network.latest.get("world",{}).duplicate(true)

func world_position(actor: String) -> Vector2:
	return _positions.get(actor,Vector2.ZERO)

func world_player_positions() -> Dictionary:
	return _positions.duplicate()

## 本地预览复用网格规则，仅供拖放反馈；提交时仍由房主检查版本 / 距离。
func preview_transfer(actor: String, payload: Dictionary) -> WildOperationResult:
	if actor != actor_id: return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	var personal := WildBaseState.new(actor,_config)
	personal.containers.clear()
	for id: String in network.latest.get("containers",{}):
		var view: Dictionary = network.latest["containers"][id]
		var box := WildInventoryContainer.new(id,view["owner_id"],Vector2i(view["grid"][0],view["grid"][1]),view["capacity_l"])
		box.version = int(view["version"])
		box.public_access = view["public_access"]
		box.carried = not box.public_access
		box.equipment_slot = id in ["main_hand","off_hand","armor"]
		box.accepted_categories = PackedStringArray({"main_hand":["tool","weapon"],"off_hand":["tool","container"],"armor":["armor"]}.get(id,[]))
		for entry: Dictionary in view["entries"]:
			var item: WildItemInstance = WildItemInstance.from_record(entry["item"])
			box.placements[item.instance_id] = {"item":item,"position":Vector2i(entry["position"][0],entry["position"][1]),"rotated":entry["rotated"]}
		personal.containers[id] = box
	return WildInventoryRules.transfer(personal,_catalog,_config,actor,payload)

func move_world_player(actor: String, direction: Vector2, _seconds: float, sprint: bool) -> Vector2:
	if actor == actor_id:
		network.set_input(direction if active_station().is_empty() else Vector2.ZERO,sprint)
	return world_position(actor)

func world_dynamic(_actor_id: String) -> Dictionary:
	var raw: Dictionary = network.latest
	if not raw.has("resources"): return {}
	var blocked: Dictionary = {}
	for building: Dictionary in raw["buildings"].values():
		var bounds: Rect2i = WildBuildingRules.occupied(building)
		for y: int in range(bounds.position.y,bounds.end.y):
			for x: int in range(bounds.position.x,bounds.end.x): blocked[Vector2i(x,y)] = true
	return {"resources":raw["resources"],"buildings":raw["buildings"],"outputs":raw["outputs"],"blocked_cells":blocked,"prey":raw.get("prey",{})}

func player_snapshot(actor: String) -> Dictionary:
	return network.latest.get("players",{}).get(actor,{}).get("body",{}).duplicate(true)

func base_snapshot(_actor_id: String) -> Dictionary:
	return network.latest.duplicate(true)

func survival_snapshot(actor: String) -> Dictionary:
	if network.latest.is_empty(): return {}
	var result: Dictionary = network.latest.duplicate(true)
	result["body"] = player_snapshot(actor)
	return result

func is_paused() -> bool:
	return false

func submit(command: WildGameCommand) -> WildOperationResult:
	if command.actor_id != actor_id: return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	if command.operation == &"base.open_pause":
		_active_station = &"pause"
		station_opened.emit(_active_station)
		return WildOperationResult.accept()
	if command.operation == &"base.close_station":
		_active_station = &""
		station_closed.emit()
		return WildOperationResult.accept()
	var id: String = network.request(str(command.operation),command.payload,command.request_id)
	return WildOperationResult.new(false,&"PENDING",{"request_id":id}) if not id.is_empty() else WildOperationResult.reject(&"NOT_CONNECTED")
