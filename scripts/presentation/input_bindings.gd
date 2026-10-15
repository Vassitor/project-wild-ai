class_name WildInputBindings
extends RefCounted
## 安装默认键鼠动作，仅补充缺失项，不覆盖用户以后自定义的键位。

const KEYS: Dictionary = {
	&"move_left": KEY_A, &"move_right": KEY_D,
	&"move_up": KEY_W, &"move_down": KEY_S,
	&"sprint": KEY_SHIFT, &"interact": KEY_E,
	&"inventory": KEY_TAB, &"craft": KEY_C,
	&"body_details": KEY_H,
	&"skills": KEY_K,
	&"field_guide": KEY_F1,
	&"build": KEY_B, &"rotate_item": KEY_R, &"pause": KEY_ESCAPE,
}


static func install_defaults() -> void:
	for action: StringName in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = KEYS[action]
		InputMap.action_add_event(action, event)
	if not InputMap.has_action(&"attack"):
		InputMap.add_action(&"attack")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(&"attack", click)
