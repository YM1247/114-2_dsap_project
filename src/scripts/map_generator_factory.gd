extends RefCounted
class_name MapGeneratorFactory

## 工廠類 - 用於創建和管理不同的演算法生成器

const ALGORITHM_DAG = "dag"
const ALGORITHM_BSP = "bsp"
const ALGORITHM_FOREST = "forest"

var available_algorithms: Array = [ALGORITHM_DAG]

## 建立指定演算法的生成器
func create_generator(algorithm: String) -> MapGeneratorBase:
	match algorithm:
		ALGORITHM_DAG:
			return MapGeneratorDAG.new()
		ALGORITHM_BSP:
			return MapGeneratorBSP.new()
		ALGORITHM_FOREST:
			return MapGeneratorForest.new()
		_:
			push_error("Unknown algorithm: %s" % algorithm)
			return MapGeneratorDAG.new()

## 獲取可用演算法列表
func get_available_algorithms() -> Array:
	return available_algorithms.duplicate()

## 註冊新演算法
func register_algorithm(algorithm_name: String) -> void:
	if not available_algorithms.has(algorithm_name):
		available_algorithms.append(algorithm_name)

## 更新可用演算法（基於實現情況）
func update_available_algorithms() -> void:
	available_algorithms = [
		ALGORITHM_DAG,
		ALGORITHM_BSP,
		ALGORITHM_FOREST
	]
