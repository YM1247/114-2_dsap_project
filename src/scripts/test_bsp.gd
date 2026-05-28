extends Node

## BSP 演算法測試腳本
## 可在 Godot 編輯器中執行進行驗證

func _ready():
	print("=== BSP 演算法測試開始 ===\n")
	
	test_bsp_generation()
	test_bsp_connectivity()
	test_bsp_vs_dag()

func test_bsp_generation():
	print("[Test 1] BSP 生成測試")
	print("-" * 40)
	
	var generator = MapGeneratorBSP.new()
	generator.floors = 8
	generator.columns = 7
	
	var map_data = generator.generate_map()
	
	var nodes = map_data["nodes"]
	var floors_to_nodes = map_data["floors"]
	
	print("✓ 地圖生成成功")
	print("  總節點數: %d" % nodes.size())
	print("  樓層數: %d" % floors_to_nodes.size())
	
	# 統計各層節點數
	var layer_stats = "  各層節點數: "
	for floor_idx in range(floors_to_nodes.size()):
		layer_stats += "%d " % floors_to_nodes[floor_idx].size()
	print(layer_stats)
	
	# 統計邊數
	var total_edges = 0
	for node_id in nodes.keys():
		total_edges += nodes[node_id]["next"].size()
	print("  總邊數: %d" % total_edges)
	
	print()

func test_bsp_connectivity():
	print("[Test 2] BSP 連通性驗證")
	print("-" * 40)
	
	var generator = MapGeneratorBSP.new()
	generator.floors = 10
	
	var success_count = 0
	var total_tests = 10
	
	for i in range(total_tests):
		var map_data = generator.generate_map()
		var connectivity = generator.verify_connectivity(map_data)
		
		if connectivity["is_valid"]:
			success_count += 1
		else:
			print("✗ 第 %d 次生成失敗:" % (i + 1))
			print("  孤立節點: %s" % connectivity["isolated_nodes"])
			print("  無法到達 Boss 的起點: %s" % connectivity["start_without_boss_path"])
	
	print("✓ 連通性驗證完成: %d/%d 通過 (%.1f%%)" % [success_count, total_tests, float(success_count) / float(total_tests) * 100])
	print()

func test_bsp_vs_dag():
	print("[Test 3] BSP vs DAG 對比")
	print("-" * 40)
	
	var bsp_gen = MapGeneratorBSP.new()
	var dag_gen = MapGeneratorDAG.new()
	
	# 配置相同
	bsp_gen.floors = 10
	dag_gen.floors = 10
	bsp_gen.columns = 7
	dag_gen.columns = 7
	
	# 測試多次
	var bsp_times = []
	var dag_times = []
	var test_count = 5
	
	print("執行 %d 次生成測試..." % test_count)
	
	for i in range(test_count):
		# 測試 BSP
		var start_bsp = Time.get_ticks_msec()
		var bsp_map = bsp_gen.generate_map()
		var end_bsp = Time.get_ticks_msec()
		bsp_times.append(end_bsp - start_bsp)
		
		# 測試 DAG
		var start_dag = Time.get_ticks_msec()
		var dag_map = dag_gen.generate_map()
		var end_dag = Time.get_ticks_msec()
		dag_times.append(end_dag - start_dag)
	
	# 計算統計數據
	var bsp_avg = _calculate_average(bsp_times)
	var dag_avg = _calculate_average(dag_times)
	var bsp_nodes_avg = _get_avg_node_count(bsp_gen, test_count)
	var dag_nodes_avg = _get_avg_node_count(dag_gen, test_count)
	
	print("\n📊 性能對比:")
	print("  BSP:")
	print("    平均執行時間: %.2f ms" % bsp_avg)
	print("    平均節點數: %.1f" % bsp_nodes_avg)
	print("  DAG:")
	print("    平均執行時間: %.2f ms" % dag_avg)
	print("    平均節點數: %.1f" % dag_nodes_avg)
	print()
	if bsp_avg < dag_avg:
		print("  ⚡ BSP 更快 (快 %.0f%%)" % ((dag_avg - bsp_avg) / dag_avg * 100))
	else:
		print("  🐢 DAG 更快 (快 %.0f%%)" % ((bsp_avg - dag_avg) / bsp_avg * 100))
	
	print()
	print("=== 測試完成 ===\n")

func _calculate_average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum: float = 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())

func _get_avg_node_count(generator: MapGeneratorBase, test_count: int) -> float:
	var total = 0
	for i in range(test_count):
		var map_data = generator.generate_map()
		total += map_data["nodes"].size()
	return float(total) / float(test_count)
