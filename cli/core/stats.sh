#!/bin/bash
# ==============================================================================
# AI CLI Tools - Usage Statistics Module
# ==============================================================================
# Version: 1.0.0
# Description: 统计分析工具使用情况、任务类型分布、推荐准确率等
# Usage: ./stats.sh [action] [options]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
readonly CONFIG_DIR="${HOME}/.config/ai-tools"
readonly DATA_DIR="${CONFIG_DIR}/data"
readonly HISTORY_FILE="${DATA_DIR}/history.json"
readonly STATS_CACHE_FILE="${DATA_DIR}/stats.json"
readonly CACHE_DIR="${CONFIG_DIR}/.cache"

# Default cache TTL: 1 hour (3600 seconds)
DEFAULT_CACHE_TTL=3600
CACHE_TTL=${CACHE_TTL:-$DEFAULT_CACHE_TTL}

# ==============================================================================
# Colors
# ==============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly GRAY='\033[0;90m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ==============================================================================
# Global Variables
# ==============================================================================
ACTION="overview"
DAYS=7
TOOL_NAME=""
SORT_BY="usage"
EXPORT_FORMAT="text"
HEATMAP_TYPE="hour"
FORCE_REFRESH=false
CACHE_ONLY=false
CLEAR_CACHE=false

# ==============================================================================
# Utility Functions
# ==============================================================================

