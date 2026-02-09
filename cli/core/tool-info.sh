#!/bin/bash
# ==============================================================================
# AI CLI Tools - Tool Info Module
# ==============================================================================
# Version: 1.0.0
# Purpose: Display detailed information about a specific AI CLI tool
#
# Usage:
#   ./tool-info.sh <tool_name> [options]
# ==============================================================================

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
readonly TOOLS_YAML="$CONFIG_DIR/tools.yaml"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

OUTPUT_FORMAT="text"
VERBOSE=false

TOOL_NAME=""
TOOL_DISPLAY_NAME=""
TOOL_DESCRIPTION=""
TOOL_CATEGORY=""
TOOL_URL=""
TOOL_INSTALL_COMMAND=""
TOOL_INSTALL_VERIFY=""
TOOL_REQUIRES=""
TOOL_ENV_VARS=""
TOOL_COMMANDS=""

INSTALL_STATUS="not_installed"
INSTALL_VERSION=""

error_exit() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

print_header() {
    local text="$1"
    echo -e "${CYAN}${BOLD}$text${NC}"
}

print_indent() {
    local content="$1"
    local indent="${2:-2}"
    local spaces=""
    local i=0
    while [[ $i -lt $indent ]]; do
        spaces+=" "
        i=$((i + 1))
    done
    echo "$spaces$content"
}

json_escape() {
    local string="$1"
    string="${string//\\/\\\\}"
    string="${string//\"/\\\"}"
    string="${string//$'\n'/\\n}"
    string="${string//$'\r'/\\r}"
    string="${string//$'\t'/\\t}"
    printf '%s' "$string"
}

