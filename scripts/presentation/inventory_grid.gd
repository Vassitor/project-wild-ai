class_name WildInventoryGrid
extends Control
## 网格只绘制快照 / 提交拖放意图。预览由事务服务执行同一领域规则。

signal item_selected(container_id: String, instance_id: String)
signal split_requested(grid: WildInventoryGrid, instance_id: String)
signal transfer_requested(payload: Dictionary)

var container_id: String
var cell_size: int = 32
var _view: Dictionary = {}
var _catalog: WildItemCatalog
var _preview: Callable
var _selected_id: String = ""
var _hover_cell := Vector2i(-1, -1)
var _hover_size := Vector2i.ONE
var _hover_valid: bool = false


func configure(view: Dictionary, catalog: WildItemCatalog, preview: Callable, pixels_per_cell: int = 32) -> void:
	_view = view.duplicate(true)
	container_id = view["id"]
	_catalog = catalog
	_preview = preview
	cell_size = pixels_per_cell
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(int(view["grid"][0]), int(view["grid"][1])) * cell_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func entry_for(id: String) -> Dictionary:
	for entry: Dictionary in _view.get("entries", []):
		if entry["item"]["id"] == id:
			return entry
	return {}


func _dimensions(item: Dictionary, rotated: bool) -> Vector2i:
	if _view.get("equipment_slot", false):
		return Vector2i.ONE
	var definition: WildItemDefinition = _catalog.find(StringName(item["item_id"]))
	return Vector2i(definition.grid_size.y, definition.grid_size.x) if rotated else definition.grid_size


func _entry_at(at_position: Vector2) -> Dictionary:
	var cell := Vector2i(floori(at_position.x / cell_size), floori(at_position.y / cell_size))
	for entry: Dictionary in _view.get("entries", []):
		var cell_origin := Vector2i(int(entry["position"][0]), int(entry["position"][1]))
		if Rect2i(cell_origin, _dimensions(entry["item"], entry["rotated"])).has_point(cell):
			return entry
	return {}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var entry: Dictionary = _entry_at(event.position)
		if not entry.is_empty():
			_selected_id = entry["item"]["id"]
			item_selected.emit(container_id, _selected_id)
			if event.shift_pressed and int(entry["item"]["quantity"]) > 1:
				split_requested.emit(self, _selected_id)
				accept_event()
			queue_redraw()


func _get_drag_data(at_position: Vector2) -> Variant:
	var entry: Dictionary = _entry_at(at_position)
	if entry.is_empty():
		return null
	var data: Dictionary = _drag_data(entry, int(entry["item"]["quantity"]))
	set_drag_preview(_drag_preview(data))
	return data


func begin_partial_drag(id: String, amount: int) -> void:
	var entry: Dictionary = entry_for(id)
	if entry.is_empty():
		return
	var data: Dictionary = _drag_data(entry, amount)
	force_drag(data, _drag_preview(data))


func _drag_data(entry: Dictionary, amount: int) -> Dictionary:
	return {"source": container_id, "item_id": entry["item"]["id"], "definition_id": entry["item"]["item_id"], "quantity": amount, "rotated": entry["rotated"], "source_version": _view["version"]}


func _drag_preview(data: Dictionary) -> Control:
	var preview := WildInventoryDragPreview.new()
	preview.configure(data, _catalog)
	return preview


func _payload(at_position: Vector2, data: Dictionary) -> Dictionary:
	var payload: Dictionary = data.duplicate(true)
	payload["target"] = container_id
	payload["target_version"] = _view["version"]
	payload["x"] = floori(at_position.x / cell_size)
	payload["y"] = floori(at_position.y / cell_size)
	return payload


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.has("source") or not data.has("definition_id"):
		return false
	var result: WildOperationResult = _preview.call(_payload(at_position, data))
	_hover_cell = Vector2i(floori(at_position.x / cell_size), floori(at_position.y / cell_size))
	_hover_size = _dimensions({"item_id": data["definition_id"]}, data["rotated"])
	_hover_valid = result.successful
	queue_redraw()
	return result.successful


func _drop_data(at_position: Vector2, data: Variant) -> void:
	transfer_requested.emit(_payload(at_position, data))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_hover_cell = Vector2i(-1, -1)
		queue_redraw()


func _draw() -> void:
	if _view.is_empty():
		return
	var columns: int = int(_view["grid"][0])
	var rows: int = int(_view["grid"][1])
	for y: int in range(rows):
		for x: int in range(columns):
			var rectangle := Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
			draw_rect(rectangle, Color("20382d"))
			draw_rect(rectangle, Color("3f5545"), false)
	var font: Font = get_theme_font("font", "Label")
	for entry: Dictionary in _view["entries"]:
		var item: Dictionary = entry["item"]
		var definition: WildItemDefinition = _catalog.find(StringName(item["item_id"]))
		var pixel_origin := Vector2(int(entry["position"][0]), int(entry["position"][1])) * cell_size
		var dimensions := Vector2(_dimensions(item, entry["rotated"])) * cell_size
		var rectangle := Rect2(pixel_origin + Vector2(2, 2), dimensions - Vector2(4, 4))
		draw_rect(rectangle, definition.color.darkened(0.4))
		draw_rect(rectangle, Color("f0d290") if item["id"] == _selected_id else definition.color, false, 2)
		if not WildArtLibrary.draw_icon(self, definition.item_id, rectangle, entry["rotated"]):
			draw_string(font, pixel_origin + Vector2(6, 22), definition.display_name.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("ebdfba"))
		if int(item["quantity"]) > 1:
			draw_string(font, pixel_origin + dimensions - Vector2(16, 6), str(int(item["quantity"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ffffff"))
		if item["free_supply"]:
			draw_rect(Rect2(pixel_origin + Vector2(5, 5), Vector2(4, 4)), Color("ead093"))
	if _hover_cell.x >= 0 and get_viewport().gui_is_dragging():
		draw_rect(Rect2(Vector2(_hover_cell) * cell_size, Vector2(_hover_size) * cell_size), Color(0.45, 0.8, 0.48, 0.35) if _hover_valid else Color(0.85, 0.32, 0.25, 0.35))
