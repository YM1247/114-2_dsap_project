extends MapGeneratorBase
class_name MapGeneratorDAG

## DAG 演算法實現
## 特點：分層 DAG + 加權隨機 + 交叉抑制
## 優勢：快速、清晰、易控

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
		"floors": floors_to_nodes,
		"algorithm": "dag"
	}

func verify_connectivity(map_data: Dictionary) -> Dictionary:
	return _verify_connectivity_impl(map_data)

func get_algorithm_name() -> String:
	return "Layered DAG"

func get_algorithm_description() -> String:
	return "Hierarchical DAG generation with crossing minimization"

## ============== DAG 特定方法 ==============

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
			var valid_types: Array = [NODE_COMBAT, NODE_EVENT, NODE_ELITE, NODE_SHOP, NODE_CAMP]
			
			# 防止連續 camp
			for prev_id in prev_nodes:
				if nodes[prev_id]["type"] == NODE_CAMP:
					valid_types.erase(NODE_CAMP)
					break

			nodes[node_id]["type"] = _pick_weighted_type(valid_types)

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

func _would_cross_existing(nodes: Dictionary, from_id: int, to_id: int, edges: Array) -> bool:
	var a: Vector2 = Vector2(float(nodes[from_id]["column"]), float(nodes[from_id]["floor"]))
	var b: Vector2 = Vector2(float(nodes[to_id]["column"]), float(nodes[to_id]["floor"]))
	for edge in edges:
		var c: Vector2 = Vector2(float(nodes[edge[0]]["column"]), float(nodes[edge[0]]["floor"]))
		var d: Vector2 = Vector2(float(nodes[edge[1]]["column"]), float(nodes[edge[1]]["floor"]))
		if _segments_cross(a, b, c, d):
			return true
	return false
