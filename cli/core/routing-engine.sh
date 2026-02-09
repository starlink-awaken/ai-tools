#!/bin/bash
# ==============================================================================
# AI CLI Tools - Enhanced Routing Engine
# ==============================================================================
# 版本: 2.0.0
# 用途: 基于规则的可配置路由引擎，支持多种匹配模式和评分系统
# 使用: ./routing-engine.sh <task_description> [options]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# 配置路径
# ==============================================================================
readonly CONFIG_DIR="${HOME}/.config/ai-tools"
readonly RULES_FILE="${CONFIG_DIR}/config/rules.yaml"
readonly TOOLS_FILE="${CONFIG_DIR}/tools.yaml"
readonly CACHE_DIR="${CONFIG_DIR}/.cache"

# ==============================================================================
# 颜色定义
# ==============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;90m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ==============================================================================
# 全局变量
# ==============================================================================
OUTPUT_FORMAT="text"
VERBOSE=false
TASK_DESCRIPTION=""

# ==============================================================================
# 工具函数
# ==============================================================================

log_debug() {
    [[ "${VERBOSE}" == "true" ]] && echo -e "${GRAY}[DEBUG]${NC} $*" >&2
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

is_installed() {
    command -v "$1" &> /dev/null
}

check_python() {
    if ! command -v python3 &> /dev/null; then
        log_error "需要 Python 3 来解析 YAML 配置"
        return 1
    fi
    return 0
}

init_cache() {
    mkdir -p "${CACHE_DIR}"
}

# ==============================================================================
# YAML 解析
# ==============================================================================

parse_yaml_to_json() {
    local yaml_file="$1"
    check_python || return 1

    python3 - "${yaml_file}" << 'PYEOF'
# -*- coding: utf-8 -*-
import yaml
import json
import sys

yaml_file = sys.argv[1]

try:
    with open(yaml_file, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)
    print(json.dumps(data, ensure_ascii=False))
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(1)
PYEOF
}

get_cached_rules() {
    local cache_file="${CACHE_DIR}/rules_cache.json"
    if [[ -f "${cache_file}" ]]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "${cache_file}" 2>/dev/null || stat -c %Y "${cache_file}" 2>/dev/null)))
        if [[ ${cache_age} -lt 3600 ]]; then
            log_debug "使用缓存的规则数据"
            cat "${cache_file}"
            return 0
        fi
    fi
    return 1
}

cache_rules() {
    local cache_file="${CACHE_DIR}/rules_cache.json"
    local data="$1"
    echo "${data}" > "${cache_file}"
    log_debug "规则数据已缓存"
}

load_rules_data() {
    local cached_data
    if cached_data=$(get_cached_rules); then
        echo "${cached_data}"
        return 0
    fi

    log_debug "从 YAML 文件加载规则"
    init_cache

    local json_data
    json_data=$(parse_yaml_to_json "${RULES_FILE}")

    if [[ -z "${json_data}" ]] || echo "${json_data}" | grep -q '"error"'; then
        log_error "无法解析规则文件: ${RULES_FILE}"
        return 1
    fi

    cache_rules "${json_data}"
    echo "${json_data}"
}

# ==============================================================================
# 推荐生成
# ==============================================================================

