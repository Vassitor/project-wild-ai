extends Control
## 1080p 本机帧时间采样：真实单机 / 四人权威加视图。四人使用快照驱动夹具，不冒充远端 GPU / LAN 测量。
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const PATHS = preload("res://tests/verification_paths.gd")
const F = preload("res://tests/p6_fixtures.gd")
var main: WildMain
var coop: WildFullCoopMain
var service: WildFullCoopService
var store: WildDurableStateStore
var sync_seconds: float = 0
var results: Dictionary = {}

func _ready() -> void:
	Engine.max_fps=60
	get_window().size=Vector2i(1920,1080)
	_capture.call_deferred()

func _capture() -> void:
	if not PATHS.arguments_are_isolated(): get_tree().quit(1); return
	results["adapter"]=RenderingServer.get_video_adapter_name()
	results["physical_window"]=[get_window().size.x,get_window().size.y]
	main=preload("res://scenes/main.tscn").instantiate() as WildMain
	main._profile_path=PATHS.profile("p8-render")
	add_child(main)
	var state: WildBaseState=F.create(main.local_player_id)
	_add_buildings(state)
	main.session._base_services[main.local_player_id]._state=state
	var began: int=Time.get_ticks_usec()
	# 注入领域夹具后同步会话流程，确保测到荒野而非仍停留在基地的视图。
	main.session._on_base_changed(main.local_player_id)
	assert(main.wilderness_world.visible and not main.base_world.visible)
	results["single_load_ms"]=(Time.get_ticks_usec()-began)/1000.0
	await _sample("single",state.survival.prey.size())
	main._open_guide()
	await get_tree().create_timer(0.3).timeout
	await _image("p8-audio-guide")
	main._close_station()
	main.queue_free()
	await get_tree().process_frame
	main=null
	coop=preload("res://scenes/coop_full.tscn").instantiate() as WildFullCoopMain
	coop._profile_override=PATHS.profile("p8-render-four")
	coop._room_root=coop._profile_override.get_basename()+"_rooms"
	add_child(coop)
	store=WildDurableStateStore.new(PATHS.profile("p8-render-world")+".json")
	service=WildFullCoopService.new(CONFIG,CATALOG,CONTENT,store.save_record)
	var actor: String=coop.network.actor_id
	assert(service.create(actor,"房主","17","secret").successful)
	for member: String in ["青松","落叶","溪流"]: assert(service.join(member,member,"").successful)
	for member: String in service.state.members:
		var personal:=WildBaseState.new(member,CONFIG)
		var offer: WildOperationResult=WildCoopProfileRules.execute(personal,"coop.reserve",{"room_id":service.state.room_id,"run_id":service.state.run_id},CONFIG,CATALOG)
		assert(WildCoopLifecycle.offer(service.state,member,offer.payload,CONFIG,CATALOG).successful)
		service.state.lifecycle["ready"][member]=true
	assert(WildCoopLifecycle.start(service.state,service.online,CONFIG).successful)
	service.state.lifecycle["phase"]="running"
	_add_buildings(service.state.members[actor])
	began=Time.get_ticks_usec()
	_sync(true)
	results["four_load_ms"]=(Time.get_ticks_usec()-began)/1000.0
	await _sample("four",service.state.survival.prey.size())
	results["scope"]="1920x1080 physical window, default half-resolution world SubViewport, 64 building fixtures, normal populations, actual synchronous durable saves; four-person authority plus host UI without three remote client processes."
	FileAccess.open("res://.godot/verification/p8-render.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("P8 render benchmark "+JSON.stringify(results))
	service=null
	await get_tree().create_timer(20).timeout
	get_tree().quit()

func _physics_process(delta: float) -> void:
	if service==null or coop==null: return
	service.advance(minf(delta,0.1))
	sync_seconds+=delta
	if sync_seconds>=0.5:
		sync_seconds=0
		_sync(false)

func _sync(include_world: bool) -> void:
	coop.network.latest=service.snapshot(coop.network.actor_id,include_world)
	coop.session._on_snapshot(coop.network.latest)
	coop._on_snapshot(coop.network.latest)

func _sample(label: String, animals: int) -> void:
	await get_tree().create_timer(2).timeout
	var intervals: Array[float]=[]
	var began: int=Time.get_ticks_usec()
	var previous: int=began
	while Time.get_ticks_usec()-began<12000000:
		await get_tree().process_frame
		var now: int=Time.get_ticks_usec()
		intervals.append((now-previous)/1000.0)
		previous=now
	var total: float=(Time.get_ticks_usec()-began)/1000000.0
	intervals.sort()
	results[label]={"frames":intervals.size(),"seconds":total,"average_fps":intervals.size()/total,"p95_ms":intervals[ceili(intervals.size()*0.95)-1],"max_ms":intervals.back(),"animals":animals,"buildings":64}
	await _image("p8-"+label+"-1080p")

func _image(title: String) -> void:
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png("res://.godot/verification/"+title+".png")==OK)

func _add_buildings(state: WildBaseState) -> void:
	# 布局压力夹具，不给玩家发材料或成长；避开实际资源与投放格。
	var occupied: Dictionary={}
	for resource: Dictionary in state.world.resources.values(): occupied[Vector2i(resource["x"],resource["y"])]=true
	for cell: Vector2i in state.world.distances(state.world.spawn):
		if state.survival.buildings.size()>=64: break
		if occupied.has(cell) or cell.distance_to(state.world.spawn)<4 or cell.distance_to(state.world.spawn)>24: continue
		var id: String="stress:"+str(state.survival.buildings.size())
		state.survival.buildings[id]={"id":id,"kind":"fire","x":cell.x,"y":cell.y,"width":1,"height":1,"level":1,"lit":false,"fuel_seconds":0.0}
	WildBuildingRules.rebuild_obstacles(state.world,state.survival)
