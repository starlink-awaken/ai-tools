#!/bin/bash
# ==============================================================================
# AI CLI Tools Manager - Install Script
# ==============================================================================
# 一键安装脚本 - 快速部署 AI CLI 工具管理器
# Usage: ./install.sh [--prefix DIR] [--no-alias] [--keep-data]
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
readonly VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_PREFIX="${HOME}/.local"
readonly CONFIG_DIR="${HOME}/.config/ai-tools"
readonly BIN_DIR="${INSTALL_PREFIX}/bin"

# 选项
KEEP_DATA=false
NO_ALIAS=false
FORCE=false

# 颜色
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║     AI CLI Tools Manager v${VERSION} - 安装程序               ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

usage() {
    cat << EOF
${BOLD}用法:${NC} ./install.sh [选项]

${BOLD}选项:${NC}
  --prefix DIR     安装前缀目录 (默认: ${INSTALL_PREFIX})
  --no-alias       不创建别名
  --keep-data      保留现有数据（升级模式）
  --force          强制覆盖安装
  -h, --help       显示帮助

${BOLD}示例:${NC}
  ./install.sh                    # 标准安装
  ./install.sh --prefix /opt      # 自定义安装目录
  ./install.sh --keep-data        # 升级安装（保留数据）
  ./install.sh --no-alias         # 不创建别名

${BOLD}安装内容:${NC}
  • 核心模块: ${CONFIG_DIR}/core/
  • 配置文件: ${CONFIG_DIR}/config/
  • 数据文件: ${CONFIG_DIR}/data/
  • 可执行脚本: ${BIN_DIR}/ai-tools
  • Shell 别名: ai-tools
EOF
}

check_dependencies() {
    info "检查系统依赖..."

    # 检查 Python
    if ! command -v python3 &>/dev/null; then
        error "未找到 Python 3，请先安装 Python"
        info "macOS: brew install python3"
        info "Ubuntu/Debian: sudo apt install python3"
        info "CentOS/RHEL: sudo yum install python3"
        exit 1
    fi
    success "Python 3 已安装: $(python3 --version)"

    # 检查 PyYAML
    if ! python3 -c "import yaml" 2>/dev/null; then
        info "安装 PyYAML..."
        pip3 install pyyaml --quiet
        success "PyYAML 安装完成"
    else
        success "PyYAML 已安装"
    fi

    # 检查 Bash (macOS 需要)
    if [[ "$(uname)" == "Darwin" ]]; then
        local bash_version
        bash_version=$(bash --version | head -1)
        success "Bash: ${bash_version}"
        info "提示: macOS 默认 Bash 较旧，如遇问题请安装新版: brew install bash"
    fi
}

create_directories() {
    info "创建目录结构..."

    mkdir -p "${CONFIG_DIR}/core"
    mkdir -p "${CONFIG_DIR}/config"
    mkdir -p "${CONFIG_DIR}/data"
    mkdir -p "${CONFIG_DIR}/backups"
    mkdir -p "${BIN_DIR}"

    success "目录创建完成"
}

install_core_modules() {
    info "安装核心模块..."

    # 复制核心模块
    cp "${SCRIPT_DIR}/cli/core/"*.sh "${CONFIG_DIR}/core/"
    chmod +x "${CONFIG_DIR}/core/"*.sh

    # 复制配置文件
    cp "${SCRIPT_DIR}/config/tools.yaml" "${CONFIG_DIR}/config/"
    cp "${SCRIPT_DIR}/config/rules.yaml" "${CONFIG_DIR}/config/"

    # 创建空数据文件
    [[ ! -f "${CONFIG_DIR}/data/history.json" ]] && echo "[]" > "${CONFIG_DIR}/data/history.json"
    [[ ! -f "${CONFIG_DIR}/data/stats.json" ]] && echo "{}" > "${CONFIG_DIR}/data/stats.json"

    local count=$(ls -1 "${CONFIG_DIR}/core/"*.sh | wc -l)
    success "安装 ${count} 个核心模块"
}

