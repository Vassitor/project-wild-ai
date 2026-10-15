class_name WildENetRoom
extends Node
## ENet 网络适配：可靠 RPC 传命令 / 收据，独立不可靠通道传输入 / 位置。
## 相同节点路径 / RPC 脚本用于房主与客户端；权限绑定在握手后，永不信任 actor 字段。
## 测试故障注入位于应用报文层：每向 50 ms 延迟、每 100 包丢 1 包；非 OS UDP 整形。

signal snapshot_received(data: Dictionary)
signal command_completed(request_id: String, result: WildOperationResult)
signal connection_status(text: String)
signal room_ended
signal deliveries_received(events: Array)
## 本机观测点，用于故障验证 / 遥测；不通过网络暴露业务状态写入。
signal command_handled(peer: int, request_id: String, result: WildOperationResult)

const PROTOCOL: int = 3
const MAXIMUM_SNAPSHOT_BYTES: int = 8*1024*1024
var authority: WildCoopService
var full_cooperation: bool = false
var content_fingerprint: String = ""
var welcoming_room_id: String = ""
var actor_id: String = ""
var nickname: String = ""
var token: String = ""
var latest: Dictionary = {}
var fault_delay_ms: int = 0
var bind_address: String = "*"
var fault_drop_every: int = 0
var sent_packets: int = 0
var dropped_packets: int = 0
var force_next_drop: bool = false
var forced_dropped_packets: int = 0
var received_packets: int = 0
var retransmissions: int = 0
var _peer_actors: Dictionary = {}
var _peer_tokens: Dictionary = {}
var _inputs: Dictionary = {}
var _input_sequences: Dictionary = {}
var _outbox: Array[Dictionary] = []
var _pending: Dictionary = {}
var _direction: Vector2 = Vector2.ZERO
var _sprint: bool = false
var _sequence: int = 0
var _input_elapsed: float = 0
var _snapshot_elapsed: float = 0
var _full_elapsed: float = 0
var _hello_elapsed: float = 0
var _active: bool = false
var _welcomed: bool = false
var _ending: bool = false
var _remote_ready: Dictionary = {}
var _welcome_sent_at: Dictionary = {}
var _credentials_save: Callable
var credentials_lookup: Callable
var _recent_results: Dictionary = {}
var _terminal_received: bool = false
var _terminal_sent_at: int = 0
var _state_revision: int = -1

func configure_identity(actor: String, display_name: String, reconnect_token: String, save_credentials: Callable = Callable()) -> void:
	actor_id = actor
	nickname = display_name
	token = reconnect_token
	_credentials_save = save_credentials

func host(service: WildCoopService, port: int) -> Error:
	if full_cooperation != service.uses_personal_profiles(): return ERR_INVALID_PARAMETER
	authority = service
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_address)
	# 留一个握手槽以返回业务拒绝原因；人数上限仍由房主领域服务执行。
	var error: Error = peer.create_server(port,service.maximum_members(),3)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	_peer_actors[1] = actor_id
	authority.online[actor_id] = true
	_connect_signals()
	_active = true
	_welcomed = true
	_emit_local(true)
	connection_status.emit("房间已创建，等待队员")
	return OK

func join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address,port,3)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	_connect_signals()
	_active = true
	_welcomed = false
	connection_status.emit("正在连接房主…")
	return OK

func _connect_signals() -> void:
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	# 仅基础 Variant；拒绝 RPC 对象反序列化。预留其他传输实现，不耦合领域规则。
	if multiplayer is SceneMultiplayer:
		(multiplayer as SceneMultiplayer).allow_object_decoding = false
		(multiplayer as SceneMultiplayer).server_relay = false

func _on_connected() -> void:
	_send_hello()

func _send_hello() -> void:
	_queue("hello",1,{"protocol":PROTOCOL,"actor":actor_id,"name":nickname,"token":token,"full_cooperation":full_cooperation,"content_fingerprint":content_fingerprint})

