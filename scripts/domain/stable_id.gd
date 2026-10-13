class_name WildStableId
extends RefCounted
## 生成持久实体 ID；它与网络临时 peer ID、场景 NodePath 没有关系。


static func create(prefix: String) -> String:
	return "%s_%s" % [prefix, Crypto.new().generate_random_bytes(16).hex_encode()]
