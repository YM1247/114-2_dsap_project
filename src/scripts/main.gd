extends Control

const NODE_RADIUS := 16.0
const NODE_CARD_SIZE := Vector2(120.0, 52.0)
const MAP_MARGIN_X := 80.0
const MAP_MARGIN_Y := 90.0
const MAP_EVALUATOR_SCRIPT = preload("res://src/scripts/map_evaluator.gd")

@onready var status_label: Label = $StatusLabel
@onready var regenerate_button: Button = $RegenerateButton

var factory: MapGeneratorFactory = MapGeneratorFactory.new()
var generator: MapGeneratorBase = null
var evaluator = null
var map_data: Dictionary = {}
var node_positions: Dictionary = {}
var current_node_id: int = -1
var selectable_nodes: Array = []
var current_algorithm: String = "dag"
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var hovered_node_id: int = -1
var walked_nodes: Dictionary = {}
var walked_edges: Dictionary = {}
var score_line_text: String = ""

func _ready() -> void:
	generator = factory.create_generator(current_algorithm)
	evaluator = MAP_EVALUATOR_SCRIPT.new()
	mouse_filter = Control.MOUSE_FILTER_PASS
	rng.randomize()
	randomize()
	regenerate_button.pressed.connect(_on_regenerate_pressed)
	_generate_new_map()

