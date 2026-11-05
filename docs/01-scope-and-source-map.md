# 可改范围与热点地图

## 实际可改的代码量

`src/OpenFOAM/matrices/`：117 个 `.C`，94 个 `.H`，约 2.0 MB。

## 不在范围内、但很重要的部分

| 组件 | 位置 | 影响 |
|---|---|---|
| `fvMatrix` 组装、`A()/H()/flux()` | `src/finiteVolume/fvMatrices/` | SIMPLE 每步的矩阵组装 |
| `faceAreaPair` 几何聚合 | `src/finiteVolume/fvMatrices/solvers/GAMGSymSolver/...` | 默认 GAMG 聚合器 |
| `processorFvPatchField` 最细层打包 | `src/finiteVolume/fields/fvPatchFields/constraint/processor/` | 最细层 MPI |
| `gSumMag` / `gSumProd` | `src/OpenFOAM/fields/` | 全局归约 |
| MPI / 毕昇 / KML | 系统库 | 不可改 |

结论：能动的只有线性求解器内部的本地 face 循环、GAMG 粗层、smoother、
preconditioner、GAMG 自己的接口字段。

## 一个必须避开的路径坑

官方指南示例写的是：

```
matrices/LduMatrix/LduMatrix/LduMatrixATmul.C
```

但 v2606 的 `src/OpenFOAM/Make/files:421` 实际编译的是：

```
matrices/lduMatrix/lduMatrix/lduMatrixATmul.C
```

大写 `LduMatrix` 是另一套模板类 `Foam::LduMatrix<Type,DType,LUType>`，
不是 `simpleFoam` 用的 `Foam::lduMatrix`。照着示例改会改到死代码。

上机第一件事：

```bash
grep -n "lduMatrixATmul" "$FOAM_SRC/OpenFOAM/Make/files"
```

## 提交目录为什么包含三个 `.H`

`simpleFoam.C` 用引号包含 `createFields.H`、`UEqn.H`、`pEqn.H`，预处理器会先
在 `simpleFoam.C` 所在目录查找。这三个文件必须原样放在
`simpleFoam-submission/` 根目录，否则 `wmake` 会找不到。

它们与官方文件逐字节一致，不构成“修改头文件”。

## 提交机制

`Make/options` 加 `-Wl,--export-dynamic`，把改写后的 `.C` 和 `simpleFoam.C`
一起编进可执行文件。运行时，可执行文件的符号先于 `libOpenFOAM.so` 被查找，
从而覆盖库里的同名实现。因此：

- 只能覆盖**已有函数**；
- 不能改头文件、不能加成员变量；
- 新增逻辑只能放在被覆盖的 `.C` 内部（匿名 namespace / 文件级 static）。

## 热点调用链

```
simpleFoam
 └─ fvMatrix::solve
     ├─ GAMG（p，对称）
     │   ├─ Amul / residual                lduMatrixATmul.C
     │   ├─ Vcycle                         GAMGSolverSolve.C
     │   │   ├─ GaussSeidel smooth          GaussSeidelSmoother.C
     │   │   ├─ restrictField               GAMGAgglomerationTemplates.C
     │   │   ├─ scale → Amul + 全局归约      GAMGSolverScale.C
     │   │   ├─ interpolate                 GAMGSolverInterpolate.C
     │   │   └─ 粗层 PCG                     PCG.C
     │   └─ 最细层再一次 Amul + residual
     └─ smoothSolver（U/k/omega，非对称）
         ├─ symGaussSeidel smooth           symGaussSeidelSmoother.C
         └─ residual + gSumMag              smoothSolver.C
```

## 已确认的源码事实

- `Amul/Tmul/residual/sumA/GS/interpolate` 都是 const 成员函数；
  它们调用的 `lower()` 是 **const 重载**，对对称矩阵直接返回 `upperPtr_`，
  **不会复制**。之前“每步复制 lower”的判断是错误的。
- `GaussSeidelSmoother` 当前是 `init → 立即 update → 整段 sweep`，
  每次 sweep 的 MPI 延迟完全暴露。
- 默认 `commsType = nonBlocking`，`nPollProcInterfaces = 0`。
- GAMG 默认 `nCellsInCoarsestLevel = 10`、`mergeLevels = 1`。
  576 rank 时最粗层约 5760 个全局 cell，约 12 层。
- `nonBlockingGaussSeidelSmoother` 已存在于源码中，说明“边界 cell 排在最后、
  先算本地再等接口”的假设是官方认可的。
