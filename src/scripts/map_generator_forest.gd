extends MapGeneratorBase
class_name MapGeneratorForest

## 隨機森林演算法實現（改進版）
## 特點：生成多條具有差異的獨立路徑（樹），並通過優化分支和跨路徑連接提升多樣性
## 優勢：結構化、易理解、具有戰略選擇價值、路徑間風險/回報差異明顯

var num_main_paths: int = 3      # 主要路徑數量
var path_drift: int = 1          # 每層路徑水平漂移的最大值
var branch_node_ratio: float = 0.4   # 每層中作為分支點的節點比例
var cross_path_connection_ratio: float = 0.2  # 跨路徑連接的機率

# 路徑風格定義
enum PathStyle { STRAIGHT, WINDING, DIVERGING }
var path_styles: Array = []      # 每條路徑的風格

func generate_map() -> Dictionary:
	var nodes: Dictionary = {}
	var floors_to_nodes: Array = []
	var next_node_id: int = 0
	path_styles.clear()

	# 初始化樓層
	for i in range(floors):
		floors_to_nodes.append([])

	var used_cols: Dictionary = {} # Key: floor, Value: Array of columns
	var path_node_ids: Array = []  # 追蹤每條路徑的節點 ID

	# Step 1: 分配路徑風格並生成主要路徑（樹幹）
	var start_cols: Array = _get_evenly_spaced_columns(num_main_paths)
	_assign_path_styles(num_main_paths)
	
	for path_idx in range(start_cols.size()):
		var start_col: int = start_cols[path_idx]
		var current_col: int = start_col
		var path_nodes: Array = []
		var style: int = path_styles[path_idx]

		for floor in range(floors - 1): # 不包含 Boss 層
			# 避免在同一層的同一列上重疊
			var attempts = 0
			while used_cols.get(floor, []).has(current_col) and attempts < columns:
				current_col = (current_col + 1) % columns
				attempts += 1
			
			if not used_cols.has(floor):
				used_cols[floor] = []
			used_cols[floor].append(current_col)

			var node: Dictionary = {
				"id": next_node_id,
				"floor": floor,
				"column": current_col,
				"type": NODE_COMBAT,
				"next": [],
				"prev": [],
				"path_id": path_idx,
				"is_branch_point": false
			}
			nodes[next_node_id] = node
			floors_to_nodes[floor].append(next_node_id)
			path_nodes.append(next_node_id)
			next_node_id += 1

			# 根據路徑風格計算下一層的位置
			var drift = _calculate_drift(style, floor)
			current_col = clampi(current_col + drift, 0, columns - 1)

		path_node_ids.append(path_nodes)

	# Step 2: 添加分支節點和額外節點增加選擇多樣性
	next_node_id = _add_branch_and_extra_nodes(nodes, floors_to_nodes, used_cols, next_node_id, path_node_ids)

	# Step 3: 添加 Boss 節點
	var boss_floor_idx = floors - 1
	var boss_node_id = next_node_id
	next_node_id += 1
	var boss_node: Dictionary = {
		"id": boss_node_id,
		"floor": boss_floor_idx,
		"column": int(columns / 2),
		"type": NODE_BOSS,
		"next": [],
		"prev": [],
		"path_id": -1
	}
	nodes[boss_node_id] = boss_node
	floors_to_nodes[boss_floor_idx].append(boss_node_id)

	# Step 4: 連接所有樓層（含跨路徑連接）
	_connect_floors_enhanced(nodes, floors_to_nodes, path_node_ids)

	# Step 5: 分配節點類型
	_assign_node_types(nodes, floors_to_nodes)

	return {
		"nodes": nodes,
		"floors": floors_to_nodes,
		"algorithm": "forest"
	}

func verify_connectivity(map_data: Dictionary) -> Dictionary:
	return _verify_connectivity_impl(map_data)

func get_algorithm_name() -> String:
	return "Random Forest"

func get_algorithm_description() -> String:
	return "Generates distinct paths and connects them"

## ============== Forest 特定方法 ==============

