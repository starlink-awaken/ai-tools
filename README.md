# AI CLI Tools Manager

![Version](https://img.shields.io/badge/version-2.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)

智能 AI CLI 工具管理器 - 统一调度、路由选择、使用统计一体化解决方案。

## 功能特性

- **统一入口**：单一命令行工具管理所有 AI CLI 工具
- **智能路由**：根据任务描述自动推荐最合适的 AI 工具
- **使用统计**：记录和分析 AI 工具使用情况
- **配置向导**：交互式添加工具配置
- **历史记录**：追踪工具推荐历史，支持复用

## 快速开始

```bash
# 克隆项目
git clone https://github.com/yourusername/ai-tools.git
cd ai-tools

# 安装依赖
pip install pyyaml

# 设置别名
alias ai-tools='./ai-tools.sh'

# 查看帮助
./ai-tools.sh --help
```

## 核心命令

| 命令 | 说明 | 示例 |
|------|------|------|
| `list` | 列出所有工具 | `ai-tools list` |
| `route <task>` | 智能路由推荐 | `ai-tools route "代码审查"` |
| `info <tool>` | 查看工具详情 | `ai-tools info claude` |
| `scan` | 扫描系统工具 | `ai-tools scan` |
| `validate` | 验证配置 | `ai-tools validate` |
| `config` | 配置管理 | `ai-tools config add` |
| `history` | 使用历史 | `ai-tools history` |
| `stats` | 使用统计 | `ai-tools stats` |

## 项目结构

```
ai-tools/
├── cli/
│   └── core/                 # 核心模块 (Bash)
│       ├── yaml-parser.sh    # YAML 解析器
│       ├── tool-scanner.sh   # 工具扫描器
│       ├── routing-engine.sh # 路由引擎
│       ├── tool-info.sh      # 工具详情
│       ├── cmd-generator.sh  # 命令生成器
│       ├── config-validator.sh # 配置验证器
│       ├── config-wizard.sh  # 配置向导
│       ├── history-manager.sh # 历史管理器
│       └── stats.sh          # 统计分析
├── config/
│   ├── tools.yaml           # 工具定义
│   └── rules.yaml           # 路由规则
├── data/
│   ├── history.json         # 使用历史
│   └── stats.json           # 统计数据
├── skills/                  # Claude Skills
│   ├── SKILL.md
│   └── Workflows/
│       ├── Route.md
│       ├── List.md
│       ├── Config.md
│       └── Scan.md
├── docs/                    # 文档
├── tests/                   # 测试
└── ai-tools.sh              # 主入口脚本
```

## 支持的工具

| 类别 | 工具 | 说明 |
|------|------|------|
| AI 模型 | OpenAI CLI | 访问 GPT-4、GPT-3.5 |
| AI 模型 | Claude CLI | 访问 Claude 3 系列 |
| 本地运行 | Ollama | 本地 LLM (Llama, Mistral) |
| 工作流 | Fabric | AI 工作流工具 |
| 代码助手 | Aider | AI 代码助手 |

## 安装

### macOS

```bash
git clone https://github.com/yourusername/ai-tools.git
cd ai-tools
pip install pyyaml
echo 'alias ai-tools="~/path/to/ai-tools/ai-tools.sh"' >> ~/.zshrc
source ~/.zshrc
```

### Linux

```bash
git clone https://github.com/yourusername/ai-tools.git
cd ai-tools
pip install pyyaml
chmod +x ai-tools.sh
sudo ln -s $(pwd)/ai-tools.sh /usr/local/bin/ai-tools
```

## 使用示例

### 列出所有工具

```bash
$ ai-tools list

═══════════════════════════════════════
  可用的 AI CLI 工具
═══════════════════════════════════════

AI 模型:
  ✅ openai     - OpenAI CLI
  ✅ claude     - Claude CLI

本地运行:
  ✅ ollama     - Ollama 本地 LLM
```

### 智能路由

```bash
$ ai-tools route "总结这篇文章"

🧠 分析任务: 总结这篇文章

📊 匹配规则: summarize (优先级: 10)
✅ 推荐工具: fabric
   置信度: 95%
   理由: 专门用于文本总结的 AI 工作流工具
```

### 查看工具详情

```bash
$ ai-tools info claude

🔧 Claude CLI (claude)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📝 描述: Anthropic Claude 命令行工具，访问 Claude 3 系列

📦 类别: AI 模型

🔗 主页: https://docs.anthropic.com/claude/reference/claude-on-the-cli

✅ 安装状态: 已安装 (v1.0.2)

📥 安装命令: npm install -g @anthropic-ai/claude-cli
```

## 配置文件

### tools.yaml

```yaml
tools:
- name: openai
  display_name: OpenAI CLI
  description: OpenAI 官方命令行工具
  category: ai
  url: https://github.com/openai/openai-cli
  install:
    command: pip install openai
    verify: openai --version
  commands:
  - name: chat
    description: 启动交互式聊天
```

### rules.yaml

```yaml
rules:
- name: summarize
  priority: 10
  keywords: [summarize, 总结, 摘要]
  tools: [fabric, claude]
```

## Claude Skills 集成

### Route Workflow

```bash
# Claude Code 中使用
@ai-tools route "总结文章"
```

### List Workflow

```bash
# 列出所有可用工具
@ai-tools list
```

## 开发

```bash
# 运行测试
./tests/run-tests.sh

# 验证配置
./ai-tools.sh validate

# 扫描系统工具
./ai-tools.sh scan
```

## 系统要求

- **Python**: 3.8+
- **Bash**: 4.0+ (macOS 用户需安装新版 Bash)
- **依赖**: PyYAML

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License - 详见 LICENSE 文件。

## 致谢

- [PyYAML](https://pyyaml.org/) - YAML 解析库
- [Fabric](https://github.com/danielmiessler/fabric) - AI 工作流灵感
- [Aider](https://github.com/paul-gauthier/aider) - AI 代码助手概念

---

**作者**: 隔壁老王

**版本**: 2.0.0

**更新日期**: 2026-02-10