log_debug() {
    [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${GRAY}[DEBUG]${NC} $*" >&2
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

check_python() {
    if ! command -v python3 &> /dev/null; then
        log_error "需要 Python 3 来处理统计数据"
        return 1
    fi
    return 0
}

# Ensure directories exist
init_dirs() {
    mkdir -p "${DATA_DIR}"
    mkdir -p "${CACHE_DIR}"
}

# Read history file
read_history() {
    if [[ ! -f "${HISTORY_FILE}" ]]; then
        echo "{\"version\": \"1.0.0\", \"created_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"records\": []}"
        return 0
    fi
    cat "${HISTORY_FILE}"
}

# Check if cache is valid
is_cache_valid() {
    if [[ ! -f "${STATS_CACHE_FILE}" ]]; then
        return 1
    fi

    local cache_age
    cache_age=$(($(date +%s) - $(stat -f %m "${STATS_CACHE_FILE}" 2>/dev/null || stat -c %Y "${STATS_CACHE_FILE}" 2>/dev/null)))

    if [[ ${cache_age} -ge ${CACHE_TTL} ]]; then
        return 1
    fi

    return 0
}

# Get cached stats or generate new ones
get_or_generate_stats() {
    if [[ "${FORCE_REFRESH}" == "true" ]] || ! is_cache_valid; then
        log_debug "生成新的统计数据..."
        generate_stats_cache
    fi

    cat "${STATS_CACHE_FILE}"
}

# Generate statistics cache
generate_stats_cache() {
    local history_data
    history_data=$(read_history)

    python3 - "${history_data}" "${STATS_CACHE_FILE}" << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys
from datetime import datetime
from collections import defaultdict

history_json = sys.argv[1]
cache_file = sys.argv[2]

try:
    history = json.loads(history_json)
    records = history.get('records', [])

    # Initialize statistics
    stats = {
        'version': '1.0.0',
        'generated_at': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
        'period': {
            'start': None,
            'end': None,
            'days': 0
        },
        'summary': {
            'total_recommendations': 0,
            'successful': 0,
            'failed': 0,
            'success_rate': 0.0,
            'avg_per_day': 0.0
        },
        'tools': {},
        'task_types': {},
        'time_distribution': {
            'by_date': {},
            'by_weekday': defaultdict(int),
            'by_hour': defaultdict(int),
            'by_period': {'morning': 0, 'afternoon': 0, 'evening': 0}
        },
        'top_tasks': []
    }

    if not records:
        stats['period']['start'] = datetime.utcnow().strftime('%Y-%m-%d')
        stats['period']['end'] = datetime.utcnow().strftime('%Y-%m-%d')
        with open(cache_file, 'w') as f:
            json.dump(stats, f, ensure_ascii=False, indent=2)
        sys.exit(0)

    # Parse timestamps and determine period
    timestamps = []
    for r in records:
        ts = r.get('timestamp', '')
        if ts:
            try:
                dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
                timestamps.append(dt)
            except:
                pass

    if timestamps:
        timestamps.sort()
        stats['period']['start'] = timestamps[0].strftime('%Y-%m-%d')
        stats['period']['end'] = timestamps[-1].strftime('%Y-%m-%d')
        stats['period']['days'] = max(1, (timestamps[-1] - timestamps[0]).days + 1)

    # Process records
    for record in records:
        stats['summary']['total_recommendations'] += 1

        # Success/failure
        if record.get('successful', True):
            stats['summary']['successful'] += 1
        else:
            stats['summary']['failed'] += 1

        # Tool usage
        selected_tool = record.get('selected_tool', 'unknown')
        if selected_tool:
            if selected_tool not in stats['tools']:
                stats['tools'][selected_tool] = {
                    'count': 0,
                    'successful': 0,
                    'failed': 0,
                    'task_types': defaultdict(int),
                    'by_period': {'morning': 0, 'afternoon': 0, 'evening': 0},
                    'by_date': defaultdict(int)
                }
            stats['tools'][selected_tool]['count'] += 1
            if record.get('successful', True):
                stats['tools'][selected_tool]['successful'] += 1
            else:
                stats['tools'][selected_tool]['failed'] += 1

        # Task type
        matched_rule = record.get('matched_rule', {})
        task_type_id = matched_rule.get('id', 'unknown')
        task_type_name = matched_rule.get('name', 'Unknown')
        if task_type_id not in stats['task_types']:
            stats['task_types'][task_type_id] = {
                'name': task_type_name,
                'count': 0
            }
        stats['task_types'][task_type_id]['count'] += 1

        # Update tool's task types
        if selected_tool and task_type_id:
            stats['tools'][selected_tool]['task_types'][task_type_id] += 1

        # Time distribution
        ts = record.get('timestamp', '')
        if ts:
            try:
                dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))

                # By date
                date_key = dt.strftime('%Y-%m-%d')
                stats['time_distribution']['by_date'][date_key] = \
                    stats['time_distribution']['by_date'].get(date_key, 0) + 1

                # By weekday
                weekday_key = dt.strftime('%A')
                stats['time_distribution']['by_weekday'][weekday_key] += 1

                # By hour
                hour = dt.hour
                stats['time_distribution']['by_hour'][hour] += 1

                # By period
                if 6 <= hour < 12:
                    period = 'morning'
                elif 12 <= hour < 18:
                    period = 'afternoon'
                else:
                    period = 'evening'
                stats['time_distribution']['by_period'][period] += 1

                # Update tool's period distribution
                if selected_tool:
                    stats['tools'][selected_tool]['by_period'][period] += 1

                # Update tool's by_date
                if selected_tool:
                    stats['tools'][selected_tool]['by_date'][date_key] += 1

            except:
                pass

    # Calculate success rate
    total = stats['summary']['total_recommendations']
    if total > 0:
        stats['summary']['success_rate'] = round(
            (stats['summary']['successful'] / total) * 100, 1
        )
        stats['summary']['avg_per_day'] = round(
            total / stats['period']['days'], 1
        )

    # Convert defaultdicts to regular dicts
    stats['time_distribution']['by_weekday'] = dict(stats['time_distribution']['by_weekday'])
    stats['time_distribution']['by_hour'] = dict(stats['time_distribution']['by_hour'])
    stats['time_distribution']['by_date'] = dict(stats['time_distribution']['by_date'])

    for tool in stats['tools']:
        stats['tools'][tool]['task_types'] = dict(stats['tools'][tool]['task_types'])
        stats['tools'][tool]['by_date'] = dict(stats['tools'][tool]['by_date'])

    # Sort task types by count
    sorted_task_types = sorted(
        stats['task_types'].items(),
        key=lambda x: x[1]['count'],
        reverse=True
    )
    stats['task_types'] = dict(sorted_task_types)

    # Sort tools by usage
    sorted_tools = sorted(
        stats['tools'].items(),
        key=lambda x: x[1]['count'],
        reverse=True
    )
    stats['tools'] = dict(sorted_tools)

    # Top tasks
    stats['top_tasks'] = [
        {'task': r.get('task', ''), 'tool': r.get('selected_tool', ''),
         'timestamp': r.get('timestamp', '')}
        for r in records[-10:]
    ]

    # Write cache
    with open(cache_file, 'w') as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)