generate_recommendations() {
    local task="$1"
    local rules_json="$2"

    log_debug "生成推荐列表..."

    # 使用文件传递数据以避免编码问题
    local task_file="${CACHE_DIR}/task.tmp"
    local rules_file="${CACHE_DIR}/rules.tmp"

    echo "${task}" > "${task_file}"
    echo "${rules_json}" > "${rules_file}"

    python3 << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import subprocess
import sys
import os

cache_dir = os.path.expanduser('~/.config/ai-tools/.cache')
task_file = os.path.join(cache_dir, 'task.tmp')
rules_file = os.path.join(cache_dir, 'rules.tmp')

with open(task_file, 'r', encoding='utf-8') as f:
    task = f.read().strip()

with open(rules_file, 'r', encoding='utf-8') as f:
    rules_json = f.read().strip()

rules_data = json.loads(rules_json)
enabled_rules = [r for r in rules_data.get('rules', []) if r.get('enabled', True)]

def is_tool_installed(tool_name):
    try:
        result = subprocess.run(['which', tool_name], capture_output=True, text=True)
        return result.returncode == 0
    except:
        return False

def calculate_score(tool_name, rule, rules_data):
    priority = rule.get('priority', 500)
    score = priority

    if is_tool_installed(tool_name):
        score += 20

    scoring = rules_data.get('global', {}).get('scoring', {})
    free_tier_bonus = scoring.get('free_tier_bonus', 15)
    low_latency_bonus = scoring.get('low_latency_bonus', 10)

    tools_meta = rules_data.get('global', {}).get('tools_metadata', {})
    tool_meta = tools_meta.get(tool_name, {})

    if tool_meta.get('cost') == 'free':
        score += free_tier_bonus

    if tool_meta.get('latency') == 'low':
        score += low_latency_bonus

    return score

def match_rule(task, rule, rules_data):
    when = rule.get('when', {})
    match_config = rule.get('match', {})
    match_type = match_config.get('type', 'any')

    task_lower = task.lower()

    # 关键词匹配
    keyword_matched = False
    if match_type in ['keyword', 'keyword_or', 'keyword_or_capability', 'keyword_exact']:
        keywords = when.get('keywords', [])
        for kw in keywords:
            if kw.lower() in task_lower:
                keyword_matched = True
                break

    # 对于纯关键词匹配类型，直接返回结果
    if match_type in ['keyword', 'keyword_or', 'keyword_exact']:
        return keyword_matched

    # 对于keyword_or_capability: 如果关键词匹配了就返回True
    if match_type == 'keyword_or_capability' and keyword_matched:
        return True

    # 能力匹配 - 仅在match_type为'capability'时使用（不用于keyword_or_capability的兜底）
    if match_type == 'capability':
        capabilities = when.get('capabilities', [])
        if capabilities:
            # 检查任务中是否包含能力相关的关键词
            capability_keywords = {
                'code': ['code', '代码', '编程', 'programming'],
                'git': ['git', 'commit', '版本', 'version'],
                'refactoring': ['refactor', '重构', '优化', 'optimize'],
                'chat': ['chat', '聊天', '对话', 'conversation'],
                'analysis': ['analyze', '分析', '分析'],
                'writing': ['write', '写作', '书写', 'write', '生成文本'],
                'text_processing': ['text', '文本', '文字'],
                'summarization': ['summarize', 'summary', '总结'],
            }
            for cap in capabilities:
                if cap in capability_keywords:
                    for kw in capability_keywords[cap]:
                        if kw in task_lower:
                            return True

    # 类别匹配
    if match_type == 'category':
        categories = when.get('categories', [])
        if categories:
            tools_meta = rules_data.get('global', {}).get('tools_metadata', {})
            for tool_name, tool_data in tools_meta.items():
                if tool_data.get('category') in categories:
                    return True

    if match_type == 'any':
        return True

    return False

def detect_tool_from_task(task):
    task_lower = task.lower()
    tool_mapping = {
        'claude': 'claude',
        'anthropic': 'claude',
        'gpt': 'openai',
        'openai': 'openai',
        'ollama': 'ollama',
        'fabric': 'fabric',
        'aider': 'aider',
    }
    for keyword, tool in tool_mapping.items():
        if keyword in task_lower:
            return tool
    return None

# 匹配规则
matched_rules = []
for rule in enabled_rules:
    if match_rule(task, rule, rules_data):
        matched_rules.append(rule)

if not matched_rules:
    for rule in enabled_rules:
        if rule.get('id') == 'general-chat':
            matched_rules = [rule]
            break

# 按优先级排序，只使用最高优先级的匹配规则
matched_rules.sort(key=lambda x: x.get('priority', 500), reverse=True)

# 只保留最高优先级的规则（同一优先级的也保留）
if matched_rules:
    highest_priority = matched_rules[0].get('priority', 500)
    matched_rules = [r for r in matched_rules if r.get('priority', 500) == highest_priority]

# 生成推荐
recommendations = []
for rule in matched_rules:
    rule_id = rule.get('id', 'unknown')
    rule_name = rule.get('name', 'Unknown')
    priority = rule.get('priority', 500)

    recommend = rule.get('recommend', {})
    tools = recommend.get('tools', [])
    fallback = recommend.get('fallback')
    reason_template = recommend.get('reason_template', '')

    for tool in tools:
        if tool == 'auto_detect':
            detected = detect_tool_from_task(task)
            if detected:
                tool = detected
            else:
                continue

        try:
            reason = reason_template.format(tool_name=tool.title())
        except:
            reason = reason_template

        score = calculate_score(tool, rule, rules_data)
        installed = is_tool_installed(tool)

        recommendations.append({
            'rule_id': rule_id,
            'rule_name': rule_name,
            'priority': priority,
            'tool': tool,
            'fallback': fallback,
            'reason': reason,
            'score': score,
            'installed': installed
        })

recommendations.sort(key=lambda x: x.get('score', 0), reverse=True)
print(json.dumps(recommendations, ensure_ascii=False))
PYEOF
}

# ==============================================================================
# 输出函数
# ==============================================================================