create_main_script() {
    info "创建主脚本..."

    cat > "${BIN_DIR}/ai-tools" << 'MAIN_SCRIPT'
#!/bin/bash
# ==============================================================================
# AI CLI Tools Manager - Main Entry Point
# ==============================================================================
# Version: 2.0.0
# ==============================================================================

set -euo pipefail

readonly VERSION="2.0.0"
readonly CONFIG_DIR="${HOME}/.config/ai-tools"
readonly CORE_DIR="${CONFIG_DIR}/core"
readonly TOOLS_YAML="${CONFIG_DIR}/config/tools.yaml"

# 颜色
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# 选项
OUTPUT_FORMAT="text"
VERBOSE=false

# ------------------------------------------------------------------------------
# Utility Functions
# ------------------------------------------------------------------------------

error_exit() {
    echo -e "${RED}错误:${NC} $1" >&2
    exit 1
}

show_help() {
    cat << EOF
${BOLD}${CYAN}🤖 AI CLI 工具管理器 v${VERSION}${NC}

${BOLD}用法:${NC} ai-tools <command> [args]

${BOLD}命令:${NC}
  list                    列出所有工具
  route <task>           智能路由推荐
  info <tool>             查看工具详情
  scan                    扫描系统工具
  validate                验证配置
  history                 查看历史
  stats                   使用统计
  help                    显示帮助

${BOLD}选项:${NC}
  --format <fmt>          输出格式 (text|json)
  --verbose, -v            详细输出
  --version               显示版本

${BOLD}示例:${NC}
  ai-tools list
  ai-tools route "总结文章"
  ai-tools info claude
  ai-tools scan

${BOLD}文档:${NC}
  完整文档: ${CONFIG_DIR}/../README.md

EOF
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    # 检查配置文件
    [[ ! -f "${TOOLS_YAML}" ]] && error_exit "配置文件未找到: ${TOOLS_YAML}"

    # 解析选项
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
            --version)
                echo "AI CLI Tools Manager v${VERSION}"
                exit 0
                ;;
            help|--help|-h)
                show_help
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    local command="${1:-}"
    shift || true

    if [[ -z "$command" ]]; then
        show_help
        exit 0
    fi

    # 处理命令
    case "$command" in
        list)
            python3 - "${TOOLS_YAML}" << 'PYEOF'
import yaml
import sys
import subprocess

yaml_file = sys.argv[1]

with open(yaml_file, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

tools = data.get('tools', [])
categories = {}

for tool in tools:
    cat = tool.get('category', 'other')
    if cat not in categories:
        categories[cat] = []
    name = tool.get('name', '')
    display = tool.get('display_name', name)
    installed = subprocess.run(['which', name], capture_output=True).returncode == 0
    status = '✓' if installed else '✗'
    color = '32' if installed else '31'
    print(f'\033[{color}m{status}\033[0m {name:<12} - {display}')

print(f"\n共 {len(tools)} 个工具")
PYEOF
            ;;
        route)
            local task="$*"
            if [[ -z "$task" ]]; then
                error_exit "请指定任务描述，如: ai-tools route '总结文章'"
            fi
            python3 - "${TOOLS_YAML}" << 'PYEOF'
import yaml
import sys

yaml_file = sys.argv[1]
task = ' '.join(sys.argv[2:])

