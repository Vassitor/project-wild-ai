extends RefCounted
## 测试寻找规则认可、且完工后可交互的箱子位置，不改变生产环境地图。
static func box_site(state: WildBaseState, actor: String) -> WildOperationResult:
	var origin: Vector2i = state.world.cell_at(state.world.players[actor])
	for y: int in range(origin.y-3,origin.y+4):
		for x: int in range(origin.x-3,origin.x+4):
			var site := {"x":x,"y":y,"width":1,"height":1}
			if WildBuildingRules.can_build(state,actor,Vector2i(x,y),Vector2i.ONE).successful and WildBuildingRules.in_reach(state.world,actor,site): return WildOperationResult.accept({"x":x,"y":y})
	return WildOperationResult.reject(&"INVALID_BUILD_SITE")

static func stack_with_amount(state: WildBaseState, definition: StringName, quantity: int) -> String:
	for entry: Dictionary in state.containers["backpack"].placements.values():
		var item: WildItemInstance = entry["item"]
		if item.item_id == definition and item.quantity >= quantity: return item.instance_id
	return ""
