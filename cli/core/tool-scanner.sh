#!/bin/bash
# ==============================================================================
# AI CLI Tool Scanner
# ==============================================================================
# 自动扫描和发现系统中已安装的 AI CLI 工具
#
# 用法:
#   tool-scanner.sh [options]
#
# 选项:
#   --sources SRC     只扫描指定来源 (path,npm,pip,brew,cargo)
#   --format FMT      输出格式 (text|json) [默认: text]
#   --verbose         详细输出
#   --test            测试模式（输出调试信息）
#   --help            显示帮助
#
# 示例:
#   # 扫描所有来源
#   ./tool-scanner.sh
#
#   # 只扫描 PATH 和 npm
#   ./tool-scanner.sh --sources path,npm
#
#   # 输出 JSON 格式
#   ./tool-scanner.sh --format json
#
#   # 详细输出
#   ./tool-scanner.sh --verbose
# ==============================================================================

set -eo pipefail

# ==============================================================================
# 配置和常量
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
TOOLS_YAML="$CONFIG_DIR/tools.yaml"

# 临时文件存储扫描结果（兼容 bash 3.2）
TMPDIR="${TMPDIR:-/tmp}"
SCAN_PATH_FILE="$TMPDIR/ai-tools-scan-path.$$"
SCAN_NPM_FILE="$TMPDIR/ai-tools-scan-npm.$$"
SCAN_PIP_FILE="$TMPDIR/ai-tools-scan-pip.$$"
SCAN_BREW_FILE="$TMPDIR/ai-tools-scan-brew.$$"
SCAN_CARGO_FILE="$TMPDIR/ai-tools-scan-cargo.$$"
SCAN_JSON_FILE="$TMPDIR/ai-tools-json.$$"

# AI 工具关键词列表
AI_KEYWORDS="claude|openai|ollama|gemini|gpt|llama|mistral|fabric|aider|copilot|chatgpt|codellama|anthropic"

# 已知 AI 工具名称列表
KNOWN_TOOL_NAMES="claude openai ollama fabric aider gemini copilot chatgpt llama mistral"

# ==============================================================================
# 全局变量
# ==============================================================================

SCAN_SOURCES="all"
OUTPUT_FORMAT="text"
VERBOSE=false
TEST_MODE=false

# 统计
TOTAL_INSTALLED=0
TOTAL_MISSING=0
TOTAL_CONFIGURED=0

# ==============================================================================
# 工具函数
# ==============================================================================

# 清理临时文件
cleanup() {
    rm -f "$SCAN_PATH_FILE" "$SCAN_NPM_FILE" "$SCAN_PIP_FILE" "$SCAN_BREW_FILE" "$SCAN_CARGO_FILE" "$SCAN_JSON_FILE" 2>/dev/null
}

trap cleanup EXIT

# 打印消息
print_info() {
    local msg="$1"
    echo "🔍 $msg"
}

print_success() {
    local msg="$1"
    echo "✅ $msg"
}

print_error() {
    local msg="$1"
    echo "❌ $msg"
}

print_warning() {
    local msg="$1"
    echo "⚠️  $msg"
}

# 详细输出
verbose_log() {
    if [[ "$VERBOSE" == true ]]; then
        echo "  [DEBUG] $*" >&2
    fi
}

# 测试模式输出
test_log() {
    if [[ "$TEST_MODE" == true ]]; then
        echo "  [TEST] $*" >&2
    fi
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &>/dev/null
}

# 转小写（兼容 bash 3.2）
to_lower() {
    echo "$1" | tr 'A-Z' 'a-z'
}

# 获取命令版本
get_version() {
    local cmd="$1"
    local version_flag="${2:---version}"

    # 尝试获取版本
    if output=$($cmd $version_flag 2>&1); then
        echo "$output" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
    elif output=$($cmd -v 2>&1); then
        echo "$output" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
    else
        echo "unknown"
    fi
}

# 检查是否为 AI 工具
is_ai_tool() {
    local name="$1"
    local lower_name=$(to_lower "$name")

    # 检查已知工具
    for known in $KNOWN_TOOL_NAMES; do
        if [[ "$lower_name" == "$known" ]]; then
            return 0
        fi
    done

    # 检查模式匹配
    if echo "$lower_name" | grep -qE "ai-|-ai|-cli|$AI_KEYWORDS"; then
        return 0
    fi

    return 1
}

# ==============================================================================
# PATH 扫描
# ==============================================================================

