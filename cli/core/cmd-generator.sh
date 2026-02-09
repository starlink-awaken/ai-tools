#!/usr/bin/env bash
# ==============================================================================
# AI CLI Tools - Intelligent Command Generator
# ==============================================================================
# Version: 2.0.0
# Purpose: Generate safe, executable commands from templates with parameter
#          escaping, validation, and security checks
#
# Usage:
#   ./cmd-generator.sh <tool_name> <template> <parameters> [options]
#
# Examples:
#   ./cmd-generator.sh claude "ask '{prompt}'" "prompt=总结这段文字"
#   ./cmd-generator.sh fabric "--pattern {pattern} --input '{input}'" \
#     "pattern=summarize" "input=这是一段需要总结的文字"
#   ./cmd-generator.sh claude "ask '{prompt}'" "prompt=test" --format json
#   ./cmd-generator.sh bash "echo '{input}'" "input=rm -rf /" --safe
# ==============================================================================

# Bash 3.2 compatibility - avoid associative arrays
set -eo pipefail

# ==============================================================================
# Configuration and Constants
# ==============================================================================

SCRIPT_VERSION="2.0.0"
SCRIPT_NAME="$(basename "${0}")"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# Default settings
OUTPUT_FORMAT="text"
VERBOSE=false
SAFE_MODE=false
EXPAND_ENV=true

# Parameters storage (bash 3.2 compatible - using eval)
PARAMETERS=""
WARNINGS=""

# Initialize parameter variables (empty by default)
prompt=""
input=""
model=""
file=""
task=""
tool=""
pattern=""
output=""
url=""
package=""
version=""
user=""
path=""

# ==============================================================================
# Utility Functions
# ==============================================================================

