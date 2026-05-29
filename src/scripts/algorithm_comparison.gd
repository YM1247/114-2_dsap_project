extends RefCounted
class_name AlgorithmComparison

## 算法對比測試工具 - 比較 DAG、BSP 和改進後的 Forest 演算法

const MAP_EVALUATOR_SCRIPT = preload("res://src/scripts/map_evaluator.gd")

var factory: MapGeneratorFactory = MapGeneratorFactory.new()
var evaluator = null

func _init() -> void:
	evaluator = MAP_EVALUATOR_SCRIPT.new()

## 運行對比測試（生成 N 張地圖並統計各演算法的平均分）
func run_comparison_test(sample_size: int = 50) -> Dictionary:
	var results: Dictionary = {}
	
	for algo_name in ["dag", "bsp", "forest"]:
		var scores: Array = []
		var metrics: Dictionary = {
			"choice_quality": [],
			"branch_options": [],
			"path_diversity": [],
			"path_quality": [],
			"encounter_variety": [],
			"pacing_balance": []
		}
		
		var current_algo_display_name: String = ""
		for i in range(sample_size):
			var generator = factory.create_generator(algo_name)
			if i == 0:
				current_algo_display_name = generator.get_algorithm_name()
			var map_data = generator.generate_map()
			
			if typeof(map_data) != TYPE_DICTIONARY or map_data.is_empty() or not map_data.has("floors") or not map_data.has("nodes"):
				continue
			
			var evaluation = evaluator.evaluate_map(map_data, generator)
			scores.append(evaluation["total_score"])
			
			for metric_key in metrics.keys():
				metrics[metric_key].append(evaluation["metrics"][metric_key])
		
		results[algo_name] = {
			"algorithm": current_algo_display_name,
			"sample_count": scores.size(),
			"avg_score": _calculate_average(scores),
			"min_score": _calculate_min(scores),
			"max_score": _calculate_max(scores),
			"std_dev": _calculate_std_dev(scores),
			"metrics_avg": _average_metrics(metrics),
			"raw_scores": scores
		}
	
	return results

## 格式化輸出對比結果
func format_comparison_results(results: Dictionary) -> String:
	var output: String = "\n" + "=".repeat(100) + "\n"
	output += "地圖生成演算法對比測試\n"
	output += "=".repeat(100) + "\n\n"
	
	for algo_key in ["dag", "bsp", "forest"]:
		if not results.has(algo_key):
			continue
		
		var data = results[algo_key]
		output += "演算法: %s\n" % data["algorithm"]
		output += "-".repeat(50) + "\n"
		output += "  樣本數: %d\n" % data["sample_count"]
		output += "  平均分: %.1f / 100\n" % data["avg_score"]
		output += "  最低分: %d / 100\n" % data["min_score"]
		output += "  最高分: %d / 100\n" % data["max_score"]
		output += "  標準差: %.2f\n" % data["std_dev"]
		output += "  指標平均值:\n"
		
		for metric_key in data["metrics_avg"].keys():
			var value = data["metrics_avg"][metric_key]
			output += "    - %s: %.1f\n" % [metric_key, value]
		
		output += "\n"
	
	output += "=".repeat(100) + "\n"
	return output

## 計算優化效果（Forest vs DAG）
func calculate_improvement_percentage(results: Dictionary) -> Dictionary:
	if not results.has("dag") or not results.has("forest"):
		return {}
	
	var dag_score = results["dag"]["avg_score"]
	var forest_score = results["forest"]["avg_score"]
	var improvement = ((forest_score - dag_score) / dag_score) * 100.0
	
	var metric_improvements: Dictionary = {}
	var dag_metrics = results["dag"]["metrics_avg"]
	var forest_metrics = results["forest"]["metrics_avg"]
	
	for metric_key in dag_metrics.keys():
		var dag_val = dag_metrics[metric_key]
		var forest_val = forest_metrics[metric_key]
		var pct = ((forest_val - dag_val) / dag_val) * 100.0
		metric_improvements[metric_key] = pct
	
	return {
		"overall_improvement": improvement,
		"metric_improvements": metric_improvements
	}

## ============== 輔助方法 ==============

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

func _average_metrics(metrics: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for metric_key in metrics.keys():
		result[metric_key] = _calculate_average(metrics[metric_key])
	return result
