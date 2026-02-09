#!/bin/bash
# ==============================================================================
# AI CLI Tools - YAML Parser Module
# ==============================================================================
# Version: 2.0.0
# Purpose: Parse YAML configuration files and output structured data
#
# Usage:
#   ./yaml-parser.sh <file_path> <output_type> [options]
#
# Examples:
#   ./yaml-parser.sh ~/.config/ai-tools/tools.yaml tools
#   ./yaml-parser.sh ~/.config/ai-tools/tools.yaml tools --field name
#   ./yaml-parser.sh ~/.config/ai-tools/tools.yaml tools --filter category=ai
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Constants and Variables
# ==============================================================================

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_ROOT="${SCRIPT_DIR}/.."

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Global arrays for storing parsed data
declare -a TOOLS_JSON=()
declare -a ALIASES_JSON=()

# Temporary storage for current tool
TOOL_NAME=""
TOOL_DISPLAY_NAME=""
TOOL_DESCRIPTION=""
TOOL_CATEGORY=""
TOOL_URL=""
INSTALL_COMMAND=""
INSTALL_VERIFY=""
CONFIG_ENV=""
COMMANDS_JSON="[]"

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
    echo -e "${BLUE}Info:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}Success:${NC} $1" >&2
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

trim() {
    local string="$1"
    string="${string#"${string%%[![:space:]]*}"}"
    string="${string%"${string##*[![:space:]]}"}"
    printf '%s' "$string"
}

get_indent() {
    local line="$1"
    local spaces="${line%%[![:space:]]*}"
    printf '%d' "${#spaces}"
}

is_comment() {
    [[ "$1" =~ ^[[:space:]]*# ]]
}

is_empty() {
    [[ -z "$(trim "$1")" ]]
}

# ==============================================================================
# YAML Parsing Functions
# ==============================================================================

reset_tool_state() {
    TOOL_NAME=""
    TOOL_DISPLAY_NAME=""
    TOOL_DESCRIPTION=""
    TOOL_CATEGORY=""
    TOOL_URL=""
    INSTALL_COMMAND=""
    INSTALL_VERIFY=""
    CONFIG_ENV=""
    COMMANDS_JSON="[]"
}

save_current_tool() {
    if [[ -z "$TOOL_NAME" ]]; then
        return
    fi

    local tool_json="{\"name\": \"$TOOL_NAME\""

    if [[ -n "$TOOL_DISPLAY_NAME" ]]; then
        tool_json="$tool_json, \"display_name\": \"$(json_escape "$TOOL_DISPLAY_NAME")\""
    fi

    if [[ -n "$TOOL_DESCRIPTION" ]]; then
        tool_json="$tool_json, \"description\": \"$(json_escape "$TOOL_DESCRIPTION")\""
    fi

    if [[ -n "$TOOL_CATEGORY" ]]; then
        tool_json="$tool_json, \"category\": \"$TOOL_CATEGORY\""
    fi

    if [[ -n "$TOOL_URL" ]]; then
        tool_json="$tool_json, \"url\": \"$TOOL_URL\""
    fi

    if [[ -n "$INSTALL_COMMAND" ]] || [[ -n "$INSTALL_VERIFY" ]]; then
        tool_json="$tool_json, \"install\": {"
        local first=1
        if [[ -n "$INSTALL_COMMAND" ]]; then
            tool_json="$tool_json\"command\": \"$(json_escape "$INSTALL_COMMAND")\""
            first=0
        fi
        if [[ -n "$INSTALL_VERIFY" ]]; then
            if [[ $first -eq 0 ]]; then
                tool_json="$tool_json, "
            fi
            tool_json="$tool_json\"verify\": \"$(json_escape "$INSTALL_VERIFY")\""
        fi
        tool_json="$tool_json}"
    fi

    if [[ -n "$CONFIG_ENV" ]]; then
        tool_json="$tool_json, \"env\": $CONFIG_ENV"
    fi

    if [[ "$COMMANDS_JSON" != "[]" ]] && [[ -n "$COMMANDS_JSON" ]]; then
        tool_json="$tool_json, \"commands\": $COMMANDS_JSON"
    fi

    tool_json="$tool_json}"
    TOOLS_JSON+=("$tool_json")
}

# Main parsing function
parse_tools_yaml() {
    local file="$1"
    local output_format="${2:-json}"
    local filter_field="${3:-}"
    local filter_value="${4:-}"

    # Reset state
    TOOLS_JSON=()
    ALIASES_JSON=()
    reset_tool_state

    local IN_GROUPS_BLOCK=0
    local IN_ALIASES_BLOCK=0
    local IN_INSTALL_BLOCK=0
    local IN_CONFIG_BLOCK=0
    local IN_COMMANDS_BLOCK=0

    # Read file into array
    local lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done < "$file"

    local total=${#lines[@]}
    local i=0

    while [[ $i -lt $total ]]; do
        local line="${lines[$i]}"
        local indent
        indent=$(get_indent "$line")
        local trimmed
        trimmed=$(trim "$line")

        # Skip comments and empty lines
        if is_comment "$line"; then
            ((i++))
            continue
        fi

        if is_empty "$line"; then
            ((i++))
            continue
        fi

        # Track section changes
        if [[ "$trimmed" =~ ^groups: ]]; then
            IN_GROUPS_BLOCK=1
            IN_ALIASES_BLOCK=0
            ((i++))
            continue
        fi

        if [[ "$trimmed" =~ ^aliases: ]]; then
            IN_ALIASES_BLOCK=1
            IN_GROUPS_BLOCK=0
            ((i++))
            continue
        fi

        # Parse aliases (indent 2, key: value format)
        if [[ $IN_ALIASES_BLOCK -eq 1 ]] && [[ $indent -eq 2 ]] && [[ "$trimmed" =~ ^([^:]+):[[:space:]]+(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            ALIASES_JSON+=("\"$key\": \"$value\"")
            ((i++))
            continue
        fi

        # Skip groups section for now
        if [[ $IN_GROUPS_BLOCK -eq 1 ]]; then
            ((i++))
            continue
        fi

        # Parse tool entry (indent 2, - name: value)
        if [[ $indent -eq 2 ]] && [[ "$trimmed" =~ ^-[[:space:]]+name:[[:space:]]+(.+)$ ]]; then
            # Save previous tool
            save_current_tool
            reset_tool_state

            TOOL_NAME="${BASH_REMATCH[1]}"
            TOOL_NAME="${TOOL_NAME//\"/}"
            IN_INSTALL_BLOCK=0
            IN_CONFIG_BLOCK=0
            IN_COMMANDS_BLOCK=0
            ((i++))
            continue
        fi

        # Skip if not in a tool
        if [[ -z "$TOOL_NAME" ]]; then
            ((i++))
            continue
        fi

        # Parse tool properties (indent 4)
        if [[ $indent -eq 4 ]]; then
            if [[ "$trimmed" =~ ^([^:]+):[[:space:]]*(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"

                key=$(trim "$key")
                value=$(trim "$value")
                value="${value//\"/}"

                case "$key" in
                    display_name)
                        TOOL_DISPLAY_NAME="$value"
                        ;;
                    description)
                        TOOL_DESCRIPTION="$value"
                        ;;
                    category)
                        TOOL_CATEGORY="$value"
                        ;;
                    url)
                        TOOL_URL="$value"
                        ;;
                    install)
                        IN_INSTALL_BLOCK=1
                        IN_CONFIG_BLOCK=0
                        IN_COMMANDS_BLOCK=0
                        ;;
                    config)
                        IN_CONFIG_BLOCK=1
                        IN_INSTALL_BLOCK=0
                        IN_COMMANDS_BLOCK=0
                        ;;
                    commands)
                        IN_COMMANDS_BLOCK=1
                        IN_INSTALL_BLOCK=0
                        IN_CONFIG_BLOCK=0
                        # Parse commands inline (start from next line)
                        COMMANDS_JSON=$(parse_commands_inline "$((i + 1))" "${lines[@]}")
                        ;;
                esac
            fi
            ((i++))
            continue
        fi

        # Parse install block (indent 6)
        if [[ $IN_INSTALL_BLOCK -eq 1 ]] && [[ $indent -eq 6 ]]; then
            if [[ "$trimmed" =~ ^command:[[:space:]]*(.*)$ ]]; then
                INSTALL_COMMAND="${BASH_REMATCH[1]}"
                INSTALL_COMMAND="${INSTALL_COMMAND//\"/}"
            elif [[ "$trimmed" =~ ^verify:[[:space:]]*(.*)$ ]]; then
                INSTALL_VERIFY="${BASH_REMATCH[1]}"
                INSTALL_VERIFY="${INSTALL_VERIFY//\"/}"
            fi
            ((i++))
            continue
        fi

        # Parse config block (indent 6)
        if [[ $IN_CONFIG_BLOCK -eq 1 ]] && [[ $indent -eq 6 ]] && [[ "$trimmed" =~ ^env: ]]; then
            CONFIG_ENV=$(parse_env_inline "$i" "${lines[@]}")
            ((i++))
            continue
        fi

        # Reset block states when returning to higher level
        if [[ $indent -le 4 ]]; then
            IN_INSTALL_BLOCK=0
            IN_CONFIG_BLOCK=0
        fi

        ((i++))
    done

    # Save last tool
    save_current_tool

    # Output
    case "$output_format" in
        json)
            output_json "$filter_field" "$filter_value"
            ;;
        raw)
            output_raw
            ;;
        *)
            error_exit "Unknown output format: $output_format"
            ;;
    esac
}

