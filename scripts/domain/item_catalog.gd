class_name WildItemCatalog
extends Resource
## 稳定 ID 查询，不依赖中文名称；不持有玩家实例。

@export var definitions: Array[WildItemDefinition] = []


func find(id: StringName) -> WildItemDefinition:
	for definition: WildItemDefinition in definitions:
		if definition.item_id == id:
			return definition
	return null


func validate() -> bool:
	var seen: Dictionary = {}
	for definition: WildItemDefinition in definitions:
		if definition == null or not definition.valid() or seen.has(definition.item_id):
			return false
		seen[definition.item_id] = true
	return not definitions.is_empty()
