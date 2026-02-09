#!/bin/bash
# ==============================================================================
# AI CLI Tools - Interactive Configuration Wizard
# ==============================================================================
# Version: 1.0.0
# Purpose: Interactive wizard for adding, removing, and editing tools in tools.yaml
#
# Usage:
#   ./config-wizard.sh add                      # Interactive add tool
#   ./config-wizard.sh remove                   # Interactive remove tool
#   ./config-wizard.sh edit <tool-name>         # Interactive edit tool
#   ./config-wizard.sh add --name "tool" ...    # Non-interactive add
#   ./config-wizard.sh list                     # List all tools
#   ./config-wizard.sh --help                   # Show help
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Constants and Variables
# ==============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_ROOT="${SCRIPT_DIR}/.."
readonly TOOLS_CONFIG="${CONFIG_ROOT}/tools.yaml"
readonly BACKUP_DIR="${CONFIG_ROOT}/backups"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Valid categories
readonly VALID_CATEGORIES="ai local workflow coding other"

# Tool data storage (using files for bash 3.2 compatibility)
TOOL_DATA_DIR=$(mktemp -d)
TOOL_DATA_FILE="$TOOL_DATA_DIR/tool_data"
TOOL_COMMANDS_FILE="$TOOL_DATA_DIR/commands"

# Initialize storage files
: > "$TOOL_DATA_FILE"
: > "$TOOL_COMMANDS_FILE"

# Options
NON_INTERACTIVE=0
VERBOSE=0
DRY_RUN=0

# ==============================================================================
# Cleanup
# ==============================================================================

cleanup() {
    rm -rf "$TOOL_DATA_DIR"
}

trap cleanup EXIT

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

print_header() {
    local title="$1"
    echo ""
    echo -e "${MAGENTA}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    printf "${MAGENTA}${BOLD}║${NC} ${BOLD}%-56s${NC}\n" "$title"
    echo -e "${MAGENTA}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step="$1"
    local total="$2"
    local title="$3"
    echo -e "${BLUE}步骤 $step/$total: ${BOLD}$title${NC}"
}

print_prompt() {
    local default="${2:-}"
    local hint="${3:-}"

    if [[ -n "$hint" ]]; then
        echo -e "  ${CYAN}提示: $hint${NC}"
    fi

    if [[ -n "$default" ]]; then
        echo -e "  ${YELLOW}当前值 [$default]:${NC} "
    else
        echo -e "  ${YELLOW}当前值 []:${NC} "
    fi
}

# ==============================================================================
# Tool Data Storage Functions (bash 3.2 compatible)
# ==============================================================================

set_tool_data() {
    local key="$1"
    local value="$2"
    echo "$key|$value" >> "$TOOL_DATA_FILE"
}

get_tool_data() {
    local key="$1"
    grep "^$key|" "$TOOL_DATA_FILE" 2>/dev/null | cut -d'|' -f2- | tail -1
}

clear_tool_data() {
    : > "$TOOL_DATA_FILE"
    : > "$TOOL_COMMANDS_FILE"
}

add_command() {
    local cmd="$1"
    echo "$cmd" >> "$TOOL_COMMANDS_FILE"
}

get_commands() {
    cat "$TOOL_COMMANDS_FILE" 2>/dev/null || true
}

count_commands() {
    wc -l < "$TOOL_COMMANDS_FILE" 2>/dev/null || echo "0"
}

# ==============================================================================
# Input Validation Functions
# ==============================================================================

