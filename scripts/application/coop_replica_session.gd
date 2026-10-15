class_name WildCoopReplicaSession
extends WildLocalSession
## 展示层的只读会话适配，复用原世界 / 人物 / 交互显示。业务命令异步交给网络。

var network: WildENetRoom
var actor_id: String
var _config: WildGameConfig
var _catalog: WildItemCatalog
var _positions: Dictionary[String, Vector2] = {}
var _targets: Dictionary[String, Vector2] = {}
var _prediction_world: WildWorldData
var _prediction_key: String = ""
var _prediction_steps: Array[Dictionary] = []
var materials_box: String = ""

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
	if network.full_cooperation and data.get("players",{}).has(actor_id):
		var key: String = data.get("cooperation",{}).get("world_hash","")+str(data.get("run_id",""))
		if _prediction_key != key and not data.get("world",{}).is_empty():
			_prediction_world = WildWorldCodec.decode(data["world"],_config)
			_prediction_key = key
		if _prediction_world != null:
			_prediction_world.blocked_cells = world_dynamic(actor_id).get("blocked_cells",{}).duplicate()
			_prediction_world.players[actor_id] = _targets[actor_id]
			var ack: int = int(data.get("input_ack",-1))
			_prediction_steps = _prediction_steps.filter(func(step: Dictionary) -> bool: return int(step["sequence"]) > ack)
			for step: Dictionary in _prediction_steps: _predict(step)
			_positions[actor_id] = _prediction_world.players[actor_id]
	world_content_changed.emit()
	base_state_changed.emit()

func interpolate(seconds: float) -> void:
	for id: String in _targets:
		if id == actor_id and network.full_cooperation: continue
		var distance: float = _positions[id].distance_to(_targets[id])
		_positions[id] = _targets[id] if distance > 96 else _positions[id].lerp(_targets[id],1-exp(-15*seconds))

func reset_view() -> void:
	_positions.clear()
	_targets.clear()
	_prediction_steps.clear()
	_prediction_world = null
	_prediction_key = ""
	materials_box = ""

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

func move_world_player(actor: String, direction: Vector2, seconds: float, sprint: bool) -> Vector2:
	if actor == actor_id:
		var allowed: bool = active_station().is_empty()
		if network.full_cooperation: allowed = allowed and network.latest.get("cooperation",{}).get("phase","") == "running" and network.latest.get("action",{}).is_empty() and player_snapshot(actor).get("health_points",0) > 0
		var intended: Vector2 = direction if allowed else Vector2.ZERO
		network.set_input(intended,sprint)
		if network.full_cooperation and _prediction_world != null:
			var step: Dictionary = {"direction":intended,"seconds":minf(seconds,0.1),"sprint":sprint,"sequence":network._sequence+1}
			_prediction_steps.append(step)
			while _prediction_steps.size() > 60: _prediction_steps.pop_front()
			_predict(step)
			_positions[actor_id] = _prediction_world.players[actor_id]
	return world_position(actor)

func _predict(step: Dictionary) -> void:
	var speeds: Dictionary = network.latest.get("movement_speed",{})
	var kind: String = "exhausted" if player_snapshot(actor_id).get("stamina",0) <= 0 else ("sprint" if step["sprint"] else "walk")
	WildWorldRules.move(_prediction_world,actor_id,step["direction"],step["seconds"],float(speeds.get(kind,_config.walking_speed_pixels_per_second)))

func world_dynamic(_actor_id: String) -> Dictionary:
	var raw: Dictionary = network.latest
	if not raw.has("resources"): return {}
	var blocked: Dictionary = {}
	for building: Dictionary in raw["buildings"].values():
		var bounds: Rect2i = WildBuildingRules.occupied(building)
		for y: int in range(bounds.position.y,bounds.end.y):
			for x: int in range(bounds.position.x,bounds.end.x): blocked[Vector2i(x,y)] = true
	return {"resources":raw["resources"],"buildings":raw["buildings"],"outputs":raw["outputs"],"blocked_cells":blocked,"prey":raw.get("prey",{}),"projectiles":raw.get("projectiles",{}),"tracks":raw.get("tracks",[]),"feedback":raw.get("feedback",{}),"combat_time":raw.get("combat_time",0),"corpses":raw.get("cooperation",{}).get("dead",{})}

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
	var payload: Dictionary = command.payload.duplicate(true)
	if network.full_cooperation and command.operation == &"survival.start" and payload.get("action","") in WildCoopMaterials.ACTIONS and not materials_box.is_empty(): payload["materials_box"] = materials_box
	var id: String = network.request(str(command.operation),payload,command.request_id)
	return WildOperationResult.new(false,&"PENDING",{"request_id":id}) if not id.is_empty() else WildOperationResult.reject(&"NOT_CONNECTED")