except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(1)
PYEOF
}

# Clear cache
clear_stats_cache() {
    rm -f "${STATS_CACHE_FILE}"
    echo "统计缓存已清除"
}

# ==============================================================================
# Visualization Functions
# ==============================================================================

# Generate progress bar
make_progress_bar() {
    local value=$1
    local max=$2
    local width=${3:-30}
    local char=${4:-█}

    if [[ ${max} -eq 0 ]]; then
        echo ""
        return
    fi

    local percentage=$((value * 100 / max))
    local filled=$((value * width / max))
    local empty=$((width - filled))

    local bar=""
    for ((i = 0; i < filled; i++)); do
        bar+="${char}"
    done
    for ((i = 0; i < empty; i++)); do
        bar+=" "
    done

    echo "${bar}"
}

# ==============================================================================
# Output Functions
# ==============================================================================

# Overview statistics
show_overview() {
    local stats_json
    stats_json=$(get_or_generate_stats)

    python3 - "${stats_json}" << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys

stats = json.loads(sys.argv[1])

# Colors for terminal
CYAN = '\033[0;36m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
BOLD = '\033[1m'
NC = '\033[0m'

def make_bar(value, max_value, width=30):
    if max_value == 0:
        return " " * width
    filled = int(value * width / max_value)
    return "█" * filled + " " * (width - filled)

print(f"{CYAN}{BOLD}📊 使用统计总览{NC}")
print()
print(f"📅 统计周期: {stats['period']['start']} 至 {stats['period']['end']} ({stats['period']['days']}天)")
print()

# Summary
summary = stats['summary']
print(f"{BOLD}📈 总体数据:{NC}")
print(f"  总推荐次数: {summary['total_recommendations']}")
print(f"  平均每天: {summary['avg_per_day']} 次")
print(f"  成功率: {GREEN}{summary['success_rate']}%{NC} ({summary['successful']}/{summary['total_recommendations']})")
print()

# Top tools
print(f"{BOLD}🏆 最常用工具 TOP 5:{NC}")
tools = list(stats['tools'].items())[:5]
if tools:
    max_count = tools[0][1]['count']
    for i, (tool, data) in enumerate(tools, 1):
        count = data['count']
        percentage = round(count / summary['total_recommendations'] * 100, 1)
        bar = make_bar(count, max_count)
        print(f"  {i}. {tool:<10} {YELLOW}{bar}{NC} {count}次 ({percentage}%)")
else:
    print("  暂无数据")
print()

# Task types
print(f"{BOLD}📋 任务类型分布:{NC}")
task_types = list(stats['task_types'].items())[:10]
if task_types:
    max_count = task_types[0][1]['count']
    for task_id, data in task_types:
        count = data['count']
        name = data['name']
        percentage = round(count / summary['total_recommendations'] * 100, 1)
        bar = make_bar(count, max_count, 24)
        print(f"  • {task_id:<20} - {count}次 ({percentage:>5}%) {YELLOW}{bar}{NC}")
else:
    print("  暂无数据")
print()

# Time trend by weekday
weekday_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
weekday_names = {'Monday': '周一', 'Tuesday': '周二', 'Wednesday': '周三',
                 'Thursday': '周四', 'Friday': '周五', 'Saturday': '周六', 'Sunday': '周日'}

print(f"{BOLD}⏰ 时间趋势:{NC}")
by_weekday = stats['time_distribution']['by_weekday']
max_count = max(by_weekday.values()) if by_weekday else 1

for day in weekday_order:
    count = by_weekday.get(day, 0)
    bar = make_bar(count, max_count, 20)
    zh_day = weekday_names[day]
    print(f"  {zh_day} {YELLOW}{bar}{NC} {count}")
PYEOF
}

