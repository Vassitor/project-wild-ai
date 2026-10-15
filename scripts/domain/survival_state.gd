class_name WildSurvivalState
extends RefCounted
## 单局共享数据按玩家 ID 索引。等待输出、动作材料锁、计时与随机状态都可保存。
var elapsed_seconds: float = 0.0
var pending_seconds: float = 0.0
var segments: Array[Dictionary] = []
var bodies: Dictionary[String, WildBodyState] = {}
var actions: Dictionary = {}
var buildings: Dictionary = {}
var outputs: Dictionary = {}
var explored: Dictionary = {}
var explored_by_actor: Dictionary = {}
var activities: Dictionary = {}
var random_state: String = "1"
var outcome: String = "running"
var notice: String = ""
## P5 单局实体 / 限额；永久技能在各玩家 WildBaseState.skills 中。
var progression_initialized: bool = false
var prey: Dictionary = {}
var fish_refills: Dictionary = {}
var fishing_random_states: Dictionary = {}
var build_experience_counts: Dictionary = {}
## P6 沿用猎物稳定 ID；现实冷却编码为本局游戏时刻，读档不重置。
var combat_initialized: bool = false
var departure_players: int = 1
var projectiles: Dictionary = {}
var attack_ready_at: Dictionary = {}
var tracks: Array[Dictionary] = []
var combat_feedback: Dictionary = {}
var wildlife_random_state: String = "1"
var sleep_random_states: Dictionary = {}
var next_animal_refill: float = 86400.0
var next_disturbance: float = 3600.0
var next_animal_serial: int = 0

func record() -> Dictionary:
	var raw: Dictionary = _base_record()
	raw["explored_by_actor"] = explored_by_actor.duplicate(true)
	raw["sleep_random_states"] = sleep_random_states.duplicate()
	raw["combat"] = {"version":1,"initialized":combat_initialized,"departure_players":departure_players,"projectiles":projectiles.duplicate(true),"attack_ready_at":attack_ready_at.duplicate(),"tracks":tracks.duplicate(true),"feedback":combat_feedback.duplicate(true),"random_state":wildlife_random_state,"next_refill":next_animal_refill,"next_disturbance":next_disturbance,"serial":next_animal_serial}
	return raw

func _base_record() -> Dictionary:
	var body_records: Dictionary = {}
	for actor: String in bodies: body_records[actor] = bodies[actor].record()
	return {"elapsed_seconds":elapsed_seconds,"pending_seconds":pending_seconds,"segments":segments.duplicate(true),"bodies":body_records,"actions":actions.duplicate(true),"buildings":buildings.duplicate(true),"outputs":outputs.duplicate(true),"explored":explored.duplicate(true),"activities":activities.duplicate(true),"random_state":random_state,"outcome":outcome,"notice":notice,"progression":{"version":1,"initialized":progression_initialized,"prey":prey.duplicate(true),"fish_refills":fish_refills.duplicate(),"fishing_random_states":fishing_random_states.duplicate(),"build_experience_counts":build_experience_counts.duplicate(true)}}

func copy() -> WildSurvivalState:
	var other := WildSurvivalState.new()
	other.elapsed_seconds = elapsed_seconds
	other.pending_seconds = pending_seconds
	other.segments.assign(segments.duplicate(true))
	for actor: String in bodies: other.bodies[actor] = bodies[actor].copy()
	other.actions = actions.duplicate(true)
	other.buildings = buildings.duplicate(true)
	other.outputs = outputs.duplicate(true)
	other.explored = explored.duplicate(true)
	other.explored_by_actor = explored_by_actor.duplicate(true)
	other.activities = activities.duplicate(true)
	other.random_state = random_state
	other.outcome = outcome
	other.notice = notice
	other.progression_initialized = progression_initialized
	other.prey = prey.duplicate(true)
	other.fish_refills = fish_refills.duplicate()
	other.fishing_random_states = fishing_random_states.duplicate()
	other.build_experience_counts = build_experience_counts.duplicate(true)
	other.combat_initialized = combat_initialized
	other.departure_players = departure_players
	other.projectiles = projectiles.duplicate(true)
	other.attack_ready_at = attack_ready_at.duplicate()
	other.tracks.assign(tracks.duplicate(true))
	other.combat_feedback = combat_feedback.duplicate(true)
	other.wildlife_random_state = wildlife_random_state
	other.sleep_random_states = sleep_random_states.duplicate()
	other.next_animal_refill = next_animal_refill
	other.next_disturbance = next_disturbance
	other.next_animal_serial = next_animal_serial
	return other

func mark_activity(actor: String, kind: String) -> void:
	if kind.is_empty(): return
	if not activities.has(actor): activities[actor] = []
	if not activities[actor].has(kind): activities[actor].append(kind)