func _assign_path_styles(count: int) -> void:
	"""為每條路徑分配風格，確保多樣性"""
	var available_styles = [PathStyle.STRAIGHT, PathStyle.WINDING, PathStyle.DIVERGING]
	for i in range(count):
		var style = available_styles[i % available_styles.size()]
		path_styles.append(style)
	# 隨機打亂確保風格分布多樣
	path_styles.shuffle()

func _calculate_drift(style: int, floor: int) -> int:
	"""根據路徑風格計算漂移量，提升每條路徑的特性"""
	match style:
		PathStyle.STRAIGHT:
			# 直線路徑：最小漂移
			return randi_range(-1, 1)
		PathStyle.WINDING:
			# 蛇形路徑：中等漂移
			return randi_range(-path_drift, path_drift)
		PathStyle.DIVERGING:
			# 發散路徑：向外擴展
			var base_drift = randi_range(0, path_drift + 1)
			return base_drift if randf() > 0.5 else -base_drift
		_:
			return randi_range(-path_drift, path_drift)

func _add_branch_and_extra_nodes(nodes: Dictionary, floors_to_nodes: Array, used_cols: Dictionary, next_node_id: int, path_node_ids: Array) -> int:
	"""添加分支節點和額外節點，提升選擇多樣性"""
	for floor in range(1, floors - 2): # 不動第一層和 Boss 前一層
		# 基於分支比例添加新的分支點
		var floor_size = floors_to_nodes[floor].size()
		var branch_count = maxi(1, int(floor_size * branch_node_ratio))
		
		for _i in range(branch_count):
			var available_cols: Array = []
			var floor_used_cols = used_cols.get(floor, [])
			
			for c in range(columns):
				if not floor_used_cols.has(c):
					available_cols.append(c)
			
			if not available_cols.is_empty():
				var col = available_cols[randi() % available_cols.size()]
				used_cols[floor].append(col)
				
				var node: Dictionary = {
					"id": next_node_id,
					"floor": floor,
					"column": col,
					"type": NODE_COMBAT,
					"next": [],
					"prev": [],
					"path_id": -1,  # 額外節點不屬於主路徑
					"is_branch_point": true
				}
				nodes[next_node_id] = node
				floors_to_nodes[floor].append(next_node_id)
				next_node_id += 1
	
	return next_node_id

func _connect_floors_enhanced(nodes: Dictionary, floors_to_nodes: Array, path_node_ids: Array) -> void:
	"""增強連接方式：優化主路徑連接 + 添加跨路徑連接"""
	for floor in range(floors_to_nodes.size() - 1):
		var current: Array = floors_to_nodes[floor]
		var nxt: Array = floors_to_nodes[floor + 1]
		var edges_this_band: Array = []

		if current.is_empty() or nxt.is_empty():
			continue

		# 第一步：主路徑內的連接
		for node_id in current:
			var node = nodes[node_id]
			var is_main_path = node.get("path_id", -1) >= 0
			var desired_links = 1
			
			if node.get("is_branch_point", false):
				desired_links = randi_range(2, max_links_per_node)
			elif floor == floors_to_nodes.size() - 2:
				desired_links = 1
			else:
				desired_links = randi_range(1, max_links_per_node)
			
			var sorted_candidates: Array = _sorted_candidates_by_distance(nodes, nxt, node_id)
			var links_added: int = 0
			
			for target_id in sorted_candidates:
				if links_added >= desired_links: 
					break
				if _edge_exists(nodes, node_id, target_id): 
					continue
				if _would_cross_existing(nodes, node_id, target_id, edges_this_band): 
					continue
				
				_add_edge(nodes, node_id, target_id)
				edges_this_band.append([node_id, target_id])
				links_added += 1
			
			# 回退：至少連接一個目標
			if links_added == 0 and not sorted_candidates.is_empty():
				var fallback_id: int = sorted_candidates[0]
				if not _edge_exists(nodes, node_id, fallback_id):
					_add_edge(nodes, node_id, fallback_id)
					edges_this_band.append([node_id, fallback_id])
		
		# 第二步：確保所有目標都有來源
		for target_id in nxt:
			if nodes[target_id]["prev"].is_empty():
				var source_id: int = _closest_source(nodes, current, target_id)
				if source_id != -1 and not _edge_exists(nodes, source_id, target_id):
					_add_edge(nodes, source_id, target_id)
					edges_this_band.append([source_id, target_id])
		
		# 第三步：添加跨路徑連接增加多樣性
		_add_cross_path_connections(nodes, current, nxt, edges_this_band)