with open(yaml_file, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

rules = data.get('rules', [])
tools = {t.get('name'): t for t in data.get('tools', [])}

matched = []
for rule in rules:
    keywords = [k.lower() for k in rule.get('keywords', [])]
    task_lower = task.lower()
    if any(k in task_lower for k in keywords):
        for tool_name in rule.get('tools', []):
            if tool_name in tools:
                tool = tools[tool_name]
                matched.append({
                    'name': tool_name,
                    'display': tool.get('display_name', tool_name),
                    'description': tool.get('description', ''),
                    'priority': rule.get('priority', 1)
                })

matched.sort(key=lambda x: -x['priority'])

if matched:
    best = matched[0]
    print(f"\n🧠 分析任务: {task}")
    print(f"\n📊 推荐结果:")
    print(f"   ✅ {best['name']} (置信度: {best['priority'] * 10}%)")
    print(f"   📝 {best['description']}")
    if len(matched) > 1:
        print(f"\n💡 备选方案:")
        for m in matched[1:]:
            print(f"   • {m['name']} - {m['display']}")
else:
    print("未找到匹配的工具，请尝试:")
    print("  ai-tools list  # 列出所有可用工具")
PYEOF
            "$@"
            ;;
        info)
            local tool_name="${1:-}"
            [[ -z "$tool_name" ]] && error_exit "请指定工具名称"
            python3 - "${TOOLS_YAML}" << 'PYEOF'
import yaml
import sys
import subprocess

yaml_file = sys.argv[1]
tool_name = sys.argv[2]

with open(yaml_file, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

tools = {t.get('name'): t for t in data.get('tools', [])}

if tool_name not in tools:
    print(f"错误: 工具 '{tool_name}' 未找到")
    print("\n可用工具:")
    for name, tool in tools.items():
        print(f"  • {name} - {tool.get('display_name', name)}")
    sys.exit(1)

tool = tools[tool_name]
installed = subprocess.run(['which', tool_name], capture_output=True).returncode == 0

print(f"\n🔧 {tool.get('display_name', tool_name)} ({tool_name})")
print(f"\n📝 描述: {tool.get('description', '无')}")
print(f"\n📦 类别: {tool.get('category', 'other')}")
print(f"\n✅ 安装状态: {'已安装' if installed else '未安装'}")

if 'install' in tool:
    install = tool['install']
    print(f"\n📥 安装命令: {install.get('command', 'N/A')}")
    print(f"🔍 验证命令: {install.get('verify', 'N/A')}")
PYEOF
            ;;
        scan)
            echo "🔍 扫描已安装的 AI CLI 工具..."
            echo ""
            python3 - "${TOOLS_YAML}" << 'PYEOF'
import yaml
import sys
import subprocess
import os

yaml_file = sys.argv[1]

with open(yaml_file, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

tools = data.get('tools', [])
installed = []
not_installed = []

for tool in tools:
    name = tool.get('name', '')
    path = subprocess.run(['which', name], capture_output=True).returncode == 0
    if path:
        installed.append(name)
    else:
        not_installed.append(name)

print("✅ 已安装:")
for name in installed:
    print(f"  • {name}")

print(f"\n❌ 未安装 ({len(not_installed)}):")
for name in not_installed:
    print(f"  • {name}")

print(f"\n总计: {len(installed)}/{len(tools)} 已安装")
PYEOF
            ;;
        validate)
            echo "✅ 验证配置文件..."
            python3 - "${TOOLS_YAML}" << 'PYEOF'
import yaml
import sys

yaml_file = sys.argv[1]

with open(yaml_file, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

tools = data.get('tools', [])
errors = []

for i, tool in enumerate(tools):
    name = tool.get('name', '')
    if not name:
        errors.append(f"工具 #{i+1} 缺少 name 字段")
    if not tool.get('display_name'):
        errors.append(f"工具 '{name}' 缺少 display_name")

if not errors:
    print(f"✅ 配置文件验证通过！")
    print(f"   工具数量: {len(tools)}")
else:
    print("❌ 验证失败:")
    for e in errors:
        print(f"   • {e}")
    sys.exit(1)
PYEOF
            ;;
        history)
            echo "📜 使用历史 (前10条)"
            history_file="${CONFIG_DIR}/data/history.json"
            if [[ -f "$history_file" ]]; then
                python3 - "$history_file" << 'PYEOF'
import json
import sys

file = sys.argv[1]
with open(file, 'r') as f:
    data = json.load(f)

for item in data[-10:]:
    print(f"  • {item.get('task', 'N/A')} → {item.get('tool', 'N/A')}")
