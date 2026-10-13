extends RefCounted
## 仅测试使用的伤病布置；游戏 UI 与网络没有这些状态设置入口。
static func create_state(config: WildGameConfig, actor: String, world: Dictionary) -> WildBaseState:
	var result := WildBaseState.new(actor,config)
	result.phase = WildRunFlow.Phase.WILDERNESS
	var raw: Dictionary = world.duplicate(true)
	raw["players"] = {actor:[(float(raw["spawn"][0])+0.5)*32,(float(raw["spawn"][1])+0.5)*32]}
	result.world = WildWorldCodec.decode(raw,config)
	result.survival = WildSurvivalSimulation.create(actor,"17")
	result.active_run = {"run_id":WildStableId.create("run"),"seed":"17","origin_containers":WildBaseState.new(actor,config).record()["containers"]}
	return result

static func give(state: WildBaseState, kind: StringName, catalog: WildItemCatalog, config: WildGameConfig, quantity: int = 1) -> WildItemInstance:
	var item := WildItemInstance.new(catalog.find(kind),quantity)
	assert(WildInventoryOperations.insert(state,catalog,config,item))
	return WildInventoryOperations.find(state,WildInventoryOperations.choose(state,kind))["item"]