func _on_connection_failed() -> void:
	_active = false
	connection_status.emit("连接失败，请检查 IP、端口与房主")

func _on_server_disconnected() -> void:
	_active = false
	_welcomed = false
	_ending = false
	_pending.clear()
	connection_status.emit("房主已断开；可使用原身份重连")
	room_ended.emit()

func _on_peer_disconnected(peer: int) -> void:
	if authority == null or not _peer_actors.has(peer): return
	var actor: String = _peer_actors[peer]
	_peer_actors.erase(peer)
	_peer_tokens.erase(peer)
	_inputs.erase(peer)
	_input_sequences.erase(peer)
	_remote_ready.erase(peer)
	_welcome_sent_at.erase(peer)
	var result: WildOperationResult = authority.member_disconnected(actor)
	connection_status.emit("%s 断线，角色留在原地%s" % [authority.state.names[actor],"；保存失败，正在重试" if not result.successful else ""])
	_broadcast(true)

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(data: Dictionary) -> void:
	if authority == null or _ending: return
	var peer: int = multiplayer.get_remote_sender_id()
	received_packets += 1
	if JSON.stringify(data).length() > 1024 or data.get("protocol",0) != PROTOCOL or not data.get("actor",null) is String or not data.get("name",null) is String or not data.get("token",null) is String:
		_queue("deliver",peer,{"type":"error","code":"PROTOCOL_MISMATCH"})
		return
	var actor: String = data["actor"]
	if data.get("full_cooperation",false) != full_cooperation or (full_cooperation and (content_fingerprint.length() != 64 or data.get("content_fingerprint","") != content_fingerprint)):
		_queue("deliver",peer,{"type":"error","code":"CONTENT_MISMATCH"})
		return
	if full_cooperation and authority.state.members.has(actor) and data["token"].sha256_text() != authority.state.token_hashes[actor]:
		_queue("deliver",peer,{"type":"challenge","room_id":authority.state.room_id})
		return
	if _peer_actors.has(peer):
		if _peer_actors[peer] == actor and Time.get_ticks_msec()-int(_welcome_sent_at.get(peer,0)) >= 3000: _welcome(peer)
		return
	var result: WildOperationResult = authority.join(actor,data["name"],data["token"])
	if not result.successful:
		_queue("deliver",peer,{"type":"error","code":str(result.code)})
		return
	_peer_actors[peer] = actor
	_peer_tokens[peer] = result.payload["token"]
	_welcome(peer)
	_broadcast(true)

func _welcome(peer: int) -> void:
	_welcome_sent_at[peer] = Time.get_ticks_msec()
	var data: Dictionary = authority.snapshot(_peer_actors[peer],true)
	data["type"] = "welcome"
	data["token"] = _peer_tokens[peer]
	_queue("deliver",peer,data)

@rpc("any_peer", "call_remote", "reliable", 0)
func _command(data: Dictionary) -> void:
	if authority == null: return
	var peer: int = multiplayer.get_remote_sender_id()
	_handle_command(peer,data)

func _handle_command(peer: int, data: Dictionary) -> void:
	var maximum: int = 131072 if full_cooperation and data.get("operation","") == "profile.offer" else 8192
	if not _peer_actors.has(peer) or JSON.stringify(data).length() > maximum: return
	received_packets += 1
	var actor: String = _peer_actors[peer]
	var already_committed: bool = authority.state.receipts.has(actor+":"+str(data.get("request_id","")))
	var result: WildOperationResult = WildOperationResult.reject(&"ROOM_ENDING") if _ending and not already_committed else authority.submit(actor,data)
	var packet: Dictionary = {"type":"result","request_id":str(data.get("request_id","")),"successful":result.successful,"code":str(result.code),"payload":result.payload}
	var recent: Dictionary = _recent_results.get(actor,{})
	recent[packet["request_id"]] = packet.duplicate(true)
	while recent.size() > 32: recent.erase(recent.keys()[0])
	_recent_results[actor] = recent
	command_handled.emit(peer,packet["request_id"],result)
	if peer == 1: _accept_packet(packet)
	else: _queue("control",peer,packet)
	# 已提交请求只补回收据；重试不能放大为 N 份完整世界广播，挤压可靠结果通道。
	if not _ending and not already_committed: _broadcast(true)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_input(data: Dictionary) -> void:
	if authority == null or _ending: return
	_handle_input(multiplayer.get_remote_sender_id(),data)

