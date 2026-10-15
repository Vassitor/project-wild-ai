class_name WildCoopDeliveries
extends RefCounted
## 房主持久 outbox。事件与完整世界在同一事务保存，收到个人写盘 ACK 才标记交付。
static func initialize(room: WildCoopState) -> void:
	room.lifecycle = {"version":1,"phase":"lobby","ready":{},"loaded":{},"offers":{},"outbox":{},"acks":{},"dead":{},"vote":{},"gifts":{},"real_seconds":0.0,"world_hash":""}

static func emit_event(room: WildCoopState, actor: String, kind: String, details: Dictionary = {}) -> Dictionary:
	var offer: Dictionary = room.lifecycle["offers"][actor]
	offer["seq"] += 1
	var event: Dictionary = {"version":1,"room_id":room.room_id,"run_id":room.run_id,"owner":actor,"lease_id":offer["manifest"]["lease_id"],"event_id":"%s:%d" % [offer["manifest"]["lease_id"],offer["seq"]],"seq":offer["seq"],"kind":kind,"skills":room.members[actor].skills.record(),"reward":0,"items":[],"won":false,"elapsed_seconds":room.survival.elapsed_seconds,"reason":""}
	event.merge(details,true)
	event["hash"] = WildCoopProfileRules.digest(event)
	if not room.lifecycle["outbox"].has(actor): room.lifecycle["outbox"][actor] = {}
	room.lifecycle["outbox"][actor][event["event_id"]] = event
	offer["skills_hash"] = WildCanonicalData.digest(event["skills"])
	return event

static func pending(room: WildCoopState, actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in room.lifecycle.get("outbox",{}).get(actor,{}).values():
		if not room.lifecycle["acks"].has(event["event_id"]): result.append(event.duplicate(true))
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a["lease_id"] < b["lease_id"] if a["lease_id"] != b["lease_id"] else a["seq"] < b["seq"])
	return result

static func growth(room: WildCoopState) -> void:
	for actor: String in room.lifecycle["offers"]:
		var offer: Dictionary = room.lifecycle["offers"][actor]
		if offer["active"] and offer["skills_hash"] != WildCanonicalData.digest(room.members[actor].skills.record()): emit_event(room,actor,"growth")

static func acknowledge(room: WildCoopState, actor: String, data: Dictionary) -> WildOperationResult:
	var event: Dictionary = room.lifecycle["outbox"].get(actor,{}).get(str(data.get("event_id","")),{})
	if event.is_empty() or data.get("hash","") != event["hash"]: return WildOperationResult.reject(&"INVALID_DELIVERY")
	room.lifecycle["acks"][event["event_id"]] = event["hash"]
	return WildOperationResult.accept()
