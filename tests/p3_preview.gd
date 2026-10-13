extends Control
## MCP 图形验证：档案 / 营地来自默认规则自动策略，身份重映射仅用于随机隔离的验证档案。
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var _path: String
var _actor: String

func _ready() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var journey := WildP3Journey.new()
	var state: WildBaseState = journey.run("17",true)
	if state == null or not journey.failure.is_empty():
		push_error("P3 preview setup failed: %s" % journey.failure)
		get_tree().quit(1)
		return
	_path = "res://.godot/verification/p3_preview_%s.cfg" % WildStableId.create("capture")
	_actor = WildProfileIdentityStore.new(_path).load_or_create().payload["player_id"]
	_reidentify(state)
	var store := WildBaseStateStore.new(_path.get_basename()+"_base.json")
	if not store.save_record(state.record()).successful:
		get_tree().quit(1)
		return
	var main: WildMain = MAIN.instantiate() as WildMain
	main._profile_path = _path
	add_child(main)
	main.session.set_focus_lost(false)
	await _save_frame("p3-survival")
	var fire: Dictionary = {}
	for building: Dictionary in main.session.survival_snapshot(_actor)["buildings"].values():
		if building["kind"] == "fire": fire = building
	main._open_survival_options(fire)
	await _save_frame("p3-actions")
	main._close_station()
	main._open_station(&"storage")
	var bag: Dictionary = main.session.base_snapshot(_actor)
	for entry: Dictionary in bag["containers"]["backpack"]["entries"]:
		if entry["item"]["item_id"] == "ration":
			main._base_panel._select_item("backpack",entry["item"]["id"])
			break
	await _save_frame("p3-inventory")
	main._close_station()
	main.queue_free()
	await get_tree().process_frame
	var victory_record: Dictionary = WildBaseStateStore.new("res://.godot/verification/p3-journey-victory.json").load_records().payload["primary"]
	var victory: WildBaseState = WildBaseStateCodec.decode(victory_record,"p",WildMain.CONFIG,WildMain.CATALOG)
	if victory != null:
		_reidentify(victory)
		store.save_record(victory.record())
		var result_main: WildMain = MAIN.instantiate() as WildMain
		result_main._profile_path = _path
		add_child(result_main)
		await _save_frame("p3-victory")
	print("P3 graphical preview: survival, actions, inventory, victory saved; isolated profile")
	await get_tree().create_timer(45.0,true).timeout
	get_tree().quit()

func _reidentify(state: WildBaseState) -> void:
	state.player_id = _actor
	for container: WildInventoryContainer in state.containers.values(): container.owner_id = _actor
	if state.world != null:
		var point: Vector2 = state.world.players["p"]
		state.world.players.clear()
		state.world.players[_actor] = point
	if state.survival != null:
		var body: WildBodyState = state.survival.bodies["p"]
		state.survival.bodies.clear()
		state.survival.bodies[_actor] = body
		if state.survival.activities.has("p"):
			state.survival.activities[_actor] = state.survival.activities["p"]
			state.survival.activities.erase("p")
		for output: Dictionary in state.survival.outputs.values(): output["owner"] = _actor

func _save_frame(title: String) -> void:
	for frame: int in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png("res://.godot/verification/%s.png" % title)
	if error != OK: push_error("P3 preview screenshot failed: %s" % title)