is_kebab_case() {
    local name="$1"
    [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

is_valid_category() {
    local category="$1"
    for valid in $VALID_CATEGORIES; do
        [[ "$category" == "$valid" ]] && return 0
    done
    return 1
}

validate_tool_name() {
    local name="$1"
    local errors=""

    if [[ -z "$name" ]]; then
        errors="工具名称不能为空"
    elif ! is_kebab_case "$name"; then
        errors="工具名称必须使用 kebab-case 格式（小写字母、数字和连字符）"
    fi

    if [[ -n "$errors" ]]; then
        echo -e "  ${RED}✗${NC} $errors"
        return 1
    fi

    # Check for duplicate
    if [[ -f "$TOOLS_CONFIG" ]]; then
        local existing
        existing=$(get_tool_names)
        if echo "$existing" | grep -q "^$name$"; then
            echo -e "  ${RED}✗${NC} 工具 '$name' 已存在"
            return 1
        fi
    fi

    echo -e "  ${GREEN}✓${NC} 工具名称有效"
    return 0
}

validate_install_command() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        echo -e "  ${RED}✗${NC} 安装命令不能为空"
        return 1
    fi
    echo -e "  ${GREEN}✓${NC} 安装命令有效"
    return 0
}

# ==============================================================================
# YAML Operations Functions
# ==============================================================================

get_tool_names() {
    if [[ ! -f "$TOOLS_CONFIG" ]]; then
        return
    fi

    python3 -c "
import yaml
import sys
try:
    with open('$TOOLS_CONFIG', 'r') as f:
        data = yaml.safe_load(f)
    tools = data.get('tools', [])
    for tool in tools:
        print(tool.get('name', ''))
except Exception as e:
    sys.exit(0)
" 2>/dev/null || true
}

get_tool_by_name() {
    local tool_name="$1"

    python3 -c "
import yaml
import json
import sys
try:
    with open('$TOOLS_CONFIG', 'r') as f:
        data = yaml.safe_load(f)
    tools = data.get('tools', [])
    for tool in tools:
        if tool.get('name') == '$tool_name':
            print(json.dumps(tool))
            sys.exit(0)
    sys.exit(1)
except Exception as e:
    print(json.dumps({'error': str(e)}), file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

backup_config() {
    local backup_file="${BACKUP_DIR}/tools.yaml.$(date +%Y%m%d_%H%M%S).bak"

    mkdir -p "$BACKUP_DIR"
    cp "$TOOLS_CONFIG" "$backup_file"

    echo "$backup_file"
}

restore_backup() {
    local backup_file="$1"
    cp "$backup_file" "$TOOLS_CONFIG"
}

yaml_escape() {
    local string="$1"
    # Escape special characters for YAML
    string="${string//\\/\\\\}"
    string="${string//\"/\\\"}"
    string="${string//$'\n'/\\n}"
    printf '%s' "$string"
}

# ==============================================================================
# Interactive Input Functions
# ==============================================================================

prompt_with_default() {
    local prompt="$1"
    local default="${2:-}"
    local validator="${3:-}"
    local max_attempts="${4:-3}"
    local input=""

    for attempt in $(seq 1 $max_attempts); do
        if [[ $NON_INTERACTIVE -eq 1 ]]; then
            input="$default"
        else
            IFS= read -e -r -p "$prompt" input
        fi

        # Use default if empty
        if [[ -z "$input" ]] && [[ -n "$default" ]]; then
            input="$default"
        fi

        # Validate if validator provided
        if [[ -n "$validator" ]] && [[ -n "$input" ]]; then
            if $validator "$input"; then
                echo "$input"
                return 0
            fi
        else
            echo "$input"
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            echo -e "  ${YELLOW}请重试...${NC}"
        fi
    done

    return 1
}

confirm() {
    local prompt="$1"
    local default="${2:-Y}"

    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        [[ "$default" =~ ^[Yy] ]] && return 0 || return 1
    fi

    local prompt_text
    if [[ "$default" =~ ^[Yy] ]]; then
        prompt_text="$prompt [Y/n]: "
    else
        prompt_text="$prompt [y/N]: "
    fi

    local response
    IFS= read -e -r -p "$prompt_text" response
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy] ]]
}

