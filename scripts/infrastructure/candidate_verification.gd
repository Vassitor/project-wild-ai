class_name WildCandidateVerification
extends RefCounted
## 候选包的显式 QA 入口。必须在身份初始化前处理，错误参数也不能回落到正式档案。
static func start(tree: SceneTree) -> bool:
	if tree.get_meta("candidate_probe_started",false): return false
	if "--qa-probe" not in OS.get_cmdline_user_args(): return false
	if not OS.has_feature("candidate_qa"):
		tree.quit(1)
		return true
	tree.set_meta("candidate_probe_started",true)
	var probe: Node=load("res://scripts/diagnostics/candidate_probe.gd").new()
	tree.root.add_child.call_deferred(probe)
	return true
