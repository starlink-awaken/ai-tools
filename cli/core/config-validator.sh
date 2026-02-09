#!/bin/bash
# ==============================================================================
# AI CLI Tools - Configuration Validator
# ==============================================================================
# Version: 1.0.0
# Purpose: Validate tools.yaml and rules.yaml configuration files
#
# Usage:
#   ./config-validator.sh --all                    # Validate all configs
#   ./config-validator.sh tools.yaml              # Validate specific file
#   ./config-validator.sh --all --format json     # JSON output
#   ./config-validator.sh --all --verbose         # Verbose mode
#   ./config-validator.sh --all --fix             # Auto-fix simple issues
# ==============================================================================

# Note: Not using 'set -e' because we need to handle validation failures gracefully

# ==============================================================================
# Constants and Variables
# ==============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly TOOLS_CONFIG="${CONFIG_ROOT}/tools.yaml"
readonly RULES_CONFIG="${CONFIG_ROOT}/config/rules.yaml"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Validation results
declare -a ERRORS=()
declare -a WARNINGS=()
declare -a INFO=()

# Options
VERBOSE=0
FIX_MODE=0
OUTPUT_FORMAT="text"
VALIDATE_ALL=0

# ==============================================================================
# Utility Functions
# ==============================================================================

error_exit() {
    echo -e "${RED}Error:${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1" >&2
}

info() {
    echo -e "${CYAN}Info:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}Success:${NC} $1" >&2
}

add_error() {
    local file="$1"
    local line="${2:-0}"
    local message="$3"
    ERRORS+=("$file|$line|$message")
}

add_warning() {
    local file="$1"
    local line="${2:-0}"
    local message="$3"
    WARNINGS+=("$file|$line|$message")
}

add_info() {
    local message="$1"
    INFO+=("$message")
}

is_valid_url() {
    local url="$1"
    [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+(\.[a-zA-Z]{2,})?(/.*)?$ ]]
}

