#!/bin/bash
# ==============================================================================
# AI CLI Tools - History Manager
# ==============================================================================
# Version: 1.0.0
# ==============================================================================

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "${0}")"
readonly CONFIG_DIR="${HOME}/.config/ai-tools"
readonly DATA_DIR="${CONFIG_DIR}/data"
readonly HISTORY_FILE="${DATA_DIR}/history.json"
readonly CACHE_DIR="${CONFIG_DIR}/.cache"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

ACTION=""
VERBOSE=false

log_debug() {
    [[ "${VERBOSE}" == "true" ]] && echo -e "${GRAY}[DEBUG]${NC} $*" >&2 || true
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

check_python() {
    if ! command -v python3 &> /dev/null; then
        log_error "需要 Python 3 来处理历史数据"
        return 1
    fi
    return 0
}

init_dirs() {
    mkdir -p "${DATA_DIR}"
    mkdir -p "${CACHE_DIR}"
    if [[ ! -f "${HISTORY_FILE}" ]]; then
        echo '{"version":"1.0.0","created_at":"2025-02-09T00:00:00Z","records":[]}' > "${HISTORY_FILE}"
    fi
}

get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

read_history() {
    check_python || return 1
    init_dirs
    cat "${HISTORY_FILE}"
}

write_history() {
    local json_data="$1"
    check_python || return 1
    if ! echo "${json_data}" | python3 -m json.tool > /dev/null 2>&1; then
        log_error "无效的JSON数据"
        return 1
    fi
    echo "${json_data}" | python3 -m json.tool > "${HISTORY_FILE}"
    return 0
}

action_add() {
    local task=""
    local tool=""
    local matched_rule_id=""
    local matched_rule_name=""
    local successful="true"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --task) task="$2"; shift 2 ;;
            --tool) tool="$2"; shift 2 ;;
            --matched-rule-id) matched_rule_id="$2"; shift 2 ;;
            --matched-rule-name) matched_rule_name="$2"; shift 2 ;;
            --successful) successful="$2"; shift 2 ;;
            *) log_error "未知参数: $1"; return 1 ;;
        esac
    done

    if [[ -z "${task}" ]] || [[ -z "${tool}" ]]; then
        log_error "缺少必需参数: --task, --tool"
        return 1
    fi

    [[ -z "${matched_rule_id}" ]] && matched_rule_id="general"
    [[ -z "${matched_rule_name}" ]] && matched_rule_name="General"

    local current_json
    current_json=$(read_history)

    local updated_json
    updated_json=$(python3 - "${task}" "${tool}" "${matched_rule_id}" "${matched_rule_name}" "${successful}" "$(get_timestamp)" "${HISTORY_FILE}" << 'PYEOF'
import json
import sys

task = sys.argv[1]
tool = sys.argv[2]
rule_id = sys.argv[3]
rule_name = sys.argv[4]
successful = sys.argv[5].lower() == 'true'
timestamp = sys.argv[6]
history_file = sys.argv[7]

with open(history_file, 'r') as f:
    data = json.load(f)

records = data.get('records', [])
max_id = 0
for rec in records:
    rec_id = rec.get('id', '0')
    try:
        id_num = int(str(rec_id).split('-')[0]) if '-' in str(rec_id) else int(rec_id)
        max_id = max(max_id, id_num)
    except:
        try:
            max_id = max(max_id, int(rec_id))
        except:
            pass

new_record = {
    'id': str(max_id + 1),
    'timestamp': timestamp,
    'task': task,
    'matched_rule': {'id': rule_id, 'name': rule_name},
    'recommendations': [{'tool': tool, 'score': 500, 'installed': True}],
    'selected_tool': tool,
    'successful': successful
}

data['records'].insert(0, new_record)
if len(data['records']) > 1000:
    data['records'] = data['records'][:1000]

print(json.dumps(data, ensure_ascii=False))
PYEOF
)

    if write_history "${updated_json}"; then
        local new_id
        new_id=$(echo "${updated_json}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['records'][0]['id'])" 2>/dev/null || echo "unknown")
        log_success "历史记录已添加: ID=${new_id}"
        echo "${new_id}"
        return 0
    else
        log_error "添加历史记录失败"
        return 1
    fi
}

action_list() {
    local last_n=""
    local tool_filter=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --last) last_n="$2"; shift 2 ;;
            --tool) tool_filter="$2"; shift 2 ;;
            *) log_error "未知参数: $1"; return 1 ;;
        esac
    done

    local current_json
    current_json=$(read_history)

    python3 - "${last_n}" "${tool_filter}" "${current_json}" << 'PYEOF'
