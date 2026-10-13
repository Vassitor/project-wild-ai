class_name WildLocalSession
extends RefCounted
## 本地权威会话：拥有玩家与流程，处理命令、返回结果，不接触 UI 或文件。
## 后续房主会话复用此领域入口，网络适配仅映射身份和传递基础消息。

signal station_opened(station_id: StringName)
signal station_closed
signal pause_changed(paused: bool)
signal base_state_changed
signal world_content_changed
signal command_resolved(request_id: String, result: WildOperationResult)

## 异步适配器通过统一结果信号通知 UI；本地同步提交不需要额外通知。
func resolve_command(request_id: String, result: WildOperationResult) -> void:
	command_resolved.emit(request_id,result)

var session_id: String = WildStableId.create("session")
var flow := WildRunFlow.new()
var _players: Dictionary[String, WildPlayerState] = {}
var _base_services: Dictionary[String, WildBaseService] = {}
var _mode: WildSessionPolicy.Mode
var _active_station: StringName = &""
var _focus_lost: bool = false
var _request_results: Dictionary[String, WildOperationResult] = {}
var _request_signatures: Dictionary[String, String] = {}


func _init(mode: WildSessionPolicy.Mode = WildSessionPolicy.Mode.SINGLE_PLAYER) -> void:
	_mode = mode


## 不接收重复身份，避免未来重连时生成第二份状态。
func register_player(player: WildPlayerState) -> WildOperationResult:
	if player.player_id.is_empty() or _players.has(player.player_id):
		return WildOperationResult.reject(&"DUPLICATE_PLAYER")
	_players[player.player_id] = player
	return WildOperationResult.accept()


func player_snapshot(id: String) -> Dictionary:
	if _base_services.has(id):
		var body: Dictionary = _base_services[id].body_snapshot(id)
		if not body.is_empty(): return body
	return _players[id].snapshot() if _players.has(id) else {}


func register_base_service(actor: String, service: WildBaseService) -> void:
	_base_services[actor] = service
	flow.current_phase = service.current_phase()
	service.changed.connect(_on_base_changed.bind(actor))
	service.world_content_changed.connect(_on_world_content_changed)


func base_snapshot(actor: String) -> Dictionary:
	return _base_services[actor].snapshot() if _base_services.has(actor) else {}


func preview_transfer(actor: String, payload: Dictionary) -> WildOperationResult:
	return _base_services[actor].preview_transfer(actor, payload) if _base_services.has(actor) else WildOperationResult.reject(&"UNKNOWN_ACTOR")


func _on_base_changed(actor: String) -> void:
	flow.current_phase = _base_services[actor].current_phase()
	base_state_changed.emit()


func _on_world_content_changed() -> void:
	world_content_changed.emit()


## 持久化命令交给事务服务；查看资源不产生收据或文件写入。
func submit(command: WildGameCommand) -> WildOperationResult:
	if not _players.has(command.actor_id):
		return WildOperationResult.reject(&"UNKNOWN_ACTOR")
	if command.request_id.is_empty():
		return WildOperationResult.reject(&"INVALID_REQUEST")
	if command.operation == &"world.inspect" and _base_services.has(command.actor_id):
		return _base_services[command.actor_id].inspect_resource(command.actor_id, command.payload)
	# 有持久化副作用的操作由事务服务去重；保存失败不能被内存缓存永久拒绝重试。
	if _base_services.has(command.actor_id) and not str(command.operation).begins_with("base."):
		return _base_services[command.actor_id].submit(command)
	var signature: String = "%s|%s|%s" % [command.actor_id, command.operation, JSON.stringify(command.payload, "", true)]
	if _request_results.has(command.request_id):
		if _request_signatures[command.request_id] != signature:
			return WildOperationResult.reject(&"REQUEST_ID_CONFLICT")
		return _request_results[command.request_id].copy()
	var result: WildOperationResult = _execute(command)
	_request_signatures[command.request_id] = signature
	_request_results[command.request_id] = result.copy()
	return result


func world_snapshot(actor: String) -> Dictionary:
	return _base_services[actor].world_record() if _base_services.has(actor) else {}


func world_position(actor: String) -> Vector2:
	return _base_services[actor].player_position(actor) if _base_services.has(actor) else Vector2.ZERO

func world_player_positions() -> Dictionary:
	var positions: Dictionary = {}
	for actor: String in _players: positions[actor] = world_position(actor)
	return positions

func is_cooperative() -> bool:
	return _mode == WildSessionPolicy.Mode.COOPERATIVE


func move_world_player(actor: String, direction: Vector2, seconds: float, sprint: bool) -> Vector2:
	if is_paused() or not _base_services.has(actor):
		return world_position(actor)
	return _base_services[actor].move_player(actor, direction, seconds, sprint)


func checkpoint(actor: String) -> WildOperationResult:
	return _base_services[actor].checkpoint() if _base_services.has(actor) else WildOperationResult.reject(&"UNKNOWN_ACTOR")


func survival_snapshot(actor: String) -> Dictionary:
	return _base_services[actor].survival_snapshot(actor) if _base_services.has(actor) else {}


func world_dynamic(actor: String) -> Dictionary:
	return _base_services[actor].world_dynamic() if _base_services.has(actor) else {}


func advance_world(actor: String, seconds: float, activity: String) -> WildOperationResult:
	if is_paused(): return WildOperationResult.accept()
	return _base_services[actor].advance_world(actor,seconds,activity) if _base_services.has(actor) else WildOperationResult.reject(&"UNKNOWN_ACTOR")


func active_station() -> StringName:
	return _active_station


func is_paused() -> bool:
	return WildSessionPolicy.pauses_world(_mode, not _active_station.is_empty(), _focus_lost)


func set_focus_lost(lost: bool) -> void:
	_focus_lost = lost
	pause_changed.emit(is_paused())


func _execute(command: WildGameCommand) -> WildOperationResult:
	if flow.current_phase not in [WildRunFlow.Phase.BASE, WildRunFlow.Phase.PREPARATION, WildRunFlow.Phase.WILDERNESS]:
		return WildOperationResult.reject(&"NOT_IN_BASE")
	match command.operation:
		&"base.open_pause":
			_active_station = &"pause"
			station_opened.emit(_active_station)
			pause_changed.emit(is_paused())
			return WildOperationResult.accept()
		&"base.open_station":
			var station_id := StringName(str(command.payload.get("station_id", "")))
			if not WildBaseLayout.STATIONS.has(station_id):
				return WildOperationResult.reject(&"UNKNOWN_STATION")
			_active_station = station_id
			station_opened.emit(station_id)
			pause_changed.emit(is_paused())
			return WildOperationResult.accept({"station_id": str(station_id)})
		&"base.close_station":
			_active_station = &""
			station_closed.emit()
			pause_changed.emit(is_paused())
			return WildOperationResult.accept()
		_:
			return WildOperationResult.reject(&"UNKNOWN_COMMAND")
