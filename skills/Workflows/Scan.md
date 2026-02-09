# Scan Workflow - 系统工具扫描

## 触发条件

用户请求扫描、检测、检查系统已安装的 AI CLI 工具时触发。

## 输入参数

- `format`: 输出格式（text/json，默认 text）
- `verbose`: 详细输出（flag）
- `quick`: 快速扫描，仅检查常用路径（flag）

## 工作流步骤

### 1. 定义扫描路径

```bash
# 常用安装路径
PATHS=(
  "/usr/local/bin"
  "/usr/bin"
  "/bin"
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  "$HOME/.npm-global/bin"
  "$HOME/go/bin"
)
```

### 2. 执行工具检测

```bash
./cli/core/tool-scanner.sh --format text
```

检测方法：
- `which <tool>` 命令查找
- 版本信息获取
- 能力验证

### 3. 生成扫描报告

报告内容：
- 已安装工具列表
- 可用但未配置的工具
- 检测到的版本信息
- 路径信息

## 输出示例

```
🔍 AI CLI 工具扫描报告
═══════════════════════════════

✅ 已安装且已配置:
  • openai     v0.28.0    /usr/local/bin/openai
  • claude     v1.0.2     /usr/local/bin/claude
  • ollama     v0.1.35    /usr/local/bin/ollama

⚠️  已安装但未配置:
  • gemini-cli (found in /usr/local/bin)
  • grok-cli  (found in ~/.local/bin)

❌  未安装:
  • fabric
  • aider

═══════════════════════════════
扫描时间: 2026-02-10 15:30:00
```

## 完整命令

```bash
# 基本扫描
@ai-tools scan

# 详细输出
@ai-tools scan --verbose

# JSON 格式
@ai-tools scan --format json

# 快速扫描
@ai-tools scan --quick
```

## JSON 输出格式

```json
{
  "scan_time": "2026-02-10T15:30:00Z",
  "installed": [
    {
      "name": "openai",
      "path": "/usr/local/bin/openai",
      "version": "0.28.0",
      "configured": true
    }
  ],
  "unconfigured": [
    {
      "name": "gemini-cli",
      "path": "/usr/local/bin/gemini-cli",
      "version": "1.0.0"
    }
  ],
  "missing": ["fabric", "aider"]
}
```

## 检测逻辑

### 版本获取

```bash
# 方法1: --version
$ openai --version
openai 0.28.0

# 方法2: -v
$ claude -v
claude version 1.0.2

# 方法3: help
$ ollama help | head -1
Ollama CLI v0.1.35
```

### 能力验证

检查工具是否真正可用：

```bash
# 测试命令执行
$ openai --help > /dev/null && echo "OK"
OK
```

## 快速扫描模式

仅检查最常用的安装路径：

```bash
# 快速扫描包含的路径
QUICK_PATHS=(
  /usr/local/bin
  /usr/bin
  ~/.local/bin
  ~/.cargo/bin
)
```

## 扫描策略

| 策略 | 说明 | 适用场景 |
|------|------|---------|
| 完整扫描 | 检查所有定义路径 | 首次扫描、问题排查 |
| 快速扫描 | 仅检查常用路径 | 日常使用、性能优先 |
| 增量扫描 | 仅扫描新安装工具 | 安装后验证 |

## 后续步骤

1. 使用 `list` 查看完整配置
2. 使用 `config add` 添加未配置的工具
3. 使用 `route` 获取使用推荐

## 性能优化

- 默认超时：5 秒/工具
- 并行检测：可达 4 个工具同时检测
- 缓存结果：24 小时内有效