import json
import sys
from datetime import datetime

last_n = sys.argv[1]
tool_filter = sys.argv[2]
history_json = sys.argv[3]

data = json.loads(history_json)
records = data.get('records', [])

if last_n:
    try:
        records = records[:int(last_n)]
    except:
        pass

if tool_filter:
    records = [r for r in records if r.get('selected_tool', '').lower() == tool_filter.lower()]

print("\033[1;34m推荐历史 (共 {} 条记录)\033[0m\n".format(len(records)))

for i, rec in enumerate(records):
    ts = rec.get('timestamp', '')[:16]
    tool = rec.get('selected_tool', 'unknown')
    task = rec.get('task', '')
    rule = rec.get('matched_rule', {}).get('name', 'unknown')
    successful = rec.get('successful', True)
    status = '\033[0;32m✓\033[0m' if successful else '\033[0;31m✗\033[0m'
    
    if len(task) > 40:
        task = task[:37] + '...'
    
    print("{} | {} | {}".format(ts, tool, task))
    print("  规则: {}".format(rule))
    print("  状态: {}".format(status))
    print("  ID: {}".format(rec.get('id', 'N/A')))
    print()

if not records:
    print("\033[0;90m暂无历史记录\033[0m")
else:
    print("提示:")
    print("  使用 --last N 查看最近N条")
    print("  使用 --tool <name> 按工具过滤")
    print("  使用 search <keyword> 搜索任务")
PYEOF
}

action_search() {
    local keyword="$1"
    local tool_filter=""
    local max_results=20

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tool) tool_filter="$2"; shift 2 ;;
            --max) max_results="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "${keyword}" ]]; then
        log_error "请提供搜索关键词"
        return 1
    fi

    local current_json
    current_json=$(read_history)

    python3 - "${keyword}" "${tool_filter}" "${max_results}" "${current_json}" << 'PYEOF'
import json
import sys

keyword = sys.argv[1].lower()
tool_filter = sys.argv[2].lower()
max_results = int(sys.argv[3])
history_json = sys.argv[4]

data = json.loads(history_json)
records = data.get('records', [])

results = []
for rec in records:
    if tool_filter and rec.get('selected_tool', '').lower() != tool_filter:
        continue
    
    task = rec.get('task', '').lower()
    rule = rec.get('matched_rule', {}).get('name', '').lower()
    
    if keyword in task or keyword in rule:
        results.append(rec)
    
    if len(results) >= max_results:
        break

print("\033[1;34m搜索结果: '{}' (找到 {} 条)\033[0m\n".format(sys.argv[1], len(results)))

for i, rec in enumerate(results, 1):
    ts = rec.get('timestamp', '')[:16]
    tool = rec.get('selected_tool', 'unknown')
    rule = rec.get('matched_rule', {}).get('name', 'unknown')
    task = rec.get('task', '')
    
    if len(task) > 50:
        task = task[:47] + '...'
    
    print(". \033[0;36m{}\033[0m | \033[0;33m{}\033[0m".format(i, ts, tool.upper()))
    print("   规则: {}".format(rule))
    print("   任务: {}".format(task))
    print("   ID: {}".format(rec.get('id', 'N/A')))
    print()

if not results:
    print("\033[0;90m未找到匹配的记录\033[0m")
else:
    print("提示: 使用 './history-manager.sh reuse --id <ID>' 重用命令")
PYEOF
}