func _assign_node_types(nodes: Dictionary, floors_to_nodes: Array) -> void:
	for floor in range(floors_to_nodes.size() - 1):
		for node_id in floors_to_nodes[floor]:
			if floor == 0:
				nodes[node_id]["type"] = NODE_COMBAT
				continue

			if force_camp_before_boss and floor == floors_to_nodes.size() - 2:
				nodes[node_id]["type"] = NODE_CAMP
				continue

			if force_shop and floor == int(floors / 2):
				nodes[node_id]["type"] = NODE_SHOP
				continue

			var valid_types: Array = [NODE_COMBAT, NODE_EVENT, NODE_ELITE, NODE_SHOP, NODE_CAMP]
			for prev_id in nodes[node_id]["prev"]:
				if nodes.has(prev_id) and nodes[prev_id]["type"] == NODE_CAMP:
					valid_types.erase(NODE_CAMP)
					break
			
			nodes[node_id]["type"] = _pick_weighted_type(valid_types)

func _closest_source(nodes: Dictionary, candidates: Array, target_id: int) -> int:
	if candidates.is_empty(): return -1
	var best_id: int = -1
	var best_dist: int = 999999
	for source_id in candidates:
		var dist: int = abs(int(nodes[source_id]["column"]) - int(nodes[target_id]["column"]))
		if dist < best_dist:
			best_dist = dist
			best_id = source_id
	return best_id

func _sorted_candidates_by_distance(nodes: Dictionary, candidates: Array, node_id: int) -> Array:
	var sorted: Array = candidates.duplicate()
	var source_col: int = nodes[node_id]["column"]
	sorted.sort_custom(func(a, b):
		var dist_a = abs(int(nodes[a]["column"]) - source_col)
		var dist_b = abs(int(nodes[b]["column"]) - source_col)
		return dist_a < dist_b
	)
	return sorted

func _would_cross_existing(nodes: Dictionary, from_id: int, to_id: int, edges: Array) -> bool:
	var a := Vector2(float(nodes[from_id]["column"]), float(nodes[from_id]["floor"]))
	var b := Vector2(float(nodes[to_id]["column"]), float(nodes[to_id]["floor"]))
	for edge in edges:
		var c := Vector2(float(nodes[edge[0]]["column"]), float(nodes[edge[0]]["floor"]))
		var d := Vector2(float(nodes[edge[1]]["column"]), float(nodes[edge[1]]["floor"]))
		if _segments_cross(a, b, c, d):
			return true
	return false

func _pick_start_columns(count: int) -> Array:
	"""隨機選擇起始列"""
	var all_cols: Array = []
	for i in range(columns):
		all_cols.append(i)
	
	all_cols.shuffle()
	return all_cols.slice(0, min(count, columns))

func _add_cross_path_connections(nodes: Dictionary, current: Array, nxt: Array, edges: Array) -> void:
	"""在不同路徑間添加跨越連接，增加決策多樣性"""
	var cross_attempts = int(current.size() * cross_path_connection_ratio)
	
	for _i in range(cross_attempts):
		if current.is_empty() or nxt.is_empty():
			continue
		
		var source_idx = randi() % current.size()
		var target_idx = randi() % nxt.size()
		var source_id = current[source_idx]
		var target_id = nxt[target_idx]
		
		# 優先選擇來自不同路徑的連接
		var source_path = nodes[source_id].get("path_id", -1)
		var target_path = nodes[target_id].get("path_id", -1)
		
		if source_path >= 0 and target_path >= 0 and source_path != target_path:
			if not _edge_exists(nodes, source_id, target_id):
				if not _would_cross_existing(nodes, source_id, target_id, edges):
					_add_edge(nodes, source_id, target_id)
					edges.append([source_id, target_id])