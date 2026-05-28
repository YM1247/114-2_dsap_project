extends MapGeneratorBase
class_name MapGeneratorBSP

## BSP 演算法實現（二分空間分割）
## 特點：遞迴分割空間、自然聚類
## 優勢：視覺美觀、區域化設計
##
## 流程：
## 1. 遞迴分割空間成子區域
## 2. 每個區域映射到樓層
## 3. 每個區域生成 1-3 個節點
## 4. 連接相鄰層級
## 5. 分配節點類型

class BSPRegion:
	var x_min: float
	var x_max: float
	var y_min: float
	var y_max: float
	var depth: int
	
	func _init(xmin: float, xmax: float, ymin: float, ymax: float, d: int):
		x_min = xmin
		x_max = xmax
		y_min = ymin
		y_max = ymax
		depth = d
	
	func width() -> float:
		return x_max - x_min
	
	func height() -> float:
		return y_max - y_min
	
	func area() -> float:
		return width() * height()

var min_region_width: float = 1.5  # 最小區域寬度
var min_region_height: float = 1.5 # 最小區域高度
var max_recursion_depth: int = 5   # 最大遞迴深度
var nodes_per_region: int = 2      # 每區域節點數

func generate_map() -> Dictionary:
	var nodes: Dictionary = {}
	var floors_to_nodes: Array = []
	var next_node_id: int = 0
	
	# 先建立固定數量的空樓層，保證總層數與 DAG 相同
	for i in range(floors - 1):
		floors_to_nodes.append([])

	# Step 1: 遞迴分割除 Boss 層以外的空間
	var partition_height = float(floors - 1)
	if partition_height < min_region_height:
		partition_height = min_region_height # 確保至少能分割

	var regions: Array = []
	_partition_space(
		BSPRegion.new(0.0, float(columns), 0.0, partition_height, 0),
		regions
	)
	
	# Step 2: 為每個區域創建節點並映射到樓層
	for region in regions:
		# 根據區域的 y 位置確定樓層
		# 使用區域的中心 Y 座標來計算樓層，更為準確且公式直觀
		var center_y: float = (region.y_min + region.y_max) / 2.0
		var max_floor_idx = floors - 2
		var region_floor: int = int(center_y / partition_height * float(max_floor_idx))
		region_floor = clampi(region_floor, 0, max_floor_idx)
		
		# 在該區域生成節點
		var nodes_in_region: int = randi_range(1, nodes_per_region)
		for i in range(nodes_in_region):
			# 收集目前該樓層已使用的欄位，避免視覺重疊
			var used_cols: Array = []
			for node_id in floors_to_nodes[region_floor]:
				used_cols.append(nodes[node_id]["column"])
			
			var available_cols: Array = []
			# 優先在區域對應的 X 範圍內尋找空欄位
			var start_col: int = clampi(int(region.x_min), 0, columns - 1)
			var end_col: int = clampi(int(region.x_max), 0, columns - 1)
			for c in range(start_col, end_col + 1):
				if not used_cols.has(c):
					available_cols.append(c)
			
			var col: int = -1
			if available_cols.size() > 0:
				col = available_cols[randi() % available_cols.size()]
			else:
				# 區域滿了則找同樓層其他空位
				var all_avail: Array = []
				for c in range(columns):
					if not used_cols.has(c):
						all_avail.append(c)
				if all_avail.size() > 0:
					col = all_avail[randi() % all_avail.size()]
			
			# 如果該層真的全部佔滿，則跳過此節點生成
			if col == -1:
				continue
			
			# 創建節點
			var node: Dictionary = {
				"id": next_node_id,
				"floor": region_floor,
				"column": col,
				"type": NODE_COMBAT,
				"next": [],
				"prev": [],
				"region": region
			}
			nodes[next_node_id] = node
			floors_to_nodes[region_floor].append(next_node_id)
			next_node_id += 1
	
	# Step 2.5: 補齊可能過少節點的樓層，強制每層至少 min_nodes_per_floor 節點，維持層數穩定與選擇多樣性
	for i in range(floors - 1):
		while floors_to_nodes[i].size() < min_nodes_per_floor:
			var used_cols: Array = []
			for node_id in floors_to_nodes[i]:
				used_cols.append(nodes[node_id]["column"])
			
			var available_cols: Array = []
			for c in range(columns):
				if not used_cols.has(c):
					available_cols.append(c)
					
			if available_cols.is_empty():
				break
				
			var col: int = available_cols[randi() % available_cols.size()]
			var node: Dictionary = {
				"id": next_node_id,
				"floor": i,
				"column": col,
				"type": NODE_COMBAT,
				"next": [],
				"prev": []
			}
			nodes[next_node_id] = node
			floors_to_nodes[i].append(next_node_id)
			next_node_id += 1

	# Step 3: 手動添加 Boss 節點
	var boss_floor_idx = floors_to_nodes.size()
	var boss_node_id = next_node_id
	next_node_id += 1
	
	var boss_node: Dictionary = {
		"id": boss_node_id,
		"floor": boss_floor_idx,
		"column": int(columns / 2),
		"type": NODE_BOSS,
		"next": [],
		"prev": []
	}
	nodes[boss_node_id] = boss_node
	floors_to_nodes.append([boss_node_id])

	# Step 4: 連接相鄰層級（DAG 方式）
	_connect_floors(nodes, floors_to_nodes)
	
	# Step 5: 分配節點類型（Boss 已處理）
	_assign_node_types(nodes, floors_to_nodes)
	
	return {
		"nodes": nodes,
		"floors": floors_to_nodes,
		"algorithm": "bsp"
	}

