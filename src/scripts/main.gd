extends Control

const NODE_RADIUS := 16.0
const NODE_CARD_SIZE := Vector2(120.0, 52.0)
const MAP_MARGIN_LEFT := 360.0
const MAP_MARGIN_RIGHT := 80.0
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

var custom_font: Font = null

var opt_force_shop: bool = false
var opt_force_camp: bool = false
var opt_floors: int = 10
var opt_columns: int = 7
var opt_seed: String = ""
var current_seed: int = 0

func _ready() -> void:
	evaluator = MAP_EVALUATOR_SCRIPT.new()
	mouse_filter = Control.MOUSE_FILTER_PASS
	rng.randomize()
	randomize()
	regenerate_button.pressed.connect(_on_regenerate_pressed)
	
	# 嘗試載入中文字型以解決 HTML5 亂碼問題
	if ResourceLoader.exists("res://NotoSansTC-Regular.ttf"):
		custom_font = load("res://NotoSansTC-Regular.ttf")
		var app_theme = Theme.new()
		app_theme.default_font = custom_font
		self.theme = app_theme
	else:
		custom_font = ThemeDB.fallback_font
		
	_build_custom_ui()
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

		var font: Font = custom_font if custom_font else ThemeDB.fallback_font
		var title: String = _node_title(int(node_id), node["type"])
		var subtitle: String = _node_subtitle(node["type"])
		draw_string(font, card_rect.position + Vector2(8.0, 19.0), title, HORIZONTAL_ALIGNMENT_LEFT, card_rect.size.x - 16.0, 14, Color.BLACK)
		draw_string(font, card_rect.position + Vector2(8.0, 38.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, card_rect.size.x - 16.0, 12, Color(0.08, 0.08, 0.08, 0.85))

func _build_custom_ui() -> void:
	var ui_canvas = CanvasLayer.new()
	add_child(ui_canvas)
	
	var panel = PanelContainer.new()
	if self.theme:
		panel.theme = self.theme
		
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	
	# 將 UI 放在左上角
	panel.set_anchors_preset(PRESET_TOP_LEFT)
	panel.position = Vector2(10, 80)
	ui_canvas.add_child(panel)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	var algo_label = Label.new()
	algo_label.text = "切換演算法："
	vbox.add_child(algo_label)
	
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)
	
	for algo in ["dag", "bsp", "forest"]:
		var btn = Button.new()
		btn.text = algo.to_upper()
		btn.pressed.connect(func(): _switch_algorithm(algo))
		hbox.add_child(btn)
		
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var opt_label = Label.new()
	opt_label.text = "生成選項："
	vbox.add_child(opt_label)
	
	var chk_shop = CheckBox.new()
	chk_shop.text = "必定會經過一次Shop (中間層)"
	chk_shop.toggled.connect(func(t): opt_force_shop = t; _generate_new_map())
	vbox.add_child(chk_shop)
	
	var chk_camp = CheckBox.new()
	chk_camp.text = "Boss前固定為Camp"
	chk_camp.toggled.connect(func(t): opt_force_camp = t; _generate_new_map())
	vbox.add_child(chk_camp)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)
	
	var param_label = Label.new()
	param_label.text = "地圖參數調整："
	vbox.add_child(param_label)
	
	var floors_hbox = HBoxContainer.new()
	var floors_label = Label.new()
	floors_label.text = "層數 (Floors): 10"
	floors_label.custom_minimum_size.x = 140
	floors_hbox.add_child(floors_label)
	
	var floors_slider = HSlider.new()
	floors_slider.min_value = 5
	floors_slider.max_value = 20
	floors_slider.value = 10
	floors_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floors_slider.value_changed.connect(func(v): opt_floors = int(v); floors_label.text = "層數 (Floors): %d" % opt_floors; _generate_new_map())
	floors_hbox.add_child(floors_slider)
	vbox.add_child(floors_hbox)
	
	var cols_hbox = HBoxContainer.new()
	var cols_label = Label.new()
	cols_label.text = "寬度 (Columns): 7"
	cols_label.custom_minimum_size.x = 140
	cols_hbox.add_child(cols_label)
	
	var cols_slider = HSlider.new()
	cols_slider.min_value = 4
	cols_slider.max_value = 15
	cols_slider.value = 7
	cols_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols_slider.value_changed.connect(func(v): opt_columns = int(v); cols_label.text = "寬度 (Columns): %d" % opt_columns; _generate_new_map())
	cols_hbox.add_child(cols_slider)
	vbox.add_child(cols_hbox)

	var sep3 = HSeparator.new()
	vbox.add_child(sep3)
	
	var seed_label = Label.new()
	seed_label.text = "種子碼 (Seed)："
	vbox.add_child(seed_label)
	
	var seed_hbox = HBoxContainer.new()
	var seed_input = LineEdit.new()
	seed_input.placeholder_text = "留空為隨機"
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_input.text_changed.connect(func(txt): opt_seed = txt)
	seed_input.text_submitted.connect(func(txt): opt_seed = txt; _generate_new_map())
	seed_hbox.add_child(seed_input)
	
	var seed_btn = Button.new()
	seed_btn.text = "生成"
	seed_btn.pressed.connect(func(): _generate_new_map())
	seed_hbox.add_child(seed_btn)
	
	vbox.add_child(seed_hbox)

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
	# 決定這次要使用的種子碼
	if opt_seed.strip_edges() == "":
		randomize() # 根據時間重置全域亂數狀態
		current_seed = randi()
	else:
		if opt_seed.is_valid_int():
			current_seed = opt_seed.to_int()
		else:
			current_seed = opt_seed.hash()
			
	seed(current_seed)        # 固定全域亂數 (用於各個地圖生成演算法)
	rng.seed = current_seed   # 固定畫面的 RNG (用於畫面節點的視覺偏移)

	generator = factory.create_generator(current_algorithm)
	generator.force_shop = opt_force_shop
	generator.force_camp_before_boss = opt_force_camp
	generator.floors = opt_floors
	generator.columns = opt_columns

	# 先嘗試由目前 generator 生成地圖，驗證回傳格式是否正確
	var gen_map = generator.generate_map()
	if typeof(gen_map) != TYPE_DICTIONARY or not gen_map.has("floors") or not gen_map.has("nodes"):
		push_error("Generator %s returned invalid map data" % generator.get_algorithm_name())
		# 使用預設 DAG 作為回退
		var fallback_factory = MapGeneratorFactory.new()
		generator = fallback_factory.create_generator(MapGeneratorFactory.ALGORITHM_DAG)
		generator.force_shop = opt_force_shop
		generator.force_camp_before_boss = opt_force_camp
		generator.floors = opt_floors
		generator.columns = opt_columns
		gen_map = generator.generate_map()
		if typeof(gen_map) != TYPE_DICTIONARY or not gen_map.has("floors") or not gen_map.has("nodes"):
			push_error("Fallback generator also failed; aborting map generation")
			status_label.text = "地圖生成失敗，請查看輸出日誌。"
			map_data = {}
			queue_redraw()
			return

	map_data = gen_map
	_compute_node_positions()
	current_node_id = -1
	hovered_node_id = -1
	walked_nodes.clear()
	walked_edges.clear()
	# 安全地設定第一層可選節點
	if map_data.has("floors") and map_data["floors"].size() > 0:
		selectable_nodes = map_data["floors"][0].duplicate()
	else:
		selectable_nodes = []

	# 驗證與評估，若失敗則顯示錯誤但不要崩潰
	var verification: Dictionary = {}
	var verify_text: String = "FAIL"
	# 只有在 floors 與 nodes 結構完整且首尾層都有節點時才做更深入驗證
	if map_data.has("floors") and map_data.has("nodes") and map_data["floors"].size() > 0 and map_data["nodes"].size() > 0 and map_data["floors"][0].size() > 0 and map_data["floors"][map_data["floors"].size() - 1].size() > 0:
		# Safe to call verify/evaluate
		verification = generator.verify_connectivity(map_data)
		verify_text = "PASS" if bool(verification.get("is_valid", false)) else "FAIL"
		var evaluation: Dictionary = evaluator.evaluate_map(map_data, generator)
		score_line_text = _build_evaluation_text(verify_text, evaluation, current_seed)
	else:
		score_line_text = "[Invalid or incomplete map data]"

	_set_action_text("點選第一層節點開始 | R 重生 | 1-3 切換演算法")
	queue_redraw()

