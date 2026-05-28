extends RefCounted
class_name MapGeneratorBase

## 所有地圖生成演算法的基類
## 
## 子類必須實現 generate_map() 和 verify_connectivity()
## 生成的 map_data 格式必須統一：
## {
##   "nodes": { node_id -> node_data },
##   "floors": [ [node_ids_floor_0], [node_ids_floor_1], ... ]
## }
## 其中 node_data = { "id", "floor", "column", "type", "next": [], "prev": [] }

# 配置參數
var floors: int = 10
var columns: int = 7
var min_nodes_per_floor: int = 3
var max_nodes_per_floor: int = 5
var max_links_per_node: int = 2

# 節點類型常數
const NODE_COMBAT := "combat"
const NODE_ELITE := "elite"
const NODE_EVENT := "event"
const NODE_SHOP := "shop"
const NODE_CAMP := "camp"
const NODE_BOSS := "boss"

# 節點類型權重（子類可覆蓋）
var type_weights: Dictionary = {
	NODE_COMBAT: 45.0,
	NODE_EVENT: 25.0,
	NODE_ELITE: 12.0,
	NODE_SHOP: 10.0,
	NODE_CAMP: 8.0
}

## 生成地圖（子類必須實現）
func generate_map() -> Dictionary:
	push_error("generate_map() must be implemented by subclass")
	return {}

## 驗證連通性（子類必須實現）
func verify_connectivity(map_data: Dictionary) -> Dictionary:
	push_error("verify_connectivity() must be implemented by subclass")
	return {}

## 獲取演算法名稱
func get_algorithm_name() -> String:
	return "Base Algorithm"

## 獲取演算法說明
func get_algorithm_description() -> String:
	return "Base class for map generation algorithms"

## ============== 通用輔助方法 ==============

## 檢查邊是否存在
func _edge_exists(nodes: Dictionary, from_id: int, to_id: int) -> bool:
	return nodes[from_id]["next"].has(to_id)

## 添加邊（雙向更新）
func _add_edge(nodes: Dictionary, from_id: int, to_id: int) -> void:
	nodes[from_id]["next"].append(to_id)
	nodes[to_id]["prev"].append(from_id)

## 通用 DFS 前向遍歷
func _dfs_forward(nodes: Dictionary, node_id: int, visited: Dictionary) -> void:
	if visited.has(node_id):
		return
	visited[node_id] = true
	for next_id in nodes[node_id]["next"]:
		_dfs_forward(nodes, next_id, visited)

## 通用 DFS 後向遍歷
func _dfs_backward(nodes: Dictionary, node_id: int, visited: Dictionary) -> void:
	if visited.has(node_id):
		return
	visited[node_id] = true
	for prev_id in nodes[node_id]["prev"]:
		_dfs_backward(nodes, prev_id, visited)

## 通用連通性驗證（基於起點可達性）
func _verify_connectivity_impl(map_data: Dictionary) -> Dictionary:
	var nodes: Dictionary = map_data["nodes"]
	var floors_to_nodes: Array = map_data["floors"]
	var starts: Array = floors_to_nodes[0]
	var boss_id: int = floors_to_nodes[floors_to_nodes.size() - 1][0]

	var reachable_from_starts: Dictionary = {}
	for start_id in starts:
		_dfs_forward(nodes, start_id, reachable_from_starts)

	var reachable_to_boss: Dictionary = {}
	_dfs_backward(nodes, boss_id, reachable_to_boss)

	var isolated_nodes: Array = []
	var start_without_boss_path: Array = []
	for node_id in nodes.keys():
		if not reachable_from_starts.has(node_id) and not starts.has(node_id):
			isolated_nodes.append(node_id)

	for start_id in starts:
		if not reachable_to_boss.has(start_id):
			start_without_boss_path.append(start_id)

	return {
		"is_valid": isolated_nodes.is_empty() and start_without_boss_path.is_empty(),
		"isolated_nodes": isolated_nodes,
		"start_without_boss_path": start_without_boss_path
	}

## 計算路徑數
func _count_paths_to_boss(nodes: Dictionary, floors_to_nodes: Array) -> int:
	var starts: Array = floors_to_nodes[0]
	var boss_id: int = floors_to_nodes[floors_to_nodes.size() - 1][0]
	var total_paths: int = 0
	for start_id in starts:
		total_paths += _dfs_path_count(nodes, start_id, boss_id, 0, 2000)
	return total_paths

func _dfs_path_count(nodes: Dictionary, current_id: int, target_id: int, depth: int, max_depth: int) -> int:
	if depth > max_depth:
		return 0
	if current_id == target_id:
		return 1
	var count: int = 0
	for next_id in nodes[current_id]["next"]:
		count += _dfs_path_count(nodes, next_id, target_id, depth + 1, max_depth)
	return count

## 加權隨機抽樣
func _pick_weighted_type(valid_types: Array = []) -> String:
	var pool: Dictionary = type_weights.duplicate()
	
	if valid_types.size() > 0:
		var filtered: Dictionary = {}
		for t in valid_types:
			if pool.has(t):
				filtered[t] = pool[t]
		pool = filtered
	
	if pool.is_empty():
		return NODE_COMBAT
	
	var total: float = 0.0
	for weight in pool.values():
		total += weight
	
	var pick: float = randf_range(0.0, total)
	var cumulative: float = 0.0
	for key in pool.keys():
		cumulative += pool[key]
		if pick <= cumulative:
			return key
	return NODE_COMBAT

## 檢查兩線段是否相交
func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if a == c or a == d or b == c or b == d:
		return false
	var ab_ac: float = (b - a).cross(c - a)
	var ab_ad: float = (b - a).cross(d - a)
	var cd_ca: float = (d - c).cross(a - c)
	var cd_cb: float = (d - c).cross(b - c)
	return (ab_ac * ab_ad < 0.0) and (cd_ca * cd_cb < 0.0)