# Tool statistics
show_tools() {
    local stats_json
    stats_json=$(get_or_generate_stats)

    python3 - "${stats_json}" "${TOOL_NAME}" "${SORT_BY}" << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys

stats = json.loads(sys.argv[1])
tool_filter = sys.argv[2] if sys.argv[2] else None
sort_by = sys.argv[3] if len(sys.argv) > 3 else 'usage'

# Colors
CYAN = '\033[0;36m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
BOLD = '\033[1m'
NC = '\033[0m'

def make_bar(value, max_value, width=20):
    if max_value == 0:
        return " " * width
    filled = int(value * width / max_value)
    return "█" * filled + " " * (width - filled)

tools_data = stats['tools']

# Filter by tool name if specified
if tool_filter:
    tools_data = {k: v for k, v in tools_data.items() if k.startswith(tool_filter)}

# Sort tools
if sort_by == 'usage':
    tools_list = sorted(tools_data.items(), key=lambda x: x[1]['count'], reverse=True)
elif sort_by == 'success':
    tools_list = sorted(tools_data.items(),
                       key=lambda x: x[1]['successful'] / max(x[1]['count'], 1),
                       reverse=True)
else:
    tools_list = sorted(tools_data.items(), key=lambda x: x[1]['count'], reverse=True)

print(f"{CYAN}{BOLD}🔧 工具使用统计{NC}")
print()

total_rec = stats['summary']['total_recommendations']

for tool, data in tools_list:
    count = data['count']
    successful = data['successful']
    failed = data['failed']
    percentage = round(count / total_rec * 100, 1) if total_rec > 0 else 0
    success_rate = round(successful / count * 100, 1) if count > 0 else 0

    print(f"{BOLD}{tool} 详细统计{NC}")
    print(f"使用次数: {count}次 ({percentage}%)")
    print(f"成功率: {GREEN}{success_rate}%{NC} ({successful}/{count})")
    print()

    # Task types for this tool
    task_types = data.get('task_types', {})
    if task_types:
        print("常用任务类型:")
        sorted_types = sorted(task_types.items(), key=lambda x: x[1], reverse=True)[:5]
        max_count = sorted_types[0][1] if sorted_types else 1
        for task_id, type_count in sorted_types:
            type_pct = round(type_count / count * 100, 1)
            bar = make_bar(type_count, max_count, 16)
            print(f"  • {task_id:<20} - {type_count}次 ({type_pct:>5}%) {YELLOW}{bar}{NC}")
    print()

    # Time period distribution
    periods = data.get('by_period', {})
    if periods:
        print("时间分布:")
        period_names = {'morning': '早晨 (6-12)', 'afternoon': '下午 (12-18)', 'evening': '晚上 (18-24)'}
        for period_key, period_count in periods.items():
            period_pct = round(period_count / count * 100, 1) if count > 0 else 0
            print(f"  {period_names[period_key]:<15} {period_count}次 ({period_pct}%)")
    print()

    # Recent 7-day trend
    by_date = data.get('by_date', {})
    if by_date:
        dates = sorted(by_date.keys())[-7:]
        if dates:
            print("最近7天趋势:")
            max_count = max(by_date[d] for d in dates) if dates else 1
            for date_key in dates:
                date_count = by_date[date_key]
                date_short = date_key[5:]  # MM-DD
                bar = make_bar(date_count, max_count, 16)
                print(f"  {date_short}: {YELLOW}{bar}{NC} {date_count}")
    print()
    print("─" * 60)
    print()
PYEOF
}