select_option() {
    local prompt="$1"
    shift
    local options=("$@")

    if [[ $NON_INTERACTIVE -eq 1 ]]; then
        echo "${options[0]}"
        return 0
    fi

    echo "  选项:"
    local i=1
    for opt in "${options[@]}"; do
        echo "    $i) $opt"
        ((i++))
    done

    local choice
    while true; do
        IFS= read -e -r -p "  选择 [1-${#options[@]}]: " choice

        if [[ -z "$choice" ]]; then
            echo "${options[0]}"
            return 0
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#options[@]} ]]; then
            echo "${options[$((choice-1))]}"
            return 0
        fi

        echo -e "  ${RED}无效选择，请输入 1-${#options[@]}${NC}"
    done
}

# ==============================================================================
# Add Tool Wizard
# ==============================================================================

wizard_add_tool() {
    print_header "交互式配置向导 - 添加新工具"

    # Clear previous data
    clear_tool_data

    # Check if config exists
    if [[ ! -f "$TOOLS_CONFIG" ]]; then
        error_exit "配置文件不存在: $TOOLS_CONFIG"
    fi

    # Step 1: Tool name
    print_step "1" "8" "工具名称"
    echo -e "  ${CYAN}工具的唯一标识符，使用 kebab-case 格式（如: claude-cli, my-tool）${NC}"
    local tool_name
    while true; do
        print_prompt "输入工具名称" "" "只能包含小写字母、数字和连字符"
        IFS= read -e -r tool_name
        if validate_tool_name "$tool_name" 2>&1 | grep -q "工具名称有效"; then
            set_tool_data "name" "$tool_name"
            break
        fi
    done

    # Step 2: Display name
    print_step "2" "8" "显示名称"
    local display_name
    display_name=$(get_tool_data "display_name")
    [[ -z "$display_name" ]] && display_name="$tool_name"
    print_prompt "输入显示名称" "$display_name" "工具的友好名称"
    display_name=$(prompt_with_default "  " "$display_name")
    set_tool_data "display_name" "$display_name"

    # Step 3: Description
    print_step "3" "8" "描述"
    print_prompt "输入描述" "" "简短描述工具的功能"
    local description
    description=$(prompt_with_default "  " "")
    set_tool_data "description" "$description"

    # Step 4: Category
    print_step "4" "8" "类别"
    local category
    category=$(select_option "选择工具类别" $VALID_CATEGORIES)
    set_tool_data "category" "$category"

    # Step 5: URL
    print_step "5" "8" "项目 URL"
    print_prompt "输入项目 URL" "" "工具的 GitHub 或官网链接（可选）"
    local url
    url=$(prompt_with_default "  " "")
    set_tool_data "url" "$url"

    # Step 6: Install command
    print_step "6" "8" "安装命令"
    print_prompt "输入安装命令" "" "如: npm install -g tool-name 或 brew install tool-name"
    local install_cmd
    while true; do
        install_cmd=$(prompt_with_default "  " "")
        if validate_install_command "$install_cmd" 2>&1 | grep -q "安装命令有效"; then
            set_tool_data "install_command" "$install_cmd"
            break
        fi
    done

    # Step 7: Verify command
    print_step "7" "8" "验证命令"
    print_prompt "输入验证命令" "" "如: tool-name --version（可选）"
    local verify_cmd
    verify_cmd=$(prompt_with_default "  " "")
    set_tool_data "verify_command" "$verify_cmd"

    # Step 8: Commands
    print_step "8" "8" "添加命令模板"

    if confirm "是否添加命令模板？" "Y"; then
        add_commands_wizard
    fi

    # Confirmation
    print_header "确认信息"
    echo "  工具名称: $(get_tool_data name)"
    echo "  显示名称: $(get_tool_data display_name)"
    echo "  描述: $(get_tool_data description)"
    echo "  类别: $(get_tool_data category)"
    local tool_url=$(get_tool_data url)
    [[ -n "$tool_url" ]] && echo "  URL: $tool_url"
    echo "  安装: $(get_tool_data install_command)"
    local verify_cmd=$(get_tool_data verify_command)
    [[ -n "$verify_cmd" ]] && echo "  验证: $verify_cmd"

    local cmd_count=$(count_commands)
    if [[ $cmd_count -gt 0 ]]; then
        echo "  命令:"
        while IFS= read -r cmd; do
            local cmd_name=$(echo "$cmd" | cut -d'|' -f1)
            local cmd_desc=$(echo "$cmd" | cut -d'|' -f2)
            echo "    - $cmd_name: $cmd_desc"
        done < "$TOOL_COMMANDS_FILE"
    fi
    echo ""

    if confirm "是否保存？" "Y"; then
        add_tool_to_yaml
        success "工具已添加到 tools.yaml"
        info "运行 'ai-tools validate' 验证配置"
    else
        info "操作已取消"
    fi
}