scan_path() {
    verbose_log "开始扫描 PATH..."

    > "$SCAN_PATH_FILE"

    local found_tools=""

    # 检查已知工具
    for tool in $KNOWN_TOOL_NAMES; do
        if command_exists "$tool"; then
            local version=$(get_version "$tool")
            local path=$(command -v "$tool")
            echo "$tool|$version|$path" >> "$SCAN_PATH_FILE"
            found_tools="$found_tools $tool"
            verbose_log "发现已知工具: $tool ($version)"
        fi
    done

    # 扫描 PATH 目录（只扫描前几个目录，避免太慢）
    local dir_count=0
    echo "$PATH" | tr ':' '\n' | while read -r dir; do
        [[ -z "$dir" ]] && continue
        [[ ! -d "$dir" ]] && continue
        [[ $dir_count -ge 5 ]] && continue
        ((dir_count++)) || true

        verbose_log "扫描目录: $dir"

        # 查找可执行文件
        find "$dir" -maxdepth 1 -type f -perm +111 2>/dev/null | while read -r cmd; do
            local cmd_name=$(basename "$cmd")
            if is_ai_tool "$cmd_name"; then
                # 检查是否已记录
                if ! grep -q "^$cmd_name|" "$SCAN_PATH_FILE" 2>/dev/null; then
                    local version=$(get_version "$cmd_name")
                    echo "$cmd_name|$version|$cmd" >> "$SCAN_PATH_FILE"
                    verbose_log "发现: $cmd_name ($version)"
                fi
            fi
        done
    done

    local count=$(wc -l < "$SCAN_PATH_FILE" 2>/dev/null || echo 0)
    test_log "PATH 扫描完成: 发现 $count 个工具"
}

# ==============================================================================
# npm 扫描
# ==============================================================================

scan_npm() {
    verbose_log "开始扫描 npm 全局包..."

    > "$SCAN_NPM_FILE"

    if ! command_exists npm; then
        verbose_log "npm 未安装，跳过扫描"
        return
    fi

    # 获取全局安装的包
    if npm list -g --depth=0 2>/dev/null | grep -E '@?(anthropic|openai|google-ai|claude|ollama|gemini|gpt|llama|mistral|fabric|aider)' > /dev/null 2>&1; then
        npm list -g --depth=0 2>/dev/null | grep -E '@?(anthropic|openai|google-ai|claude|ollama|gemini|gpt|llama|mistral|fabric|aider)' | while read -r line; do
            # 解析包名和版本: "@anthropic-ai/claude-cli@1.2.3" 或 "├── package@1.0.0"
            local pkg_name=$(echo "$line" | sed 's/.*├── //' | sed 's/@.*//' | xargs)
            local pkg_version=$(echo "$line" | grep -oE '@[0-9]+\.[0-9]+\.[0-9]+' | sed 's/@//' | head -1)

            if [[ -n "$pkg_name" ]]; then
                if [[ -z "$pkg_version" ]]; then
                    pkg_version="unknown"
                fi
                echo "$pkg_name|$pkg_version" >> "$SCAN_NPM_FILE"
                verbose_log "发现 npm 包: $pkg_name ($pkg_version)"
            fi
        done
    fi

    local count=$(wc -l < "$SCAN_NPM_FILE" 2>/dev/null || echo 0)
    test_log "npm 扫描完成: 发现 $count 个包"
}

# ==============================================================================
# pip 扫描
# ==============================================================================

scan_pip() {
    verbose_log "开始扫描 pip 包..."

    > "$SCAN_PIP_FILE"

    local pip_cmd=""
    if command_exists pip3; then
        pip_cmd="pip3"
    elif command_exists pip; then
        pip_cmd="pip"
    else
        verbose_log "pip 未安装，跳过扫描"
        return
    fi

    # 获取已安装的包
    $pip_cmd list 2>/dev/null | tail -n +3 | while read -r line; do
        [[ -z "$line" ]] && continue

        local pkg_name=$(echo "$line" | awk '{print $1}')
        local pkg_version=$(echo "$line" | awk '{print $2}')

        if is_ai_tool "$pkg_name"; then
            echo "$pkg_name|$pkg_version" >> "$SCAN_PIP_FILE"
            verbose_log "发现 pip 包: $pkg_name ($pkg_version)"
        fi
    done

    local count=$(wc -l < "$SCAN_PIP_FILE" 2>/dev/null || echo 0)
    test_log "pip 扫描完成: 发现 $count 个包"
}

