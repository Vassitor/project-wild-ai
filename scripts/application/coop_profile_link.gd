class_name WildCoopProfileLink
extends RefCounted
## 本机个人存档与房主消息的桥接；只在个人写盘成功后 ACK，断线不解锁租约。
var network: WildENetRoom
var base: WildBaseService
var actor: String
var _acknowledged: Dictionary = {}

func configure(room: WildENetRoom, profile: WildBaseService, owner: String) -> void:
	network = room
	base = profile
	actor = owner
	network.snapshot_received.connect(_snapshot)
	network.deliveries_received.connect(apply_deliveries)
	network.command_completed.connect(func(id: String, result: WildOperationResult) -> void:
		if id.begins_with("ack:") and result.successful: _acknowledged[id.trim_prefix("ack:")] = true)

func reserve_and_offer() -> WildOperationResult:
	if network.latest.is_empty() or not network._active or not network._welcomed: return WildOperationResult.reject(&"NOT_CONNECTED")
	var result: WildOperationResult = base.submit(WildGameCommand.new(actor,&"coop.reserve",{"room_id":network.latest["room_id"],"run_id":network.latest["run_id"]}))
	if not result.successful: return result
	var request: String = network.request("profile.offer",{"manifest":result.payload["manifest"]})
	return WildOperationResult.accept() if not request.is_empty() else WildOperationResult.reject(&"NOT_CONNECTED")

func _snapshot(data: Dictionary) -> void:
	apply_deliveries(data.get("cooperation",{}).get("deliveries",[]))

func apply_deliveries(events: Array) -> void:
	for event: Variant in events:
		if not event is Dictionary: continue
		var result: WildOperationResult = base.submit(WildGameCommand.new(actor,&"coop.apply_event",event,"delivery:"+str(event.get("hash","invalid"))))
		if not result.successful:
			network.connection_status.emit("个人进度尚未写入："+str(result.code)+"；保留待同步行装。")
			return
		var event_hash: String = event["hash"]
		# 仅收到房主成功收据才记作 ACK；断线清除在途请求后可再次提交，不能永久漏确认。
		if not _acknowledged.has(event_hash) and not network._pending.has("ack:"+event_hash):
			network.request("profile.ack",{"event_id":event["event_id"],"hash":event_hash},"ack:"+event_hash)
