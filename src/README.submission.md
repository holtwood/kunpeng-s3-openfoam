# simpleFoam-submission

A/B profile: `@PROFILE@`

Compile defines: `@DEFINES@`

## 改动清单

只修改了 `matrices/` 下的 `.C` 实现；`simpleFoam.C`、`UEqn.H`、`pEqn.H`、
`createFields.H` 与 OpenFOAM v2606 官方文件逐字节一致。

| 文件 | 改动 | 开关 |
|---|---|---|
| `matrices/lduMatrix/lduMatrix/lduMatrixATmul.C` | 对称矩阵 `Amul/Tmul/sumA/residual` 只读一份系数 | `KUNPENG_SYMMETRIC` |
| `matrices/lduMatrix/smoothers/GaussSeidel/GaussSeidelSmoother.C` | 本地前缀扫描与接口交换重叠 | `KUNPENG_GS_OVERLAP` |
| `matrices/lduMatrix/solvers/smoothSolver/smoothSolver.C` | 复用 residual 缓冲 | `KUNPENG_REUSE_RESIDUAL` |
| `matrices/lduMatrix/solvers/GAMG/GAMGSolverSolve.C` | 最细层 fused residual | `KUNPENG_GAMG_RESIDUAL` |
| `matrices/lduMatrix/solvers/GAMG/GAMGSolverInterpolate.C` | 对称矩阵单系数数组 | `KUNPENG_SYMMETRIC` |
| `matrices/.../GAMGAgglomeration.C` | 粗层 cell 数默认值 | `KUNPENG_GAMG_COARSEST_CELLS` |
| `matrices/.../pairGAMGAgglomeration.C` | pair 聚合 mergeLevels 默认值 | `KUNPENG_GAMG_MERGE_LEVELS` |

## 为什么快

- **对称矩阵单系数数组**：对 `symmetric()` 矩阵，`lower()` 返回的就是
  `upper()`，原实现仍然加载两次。改成一次加载、两个方向复用，少一条
  load 指令。
- **GS 通信重叠**：原实现 `init` 后立刻 `update`，MPI 延迟完全暴露。
  改成先扫描不与接口相邻的 cell，再等待接口，把通信藏到计算后面。
  数学顺序不变，结果逐位一致。
- **residual 缓冲复用**：去掉热路径上的堆分配和零初始化。
- **GAMG fused residual**：用一次 `source - A*psi` 遍历替代
  `Amul + 赋值 + 相减`。
- **GAMG 粗层参数**：576 rank 下默认 10 cells/rank 会产生约 12 层，
  每层都有接口交换和全局归约。提高粗层规模、合并 pair 层可以减少往返。
  该改动会改变收敛路径，必须单独 A/B。

## 怎么验证

- 跑满 `Time = 500`；
- 所有最终残差 `< 5e-3`；
- 与基线交错运行至少 6 轮，报告中位数与 MAD；
- 语义保持的改动（P1–P4）用逐位/ULP 差分确认；
- 最终提交前用 `check_submission.sh` 检查二进制、大小和官方文件哈希。

## 未启用/已回退

（上机后填写：哪些候选没有收益、哪些导致残差变差、最终保留哪些。）
