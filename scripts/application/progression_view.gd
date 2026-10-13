class_name WildProgressionView
extends RefCounted
## 可观察的共享设施视图；检查时间 / 捕获可见，未来捕获的随机序列不发给客户端。
static func buildings(run: WildSurvivalState) -> Dictionary:
	var view: Dictionary = run.buildings.duplicate(true)
	for building: Dictionary in view.values(): building.erase("trap_random_state")
	return view