print(f"\n总计: {len(data)} 条记录")
PYEOF
            else
                echo "暂无历史记录"
            fi
            ;;
        stats)
            echo "📊 使用统计"
            stats_file="${CONFIG_DIR}/data/stats.json"
            if [[ -f "$stats_file" ]]; then
                python3 - "$stats_file" << 'PYEOF'
import json
import sys

file = sys.argv[1]
with open(file, 'r') as f:
    data = json.load(f)

if not data:
    print("暂无统计数据")
else:
    sorted_tools = sorted(data.items(), key=lambda x: -x[1])
    print("工具使用次数:")
    for tool, count in sorted_tools[:10]:
        print(f"  • {tool}: {count} 次")
PYEOF
            else
                echo "暂无统计数据"
            fi
            ;;
        *)
            error_exit "未知命令: $command"
            ;;
    esac
}

main "$@"
MAIN_SCRIPT

    chmod +x "${BIN_DIR}/ai-tools"
    success "主脚本已创建: ${BIN_DIR}/ai-tools"
}

create_alias() {
    if [[ "$NO_ALIAS" == "true" ]]; then
        warn "跳过创建别名"
        return 0
    fi

    info "创建 Shell 别名..."

    local shell_config
    local alias_line="alias ai-tools='${BIN_DIR}/ai-tools'"

    # 检测 Shell 类型
    if [[ "$HOME" == *"/root"* ]]; then
        shell_config="${HOME}/.bashrc"
    else
        shell_config="${HOME}/.zshrc"
    fi

    # 检查是否已存在
    if grep -q "ai-tools" "$shell_config" 2>/dev/null; then
        warn "别名已存在，请手动更新 ${shell_config}"
    else
        echo "" >> "$shell_config"
        echo "# AI CLI Tools Manager" >> "$shell_config"
        echo "$alias_line" >> "$shell_config"
        success "别名已添加到: $shell_config"
        info "请运行: source $shell_config"
    fi
}

print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║                    安装完成！                            ║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}安装位置:${NC}"
    echo "  • 主脚本: ${BIN_DIR}/ai-tools"
    echo "  • 配置目录: ${CONFIG_DIR}"
    echo ""
    echo -e "${BOLD}使用方式:${NC}"
    echo "  • 直接执行: ${BIN_DIR}/ai-tools list"
    echo "  • 使用别名: ai-tools list"
    echo ""
    echo -e "${BOLD}下一步:${NC}"
    if [[ "$NO_ALIAS" == "false" ]]; then
        echo "  source ${HOME}/.zshrc  # 或重启终端"
    fi
    echo "  ai-tools --help         # 查看帮助"
    echo ""
    echo -e "${BOLD}卸载方式:${NC}"
    echo "  ./uninstall.sh          # 运行卸载脚本"
    echo ""
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
    header

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)
                INSTALL_PREFIX="$2"
                BIN_DIR="${INSTALL_PREFIX}/bin"
                CONFIG_DIR="${INSTALL_PREFIX}/.config/ai-tools"
                shift 2
                ;;
            --no-alias)
                NO_ALIAS=true
                shift
                ;;
            --keep-data)
                KEEP_DATA=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "未知参数: $1"
                usage
                exit 1
                ;;
        esac
    done

    # 检查是否已安装
    if [[ -f "${BIN_DIR}/ai-tools" ]]; then
        if [[ "$FORCE" == "false" ]]; then
            warn "AI CLI Tools 已安装"
            info "使用 --force 强制重新安装"
            info "使用 --keep-data 保留数据"
            exit 0
        fi
    fi

    # 检查配置文件
    if [[ -f "${CONFIG_DIR}/config/tools.yaml" ]]; then
        if [[ "$KEEP_DATA" == "true" ]]; then
            info "保留现有数据（升级模式）"
        else
            warn "检测到现有配置，是否覆盖？"
            read -p "按 Enter 继续，或 Ctrl+C 取消..."
        fi
    fi

    # 执行安装
    check_dependencies
    create_directories
    install_core_modules
    create_main_script
    create_alias
    print_summary
}

main "$@"
