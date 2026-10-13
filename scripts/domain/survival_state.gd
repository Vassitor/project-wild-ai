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

func record() -> Dictionary:
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
	other.activities = activities.duplicate(true)
	other.random_state = random_state
	other.outcome = outcome
	other.notice = notice
	other.progression_initialized = progression_initialized
	other.prey = prey.duplicate(true)
	other.fish_refills = fish_refills.duplicate()
	other.fishing_random_states = fishing_random_states.duplicate()
	other.build_experience_counts = build_experience_counts.duplicate(true)
	return other

func mark_activity(actor: String, kind: String) -> void:
	if kind.is_empty(): return
	if not activities.has(actor): activities[actor] = []
	if not activities[actor].has(kind): activities[actor].append(kind)
