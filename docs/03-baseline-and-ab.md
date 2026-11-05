# 基线、Profiling 与 A/B 协议

> 本文件是上机后的执行清单。当前仓库没有编译过任何东西。

## Phase 0：环境固化

在目标机器上记录：

```bash
grep -n "lduMatrixATmul" "$FOAM_SRC/OpenFOAM/Make/files"
which simpleFoam
simpleFoam -help 2>&1 | head -5
echo "$WM_OPTIONS"
clang++ --version 2>/dev/null || bisheng --version 2>/dev/null || g++ --version
mpirun --version | head -3
```

保存：

- `simpleFoam.C`、`UEqn.H`、`pEqn.H`、`createFields.H` 的 SHA256；
- `Make/options` 的实际内容；
- 编译日志；
- `FOAM_USER_APPBIN/simpleFoam` 的 `ldd` 结果。

## Phase 1：基线

用官方 `simpleFoam` 和官方 `of_21M_template.tar.gz` 跑一轮完整 500 步。

记录：

- 最后一条 `ExecutionTime` 和 `ExecutionTime/500`；
- 每一步的 `Time =` 数量（应为 500）；
- 每个 field 的最终残差（`Ux/Uy/Uz/p/k/omega` 或实际字段）；
- 每个 solver 的迭代次数（从日志的 `Solving for ... No Iterations` 统计）；
- 总 wall time 和 MPI rank 数。

基线至少 3 轮。不要用单次最快值。

## Phase 2：Profiling

优先级从高到低：

1. **OpenFOAM 内置 profiling**
   在**诊断副本**的 `system/controlDict` 里临时加：

   ```cpp
   profiling
   {
       active      true;
       cpuInfo     false;
       memInfo     false;
       sysInfo     false;
   }
   ```

   注意：这只用于诊断，不进入提交，也不用于最终成绩。

2. **perf**
   ```bash
   perf stat -e cycles,instructions,cache-misses,LLC-load-misses,\
   branch-misses,stalled-cycles-frontend,stalled-cycles-backend \
   -p <pid> sleep 30
   ```
   如果集群允许，`perf record -g` 采 30–60 秒，生成火焰图。

3. **MPI 占比**
   对比 `ExecutionTime` 与 `perf` 的 user time；或使用 MPI 自带的
   profiling/tracing（如果环境提供）。

要回答的问题：

- `matrices/` 里的函数占总时间多少？
- GAMG 粗层（level >= 6）占多少？
- GS sweep 和接口交换各占多少？
- 最细层 `Amul/residual` 的 IPC 和 cache miss 是多少？
- 576 rank 下每步的 MPI 时间是否随 rank 数超线性增长？

如果 `matrices/` 占比低于 20%，本题上限很低，应优先确认是否还有其它
可改空间，而不是继续微调循环。

## Phase 3：A/B

### 档位

```bash
./scripts/assemble.sh baseline     # 原实现 + --export-dynamic
./scripts/assemble.sh p1           # P1
./scripts/assemble.sh p1p2         # P1+P2
./scripts/assemble.sh p1p2p3p4     # P1..P4
./scripts/assemble.sh p5           # P5（单独）
./scripts/assemble.sh all          # 全部
```

每次只增加一个变量，便于归因。

### 运行

- 同一节点、同一队列、同一 `Allrun-solve`、同一 rank 数；
- 基线与候选**交错**运行：B, C, B, C, B, C …；
- 每个档位至少 6 轮；
- 记录每轮的 `ExecutionTime` 和最终残差；
- 不要挑最快的一次；报告 median 和 MAD。

### 验收门禁

每个候选必须同时满足：

1. `Time = 500`；
2. 所有最终残差 `< 5e-3`；
3. 无 NaN/Inf；
4. 相对基线的 median 改善大于噪声（建议 > 2%，且 6 轮中至少 5 轮同向）；
5. `simpleFoam.C` 和所有 `.H` 与官方逐字节一致；
6. 提交目录无二进制、≤ 30 MB。

### 止损条件

出现以下任一情况，回退该候选：

- 最终残差逼近 5e-3 或出现震荡；
- V-cycle/迭代次数显著增加，抵消了单次成本下降；
- 6 轮 A/B 的方向不一致；
- 需要修改头文件或算例配置才能生效；
- 只能对 21M/576 这一组参数生效，缺乏泛化解释。

## Phase 4：提交

```bash
./scripts/assemble.sh all
./scripts/check_submission.sh
tar -czf simpleFoam-submission.tar.gz -C submission simpleFoam-submission
```

按官方要求补 `manifest.json`，队伍 ID 由平台分配。

提交前最后确认：

- `grep -c '^Time = '` 为 500；
- `grep -E '^ExecutionTime' | tail -1` 是预期成绩；
- 残差全部达标；
- 提交的是源码，不是二进制。
