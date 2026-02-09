# List Workflow - 列出所有 AI CLI 工具

## 触发条件

用户请求显示、列出、查看可用 AI CLI 工具时触发。

## 输入参数

- `category`: 按类别筛选（ai/local/workflow/coding/all，默认 all）
- `format`: 输出格式（text/json/compact，默认 text）
- `installed`: 仅显示已安装的工具（flag）

## 工作流步骤

### 1. 读取工具配置

```bash
./cli/core/yaml-parser.sh config/tools.yaml tools
```

解析 `config/tools.yaml` 文件：
- 工具列表
- 工具元数据
- 别名配置

### 2. 扫描系统状态

检查每个工具是否已安装：

```bash
./cli/core/tool-scanner.sh
```

### 3. 按类别分组输出

将工具按类别分组：
- **AI 模型** (ai): OpenAI CLI, Claude CLI
- **本地运行** (local): Ollama
- **工作流** (workflow): Fabric
- **代码助手** (coding): Aider

## 输出示例

```
═══════════════════════════════════════
  可用的 AI CLI 工具
═══════════════════════════════════════

AI 模型:
  ✅ openai     - OpenAI CLI
  ✅ claude     - Claude CLI

本地运行:
  ✅ ollama     - Ollama 本地 LLM

工作流:
  ✅ fabric     - Fabric AI 工作流

代码助手:
  ✅ aider      - Aider AI 代码助手
```

## 完整命令

```bash
# 列出所有工具
@ai-tools list

# 仅显示已安装
@ai-tools list --installed

# JSON 格式
@ai-tools list --format json

# 按类别筛选
@ai-tools list --category ai
```

## JSON 输出格式

```json
{
  "tools": [
    {
      "name": "openai",
      "display_name": "OpenAI CLI",
      "description": "OpenAI 官方命令行工具",
      "category": "ai",
      "installed": true,
      "version": "0.28.0"
    }
  ],
  "aliases": {
    "ai": "openai",
    "chat": "claude"
  }
}
```

## 工具状态图标

- ✅ 已安装且可正常运行
- ❌ 未安装或不可用
- ⚠️  安装但有警告

## 类别说明

| 类别 | 说明 | 示例工具 |
|------|------|---------|
| ai | 在线 AI 模型 API | openai, claude |
| local | 本地运行的模型 | ollama |
| workflow | AI 工作流工具 | fabric |
| coding | AI 代码助手 | aider |
| other | 其他工具 | test-tool |

## 后续步骤

1. 使用 `route` 命令获取任务推荐
2. 使用 `info <tool>` 查看工具详情
3. 使用 `config add` 添加新工具