func _draw() -> void:
	if map_data.is_empty():
		return

	var nodes: Dictionary = map_data["nodes"]
	var current_floor: int = -1
	if current_node_id != -1:
		current_floor = int(nodes[current_node_id]["floor"])

	for node_id in nodes.keys():
		for next_id in nodes[node_id]["next"]:
			var color: Color = Color(0.35, 0.35, 0.35, 1.0)
			var edge_key: String = _edge_key(int(node_id), int(next_id))
			var from_floor: int = int(nodes[node_id]["floor"])
			var is_abandoned_past_edge: bool = current_floor > 0 and from_floor < current_floor and not walked_edges.has(edge_key)
			if walked_edges.has(edge_key):
				color = Color(0.2, 1.0, 0.6, 1.0)
			elif current_node_id == node_id and selectable_nodes.has(next_id):
				color = Color(0.95, 0.9, 0.3, 1.0)
			elif is_abandoned_past_edge:
				color = Color(0.22, 0.22, 0.22, 0.5)
			draw_line(node_positions[node_id], node_positions[next_id], color, 2.0)

	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id]
		var base_color: Color = _type_color(node["type"])
		var card_center: Vector2 = node_positions[node_id]
		var card_rect := Rect2(card_center - NODE_CARD_SIZE * 0.5, NODE_CARD_SIZE)
		var node_floor: int = int(node["floor"])
		var is_abandoned_node: bool = current_floor >= 0 and node_floor <= current_floor and not walked_nodes.has(node_id)

		if is_abandoned_node:
			base_color = base_color.darkened(0.72)
			base_color.a = 0.6

		if walked_nodes.has(node_id):
			base_color = base_color.lightened(0.25)

		var draw_rect_area: Rect2 = card_rect
		if node_id == current_node_id:
			base_color = Color(0.2, 0.9, 1.0, 1.0)
			draw_rect_area = draw_rect_area.grow(2.0)
		if node_id == hovered_node_id:
			draw_rect(card_rect.grow(5.0), Color(1.0, 1.0, 0.6, 0.18), true)

		draw_rect(draw_rect_area, base_color, true)
		var border_width: float = 2.0
		var border_color: Color = Color.BLACK
		if selectable_nodes.has(node_id):
			border_width = 4.0
			border_color = Color(1.0, 0.95, 0.45, 1.0)
			draw_rect(draw_rect_area.grow(4.0), border_color, false, border_width)
		draw_rect(draw_rect_area, border_color if not selectable_nodes.has(node_id) else Color.BLACK, false, 2.0)

		var font: Font = ThemeDB.fallback_font
		var title: String = _node_title(int(node_id), node["type"])
		var subtitle: String = _node_subtitle(node["type"])
		draw_string(font, card_rect.position + Vector2(8.0, 19.0), title, HORIZONTAL_ALIGNMENT_LEFT, card_rect.size.x - 16.0, 14, Color.BLACK)
		draw_string(font, card_rect.position + Vector2(8.0, 38.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, card_rect.size.x - 16.0, 12, Color(0.08, 0.08, 0.08, 0.85))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var new_hovered_id: int = _find_clicked_node(event.position)
		if new_hovered_id != hovered_node_id:
			hovered_node_id = new_hovered_id
			queue_redraw()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked_id: int = _find_clicked_node(event.position)
		if clicked_id == -1:
			return
		_try_select_node(clicked_id)
		accept_event()

func _generate_new_map() -> void:
	map_data = generator.generate_map()
	_compute_node_positions()
	current_node_id = -1
	hovered_node_id = -1
	walked_nodes.clear()
	walked_edges.clear()
	selectable_nodes = map_data["floors"][0].duplicate()

	var verification: Dictionary = generator.verify_connectivity(map_data)
	var verify_text: String = "PASS" if bool(verification["is_valid"]) else "FAIL"
	var evaluation: Dictionary = evaluator.evaluate_map(map_data, generator)
	score_line_text = _build_evaluation_text(verify_text, evaluation)
	_set_action_text("點選第一層節點開始 | R 重生 | 1-4 切換演算法")
	queue_redraw()

func _compute_node_positions() -> void:
	node_positions.clear()
	var floors_to_nodes: Array = map_data["floors"]
	var nodes: Dictionary = map_data["nodes"]

	var usable_w: float = max(size.x - MAP_MARGIN_X * 2.0, 100.0)
	var usable_h: float = max(size.y - MAP_MARGIN_Y * 2.0, 100.0)

	for floor_idx in range(floors_to_nodes.size()):
		var base_y: float = MAP_MARGIN_Y + usable_h * (1.0 - float(floor_idx) / float(max(floors_to_nodes.size() - 1, 1)))
		for node_id in floors_to_nodes[floor_idx]:
			var col: int = nodes[node_id]["column"]
			var x: float = MAP_MARGIN_X + usable_w * (float(col) / float(max(generator.columns - 1, 1)))
			var y: float = base_y
			x += rng.randf_range(-14.0, 14.0)
			y += rng.randf_range(-3.0, 3.0)
			node_positions[node_id] = Vector2(x, y)

func _find_clicked_node(mouse_pos: Vector2) -> int:
	for node_id in node_positions.keys():
		var center: Vector2 = node_positions[node_id]
		var hit_rect := Rect2(center - NODE_CARD_SIZE * 0.5, NODE_CARD_SIZE).grow(3.0)
		if hit_rect.has_point(mouse_pos):
			return node_id
	return -1

func _try_select_node(node_id: int) -> void:
	if current_node_id == -1:
		if selectable_nodes.has(node_id):
			current_node_id = node_id
			walked_nodes[node_id] = true
			selectable_nodes = map_data["nodes"][node_id]["next"].duplicate()
			_set_action_text("已選起點，請選擇下一層可達節點。")
			queue_redraw()
		else:
			_set_action_text("無效操作：請從第一層可選節點開始。")
		return

	if not selectable_nodes.has(node_id):
		_set_action_text("無效操作：只能點選與目前節點相連的下一層。")
		return

	walked_edges[_edge_key(current_node_id, node_id)] = true
	current_node_id = node_id
	walked_nodes[node_id] = true
	selectable_nodes = map_data["nodes"][node_id]["next"].duplicate()
	if selectable_nodes.is_empty():
		_set_action_text("到達 Boss，流程驗證完成！按 R 或按鈕可重生。")
	else:
		_set_action_text("移動成功：請選擇下一層可達節點。")
	queue_redraw()

func _on_regenerate_pressed() -> void:
	_generate_new_map()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_generate_new_map()
	
	# 按 1-4 切換演算法
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_switch_algorithm("dag")
			KEY_2:
				_switch_algorithm("bsp")
			KEY_3:
				_switch_algorithm("forest")
			KEY_4:
				_switch_algorithm("csp")

func _switch_algorithm(algorithm: String) -> void:
	var factory = MapGeneratorFactory.new()
	generator = factory.create_generator(algorithm)
	_set_action_text("已切換到演算法: %s" % generator.get_algorithm_name())
	_generate_new_map()

func _type_color(node_type: String) -> Color:
	match node_type:
		"combat":
			return Color(0.75, 0.75, 0.75)
		"elite":
			return Color(0.95, 0.4, 0.4)
		"event":
			return Color(0.45, 0.7, 1.0)
		"shop":
			return Color(0.8, 0.55, 0.2)
		"camp":
			return Color(0.4, 0.85, 0.45)
		"boss":
			return Color(0.85, 0.2, 0.85)
		_:
			return Color.WHITE

func _edge_key(from_id: int, to_id: int) -> String:
	return str(from_id) + "->" + str(to_id)

func _build_evaluation_text(verify_text: String, evaluation: Dictionary) -> String:
	var m: Dictionary = evaluation["metrics"]
	var algo_name: String = generator.get_algorithm_name()
	return "%s %s | Score %d/100 | Choice %d Branch %d Path %d Variety %d Pace %d" % [
		algo_name,
		verify_text,
		evaluation["total_score"],
		m["choice_quality"],
		m["branch_options"],
		m["path_diversity"],
		m["encounter_variety"],
		m["pacing_balance"]
	]

func _set_action_text(message: String) -> void:
	status_label.text = score_line_text + "\n" + message

func _node_title(node_id: int, node_type: String) -> String:
	if node_type == "boss":
		return "Boss"
	return "Node %d" % node_id

func _node_subtitle(node_type: String) -> String:
	match node_type:
		"combat":
			return "Combat"
		"elite":
			return "Elite"
		"event":
			return "Event"
		"shop":
			return "Shop"
		"camp":
			return "Camp"
		"boss":
			return "Final Battle"
		_:
			return "Unknown"