add_commands_wizard() {
    local cmd_num=1

    while true; do
        echo ""
        echo -e "${CYAN}添加命令 $cmd_num${NC}"

        # Command name
        local cmd_name
        print_prompt "命令名称" "ask" "如: ask, chat, run"
        cmd_name=$(prompt_with_default "  " "ask")

        # Command description
        local cmd_desc
        print_prompt "命令描述" "" "简要说明命令功能"
        cmd_desc=$(prompt_with_default "  " "")

        # Command syntax
        local cmd_syntax
        print_prompt "命令语法" "\${tool_name} ask '{prompt}'" "实际执行的命令"
        cmd_syntax=$(prompt_with_default "  " "\${tool_name} $cmd_name '{prompt}'")

        add_command "$cmd_name|$cmd_desc|$cmd_syntax"

        if ! confirm "是否添加更多命令？" "N"; then
            break
        fi

        ((cmd_num++))
    done
}

# ==============================================================================
# Edit Tool Wizard
# ==============================================================================

wizard_edit_tool() {
    local tool_name="$1"

    print_header "交互式配置向导 - 编辑工具"

    # Clear previous data
    clear_tool_data

    # Get existing tool data
    local tool_json
    tool_json=$(get_tool_by_name "$tool_name")

    if [[ -z "$tool_json" ]]; then
        error_exit "工具 '$tool_name' 不存在"
    fi

    # Parse existing data
    set_tool_data "name" "$tool_name"
    set_tool_data "display_name" "$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('display_name',''))" 2>/dev/null || echo "$tool_name")"
    set_tool_data "description" "$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" 2>/dev/null || echo "")"
    set_tool_data "category" "$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('category',''))" 2>/dev/null || echo "")"
    set_tool_data "url" "$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || echo "")"

    # Get install info
    local install_info
    install_info=$(echo "$tool_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
install = data.get('install', {})
print(install.get('command', ''))
print(install.get('verify', ''))" 2>/dev/null)
    set_tool_data "install_command" "$(echo "$install_info" | sed -n '1p')"
    set_tool_data "verify_command" "$(echo "$install_info" | sed -n '2p')"

    echo -e "${CYAN}编辑工具: $tool_name${NC}"
    echo "  留空保持原值，输入 'clear' 清除该字段"
    echo ""

    # Display name
    print_step "1" "7" "显示名称"
    local current_display=$(get_tool_data display_name)
    print_prompt "输入显示名称" "$current_display"
    local input
    input=$(prompt_with_default "  " "$current_display")
    [[ "$input" != "clear" ]] && set_tool_data "display_name" "$input"
    [[ "$input" == "clear" ]] && set_tool_data "display_name" ""

    # Description
    print_step "2" "7" "描述"
    local current_desc=$(get_tool_data description)
    print_prompt "输入描述" "$current_desc"
    input=$(prompt_with_default "  " "$current_desc")
    [[ "$input" != "clear" ]] && set_tool_data "description" "$input"
    [[ "$input" == "clear" ]] && set_tool_data "description" ""

    # Category
    print_step "3" "7" "类别"
    local current_cat=$(get_tool_data category)
    echo "  当前值: $current_cat"
    if confirm "是否修改类别？" "N"; then
        local category
        category=$(select_option "选择新类别" $VALID_CATEGORIES)
        set_tool_data "category" "$category"
    fi

    # URL
    print_step "4" "7" "项目 URL"
    local current_url=$(get_tool_data url)
    print_prompt "输入 URL" "$current_url"
    input=$(prompt_with_default "  " "$current_url")
    [[ "$input" != "clear" ]] && set_tool_data "url" "$input"
    [[ "$input" == "clear" ]] && set_tool_data "url" ""

    # Install command
    print_step "5" "7" "安装命令"
    local current_install=$(get_tool_data install_command)
    print_prompt "输入安装命令" "$current_install"
    input=$(prompt_with_default "  " "$current_install")
    [[ "$input" != "clear" ]] && set_tool_data "install_command" "$input"
    [[ "$input" == "clear" ]] && set_tool_data "install_command" ""

    # Verify command
    print_step "6" "7" "验证命令"
    local current_verify=$(get_tool_data verify_command)
    print_prompt "输入验证命令" "$current_verify"
    input=$(prompt_with_default "  " "$current_verify")
    [[ "$input" != "clear" ]] && set_tool_data "verify_command" "$input"
    [[ "$input" == "clear" ]] && set_tool_data "verify_command" ""

    # Commands
    print_step "7" "7" "命令模板"
    echo "  现有命令将保留，可以添加新命令"
    if confirm "是否添加新命令？" "N"; then
        add_commands_wizard
    fi

    # Confirmation
    print_header "确认修改"
    echo "  工具名称: $(get_tool_data name)"
    echo "  显示名称: $(get_tool_data display_name)"
    echo "  描述: $(get_tool_data description)"
    echo "  类别: $(get_tool_data category)"
    local tool_url=$(get_tool_data url)
    [[ -n "$tool_url" ]] && echo "  URL: $tool_url"
    echo "  安装: $(get_tool_data install_command)"
    local verify_cmd=$(get_tool_data verify_command)
    [[ -n "$verify_cmd" ]] && echo "  验证: $verify_cmd"
    echo ""

    if confirm "是否保存修改？" "Y"; then
        edit_tool_in_yaml
        success "工具已更新"
        info "运行 'ai-tools validate' 验证配置"
    else
        info "操作已取消"
    fi
}

