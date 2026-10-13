class_name WildOperationResult
extends RefCounted
## 命令处理结果。错误码与界面中文分离，未来网络传输只序列化基础字段。

var successful: bool
var code: StringName
var payload: Dictionary


func _init(was_successful: bool, result_code: StringName, result_payload: Dictionary = {}) -> void:
	successful = was_successful
	code = result_code
	payload = result_payload.duplicate(true)


static func accept(data: Dictionary = {}) -> WildOperationResult:
	return WildOperationResult.new(true, &"OK", data)


static func reject(error_code: StringName) -> WildOperationResult:
	return WildOperationResult.new(false, error_code)


## 缓存与调用者各持有自己的结果，避免展示层修改重发收据。
func copy() -> WildOperationResult:
	return WildOperationResult.new(successful, code, payload)
