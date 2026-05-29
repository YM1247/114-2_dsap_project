extends RefCounted
class_name MapEvaluator

const METRIC_WEIGHTS := {
	"choice_quality": 0.20,       # 降低：去重後更專注
	"branch_options": 0.15,       # 簡化為獨立指標
	"path_diversity": 0.20,       # 改為路徑品質評估
	"path_quality": 0.15,         # 新增：路徑間差異度
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
	var path_quality_score: float = _path_quality_score(nodes, floors_to_nodes)
	var encounter_variety_score: float = _encounter_variety_score(nodes, floors_to_nodes)
	var pacing_balance_score: float = _pacing_balance_score(floors_to_nodes)

	var weighted_total: float = (
		choice_quality_score * METRIC_WEIGHTS["choice_quality"] +
		branch_options_score * METRIC_WEIGHTS["branch_options"] +
		path_diversity_score * METRIC_WEIGHTS["path_diversity"] +
		path_quality_score * METRIC_WEIGHTS["path_quality"] +
		encounter_variety_score * METRIC_WEIGHTS["encounter_variety"] +
		pacing_balance_score * METRIC_WEIGHTS["pacing_balance"]
	)

	return {
		"total_score": int(round(clamp(weighted_total, 0.0, 100.0))),
		"metrics": {
			"choice_quality": int(round(choice_quality_score)),
			"branch_options": int(round(branch_options_score)),
			"path_diversity": int(round(path_diversity_score)),
			"path_quality": int(round(path_quality_score)),
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
	## 改進：專注於決策節點的品質，移除與 branch_options 的重疊
	var decision_ratio: float = _decision_node_ratio(nodes, floors_to_nodes)
	# 目標：約 55% 的節點是決策點（有 2 個或以上的出度）
	var decision_score: float = clamp(100.0 - abs(decision_ratio - 0.55) * 180.0, 0.0, 100.0)
	
	# 添加：決策點的分支品質評估
	var branch_quality_score: float = _branch_point_quality(nodes, floors_to_nodes)
	
	return decision_score * 0.6 + branch_quality_score * 0.4

func _path_diversity_score(nodes: Dictionary, floors_to_nodes: Array) -> float:
	var path_count: int = _count_paths_to_boss(nodes, floors_to_nodes)
	var normalized: float = log(1.0 + float(path_count)) / log(1.0 + 40.0)
	return clamp(normalized * 100.0, 0.0, 100.0)

func _branch_options_score(nodes: Dictionary, floors_to_nodes: Array, generator: Object) -> float:
	## 改進：簡化為獨立指標，只評估平均出度
	var avg_out_degree: float = _avg_out_degree(nodes, floors_to_nodes)
	# 目標出度：約 1.8-2.0
	var optimal_degree: float = 1.9
	var ratio: float = clamp(avg_out_degree / optimal_degree, 0.5, 1.5)
	return clamp(ratio * 100.0, 0.0, 100.0)

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
	if floors_to_nodes.is_empty() or floors_to_nodes[0].is_empty() or floors_to_nodes[-1].is_empty():
		return 0
		
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

## ============== Phase 1 優化：新增方法 ==============

func _branch_point_quality(nodes: Dictionary, floors_to_nodes: Array) -> float:
	## 評估決策點（分支點）的品質
	## - 分支點應連接到不同的下層節點
	## - 分支點應均勻分布
	var total_branch_points: int = 0
	var high_quality_branch_points: int = 0
	
	for floor_idx in range(0, floors_to_nodes.size() - 1):
		for node_id in floors_to_nodes[floor_idx]:
			var out_degree = nodes[node_id]["next"].size()
			if out_degree >= 2:  # 這是一個分支點
				total_branch_points += 1
				# 檢查分支點是否連接到足夠差異化的節點
				if out_degree >= 3 or _branch_has_variety(nodes, node_id):
					high_quality_branch_points += 1
	
	if total_branch_points == 0:
		return 0.0
	
	var quality_ratio: float = float(high_quality_branch_points) / float(total_branch_points)
	return quality_ratio * 100.0

func _branch_has_variety(nodes: Dictionary, branch_node_id: int) -> bool:
	## 檢查分支點是否連接到足夠不同的目標
	if nodes[branch_node_id]["next"].size() < 2:
		return false
	
	var targets = nodes[branch_node_id]["next"]
	if targets.size() < 2:
		return false
	
	# 檢查至少 2 個目標的列數差異 >= 2
	var target_cols: Array = []
	for target_id in targets:
		target_cols.append(nodes[target_id]["column"])
	
	target_cols.sort()
	var col_spread = target_cols[-1] - target_cols[0]
	return col_spread >= 2

func _path_quality_score(nodes: Dictionary, floors_to_nodes: Array) -> float:
	## Phase 1 新增：評估路徑間的品質和差異度
	## - 計算不同路徑的特徵差異
	## - 檢查是否有重複/冗餘路徑
	## - 評估路徑多樣性
	
	var path_count: int = _count_paths_to_boss(nodes, floors_to_nodes)
	if path_count <= 1:
		return 0.0
	
	# 計算路徑特徵的多樣性
	var path_profiles = _calculate_path_profiles(nodes, floors_to_nodes)
	var unique_ratio = float(path_profiles.size()) / max(float(path_count), 1.0)
	
	# 路徑多樣性評分：根據唯一路徑比例
	# - 如果所有路徑都不同：得分 100
	# - 如果有重複路徑：根據唯一比例扣分
	var diversity_score = clamp(unique_ratio * 100.0, 0.0, 100.0)
	
	return diversity_score

func _calculate_path_profiles(nodes: Dictionary, floors_to_nodes: Array) -> Array:
	## 計算所有路徑的節點類型序列作為「特徵」
	## 用於檢測重複路徑
	
	var starts: Array = floors_to_nodes[0]
	var boss_id: int = floors_to_nodes[floors_to_nodes.size() - 1][0]
	var all_paths: Array = []
	
	for start_id in starts:
		var paths = _enumerate_all_paths(nodes, start_id, boss_id, 0, 100)
		for path in paths:
			all_paths.append(path)
	
	# 轉換為特徵向量（簡化：每層的平均節點類型）
	var profiles: Dictionary = {}
	for path in all_paths:
		var profile = _path_to_profile(nodes, path)
		profiles[profile] = true  # 用 Dictionary 去重
	
	return profiles.keys()

func _enumerate_all_paths(nodes: Dictionary, current_id: int, target_id: int, depth: int, max_depth: int) -> Array:
	## 列舉從 current_id 到 target_id 的所有路徑
	if depth > max_depth:
		return []
	if current_id == target_id:
		return [[current_id]]
	
	var all_paths: Array = []
	for next_id in nodes[current_id]["next"]:
		var sub_paths = _enumerate_all_paths(nodes, next_id, target_id, depth + 1, max_depth)
		for sub_path in sub_paths:
			all_paths.append([current_id] + sub_path)
	
	return all_paths

func _path_to_profile(nodes: Dictionary, path: Array) -> String:
	## 將路徑轉換為特徵字符串
	## 用節點類型的序列代表路徑特徵
	var profile: String = ""
	for node_id in path:
		var node_type = nodes[node_id]["type"]
		var type_char = node_type.substr(0, 1).to_upper()  # c=combat, e=elite 等
		profile += type_char
	return profile