func _handle_input(peer: int, data: Dictionary) -> void:
	if not _peer_actors.has(peer) or not WildDataValidation.whole(data.get("sequence",null)) or int(data["sequence"]) <= int(_input_sequences.get(peer,-1)) or not data.get("sprint",null) is bool or not data.get("direction",null) is Array or data["direction"].size() != 2: return
	var raw: Array = data["direction"]
	if not WildDataValidation.number(raw[0]) or not WildDataValidation.number(raw[1]): return
	var direction := Vector2(raw[0],raw[1])
	_input_sequences[peer] = int(data["sequence"])
	_inputs[peer] = {"direction":direction.limit_length(1),"sprint":data["sprint"],"received_at":Time.get_ticks_msec()}

@rpc("authority", "call_remote", "reliable", 0)
func _deliver(data: Dictionary) -> void:
	_accept_packet(data)

## 可靠状态有大量重复字段；压缩后传输，避免分片积压占满四人房间的窗口。
## 解压设硬上限，禁止对象反序列化；命令 / 结果仍为原始基础 Variant。
@rpc("authority", "call_remote", "reliable", 0)
func _snapshot_blob(compressed: PackedByteArray) -> void:
	if compressed.size() > MAXIMUM_SNAPSHOT_BYTES: return
	var decoded: PackedByteArray = compressed.decompress_dynamic(MAXIMUM_SNAPSHOT_BYTES,FileAccess.COMPRESSION_DEFLATE)
	if decoded.is_empty(): return
	var raw: Variant = bytes_to_var(decoded)
	if raw is Dictionary: _accept_packet(raw)

## 结果 / 结束走独立可靠通道，大地图的分片不能阻塞最后一条确认。
@rpc("authority", "call_remote", "reliable", 2)
func _control(data: Dictionary) -> void:
	_accept_packet(data)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _frame(data: Dictionary) -> void:
	_accept_packet(data)