# Task type distribution
show_tasks() {
    local stats_json
    stats_json=$(get_or_generate_stats)

    python3 - "${stats_json}" << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys

stats = json.loads(sys.argv[1])

# Colors
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
BOLD = '\033[1m'
NC = '\033[0m'

def make_bar(value, max_value, width=30):
    if max_value == 0:
        return " " * width
    filled = int(value * width / max_value)
    return "█" * filled + " " * (width - filled)

print(f"{CYAN}{BOLD}📋 任务类型分布{NC}")
print()

task_types = stats['task_types']
total = stats['summary']['total_recommendations']

if task_types:
    max_count = list(task_types.values())[0]['count']

    for task_id, data in task_types.items():
        count = data['count']
        name = data['name']
        percentage = round(count / total * 100, 1)
        bar = make_bar(count, max_count)
        print(f"• {task_id:<20} {name}")
        print(f"  {count}次 ({percentage}%) {YELLOW}{bar}{NC}")
        print()
else:
    print("暂无任务类型数据")
PYEOF
}

# Time trend
show_trend() {
    local stats_json
    stats_json=$(get_or_generate_stats)

    python3 - "${stats_json}" "${DAYS}" << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys
from datetime import datetime, timedelta

stats = json.loads(sys.argv[1])
days = int(sys.argv[2])

# Colors
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
BOLD = '\033[1m'
NC = '\033[0m'

def make_bar(value, max_value, width=25):
    if max_value == 0:
        return " " * width
    filled = int(value * width / max_value)
    return "█" * filled + " " * (width - filled)

print(f"{CYAN}{BOLD}📈 时间趋势分析 (最近{days}天){NC}")
print()

by_date = stats['time_distribution']['by_date']

# Get last N days
end_date = datetime.strptime(stats['period']['end'], '%Y-%m-%d')
date_range = []
for i in range(days - 1, -1, -1):
    d = end_date - timedelta(days=i)
    date_range.append(d.strftime('%Y-%m-%d'))

max_count = max([by_date.get(d, 0) for d in date_range]) if date_range else 1

for date_key in date_range:
    count = by_date.get(date_key, 0)
    date_short = date_key[5:].replace('-', '/')
    bar = make_bar(count, max_count)
    print(f"{date_short} {YELLOW}{bar}{NC} {count}")
PYEOF
}

# Heatmap
show_heatmap() {
    local stats_json
    stats_json=$(get_or_generate_stats)

    python3 - "${stats_json}" "${HEATMAP_TYPE}" << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys

stats = json.loads(sys.argv[1])
heatmap_type = sys.argv[2]

# Colors
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
GREEN = '\033[0;32m'
BOLD = '\033[1m'
NC = '\033[0m'

def get_heat_block(value, max_value):
    """Get colored block for heatmap"""
    if max_value == 0:
        return ' '
    ratio = value / max_value
    if ratio == 0:
        return ' '
    elif ratio < 0.25:
        return f'{GREEN}▂{NC}'
    elif ratio < 0.5:
        return f'{YELLOW}▃{NC}'
    elif ratio < 0.75:
        return f'{YELLOW}▅{NC}'
    else:
        return f'{RED}▇{NC}'

if heatmap_type == 'hour':
    print(f"{CYAN}{BOLD}⏰ 使用热力图 - 按小时 (0-23时){NC}")
    print()

    by_hour = stats['time_distribution']['by_hour']
    max_count = max(by_hour.values()) if by_hour else 1

    # Find peak hours
    sorted_hours = sorted(by_hour.items(), key=lambda x: int(x[0]) if isinstance(x[0], str) else x[0], reverse=False)
    peak_hours = [int(h) if isinstance(h, str) else h for h, c in sorted(by_hour.items(), key=lambda x: x[1], reverse=True)[:3] if c > max_count * 0.5]

    for hour in range(24):
        count = by_hour.get(str(hour), 0)
        bar_width = int(count * 20 / max_count) if max_count > 0 else 0
        bar = '█' * bar_width
        hour_str = f"{hour:2d}"
        print(f"  {hour_str}  {YELLOW}{bar}{NC}")

    print()
    peak_str = ', '.join([f'{h}时' for h in peak_hours]) if peak_hours else '无'
    print(f"高峰时段: {peak_str}")

elif heatmap_type == 'weekday':
    print(f"{CYAN}{BOLD}📅 使用热力图 - 按星期{NC}")
    print()

    weekday_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    weekday_names = {'Monday': '周一', 'Tuesday': '周二', 'Wednesday': '周三',
                     'Thursday': '周四', 'Friday': '周五', 'Saturday': '周六', 'Sunday': '周日'}

    by_weekday = stats['time_distribution']['by_weekday']
    max_count = max(by_weekday.values()) if by_weekday else 1

    for day in weekday_order:
        count = by_weekday.get(day, 0)
        bar_width = int(count * 25 / max_count) if max_count > 0 else 0
        bar = '█' * bar_width
        print(f"  {weekday_names[day]} {YELLOW}{bar}{NC} {count}")
else:
    print("未知的热力图类型，请使用: hour 或 weekday")
PYEOF
}

