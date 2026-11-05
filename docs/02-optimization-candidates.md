# 候选优化清单

所有改动默认关闭，由 `assemble.sh` 通过 `-D` 打开。

## 总表

| # | 宏 | 改动位置 | 预期 | 风险 | 数学等价 | 通用技术 | 面试价值 |
|---|---|---|---|---|---|---|---|
| P1 | `KUNPENG_SYMMETRIC` | `lduMatrixATmul.C`、`GAMGSolverInterpolate.C` | 小 | 极低 | 是（逐位） | 消除冗余 load | 低 |
| P2 | `KUNPENG_GS_OVERLAP` | `GaussSeidelSmoother.C` | 中 | 中低 | 是（逐位） | latency hiding / pipelining | 高 |
| P3 | `KUNPENG_REUSE_RESIDUAL` | `smoothSolver.C` | 小 | 极低 | 是 | 热路径去分配 | 中 |
| P4 | `KUNPENG_GAMG_RESIDUAL` | `GAMGSolverSolve.C` | 小 | 极低 | 浮点顺序略变 | loop fusion | 中 |
| P5 | `KUNPENG_GAMG_COARSEST_CELLS` / `KUNPENG_GAMG_MERGE_LEVELS` | `GAMGAgglomeration.C`、`pairGAMGAgglomeration.C` | 中高 | 中 | 否，改变收敛路径 | 分层聚合 / 减少往返 | 高 |
| P6 | 未实现 | `masterCoarsestGAMGProcAgglomeration` | 高（理论） | 高 | 否 | 缩小 communicator | 高 |
| P7 | 未实现 | `Make/options` | 小 | 低 | 是 | 编译选项 / ISA | 中 |
| P8 | 未实现 | 手写 NEON/SVE | 不确定 | 高 | 需验证 | SIMD / roofline | 高 |

## P1：对称矩阵单系数数组

**事实**：对对称矩阵，`lowerPtr_` 为空，const `lower()` 返回 `upperPtr_`，
两个指针指向同一数组。

**改动**：在 `Amul/Tmul/sumA/residual/interpolate` 的 face 循环里，
`symmetric()` 时只加载一次 `coeff = upper[face]`，两个方向复用。

**为什么可能快**：少一条 load 指令；同一 cache line 的第二次访问虽然命中 L1，
但仍占 load port。

**为什么收益有限**：不是减少 DRAM 流量，只是减少指令数。预期 1–5%。

**正确性**：同一份 double 参与同样的两次乘加，结果逐位相同。

## P2：Gauss-Seidel 前缀扫描与接口交换重叠

**现状**：

```cpp
initMatrixInterfaces(...);     // 发出 Isend/Irecv
updateMatrixInterfaces(...);   // 立刻 wait
for (cell = 0; cell < nCells; ++cell) { ... }
```

本地 sweep 完全在通信之后，MPI 延迟无法被计算掩盖。

**改动**：

```cpp
initMatrixInterfaces(...);     // 发出
for (cell = 0; cell < blockStart; ++cell) { ... }   // 纯本地，先算
updateMatrixInterfaces(...);   // wait
for (cell = blockStart; cell < nCells; ++cell) { ... }
```

`blockStart` 是所有接口 patch 的 `patchAddr` 最小值。`[0, blockStart)` 的 cell
不与任何耦合接口相邻，`updateMatrixInterfaces` 不会写它们；因此前缀扫描的结果
与“先 update 再整段 sweep”完全一致。

**与官方实现的关系**：`nonBlockingGaussSeidelSmoother` 已采用同样的假设。
本改动把它做进默认的 `GaussSeidelSmoother`，并在 `commsType` 不是
`buffered/nonBlocking` 时自动回退。

**收益条件**：`blockStart > 0` 且接口 cell 在局部编号中靠后。
如果 `blockStart == 0`，退化为原实现，无收益但也无损失。

**安全边界**：只对 `processor` / `processorCyclic` 接口启用。
`cyclic`/`AMI` 的 `updateInterfaceMatrix` 会直接读 `psi` 的邻接 patch cell，
虽然理论上这些 cell 都在 `blockStart` 之后，但为了不依赖这个假设，
遇到其它接口类型直接回退原顺序。

**第一轮先测**：

```bash
./scripts/assemble.sh diag
```

它会打印一次 `KUNPENG_GS blockStart = X / N allowOverlap = 1`。
如果 `X` 很小（例如 < 5% N），P2 没有多少重叠空间，应直接放弃，
不要在上面继续投入。

**成本**：每次 `smooth()` 调用多一次 O(接口 face 数) 的 `min` 扫描，
相对整段 sweep 可忽略。

## P3：smoothSolver 复用 residual 缓冲

**现状**：外层每次迭代 `residual = matrix_.residual(...)`，每次分配一个新的
`solveScalarField`，并且 `Field` 构造会零初始化，而 residual 会覆盖每个元素。

**改动**：预分配 `residual(psi.size())`，调用 in-place 重载。

**收益**：去掉热路径上的 malloc/free 和一次 memset。分配器竞争在 576 rank
下可能被放大，但我没有实测数据。

## P4：GAMG 外层 fused residual

**现状**：

```cpp
matrix_.Amul(Apsi, psi, ...);
finestResidual = tsource();
finestResidual -= Apsi;
```

两次全 cell 遍历 + 一次临时赋值。

**改动**：改为 `matrix_.residual(finestResidual, psi, source, ...)`，
一次遍历完成 `source - A*psi`。

**注意**：`Apsi` 在之后只作为 `Vcycle` 的 scratch，进入 `interpolate` 时会
先 `Apsi = 0`，所以不再预先更新它是安全的。

## P5：GAMG 粗层参数

**背景**：`continueAgglomerating` 的条件是

```
nTotalCoarseCells < nProcs * nCellsInCoarsestLevel
```

`nCellsInCoarsestLevel` 是**每 rank** 的值。576 rank、默认 10 时，最粗层约
5760 个全局 cell，从 21M 到 5760 约 12 层。每层至少一次接口交换 + 若干次
全局归约。

**改动**：

- `KUNPENG_GAMG_COARSEST_CELLS` 默认 10，实验值 128；
- `KUNPENG_GAMG_MERGE_LEVELS` 默认 1，实验值 2。

**风险**：减少层数会改变粗层修正的质量，可能增加 V-cycle 次数或改变最终残差
轨迹。必须单独 A/B，并检查最终残差和迭代次数。

**规则判断**：这是实现内部的默认策略，不是修改算例配置。但如果官方
`fvSolution` 显式写了这两个键，宏不会生效。

## P6/P7/P8：暂不实现

- **P6 processor agglomeration**：`GAMGAgglomeration.C` 目前只在配置显式指定
  `processorAgglomerator` 时启用。改成默认启用会引入矩阵 gather/scatter，
  复杂度和风险都高，等 P5 有数据后再评估。
- **P7 编译选项**：官方 wmake 规则是 `-O3`，没有 `-mcpu`。可以在
  `Make/options` 里加 `-mcpu=tsv110` 或用函数级
  `__attribute__((target(...)))`。收益通常小于算法级改动。
- **P8 NEON/SVE**：face 循环是间接寻址 + scatter，NEON 没有 gather，
  收益不确定；SVE 需要平台支持。没有 profile 不做。

## 明确不做的事

- 不修改计时、日志、环境变量。
- 不缓存结果、不跳过迭代、不针对 DrivAer 的固定尺寸写死。
- 不通过“少算”换性能；所有候选必须在 `Time = 500` 和残差门禁下验证。