log_debug() {
    [[ "${VERBOSE}" == "true" ]] && echo -e "${GRAY}[DEBUG]${NC} $*" >&2 || true
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

# ==============================================================================
# Help and Version
# ==============================================================================

show_help() {
    cat << EOF
${BOLD}AI CLI Tools - 智能命令生成器${NC} v${SCRIPT_VERSION}

${BOLD}用法:${NC}
  ${SCRIPT_NAME} <tool_name> <template> <parameters> [options]

${BOLD}参数:${NC}
  tool_name      工具名称 (如: claude, fabric, curl)
  template       命令模板，支持占位符
  parameters     key=value 格式的参数列表

${BOLD}占位符:${NC}
  {prompt}       用户提示词
  {input}        输入文本
  {model}        模型名称
  {file}         文件路径
  {task}         任务描述
  {tool}         工具名称

${BOLD}选项:${NC}
  --format, -f   输出格式 (text|json) [默认: text]
  --safe, -s     启用安全模式，检查危险命令
  --no-expand    禁用环境变量展开
  --verbose, -v  详细输出模式
  --help, -h     显示此帮助信息
  --version, -V  显示版本信息

${BOLD}示例:${NC}
  # 基本用法
  ${SCRIPT_NAME} claude "ask '{prompt}'" "prompt=总结这段文字"

  # 多参数
  ${SCRIPT_NAME} fabric "--pattern {pattern} --input '{input}'" \\
    "pattern=summarize" "input=这是一段需要总结的文字"

  # JSON 输出
  ${SCRIPT_NAME} claude "ask '{prompt}'" "prompt=test" --format json

  # 安全模式
  ${SCRIPT_NAME} bash "echo '{input}'" "input=rm -rf /" --safe

${BOLD}安全特性:${NC}
  - 自动参数转义，防止命令注入
  - 危险命令检测
  - 智能引号处理
  - 命令链语法验证

EOF
}

show_version() {
    echo "${SCRIPT_NAME} 版本 ${SCRIPT_VERSION}"
    echo "AI CLI Tools - 智能命令生成器"
}

# ==============================================================================
# Parameter Storage (bash 3.2 compatible)
# ==============================================================================

# Set a parameter value
param_set() {
    local key="$1"
    local value="$2"
    # Map 'tool' to 'tool_param' to avoid conflicts
    if [[ "${key}" == "tool" ]]; then
        key="tool_param"
    fi
    # Escape value for storage
    value="$(echo "${value}" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')"
    PARAMETERS="${PARAMETERS}${key}=\"${value}\" "
    log_debug "设置参数: ${key}=${value}"
}

# Get a parameter value
param_get() {
    local key="$1"
    local default="${2:-}"
    # Evaluate to get the value
    eval "local value=\${${key}:-${default}}"
    printf '%s' "${value}"
}

# Check if parameter exists
param_has() {
    local key="$1"
    eval "[[ -n \"\${${key}:-}\" ]]"
}

# Initialize parameters from storage
param_init() {
    # First clear existing values
    prompt=""
    input=""
    model=""
    file=""
    task=""
    url=""
    package=""
    version=""
    user=""
    path=""
    # Then evaluate stored parameters
    eval "${PARAMETERS}" 2>/dev/null || true
}

# Clear all parameters
param_clear() {
    PARAMETERS=""
    prompt=""
    input=""
    model=""
    file=""
    task=""
    tool_param=""
    pattern=""
    output=""
    url=""
    package=""
    version=""
    user=""
    path=""
}

# Export parameters for use in subshells
param_export() {
    eval "${PARAMETERS}"
    export prompt input model file task tool pattern output
}

# ==============================================================================
# String Escaping Functions
# ==============================================================================

# 单引号转义 - 最安全的转义方式
escape_single_quote() {
    local string="$1"
    # 将单引号替换为 '\''
    string="${string//\'/\'\\\'\'}"
    printf '%s' "${string}"
}

# 双引号转义
escape_double_quote() {
    local string="$1"
    string="${string//\\/\\\\}"  # 反斜杠
    string="${string//\"/\\\"}"  # 双引号
    string="${string//\$/\\\$}"  # 美元符号
    string="${string//\`/\\\`}"  # 反引号
    printf '%s' "${string}"
}

# 用于单引号内部的转义
escape_for_single_quotes() {
    local string="$1"
    printf '%s' "$(escape_single_quote "${string}")"
}

# 检测字符串中是否包含单引号
contains_single_quote() {
    [[ "$1" == *"'"* ]]
}

# 智能引号选择
smart_quote() {
    local string="$1"
    local use_double="${2:-false}"

    if [[ "${use_double}" == "true" ]]; then
        printf '"%s"' "$(escape_double_quote "${string}")"
    else
        printf "'%s'" "$(escape_for_single_quotes "${string}")"
    fi
}

# ==============================================================================
# Placeholder Replacement
# ==============================================================================

# 替换模板中的占位符
replace_placeholders() {
    local template="$1"
    local result="${template}"

    # Initialize parameters
    param_init

    # Replace each placeholder if value exists
    # {prompt}
    if [[ -n "${prompt:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${prompt}")"
        result="${result//\{prompt\}/${escaped}}"
        log_debug "替换 {prompt} -> ${escaped}"
    fi

    # {input}
    if [[ -n "${input:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${input}")"
        result="${result//\{input\}/${escaped}}"
        log_debug "替换 {input} -> ${escaped}"
    fi

    # {model}
    if [[ -n "${model:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${model}")"
        result="${result//\{model\}/${escaped}}"
        log_debug "替换 {model} -> ${escaped}"
    fi

    # {file}
    if [[ -n "${file:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${file}")"
        result="${result//\{file\}/${escaped}}"
        log_debug "替换 {file} -> ${escaped}"
    fi

    # {task}
    if [[ -n "${task:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${task}")"
        result="${result//\{task\}/${escaped}}"
        log_debug "替换 {task} -> ${escaped}"
    fi

    # {tool}
    if [[ -n "${tool_param:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${tool_param}")"
        result="${result//\{tool\}/${escaped}}"
        log_debug "替换 {tool} -> ${escaped}"
    fi

    # {pattern}
    if [[ -n "${pattern:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${pattern}")"
        result="${result//\{pattern\}/${escaped}}"
        log_debug "替换 {pattern} -> ${escaped}"
    fi

    # {output}
    if [[ -n "${output:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${output}")"
        result="${result//\{output\}/${escaped}}"
        log_debug "替换 {output} -> ${escaped}"
    fi

    # {url}
    if [[ -n "${url:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${url}")"
        result="${result//\{url\}/${escaped}}"
        log_debug "替换 {url} -> ${escaped}"
    fi

    # {package}
    if [[ -n "${package:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${package}")"
        result="${result//\{package\}/${escaped}}"
        log_debug "替换 {package} -> ${escaped}"
    fi

    # {version}
    if [[ -n "${version:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${version}")"
        result="${result//\{version\}/${escaped}}"
        log_debug "替换 {version} -> ${escaped}"
    fi

    # {user}
    if [[ -n "${user:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${user}")"
        result="${result//\{user\}/${escaped}}"
        log_debug "替换 {user} -> ${escaped}"
    fi

    # {path}
    if [[ -n "${path:-}" ]]; then
        local escaped="$(escape_for_single_quotes "${path}")"
        result="${result//\{path\}/${escaped}}"
        log_debug "替换 {path} -> ${escaped}"
    fi

    # 处理环境变量展开
    if [[ "${EXPAND_ENV}" == "true" ]]; then
        result="${result//\$HOME/${HOME}}"
        result="${result//\$USER/${USER}}"
        result="${result//\$PWD/${PWD}}"
    fi

    printf '%s' "${result}"
}

# ==============================================================================
# Security Functions
# ==============================================================================

# 添加警告
add_warning() {
    WARNINGS="${WARNINGS}$1
"
}

# 检查是否包含危险命令
check_dangerous_commands() {
    local command="$1"
    local found_dangerous=false

    # Dangerous patterns to check
    local patterns="rm -rf /|rm -rf |rm \.\*|dd if=/dev/zero|dd if=/dev/random|dd if=/dev/urandom|mkfs\.|format c::|:\(\): |:|:& \};:|killall -9|kill -9 -1|chmod 000|chown -R|> /dev/sd|> /dev/nvme|shred|wipefs|fsck"

    local IFS='|'
    for pattern in $patterns; do
        if echo "${command}" | grep -qE "${pattern}"; then
            add_warning "检测到潜在危险命令: ${pattern}"
            found_dangerous=true
        fi
    done

    if [[ "${found_dangerous}" == "true" ]]; then
        return 1
    fi
    return 0
}

# 验证命令链语法
validate_command_chain() {
    local command="$1"
    local errors=""

    # 检查未配对的引号 - 简化检查
    local single_count=$(echo "${command}" | grep -o "'" | wc -l | tr -d ' ')
    local double_count=$(echo "${command}" | grep -o '"' | wc -l | tr -d ' ')

    if [[ $((single_count % 2)) -ne 0 ]]; then
        errors="${errors}未配对的单引号 "
    fi

    if [[ $((double_count % 2)) -ne 0 ]]; then
        errors="${errors}未配对的双引号 "
    fi

    # 检查管道操作符后是否有命令
    if echo "${command}" | grep -qE '\|\s*$'; then
        errors="${errors}管道符后缺少命令 "
    fi

    if [[ -n "${errors}" ]]; then
        for error in $errors; do
            add_warning "语法错误: ${error}"
        done
        return 1
    fi

    return 0
}

# 检查参数中的危险字符
check_dangerous_characters() {
    local value="$1"
    local dangerous=true

    # 在安全模式下检查危险字符
    if [[ "${SAFE_MODE}" == "true" ]]; then
        # 检查未转义的重定向 (简化检查)
        if echo "${value}" | grep -qE '[^\\]>|[^\\]<'; then
            add_warning "参数包含未转义的重定向字符"
            dangerous=false
        fi

        # 检查未转义的管道
        if echo "${value}" | grep -qE '[^\\]\|'; then
            add_warning "参数包含未转义的管道字符"
            dangerous=false
        fi

        # 检查命令替换
        if echo "${value}" | grep -qE '\$\(|`'; then
            add_warning "参数包含命令替换"
            dangerous=false
        fi
    fi

    [[ "${dangerous}" == "true" ]]
}

# ==============================================================================
# Output Formatting
# ==============================================================================

output_text() {
    local tool="$1"
    local template="$2"
    local command="$3"
    local is_safe="$4"

    echo ""
    echo -e "${GREEN}✓ 命令生成成功${NC}"
    echo ""
    echo -e "${BOLD}工具:${NC} ${tool}"
    echo -e "${BOLD}模板:${NC} ${template}"
    echo ""
    echo -e "${BOLD}参数:${NC}"

    # Initialize to show parameters
    param_init

    [[ -n "${prompt:-}" ]] && echo "  prompt=\"${prompt}\""
    [[ -n "${input:-}" ]] && echo "  input=\"${input}\""
    [[ -n "${model:-}" ]] && echo "  model=\"${model}\""
    [[ -n "${file:-}" ]] && echo "  file=\"${file}\""
    [[ -n "${task:-}" ]] && echo "  task=\"${task}\""
    [[ -n "${tool_param:-}" ]] && echo "  tool=\"${tool_param}\""
    [[ -n "${pattern:-}" ]] && echo "  pattern=\"${pattern}\""
    [[ -n "${output:-}" ]] && echo "  output=\"${output}\""
    [[ -n "${url:-}" ]] && echo "  url=\"${url}\""
    [[ -n "${package:-}" ]] && echo "  package=\"${package}\""
    [[ -n "${version:-}" ]] && echo "  version=\"${version}\""
    [[ -n "${user:-}" ]] && echo "  user=\"${user}\""
    [[ -n "${path:-}" ]] && echo "  path=\"${path}\""

    echo ""
    echo -e "${BOLD}生成命令:${NC}"
    echo -e "${CYAN}  ${command}${NC}"
    echo ""
    echo -e "${BOLD}安全检查:${NC}"

    if [[ "${is_safe}" == "true" ]]; then
        echo -e "  ${GREEN}✓${NC} 无危险命令"
    else
        echo -e "  ${YELLOW}⚠${NC} 检测到潜在危险命令"
    fi

    if [[ -z "${WARNINGS}" ]]; then
        echo -e "  ${GREEN}✓${NC} 参数已转义"
        echo -e "  ${GREEN}✓${NC} 语法有效"
    else
        echo -e "  ${YELLOW}⚠${NC} 发现警告:"
        echo "${WARNINGS}" | while read -r warning; do
            [[ -n "${warning}" ]] && echo "    - ${warning}"
        done
    fi
    echo ""
}

output_json() {
    local tool="$1"
    local template="$2"
    local command="$3"
    local is_safe="$4"

    # JSON escape function
    json_escape() {
        local string="$1"
        string="${string//\\/\\\\}"   # 反斜杠
        string="${string//\"/\\\"}"   # 双引号
        string="${string//$'\n'/\\n}" # 换行
        string="${string//$'\r'/\\r}" # 回车
        string="${string//$'\t'/\\t}" # 制表符
        string="${string//\$/\\\$}"   # 美元符号
        printf '%s' "${string}"
    }

    # Build JSON manually
    local json="{"
    json+="\"tool\":\"$(json_escape "${tool}")\","
    json+="\"template\":\"$(json_escape "${template}")\","
    json+="\"parameters\":{"

    local first=true
    param_init

    if [[ -n "${prompt:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"prompt\":\"$(json_escape "${prompt}")\""
    fi
    if [[ -n "${input:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"input\":\"$(json_escape "${input}")\""
    fi
    if [[ -n "${model:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"model\":\"$(json_escape "${model}")\""
    fi
    if [[ -n "${file:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"file\":\"$(json_escape "${file}")\""
    fi
    if [[ -n "${task:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"task\":\"$(json_escape "${task}")\""
    fi
    if [[ -n "${tool_param:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"tool\":\"$(json_escape "${tool_param}")\""
    fi
    if [[ -n "${pattern:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"pattern\":\"$(json_escape "${pattern}")\""
    fi
    if [[ -n "${output:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"output\":\"$(json_escape "${output}")\""
    fi
    if [[ -n "${url:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"url\":\"$(json_escape "${url}")\""
    fi
    if [[ -n "${package:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"package\":\"$(json_escape "${package}")\""
    fi
    if [[ -n "${version:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"version\":\"$(json_escape "${version}")\""
    fi
    if [[ -n "${user:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"user\":\"$(json_escape "${user}")\""
    fi
    if [[ -n "${path:-}" ]]; then
        if [[ "${first}" != "true" ]]; then json+=","; fi
        first=false
        json+="\"path\":\"$(json_escape "${path}")\""
    fi

    json+="},"
    json+="\"command\":\"$(json_escape "${command}")\","
    json+="\"escaped\":true,"
    json+="\"safe\":${is_safe},"
    json+="\"warnings\":["

    local first_warning=true
    if [[ -n "${WARNINGS}" ]]; then
        echo "${WARNINGS}" | while read -r warning; do
            if [[ -n "${warning}" ]]; then
                if [[ "${first_warning}" != "true" ]]; then
                    echo -n ","
                fi
                first_warning=false
                echo -n "\"$(json_escape "${warning}")\""
            fi
        done
    fi

    json+="]}"
    echo "${json}"
}

# ==============================================================================
# Main Generation Logic
# ==============================================================================

generate_command() {
    local tool_name="$1"
    local template="$2"

    log_debug "开始生成命令 - 工具: ${tool_name}, 模板: ${template}"

    # 替换占位符
    local replaced_template
    replaced_template="$(replace_placeholders "${template}")"

    # 构建完整命令
    local full_command="${tool_name} ${replaced_template}"

    # 验证命令
    local is_safe=true

    if ! check_dangerous_commands "${full_command}"; then
        is_safe=false
    fi

    if ! validate_command_chain "${full_command}"; then
        is_safe=false
    fi

    # 检查参数
    param_init
    [[ -n "${prompt:-}" ]] && check_dangerous_characters "${prompt}" || true
    [[ -n "${input:-}" ]] && check_dangerous_characters "${input}" || true
    [[ -n "${model:-}" ]] && check_dangerous_characters "${model}" || true
    [[ -n "${file:-}" ]] && check_dangerous_characters "${file}" || true
    [[ -n "${task:-}" ]] && check_dangerous_characters "${task}" || true

    # 输出结果
    if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
        output_json "${tool_name}" "${template}" "${full_command}" "${is_safe}"
    else
        output_text "${tool_name}" "${template}" "${full_command}" "${is_safe}"
    fi

    # 根据安全状态返回
    if [[ "${is_safe}" == "false" ]]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# Main Entry Point
# ==============================================================================

main() {
    # Clear parameters
    param_clear

    # 首先检查 help 和 version 选项（无需参数）
    for arg in "$@"; do
        case "${arg}" in
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-V)
                show_version
                exit 0
                ;;
        esac
    done

    # 检查最小参数数量
    if [[ $# -lt 2 ]]; then
        log_error "参数不足"
        echo "使用 --help 查看帮助信息" >&2
        exit 1
    fi

    # 获取位置参数
    local tool_name="$1"
    local template="$2"
    shift 2

    # 解析选项和参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format|-f)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --safe|-s)
                SAFE_MODE=true
                shift
                ;;
            --no-expand)
                EXPAND_ENV=false
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h|--version|-V)
                # Already handled above
                shift
                ;;
            *=*)
                local key="${1%%=*}"
                local value="${1#*=}"
                param_set "${key}" "${value}"
                shift
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    # 验证工具名称
    if [[ -z "${tool_name}" ]]; then
        log_error "工具名称不能为空"
        exit 1
    fi

    # 验证模板
    if [[ -z "${template}" ]]; then
        log_error "模板不能为空"
        exit 1
    fi

    # 生成命令
    if ! generate_command "${tool_name}" "${template}"; then
        if [[ "${OUTPUT_FORMAT}" == "text" ]]; then
            log_warn "命令生成完成，但存在安全问题"
        fi
        exit 1
    fi

    exit 0
}

# Run main
main "$@"