func verify_connectivity(map_data: Dictionary) -> Dictionary:
	return _verify_connectivity_impl(map_data)

func get_algorithm_name() -> String:
	return "Binary Space Partition (BSP)"

func get_algorithm_description() -> String:
	return "Space-partitioning based generation with natural clustering"

## ============== BSP 特定方法 ==============

## 遞迴分割空間
func _partition_space(region: BSPRegion, output: Array) -> void:
	# 終止條件：深度達到上限
	if region.depth >= max_recursion_depth:
		output.append(region)
		return
	
	var can_cut_v: bool = region.width() >= min_region_width * 2.0
	var can_cut_h: bool = region.height() >= min_region_height * 2.0
	
	# 如果兩邊都不能切，就只能終止
	if not can_cut_v and not can_cut_h:
		output.append(region)
		return
		
	var cut_vertical: bool
	if can_cut_v and can_cut_h:
		cut_vertical = randf() > 0.5
	else:
		cut_vertical = can_cut_v
	
	if cut_vertical:
		# 垂直切割 (沿 x 軸)
		var cut_x: float = randf_range(
			region.x_min + min_region_width,
			region.x_max - min_region_width
		)
		var left_region = BSPRegion.new(region.x_min, cut_x, region.y_min, region.y_max, region.depth + 1)
		var right_region = BSPRegion.new(cut_x, region.x_max, region.y_min, region.y_max, region.depth + 1)
		
		_partition_space(left_region, output)
		_partition_space(right_region, output)
	else:
		# 水平切割 (沿 y 軸)
		var cut_y: float = randf_range(
			region.y_min + min_region_height,
			region.y_max - min_region_height
		)
		var top_region = BSPRegion.new(region.x_min, region.x_max, cut_y, region.y_max, region.depth + 1)
		var bottom_region = BSPRegion.new(region.x_min, region.x_max, region.y_min, cut_y, region.depth + 1)
		
		_partition_space(top_region, output)
		_partition_space(bottom_region, output)

