---
name: commit
description: 为“回见”iOS 项目检查全部 Git 变更，生成英文 Conventional Commit 提交信息，并在中文确认后执行提交。用户要求提交代码、创建 commit、整理提交信息或准备版本提交时使用。
---

# 回见项目提交

为当前仓库准备边界清晰、可复核的 Git 提交。提交信息使用英文，分析和确认使用中文。

## 不可跳过的约束

- 在用户明确确认前，不得执行 `git add`、`git commit`、`git push` 或修改 Git 历史。
- 确认前必须展示完整提交信息、变更摘要和所有计划提交的文件。
- 用户要求“提交”并不等于预先确认；仍须先展示提案并等待一次明确回复。
- 本技能只创建本地 commit。不得自动 push、创建 tag 或发布版本，除非用户另行明确要求，并按相应操作再次确认。
- 不修改源码来迎合提交信息。发现无关变更、冲突或验证失败时，如实报告并缩小范围或等待用户决定。

## 收集与审查

先确认仓库状态和完整差异：

```bash
git status --short --branch
git diff --cached --stat
git diff --cached
git diff --stat
git diff
git ls-files --others --exclude-standard
```

对未追踪文本文件读取实际内容；对图片、模型等二进制文件至少核对类型、路径和大小。不要因为文件位于隐藏目录而遗漏它，只排除 Git 已忽略的内容。

特别检查本项目容易误入版本库的文件：

- `DerivedData/`、`.build/`、`xcuserdata/`、`*.xcuserstate` 等本机构建或 Xcode 用户状态应保持忽略。
- 不提交开发证书、 provisioning profile、私钥、令牌、真实用户采集数据、未脱敏位置或媒体资料。
- `project.pbxproj`、共享 scheme、`Info.plist`、Assets 和测试属于正常工程文件，应结合内容判断，不要仅因其为生成格式而忽略。

若发现疑似敏感信息或明显无关的用户变更，停止准备提交并用中文指出具体路径；不要自行删除、还原或纳入提交。

## 验证

根据变更风险执行与提交相关的最小充分验证，并在确认提示中报告结果：

- 工程配置变化：用完整 Xcode 工具链执行 `xcodebuild -list -project ReSee.xcodeproj`。
- Swift、资源或工程文件变化：优先执行无签名模拟器构建。
- 测试或数据模型变化：至少执行 `build-for-testing`；环境允许时运行相关测试。
- 文档或纯技能变化：检查格式、链接、Git 状态；无需为此强制完整应用构建。

推荐命令使用当前机器的完整 Xcode，而不修改全局 `xcode-select`：

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ReSee.xcodeproj \
  -scheme ReSee \
  -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

验证受模拟器、签名或沙盒限制时，区分“代码验证失败”和“环境未允许执行”，不得把未运行写成通过。

## 生成提交信息

使用下列标题之一：

- `feat: ...`：新增用户可感知能力或主要模块
- `fix: ...`：修复缺陷
- `refactor: ...`：不改变行为的结构调整
- `test: ...`：仅测试变化
- `docs: ...`：仅文档变化
- `build: ...`：Xcode 工程、依赖或构建系统变化
- `chore: ...`：维护性变更或仓库配置
- `release: VERSION`：用户明确要求的版本发布准备

格式：

```text
type: concise lowercase description

- lowercase change detail
- lowercase change detail
```

标题和正文均使用英文。标题简洁、具体，建议不超过 50 个字符；正文描述“做了什么”，不要写空泛过程。若变更包含一个主目标及其配套工程、测试和文档，优先做一个内聚提交；若存在互不相关的目标，先提出拆分方案，不要擅自把所有内容塞进一个提交。

## 强制确认

使用以下结构展示提案，其中“将提交的文件”必须列出全部路径，不能用“等”或目录缩写：

````markdown
=== 需要确认提交 ===

提交信息：
```text
[完整英文标题]

- [英文提交明细]
- [英文提交明细]
```

变更摘要：

- [中文摘要]
- [中文摘要]

验证结果：

- [已通过、失败或未执行的检查及原因]

将提交的文件：

- [完整相对路径]
- [完整相对路径]

确认提交吗？请回复“确认”继续，或回复“取消”终止。
````

确认词包括“确认”“是”“提交”以及 `yes`、`y`、`confirm`；拒绝词包括“取消”“否”以及 `no`、`n`、`cancel`，允许常见结尾标点。其他回复均视为不明确，回复：

> 您的回复不明确。请回复“确认”继续提交，或回复“取消”终止。

若用户在确认时改变提交范围、提交信息或代码，原提案失效。重新收集状态和差异，生成新的完整提案并再次确认。

## 确认后的执行

仅在当前提案得到明确确认后：

1. 再次执行 `git status --short`，确保没有出现提案之外的新变化。
2. 若状态变化，停止并重新走确认流程。
3. 使用 `git add --all` 暂存已确认的完整范围。
4. 用标题和正文执行一次非交互式 `git commit`。
5. 报告 commit 短哈希、最终标题和提交文件数量，并展示剩余工作区状态。

如果 `git commit` 因钩子或验证失败而中止，报告原始错误并保持现状；不得使用 `--no-verify` 绕过，也不得自动重复提交。用户取消时不执行任何 Git 写操作，并说明提交已取消。