func _accept_packet(data: Dictionary) -> void:
	received_packets += 1
	match data.get("type",""):
		"challenge":
			if credentials_lookup.is_valid():
				var previous: String = str(credentials_lookup.call(str(data.get("room_id",""))))
				if not previous.is_empty() and previous != token:
					token = previous
					_send_hello()
				else: connection_status.emit("原成员身份凭据不匹配。")
		"error":
			connection_status.emit("连接被拒绝："+str(data["code"]))
		"ended":
			if _terminal_received: return
			_terminal_received = true
			deliveries_received.emit(data.get("deliveries",[]))
			_ending = true
			# 结束前的最后确认可能被应用报文故障丢掉；补发已处理结果后再通知 UI。
			var receipts: Dictionary = data.get("receipts",{})
			for pending_id: String in _pending.keys():
				if receipts.has(pending_id): _accept_packet(receipts[pending_id])
				else:
					_pending.erase(pending_id)
					command_completed.emit(pending_id,WildOperationResult.new(false,&"ROOM_ENDED_PENDING",{"unknown_outcome":true}))
			connection_status.emit("房主已保存并结束房间")
			room_ended.emit()
		"result":
			var request_id: String = data["request_id"]
			_pending.erase(request_id)
			command_completed.emit(request_id,WildOperationResult.new(data["successful"],StringName(data["code"]),data["payload"]))
		"welcome","state","frame":
			if data["type"] == "welcome":
				token = data["token"]
				welcoming_room_id = data["room_id"]
				if _credentials_save.is_valid() and not bool(_credentials_save.call(token)):
					connection_status.emit("无法保存重连凭据，连接已关闭")
					close_connection()
					return
				_welcomed = true
				connection_status.emit("已进入共享荒野")
				_queue("ready",1,{})
			# 世界版本与位置帧序号分别检查，防止跨通道旧快照覆盖新位置。
			if data["type"] == "frame":
				if not latest.is_empty() and data.get("revision",0) < latest.get("revision",0): return
			elif int(data.get("revision",0)) < _state_revision: return
			var old_world: Dictionary = latest.get("world",{})
			if data["type"] == "frame" and data.has("compact_players"):
				data["players"] = {}
				for actor: String in data["compact_players"]:
					var values: Array = data["compact_players"][actor]
					data["players"][actor] = {"position":[values[0],values[1]],"body":{"health_points":values[2],"health":values[3],"hydration":values[4],"stamina":values[5]}}
			if data["type"] == "frame":
				if int(data.get("frame_sequence",0)) <= int(latest.get("frame_sequence",-1)): return
				# 高频帧只带位置与四项即时数值；可靠状态保存完整疾病 / 恢复详情。
				for actor: String in data["players"]:
					if not latest.get("players",{}).has(actor): continue
					var player: Dictionary = latest["players"][actor]
					player["position"] = data["players"][actor]["position"].duplicate()
					player["body"].merge(data["players"][actor]["body"],true)
				for key: String in ["revision","frame_sequence","elapsed_seconds","pending_seconds"]: latest[key] = data[key]
				latest["input_ack"] = data.get("input_ack",-1)
			else:
				_state_revision = int(data.get("revision",0))
				var old_revision: int = int(latest.get("revision",0))
				var old_frame: int = latest.get("frame_sequence",-1)
				var old_players: Dictionary = latest.get("players",{})
				latest = data.duplicate(true)
				latest["revision"] = maxi(old_revision,_state_revision)
				if not latest.has("world"): latest["world"] = old_world
				if int(data.get("frame_sequence",0)) < old_frame:
					for actor: String in latest["players"]:
						if old_players.has(actor):
							latest["players"][actor]["position"] = old_players[actor]["position"]
							for field: String in ["health_points","health","hydration","stamina"]: latest["players"][actor]["body"][field] = old_players[actor]["body"][field]
					latest["frame_sequence"] = old_frame
			snapshot_received.emit(latest.duplicate(true))

@rpc("any_peer", "call_remote", "reliable", 0)
func _ready_for_world(_data: Dictionary) -> void:
	if authority != null: _remote_ready[multiplayer.get_remote_sender_id()] = true

## 异步意图，重发保留相同请求 ID。UI 的“已提交”不能冒充“已执行”。
func request(operation: String, payload: Dictionary, request_id: String = "") -> String:
	if not _active or not _welcomed or latest.is_empty() or _ending: return ""
	var id: String = request_id if not request_id.is_empty() else WildStableId.create("request")
	var data: Dictionary = {"room_id":latest["room_id"],"run_id":latest["run_id"],"request_id":id,"operation":operation,"payload":payload.duplicate(true)}
	_pending[id] = {"data":data,"sent_at":Time.get_ticks_msec(),"attempts":1}
	if authority != null: _handle_command.call_deferred(1,data)
	else: _queue("command",1,data)
	return id

func set_input(direction: Vector2, sprint: bool) -> void:
	_direction = direction
	_sprint = sprint

