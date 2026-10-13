class_name WildGameCommand
extends RefCounted
## 用户意图，不直接写状态。payload 只接受未来可传输的基础数据。

var request_id: String
var actor_id: String
var operation: StringName
var payload: Dictionary


func _init(actor: String, action: StringName, data: Dictionary = {}, id: String = "") -> void:
	actor_id = actor
	operation = action
	payload = data.duplicate(true)
	request_id = id if not id.is_empty() else WildStableId.create("request")
