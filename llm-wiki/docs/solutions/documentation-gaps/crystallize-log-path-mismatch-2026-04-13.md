---
title: 修正 crystallize 日志路径说明与实际落点不一致
date: 2026-04-13
category: documentation-gaps
module: llm-wiki crystallize workflow
problem_type: documentation_gap
component: documentation
symptoms:
  - Phase B 的验收说明要求检查 `$WIKI_ROOT/wiki/log.md`，但仓库实际只会生成根目录 `log.md`。
  - 结晶化文件已经正常生成，但验收仍然因为日志路径断言失败而被判为不通过。
  - 新建的临时知识库里存在 `log.md`，不存在 `wiki/log.md`，导致测试口径和真实行为对不上。
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: medium
related_components:
  - development_workflow
  - testing_framework
tags: [crystallize, log-path, acceptance-test, skill-md, documentation-drift]
---

# 修正 crystallize 日志路径说明与实际落点不一致

## Problem
`crystallize` 工作流本身已经能正确生成结晶化文件，但文档里的日志路径说明漂移了。验收步骤要求测试者检查 `$WIKI_ROOT/wiki/log.md`，而仓库初始化和其他工作流一直使用的都是根目录 `log.md`，导致 Phase B 的验收口径和实际行为发生冲突。

## Symptoms
- 按照 [`SKILL.md`](../../../SKILL.md) 旧版说明执行验收时，Phase B 会在日志检查这一步失败。
- 临时知识库里可以看到 `wiki/synthesis/sessions/{主题}-{日期}.md` 正常生成，但找不到 `wiki/log.md`。
- [`scripts/init-wiki.sh`](../../../scripts/init-wiki.sh) 创建的是 `$WIKI_ROOT/log.md`，而不是 `$WIKI_ROOT/wiki/log.md`。
- `ingest` 和仓库其余工作流都已经写成“更新 `log.md`”，只有 `crystallize` 这一段还保留了旧路径。

## What Didn't Work
- 第一次验收测试严格按旧文档检查 `wiki/log.md`，结果把一个文档问题误判成了功能问题。
- 继续追查结晶化文件生成逻辑并不能解决验收失败，因为真正出错的不是输出流程，而是验收合同写错了路径。
- 单看 `crystallize` 那一段文字很难发现问题，只有把它和初始化脚本、现有知识库结构，以及 `ingest` 的日志约定一起对照，才能看出这是一次说明漂移。

## Solution
把 `crystallize` 的日志路径说明改回与仓库真实行为一致的根目录 `log.md`。

这次修复发生在提交 `65f4a90f634461cd45dca18480e117d5a4015ff0`，改动集中在 [`SKILL.md`](../../../SKILL.md) 的两处：

```diff
-4. 更新 `wiki/log.md`（记录本次结晶化操作）
+4. 更新 `log.md`（记录本次结晶化操作）
```

```diff
-已更新 wiki/log.md
+已更新 log.md
```

修复后重新建了新的隔离知识库并从头重跑验收。结果显示：
- 结晶化文件仍然正常生成在 `wiki/synthesis/sessions/`
- 日志记录落在根目录 `log.md`
- 按修正后的说明检查时，Phase B 通过

## Why This Works
这个修复直接把书面约定重新对齐到仓库已经存在的真实文件布局上。

[`scripts/init-wiki.sh`](../../../scripts/init-wiki.sh) 明确写入的是：

```bash
replace_vars "$SKILL_DIR/templates/log-template.md" "$WIKI_ROOT/log.md"
```

而 `ingest` 工作流也一直写成“更新 `log.md`”。所以问题并不是 `crystallize` 的实现与其他流程不同，而是这一个说明段从统一约定里漂移了出去。把它改回 `log.md` 后，验收步骤、初始化结果和其他工作流重新回到同一套路径约定上，测试自然恢复一致。

## Prevention
- 任何文档里写到“生成了哪个文件”的地方，都要和 [`scripts/init-wiki.sh`](../../../scripts/init-wiki.sh) 的真实输出路径逐项对照，不要凭目录印象补路径。
- 修改单个工作流说明时，顺手对照同类工作流的输出约定，避免只有一段文档脱离全局约定。
- 遇到“功能看起来正常，但验收失败”的情况，先检查验收合同是不是和仓库真实行为一致，再决定是否继续追查实现。
- 对新增或修改的工作流说明，至少做一次新建临时知识库的端到端验证，确认文档写的文件路径真的存在。

## Related Issues
- 中度重叠：[`docs/solutions/workflow-issues/ingest-step1-validation-contract-and-crystallize-workflow-2026-04-13.md`](../workflow-issues/ingest-step1-validation-contract-and-crystallize-workflow-2026-04-13.md)。它覆盖了 `crystallize` 工作流的引入和验证门槛，但这次问题更聚焦在日志路径说明漂移。
- GitHub issues：使用 `gh issue list --search "crystallize log.md wiki/log.md acceptance"` 检查后，没有找到相关 issue。
