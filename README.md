# 鲲鹏 S3 · 流体力学应用优化（OpenFOAM v2606 / simpleFoam）

> Part of [holtwood-arena](https://github.com/holtwood-arena) · 比赛与 benchmark 归档

> ⚠️ **项目状态：已归档（2026-11-05）**
>
> 本仓库是 S3 赛季 OpenFOAM 赛题的调研与实现存档。**未参赛、未上机、未产生任何平台成绩。**
>
> **归档原因**：求职面试时间冲突，主动放弃 S3，精力转向 CPU 算子级性能优化
> （见 [`kunpeng-s2-conv`](https://github.com/holtwood-arena/kunpeng-s2-conv)）。
>
> **保留价值**：完整的赛题拆解、可修改范围分析、7 个候选优化的宏开关实现与 A/B 协议，
> 可作为「HPC 应用级优化」的调研样本。
>
> **重要边界**：本仓库所有结论均来自**静态源码分析**，未经编译、未经实测。
> 任何性能推断都不构成已验证事实。

本仓库记录赛题 `OpenFOAM simpleFoam 性能优化` 的调研过程与实现存档。

- 目标源码：官方 OpenFOAM v2606
- 源码身份：`OpenFOAM-v2606.tgz`
  SHA256 `2a1310e3ed192cc4c521e1d22dcc176f57bec61160c878dc4348f21d6672294d`
  内部 commit `481094fdf34f11ed6d0d603ee59a858a0124236d`
- 算例：官方 DrivAer 21M，500 步，576 核
- 成绩：最后一条 `ExecutionTime / 500`
- 正确性：`Time = 500`，最终残差全部 `< 5e-3`

> 当前状态：源码改造、提交骨架、脚本已写好；**尚未编译、尚未上机**。
> 本机不执行任何构建，等目标环境。

## 目录

```
src/          可直接组装为 simpleFoam-submission 的源码
  simpleFoam.C / UEqn.H / pEqn.H / createFields.H   （官方原文，未改）
  matrices/...                                     （改写后的 .C）
  Make/                                             （files + options 模板）
reference/    官方原文副本，仅用于 diff 复核
scripts/      assemble / check / selftest / diff
docs/         赛题事实、范围、候选优化、基线协议、面试讲法
submission/   assemble.sh 生成的提交目录（不入库）
```

> 不要在 `src/` 里直接 `wmake`：`src/Make/options.in` 是模板，
> 必须先用 `assemble.sh` 生成提交目录。

## 快速开始

```bash
# 1. 组装某个 A/B 档位（不编译）
./scripts/assemble.sh baseline
./scripts/assemble.sh p1
./scripts/assemble.sh p1p2
./scripts/assemble.sh p1p2p3p4
./scripts/assemble.sh diag      # P2 + blockStart 诊断
./scripts/assemble.sh p5
./scripts/assemble.sh all

# 2. 静态检查
./scripts/check_submission.sh

# 3. 看源码相对官方的差异
./scripts/diff_sources.sh

# 4. 到目标机器后（先 source 官方环境）
cd submission/simpleFoam-submission
wclean && wmake -j 16
ls -l "$FOAM_USER_APPBIN/simpleFoam"
```

## 编译期开关

所有改动默认关闭；`assemble.sh` 通过 `-D` 打开，便于 A/B 归因。

| 宏 | 作用 |
|---|---|
| `KUNPENG_SYMMETRIC` | 对称矩阵只读一份系数 |
| `KUNPENG_GS_OVERLAP` | Gauss-Seidel 前缀扫描与接口交换重叠 |
| `KUNPENG_REUSE_RESIDUAL` | `smoothSolver` 复用 residual 缓冲 |
| `KUNPENG_GAMG_RESIDUAL` | GAMG 外层用 fused residual 少一遍遍历 |
| `KUNPENG_GAMG_COARSEST_CELLS` | GAMG 粗层每 rank 最少 cell 数（默认 10） |
| `KUNPENG_GAMG_MERGE_LEVELS` | pair 聚合合并层数（默认 1） |

前四个是语义保持的实现优化；后两个会改变收敛路径，必须单独 A/B。

## 重要约束

1. **只能改 `.C`**。`simpleFoam.C` 和所有 `.H` 必须与官方逐字节一致。
2. 提交物只包含源码；不得有 `.so/.a/.o`/可执行文件；≤ 30 MB。
3. 提交机制是把改写的 `.C` 编进可执行文件，用 `-Wl,--export-dynamic` 覆盖
   `libOpenFOAM.so` 的同名符号。
4. 自测是 4 小时、576 核、`Allrun-solve` 内置绑核。
5. 以最后一次提交成绩为准，未验证的版本不提交。

详见 `docs/`。

## 仓库与迁移

- GitHub：`holtwood-arena/kunpeng-s3-openfoam`（public）
- 服务器克隆：

```bash
git clone git@github.com:holtwood-arena/kunpeng-s3-openfoam.git
# 或
git clone https://github.com/holtwood-arena/kunpeng-s3-openfoam.git
```

- 如果服务器访问不了 GitHub，用本机生成的 bundle：

```bash
# 本机
git bundle create kunpeng-s3-openfoam.bundle --all

# 传到服务器后
git clone kunpeng-s3-openfoam.bundle kunpeng-s3-openfoam
```

- 新机器上继续开发：

```bash
cd kunpeng-s3-openfoam
./scripts/assemble.sh baseline
```