func _compute_node_positions() -> void:
	node_positions.clear()
	var floors_to_nodes: Array = map_data["floors"]
	var nodes: Dictionary = map_data["nodes"]

	var usable_w: float = max(size.x - MAP_MARGIN_LEFT - MAP_MARGIN_RIGHT, 100.0)
	var usable_h: float = max(size.y - MAP_MARGIN_Y * 2.0, 100.0)

	for floor_idx in range(floors_to_nodes.size()):
		var base_y: float = MAP_MARGIN_Y + usable_h * (1.0 - float(floor_idx) / float(max(floors_to_nodes.size() - 1, 1)))
		for node_id in floors_to_nodes[floor_idx]:
			var col: int = nodes[node_id]["column"]
			var x: float = MAP_MARGIN_LEFT + usable_w * (float(col) / float(max(generator.columns - 1, 1)))
			var y: float = base_y
			
			# 固定 Boss 置中，且第一層與 Boss 層取消隨機偏移
			if nodes[node_id]["type"] == "boss":
				x = MAP_MARGIN_LEFT + usable_w * 0.5
			elif floor_idx != 0:
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
	
	# 按 1-3 切換演算法
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_switch_algorithm("dag")
			KEY_2:
				_switch_algorithm("bsp")
			KEY_3:
				_switch_algorithm("forest")

func _switch_algorithm(algorithm: String) -> void:
	current_algorithm = algorithm
	_set_action_text("已切換到演算法: %s" % algorithm.to_upper())
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

func _build_evaluation_text(verify_text: String, evaluation: Dictionary, used_seed: int) -> String:
	var m: Dictionary = evaluation["metrics"]
	var algo_name: String = generator.get_algorithm_name()
	return "%s %s | Seed: %d | Score %d/100 | Quality %d Branch %d Diversity %d PathQty %d Variety %d Pace %d" % [
		algo_name,
		verify_text,
		used_seed,
		evaluation["total_score"],
		m["choice_quality"],
		m["branch_options"],
		m["path_diversity"],
		m.get("path_quality", 0),
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