# Export statistics
export_stats() {
    local stats_json
    stats_json=$(get_or_generate_stats)

    case "${EXPORT_FORMAT}" in
        json)
            echo "${stats_json}"
            ;;
        markdown)
            python3 - "${stats_json}" << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys
from datetime import datetime

stats = json.loads(sys.argv[1])

print(f"# AI CLI Tools 使用统计报告")
print(f"")
print(f"**生成时间**: {stats['generated_at']}")
print(f"**统计周期**: {stats['period']['start']} 至 {stats['period']['end']} ({stats['period']['days']}天)")
print(f"")

summary = stats['summary']
print(f"## 总体数据")
print(f"")
print(f"| 指标 | 数值 |")
print(f"|------|------|")
print(f"| 总推荐次数 | {summary['total_recommendations']} |")
print(f"| 成功次数 | {summary['successful']} |")
print(f"| 失败次数 | {summary['failed']} |")
print(f"| 成功率 | {summary['success_rate']}% |")
print(f"| 平均每天 | {summary['avg_per_day']} 次 |")
print(f"")

print(f"## 工具使用排名")
print(f"")
print(f"| 排名 | 工具 | 使用次数 | 成功率 | 占比 |")
print(f"|------|------|----------|--------|------|")

total = summary['total_recommendations']
for i, (tool, data) in enumerate(list(stats['tools'].items())[:10], 1):
    count = data['count']
    success_rate = round(data['successful'] / count * 100, 1) if count > 0 else 0
    percentage = round(count / total * 100, 1) if total > 0 else 0
    print(f"| {i} | {tool} | {count} | {success_rate}% | {percentage}% |")
print(f"")

print(f"## 任务类型分布")
print(f"")
print(f"| 任务类型 | 名称 | 次数 | 占比 |")
print(f"|----------|------|------|------|")

for task_id, data in list(stats['task_types'].items())[:10]:
    count = data['count']
    name = data['name']
    percentage = round(count / total * 100, 1) if total > 0 else 0
    print(f"| {task_id} | {name} | {count} | {percentage}% |")
print(f"")

print(f"## 时间趋势")
print(f"")

by_weekday = stats['time_distribution']['by_weekday']
weekday_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
weekday_names = {'Monday': '周一', 'Tuesday': '周二', 'Wednesday': '周三',
                 'Thursday': '周四', 'Friday': '周五', 'Saturday': '周六', 'Sunday': '周日'}

print(f"### 按星期")
print(f"")
max_count = max(by_weekday.values()) if by_weekday else 1
for day in weekday_order:
    count = by_weekday.get(day, 0)
    bar = '█' * int(count * 20 / max_count) if max_count > 0 else ''
    print(f"- {weekday_names[day]}: `{bar}` {count}")
print(f"")

by_hour = stats['time_distribution']['by_hour']
print(f"### 按小时 (0-23)")
print(f"")

