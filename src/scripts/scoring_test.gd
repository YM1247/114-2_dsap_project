extends RefCounted
class_name ScoringTest

## Phase 1 優化驗證測試
## 用於對比改進前後的評分差異

const MAP_EVALUATOR_SCRIPT = preload("res://src/scripts/map_evaluator.gd")

var factory: MapGeneratorFactory = MapGeneratorFactory.new()
var evaluator = null
var test_results: Dictionary = {}

func _init() -> void:
	evaluator = MAP_EVALUATOR_SCRIPT.new()

## 運行完整測試套件
func run_full_test(sample_per_algo: int = 30) -> String:
	var output: String = "\n" + "=".repeat(120) + "\n"
	output += "Phase 1 評分系統優化驗證測試\n"
	output += "=".repeat(120) + "\n\n"
	
	for algo_name in ["dag", "bsp", "forest"]:
		output += _test_single_algorithm(algo_name, sample_per_algo)
	
	output += _compare_algorithms()
	output += "=".repeat(120) + "\n"
	return output

func _test_single_algorithm(algo_name: String, sample_count: int) -> String:
	var output: String = "演算法: %s\n" % algo_name.to_upper()
	output += "-".repeat(50) + "\n"
	
	var scores: Array = []
	var metrics_data: Dictionary = {
		"choice_quality": [],
		"branch_options": [],
		"path_diversity": [],
		"path_quality": [],
		"encounter_variety": [],
		"pacing_balance": []
	}
	
	for i in range(sample_count):
		var generator = factory.create_generator(algo_name)
		var map_data = generator.generate_map()
		
		if map_data.is_empty():
			continue
		
		var evaluation = evaluator.evaluate_map(map_data, generator)
		scores.append(evaluation["total_score"])
		
		for metric_key in metrics_data.keys():
			if evaluation["metrics"].has(metric_key):
				metrics_data[metric_key].append(evaluation["metrics"][metric_key])
	
	if scores.is_empty():
		output += "✗ 測試失敗：無法生成有效地圖\n\n"
		return output
	
	# 計算統計數據
	var avg_score = _calculate_average(scores)
	var min_score = _calculate_min(scores)
	var max_score = _calculate_max(scores)
	var std_dev = _calculate_std_dev(scores)
	
	output += "樣本數: %d\n" % scores.size()
	output += "平均分: %.1f / 100\n" % avg_score
	output += "最低分: %d / 100\n" % min_score
	output += "最高分: %d / 100\n" % max_score
	output += "標準差: %.2f (穩定性指標)\n" % std_dev
	output += "\n各指標平均值:\n"
	
	for metric_key in metrics_data.keys():
		var avg = _calculate_average(metrics_data[metric_key])
		var std = _calculate_std_dev(metrics_data[metric_key])
		output += "  - %s: %.1f (±%.1f)\n" % [metric_key, avg, std]
	
	test_results[algo_name] = {
		"avg_score": avg_score,
		"std_dev": std_dev,
		"min": min_score,
		"max": max_score,
		"metrics": metrics_data,
		"scores": scores
	}
	
	output += "\n"
	return output

func _compare_algorithms() -> String:
	var output: String = "對比分析\n"
	output += "-".repeat(50) + "\n"
	
	# 檢查指標獨立性
	output += "✓ 指標獨立性檢查:\n"
	for algo_name in test_results.keys():
		var data = test_results[algo_name]
		var choice_and_branch_corr = _calculate_correlation(
			data["metrics"]["choice_quality"],
			data["metrics"]["branch_options"]
		)
		output += "  %s: choice_quality ↔ branch_options 相關性: %.2f\n" % [algo_name, choice_and_branch_corr]
	
	# 檢查穩定性
	output += "\n✓ 評分穩定性檢查 (標準差越小越穩定):\n"
	var min_std = 999.0
	var max_std = 0.0
	for algo_name in test_results.keys():
		var std = test_results[algo_name]["std_dev"]
		min_std = min(min_std, std)
		max_std = max(max_std, std)
		var stability = "✓ 穩定" if std < 10.0 else "⚠ 波動"
		output += "  %s: %.2f %s\n" % [algo_name, std, stability]
	
	# 檢查演算法差異化
	output += "\n✓ 演算法差異化檢查:\n"
	var avg_scores: Array = []
	for algo_name in test_results.keys():
		avg_scores.append(test_results[algo_name]["avg_score"])
	
	var min_avg = _calculate_min(avg_scores)
	var max_avg = _calculate_max(avg_scores)
	var score_range = max_avg - min_avg
	
	if score_range > 5.0:
		output += "  ✓ 演算法得分差異明顯 (範圍: %.1f 分)\n" % score_range
	else:
		output += "  ⚠ 演算法得分差異較小 (範圍: %.1f 分)\n" % score_range
	
	output += "\n優化效果評估:\n"
	output += "  📊 指標重疊度: %s\n" % _get_overlap_assessment()
	output += "  📈 分布穩定性: %s\n" % _get_stability_assessment()
	output += "  🎯 演算法差異化: %s\n" % _get_differentiation_assessment()
	
	output += "\n"
	return output

