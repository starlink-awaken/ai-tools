# Route Workflow - AI CLI 工具路由选择

## 触发条件

用户请求使用 AI CLI 工具完成任务时触发。

## 输入参数

- `task`: 任务描述（必填）
- `format`: 输出格式（text/json，默认 text）
- `tool`: 指定工具（可选）

## 工作流步骤

### 1. 解析用户需求

分析任务描述，提取关键信息：
- 任务类型（代码、文本、翻译、分析等）
- 优先级（速度、成本、质量）
- 特殊要求（本地运行、免费等）

### 2. 执行路由引擎

```bash
./cli/core/routing-engine.sh "$task" --format "$format"
```

路由引擎会根据：
- `config/rules.yaml` 中的规则
- 任务关键词匹配
- 工具优先级评分

### 3. 返回推荐结果

推荐结果包含：
- 推荐工具名称
- 推荐理由
- 置信度评分
- 备选方案

## 输出示例

```
🧠 分析任务: 总结这篇文章

📊 匹配结果:
  ✅ fabric (置信度: 95%)
  ✅ claude (置信度: 80%)

💡 推荐: fabric
   理由: 专门用于文本总结的 AI 工作流工具
```

## 完整命令

```bash
# 基本用法
@ai-tools route "总结这篇文章"

# 指定输出格式
@ai-tools route "代码审查" --format json

# 指定工具
@ai-tools route "生成 Python 代码" --tool claude
```

## 路由规则

详见 `config/rules.yaml`：

```yaml
- name: summarize
  priority: 10
  keywords: [summarize, 总结, 摘要]
  tools: [fabric, claude]
  score_logic: keyword_match + tool_capability
```

## 错误处理

- 任务描述为空 → 显示帮助信息
- 无匹配工具 → 返回所有可用工具列表
- 路由引擎错误 → 显示详细错误信息

## 后续步骤

1. 用户确认后，使用 `generate` 命令生成执行命令
2. 可使用 `history` 记录本次推荐
3. 使用 `stats` 更新使用统计
