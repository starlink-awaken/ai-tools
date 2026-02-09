# Config Workflow - 工具配置管理

## 触发条件

用户请求添加、删除、编辑、验证工具配置时触发。

## 子命令

| 子命令 | 说明 | 示例 |
|--------|------|------|
| `add` | 交互式添加新工具 | `config add` |
| `remove <tool>` | 删除工具 | `config remove test-tool` |
| `edit <tool>` | 编辑工具配置 | `config edit claude` |
| `validate` | 验证配置 | `config validate` |

## 工作流步骤

### validate - 验证配置

```bash
./cli/core/config-validator.sh --all --format text
```

检查内容：
- YAML 语法正确性
- 必填字段完整性
- 工具名称唯一性
- 命令语法有效性

### add - 添加工具

```bash
./cli/core/config-wizard.sh add
```

交互式输入：
1. 工具名称
2. 显示名称
3. 描述
4. 类别
5. 安装命令
6. 验证命令
7. 依赖要求
8. 环境变量配置

### remove - 删除工具

```bash
./cli/core/config-wizard.sh remove <tool_name>
```

删除操作：
- 从 `config/tools.yaml` 移除
- 从 `config/rules.yaml` 清理关联规则
- 保留数据备份

### edit - 编辑工具

```bash
./cli/core/config-wizard.sh edit <tool_name>
```

可编辑字段：
- 显示名称
- 描述
- 安装命令
- 配置参数
- 支持的命令

## 验证命令

```bash
# 验证所有配置
@ai-tools validate

# 验证并输出 JSON
@ai-tools validate --format json

# 详细输出
@ai-tools validate --verbose
```

## 验证检查项

### 语法检查

```yaml
# ✅ 正确格式
- name: openai
  display_name: OpenAI CLI

# ❌ 错误格式
- name:openai  # 缺少空格
  display_name:OpenAI CLI
```

### 必填字段

每个工具必须包含：
- `name`: 工具唯一标识
- `display_name`: 显示名称
- `description`: 功能描述
- `category`: 所属类别

### 唯一性检查

- 工具名称不能重复
- 别名不能与工具名冲突

## 配置文件位置

| 文件 | 说明 |
|------|------|
| `config/tools.yaml` | 工具定义 |
| `config/rules.yaml` | 路由规则 |
| `data/history.json` | 使用历史 |
| `data/stats.json` | 统计数据 |

## 错误处理

- 配置无效 → 显示具体错误位置
- 工具不存在 → 显示可用工具列表
- 权限不足 → 检查文件权限

## 备份与恢复

每次修改配置前自动备份：
- 备份位置：`config/*.yaml.bak`
- 恢复命令：`config-wizard.sh restore <backup_file>`