action_stats() {
    local current_json
    current_json=$(read_history)

    python3 - "${HISTORY_FILE}" << 'PYEOF'
import json
import sys
from datetime import datetime
from collections import Counter

history_file = sys.argv[1]
with open(history_file, 'r') as f:
    data = json.load(f)
records = data.get('records', [])

if not records:
    print("\033[1;34m历史统计\033[0m\n")
    print("\033[0;90m暂无历史记录\033[0m")
    sys.exit(0)

total = len(records)

tool_counter = Counter()
for rec in records:
    tool = rec.get('selected_tool', 'unknown')
    tool_counter[tool] += 1

rule_counter = Counter()
for rec in records:
    rule = rec.get('matched_rule', {}).get('name', 'unknown')
    rule_counter[rule] += 1

successful = sum(1 for rec in records if rec.get('successful', True))
success_rate = (successful / total) * 100

timestamps = []
for rec in records:
    ts = rec.get('timestamp', '')
    if ts:
        try:
            dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
            timestamps.append(dt)
        except:
            pass

avg_per_day = 0
time_range_days = 1
if timestamps:
    earliest = min(timestamps)
    latest = max(timestamps)
    time_range_days = max(1, (latest - earliest).days)
    avg_per_day = total / time_range_days

print("\033[1;34m历史统计\033[0m\n")
print("总记录数: {}".format(total))
print("成功率: {:.1f}%\n".format(success_rate))

print("\033[1m按工具:\033[0m")
for tool, count in tool_counter.most_common():
    pct = (count / total) * 100
    print("  • {:12s} - {:3d} 次 ({:5.1f}%)".format(tool, count, pct))

print()
print("\033[1m按规则类型:\033[0m")
for rule, count in rule_counter.most_common():
    print("  • {:20s} - {:3d} 次".format(rule, count))

if timestamps:
    print()
    print("\033[1m时间范围:\033[0m")
    print("  • 最早: {}".format(earliest.strftime('%Y-%m-%d %H:%M')))
    print("  • 最近: {}".format(latest.strftime('%Y-%m-%d %H:%M')))
    print("  • 平均每天: {:.1f} 次".format(avg_per_day))
PYEOF
}

action_reuse() {
    local record_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id) record_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "${record_id}" ]]; then
        log_error "请指定 --id <记录ID>"
        return 1
    fi

    local current_json
    current_json=$(read_history)

    python3 - "${record_id}" "${CACHE_DIR}" "${current_json}" << 'PYEOF'
import json
import sys

record_id = sys.argv[1]
cache_dir = sys.argv[2]
history_json = sys.argv[3]

data = json.loads(history_json)
records = data.get('records', [])

found = None
for rec in records:
    if str(rec.get('id', '')) == str(record_id):
        found = rec
        break

if not found:
    print("\033[0;31m未找到记录: {}\033[0m".format(record_id))
    sys.exit(1)

print("\033[1;34m历史记录详情:\033[0m")
print("ID: {}".format(found.get('id', '')))
print("时间: {}".format(found.get('timestamp', '')[:19]))
print("工具: {}".format(found.get('selected_tool', '').upper()))
print("规则: {}".format(found.get('matched_rule', {}).get('name', '')))
print("任务: {}".format(found.get('task', '')))
print("成功: {}".format('是' if found.get('successful', True) else '否'))
print()

tool = found.get('selected_tool', '')
task = found.get('task', '')
command = "{} '{}'".format(tool, task)

print("\033[1;33m建议命令:\033[0m")
print(command)
print()

with open(cache_dir + '/reuse_command.txt', 'w') as f:
    f.write(command)

print("命令已保存到: {}/reuse_command.txt".format(cache_dir))
PYEOF
}

action_cleanup() {
    local days=""
    local count=""
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days) days="$2"; shift 2 ;;
            --count) count="$2"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            *) log_error "未知参数: $1"; return 1 ;;
        esac
    done

    if [[ -z "${days}" ]] && [[ -z "${count}" ]]; then
        log_error "请指定 --days <天数> 或 --count <数量>"
        return 1
    fi

    local current_json
    current_json=$(read_history)

    local updated_json
    updated_json=$(python3 - "${days}" "${count}" "${current_json}" << 'PYEOF'
import json
import sys
from datetime import datetime, timedelta

days = sys.argv[1]
count = sys.argv[2]
history_json = sys.argv[3]

data = json.loads(history_json)
records = data.get('records', [])
original_count = len(records)

if days:
    try:
        days_val = int(days)
        cutoff = datetime.now() - timedelta(days=days_val)
        filtered = []
        for r in records:
            try:
                ts = datetime.fromisoformat(r.get('timestamp', '').replace('Z', '+00:00'))
                if ts >= cutoff:
                    filtered.append(r)
            except:
                filtered.append(r)
        records = filtered
    except:
        pass

if count:
    try:
        count_val = int(count)
        records = records[:count_val]
    except:
        pass

data['records'] = records

kept = len(records)
removed = original_count - kept

print("清理完成: 保留 {} 条, 删除 {} 条".format(kept, removed))
print(json.dumps(data, ensure_ascii=False))
PYEOF
)

    if [[ "${dry_run}" == "true" ]]; then
        echo "预览模式: 不会实际删除"
    else
        # Extract only the JSON part (second line onwards)
        write_history "$(echo "${updated_json}" | tail -n +2)"
    fi
}