func _physics_process(delta: float) -> void:
	if not _active or _ending: return
	_input_elapsed += delta
	if _input_elapsed >= 0.05 and _welcomed:
		_input_elapsed = 0
		_sequence += 1
		var data: Dictionary = {"sequence":_sequence,"direction":[_direction.x,_direction.y],"sprint":_sprint}
		if authority != null: _handle_input(1,data)
		else: _queue("input",1,data)
	if authority != null:
		for peer: int in _peer_actors:
			var input: Dictionary = _inputs.get(peer,{})
			var alive_input: bool = not input.is_empty() and Time.get_ticks_msec()-int(input["received_at"]) <= 250
			authority.move(_peer_actors[peer],input["direction"] if alive_input else Vector2.ZERO,minf(delta,0.1),alive_input and input["sprint"])
		authority.advance(delta)
		_snapshot_elapsed += delta
		_full_elapsed += delta
		if _snapshot_elapsed >= 0.1:
			_snapshot_elapsed = 0
			_broadcast(false)
		if _full_elapsed >= 1:
			_full_elapsed = 0
			_broadcast(true)

func _process(delta: float) -> void:
	if not _active: return
	var now: int = Time.get_ticks_msec()
	if authority != null and _ending and now-_terminal_sent_at >= 100:
		_send_terminal_receipts()
	if authority == null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not _welcomed:
		_hello_elapsed += delta
		if _hello_elapsed >= 1:
			_hello_elapsed = 0
			_send_hello()
	elif authority == null and _welcomed:
		_hello_elapsed += delta
		if _hello_elapsed >= 2:
			_hello_elapsed = 0
			_queue("ready",1,{}) # 初次 ACK 丢失后仍可解除世界加载屏障。
	for request_id: String in _pending.keys():
		var pending: Dictionary = _pending[request_id]
		if now-int(pending["sent_at"]) < 600: continue
		pending["sent_at"] = now
		pending["attempts"] += 1
		retransmissions += 1
		_queue("command",1,pending["data"])
	while not _outbox.is_empty() and int(_outbox.front()["due"]) <= now:
		var packet: Dictionary = _outbox.pop_front()
		_send(packet)

var _frame_sequence: int = 0
func _broadcast(full: bool) -> void:
	if authority == null: return
	_frame_sequence += 1
	_emit_local(full)
	for peer: int in _peer_actors:
		if peer == 1 or not _remote_ready.get(peer,false): continue
		var include_world: bool = full_cooperation and authority.state.lifecycle.get("phase","") == "loading" and not authority.state.lifecycle["loaded"].get(_peer_actors[peer],false)
		var data: Dictionary = authority.snapshot(_peer_actors[peer],include_world) if full else _position_frame()
		data["input_ack"] = int(_input_sequences.get(peer,-1))
		data["type"] = "state" if full else "frame"
		data["frame_sequence"] = _frame_sequence
		_queue("deliver" if full else "frame",peer,data)

func _position_frame() -> Dictionary:
	var players: Dictionary = {}
	for actor: String in authority.state.members:
		var point: Vector2 = authority.state.world.players[actor]
		var body: WildBodyState = authority.state.survival.bodies[actor]
		players[actor] = {"position":[point.x,point.y],"body":{"health_points":body.hp,"health":body.health,"hydration":body.water,"stamina":body.stamina}}
	var result: Dictionary = {"room_id":authority.state.room_id,"revision":authority.state.revision,"players":players,"elapsed_seconds":authority.state.survival.elapsed_seconds,"pending_seconds":authority.state.survival.pending_seconds}
	if full_cooperation:
		var compact: Dictionary = {}
		for actor: String in players:
			var body: WildBodyState = authority.state.survival.bodies[actor]
			var point: Vector2 = authority.state.world.players[actor]
			# 量化不能把仍存活的极低血量角色报告成死亡；死亡只由房主的精确零值决定。
			var health_points: float = maxf(0.01,snappedf(body.hp,0.01)) if body.hp > 0 else 0.0
			compact[actor] = [snappedf(point.x,0.01),snappedf(point.y,0.01),health_points,snappedf(body.health,0.01),snappedf(body.water,0.01),snappedf(body.stamina,0.01)]
		result.erase("players")
		result["compact_players"] = compact
	return result