is_kebab_case() {
    local name="$1"
    [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

is_valid_version() {
    local version="$1"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ==============================================================================
# YAML Syntax Validation
# ==============================================================================

validate_yaml_syntax() {
    local file="$1"
    local filename=$(basename "$file")

    # Use Python to validate YAML syntax
    local python_check=$(python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        yaml.safe_load(f)
    print('OK')
except yaml.YAMLError as e:
    print(f'YAML_ERROR: {e}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)

    if [[ "$python_check" =~ YAML_ERROR ]]; then
        # Extract line number from error if available
        local error_msg=$(echo "$python_check" | sed 's/YAML_ERROR: //')
        local line_num=$(echo "$error_msg" | grep -oE 'line [0-9]+' | grep -oE '[0-9]+' || echo "0")
        add_error "$filename" "$line_num" "YAML语法错误: $error_msg"
        return 1
    elif [[ "$python_check" =~ ERROR ]]; then
        add_error "$filename" "0" "文件读取错误: $python_check"
        return 1
    fi

    return 0
}

# ==============================================================================
# tools.yaml Validation
# ==============================================================================

validate_tools_yaml() {
    local file="$1"
    local filename=$(basename "$file")

    # Parse YAML content using Python
    local yaml_content=$(python3 -c "
import yaml
import json
with open('$file', 'r') as f:
    data = yaml.safe_load(f)
print(json.dumps(data))
")

    # Check version field
    local version=$(echo "$yaml_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('version', ''))
")
    if [[ -z "$version" ]]; then
        add_error "$filename" "1" "缺少必需字段 'version'"
    elif ! is_valid_version "$version"; then
        add_error "$filename" "1" "version 格式无效，应为 'x.y.z' 格式"
    fi

    # Check tools array
    local tools_count=$(echo "$yaml_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tools = data.get('tools', [])
print(len(tools))
")
    if [[ "$tools_count" -eq 0 ]]; then
        add_error "$filename" "14" "tools 数组为空，至少需要一个工具定义"
    fi

    # Validate each tool
    local tool_names=()
    local tool_index=0
    while [[ $tool_index -lt $tools_count ]]; do
        local tool_info=$(echo "$yaml_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tools = data.get('tools', [])
if $tool_index < len(tools):
    print(json.dumps(tools[$tool_index]))
")
        validate_tool_entry "$filename" "$tool_info" "$tool_index"
        local tool_name=$(echo "$tool_info" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
        tool_names+=("$tool_name")
        ((tool_index++))
    done

    # Validate aliases
    validate_aliases "$filename" "$yaml_content" "${tool_names[@]}"

    # Validate groups
    validate_groups "$filename" "$yaml_content" "${tool_names[@]}"

    # Add info
    add_info "发现 $tools_count 个工具定义"
}

validate_tool_entry() {
    local filename="$1"
    local tool_json="$2"
    local index="$3"
    local base_line=$((14 + index * 30))  # Approximate line number

    local name=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
    local display_name=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('display_name',''))")
    local description=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))")
    local category=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('category',''))")
    local url=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url',''))")
    local install=$(echo "$tool_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
install = data.get('install', {})
if isinstance(install, dict):
    print(json.dumps(install))
else:
    print('{}')
")

    # Check required fields
    if [[ -z "$name" ]]; then
        add_error "$filename" "$base_line" "工具 #$index 缺少必需字段 'name'"
    else
        # Validate name format (kebab-case)
        if ! is_kebab_case "$name"; then
            add_warning "$filename" "$base_line" "工具 '$name' 不符合 kebab-case 格式建议"
        fi
    fi

    if [[ -z "$display_name" ]]; then
        add_error "$filename" "$base_line" "工具 '$name' 缺少必需字段 'display_name'"
    fi

    if [[ -z "$description" ]]; then
        add_error "$filename" "$base_line" "工具 '$name' 缺少必需字段 'description'"
    fi

    if [[ -z "$category" ]]; then
        add_error "$filename" "$base_line" "工具 '$name' 缺少必需字段 'category'"
    else
        # Validate category enum
        case "$category" in
            ai|local|workflow|coding|other)
                # Valid category
                ;;
            *)
                add_error "$filename" "$base_line" "工具 '$name' 的 category 值无效: '$category' (应为: ai, local, workflow, coding, other)"
                ;;
        esac
    fi

    # Validate URL format if present
    if [[ -n "$url" ]] && ! is_valid_url "$url"; then
        add_warning "$filename" "$base_line" "工具 '$name' 的 URL 格式可能无效: $url"
    elif [[ -z "$url" ]]; then
        add_warning "$filename" "$base_line" "工具 '$name' 缺少 'url' 字段"
    fi

    # Validate install command
    local install_cmd=$(echo "$install" | python3 -c "import json,sys; print(json.load(sys.stdin).get('command',''))")
    if [[ -z "$install_cmd" ]]; then
        add_error "$filename" "$base_line" "工具 '$name' 缺少 'install.command' 字段"
    fi
}

validate_aliases() {
    local filename="$1"
    local yaml_content="$2"
    shift 2
    local valid_tools=("$@")

    local aliases=$(echo "$yaml_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
aliases = data.get('aliases', {})
if isinstance(aliases, dict):
    print(json.dumps(aliases))
else:
    print('{}')
")

    if [[ "$aliases" == "{}" ]]; then
        return
    fi

    local alias_count=$(echo "$aliases" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    local alias_keys=$(echo "$aliases" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for key in data.keys():
    print(key)
")

    for alias in $alias_keys; do
        local target=$(echo "$aliases" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$alias',''))")
        local found=0
        for valid_tool in "${valid_tools[@]}"; do
            if [[ "$valid_tool" == "$target" ]]; then
                found=1
                break
            fi
        done
        if [[ $found -eq 0 ]]; then
            add_warning "$filename" "208" "别名 '$alias' 引用了不存在的工具: '$target'"
        fi
    done
}

validate_groups() {
    local filename="$1"
    local yaml_content="$2"
    shift 2
    local valid_tools=("$@")

    local groups=$(echo "$yaml_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
groups = data.get('groups', [])
if isinstance(groups, list):
    print(json.dumps(groups))
else:
    print('[]')
")

    if [[ "$groups" == "[]" ]]; then
        return
    fi

    local group_count=$(echo "$groups" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    add_info "发现 $group_count 个工具组"

    local group_index=0
    while [[ $group_index -lt $group_count ]]; do
        local group_tools=$(echo "$groups" | python3 -c "
import json, sys
data = json.load(sys.stdin)
groups = $groups
if $group_index < len(groups):
    group = groups[$group_index]
    tools = group.get('tools', [])
    print(' '.join(tools) if tools else '')
")
        for tool in $group_tools; do
            local found=0
            for valid_tool in "${valid_tools[@]}"; do
                if [[ "$valid_tool" == "$tool" ]]; then
                    found=1
                    break
                fi
            done
            if [[ $found -eq 0 ]]; then
                add_warning "$filename" "$((183 + group_index * 10))" "组 #$group_index 引用了不存在的工具: '$tool'"
            fi
        done
        ((group_index++))
    done
}

# ==============================================================================
# rules.yaml Validation
# ==============================================================================

validate_rules_yaml() {
    local file="$1"
    local filename=$(basename "$file")

    # Parse YAML content using Python
    local yaml_content=$(python3 -c "
import yaml
import json
with open('$file', 'r') as f:
    data = yaml.safe_load(f)
print(json.dumps(data))
" 2>&1)

    if [[ "$yaml_content" =~ ERROR ]]; then
        add_error "$filename" "0" "解析错误: $yaml_content"
        return 1
    fi

    # Check version field
    local version=$(echo "$yaml_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('version', ''))
")
    if [[ -z "$version" ]]; then
        add_error "$filename" "8" "缺少必需字段 'version'"
    fi

    # Get all tool names from tools.yaml for reference validation
    local tool_names=$(get_tool_names_from_config)

    # Check rules array
    local rules_count=$(echo "$yaml_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
rules = data.get('rules', [])
print(len(rules))
")
    if [[ "$rules_count" -eq 0 ]]; then
        add_error "$filename" "56" "rules 数组为空，至少需要一个规则定义"
    fi

    # Use global variable to track rule IDs (bash 3.2 compatible)
    RULE_IDS_FILE=$(mktemp)
    > "$RULE_IDS_FILE"

    # Validate each rule
    local rule_index=0
    while [[ $rule_index -lt $rules_count ]]; do
        local rule_info=$(echo "$yaml_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
rules = data.get('rules', [])
if $rule_index < len(rules):
    print(json.dumps(rules[$rule_index]))
")
        validate_rule_entry "$filename" "$rule_info" "$rule_index" "$tool_names"
        ((rule_index++))
    done

    # Check for duplicate rule IDs
    local unique_count=$(wc -l < "$RULE_IDS_FILE" | tr -d ' ')
    rm -f "$RULE_IDS_FILE"
    if [[ $unique_count -lt $rules_count ]]; then
        add_error "$filename" "56" "存在重复的规则 ID"
    fi

    # Check default_fallback in global config
    local default_fallback=$(echo "$yaml_content" | python3 -c "
import json, sys
data = json.load(sys.stdin)
global_config = data.get('global', {})
print(global_config.get('default_fallback', ''))
")
    if [[ -n "$default_fallback" ]]; then
        if ! echo "$tool_names" | grep -q "\"$default_fallback\""; then
            add_warning "$filename" "15" "default_fallback 引用的工具不存在: '$default_fallback'"
        fi
    fi

    # Add info
    add_info "发现 $rules_count 个路由规则"
}

get_tool_names_from_config() {
    if [[ ! -f "$TOOLS_CONFIG" ]]; then
        echo "[]"
        return
    fi

    python3 -c "
import yaml
import json
with open('$TOOLS_CONFIG', 'r') as f:
    data = yaml.safe_load(f)
tools = data.get('tools', [])
names = [t.get('name', '') for t in tools if t.get('name')]
print(json.dumps(names))
" 2>/dev/null || echo "[]"
}

validate_rule_entry() {
    local filename="$1"
    local rule_json="$2"
    local index="$3"
    local tool_names_json="$4"
    local base_line=$((60 + index * 40))  # Approximate line number

    local id=$(echo "$rule_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
    local name=$(echo "$rule_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
    local priority=$(echo "$rule_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('priority',0))")
    local enabled=$(echo "$rule_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('enabled',True))")
    local match=$(echo "$rule_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
match = data.get('match', {})
if isinstance(match, dict):
    print(json.dumps(match))
else:
    print('{}')
")
    local recommend=$(echo "$rule_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
recommend = data.get('recommend', {})
if isinstance(recommend, dict):
    print(json.dumps(recommend))
else:
    print('{}')
")

    # Check required fields
    if [[ -z "$id" ]]; then
        add_error "$filename" "$base_line" "规则 #$index 缺少必需字段 'id'"
    else
        # Check for duplicate IDs using temp file (bash 3.2 compatible)
        if grep -q "^$id$" "$RULE_IDS_FILE" 2>/dev/null; then
            add_error "$filename" "$base_line" "规则 ID '$id' 重复"
        else
            echo "$id" >> "$RULE_IDS_FILE"
        fi
    fi

    if [[ -z "$name" ]]; then
        add_error "$filename" "$base_line" "规则 '$id' 缺少必需字段 'name'"
    fi

    # Validate priority range
    if [[ "$priority" -lt 0 ]] || [[ "$priority" -gt 1000 ]]; then
        add_warning "$filename" "$base_line" "规则 '$id' 的优先级 $priority 超出建议范围 (0-1000)"
    fi

    # Check if disabled
    if [[ "$enabled" != "True" ]] && [[ "$enabled" != "true" ]]; then
        add_warning "$filename" "$base_line" "规则 '$id' 未启用"
    fi

    # Validate match.type
    local match_type=$(echo "$match" | python3 -c "import json,sys; print(json.load(sys.stdin).get('type',''))")
    if [[ -n "$match_type" ]]; then
        case "$match_type" in
            keyword|capability|category|keyword_or_capability|keyword_exact|any)
                # Valid match type
                ;;
            *)
                add_error "$filename" "$base_line" "规则 '$id' 的 match.type 值无效: '$match_type'"
                ;;
        esac
    else
        add_error "$filename" "$base_line" "规则 '$id' 缺少 match.type 字段"
    fi

    # Validate recommend.tools references
    local recommend_tools=$(echo "$recommend" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tools = data.get('tools', [])
if isinstance(tools, list):
    print(' '.join(tools))
else:
    print('')
")
    if [[ -n "$recommend_tools" ]]; then
        for tool in $recommend_tools; do
            # Skip special values like "auto_detect"
            if [[ "$tool" == "auto_detect" ]]; then
                continue
            fi
            if ! echo "$tool_names_json" | grep -q "\"$tool\""; then
                add_warning "$filename" "$base_line" "规则 '$id' 引用了不存在的工具: '$tool'"
            fi
        done
    fi

    # Validate recommend.fallback reference
    local fallback=$(echo "$recommend" | python3 -c "import json,sys; print(json.load(sys.stdin).get('fallback',''))")
    if [[ -n "$fallback" ]] && [[ "$fallback" != "null" ]]; then
        if ! echo "$tool_names_json" | grep -q "\"$fallback\""; then
            add_warning "$filename" "$base_line" "规则 '$id' 的 fallback 引用了不存在的工具: '$fallback'"
        fi
    fi
}

# ==============================================================================
# Auto-Fix Functions
# ==============================================================================

fix_yaml_file() {
    local file="$1"
    local filename=$(basename "$file")

    if [[ $FIX_MODE -eq 0 ]]; then
        return
    fi

    info "尝试自动修复 $filename..."

    # Create backup
    local backup="${file}.backup.$(date +%s)"
    cp "$file" "$backup"
    info "已创建备份: $backup"

    # Fix common issues
    local fixed_content=$(cat "$file")

    # Fix: Add missing version field
    if ! grep -q "^version:" "$file"; then
        fixed_content=$(echo "$fixed_content" | sed '1i\
# 版本信息\
version: "1.0.0"'
        )
        add_info "已添加 version 字段"
    fi

    # Fix: Remove trailing whitespace
    fixed_content=$(echo "$fixed_content" | sed 's/[[:space:]]*$//')

    # Fix: Ensure proper line endings
    fixed_content=$(echo "$fixed_content" | tr -d '\r')

    # Fix: Remove duplicate consecutive blank lines
    fixed_content=$(echo "$fixed_content" | awk '/^$/ {if (blank++) next;} !/^$/ {blank=0; print}')

    # Write fixed content
    echo "$fixed_content" > "$file"
    success "已应用自动修复"
}

# ==============================================================================
# Report Generation
# ==============================================================================

generate_text_report() {
    local exit_code=0

    echo ""
    echo "================================================================================================"
    if [[ ${#ERRORS[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ 配置验证通过${NC}"
    else
        echo -e "${RED}❌ 配置验证失败${NC}"
        exit_code=1
    fi
    echo "================================================================================================"
    echo ""

    # Show checked files
    echo "检查的文件:"
    local tools_errors=0
    local tools_warnings=0
    local rules_errors=0
    local rules_warnings=0

    for error in "${ERRORS[@]}"; do
        local file=$(echo "$error" | cut -d'|' -f1)
        if [[ "$file" == "tools.yaml" ]]; then
            ((tools_errors++))
        elif [[ "$file" == "rules.yaml" ]]; then
            ((rules_errors++))
        fi
    done

    for warning in "${WARNINGS[@]}"; do
        local file=$(echo "$warning" | cut -d'|' -f1)
        if [[ "$file" == "tools.yaml" ]]; then
            ((tools_warnings++))
        elif [[ "$file" == "rules.yaml" ]]; then
            ((rules_warnings++))
        fi
    done

    if [[ -f "$TOOLS_CONFIG" ]]; then
        local tools_status="✅"
        if [[ $tools_errors -gt 0 ]]; then
            tools_status="❌"
        elif [[ $tools_warnings -gt 0 ]]; then
            tools_status="⚠️ "
        fi
        echo "  $tools_status tools.yaml ($tools_warnings warnings)"
    fi

    if [[ -f "$RULES_CONFIG" ]]; then
        local rules_status="✅"
        if [[ $rules_errors -gt 0 ]]; then
            rules_status="❌"
        elif [[ $rules_warnings -gt 0 ]]; then
            rules_status="⚠️ "
        fi
        echo "  $rules_status rules.yaml ($rules_warnings warnings)"
    fi

    echo ""
    echo "汇总:"
    echo "  错误: ${#ERRORS[@]}"
    echo "  警告: ${#WARNINGS[@]}"
    echo "  信息: ${#INFO[@]}"

    # Show errors
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo ""
        echo "发现的错误:"
        for error in "${ERRORS[@]}"; do
            local file=$(echo "$error" | cut -d'|' -f1)
            local line=$(echo "$error" | cut -d'|' -f2)
            local message=$(echo "$error" | cut -d'|' -f3-)
            echo -e "  ${RED}✗${NC} $file:$line - $message"
        done
    fi

    # Show warnings
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo ""
        echo "警告:"
        for warning in "${WARNINGS[@]}"; do
            local file=$(echo "$warning" | cut -d'|' -f1)
            local line=$(echo "$warning" | cut -d'|' -f2)
            local message=$(echo "$warning" | cut -d'|' -f3-)
            echo -e "  ${YELLOW}⚠️ ${NC} $file:$line - $message"
        done
    fi

    # Show info
    if [[ ${#INFO[@]} -gt 0 ]] && [[ $VERBOSE -eq 1 ]]; then
        echo ""
        echo "信息:"
        for info_msg in "${INFO[@]}"; do
            echo -e "  ${CYAN}ℹ️ ${NC} $info_msg"
        done
    fi

    # Severity assessment
    echo ""
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo -e "${RED}严重程度: CRITICAL${NC}"
        echo "建议: 立即修复所有错误后才能继续使用"
    elif [[ ${#WARNINGS[@]} -gt 10 ]]; then
        echo -e "${YELLOW}严重程度: HIGH${NC}"
        echo "建议: 尽快修复警告以确保配置正确"
    elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}严重程度: MEDIUM${NC}"
        echo "建议: 检查警告并根据需要修复"
    else
        echo -e "${GREEN}严重程度: LOW${NC}"
        echo "配置良好，可以正常使用"
    fi

    echo ""
    echo "================================================================================================"

    return $exit_code
}

generate_json_report() {
    local status="success"
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        status="error"
    elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
        status="warning"
    fi

    echo "{"
    echo "  \"status\": \"$status\","
    echo "  \"version\": \"$SCRIPT_VERSION\","
    echo "  \"validated_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"errors\": ["

    local first=1
    for error in "${ERRORS[@]}"; do
        if [[ $first -eq 0 ]]; then
            echo ","
        fi
        local file=$(echo "$error" | cut -d'|' -f1)
        local line=$(echo "$error" | cut -d'|' -f2)
        local message=$(echo "$error" | cut -d'|' -f3-)
        message=$(echo "$message" | sed 's/"/\\"/g')
        echo "    {"
        echo "      \"file\": \"$file\","
        echo "      \"line\": $line,"
        echo "      \"message\": \"$message\","
        echo "      \"severity\": \"error\""
        echo -n "    }"
        first=0
    done

    echo ""
    echo "  ],"
    echo "  \"warnings\": ["

    first=1
    for warning in "${WARNINGS[@]}"; do
        if [[ $first -eq 0 ]]; then
            echo ","
        fi
        local file=$(echo "$warning" | cut -d'|' -f1)
        local line=$(echo "$warning" | cut -d'|' -f2)
        local message=$(echo "$warning" | cut -d'|' -f3-)
        message=$(echo "$message" | sed 's/"/\\"/g')
        echo "    {"
        echo "      \"file\": \"$file\","
        echo "      \"line\": $line,"
        echo "      \"message\": \"$message\","
        echo "      \"severity\": \"warning\""
        echo -n "    }"
        first=0
    done

    echo ""
    echo "  ],"
    echo "  \"info\": ["

    first=1
    for info_msg in "${INFO[@]}"; do
        if [[ $first -eq 0 ]]; then
            echo ","
        fi
        local message=$(echo "$info_msg" | sed 's/"/\\"/g')
        echo "    {"
        echo "      \"message\": \"$message\","
        echo "      \"severity\": \"info\""
        echo -n "    }"
        first=0
    done

    echo ""
    echo "  ],"
    echo "  \"summary\": {"
    echo "    \"errors\": ${#ERRORS[@]},"
    echo "    \"warnings\": ${#WARNINGS[@]},"
    echo "    \"info\": ${#INFO[@]}"
    echo "  }"
    echo "}"
}

# ==============================================================================
# Main Validation Logic
# ==============================================================================

validate_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        add_error "$(basename "$file")" "0" "文件不存在"
        return 1
    fi

    if [[ ! -r "$file" ]]; then
        add_error "$(basename "$file")" "0" "文件不可读"
        return 1
    fi

    # Apply auto-fix if enabled
    if [[ $FIX_MODE -eq 1 ]]; then
        fix_yaml_file "$file"
    fi

    # Validate YAML syntax first
    if ! validate_yaml_syntax "$file"; then
        return 1
    fi

    # Validate structure based on file type or content
    local filename=$(basename "$file")
    local file_type=""

    # Detect file type by name or content
    case "$filename" in
        tools.yaml|*tools*.yaml)
            file_type="tools"
            ;;
        rules.yaml|*rules*.yaml)
            file_type="rules"
            ;;
        *)
            # Try to detect by content
            if grep -q "^tools:" "$file" 2>/dev/null; then
                file_type="tools"
            elif grep -q "^rules:" "$file" 2>/dev/null; then
                file_type="rules"
            fi
            ;;
    esac

    case "$file_type" in
        tools)
            validate_tools_yaml "$file"
            ;;
        rules)
            validate_rules_yaml "$file"
            ;;
        *)
            add_warning "$filename" "0" "未知的配置文件类型，仅进行语法验证"
            ;;
    esac
}

validate_all() {
    if [[ -f "$TOOLS_CONFIG" ]]; then
        validate_file "$TOOLS_CONFIG"
    else
        add_warning "tools.yaml" "0" "未找到 tools.yaml 配置文件"
    fi

    if [[ -f "$RULES_CONFIG" ]]; then
        validate_file "$RULES_CONFIG"
    else
        add_warning "rules.yaml" "0" "未找到 rules.yaml 配置文件"
    fi
}

# ==============================================================================
# Usage and Help
# ==============================================================================

show_usage() {
    cat << EOF
AI CLI Tools 配置验证工具 v${SCRIPT_VERSION}

用法:
    $0 [options] [file]

参数:
    file              要验证的配置文件路径 (tools.yaml 或 rules.yaml)

选项:
    --all             验证所有配置文件
    --format json     以 JSON 格式输出结果
    --format text     以文本格式输出结果 (默认)
    --verbose         显示详细信息
    --fix             自动修复简单问题 (会创建备份)
    --help, -h        显示此帮助信息

示例:
    # 验证所有配置
    $0 --all

    # 验证特定文件
    $0 tools.yaml
    $0 ~/.config/ai-tools/config/rules.yaml

    # 输出 JSON 格式
    $0 --all --format json

    # 详细模式
    $0 --all --verbose

    # 自动修复小问题
    $0 --all --fix

退出码:
    0    验证通过（无错误）
    1    验证失败（发现错误）

EOF
}

# ==============================================================================
# Main Entry Point
# ==============================================================================

main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi

    local target_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                VALIDATE_ALL=1
                shift
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=1
                shift
                ;;
            --fix)
                FIX_MODE=1
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                error_exit "未知选项: $1"
                ;;
            *)
                target_file="$1"
                shift
                ;;
        esac
    done

    # Expand ~ in path
    target_file="${target_file/#\~/$HOME}"

    # Perform validation
    if [[ $VALIDATE_ALL -eq 1 ]]; then
        validate_all
    elif [[ -n "$target_file" ]]; then
        validate_file "$target_file"
    else
        show_usage
        exit 1
    fi

    # Generate report
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        generate_json_report
    else
        generate_text_report
    fi

    # Exit with appropriate code
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
