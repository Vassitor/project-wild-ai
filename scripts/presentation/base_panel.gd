class_name WildBasePanel
extends PanelContainer
## 基地面板：商品目录、网格快照、装备槽和出发按钮。所有操作通过会话提交。

signal close_requested

var _session: WildLocalSession
var _actor: String
var _catalog: WildItemCatalog
var _config: WildGameConfig
var _station: StringName = &"storage"
var _view: Dictionary = {}
var _selection: Dictionary = {}
var _selected_definition: StringName = &"axe"
var _body: VBoxContainer
var _status: Label
var _selection_view: VBoxContainer
var _quantity: SpinBox
var _seed_input: LineEdit
var _split_dialog: ConfirmationDialog
var _split_quantity: SpinBox
var _split_grid: WildInventoryGrid
var _split_id: String
var _notice: String = "拖动整理；R 旋转；Shift + 点击拆分堆叠。"
signal survival_action_started


func configure(session: WildLocalSession, actor: String, catalog: WildItemCatalog, config: WildGameConfig) -> void:
	_session = session
	_actor = actor
	_catalog = catalog
	_config = config
	_session.base_state_changed.connect(_schedule_refresh)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102219")
	style.border_color = Color("6b7956")
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	_split_dialog = ConfirmationDialog.new()
	_split_dialog.title = "拆分物资"
	_split_dialog.ok_button_text = "拖动选定数量"
	_split_dialog.cancel_button_text = "取消"
	_split_quantity = SpinBox.new()
	_split_quantity.position = Vector2(24, 24)
	_split_quantity.custom_minimum_size = Vector2(260, 44)
	_split_quantity.min_value = 1
	_split_quantity.step = 1
	_split_dialog.add_child(_split_quantity)
	_split_dialog.confirmed.connect(_confirm_split)
	add_child(_split_dialog)


func open(station_id: StringName) -> void:
	_station = station_id
	_selection = {}
	visible = true
	refresh()


func _schedule_refresh() -> void:
	refresh.call_deferred()


