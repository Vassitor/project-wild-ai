extends SceneTree
const CONFIG: WildGameConfig = preload("res://data/game_config.tres")
const CATALOG: WildItemCatalog = preload("res://data/item_catalog.tres")
const CONTENT: WildSurvivalContent = preload("res://data/survival_content.tres")
const PATHS = preload("res://tests/verification_paths.gd")
const F = preload("res://tests/p5_fixtures.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	if not PATHS.arguments_are_isolated(): quit(1); return
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if value: passed+=1
	else: failed+=1; push_error(label)

func _run() -> void:
	var path: String=PATHS.profile("p8-journal")+".json"
	var store:=WildDurableStateStore.new(path)
	check(store.save_record({"value":1.23456789012345}).successful,"compact commit")
	check(not FileAccess.get_file_as_string(path).contains("\t"),"primary compact encoding")
	FileAccess.open(path,FileAccess.WRITE).store_string("corrupted")
	check(store.save_record({"value":2}).successful and store.load_records().payload["primary"]["value"]==2,"changed raw file restored before next commit")
	var invalid:=WildDurableStateStore.new(PATHS.profile("p8-invalid")+".json")
	var data: String="not-json"
	FileAccess.open(invalid._path,FileAccess.WRITE).store_string(data)
	check(invalid._head.save_record({"version":1,"sequence":1,"hash":data.sha256_text()}).successful,"malformed previous transaction fixture")
	check(invalid.save_record({"value":3}).code==&"JOURNAL_INVALID","cold writer must parse / validate even with matching raw hash")
	var audio:=WildUiFeedback.new()
	var owner:=Control.new()
	root.add_child(owner)
	owner.add_child(audio)
	var prefs: String=PATHS.profile("p8-audio")
	audio.configure(owner,prefs)
	check(audio.set_volume(0)==OK and audio.volume==0,"explicit mute persisted")
	audio.play()
	check(not audio._player.playing,"mute produces no playback")
	check(audio.set_volume(0.42)==OK,"volume adjustable")
	var another:=WildUiFeedback.new()
	owner.add_child(another)
	another.configure(owner,prefs)
	check(is_equal_approx(another.volume,0.42),"preferences restored independently of survival saves")
	var wave: AudioStreamWAV=audio._player.stream as AudioStreamWAV
	check(wave!=null and wave.data.size()>0 and wave.get_length()<0.1,"bounded generated cue, no external audio dependency")
	owner.queue_free()
	await process_frame
	var ordinary: WildBaseState=F.create_state()
	F.give(ordinary,"wood",8)
	F.give(ordinary,"fiber",6)
	var site: Dictionary=F.open_site(ordinary,Vector2i(2,2))
	check(F.start(ordinary,{"action":"build","recipe":"camp","x":site["x"],"y":site["y"]}).successful,"comparison camp built by actual action")
	F.finish(ordinary)
	ordinary.survival.bodies["p"].water=80
	ordinary.survival.bodies["p"].nutrition=[70.0,70.0,70.0,70.0,70.0]
	check(F.start(ordinary,{"action":"sleep","hours":2}).successful,"same legal sleep begins")
	var skipped: WildBaseState=ordinary.copy(CONFIG)
	for second: int in range(7200): F.time(ordinary,1,"sleep")
	WildSurvivalSimulation.sleep(skipped,"p",CONFIG,CATALOG,CONTENT)
	var a: WildBodyState=ordinary.survival.bodies["p"]
	var b: WildBodyState=skipped.survival.bodies["p"]
	check(absf(a.hp-b.hp)<0.001 and absf(a.water-b.water)<0.001 and absf(a.stamina-b.stamina)<0.001,"ordinary versus skipped sleep body / hydration / stamina")
	for index: int in range(5): check(absf(a.nutrition[index]-b.nutrition[index])<0.001,"sleep nutrition consistency "+str(index))
	check(absf(ordinary.survival.elapsed_seconds-skipped.survival.elapsed_seconds)<0.001 and ordinary.survival.actions.is_empty() and skipped.survival.actions.is_empty(),"same elapsed time and action completion")
	check(ordinary.survival.fish_refills==skipped.survival.fish_refills,"world refill schedule is not multiplied by sleep")
	print("P8 checks: %d passed, %d failed" % [passed,failed])
	quit(0 if failed==0 else 1)