max_hour = max([int(v) for v in by_hour.values()]) if by_hour else 1
for hour in range(24):
    count = by_hour.get(str(hour), 0)
    bar = '█' * int(count * 15 / max_hour) if max_hour > 0 else ''
    print(f"- {hour:2d}时: `{bar}` {count}")
PYEOF
            ;;
        csv)
            python3 - "${stats_json}" << 'PYEOF'
# -*- coding: utf-8 -*-
import json
import sys
import csv

stats = json.loads(sys.argv[1])

# CSV Header
print("tool,count,successful,failed,success_rate,percentage")

total = stats['summary']['total_recommendations']

for tool, data in stats['tools'].items():
    count = data['count']
    successful = data['successful']
    failed = data['failed']
    success_rate = round(successful / count * 100, 1) if count > 0 else 0
    percentage = round(count / total * 100, 1) if total > 0 else 0
    print(f"{tool},{count},{successful},{failed},{success_rate},{percentage}")
PYEOF
            ;;
        *)
            log_error "不支持的导出格式: ${EXPORT_FORMAT}"
            echo "支持的格式: json, markdown, csv"
            exit 1
            ;;
    esac
}

# Show help
show_help() {
    cat << EOF
用法: stats.sh [action] [options]

Actions:
  overview              显示总体统计 (默认)
  tools                 工具使用排名和详情
  tasks                 任务类型分布
  trend                 时间趋势
  heatmap               使用热力图
  export                导出统计数据

Options:
  --tool <name>         指定工具名称 (仅用于 tools)
  --by <field>          排序字段: usage (默认), success
  --days <n>            天数，用于 trend (默认: 7)
  --type <type>         热力图类型: hour (默认), weekday
  --format <fmt>        导出格式: json, markdown, csv
  --refresh             强制刷新缓存
  --clear-cache         清除缓存
  --cache-ttl <sec>     缓存有效期 (秒，默认: 3600)
  --verbose, -v         详细输出
  --help, -h            显示帮助

示例:
  # 总体统计
  ./stats.sh overview

  # 工具排名 (按使用频率)
  ./stats.sh tools --by usage

  # 工具排名 (按成功率)
  ./stats.sh tools --by success

  # 特定工具详情
  ./stats.sh tools --tool claude

  # 任务类型分布
  ./stats.sh tasks

  # 时间趋势 (最近7天)
  ./stats.sh trend --days 7

  # 按小时热力图
  ./stats.sh heatmap --type hour

  # 按星期热力图
  ./stats.sh heatmap --type weekday

  # 导出为 Markdown
  ./stats.sh export --format markdown > stats.md

  # 导出为 JSON
  ./stats.sh export --format json > stats.json

  # 导出为 CSV
  ./stats.sh export --format csv > stats.csv

  # 清除缓存
  ./stats.sh --clear-cache

  # 强制刷新并显示
  ./stats.sh overview --refresh
EOF
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            overview|tools|tasks|trend|heatmap|export)
                ACTION="$1"
                shift
                ;;
            --tool)
                TOOL_NAME="$2"
                shift 2
                ;;
            --by)
                SORT_BY="$2"
                shift 2
                ;;
            --days)
                DAYS="$2"
                shift 2
                ;;
            --type)
                HEATMAP_TYPE="$2"
                shift 2
                ;;
            --format)
                EXPORT_FORMAT="$2"
                shift 2
                ;;
            --refresh)
                FORCE_REFRESH=true
                shift
                ;;
            --clear-cache)
                CLEAR_CACHE=true
                shift
                ;;
            --cache-ttl)
                CACHE_TTL="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Initialize
    init_dirs
    check_python || exit 1

    # Handle cache clearing
    if [[ "${CLEAR_CACHE}" == "true" ]]; then
        clear_stats_cache
        exit 0
    fi

    # Execute action
    case "${ACTION}" in
        overview)
            show_overview
            ;;
        tools)
            show_tools
            ;;
        tasks)
            show_tasks
            ;;
        trend)
            show_trend
            ;;
        heatmap)
            show_heatmap
            ;;
        export)
            export_stats
            ;;
    esac
}

main "$@"