# ==============================================================================
# Remove Tool Wizard
# ==============================================================================

wizard_remove_tool() {
    print_header "交互式配置向导 - 删除工具"

    # Get all tools
    local tools=""
    while IFS= read -r tool_name; do
        [[ -n "$tool_name" ]] && tools="$tools$tool_name"$'\n'
    done < <(get_tool_names)

    if [[ -z "$tools" ]]; then
        error_exit "没有找到任何工具"
    fi

    # Store tools in array
    local tool_count=0
    declare -a tool_list
    while IFS= read -r tool_name; do
        [[ -n "$tool_name" ]] && tool_list+=("$tool_name")
    done < <(get_tool_names)

    # Get tool display names
    echo "可用的工具:"
    local i=1
    for tool_name in "${tool_list[@]}"; do
        local tool_json
        tool_json=$(get_tool_by_name "$tool_name")
        local display_name
        display_name=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('display_name','$tool_name'))" 2>/dev/null || echo "$tool_name")
        local category
        category=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('category',''))" 2>/dev/null || echo "")
        echo "  $i) $tool_name - $display_name"
        [[ -n "$category" ]] && echo "     类别: $category"
        ((i++))
    done
    echo ""

    local choice
    IFS= read -e -r -p "选择要删除的工具 [1-${#tool_list[@]}]: " choice

    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#tool_list[@]} ]]; then
        error_exit "无效选择"
    fi

    local tool_to_remove="${tool_list[$((choice-1))]}"

    if confirm "确认删除 '$tool_to_remove'？" "N"; then
        remove_tool_from_yaml "$tool_to_remove"
        success "工具 '$tool_to_remove' 已从 tools.yaml 删除"
        info "运行 'ai-tools validate' 验证配置"
    else
        info "操作已取消"
    fi
}