## 連接相鄰層級（沿用 DAG 的連接邏輯）
func _connect_floors(nodes: Dictionary, floors_to_nodes: Array) -> void:
	for floor in range(floors_to_nodes.size() - 1):
		var current: Array = floors_to_nodes[floor]
		var nxt: Array = floors_to_nodes[floor + 1]
		var edges_this_band: Array = []
		
		# 從當前層連接到下層
		for node_id in current:
			var desired_links: int = 1 if floor == floors_to_nodes.size() - 2 else randi_range(1, max_links_per_node)
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
			
			# 確保至少有一條邊
			if links_added == 0:
				var fallback_id: int = sorted_candidates[0]
				if not _edge_exists(nodes, node_id, fallback_id):
					_add_edge(nodes, node_id, fallback_id)
					edges_this_band.append([node_id, fallback_id])
		
		# 確保下層每個節點至少有一個前置節點
		for target_id in nxt:
			if nodes[target_id]["prev"].is_empty():
				var source_id: int = _closest_source(nodes, current, target_id)
				if not _edge_exists(nodes, source_id, target_id):
					_add_edge(nodes, source_id, target_id)
					edges_this_band.append([source_id, target_id])

## 分配節點類型
func _assign_node_types(nodes: Dictionary, floors_to_nodes: Array) -> void:
	# Boss 層已經在生成時處理，所以遍歷到倒數第二層即可
	for floor in range(floors_to_nodes.size() - 1):
		var floor_nodes: Array = floors_to_nodes[floor]
		for node_id in floor_nodes:
			# 第一層必須是 combat
			if floor == 0:
				nodes[node_id]["type"] = NODE_COMBAT
				continue

			# 中間層根據規則選擇
			var prev_nodes: Array = nodes[node_id]["prev"]
			var valid_types: Array = [NODE_COMBAT, NODE_EVENT, NODE_ELITE, NODE_SHOP, NODE_CAMP]
			
			# 防止連續 camp
			for prev_id in prev_nodes:
				if nodes[prev_id]["type"] == NODE_CAMP:
					valid_types.erase(NODE_CAMP)
					break
			
			nodes[node_id]["type"] = _pick_weighted_type(valid_types)

## 查找最近的源節點（按列距離）
func _closest_source(nodes: Dictionary, candidates: Array, target_id: int) -> int:
	# 如果 candidates 為空，從整體節點中找尋所有位於目標樓層之前的節點作為備援
	if candidates.is_empty():
		var fallback: Array = []
		for id in nodes.keys():
			if int(nodes[id]["floor"]) < int(nodes[target_id]["floor"]):
				fallback.append(id)
		if fallback.is_empty():
			# 沒有可用來源，回傳 target_id 作為保險（呼叫方應避免自環）
			return target_id
		candidates = fallback

	var best_id: int = candidates[0]
	var best_dist: int = abs(int(nodes[best_id]["column"]) - int(nodes[target_id]["column"]))
	for source_id in candidates:
		var dist: int = abs(int(nodes[source_id]["column"]) - int(nodes[target_id]["column"]))
		if dist < best_dist:
			best_dist = dist
			best_id = source_id
	return best_id

## 按距離排序候選節點
func _sorted_candidates_by_distance(nodes: Dictionary, candidates: Array, node_id: int) -> Array:
	var sorted: Array = candidates.duplicate()
	var source_col: int = nodes[node_id]["column"]
	
	# 簡單排序
	for i in range(sorted.size()):
		var best_index: int = i
		var best_dist: int = abs(int(nodes[sorted[best_index]]["column"]) - source_col)
		for j in range(i + 1, sorted.size()):
			var current_dist: int = abs(int(nodes[sorted[j]]["column"]) - source_col)
			if current_dist < best_dist:
				best_dist = current_dist
				best_index = j
		if best_index != i:
			var temp = sorted[i]
			sorted[i] = sorted[best_index]
			sorted[best_index] = temp
	
	return sorted

## 檢查路徑是否會與已存在的連線交叉
func _would_cross_existing(nodes: Dictionary, from_id: int, to_id: int, edges: Array) -> bool:
	var a: Vector2 = Vector2(float(nodes[from_id]["column"]), float(nodes[from_id]["floor"]))
	var b: Vector2 = Vector2(float(nodes[to_id]["column"]), float(nodes[to_id]["floor"]))
	for edge in edges:
		var c: Vector2 = Vector2(float(nodes[edge[0]]["column"]), float(nodes[edge[0]]["floor"]))
		var d: Vector2 = Vector2(float(nodes[edge[1]]["column"]), float(nodes[edge[1]]["floor"]))
		if _segments_cross(a, b, c, d):
			return true
	return false