# ==============================================================================
# Homebrew 扫描
# ==============================================================================

scan_brew() {
    verbose_log "开始扫描 Homebrew..."

    > "$SCAN_BREW_FILE"

    if ! command_exists brew; then
        verbose_log "Homebrew 未安装，跳过扫描"
        return
    fi

    brew list --formula 2>/dev/null | grep -iE "$AI_KEYWORDS" | while read -r pkg_name; do
        # 尝试获取版本
        local pkg_version=$(brew info "$pkg_name" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        pkg_version=${pkg_version:-"unknown"}
        echo "$pkg_name|$pkg_version" >> "$SCAN_BREW_FILE"
        verbose_log "发现 brew 包: $pkg_name ($pkg_version)"
    done

    local count=$(wc -l < "$SCAN_BREW_FILE" 2>/dev/null || echo 0)
    test_log "brew 扫描完成: 发现 $count 个包"
}

# ==============================================================================
# Cargo 扫描
# ==============================================================================

scan_cargo() {
    verbose_log "开始扫描 Cargo..."

    > "$SCAN_CARGO_FILE"

    if ! command_exists cargo; then
        verbose_log "cargo 未安装，跳过扫描"
        return
    fi

    local cargo_home="${CARGO_HOME:-$HOME/.cargo}"
    local cargo_bin_dir="$cargo_home/bin"

    if [[ ! -d "$cargo_bin_dir" ]]; then
        verbose_log "Cargo bin 目录不存在: $cargo_bin_dir"
        return
    fi

    find "$cargo_bin_dir" -type f -perm +111 2>/dev/null | while read -r cmd; do
        local cmd_name=$(basename "$cmd")
        if is_ai_tool "$cmd_name"; then
            local version=$(get_version "$cmd_name")
            echo "$cmd_name|$version|$cmd" >> "$SCAN_CARGO_FILE"
            verbose_log "发现 cargo 工具: $cmd_name ($version)"
        fi
    done

    local count=$(wc -l < "$SCAN_CARGO_FILE" 2>/dev/null || echo 0)
    test_log "cargo 扫描完成: 发现 $count 个工具"
}

# ==============================================================================
# 配置检查
# ==============================================================================

check_any_config() {
    # 检查常见 API 密钥环境变量
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]] || \
       [[ -n "${OPENAI_API_KEY:-}" ]] || \
       [[ -n "${GOOGLE_API_KEY:-}" ]] || \
       [[ -n "${COHERE_API_KEY:-}" ]] || \
       [[ -n "${HUGGINGFACE_API_KEY:-}" ]] || \
       [[ -n "${OLLAMA_HOST:-}" ]]; then
        return 0
    fi
    return 1
}

# ==============================================================================
# 输出格式化
# ==============================================================================

# 文本格式输出
output_text() {
    echo "=========================================="
    echo "🔍 扫描系统中的 AI CLI 工具"
    echo "=========================================="
    echo ""

    # PATH 扫描结果
    echo "📂 PATH 扫描:"
    if [[ -s "$SCAN_PATH_FILE" ]]; then
        while IFS='|' read -r name version path; do
            echo "  ✅ $name (v$version) - $path"
        done < "$SCAN_PATH_FILE"
    else
        if [[ "$SCAN_SOURCES" == "all" ]] || [[ "$SCAN_SOURCES" == *"path"* ]]; then
            echo "  (无发现)"
        else
            echo "  (跳过)"
        fi
    fi
    echo ""

    # npm 扫描结果
    echo "📦 npm 扫描:"
    if [[ -s "$SCAN_NPM_FILE" ]]; then
        while IFS='|' read -r name version; do
            echo "  ✅ $name (v$version)"
        done < "$SCAN_NPM_FILE"
    else
        if [[ "$SCAN_SOURCES" == "all" ]] || [[ "$SCAN_SOURCES" == *"npm"* ]]; then
            echo "  (无发现)"
        else
            echo "  (跳过)"
        fi
    fi
    echo ""

    # pip 扫描结果
    echo "🐍 pip 扫描:"
    if [[ -s "$SCAN_PIP_FILE" ]]; then
        while IFS='|' read -r name version; do
            echo "  ✅ $name (v$version)"
        done < "$SCAN_PIP_FILE"
    else
        if [[ "$SCAN_SOURCES" == "all" ]] || [[ "$SCAN_SOURCES" == *"pip"* ]]; then
            echo "  (无发现)"
        else
            echo "  (跳过)"
        fi
    fi
    echo ""

    # brew 扫描结果
    echo "🍺 Homebrew 扫描:"
    if [[ -s "$SCAN_BREW_FILE" ]]; then
        while IFS='|' read -r name version; do
            echo "  ✅ $name (v$version)"
        done < "$SCAN_BREW_FILE"
    else
        if [[ "$SCAN_SOURCES" == "all" ]] || [[ "$SCAN_SOURCES" == *"brew"* ]]; then
            echo "  (无发现)"
        else
            echo "  (跳过)"
        fi
    fi
    echo ""

    # cargo 扫描结果
    echo "🦀 Cargo 扫描:"
    if [[ -s "$SCAN_CARGO_FILE" ]]; then
        while IFS='|' read -r name version path; do
            echo "  ✅ $name (v$version)"
        done < "$SCAN_CARGO_FILE"
    else
        if [[ "$SCAN_SOURCES" == "all" ]] || [[ "$SCAN_SOURCES" == *"cargo"* ]]; then
            echo "  (无发现)"
        else
            echo "  (跳过)"
        fi
    fi
    echo ""

    # 汇总
    calculate_summary
    echo "=========================================="
    echo "📊 汇总:"
    echo "  已安装: $TOTAL_INSTALLED 个"
    if check_any_config; then
        echo "  已配置: API 密钥已设置"
    else
        echo "  已配置: 未检测到 API 密钥"
    fi
    echo "=========================================="
}