# ==============================================================================
# YAML Modification Functions
# ==============================================================================

add_tool_to_yaml() {
    local backup_file
    backup_file=$(backup_config)

    # Get data
    local name=$(get_tool_data name)
    local display_name=$(get_tool_data display_name)
    local description=$(get_tool_data description)
    local category=$(get_tool_data category)
    local url=$(get_tool_data url)
    local install_cmd=$(get_tool_data install_command)
    local verify_cmd=$(get_tool_data verify_command)

    # Build YAML entry
    local yaml_entry=""
    yaml_entry+="  # --------------------------------------------------------------------------"$'\n'
    yaml_entry+="  # 工具: $display_name"$'\n'
    yaml_entry+="  # --------------------------------------------------------------------------"$'\n'
    yaml_entry+="  - name: $name"$'\n'
    yaml_entry+="    display_name: \"$display_name\""$'\n'
    yaml_entry+="    description: \"$description\""$'\n'
    yaml_entry+="    category: $category"$'\n'

    if [[ -n "$url" ]]; then
        yaml_entry+="    url: \"$url\""$'\n'
    fi

    yaml_entry+="    install:"$'\n'
    yaml_entry+="      command: |"$'\n'
    yaml_entry+="        $install_cmd"$'\n'

    if [[ -n "$verify_cmd" ]]; then
        yaml_entry+="      verify: \"$verify_cmd\""$'\n'
    fi

    yaml_entry+="      requires: []"$'\n'

    # Add commands if any
    local cmd_count=$(count_commands)
    if [[ $cmd_count -gt 0 ]]; then
        yaml_entry+="    commands:"$'\n'
        while IFS= read -r cmd; do
            local cmd_name=$(echo "$cmd" | cut -d'|' -f1)
            local cmd_desc=$(echo "$cmd" | cut -d'|' -f2)
            local cmd_syntax=$(echo "$cmd" | cut -d'|' -f3)
            yaml_entry+="      - name: \"$cmd_name\""$'\n'
            yaml_entry+="        description: \"$cmd_desc\""$'\n'
            yaml_entry+="        syntax: \"$cmd_syntax\""$'\n'
        done < "$TOOL_COMMANDS_FILE"
    fi

    # Insert before groups section or at end
    if grep -q "^groups:" "$TOOLS_CONFIG"; then
        # Insert before groups using Python
        python3 -c "
import sys
with open('$TOOLS_CONFIG', 'r') as f:
    lines = f.readlines()

# Find groups line
insert_idx = -1
for i, line in enumerate(lines):
    if line.startswith('groups:'):
        insert_idx = i
        break

# Insert new tool before groups
yaml_entry = '''$yaml_entry'''
if insert_idx >= 0:
    lines.insert(insert_idx, yaml_entry)
else:
    lines.append(yaml_entry)

with open('$TOOLS_CONFIG', 'w') as f:
    f.writelines(lines)
"
    else
        # Append to file
        echo "" >> "$TOOLS_CONFIG"
        echo "$yaml_entry" >> "$TOOLS_CONFIG"
    fi

    # Validate and restore if needed
    if ! validate_after_change; then
        restore_backup "$backup_file"
        error_exit "验证失败，已恢复备份"
    fi

    if [[ $VERBOSE -eq 1 ]]; then
        info "备份保存在: $backup_file"
    fi
}

