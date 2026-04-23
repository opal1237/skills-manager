---
title: lint-runner INDEX_FILE 路径错误与安装副本未同步
date: 2026-04-14
category: logic-errors
module: llm-wiki lint-runner
problem_type: logic_error
component: tooling
symptoms:
  - codex 运行 lint 工作流时报 "ERROR: index.md 不存在：.../wiki/index.md"，exit 1 退出
  - Phase C 回归测试 Step B lint 失败
  - 源码修复后 codex 重跑仍然失败，提示相同的路径错误
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [path-resolution, install-sync, regression, fixture, index-file]
---

# lint-runner INDEX_FILE 路径错误与安装副本未同步

## Problem

`lint-runner.sh` 的 `INDEX_FILE` 变量指向 `$WIKI_DIR/index.md`（即 `$WIKI_ROOT/wiki/index.md`），但 `index.md` 实际位于 `$WIKI_ROOT/index.md`。路径多了一层 `wiki/`，导致脚本对任何正常初始化的知识库都报错退出。修复源码后，`~/.codex/skills/` 下的已安装副本未同步，codex 仍运行旧版。

## Symptoms

- 运行 `lint-runner.sh` 报错：`ERROR: index.md 不存在：.../cowork-wiki/wiki/index.md`，exit 1
- 测试 fixture 中 `index.md` 位于 `wiki/` 子目录内，与真实 wiki 根目录布局不符
- 源码修复后，codex 侧重跑仍然失败——已安装副本是旧的

## What Didn't Work

- **只改源码就以为修好了**：Codex 从 `~/.codex/skills/llm-wiki/scripts/lint-runner.sh` 读已安装副本，源码和运行环境是分离的
- **测试 fixture 掩盖了 bug**：fixture 把 `index.md` 放在 `wiki/` 下，复制了脚本的错误假设，导致测试通过但真实环境失败

## Solution

**修复 1：lint-runner.sh 路径变量**

```bash
# Before（错误）
INDEX_FILE="$WIKI_DIR/index.md"    # → $WIKI_ROOT/wiki/index.md

# After（正确）
INDEX_FILE="$WIKI_ROOT/index.md"   # → $WIKI_ROOT/index.md
```

**修复 2：测试 fixture 目录结构**

```
# Before
tests/fixtures/lint-sample-wiki/wiki/index.md   # 多了一层 wiki/

# After
tests/fixtures/lint-sample-wiki/index.md         # 与真实布局一致
```

同步更新 `tests/expected/lint-output.txt`（断链列表从包含 `[[Ghost]]` 改为由 index 一致性检查报告）。

**修复 3：同步安装副本**

```bash
bash install.sh --platform codex
# 将源码修复同步到 ~/.codex/skills/llm-wiki/scripts/lint-runner.sh
```

验证：

```bash
grep 'INDEX_FILE=' ~/.codex/skills/llm-wiki/scripts/lint-runner.sh
# 应输出：INDEX_FILE="$WIKI_ROOT/index.md"
```

## Why This Works

核心问题是路径变量的目录层级错误。`$WIKI_DIR` 指向 `$WIKI_ROOT/wiki/`（内容子目录），而 `index.md` 实际位于 `$WIKI_ROOT/`（知识库根目录），由 `templates/schema-template.md` 第 31 行确认——`index.md` 与 `raw/`、`wiki/` 等顶级目录并列。

测试 fixture 的问题在于它复制了脚本中的错误假设，而非真实目录结构，形成"测试通过但生产失败"的假象。

安装副本问题源于项目架构设计：源码仓库与运行环境（`~/.codex/skills/`）是分离的，修改源码不会自动反映到已安装位置，必须显式重装。

## Prevention

- **fixture 与真实结构对齐**：测试 fixture 目录必须从真实 wiki 结构镜像，不能手工凭感觉创建。可以在 CI 中用 schema-template.md 校验 fixture 结构
- **源码改脚本后必须重装**：在 CLAUDE.md 的推送前测试规则里已写入——修改 `scripts/` 下任何文件后，push 前必须 `bash install.sh --platform codex` 同步
- **安装后冒烟测试**：`lint-runner.sh` 自身已有路径不存在时的 exit 1 检查，但应该在 install 流程末尾加一步 `bash scripts/lint-runner.sh tests/fixtures/lint-sample-wiki` 确认核心路径可解析
- **路径变量集中定义**：`WIKI_ROOT`、`WIKI_DIR`、`INDEX_FILE` 等路径变量应集中到一处，避免各脚本各自拼接时产生不一致

## Related

- [crystallize-log-path-mismatch-2026-04-13](../documentation-gaps/crystallize-log-path-mismatch-2026-04-13.md)：同类路径混淆（`$WIKI_ROOT/wiki/log.md` vs `$WIKI_ROOT/log.md`），那一次是文档层面的修复，这次是代码层面。两次出现说明 `$WIKI_ROOT/wiki/X` vs `$WIKI_ROOT/X` 是这个项目的高频错误模式，值得集中定义路径变量
- [ingest-step1-validation-contract-and-crystallize-workflow-2026-04-13](../workflow-issues/ingest-step1-validation-contract-and-crystallize-workflow-2026-04-13.md)：同一次 Phase B 验收中发现的问题
