class_name WildRunFlow
extends RefCounted
## 主流程状态机，只有应用服务能提交转换，界面不能跳过准备 / 生成步骤。

enum Phase { BASE, PREPARATION, GENERATING, WILDERNESS, SETTLEMENT }

const TRANSITIONS: Dictionary = {
	Phase.BASE: [Phase.PREPARATION],
	Phase.PREPARATION: [Phase.BASE, Phase.GENERATING],
	Phase.GENERATING: [Phase.BASE, Phase.WILDERNESS],
	Phase.WILDERNESS: [Phase.SETTLEMENT],
	Phase.SETTLEMENT: [Phase.BASE],
}

var current_phase: Phase = Phase.BASE


## 非法转换不会改变现有阶段；生成失败允许退回基地。
func try_transition(next_phase: Phase) -> WildOperationResult:
	if not TRANSITIONS[current_phase].has(next_phase):
		return WildOperationResult.reject(&"INVALID_PHASE_TRANSITION")
	current_phase = next_phase
	return WildOperationResult.accept({"phase": next_phase})
