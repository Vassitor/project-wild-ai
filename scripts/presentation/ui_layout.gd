class_name WildUiLayout
extends RefCounted
## 只处理逻辑视口坐标和面板层级；不决定单机 / 合作是否暂停。

## 居中面板按可用逻辑尺寸收缩；内部长内容由各面板的 ScrollContainer 承接。
static func center(control: Control, viewport_size: Vector2, preferred: Vector2, margin: float = 20) -> void:
	var available: Vector2 = viewport_size - Vector2.ONE * margin * 2
	control.size = Vector2(minf(preferred.x, available.x), minf(preferred.y, available.y))
	control.position = ((viewport_size - control.size) / 2).floor()

## 遮罩只拦截背景鼠标，所有菜单继续使用既有会话暂停策略。
static func modal_backdrop(owner: Control, panels: Array[Control]) -> ColorRect:
	var backdrop := ColorRect.new()
	backdrop.name = "MenuBackdrop"
	backdrop.color = Color(0.025, 0.055, 0.045, 0.66)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.z_index = 100
	backdrop.visible = false
	owner.add_child(backdrop)
	var update: Callable = func() -> void:
		backdrop.visible = panels.any(func(panel: Control) -> bool: return panel.visible)
	for panel: Control in panels:
		panel.z_index = 101
		panel.visibility_changed.connect(update)
	update.call()
	return backdrop