action_export() {
    local format="json"
    local output_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format) format="$2"; shift 2 ;;
            --output|-o) output_file="$2"; shift 2 ;;
            *) log_error "未知参数: $1"; return 1 ;;
        esac
    done

    local current_json
    current_json=$(read_history)

    case "${format}" in
        json)
            if [[ -n "${output_file}" ]]; then
                echo "${current_json}" | python3 -m json.tool > "${output_file}"
                log_success "已导出到: ${output_file}"
            else
                echo "${current_json}" | python3 -m json.tool
            fi
            ;;
        csv)
            python3 - "${output_file}" "${current_json}" << 'PYEOF'
import json
import csv
import sys

output_file = sys.argv[1]
history_json = sys.argv[2]

data = json.loads(history_json)
records = data.get('records', [])

if output_file:
    csvfile = open(output_file, 'w', newline='', encoding='utf-8')
else:
    csvfile = sys.stdout

writer = csv.writer(csvfile)
writer.writerow(['ID', 'Timestamp', 'Tool', 'Rule', 'Task', 'Successful'])

for rec in records:
    writer.writerow([
        rec.get('id', ''),
        rec.get('timestamp', ''),
        rec.get('selected_tool', ''),
        rec.get('matched_rule', {}).get('name', ''),
        rec.get('task', ''),
        rec.get('successful', True)
    ])

if csvfile != sys.stdout:
    csvfile.close()
    print("已导出 {} 条记录到: {}".format(len(records), output_file))
PYEOF
            ;;
        *)
            log_error "不支持的导出格式: ${format}"
            return 1
            ;;
    esac
}

action_clear() {
    local confirm=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --confirm|-y) confirm=true; shift ;;
            *) log_error "未知参数: $1"; return 1 ;;
        esac
    done

    if [[ "${confirm}" != "true" ]]; then
        echo "警告: 此操作将清空所有历史记录"
        echo "请使用 --confirm 确认操作"
        return 1
    fi

    echo '{"version":"1.0.0","created_at":"2025-02-09T00:00:00Z","records":[]}' > "${HISTORY_FILE}"
    log_success "历史记录已清空"
}

show_help() {
    cat << EOF
${BOLD}AI CLI Tools - 历史记录管理器${NC} v${SCRIPT_VERSION}

${BOLD}用法:${NC}
  ${SCRIPT_NAME} <action> [options]

${BOLD}操作:${NC}
  ${CYAN}add${NC}        添加新的历史记录
  ${CYAN}list${NC}       列出历史记录
  ${CYAN}search${NC}     搜索历史记录
  ${CYAN}stats${NC}      显示统计信息
  ${CYAN}reuse${NC}      重用历史命令
  ${CYAN}cleanup${NC}    清理旧记录
  ${CYAN}export${NC}     导出历史数据
  ${CYAN}clear${NC}      清空所有历史
  ${CYAN}help${NC}       显示此帮助

${BOLD}示例:${NC}
  # 添加记录
  ${SCRIPT_NAME} add --task "总结这段文字" --tool "claude"

  # 查看最近10条
  ${SCRIPT_NAME} list --last 10

  # 搜索记录
  ${SCRIPT_NAME} search "代码"

  # 按工具过滤
  ${SCRIPT_NAME} list --tool claude

  # 查看统计
  ${SCRIPT_NAME} stats

  # 重用命令
  ${SCRIPT_NAME} reuse --id 1

  # 清理记录
  ${SCRIPT_NAME} cleanup --days 30

  # 导出数据
  ${SCRIPT_NAME} export --format json --output history.json

EOF
}

main() {
    if [[ $# -eq 0 ]] || [[ "$1" == "help" ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_help
        exit 0
    fi

    ACTION="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v) VERBOSE=true; shift ;;
            *) break ;;
        esac
    done

    init_dirs

    case "${ACTION}" in
        add) action_add "$@" ;;
        list) action_list "$@" ;;
        search) action_search "$@" ;;
        stats) action_stats ;;
        reuse) action_reuse "$@" ;;
        cleanup) action_cleanup "$@" ;;
        export) action_export "$@" ;;
        clear) action_clear "$@" ;;
        *)
            log_error "未知操作: ${ACTION}"
            echo "运行 '${SCRIPT_NAME} help' 查看帮助"
            exit 1
            ;;
    esac
}

main "$@"