output_text() {
    local task="$1"
    local recommendations="$2"

    local rec_file="${CACHE_DIR}/recs.tmp"
    local task_file="${CACHE_DIR}/task_output.tmp"

    echo "${recommendations}" > "${rec_file}"
    echo "${task}" > "${task_file}"

    python3 << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys
import os

cache_dir = os.path.expanduser('~/.config/ai-tools/.cache')
rec_file = os.path.join(cache_dir, 'recs.tmp')
task_file = os.path.join(cache_dir, 'task_output.tmp')

with open(rec_file, 'r', encoding='utf-8') as f:
    recommendations = f.read().strip()

with open(task_file, 'r', encoding='utf-8') as f:
    task = f.read().strip()

recs = json.loads(recommendations)

if not recs:
    print("\033[1;33m⚠️  未找到匹配的工具\033[0m\n")
    sys.exit(0)

r = recs[0]
tool = r.get('tool', '')
score = r.get('score', 0)
installed = r.get('installed', False)
reason = r.get('reason', '')
rule_name = r.get('rule_name', '')
rule_priority = r.get('priority', 0)

print(f"\033[0;36m匹配规则:\033[0m #{rule_priority} {rule_name} (优先级: {rule_priority})\n")
print("\033[0;32m推荐工具:\033[0m\n")

status = '\u2705 已安装' if installed else '\u274c 未安装'
print(f"  1. {tool.title()} (score: {score})")
print(f"     {status}")
print(f"     理由: {reason}")

if len(recs) > 1:
    print("  备选:")
    for i, rec in enumerate(recs[1:3], 2):
        tool = rec.get('tool', 'unknown')
        score = rec.get('score', 0)
        installed = rec.get('installed', False)
        reason = rec.get('reason', '')
        status = '\u2705 已安装' if installed else '\u274c 未安装'
        print(f"    {i}. {tool.title()} (score: {score})")
        print(f"       {status}")
        print(f"       理由: {reason}")

print(f"\n\033[1m建议命令:\033[0m")
print(f"\033[0;36m{recs[0].get('tool', '')} \"{task}\"\033[0m\n")
PYEOF
}

output_json() {
    local task="$1"
    local recommendations="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local rec_file="${CACHE_DIR}/recs_json.tmp"
    local task_file="${CACHE_DIR}/task_json.tmp"
    local time_file="${CACHE_DIR}/time.tmp"

    echo "${recommendations}" > "${rec_file}"
    echo "${task}" > "${task_file}"
    echo "${timestamp}" > "${time_file}"

    python3 << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys
import os

cache_dir = os.path.expanduser('~/.config/ai-tools/.cache')
rec_file = os.path.join(cache_dir, 'recs_json.tmp')
task_file = os.path.join(cache_dir, 'task_json.tmp')
time_file = os.path.join(cache_dir, 'time.tmp')

with open(rec_file, 'r', encoding='utf-8') as f:
    recommendations = f.read().strip()

with open(task_file, 'r', encoding='utf-8') as f:
    task = f.read().strip()

with open(time_file, 'r', encoding='utf-8') as f:
    timestamp = f.read().strip()

recs = json.loads(recommendations)

output = {
    'task': task,
    'matched_rule': {
        'id': recs[0].get('rule_id', 'unknown') if recs else 'none',
        'name': recs[0].get('rule_name', 'Unknown') if recs else 'None',
        'priority': recs[0].get('priority', 0) if recs else 0
    },
    'recommendations': [],
    'timestamp': timestamp
}

for rec in recs:
    tool = rec.get('tool', 'unknown')
    output['recommendations'].append({
        'tool': tool,
        'display_name': tool.title(),
        'score': rec.get('score', 0),
        'installed': rec.get('installed', False),
        'reason': rec.get('reason', ''),
        'command': f'{tool} "{task}"'
    })

print(json.dumps(output, ensure_ascii=False, indent=2))
PYEOF
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    # 先处理选项参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --exclude)
                EXCLUDE_TOOLS+=("$2")
                shift 2
                ;;
            --help|-h)
                echo "用法: $0 <task_description> [options]"
                echo ""
                echo "选项:"
                echo "  --format <format>    输出格式 (text|json), 默认: text"
                echo "  --verbose, -v        显示详细匹配过程"
                echo "  --exclude <tool>     排除特定工具"
                echo "  --help, -h           显示帮助"
                echo ""
                echo "示例:"
                echo "  $0 \"总结这段文字\""
                echo "  $0 \"生成代码\" --format json"
                echo "  $0 --format json \"生成代码\""
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                echo "运行 $0 --help 查看帮助"
                exit 1
                ;;
            *)
                # 收集剩余参数作为任务描述
                TASK_DESCRIPTION="$*"
                break
                ;;
        esac
    done

    if [[ -z "${TASK_DESCRIPTION}" ]]; then
        log_error "请提供任务描述"
        echo "用法: $0 <task_description> [options]"
        exit 1
    fi

    log_info "分析任务: ${TASK_DESCRIPTION}"

    local rules_json
    rules_json=$(load_rules_data)

    if [[ -z "${rules_json}" ]]; then
        log_error "无法加载规则数据"
        exit 1
    fi

    local recommendations
    recommendations=$(generate_recommendations "${TASK_DESCRIPTION}" "${rules_json}")

    case "${OUTPUT_FORMAT}" in
        json)
            output_json "${TASK_DESCRIPTION}" "${recommendations}"
            ;;
        *)
            echo ""
            echo -e "${BLUE}🎯 路由分析结果${NC}"
            echo "════════════════════════════════════════════════════════════"
            echo ""
            echo -e "${BOLD}任务:${NC} \"${TASK_DESCRIPTION}\""
            echo ""
            output_text "${TASK_DESCRIPTION}" "${recommendations}"
            echo "════════════════════════════════════════════════════════════"
            ;;
    esac
}

main "$@"