# JSON 格式输出
output_json() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "{"
    echo "  \"scanned_at\": \"$timestamp\","
    echo "  \"sources\": {"

    local first=true

    # PATH 结果
    if [[ -s "$SCAN_PATH_FILE" ]]; then
        [[ "$first" == false ]] && echo ","
        first=false
        echo "    \"path\": {"
        echo "      \"found\": ["

        local first_tool=true
        while IFS='|' read -r name version path; do
            [[ "$first_tool" == false ]] && echo ","
            first_tool=false
            path=$(echo "$path" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
            printf '        {\"name\": \"%s\", \"version\": \"%s\", \"path\": \"%s\"}' "$name" "$version" "$path"
        done < "$SCAN_PATH_FILE"

        echo ""
        echo "      ]"
        printf "    }"
    fi

    # npm 结果
    if [[ -s "$SCAN_NPM_FILE" ]]; then
        [[ "$first" == false ]] && echo ","
        first=false
        echo ""
        echo "    \"npm\": {"
        echo "      \"found\": ["

        local first_pkg=true
        while IFS='|' read -r name version; do
            [[ "$first_pkg" == false ]] && echo ","
            first_pkg=false
            name=$(echo "$name" | sed 's/"/\\"/g')
            printf '        {\"name\": \"%s\", \"version\": \"%s\"}' "$name" "$version"
        done < "$SCAN_NPM_FILE"

        echo ""
        echo "      ]"
        printf "    }"
    fi

    # pip 结果
    if [[ -s "$SCAN_PIP_FILE" ]]; then
        [[ "$first" == false ]] && echo ","
        first=false
        echo ""
        echo "    \"pip\": {"
        echo "      \"found\": ["

        local first_pkg=true
        while IFS='|' read -r name version; do
            [[ "$first_pkg" == false ]] && echo ","
            first_pkg=false
            printf '        {\"name\": \"%s\", \"version\": \"%s\"}' "$name" "$version"
        done < "$SCAN_PIP_FILE"

        echo ""
        echo "      ]"
        printf "    }"
    fi

    # brew 结果
    if [[ -s "$SCAN_BREW_FILE" ]]; then
        [[ "$first" == false ]] && echo ","
        first=false
        echo ""
        echo "    \"brew\": {"
        echo "      \"found\": ["

        local first_pkg=true
        while IFS='|' read -r name version; do
            [[ "$first_pkg" == false ]] && echo ","
            first_pkg=false
            printf '        {\"name\": \"%s\", \"version\": \"%s\"}' "$name" "$version"
        done < "$SCAN_BREW_FILE"

        echo ""
        echo "      ]"
        printf "    }"
    fi

    # cargo 结果
    if [[ -s "$SCAN_CARGO_FILE" ]]; then
        [[ "$first" == false ]] && echo ","
        first=false
        echo ""
        echo "    \"cargo\": {"
        echo "      \"found\": ["

        local first_tool=true
        while IFS='|' read -r name version path; do
            [[ "$first_tool" == false ]] && echo ","
            first_tool=false
            printf '        {\"name\": \"%s\", \"version\": \"%s\"}' "$name" "$version"
        done < "$SCAN_CARGO_FILE"

        echo ""
        echo "      ]"
        printf "    }"
    fi

    echo ""
    echo "  },"
    echo "  \"summary\": {"
    calculate_summary
    echo "    \"total_installed\": $TOTAL_INSTALLED,"
    if check_any_config; then
        echo "    \"configured\": true"
    else
        echo "    \"configured\": false"
    fi
    echo "  }"
    echo "}"
}