func _emit_local(include_world: bool) -> void:
	var data: Dictionary = authority.snapshot(actor_id,include_world)
	data["type"] = "state"
	data["frame_sequence"] = _frame_sequence
	data["input_ack"] = int(_input_sequences.get(1,-1))
	_accept_packet(data)

func _queue(kind: String, peer: int, data: Dictionary) -> void:
	sent_packets += 1
	if force_next_drop:
		force_next_drop = false
		forced_dropped_packets += 1
		return
	if fault_drop_every > 0 and sent_packets % fault_drop_every == 0:
		dropped_packets += 1
		return
	# 尚未送出的快照可合并，命令 / 结果仍逐条可靠传输；保存待加载地图直至实际发送。
	if kind == "deliver" and data.get("type","") == "state":
		for index: int in range(_outbox.size()-1,-1,-1):
			var previous: Dictionary = _outbox[index]
			if previous["kind"] == kind and previous["peer"] == peer and previous["data"].get("type","") == "state":
				if not data.has("world") and previous["data"].has("world"): data["world"] = previous["data"]["world"]
				_outbox.remove_at(index)
	_outbox.append({"kind":kind,"peer":peer,"data":data.duplicate(true),"due":Time.get_ticks_msec()+fault_delay_ms})

func _send(packet: Dictionary) -> void:
	if not _active or (authority != null and not multiplayer.get_peers().has(packet["peer"])): return
	match packet["kind"]:
		"hello": _hello.rpc_id(packet["peer"],packet["data"])
		"command": _command.rpc_id(packet["peer"],packet["data"])
		"input": _receive_input.rpc_id(packet["peer"],packet["data"])
		"deliver":
			if packet["data"].get("type","") in ["welcome","state"]:
				var raw: PackedByteArray = var_to_bytes(packet["data"])
				if raw.size() <= MAXIMUM_SNAPSHOT_BYTES: _snapshot_blob.rpc_id(packet["peer"],raw.compress(FileAccess.COMPRESSION_DEFLATE))
			else: _deliver.rpc_id(packet["peer"],packet["data"])
		"control": _control.rpc_id(packet["peer"],packet["data"])
		"frame": _frame.rpc_id(packet["peer"],packet["data"])
		"ready": _ready_for_world.rpc_id(packet["peer"],packet["data"])

## 房主正常退出先持久化。失败留在房间重试，不能显示“已保存”。
func end_host() -> WildOperationResult:
	if authority == null: return WildOperationResult.reject(&"HOST_ONLY")
	if _ending: return WildOperationResult.accept()
	var result: WildOperationResult = authority.end_room()
	if not result.successful: return result
	_ending = true
	if full_cooperation: deliveries_received.emit(WildCoopDeliveries.pending(authority.state,actor_id))
	_send_terminal_receipts()
	return result

## 关闭宽限期内重发终态；接收端幂等处理，最后一包丢失不会丢掉近期操作结果。
func _send_terminal_receipts() -> void:
	_terminal_sent_at = Time.get_ticks_msec()
	for peer: int in _peer_actors:
		if peer != 1:
			var deliveries: Array = WildCoopDeliveries.pending(authority.state,_peer_actors[peer]) if full_cooperation else []
			_queue("control",peer,{"type":"ended","receipts":_recent_results.get(_peer_actors[peer],{}).duplicate(true),"deliveries":deliveries})

func close_connection() -> void:
	if _active: multiplayer.multiplayer_peer.close()
	_active = false
	_welcomed = false
	_outbox.clear()
	_inputs.clear()
	_input_sequences.clear()
	_pending.clear()
	_remote_ready.clear()
	_welcome_sent_at.clear()
	_peer_actors.clear()
	_peer_tokens.clear()
	_recent_results.clear()
	latest = {}
	_sequence = 0
	_ending = false
	_terminal_received = false
	_terminal_sent_at = 0
	_state_revision = -1
	if authority != null: authority = null

func _exit_tree() -> void:
	close_connection()
