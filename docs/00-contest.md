# 赛题事实（S3 · 流体力学应用优化）

## 评分

| 项 | 值 |
|---|---|
| 软件 | OpenFOAM v2606，`simpleFoam` |
| 算例 | 官方 DrivAer 21M，预处理完成，直接求解 500 步 |
| 资源 | 单节点 576 核 |
| 成绩 | 求解日志最后一条 `ExecutionTime ÷ 500`，越小越好 |
| 正确性 | 跑满 `Time = 500`，最终残差全部 `< 5e-3` |
| 时限 | 自测 4 小时 |
| 提交 | `simpleFoam-submission/` 源码目录，含 `Make/{files,options}` |
| 禁止 | `.so/.a/.o`/可执行文件；包 ≤ 30 MB |
| 排名 | 可多次提交，以最后一次为准 |

## 可改范围

只允许修改 `$FOAM_SRC/OpenFOAM/matrices/` 下的源文件；复制进提交目录后改。

- 函数签名不可改。
- `simpleFoam.C`、`*.H` 等官方文件必须保持原样（判题逐字节比对）。
- 不能改其它目录、第三方/MPI 库、算例与配置。

## 红线

- 不得硬编码答案、预计算、跳过核心计算。
- 不得只对特定输入正确；优化必须具备泛化能力。
- 不得缓存结果或多次运行挑最快。
- 不得篡改计时器、评分脚本、结果文件、环境变量。
- 不得调用系统命令、读写隐藏文件、篡改评测环境。

## 官方环境（来自《OpenFOAM 编译与提交指南》）

> 路径中的 `<env-user>` 是比赛方环境里的账号名，已脱敏处理。

```bash
source /home/share/<env-user>/s3/env-build/init.sh --quiet
export MY_SUFFIX=_bisheng_native
source /home/share/<env-user>/s3/data/OpenFOAM-v2606/etc/bashrc
export FOAM_EXTRA_LDFLAGS="-L/home/share/<env-user>/s3/env-build/cxx-lib -L/home/share/<env-user>/s3/env-build/hpckit/26.1.RC1/compiler/gcc/lib64"
mkdir -p "$FOAM_USER_APPBIN"
```

- 编译器：HPCKit 26.1.RC1 / bisheng (clang)
- 官方安装：`/home/share/<env-user>/s3/data/OpenFOAM-v2606`（只读）
- 算例模板：`/home/share/<env-user>/s3/release/case/of_21M_template.tar.gz`
- 自测：`bash Allrun-solve`，576 核与绑核参数已内置

## 当前公开榜

`Tester`，`0.8027` s/step，提交 5 次。仅作参考，不是官方基线。