# 计算汇总统计
calculate_summary() {
    TOTAL_INSTALLED=0

    # 在读取前先获取值，避免文件被清理
    local path_count=0
    local npm_count=0
    local pip_count=0
    local brew_count=0
    local cargo_count=0

    [[ -s "$SCAN_PATH_FILE" ]] && path_count=$(wc -l < "$SCAN_PATH_FILE" 2>/dev/null | tr -d ' ' || echo 0)
    [[ -s "$SCAN_NPM_FILE" ]] && npm_count=$(wc -l < "$SCAN_NPM_FILE" 2>/dev/null | tr -d ' ' || echo 0)
    [[ -s "$SCAN_PIP_FILE" ]] && pip_count=$(wc -l < "$SCAN_PIP_FILE" 2>/dev/null | tr -d ' ' || echo 0)
    [[ -s "$SCAN_BREW_FILE" ]] && brew_count=$(wc -l < "$SCAN_BREW_FILE" 2>/dev/null | tr -d ' ' || echo 0)
    [[ -s "$SCAN_CARGO_FILE" ]] && cargo_count=$(wc -l < "$SCAN_CARGO_FILE" 2>/dev/null | tr -d ' ' || echo 0)

    TOTAL_INSTALLED=$((path_count + npm_count + pip_count + brew_count + cargo_count))
}

# ==============================================================================
# 主扫描流程
# ==============================================================================

run_scan() {
    verbose_log "开始扫描，来源: $SCAN_SOURCES"

    # 清空临时文件
    > "$SCAN_PATH_FILE"
    > "$SCAN_NPM_FILE"
    > "$SCAN_PIP_FILE"
    > "$SCAN_BREW_FILE"
    > "$SCAN_CARGO_FILE"

    # 根据指定的来源执行扫描
    if [[ "$SCAN_SOURCES" == "all" ]]; then
        scan_path
        scan_npm
        scan_pip
        scan_brew
        scan_cargo
    else
        echo "$SCAN_SOURCES" | tr ',' '\n' | while read -r source; do
            source=$(echo "$source" | xargs)  # 去除空格
            case "$source" in
                path) scan_path ;;
                npm) scan_npm ;;
                pip) scan_pip ;;
                brew) scan_brew ;;
                cargo) scan_cargo ;;
                *) print_warning "未知来源: $source" ;;
            esac
        done
    fi

    verbose_log "所有扫描完成"
}

# ==============================================================================
# 帮助信息
# ==============================================================================

show_help() {
    cat << EOF
用法: $(basename "$0") [options]

选项:
  --sources SRC     只扫描指定来源，逗号分隔
                    可用: path, npm, pip, brew, cargo, all (默认)
  --format FMT      输出格式: text (默认) 或 json
  --verbose         详细输出，显示扫描过程
  --test            测试模式，输出调试信息
  --help            显示此帮助信息

示例:
  # 扫描所有来源
  $0

  # 只扫描 PATH 和 npm
  $0 --sources path,npm

  # 输出 JSON 格式
  $0 --format json

  # 详细模式
  $0 --verbose

来源说明:
  path   - 扫描 PATH 环境变量中的可执行文件
  npm    - 扫描 npm 全局安装的包
  pip    - 扫描 Python pip 安装的包
  brew   - 扫描 Homebrew 安装的 formula
  cargo  - 扫描 Cargo (Rust) 安装的工具

EOF
}

# ==============================================================================
# 参数解析
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sources)
                SCAN_SOURCES="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --test)
                TEST_MODE=true
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 验证输出格式
    if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" ]]; then
        print_error "无效的输出格式: $OUTPUT_FORMAT"
        exit 1
    fi
}

# ==============================================================================
# 主入口
# ==============================================================================

main() {
    parse_args "$@"
    run_scan

    case "$OUTPUT_FORMAT" in
        text)
            output_text
            ;;
        json)
            output_json
            ;;
    esac
}

# 如果直接运行脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