# Parse commands array starting from given index
parse_commands_inline() {
    local start_idx=$1
    shift
    local lines=("$@")

    local commands=()
    local i=$start_idx
    local total=${#lines[@]}

    while [[ $i -lt $total ]]; do
        local line="${lines[$i]}"
        local indent
        indent=$(get_indent "$line")
        local trimmed
        trimmed=$(trim "$line")

        # Exit when returning to tool level
        if [[ $indent -le 4 ]]; then
            break
        fi

        # Found a command entry (indent 6, - name:)
        if [[ $indent -eq 6 ]] && [[ "$trimmed" =~ ^-[[:space:]]+name:[[:space:]]+(.+)$ ]]; then
            local cmd_name="${BASH_REMATCH[1]}"
            cmd_name="${cmd_name//\"/}"
            local cmd_desc=""
            local cmd_syntax=""
            ((i++))

            # Read command properties (indent 8)
            while [[ $i -lt $total ]]; do
                local next_line="${lines[$i]}"
                local next_indent
                next_indent=$(get_indent "$next_line")
                local next_trimmed
                next_trimmed=$(trim "$next_line")

                if [[ $next_indent -le 6 ]]; then
                    break
                fi

                if [[ $next_indent -eq 8 ]] && [[ "$next_trimmed" =~ ^([^:]+):[[:space:]]*(.*)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local value="${BASH_REMATCH[2]}"
                    key=$(trim "$key")
                    value=$(trim "$value")
                    value="${value//\"/}"

                    case "$key" in
                        description)
                            cmd_desc="$value"
                            ;;
                        syntax)
                            cmd_syntax="$value"
                            ;;
                    esac
                fi
                ((i++))
            done

            # Build command JSON
            local cmd_json="{\"name\": \"$cmd_name\""
            if [[ -n "$cmd_desc" ]]; then
                cmd_json="$cmd_json, \"description\": \"$(json_escape "$cmd_desc")\""
            fi
            if [[ -n "$cmd_syntax" ]]; then
                cmd_json="$cmd_json, \"syntax\": \"$(json_escape "$cmd_syntax")\""
            fi
            cmd_json="$cmd_json}"
            commands+=("$cmd_json")

            continue
        fi

        ((i++))
    done

    # Build JSON array
    if [[ ${#commands[@]} -eq 0 ]]; then
        echo "[]"
    else
        local result="["
        local first=1
        for cmd in "${commands[@]}"; do
            if [[ $first -eq 0 ]]; then
                result="$result, "
            fi
            result="$result$cmd"
            first=0
        done
        result="$result]"
        echo "$result"
    fi
}

# Parse env array starting from given index
parse_env_inline() {
    local start_idx=$1
    shift
    local lines=("$@")

    local env_vars=()
    local i=$((start_idx + 1))
    local total=${#lines[@]}

    while [[ $i -lt $total ]]; do
        local line="${lines[$i]}"
        local indent
        indent=$(get_indent "$line")
        local trimmed
        trimmed=$(trim "$line")

        # Exit when returning to config level
        if [[ $indent -le 6 ]]; then
            break
        fi

        # Found env entry (indent 8, - name:)
        if [[ $indent -eq 8 ]] && [[ "$trimmed" =~ ^-[[:space:]]+name:[[:space:]]+(.+)$ ]]; then
            local env_name="${BASH_REMATCH[1]}"
            env_name="${env_name//\"/}"
            env_vars+=("$env_name")
        fi

        ((i++))
    done

    # Build JSON array
    if [[ ${#env_vars[@]} -eq 0 ]]; then
        echo "[]"
    else
        local result="["
        local first=1
        for env in "${env_vars[@]}"; do
            if [[ $first -eq 0 ]]; then
                result="$result, "
            fi
            result="$result\"$env\""
            first=0
        done
        result="$result]"
        echo "$result"
    fi
}

output_json() {
    local filter_field="$1"
    local filter_value="$2"

    echo "{"
    echo "  \"version\": \"$SCRIPT_VERSION\","
    echo "  \"generated_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"tools\": ["

    local first=1
    for tool in "${TOOLS_JSON[@]}"; do
        local include=1
        if [[ -n "$filter_field" ]] && [[ -n "$filter_value" ]]; then
            if ! echo "$tool" | grep -q "\"$filter_field\"[[:space:]]*:[[:space:]]*\"$filter_value\""; then
                include=0
            fi
        fi

        if [[ $include -eq 1 ]]; then
            if [[ $first -eq 0 ]]; then
                echo ","
            fi
            echo "    $tool"
            first=0
        fi
    done

    echo "  ],"
    echo "  \"groups\": []"

    if [[ ${#ALIASES_JSON[@]} -gt 0 ]]; then
        echo ","
        echo "  \"aliases\": {"
        local first=1
        for alias in "${ALIASES_JSON[@]}"; do
            if [[ $first -eq 0 ]]; then
                echo ","
            fi
            echo "    $alias"
            first=0
        done
        echo "  }"
    fi

    echo "}"
}

output_raw() {
    echo "=== Parsed Tools (${#TOOLS_JSON[@]}) ==="
    for tool in "${TOOLS_JSON[@]}"; do
        echo "$tool"
        echo ""
    done

    echo "=== Parsed Aliases (${#ALIASES_JSON[@]}) ==="
    for alias in "${ALIASES_JSON[@]}"; do
        echo "$alias"
    done
}

parse_rules_yaml() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        error_exit "Rules file not found: $file"
    fi
    echo "{"
    echo "  \"version\": \"$SCRIPT_VERSION\","
    echo "  \"rules\": []"
    echo "}"
}

validate_yaml() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        error_exit "File not found: $file"
    fi
    if [[ ! -r "$file" ]]; then
        error_exit "File not readable: $file"
    fi
    if ! grep -q "version:" "$file"; then
        warn "Missing version field in $file"
    fi
    success "YAML file validation passed: $file"
    return 0
}

extract_field() {
    local file="$1"
    local field="$2"
    parse_tools_yaml "$file" "json" "$field" "" 2>/dev/null | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4 | grep -v "^$"
}

show_usage() {
    cat << EOF
AI CLI Tools YAML Parser v${SCRIPT_VERSION}

Usage:
    $0 <file_path> <output_type> [options]

Arguments:
    file_path       Path to YAML file to parse
    output_type     Type of output: 'tools', 'rules', 'validate', 'extract'

Options:
    --field <name>  Extract specific field from tools
    --filter <k=v>  Filter output by key=value pair
    --help          Show this help message

Examples:
    $0 ~/.config/ai-tools/tools.yaml tools
    $0 ~/.config/ai-tools/tools.yaml validate
    $0 ~/.config/ai-tools/tools.yaml extract --field display_name
    $0 ~/.config/ai-tools/tools.yaml tools --filter category=ai

EOF
}

main() {
    if [[ $# -lt 2 ]]; then
        show_usage
        exit 1
    fi

    local file_path="$1"
    local output_type="$2"
    local filter_field=""
    local filter_value=""

    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --field)
                filter_field="$2"
                shift 2
                ;;
            --filter)
                local filter="$2"
                filter_field="${filter%%=*}"
                filter_value="${filter#*=}"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done

    file_path="${file_path/#\~/$HOME}"

    if [[ ! -f "$file_path" ]]; then
        error_exit "File not found: $file_path"
    fi

    case "$output_type" in
        tools)
            parse_tools_yaml "$file_path" "json" "$filter_field" "$filter_value"
            ;;
        rules)
            parse_rules_yaml "$file_path"
            ;;
        validate)
            validate_yaml "$file_path"
            ;;
        extract)
            if [[ -z "$filter_field" ]]; then
                error_exit "--field is required for extract mode"
            fi
            extract_field "$file_path" "$filter_field"
            ;;
        *)
            error_exit "Unknown output type: $output_type"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
