---
title: 为 ingest Step 1 建立可执行校验契约，并补齐 crystallize 工作流
date: 2026-04-13
category: workflow-issues
module: llm-wiki
problem_type: workflow_issue
component: development_workflow
symptoms:
  - Step 1 的 JSON 输出只有文字约定，没有可执行的格式校验门槛。
  - `confidence` 缺失或乱填时，Step 2 仍可能继续执行。
  - 合法的空 `entities` 数组如果处理不当，会被误判成失败。
  - 用户已经需要“结晶化”入口，但仓库里还没有对应工作流、模板和目录准备。
root_cause: missing_validation
resolution_type: workflow_improvement
severity: medium
related_components:
  - documentation
  - tooling
  - testing_framework
tags: [ingest, step1-validation, confidence-rules, crystallize, regression]
---

# 为 ingest Step 1 建立可执行校验契约，并补齐 crystallize 工作流

## Problem
`ingest` 的两步流程原来只有文档说明，没有一个真正会执行的 Step 1 校验门槛，所以“输出结构到底合不合格”这件事只能靠约定。与此同时，`crystallize` 已经是明确需求，但仓库里还没有对应的路由、模板和落盘约定。

## Symptoms
- `SKILL.md` 虽然写了 Step 1 的 JSON 结构和置信度规则，但没有任何脚本会在 Step 2 前拦截坏输出。
- `confidence` 字段缺失或写成非法值时，流程缺少一个统一的失败出口。
- 某些输入本来就提不出实体，空 `entities` 数组应该是合法结果，但校验逻辑如果写得过死，会把这种结果误杀。
- 用户说“结晶化”时，系统没有单独工作流，也没有 `wiki/synthesis/sessions/` 模板和目录准备。

## What Didn't Work
- 只把规则写在 [`SKILL.md`](../../SKILL.md) 里不够，文字不会自动阻止坏 JSON 进入 Step 2。
- 只检查 `entities` 是否存在也不够，因为这会漏掉缺失 `confidence` 和非法值的问题。
- 直接遍历 `.entities[]` 过于脆弱。空数组本身是合法的，但这种写法很容易在 shell 管道里把“没有实体”混同为失败。
- 单独补一个 `crystallize` 说明段也不够，如果没有模板、目录和初始化支持，这条工作流仍然落不了地。

## Solution
把这次改动收紧成“文档规则 + 可执行脚本 + 回归测试”三层一起生效。

第一层是在 [`SKILL.md`](../../SKILL.md) 明确 Step 1 的置信度规则、验证步骤，以及 `crystallize` 的路由和工作流说明：

```text
EXTRACTED | INFERRED | AMBIGUOUS | UNVERIFIED
```

并且要求 Step 1 完成后必须先把 JSON 写到临时文件，再调用校验脚本：

```bash
mkdir -p {wiki_root}/.wiki-tmp
bash ${SKILL_DIR}/scripts/validate-step1.sh {wiki_root}/.wiki-tmp/step1-latest.json
```

第二层是新增 [`scripts/validate-step1.sh`](../../scripts/validate-step1.sh)，把规则变成真正的执行门槛。它现在会：
- 检查文件参数、`jq` 依赖和 JSON 有效性
- 检查 `entities`、`topics`、`connections`、`contradictions`、`new_vs_existing` 的类型
- 检查每个实体的 `confidence` 只能取 `EXTRACTED / INFERRED / AMBIGUOUS / UNVERIFIED`
- 允许空 `entities` 数组通过，不把合法空结果误判成错误

最关键的修正是：

```bash
INVALID=$(jq -r '.entities[]? | (.confidence // "MISSING")' "$JSON_FILE" 2>/dev/null | \
    grep -v -E "^(EXTRACTED|INFERRED|AMBIGUOUS|UNVERIFIED)$" | head -3)
```

这里的 `[]?` 让空数组安静通过，但一旦某个实体缺少 `confidence`，仍会被抓成 `MISSING`；如果值写成 `HIGH` 之类的非法值，也会被直接拦下。

第三层是把 `crystallize` 补齐成一条真正可执行的工作流：
- [`templates/synthesis-template.md`](../../templates/synthesis-template.md) 提供统一的结晶化页面结构
- [`scripts/init-wiki.sh`](../../scripts/init-wiki.sh) 会预先创建 `wiki/synthesis/sessions/`
- 初始化时同时写入 `.gitignore`，忽略 `.wiki-tmp/`
- [`SKILL.md`](../../SKILL.md) 增加 `crystallize` 路由和输出示例

最后，在 [`tests/regression.sh`](../../tests/regression.sh) 里补上回归门槛，锁住脚本行为、文档规则和初始化目录：
- 无参数应报 usage
- 合法 JSON 应通过
- 缺失 `confidence` 应失败
- 非法 `confidence` 应失败
- `entities` 不是数组应失败
- 空 `entities` 数组应通过
- `SKILL.md` 必须包含新的规则、验证步骤和 `crystallize` 工作流
- `init-wiki.sh` 必须创建 `wiki/synthesis/sessions/`

## Why This Works
它把以前“写在说明里”的约束，变成了真正会执行的输入契约。Step 1 现在不再是一个松散的中间态，而是一个有边界的关口：结构不对就回退，置信度不合规就回退，空 `entities` 又不会被误杀。

`crystallize` 这条线也从“有需求但没有落点”变成了完整闭环：用户有触发词，仓库有模板，初始化会准备目录，日志也有固定记录位置。这样这条工作流才不是纯文档承诺，而是能实际落地的知识沉淀路径。

## Prevention
- 以后只要修改 Step 1 输出格式，就必须同时检查 [`SKILL.md`](../../SKILL.md)、[`scripts/validate-step1.sh`](../../scripts/validate-step1.sh) 和 [`tests/regression.sh`](../../tests/regression.sh)，不要只改其中一层。
- 对 shell + `jq` 的数组校验，默认优先考虑空数组是否合法；如果合法，就避免把“空结果”和“坏结果”混成同一类失败。
- 新增工作流不要只补路由说明，还要一起补模板、初始化目录和回归门槛，否则流程会停在“写了说明但跑不起来”。
- 这类工作完成后的最低验证门槛应至少包括：

```bash
bash tests/regression.sh
```

- 如果后续再扩展 Step 1 JSON 字段，先加失败用例，再改脚本和文档，确保新字段不会只存在于说明里而没有执行约束。

## Related Issues
- 相关但不重复的流程硬化文档：[`freeze-ingest-source-contract-and-registry-2026-04-06.md`](../developer-experience/freeze-ingest-source-contract-and-registry-2026-04-06.md)
- 同一片 ingest 领域的适配器状态治理：[`unify-optional-adapter-states-and-fallback-paths-2026-04-06.md`](../integration-issues/unify-optional-adapter-states-and-fallback-paths-2026-04-06.md)
- 邻近的兼容性工作：[`legacy-wiki-lazy-compatibility-2026-04-06.md`](legacy-wiki-lazy-compatibility-2026-04-06.md)
- GitHub issue 搜索：`gh issue list --search "ingest validation confidence crystallize" --state all --limit 5` 未找到直接对应问题
