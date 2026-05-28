extends RefCounted
class_name AlgorithmTester

## 用於測試不同演算法的工具類
## 可執行單個或多個演算法的生成和驗證

func test_single_algorithm(algorithm: String, map_count: int = 5) -> Dictionary:
	var factory = MapGeneratorFactory.new()
	var generator = factory.create_generator(algorithm)
	var results = {
		"algorithm": algorithm,
		"algorithm_name": generator.get_algorithm_name(),
		"total_tests": map_count,
		"successful": 0,
		"failed": 0,
		"errors": [],
		"execution_times": [],
		"maps": []
	}
	
	for i in range(map_count):
		var start_time = Time.get_ticks_msec()
		var map_data = generator.generate_map()
		var end_time = Time.get_ticks_msec()
		var execution_time = end_time - start_time
		
		var connectivity = generator.verify_connectivity(map_data)
		
		if map_data.is_empty():
			results["failed"] += 1
			results["errors"].append("Map %d: Failed to generate" % i)
		elif not connectivity["is_valid"]:
			results["failed"] += 1
			results["errors"].append("Map %d: Connectivity check failed" % i)
		else:
			results["successful"] += 1
			results["execution_times"].append(execution_time)
		
		results["maps"].append({
			"map_data": map_data,
			"connectivity": connectivity,
			"execution_time": execution_time
		})
	
	# 計算統計數據
	if results["execution_times"].size() > 0:
		var sum: int = 0
		for t in results["execution_times"]:
			sum += t
		results["avg_execution_time"] = float(sum) / float(results["execution_times"].size())
	else:
		results["avg_execution_time"] = 0.0
	
	return results

func test_all_algorithms(map_count: int = 5) -> Dictionary:
	var factory = MapGeneratorFactory.new()
	var algorithms = factory.get_available_algorithms()
	var results = {}
	
	for algo in algorithms:
		results[algo] = test_single_algorithm(algo, map_count)
	
	return results

## 生成測試報告文本
func generate_test_report(test_results: Dictionary) -> String:
	var report = "=== 演算法測試報告 ===\n\n"
	
	if test_results.has("algorithm"):
		# 單演算法結果
		var result = test_results
		report += "演算法: %s\n" % result["algorithm_name"]
		report += "測試次數: %d\n" % result["total_tests"]
		report += "成功: %d / 失敗: %d\n" % [result["successful"], result["failed"]]
		if result.has("avg_execution_time"):
			report += "平均執行時間: %.2f ms\n" % result["avg_execution_time"]
		
		if result["errors"].size() > 0:
			report += "\n錯誤列表:\n"
			for err in result["errors"]:
				report += "  - %s\n" % err
	else:
		# 多演算法結果
		report += "測試結果總覽:\n\n"
		for algo in test_results.keys():
			var result = test_results[algo]
			report += "[%s]\n" % result["algorithm_name"]
			report += "  成功: %d / 失敗: %d" % [result["successful"], result["failed"]]
			if result.has("avg_execution_time"):
				report += " | 平均時間: %.2f ms" % result["avg_execution_time"]
			report += "\n"
	
	return report
