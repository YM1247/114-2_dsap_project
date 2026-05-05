extends RefCounted
class_name MapEvaluator

const METRIC_WEIGHTS := {
	"choice_quality": 0.25,
	"branch_options": 0.20,
	"path_diversity": 0.25,
	"encounter_variety": 0.20,
	"pacing_balance": 0.10
}

func evaluate_map(map_data: Dictionary, generator: Object) -> Dictionary:
	var nodes: Dictionary = map_data["nodes"]
	var floors_to_nodes: Array = map_data["floors"]

	var connectivity_report: Dictionary = generator.verify_connectivity(map_data)
	var camp_violation_count: int = _count_consecutive_camp_violations(nodes)
	var dead_end_count: int = _count_dead_ends_before_last_floor(nodes, floors_to_nodes)

	var choice_quality_score: float = _choice_quality_score(nodes, floors_to_nodes)
	var branch_options_score: float = _branch_options_score(nodes, floors_to_nodes, generator)
	var path_diversity_score: float = _path_diversity_score(nodes, floors_to_nodes)
	var encounter_variety_score: float = _encounter_variety_score(nodes, floors_to_nodes)
	var pacing_balance_score: float = _pacing_balance_score(floors_to_nodes)

	var weighted_total: float = (
		choice_quality_score * METRIC_WEIGHTS["choice_quality"] +
		branch_options_score * METRIC_WEIGHTS["branch_options"] +
		path_diversity_score * METRIC_WEIGHTS["path_diversity"] +
		encounter_variety_score * METRIC_WEIGHTS["encounter_variety"] +
		pacing_balance_score * METRIC_WEIGHTS["pacing_balance"]
	)

	return {
		"total_score": int(round(clamp(weighted_total, 0.0, 100.0))),
		"metrics": {
			"choice_quality": int(round(choice_quality_score)),
			"branch_options": int(round(branch_options_score)),
			"path_diversity": int(round(path_diversity_score)),
			"encounter_variety": int(round(encounter_variety_score)),
			"pacing_balance": int(round(pacing_balance_score))
		},
		"raw": {
			"connectivity_ok": bool(connectivity_report["is_valid"]),
			"camp_violations": camp_violation_count,
			"dead_ends": dead_end_count,
			"path_count_to_boss": _count_paths_to_boss(nodes, floors_to_nodes),
			"avg_out_degree": _avg_out_degree(nodes, floors_to_nodes),
			"decision_node_ratio": _decision_node_ratio(nodes, floors_to_nodes)
		}
	}

func _choice_quality_score(nodes: Dictionary, floors_to_nodes: Array) -> float:
	var avg_out_degree: float = _avg_out_degree(nodes, floors_to_nodes)
	var decision_ratio: float = _decision_node_ratio(nodes, floors_to_nodes)
	var out_degree_score: float = clamp(100.0 - abs(avg_out_degree - 1.8) * 140.0, 0.0, 100.0)
	var decision_score: float = clamp(100.0 - abs(decision_ratio - 0.55) * 180.0, 0.0, 100.0)
	return out_degree_score * 0.55 + decision_score * 0.45

func _path_diversity_score(nodes: Dictionary, floors_to_nodes: Array) -> float:
	var path_count: int = _count_paths_to_boss(nodes, floors_to_nodes)
	var normalized: float = log(1.0 + float(path_count)) / log(1.0 + 40.0)
	return clamp(normalized * 100.0, 0.0, 100.0)

func _branch_options_score(nodes: Dictionary, floors_to_nodes: Array, generator: Object) -> float:
	var avg_out_degree: float = _avg_out_degree(nodes, floors_to_nodes)
	var max_possible: float = max(float(generator.max_links_per_node), 1.0)
	var normalized: float = avg_out_degree / max_possible
	return clamp(normalized * 100.0, 0.0, 100.0)

func _encounter_variety_score(nodes: Dictionary, floors_to_nodes: Array) -> float:
	var counts := {
		"combat": 0,
		"elite": 0,
		"event": 0,
		"shop": 0,
		"camp": 0
	}
	var total: int = 0
	for floor_idx in range(1, floors_to_nodes.size() - 1):
		for node_id in floors_to_nodes[floor_idx]:
			var t: String = nodes[node_id]["type"]
			if counts.has(t):
				counts[t] += 1
				total += 1

	if total == 0:
		return 0.0

	var entropy: float = 0.0
	for key in counts.keys():
		var ratio: float = float(counts[key]) / float(total)
		if ratio > 0.0:
			entropy -= ratio * log(ratio)
	var max_entropy: float = log(5.0)
	return clamp((entropy / max_entropy) * 100.0, 0.0, 100.0)

func _pacing_balance_score(floors_to_nodes: Array) -> float:
	if floors_to_nodes.size() <= 2:
		return 0.0

	var middle_sizes: Array = []
	for floor_idx in range(1, floors_to_nodes.size() - 1):
		middle_sizes.append(floors_to_nodes[floor_idx].size())

	var avg_size: float = 0.0
	for v in middle_sizes:
		avg_size += float(v)
	avg_size /= float(middle_sizes.size())

	var variance: float = 0.0
	for v in middle_sizes:
		var diff: float = float(v) - avg_size
		variance += diff * diff
	variance /= float(middle_sizes.size())
	var std_dev: float = sqrt(variance)

	var avg_score: float = clamp(100.0 - abs(avg_size - 3.8) * 30.0, 0.0, 100.0)
	var stability_score: float = clamp(100.0 - std_dev * 40.0, 0.0, 100.0)
	return avg_score * 0.6 + stability_score * 0.4

func _avg_out_degree(nodes: Dictionary, floors_to_nodes: Array) -> float:
	var out_sum: int = 0
	var out_count: int = 0
	for floor_idx in range(0, floors_to_nodes.size() - 1):
		for node_id in floors_to_nodes[floor_idx]:
			out_sum += nodes[node_id]["next"].size()
			out_count += 1
	if out_count == 0:
		return 0.0
	return float(out_sum) / float(out_count)

func _decision_node_ratio(nodes: Dictionary, floors_to_nodes: Array) -> float:
	var decision_nodes: int = 0
	var total_nodes: int = 0
	for floor_idx in range(0, floors_to_nodes.size() - 1):
		for node_id in floors_to_nodes[floor_idx]:
			total_nodes += 1
			if nodes[node_id]["next"].size() >= 2:
				decision_nodes += 1
	if total_nodes == 0:
		return 0.0
	return float(decision_nodes) / float(total_nodes)

func _count_consecutive_camp_violations(nodes: Dictionary) -> int:
	var violations: int = 0
	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id]
		if node["type"] != "camp":
			continue
		for prev_id in node["prev"]:
			if nodes[prev_id]["type"] == "camp":
				violations += 1
				break
	return violations

func _count_dead_ends_before_last_floor(nodes: Dictionary, floors_to_nodes: Array) -> int:
	var dead_ends: int = 0
	var last_floor: int = floors_to_nodes.size() - 1
	for node_id in nodes.keys():
		var node: Dictionary = nodes[node_id]
		if int(node["floor"]) == last_floor:
			continue
		if node["next"].is_empty():
			dead_ends += 1
	return dead_ends

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

