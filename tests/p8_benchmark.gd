extends SceneTree
## 主线程成本基线：真实完整状态与提交日志；只写随机工作区档案。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const F = preload("res://tests/p6_fixtures.gd")
const P5 = preload("res://tests/p5_fixtures.gd")
const PATHS = preload("res://tests/verification_paths.gd")
var result: Dictionary = {}
var failed: int = 0

func _initialize() -> void:
	if not PATHS.arguments_are_isolated(): quit(1); return
	_run.call_deferred()

func _run() -> void:
	result["hardware"] = {"cpu":OS.get_processor_name(),"logical_cpus":OS.get_processor_count(),"memory":OS.get_memory_info(),"os":OS.get_distribution_name(),"engine":Engine.get_version_info()["string"]}
	var single: WildBaseState = F.create()
	_measure("single",func() -> Dictionary: return single.record(),func() -> WildOperationResult:
		WildSurvivalSimulation.queue_time(single.survival,60,"idle")
		WildSurvivalSimulation.process(single,CONFIG,CATALOG,CONTENT,true)
		return WildOperationResult.accept())
	var service := WildFullCoopService.new(CONFIG,CATALOG,CONTENT,func(_raw: Dictionary,_backup: bool) -> WildOperationResult: return WildOperationResult.accept())
	assert(service.create("p0","host","17","secret").successful)
	for actor: String in ["p1","p2","p3"]: assert(service.join(actor,actor,"").successful)
	for actor: String in service.state.members:
		var personal := WildBaseState.new(actor,CONFIG)
		for kind: String in ["knife","bottle","ration"]: P5.give(personal,kind)
		var lease: WildOperationResult = WildCoopProfileRules.execute(personal,"coop.reserve",{"room_id":service.state.room_id,"run_id":service.state.run_id},CONFIG,CATALOG)
		assert(WildCoopLifecycle.offer(service.state,actor,lease.payload,CONFIG,CATALOG).successful)
		service.state.lifecycle["ready"][actor] = true
	assert(WildCoopLifecycle.start(service.state,service.online,CONFIG).successful)
	service.state.lifecycle["phase"] = "running"
	_measure("four",service.state.record,func() -> WildOperationResult:
		WildSurvivalSimulation.queue_time(service.state.survival,60,"idle")
		service._simulate(service.state,true)
		return WildOperationResult.accept())
	result["scope"] = "Seed 17 default populations; main-thread record + durable journal/head/primary, 12 commits each; simulation 60 game seconds each; not a GPU frame-rate test."
	var file := FileAccess.open("res://.godot/verification/p8-benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("P8 benchmark "+JSON.stringify(result))
	quit(failed)

func _measure(label: String, record: Callable, simulate: Callable) -> void:
	var store := WildDurableStateStore.new(PATHS.profile("p8-benchmark-"+label)+".json")
	var saves: Array[float] = []
	var simulations: Array[float] = []
	var raw: Dictionary = {}
	var timeline: Dictionary = {}
	var phases: Dictionary = {"prepare":[],"journal":[],"head":[],"primary":[]}
	store.stage_check = func(stage: String) -> bool:
		timeline[stage] = Time.get_ticks_usec()
		return true
	for index: int in range(12):
		var began: int = Time.get_ticks_usec()
		timeline.clear()
		timeline["begin"] = began
		raw = record.call()
		var saved: WildOperationResult = store.save_record(raw)
		var end: int = Time.get_ticks_usec()
		for key: String in phases:
			var edges: Array = {"prepare":["begin","journal"],"journal":["journal","commit"],"head":["commit","primary"],"primary":["primary","end"]}[key]
			phases[key].append(((end if edges[1] == "end" else int(timeline[edges[1]]))-int(timeline[edges[0]]))/1000.0)
		saves.append((Time.get_ticks_usec()-began)/1000.0)
		if not saved.successful: failed += 1
		began = Time.get_ticks_usec()
		simulate.call()
		simulations.append((Time.get_ticks_usec()-began)/1000.0)
	var restored: WildOperationResult = store.load_records()
	if not restored.successful: failed += 1
	result[label] = {"save_ms":_stats(saves),"simulate_minute_ms":_stats(simulations),"json_bytes":JSON.stringify(raw,"\t",true,true).to_utf8_buffer().size(),"restored":restored.successful}
	for phase: String in phases:
		var values: Array[float] = []
		values.assign(phases[phase])
		result[label][phase+"_ms"] = _stats(values)

func _stats(samples: Array[float]) -> Dictionary:
	samples.sort()
	return {"min":samples[0],"median":samples[floori(samples.size()/2.0)],"p95":samples[ceili(samples.size()*0.95)-1],"max":samples.back()}