func refresh() -> void:
	if _body == null:
		return
	_view = _session.base_snapshot(_actor)
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var header := HBoxContainer.new()
	_body.add_child(header)
	var title := _text("补给站" if _station == &"supply" else ("出发整备" if _station == &"expedition" else "仓库与行装"), 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_button(header, "关闭  Esc", func() -> void: close_requested.emit())
	_body.add_child(_text("货币 %d    携带 %.2f / %.0f kg    背包 %.2f / %.0f L    移动效率 %.0f%%" % [_view["currency"], _view["carried_weight_kg"], _config.hard_weight_limit_kg, _view["containers"]["backpack"]["volume_l"], _config.backpack_capacity_l, _view["movement_multiplier"] * 100.0], 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(row)
	if _view["phase"] != WildRunFlow.Phase.WILDERNESS:
		_add_grid_column(row, "warehouse", "永久仓库  12×10", 32)
	var bag_column: VBoxContainer = _add_grid_column(row, "backpack", "标准背包  8×6", 40)
	var equipment := HBoxContainer.new()
	equipment.add_theme_constant_override("separation", 16)
	bag_column.add_child(equipment)
	for slot: String in ["main_hand", "off_hand", "armor"]:
		var slot_column := VBoxContainer.new()
		equipment.add_child(slot_column)
		slot_column.add_child(_text({"main_hand": "主手", "off_hand": "副手", "armor": "护甲"}[slot], 14))
		_add_grid(slot_column, slot, 56)
	var details := VBoxContainer.new()
	details.custom_minimum_size.x = 300
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	if _station == &"supply":
		_build_shop(details)
	_selection_view = VBoxContainer.new()
	details.add_child(_selection_view)
	_build_selection(_selection_view)
	_status = _text(_notice, 15)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 30
	_body.add_child(_status)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	_body.add_child(footer)
	if _view["phase"] == WildRunFlow.Phase.BASE:
		_button(footer, "领取缺少的基础补给", _send.bind(&"supply.claim", {}))
		_button(footer, "开始出发整备", func() -> void: _send(&"expedition.prepare", {"seed": _seed_input.text.strip_edges()}))
		footer.add_child(_text("地图种子", 14))
		_seed_input = LineEdit.new()
		_seed_input.placeholder_text = "留空随机 · 可输入整数复现"
		_seed_input.custom_minimum_size.x = 280
		_seed_input.max_length = 19
		footer.add_child(_seed_input)
		if _view.get("pending_count",0) > 0:
			_button(_selection_view,"领取返航物资（%d 组）" % _view["pending_count"],_send.bind(&"pending.claim",{}))
	elif _view["phase"] == WildRunFlow.Phase.PREPARATION:
		_button(footer, "取消整备 · 恢复原行装", _send.bind(&"expedition.cancel", {}))
		_button(footer, "确认出发", _send.bind(&"expedition.commit", {}))
	else:
		if _view.get("survival_enabled",false): footer.add_child(_text("本局计时中；到期胜利，死亡或放弃会失去随身物资。",15))
		else: _button(footer, "结束探索 · 恢复行装", _send.bind(&"expedition.return_exploration" if _view.get("exploration_only", false) else &"expedition.return_placeholder", {}))
	if _view["phase"] == WildRunFlow.Phase.PREPARATION:
		footer.add_child(_text("地图种子 %s · 交易关闭" % _view.get("seed", ""), 14))


func _add_grid_column(parent: Control, id: String, title: String, pixels: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	column.add_child(_text(title, 18))
	_add_grid(column, id, pixels)
	var container: Dictionary = _view["containers"][id]
	column.add_child(_text("%.2f / %.0f L   ·   %.2f kg" % [container["volume_l"], container["capacity_l"], container["weight_kg"]], 14))
	return column


func _add_grid(parent: Control, id: String, pixels: int) -> void:
	var grid := WildInventoryGrid.new()
	grid.configure(_view["containers"][id], _catalog, func(payload: Dictionary) -> WildOperationResult: return _session.preview_transfer(_actor, payload), pixels)
	grid.item_selected.connect(_select_item)
	grid.split_requested.connect(_request_split)
	grid.transfer_requested.connect(func(payload: Dictionary) -> void: _send(&"inventory.transfer", payload))
	parent.add_child(grid)


func _build_shop(parent: Control) -> void:
	parent.add_child(_text("补给目录", 18))
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(280, 150)
	parent.add_child(list)
	for definition: WildItemDefinition in _catalog.definitions:
		if definition.purchasable:
			var index: int = list.add_item("%s   ·   %d" % [definition.display_name, definition.price])
			list.set_item_metadata(index, str(definition.item_id))
			if definition.item_id == _selected_definition:
				list.select(index)
	list.item_selected.connect(func(index: int) -> void:
		_selected_definition = StringName(str(list.get_item_metadata(index)))
		refresh.call_deferred()
	)
	var selected: WildItemDefinition = _catalog.find(_selected_definition)
	parent.add_child(_text("%s  %d×%d  %.2f kg / %.2f L" % [selected.display_name, selected.grid_size.x, selected.grid_size.y, selected.unit_weight_kg, selected.unit_volume_l], 14))
	var purchase := HBoxContainer.new()
	parent.add_child(purchase)
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = selected.max_stack
	_quantity.value = 1
	_quantity.step = 1
	_quantity.custom_minimum_size.x = 110
	purchase.add_child(_quantity)
	var buy := _button(purchase, "购买", func() -> void: _send(&"shop.buy", {"definition_id": str(_selected_definition), "quantity": int(_quantity.value)}))
	buy.disabled = _view["phase"] != WildRunFlow.Phase.BASE


func _build_selection(parent: Control) -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		parent.add_child(_text("点击物资查看详情。\n拖动到另一网格可转移，\n拖到同类物资可合并。", 16))
		return
	var item: Dictionary = entry["item"]
	var definition: WildItemDefinition = _catalog.find(StringName(item["item_id"]))
	parent.add_child(_text("%s × %d" % [definition.display_name, item["quantity"]], 20))
	if item.get("nutrition_multiplier",1) > 1 or item.get("shelf_life_multiplier",1) > 1: parent.add_child(_text("制作者加成：营养 ×%.2f，保质期 ×%.2f" % [item.get("nutrition_multiplier",1),item.get("shelf_life_multiplier",1)],14))
	parent.add_child(_text("单份 %.2f kg / %.2f L\n耐久 %.0f   水量 %.2f L%s" % [definition.unit_weight_kg, definition.unit_volume_l, item["durability"], item["water_l"], "\n基础补给 · 不可出售" if item["free_supply"] else ""], 14))
	var buttons := HBoxContainer.new()
	parent.add_child(buttons)
	_button(buttons, "旋转 R", _rotate_selection)
	if _view["phase"] != WildRunFlow.Phase.WILDERNESS:
		_button(buttons, "装入背包" if _selection["container"] == "warehouse" else "送回仓库", _transfer_selection)
	if _selection["container"] == "warehouse":
		var sell := _button(parent, "出售这组物资", func() -> void: _send(&"shop.sell", {"item_id": item["id"], "version": _view["containers"]["warehouse"]["version"], "quantity": item["quantity"]}))
		sell.disabled = item["free_supply"] or _view["phase"] != WildRunFlow.Phase.BASE
	if _view.get("survival_enabled",false):
		if definition.item_id in [&"bandage",&"herbal_medicine"]: _button(parent,"包扎 · 5 分钟" if definition.item_id == &"bandage" else "服用草药药剂 · 10 分钟",_send.bind(&"survival.start",{"action":"treat","item_id":item["id"]}))
		if definition.category == &"food": _button(parent,"进食 1 份 · 1 分钟，10 分钟消化",_send.bind(&"survival.start",{"action":"eat","item_id":item["id"]}))
		if definition.item_id == &"bottle":
			for litres: float in [0.25,0.5]: _button(parent,"饮水 %.2f L · 1 分钟" % litres,_send.bind(&"survival.start",{"action":"drink","item_id":item["id"],"litres":litres}))


func _select_item(container_id: String, instance_id: String) -> void:
	_selection = {"container": container_id, "item_id": instance_id}
	# 只更新详情，不销毁开始拖拽的网格控件。
	for child: Node in _selection_view.get_children():
		_selection_view.remove_child(child)
		child.queue_free()
	_build_selection(_selection_view)


func _selected_entry() -> Dictionary:
	if _selection.is_empty():
		return {}
	for entry: Dictionary in _view["containers"][_selection["container"]]["entries"]:
		if entry["item"]["id"] == _selection["item_id"]:
			return entry
	_selection = {}
	return {}


func _transfer_selection() -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		return
	var source: String = _selection["container"]
	var target: String = "backpack" if source == "warehouse" else "warehouse"
	_send(&"inventory.transfer", {"source": source, "target": target, "item_id": _selection["item_id"], "source_version": _view["containers"][source]["version"], "target_version": _view["containers"][target]["version"], "auto": true})


func _rotate_selection() -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		return
	var source: String = _selection["container"]
	_send(&"inventory.transfer", {"source": source, "target": source, "item_id": _selection["item_id"], "source_version": _view["containers"][source]["version"], "target_version": _view["containers"][source]["version"], "x": entry["position"][0], "y": entry["position"][1], "rotated": not entry["rotated"]})


func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"rotate_item"):
		return
	if get_viewport().gui_is_dragging():
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.has("rotated"):
			data["rotated"] = not data["rotated"]
	else:
		_rotate_selection()
	get_viewport().set_input_as_handled()


func _request_split(grid: WildInventoryGrid, id: String) -> void:
	_split_grid = grid
	_split_id = id
	_split_quantity.max_value = int(grid.entry_for(id)["item"]["quantity"]) - 1
	_split_quantity.value = 1
	_split_dialog.popup_centered(Vector2i(330, 140))


func _confirm_split() -> void:
	if is_instance_valid(_split_grid):
		_split_grid.begin_partial_drag.call_deferred(_split_id, int(_split_quantity.value))


func _send(operation: StringName, payload: Dictionary = {}) -> void:
	var result: WildOperationResult = _session.submit(WildGameCommand.new(_actor, operation, payload))
	_notice = "操作完成，行装已保存。" if result.successful else WildErrorMessages.describe(result.code)
	if result.successful and operation == &"survival.start": survival_action_started.emit()
	if _status != null:
		_status.text = _notice
	refresh.call_deferred()


func _text(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("dddbbc"))
	return label


func _button(parent: Control, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 36
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button