func _get_overlap_assessment() -> String:
	var avg_corr = 0.0
	var count = 0
	for algo_name in test_results.keys():
		var data = test_results[algo_name]
		var corr = _calculate_correlation(
			data["metrics"]["choice_quality"],
			data["metrics"]["branch_options"]
		)
		avg_corr += corr
		count += 1
	
	avg_corr /= max(count, 1)
	
	if avg_corr < 0.4:
		return "✓ 優秀 (相關性 < 0.4，指標獨立)"
	elif avg_corr < 0.6:
		return "✓ 良好 (相關性 0.4-0.6)"
	else:
		return "⚠ 需改進 (相關性 > 0.6，仍有重疊)"

func _get_stability_assessment() -> String:
	var avg_std = 0.0
	var count = 0
	for algo_name in test_results.keys():
		avg_std += test_results[algo_name]["std_dev"]
		count += 1
	
	avg_std /= max(count, 1)
	
	if avg_std < 5.0:
		return "✓ 優秀 (標準差 < 5)"
	elif avg_std < 10.0:
		return "✓ 良好 (標準差 5-10)"
	else:
		return "⚠ 需改進 (標準差 > 10)"

func _get_differentiation_assessment() -> String:
	var avg_scores: Array = []
	for algo_name in test_results.keys():
		avg_scores.append(test_results[algo_name]["avg_score"])
	
	var min_avg = _calculate_min(avg_scores)
	var max_avg = _calculate_max(avg_scores)
	var range = max_avg - min_avg
	
	if range > 8.0:
		return "✓ 優秀 (平均分差 > 8 分)"
	elif range > 5.0:
		return "✓ 良好 (平均分差 5-8 分)"
	else:
		return "⚠ 需改進 (平均分差 < 5 分)"

## ============== 統計工具 ==============

func _calculate_average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum = 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())

func _calculate_min(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var min_val = values[0]
	for v in values:
		if v < min_val:
			min_val = v
	return min_val

func _calculate_max(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var max_val = values[0]
	for v in values:
		if v > max_val:
			max_val = v
	return max_val

func _calculate_std_dev(values: Array) -> float:
	if values.size() <= 1:
		return 0.0
	var avg = _calculate_average(values)
	var variance = 0.0
	for v in values:
		variance += pow(float(v) - avg, 2)
	variance /= float(values.size())
	return sqrt(variance)

func _calculate_correlation(values1: Array, values2: Array) -> float:
	## 計算皮爾遜相關係數
	if values1.size() != values2.size() or values1.is_empty():
		return 0.0
	
	var mean1 = _calculate_average(values1)
	var mean2 = _calculate_average(values2)
	
	var numerator = 0.0
	var sum_sq1 = 0.0
	var sum_sq2 = 0.0
	
	for i in range(values1.size()):
		var diff1 = float(values1[i]) - mean1
		var diff2 = float(values2[i]) - mean2
		numerator += diff1 * diff2
		sum_sq1 += diff1 * diff1
		sum_sq2 += diff2 * diff2
	
	if sum_sq1 == 0.0 or sum_sq2 == 0.0:
		return 0.0
	
	var correlation = numerator / sqrt(sum_sq1 * sum_sq2)
	return abs(correlation)  # 返回絕對值
