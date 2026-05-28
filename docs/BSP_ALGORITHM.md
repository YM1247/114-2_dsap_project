# BSP 演算法實現詳解

## 📋 概述

BSP（Binary Space Partition）演算法實現了一個**遞迴空間分割**的地圖生成器。核心特點是通過不斷將地圖空間切分成子區域，最終在每個子區域內生成節點，形成自然的視覺聚類。

---

## 🏗️ 實現架構

### 1. **BSPRegion 類**

代表一個矩形區域（潛在的葉子節點）。

```gdscript
class BSPRegion:
    var x_min: float      # 區域左邊界
    var x_max: float      # 區域右邊界
    var y_min: float      # 區域下邊界
    var y_max: float      # 區域上邊界
    var depth: int        # 遞迴深度
```

**為什麼需要這個類？**
- 便於追蹤區域的邊界
- 方便計算區域尺寸，判斷是否需要繼續切割
- 清晰的數據結構

---

## 🔄 核心演算法流程

### **Step 1: 遞迴分割空間** `_partition_space()`

```
輸入: 初始區域 (0, 0) ~ (columns, floors)
輸出: 葉子區域列表

遞迴過程:
┌─────────────────────────────┐
│  如果深度 >= max_depth       │
│  或 寬度/高度 < min_size     │
│  ⟹ 加入輸出 (終止)          │
└─────────────────────────────┘
                ↓
┌─────────────────────────────┐
│  隨機選擇垂直或水平切割      │
└─────────────────────────────┘
         ↙            ↘
  垂直切割 (沿x軸)  水平切割 (沿y軸)
  在 x_min~x_max    在 y_min~y_max
  中隨機選 cut_x    中隨機選 cut_y
         ↙            ↘
  [左區域] [右區域]  [上區域] [下區域]
         ↓            ↓
  遞迴分割左右      遞迴分割上下
```

**關鍵參數：**
- `min_region_size = 15.0` - 最小區域尺寸（防止過度分割）
- `max_recursion_depth = 3` - 最大深度（控制分割層級）

**代碼邏輯：**

```gdscript
func _partition_space(region: BSPRegion, output: Array) -> void:
    # 終止條件
    if region.depth >= max_recursion_depth or \
       region.width() < min_region_size or \
       region.height() < min_region_size:
        output.append(region)  # 葉子節點
        return
    
    # 隨機選擇方向
    var cut_vertical: bool = randf() > 0.5
    
    if cut_vertical:
        # 沿 x 軸切割
        var cut_x = randf_range(
            region.x_min + min_region_size * 0.5,
            region.x_max - min_region_size * 0.5
        )
        var left = BSPRegion.new(region.x_min, cut_x, ...)
        var right = BSPRegion.new(cut_x, region.x_max, ...)
        
        _partition_space(left, output)   # 遞迴左
        _partition_space(right, output)  # 遞迴右
    else:
        # 沿 y 軸切割 (類似)
        ...
```

### **Step 2: 區域映射到樓層**

每個區域的 y 坐標對應不同的樓層：

```
y_max (樓層 0)     ┌─────────────────┐ ← 上層
       ↑           │   Region 1      │
       │           │ (y=0.7~1.0)     │
       │           ├─────────────────┤
y=0.5  │           │   Region 2      │
(樓層5)│           │ (y=0.3~0.7)     │
       │           ├─────────────────┤
       │           │   Region 3      │
y_min  ↓           │ (y=0~0.3)       │ ← 下層
       (樓層9)     └─────────────────┘

轉換公式:
floor = int((1.0 - region.y_min / floors) * (floors - 1))
```

### **Step 3: 生成節點**

在每個區域內隨機生成 1-3 個節點：

```gdscript
for region in regions:
    var region_floor = map_y_to_floor(region.y_min)
    
    # 在該區域隨機生成 1-3 個節點
    var nodes_in_region = randi_range(1, nodes_per_region)
    
    for i in range(nodes_in_region):
        var x = randf_range(region.x_min, region.x_max)
        var y = randf_range(region.y_min, region.y_max)
        var col = int(x)  # 轉換為列號
        
        create_node(
            id=next_node_id,
            floor=region_floor,
            column=col,
            type="combat"  # 暫時
        )
```

**為什麼是 1-3 個？**
- 1 個：保證稀疏（視覺清晰）
- 3 個：保證分支（決策機會）

### **Step 4: 連接樓層 & Step 5: 分配類型**

這部分複用 DAG 的邏輯，確保：
- 層級連接（下層連到上層）
- 無環（拓樸排序）
- 無連續 camp
- 連通性

---

## 💡 BSP vs DAG 的關鍵差異

| 方面 | DAG | BSP |
|------|-----|-----|
| **連接策略** | 按距離 + 交叉檢查 | 按距離（區域天然分組） |
| **節點分佈** | 均勻隨機 | 聚集在區域內 |
| **視覺感受** | 分散 | 聚集、區域化 |
| **交叉控制** | 主動檢查 | 被動受益 |

---

## 🧪 測試與驗證

### 運行測試

在 Godot 編輯器中：
1. 建立 Node，附加 `test_bsp.gd` 腳本
2. 播放場景
3. 在輸出面板查看測試結果

### 預期輸出

```
[Test 1] BSP 生成測試
✓ 地圖生成成功
  總節點數: 28
  樓層數: 10
  各層節點數: 1 3 2 2 3 2 2 3 2 1
  總邊數: 31

[Test 2] BSP 連通性驗證
✓ 連通性驗證完成: 10/10 通過 (100.0%)

[Test 3] BSP vs DAG 對比
  BSP:
    平均執行時間: 2.45 ms
    平均節點數: 27.4
  DAG:
    平均執行時間: 1.89 ms
    平均節點數: 27.8
```

---

## 🎨 視覺特性分析

### BSP 生成的地圖特點

**優勢：**
1. **天然聚類** - 節點在區域內聚集
2. **層級感強** - 區域邊界清晰
3. **視覺美觀** - 交叉少

**劣勢：**
1. **隨機性** - 分割點隨機，可能不平衡
2. **路徑多樣性** - 低於隨機森林
3. **決策品質** - 中等（取決於聚類效果）

### 調整參數以改進

```gdscript
# 更多層級 → 更多節點
max_recursion_depth = 4  # (3 → 4)

# 更小區域 → 更多節點
min_region_size = 10.0   # (15.0 → 10.0)

# 每區域更多節點 → 更密集
nodes_per_region = 3     # (2 → 3)
```

---

## 🔗 與 DAG 的集成

BSP 仍然使用 DAG 的連接和類型分配邏輯：

```
BSP 特有部分          DAG 複用部分
  ├─ 空間分割           ├─ 層級連接
  ├─ 區域映射    →      ├─ 類型分配
  └─ 節點生成           └─ 連通性驗證
```

這確保了 **最大相容性** 和 **最小開發成本**。

---

## ⚡ 性能特性

| 指標 | 值 | 備註 |
|------|-----|------|
| 生成時間 | 2-5ms | 根據參數 |
| 記憶體用量 | 低 | 區域存儲臨時 |
| 可擴展性 | 高 | 參數調整容易 |

---

## 🚀 下一步優化方向

1. **動態調整區域尺寸** - 基於樓層數
2. **區間連接優化** - 考慮區域鄰接性
3. **重複節點去重** - 鄰近區域的重疊
4. **視覺佈局** - 力導向圖優化

---

## 📚 相關課程概念

- **遞迴分治** (Divide & Conquer) - 空間分割核心
- **樹結構** - 分割樹的構建
- **圖論** - DAG 連接與驗證
- **幾何計算** - 區域邊界與坐標轉換
