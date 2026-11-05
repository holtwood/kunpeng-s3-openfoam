# 面试讲法：从“CFD 调参”到“低层性能工程”

## 先说实话

这个项目是**通用方法论 + 专用落点**。

- 通用：基线、profiling、roofline、cache/带宽、延迟隐藏、减少同步、
  实验设计、回归门禁。
- 专用：LDU 存储、Gauss-Seidel、GAMG 聚合、OpenFOAM 残差语义、MPI halo。

对互联网岗位的匹配度：

| 岗位 | 匹配度 | 说明 |
|---|---|---|
| 业务后端（Java/Go、p99） | 中低 | 方法可迁移，场景不匹配 |
| 基础架构 / 中间件 | 高 | 通信、扩展性、内存带宽 |
| 数据库 / 存储内核 | 高 | cache-friendly、memory-bound、SIMD |
| 编译器 / 运行时 | 高 | ISA、代码生成、性能模型 |
| ML Systems / 推理 | 高 | kernel、带宽、SIMD |
| HPC / CAE | 极高 | 直接对口 |

如果目标是纯业务后端，这个项目是加分项，不是决定项。
如果目标是性能优化工程师、基础架构、数据库内核、推理加速，它很对口。

## 三个故事

### 故事 1：定位

> 576 核、21M 网格、500 步，端到端约 0.8 s/step。我先建立可复现基线，
> 再用 OpenFOAM 内置 profiling 和 perf 拆时间。结果不是直觉上的矩阵组装，
> 而是 GAMG 粗层的接口交换和 Gauss-Seidel sweep 占了主要部分。

要能给出：

- 总时间、每步时间、每步的 solver 迭代次数；
- `matrices/` 占比、GAMG 各层占比、MPI 占比；
- IPC、cache miss、stall 计数；
- 为什么这些数字支持你的下一步。

通用能力：`perf`、火焰图、roofline、Amdahl、strong scaling。

### 故事 2：优化

> GS 每次 sweep 都是 `init → 立刻 wait → 再计算`，MPI 延迟完全暴露。
> 我把它改成“先算不与 halo 相邻的 cell，再 wait，再算边界 cell”。
> 数学顺序不变、结果逐位一致，但把通信藏到了计算后面。

要能给出：

- 改动的 20 行代码；
- 为什么 `[0, blockStart)` 不受接口影响；
- `commsType` 不是 nonBlocking/buffered 时怎么回退；
- 6 轮交错 A/B 的 median 和 MAD；
- 失败/回退的候选。

通用能力：**latency hiding、pipelining、async I/O、批处理**。
在互联网后端可以类比为“同步 RPC 等待”改成“先做本地可做的活，再收结果”。

GAMG 那条对应：**减少调用链层数、减少 RPC 往返、分层聚合**。

### 故事 3：守门

> 每个候选都和基线交错跑 6 轮；用逐位/ULP 差分确认数学等价；
> 用 `Time = 500` 和最终残差 `< 5e-3` 做正确性门禁；不用单次最快值。

通用能力：实验设计、统计显著性、差分测试、回归控制。

## 概念映射表

| 赛题里的东西 | 面试里的通用说法 |
|---|---|
| GS 前缀扫描 + 接口交换 | 计算与 I/O 重叠、pipeline、async |
| GAMG 粗层减少 | 减少调用链层数、减少 RPC 往返、分层聚合 |
| 对称矩阵单系数数组 | 消除冗余内存读、cache-friendly layout |
| residual 缓冲复用 | 热路径去分配、对象池 |
| Amul + residual 融合 | loop fusion、减少 pass、减少带宽 |
| 576 rank 扩展性 | strong scaling、surface-to-volume、Amdahl |
| 逐位差分 | differential testing、等价性证明 |
| 6 轮交错 A/B | 实验设计、噪声控制、置信度 |

## 面试官可能追问

**Q：为什么 576 核不是线性扩展？**
A：每个 rank 的 cell 数降到约 36k，halo/volume 比上升；GAMG 粗层的
全局同步次数随层数增加；全局归约的延迟不随本地计算量下降。
可用 surface-to-volume 和 `T = T_compute + T_comm` 的模型解释。

**Q：你怎么证明快的是你的改动，不是机器噪声？**
A：同节点、同队列、同 rank 数；基线和候选交错跑 6 轮；看 median 和 MAD；
要求 6 轮中至少 5 轮同向；同时看迭代次数是否变化。

**Q：为什么不用 GPU？**
A：赛题限定单节点 576 核、只允许改 `matrices/`，不能改求解器框架和算例；
GPU 端口不在可交付范围内。

**Q：这个优化对别的算例有效吗？**
A：P1/P2/P3/P4 是语义保持的实现优化，对所有矩阵都成立；
P5 是对大 rank 数下 GAMG 层数的通用启发式，但需要按 rank 数和
local cell 数做泛化验证。我们不会针对 21M/576 写死。

**Q：如果让你优化一个 Java 服务，你会怎么做？**
A：同一套方法，换工具。先用 p99 分解定位（GC、锁、syscall、下游 RPC、
队列），再用 async-profiler / JFR / eBPF 采样；区分 CPU-bound、
memory-bound、lock-bound、I/O-bound；然后做批处理、缓存、异步化、
减少往返；最后用交错 A/B 和错误率/延迟门禁验证。

**Q：你最大的失败是什么？**
A：准备一个真实的被否掉的候选。例如 P1 的“避免 lower 复制”一开始被认为
收益很大，后来读源码发现 const `lower()` 本来就不复制，只剩一条 load 的
收益，于是降级为微优化。这体现你会用证据修正判断。

## 建议补充的材料

1. **microbenchmark harness**：把 `Amul` 和 GS sweep 抽出来，构造合成 LDU
   矩阵，测 GB/s、GFLOP/s、IPC、cache-miss，和 roofline 对比。
2. **扩展性曲线**：72/144/288/576 rank 的 step time 和并行效率。
3. **2–3 页 performance report**：基线、profile、假设、改动、A/B 表、
   被否掉的方案、泛化性论证。

这三样不在提交物里，但它们是面试时最能证明“你会做性能工程”的材料。

## 一句话版本

> 我在一个 576 核 MPI 应用上，从零建立可复现基线，用 profiling 定位到
> 粗层同步和 smoother 的通信暴露，做了语义保持的延迟隐藏和分配消除，
> 用逐位差分和 6 轮交错 A/B 证明收益；这套方法可以直接迁移到服务端
> 的延迟分解和异步化。
