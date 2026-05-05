extends RefCounted
class_name MapGenerator

const NODE_COMBAT := "combat"
const NODE_ELITE := "elite"
const NODE_EVENT := "event"
const NODE_SHOP := "shop"
const NODE_CAMP := "camp"
const NODE_BOSS := "boss"

var floors: int = 10
var columns: int = 7
var min_nodes_per_floor: int = 3
var max_nodes_per_floor: int = 5
var max_links_per_node: int = 2

var type_weights: Dictionary = {
	NODE_COMBAT: 45.0,
	NODE_EVENT: 25.0,
	NODE_ELITE: 12.0,
	NODE_SHOP: 10.0,
	NODE_CAMP: 8.0
}

func generate_map() -> Dictionary:
	var nodes: Dictionary = {}
	var floors_to_nodes: Array = []
	var next_node_id: int = 0

	for floor in range(floors):
		var floor_nodes: Array = []
		var target_count: int = 1 if floor == floors - 1 else randi_range(min_nodes_per_floor, max_nodes_per_floor)
		var chosen_columns: Array = _pick_columns(target_count)

		for col in chosen_columns:
			var node: Dictionary = {
				"id": next_node_id,
				"floor": floor,
				"column": col,
				"type": NODE_COMBAT,
				"next": [],
				"prev": []
			}
			nodes[next_node_id] = node
			floor_nodes.append(next_node_id)
			next_node_id += 1

		floors_to_nodes.append(floor_nodes)

	_connect_floors(nodes, floors_to_nodes)
	_assign_node_types(nodes, floors_to_nodes)

	return {
		"nodes": nodes,
		"floors": floors_to_nodes
	}

func verify_connectivity(map_data: Dictionary) -> Dictionary:
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

func _pick_columns(count: int) -> Array:
	var all_cols: Array = []
	for col in range(columns):
		all_cols.append(col)

	all_cols.shuffle()
	all_cols = all_cols.slice(0, count)
	all_cols.sort()
	return all_cols

func _connect_floors(nodes: Dictionary, floors_to_nodes: Array) -> void:
	for floor in range(floors_to_nodes.size() - 1):
		var current: Array = floors_to_nodes[floor]
		var nxt: Array = floors_to_nodes[floor + 1]
		var edges_this_band: Array = []

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

			if links_added == 0:
				var fallback_id: int = sorted_candidates[0]
				_add_edge(nodes, node_id, fallback_id)
				edges_this_band.append([node_id, fallback_id])

		for target_id in nxt:
			if nodes[target_id]["prev"].is_empty():
				var source_id: int = _closest_source(nodes, current, target_id)
				if not _edge_exists(nodes, source_id, target_id):
					_add_edge(nodes, source_id, target_id)
					edges_this_band.append([source_id, target_id])

func _assign_node_types(nodes: Dictionary, floors_to_nodes: Array) -> void:
	for floor in range(floors_to_nodes.size()):
		var floor_nodes: Array = floors_to_nodes[floor]
		for node_id in floor_nodes:
			if floor == 0:
				nodes[node_id]["type"] = NODE_COMBAT
				continue
			if floor == floors_to_nodes.size() - 1:
				nodes[node_id]["type"] = NODE_BOSS
				continue

			var prev_nodes: Array = nodes[node_id]["prev"]
			var can_be_camp: bool = true
			for prev_id in prev_nodes:
				if nodes[prev_id]["type"] == NODE_CAMP:
					can_be_camp = false
					break

			nodes[node_id]["type"] = _pick_weighted_type(can_be_camp)

func _pick_weighted_type(can_be_camp: bool) -> String:
	var pool: Dictionary = type_weights.duplicate()
	if not can_be_camp:
		pool.erase(NODE_CAMP)

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

func _closest_source(nodes: Dictionary, candidates: Array, target_id: int) -> int:
	var best_id: int = candidates[0]
	var best_dist: int = abs(int(nodes[best_id]["column"]) - int(nodes[target_id]["column"]))
	for source_id in candidates:
		var dist: int = abs(int(nodes[source_id]["column"]) - int(nodes[target_id]["column"]))
		if dist < best_dist:
			best_dist = dist
			best_id = source_id
	return best_id

func _sorted_candidates_by_distance(nodes: Dictionary, candidates: Array, node_id: int) -> Array:
	var sorted: Array = candidates.duplicate()
	var source_col: int = nodes[node_id]["column"]
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

func _add_edge(nodes: Dictionary, from_id: int, to_id: int) -> void:
	nodes[from_id]["next"].append(to_id)
	nodes[to_id]["prev"].append(from_id)

func _edge_exists(nodes: Dictionary, from_id: int, to_id: int) -> bool:
	return nodes[from_id]["next"].has(to_id)

func _would_cross_existing(nodes: Dictionary, from_id: int, to_id: int, edges: Array) -> bool:
	var a: Vector2 = Vector2(float(nodes[from_id]["column"]), float(nodes[from_id]["floor"]))
	var b: Vector2 = Vector2(float(nodes[to_id]["column"]), float(nodes[to_id]["floor"]))
	for edge in edges:
		var c: Vector2 = Vector2(float(nodes[edge[0]]["column"]), float(nodes[edge[0]]["floor"]))
		var d: Vector2 = Vector2(float(nodes[edge[1]]["column"]), float(nodes[edge[1]]["floor"]))
		if _segments_cross(a, b, c, d):
			return true
	return false

func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if a == c or a == d or b == c or b == d:
		return false
	var ab_ac: float = (b - a).cross(c - a)
	var ab_ad: float = (b - a).cross(d - a)
	var cd_ca: float = (d - c).cross(a - c)
	var cd_cb: float = (d - c).cross(b - c)
	return (ab_ac * ab_ad < 0.0) and (cd_ca * cd_cb < 0.0)

func _dfs_forward(nodes: Dictionary, node_id: int, visited: Dictionary) -> void:
	if visited.has(node_id):
		return
	visited[node_id] = true
	for next_id in nodes[node_id]["next"]:
		_dfs_forward(nodes, next_id, visited)

func _dfs_backward(nodes: Dictionary, node_id: int, visited: Dictionary) -> void:
	if visited.has(node_id):
		return
	visited[node_id] = true
	for prev_id in nodes[node_id]["prev"]:
		_dfs_backward(nodes, prev_id, visited)