edit_tool_in_yaml() {
    local backup_file
    backup_file=$(backup_config)

    # Get data
    local name=$(get_tool_data name)
    local display_name=$(get_tool_data display_name)
    local description=$(get_tool_data description)
    local category=$(get_tool_data category)
    local url=$(get_tool_data url)
    local install_cmd=$(get_tool_data install_command)
    local verify_cmd=$(get_tool_data verify_command)

    # Use Python to modify YAML
    python3 -c "
import yaml
import sys

with open('$TOOLS_CONFIG', 'r') as f:
    data = yaml.safe_load(f)

tools = data.get('tools', [])
for i, tool in enumerate(tools):
    if tool.get('name') == '$name':
        tool['display_name'] = '$display_name'
        tool['description'] = '$description'
        tool['category'] = '$category'
        tool['url'] = '$url'

        if 'install' not in tool:
            tool['install'] = {}
        tool['install']['command'] = '$install_cmd'
        if '$verify_cmd':
            tool['install']['verify'] = '$verify_cmd'
        elif 'verify' in tool['install']:
            del tool['install']['verify']

        if 'requires' not in tool['install']:
            tool['install']['requires'] = []
        break

with open('$TOOLS_CONFIG', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
"

    # Validate and restore if needed
    if ! validate_after_change; then
        restore_backup "$backup_file"
        error_exit "验证失败，已恢复备份"
    fi

    if [[ $VERBOSE -eq 1 ]]; then
        info "备份保存在: $backup_file"
    fi
}

remove_tool_from_yaml() {
    local tool_name="$1"
    local backup_file
    backup_file=$(backup_config)

    # Use Python to remove tool
    python3 -c "
import yaml
import sys

with open('$TOOLS_CONFIG', 'r') as f:
    data = yaml.safe_load(f)

tools = data.get('tools', [])
data['tools'] = [t for t in tools if t.get('name') != '$tool_name']

# Also remove from groups
if 'groups' in data:
    for group in data['groups']:
        if 'tools' in group:
            group['tools'] = [t for t in group['tools'] if t != '$tool_name']

# Also remove from aliases
if 'aliases' in data:
    aliases_to_remove = [k for k, v in data['aliases'].items() if v == '$tool_name']
    for alias in aliases_to_remove:
        del data['aliases'][alias]

with open('$TOOLS_CONFIG', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
"

    # Validate and restore if needed
    if ! validate_after_change; then
        restore_backup "$backup_file"
        error_exit "验证失败，已恢复备份"
    fi

    if [[ $VERBOSE -eq 1 ]]; then
        info "备份保存在: $backup_file"
    fi
}

validate_after_change() {
    if [[ -x "${SCRIPT_DIR}/config-validator.sh" ]]; then
        "${SCRIPT_DIR}/config-validator.sh" "$TOOLS_CONFIG" >/dev/null 2>&1
        return $?
    fi
    return 0
}

# ==============================================================================
# List Tools
# ==============================================================================

list_tools() {
    print_header "已配置的工具"

    if [[ ! -f "$TOOLS_CONFIG" ]]; then
        error_exit "配置文件不存在: $TOOLS_CONFIG"
    fi

    local tool_count=0
    declare -a tools
    while IFS= read -r tool_name; do
        [[ -n "$tool_name" ]] && tools+=("$tool_name")
    done < <(get_tool_names)

    if [[ ${#tools[@]} -eq 0 ]]; then
        echo "  没有找到任何工具"
        return
    fi

    echo "  共 ${#tools[@]} 个工具:"
    echo ""

    for tool_name in "${tools[@]}"; do
        local tool_json
        tool_json=$(get_tool_by_name "$tool_name")
        local display_name
        display_name=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('display_name','$tool_name'))" 2>/dev/null || echo "$tool_name")
        local description
        description=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" 2>/dev/null || echo "")
        local category
        category=$(echo "$tool_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('category',''))" 2>/dev/null || echo "")

        echo -e "  ${BOLD}$tool_name${NC} - $display_name"
        [[ -n "$description" ]] && echo -e "    ${CYAN}$description${NC}"
        [[ -n "$category" ]] && echo -e "    类别: ${GREEN}$category${NC}"
        echo ""
    done
}

# ==============================================================================
# Non-Interactive Mode
# ==============================================================================

non_interactive_add() {
    local name=""
    local display_name=""
    local description=""
    local category="other"
    local install_command=""
    local verify_command=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            --display-name)
                display_name="$2"
                shift 2
                ;;
            --description)
                description="$2"
                shift 2
                ;;
            --category)
                category="$2"
                shift 2
                ;;
            --install-command)
                install_command="$2"
                shift 2
                ;;
            --verify-command)
                verify_command="$2"
                shift 2
                ;;
            *)
                error_exit "未知选项: $1"
                ;;
        esac
    done

    # Clear previous data
    clear_tool_data

    # Validate required fields
    if [[ -z "$name" ]]; then
        error_exit "--name 是必需的"
    fi

    if ! validate_tool_name "$name" >/dev/null 2>&1; then
        error_exit "无效的工具名称: $name"
    fi

    if [[ -z "$install_command" ]]; then
        error_exit "--install-command 是必需的"
    fi

    if ! is_valid_category "$category"; then
        error_exit "无效的类别: $category (应为: ai, local, workflow, coding, other)"
    fi

    # Set defaults
    [[ -z "$display_name" ]] && display_name="$name"

    # Populate data
    set_tool_data "name" "$name"
    set_tool_data "display_name" "$display_name"
    set_tool_data "description" "$description"
    set_tool_data "category" "$category"
    set_tool_data "install_command" "$install_command"
    set_tool_data "verify_command" "$verify_command"
    set_tool_data "url" ""

    # Add tool
    add_tool_to_yaml
    success "工具 '$name' 已添加"
}