parse_tool_data() {
    local tool_name="$1"
    local yaml_file="$TOOLS_YAML"

    if [[ ! -f "$yaml_file" ]]; then
        error_exit "Tools configuration not found: $yaml_file"
    fi

    TOOL_NAME=""
    TOOL_DISPLAY_NAME=""
    TOOL_DESCRIPTION=""
    TOOL_CATEGORY=""
    TOOL_URL=""
    TOOL_INSTALL_COMMAND=""
    TOOL_INSTALL_VERIFY=""
    TOOL_REQUIRES=""
    TOOL_ENV_VARS=""
    TOOL_COMMANDS=""

    # Use grep to find the line number and then extract section
    local start_line=$(grep -n "^- name: \"$tool_name\"" "$yaml_file" | head -1 | cut -d: -f1)
    [[ -z "$start_line" ]] && start_line=$(grep -n "^- name: $tool_name$" "$yaml_file" | head -1 | cut -d: -f1)
    [[ -z "$start_line" ]] && start_line=$(grep -n "^- name: $tool_name " "$yaml_file" | head -1 | cut -d: -f1)

    if [[ -z "$start_line" ]]; then
        return 1
    fi

    # Find the next tool entry (including those with quotes)
    local next_tool_line=$(tail -n +$((start_line + 1)) "$yaml_file" | grep -n "^- name:" | head -1 | cut -d: -f1)

    if [[ -n "$next_tool_line" ]]; then
        local tool_section=$(tail -n +$start_line "$yaml_file" | head -n $((next_tool_line - 1)))
    else
        local tool_section=$(tail -n +$start_line "$yaml_file")
    fi

    TOOL_NAME="$tool_name"

    # Parse the extracted section
    TOOL_DISPLAY_NAME=$(echo "$tool_section" | grep "display_name:" | head -1 | sed 's/.*display_name:[[:space:]]*//' | tr -d '"')
    TOOL_DESCRIPTION=$(echo "$tool_section" | grep "description:" | head -1 | sed 's/.*description:[[:space:]]*//' | tr -d '"')
    TOOL_CATEGORY=$(echo "$tool_section" | grep "^[[:space:]]*category:" | head -1 | sed 's/.*category:[[:space:]]*//' | tr -d '"')
    TOOL_URL=$(echo "$tool_section" | grep "^[[:space:]]*url:" | head -1 | sed 's/.*url:[[:space:]]*//' | tr -d '"')

    # Parse install block - use awk for more reliable extraction
    local install_section=$(echo "$tool_section" | awk '
        /install:/ {flag=1; next}
        flag && /^[^ ]/ {exit}
        flag {print}
    ')

    if [[ -n "$install_section" ]]; then
        if echo "$install_section" | grep -q "command:[[:space:]]*|"; then
            TOOL_INSTALL_COMMAND=$(echo "$install_section" | awk '
                /command:[[:space:]]*\|/ {flag=1; next}
                flag && /verify:/ {exit}
                flag {print}
            ' | sed 's/^[[:space:]]*//')
        else
            TOOL_INSTALL_COMMAND=$(echo "$install_section" | grep "command:" | head -1 | sed 's/.*command:[[:space:]]*//' | tr -d '"')
        fi
        TOOL_INSTALL_VERIFY=$(echo "$install_section" | grep "verify:" | head -1 | sed 's/.*verify:[[:space:]]*//' | tr -d '"')
        local requires=$(echo "$install_section" | awk '
            /requires:/{flag=1;next}
            flag && /^-/{print;next}
            flag && /verify:/ {exit}
            flag{exit}
        ' | sed 's/.*- //')
        TOOL_REQUIRES=$(echo "$requires" | tr '\n' ' ')
    fi

    # Parse config/env block
    local config_section=$(echo "$tool_section" | awk '
        /^    config:/ {flag=1; next}
        /^- name:/ && flag {exit}
        flag {print}
    ')

    if [[ -n "$config_section" ]]; then
        local env_vars=$(echo "$config_section" | awk '
            /^      env:/ {flag=1; next}
            /^    commands:/ && flag {exit}
            flag && /^        - name:/ {
                gsub(/.*name:[[:space:]]*/, "");
                gsub(/["]/, "");
                print
            }
        ')
        TOOL_ENV_VARS=$(echo "$env_vars" | tr '\n' ' ')
    fi

    # Parse commands block
    local commands_section=$(echo "$tool_section" | awk '
        /commands:/ {flag=1; next}
        flag && /^[^ ]/ {exit}
        flag {print}
    ')

    if [[ -n "$commands_section" ]]; then
        local cmd_names=$(echo "$commands_section" | awk '
            /^      - name:/ {
                gsub(/.*name:[[:space:]]*/, "");
                gsub(/["]/, "");
                print
            }
        ')

        for cmd_name in $cmd_names; do
            local cmd_block=$(echo "$commands_section" | awk -v name="$cmd_name" '
                /^      - name:/ {
                    gsub(/.*name:[[:space:]]*/, "");
                    gsub(/["]/, "");
                    if ($0 == name) {flag=1; next}
                    if (flag) exit
                }
                flag {print}
            ')

            local cmd_desc=$(echo "$cmd_block" | grep "description:" | head -1 | sed 's/.*description:[[:space:]]*//' | tr -d '"')
            local cmd_syntax=$(echo "$cmd_block" | grep "syntax:" | head -1 | sed 's/.*syntax:[[:space:]]*//' | tr -d '"')

            [[ -n "$TOOL_COMMANDS" ]] && TOOL_COMMANDS="$TOOL_COMMANDS|"
            TOOL_COMMANDS="$TOOL_COMMANDS$cmd_name|$cmd_desc|$cmd_syntax"
        done
    fi

    return 0
}

command_exists() {
    command -v "$1" &>/dev/null
}

get_command_version() {
    local cmd="$1"

    if command_exists "$cmd"; then
        if output=$($cmd --version 2>&1); then
            echo "$output" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
        elif output=$($cmd -v 2>&1); then
            echo "$output" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
        else
            echo "installed"
        fi
    else
        echo "not_installed"
    fi
}

check_env_status() {
    local env_name="$1"
    local value=""
    eval "value=\"\${$env_name:-}\""

    if [[ -n "$value" ]]; then
        echo "configured"
    else
        echo "not_configured"
    fi
}

get_install_status() {
    local tool_name="$1"
    local version=""
    local status="not_installed"

    if command_exists "$tool_name"; then
        version=$(get_command_version "$tool_name")
        if [[ "$version" != "not_installed" ]]; then
            status="installed"
        fi
    fi

    INSTALL_STATUS="$status"
    INSTALL_VERSION="${version:-unknown}"
}

get_category_display() {
    local category="$1"
    case "$category" in
        ai) echo "AI 模型" ;;
        local) echo "本地运行" ;;
        workflow) echo "工作流" ;;
        coding) echo "代码助手" ;;
        *) echo "$category" ;;
    esac
}

output_text() {
    local tool_name="$TOOL_NAME"
    local display_name="${TOOL_DISPLAY_NAME:-$tool_name}"
    local description="${TOOL_DESCRIPTION:-无描述}"
    local url="$TOOL_URL"
    local category="$TOOL_CATEGORY"

    get_install_status "$tool_name"
    local install_status="$INSTALL_STATUS"
    local install_version="$INSTALL_VERSION"

    echo ""
    print_header "🔧 $display_name ($tool_name)"
    echo ""
    echo "📝 描述:"
    print_indent "$description"
    echo ""

    if [[ -n "$category" ]]; then
        echo "📦 类别: $(get_category_display "$category")"
        echo ""
    fi

    if [[ -n "$url" ]]; then
        echo "🔗 主页: $url"
        echo ""
    fi

    if [[ "$install_status" == "installed" ]]; then
        echo -e "✅ 安装状态: ${GREEN}已安装${NC} ${install_version:+(v$install_version)}"
    else
        echo -e "❌ 安装状态: ${RED}未安装${NC}"
    fi
    echo ""

    local install_cmd="$TOOL_INSTALL_COMMAND"
    if [[ -n "$install_cmd" ]]; then
        echo "📥 安装命令:"
        print_indent "$install_cmd"
        echo ""
    fi

    local requires="$TOOL_REQUIRES"
    if [[ -n "$requires" ]]; then
        echo "🔧 依赖要求:"
        for req in $requires; do
            print_indent "• $req"
        done
        echo ""
    fi

    local env_vars="$TOOL_ENV_VARS"
    if [[ -n "$env_vars" ]]; then
        echo "🔑 配置需求:"
        for env_var in $env_vars; do
            local env_status=$(check_env_status "$env_var")
            if [[ "$env_status" == "configured" ]]; then
                echo "  • $env_var (必需) - ✅ 已配置"
            else
                echo "  • $env_var (必需) - ⚠️  未配置"
            fi
        done
        echo ""
    fi

    local commands="$TOOL_COMMANDS"
    if [[ -n "$commands" ]]; then
        echo "⚡ 支持的命令:"
        local IFS_BAK="$IFS"
        IFS='|'
        set -- $commands
        IFS="$IFS_BAK"

        while [[ $# -ge 3 ]]; do
            local cmd_name="$1"
            local cmd_desc="$2"
            local cmd_syntax="$3"
            shift 3

            print_indent "• $cmd_name - $cmd_desc"
            if [[ -n "$cmd_syntax" ]]; then
                print_indent "用法: $cmd_syntax" 4
            fi
        done
        echo ""
    fi

    echo "💡 使用示例:"
    if [[ -n "$commands" ]]; then
        local IFS_BAK="$IFS"
        IFS='|'
        set -- $commands
        IFS="$IFS_BAK"

        while [[ $# -ge 3 ]]; do
            local cmd_name="$1"
            local cmd_syntax="$3"
            shift 3

            if [[ -n "$cmd_syntax" ]]; then
                local example=$(echo "$cmd_syntax" | sed 's/{prompt}/"你的问题"/g' | sed 's/{model}/llama2/g' | sed 's/{input}/"输入文本"/g')
                print_indent "# $cmd_name 示例"
                print_indent "$tool_name $example" 4
            fi
        done
    else
        print_indent "# 查看帮助"
        print_indent "$tool_name --help" 4
    fi
    echo ""
}

output_json() {
    local tool_name="$TOOL_NAME"
    local display_name="${TOOL_DISPLAY_NAME:-$tool_name}"
    local description="$TOOL_DESCRIPTION"
    local url="$TOOL_URL"
    local category="$TOOL_CATEGORY"
    local install_cmd="$TOOL_INSTALL_COMMAND"
    local requires="$TOOL_REQUIRES"

    get_install_status "$tool_name"
    local install_status="$INSTALL_STATUS"
    local install_version="$INSTALL_VERSION"

    echo "{"
    echo "  \"name\": \"$tool_name\","
    echo "  \"display_name\": \"$(json_escape "$display_name")\","
    echo "  \"description\": \"$(json_escape "$description")\","

    [[ -n "$category" ]] && echo "  \"category\": \"$category\","
    [[ -n "$url" ]] && echo "  \"url\": \"$url\","

    echo "  \"installation\": {"
    echo "    \"status\": \"$install_status\","
    echo "    \"version\": \"$install_version\""
    echo "  },"

    [[ -n "$install_cmd" ]] && echo "  \"install_command\": \"$(json_escape "$install_cmd")\","

    if [[ -n "$requires" ]]; then
        echo "  \"requires\": ["
        local first=true
        for req in $requires; do
            if [[ "$first" == false ]]; then
                echo ", "
            else
                echo -n "    "
            fi
            printf '"%s"' "$req"
            first=false
        done
        echo ""
        echo "  ],"
    fi

    local env_vars="$TOOL_ENV_VARS"
    if [[ -n "$env_vars" ]]; then
        echo "  \"env\": ["
        local first=true
        for env_var in $env_vars; do
            if [[ "$first" == false ]]; then
                echo ","
            else
                echo -n "    "
            fi
            local env_status=$(check_env_status "$env_var")
            local value=""
            eval "value=\"\${$env_var:-}\""
            local masked_value=""
            if [[ -n "$value" ]]; then
                local len=${#value}
                if [[ $len -gt 8 ]]; then
                    masked_value=$(echo "$value" | cut -c1-4)..."$(echo "$value" | tail -c 5)"
                else
                    masked_value="****"
                fi
            fi
            printf '{"name": "%s", "configured": %s' "$env_var" "$([ "$env_status" = "configured" ] && echo "true" || echo "false")"
            if [[ -n "$masked_value" ]]; then
                printf ', "value": "%s"' "$masked_value"
            fi
            printf '}'
            first=false
        done
        echo ""
        echo "  ],"
    fi

    local commands="$TOOL_COMMANDS"
    if [[ -n "$commands" ]]; then
        echo "  \"commands\": ["
        local first=true
        local IFS_BAK="$IFS"
        IFS='|'
        set -- $commands
        IFS="$IFS_BAK"

        while [[ $# -ge 3 ]]; do
            local cmd_name="$1"
            local cmd_desc="$2"
            local cmd_syntax="$3"
            shift 3

            if [[ "$first" == false ]]; then
                echo ","
            else
                echo -n "    "
            fi
            printf '{"name": "%s", "description": "%s"' "$cmd_name" "$(json_escape "$cmd_desc")"
            if [[ -n "$cmd_syntax" ]]; then
                printf ', "syntax": "%s"' "$(json_escape "$cmd_syntax")"
            fi
            printf '}'
            first=false
        done
        echo ""
        echo "  ]"
    else
        echo "  \"commands\": []"
    fi

    echo "}"
}

output_compact() {
    local tool_name="$TOOL_NAME"
    local display_name="${TOOL_DISPLAY_NAME:-$tool_name}"

    get_install_status "$tool_name"
    local install_status="$INSTALL_STATUS"

    if [[ "$install_status" == "installed" ]]; then
        printf "✅ "
    else
        printf "❌ "
    fi
    printf "%-20s %s\n" "$tool_name" "$display_name"
}

show_help() {
    cat << 'HELPEND'
AI CLI Tools - Tool Info v1.0.0

用法:
    tool-info.sh <tool_name> [options]
    tool-info.sh <tool1> <tool2> ... [options]

参数:
    tool_name           工具名称 (如: claude, openai, ollama)

选项:
    --format FMT        输出格式: text (默认), json, compact
    --verbose           详细输出
    --help, -h          显示此帮助信息

示例:
    # 查看单个工具详情
    tool-info.sh claude

    # 输出 JSON 格式
    tool-info.sh claude --format json

    # 查看多个工具
    tool-info.sh claude openai ollama

    # 紧凑格式查看多个工具
    tool-info.sh claude openai ollama --format compact

可用的工具:
    claude      - Anthropic Claude CLI
    openai      - OpenAI CLI
    ollama      - 本地 LLM 运行器
    fabric      - AI 工作流工具
    aider       - AI 代码助手

HELPEND
}

list_tools() {
    echo "可用的工具:"
    echo ""
    grep "^- name:" "$TOOLS_YAML" 2>/dev/null | while IFS= read -r line; do
        # Extract tool name from "  - name: toolname"
        local tool_name=$(echo "$line" | sed 's/.*name:[[:space:]]*//' | tr -d '"')
        printf "  • %-12s" "$tool_name"
        local display_name=$(grep -A 5 "^- name: $tool_name" "$TOOLS_YAML" 2>/dev/null | grep "display_name:" | head -1 | sed 's/.*display_name:[[:space:]]*//' | tr -d '"')
        if [[ -n "$display_name" ]]; then
            echo "- $display_name"
        else
            echo ""
        fi
    done
    echo ""
}

show_tool_info() {
    local tool_name="$1"

    if ! parse_tool_data "$tool_name"; then
        echo -e "${RED}错误:${NC} 工具 '$tool_name' 未找到" >&2
        echo "" >&2
        echo "可用的工具:" >&2
        list_tools >&2
        return 1
    fi

    case "$OUTPUT_FORMAT" in
        json) output_json ;;
        compact) output_compact ;;
        *) output_text ;;
    esac
}

show_multiple_tools() {
    local tool_list="$@"
    local found=0

    for tool_name in $tool_list; do
        if parse_tool_data "$tool_name"; then
            found=$((found + 1))
            if [[ "$OUTPUT_FORMAT" == "compact" ]]; then
                show_tool_info "$tool_name"
            else
                if [[ $found -gt 1 ]]; then
                    echo ""
                    echo "=========================================="
                    echo ""
                fi
                show_tool_info "$tool_name"
            fi
        else
            echo -e "${RED}错误:${NC} 工具 '$tool_name' 未找到" >&2
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "" >&2
        list_tools >&2
        return 1
    fi
}

parse_args() {
    local tools=""
    local tools_count=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --*)
                error_exit "未知选项: $1"
                ;;
            *)
                [[ -n "$tools" ]] && tools="$tools "
                tools="$tools$1"
                tools_count=$((tools_count + 1))
                shift
                ;;
        esac
    done

    if [[ "$OUTPUT_FORMAT" != "text" ]] && [[ "$OUTPUT_FORMAT" != "json" ]] && [[ "$OUTPUT_FORMAT" != "compact" ]]; then
        error_exit "无效的输出格式: $OUTPUT_FORMAT - 支持 text, json, compact"
    fi

    if [[ $tools_count -eq 0 ]]; then
        show_help
        exit 1
    fi

    if [[ $tools_count -eq 1 ]]; then
        show_tool_info "$tools"
    else
        show_multiple_tools $tools
    fi
}

main() {
    if [[ ! -f "$TOOLS_YAML" ]]; then
        error_exit "工具配置文件未找到: $TOOLS_YAML"
    fi

    parse_args "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
