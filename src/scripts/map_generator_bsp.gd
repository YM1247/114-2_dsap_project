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

var min_region_size: float = 15.0  # 最小區域尺寸
var max_recursion_depth: int = 3   # 最大遞迴深度
var nodes_per_region: int = 2      # 每區域節點數

func generate_map() -> Dictionary:
	var nodes: Dictionary = {}
	var floors_to_nodes: Array = []
	var next_node_id: int = 0
	
	# Step 1: 遞迴分割空間
	var regions: Array = []
	_partition_space(
		BSPRegion.new(0.0, float(columns), 0.0, float(floors), 0),
		regions
	)
	
	# Step 2: 為每個區域創建節點
	var region_to_floor: Dictionary = {}  # region -> floor_idx 的映射
	
	for region in regions:
		# 根據區域的 y 位置確定樓層
		var region_floor: int = int((1.0 - region.y_min / float(floors)) * float(floors - 1))
		region_floor = clampi(region_floor, 0, floors - 1)
		region_to_floor[region] = region_floor
		
		# 確保每層有足夠的數組空間
		while floors_to_nodes.size() <= region_floor:
			floors_to_nodes.append([])
		
		# 在該區域生成節點
		var nodes_in_region: int = randi_range(1, nodes_per_region)
		for i in range(nodes_in_region):
			# 隨機在區域內選擇位置
			var x: float = randf_range(region.x_min, region.x_max)
			var y: float = randf_range(region.y_min, region.y_max)
			
			# 轉換為列號（四舍五入）
			var col: int = clampi(int(x), 0, columns - 1)
			
			# 創建節點
			var node: Dictionary = {
				"id": next_node_id,
				"floor": region_floor,
				"column": col,
				"type": NODE_COMBAT,
				"next": [],
				"prev": [],
				"region": region  # 記錄所屬區域
			}
			nodes[next_node_id] = node
			floors_to_nodes[region_floor].append(next_node_id)
			next_node_id += 1
	
	# Step 3: 連接相鄰層級（DAG 方式）
	_connect_floors(nodes, floors_to_nodes)
	
	# Step 4: 分配節點類型
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
	# 終止條件：深度達到上限或區域太小
	if region.depth >= max_recursion_depth or \
	   region.width() < min_region_size or \
	   region.height() < min_region_size:
		output.append(region)
		return
	
	# 隨機選擇切割方向（垂直或水平）
	var cut_vertical: bool = randf() > 0.5
	
	if cut_vertical:
		# 垂直切割 (沿 x 軸)
		var cut_x: float = randf_range(
			region.x_min + min_region_size * 0.5,
			region.x_max - min_region_size * 0.5
		)
		var left_region = BSPRegion.new(region.x_min, cut_x, region.y_min, region.y_max, region.depth + 1)
		var right_region = BSPRegion.new(cut_x, region.x_max, region.y_min, region.y_max, region.depth + 1)
		
		_partition_space(left_region, output)
		_partition_space(right_region, output)
	else:
		# 水平切割 (沿 y 軸)
		var cut_y: float = randf_range(
			region.y_min + min_region_size * 0.5,
			region.y_max - min_region_size * 0.5
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
				# BSP 較寬鬆，不做交叉檢查（因為區域天然分組）
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
	for floor in range(floors_to_nodes.size()):
		var floor_nodes: Array = floors_to_nodes[floor]
		for node_id in floor_nodes:
			# 第一層必須是 combat
			if floor == 0:
				nodes[node_id]["type"] = NODE_COMBAT
				continue
			
			# 最後一層必須是 boss
			if floor == floors_to_nodes.size() - 1:
				nodes[node_id]["type"] = NODE_BOSS
				continue
			
			# 中間層：根據規則選擇
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