# ==============================================================================
# Usage and Help
# ==============================================================================

show_usage() {
    cat << EOF
AI CLI Tools 交互式配置向导 v${SCRIPT_VERSION}

用法:
    $0 <action> [options]

操作:
    add                       交互式添加新工具
    remove                    交互式删除工具
    edit <tool-name>          交互式编辑工具
    list                      列出所有工具

非交互模式选项:
    --name <name>             工具名称 (kebab-case)
    --display-name <name>     显示名称
    --description <text>      工具描述
    --category <cat>          类别 (ai|local|workflow|coding|other)
    --install-command <cmd>   安装命令
    --verify-command <cmd>    验证命令

其他选项:
    --verbose                 显示详细输出
    --dry-run                 预览但不修改
    --help, -h                显示此帮助信息

示例:
    # 交互式添加工具
    $0 add

    # 交互式删除工具
    $0 remove

    # 编辑现有工具
    $0 edit claude

    # 非交互模式添加工具
    $0 add --name "my-tool" \\
        --display-name "My Tool" \\
        --description "A great tool" \\
        --category "ai" \\
        --install-command "npm install -g my-tool"

    # 列出所有工具
    $0 list

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

    # Check for help first
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_usage
        exit 0
    fi

    local action="$1"
    shift

    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                VERBOSE=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            *)
                break
                ;;
        esac
    done

    # Execute action
    case "$action" in
        add)
            if has_non_interactive_flags "$@"; then
                non_interactive_add "$@"
            else
                wizard_add_tool
            fi
            ;;
        remove|rm)
            wizard_remove_tool
            ;;
        edit)
            if [[ $# -eq 0 ]]; then
                error_exit "请指定要编辑的工具名称"
            fi
            wizard_edit_tool "$1"
            ;;
        list|ls)
            list_tools
            ;;
        *)
            error_exit "未知操作: $action. 使用 --help 查看帮助"
            ;;
    esac
}

has_non_interactive_flags() {
    for arg in "$@"; do
        case "$arg" in
            --name|--display-name|--description|--category|--install-command|--verify-command)
                return 0
                ;;
        esac
    done
    return 1
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}操作已取消${NC}"; exit 130' INT

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
