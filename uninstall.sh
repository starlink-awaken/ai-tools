#!/bin/bash
# ==============================================================================
# AI CLI Tools Manager - Uninstall Script
# ==============================================================================
# 一键卸载脚本 - 彻底移除 AI CLI 工具管理器
# Usage: ./uninstall.sh [--keep-data] [--backup]
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
readonly BACKUP_DIR="${CONFIG_DIR}/backups"

# 选项
KEEP_DATA=false
BACKUP=false
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
    echo -e "${BOLD}${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║     AI CLI Tools Manager v${VERSION} - 卸载程序             ║${NC}"
    echo -e "${BOLD}${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

usage() {
    cat << EOF
${BOLD}用法:${NC} ./uninstall.sh [选项]

${BOLD}选项:${NC}
  --keep-data   保留配置文件和数据
  --backup      卸载前备份数据到 Downloads 目录
  --force       强制执行，不询问确认
  -h, --help    显示帮助

${BOLD}示例:${NC}
  ./uninstall.sh              # 交互式卸载
  ./uninstall.sh --force      # 强制卸载
  ./uninstall.sh --keep-data  # 卸载但保留数据
  ./uninstall.sh --backup     # 备份后卸载

${BOLD}卸载内容:${NC}
  • 主脚本: ${BIN_DIR}/ai-tools
  • 核心模块: ${CONFIG_DIR}/core/
  • 配置目录: ${CONFIG_DIR}/
  • Shell 别名 (需要手动清理)
EOF
}

confirm_uninstall() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    echo ""
    echo -e "${BOLD}${YELLOW}⚠️  警告：此操作将删除以下内容:${NC}"
    echo ""
    echo "  • ${BIN_DIR}/ai-tools"
    echo "  • ${CONFIG_DIR}/core/"
    echo "  • ${CONFIG_DIR}/config/"
    echo "  • ${CONFIG_DIR}/data/"
    echo ""

    if [[ "$KEEP_DATA" == "false" ]]; then
        echo -e "${RED}所有数据和配置将被删除！${NC}"
    else
        echo -e "${GREEN}配置文件和数据将被保留。${NC}"
    fi
    echo ""

    read -p "确认卸载? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "已取消卸载"
        exit 0
    fi
}

backup_data() {
    if [[ "$BACKUP" == "false" ]]; then
        return 0
    fi

    info "创建备份..."

    local backup_file="${HOME}/Downloads/ai-tools-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    tar -czf "$backup_file" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>/dev/null || {
        warn "备份失败，继续卸载..."
        return 0
    }

    success "备份已保存到: $backup_file"
}

remove_bin() {
    info "删除主脚本..."

    if [[ -f "${BIN_DIR}/ai-tools" ]]; then
        rm -f "${BIN_DIR}/ai-tools"
        success "已删除: ${BIN_DIR}/ai-tools"
    else
        info "主脚本不存在，跳过"
    fi
}

remove_core_modules() {
    info "删除核心模块..."

    if [[ -d "${CONFIG_DIR}/core" ]]; then
        rm -rf "${CONFIG_DIR}/core"
        success "已删除: ${CONFIG_DIR}/core/"
    else
        info "核心模块目录不存在，跳过"
    fi
}

remove_config() {
    if [[ "$KEEP_DATA" == "true" ]]; then
        info "保留配置文件（--keep-data）"
        return 0
    fi

    info "删除配置和数据..."

    if [[ -d "${CONFIG_DIR}" ]]; then
        # 备份目录存在时排除
        if [[ -d "${BACKUP_DIR}" ]]; then
            rm -rf "${CONFIG_DIR:?}" --exclude="${BACKUP_DIR}"
        else
            rm -rf "${CONFIG_DIR}"
        fi
        success "已删除: ${CONFIG_DIR}"
    else
        info "配置目录不存在，跳过"
    fi
}

cleanup_alias() {
    info "清理 Shell 别名..."

    local cleaned=false
    local shell_configs=("${HOME}/.zshrc" "${HOME}/.bashrc" "${HOME}/.bash_profile")

    for config in "${shell_configs[@]}"; do
        if [[ -f "$config" ]]; then
            # 移除别名行
            if grep -q "ai-tools" "$config" 2>/dev/null; then
                # 创建临时文件
                local temp_file
                temp_file=$(mktemp)
                grep -v "ai-tools" "$config" > "$temp_file" 2>/dev/null || true
                grep -v "# AI CLI Tools Manager" "$temp_file" > "${temp_file}.clean" 2>/dev/null || true
                mv "${temp_file}.clean" "$config"
                success "已清理: $config"
                cleaned=true
            fi
        fi
    done

    if [[ "$cleaned" == "false" ]]; then
        info "未检测到别名，无需清理"
    else
        info "请运行: source ~/.zshrc 或重启终端"
    fi
}

print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║                    卸载完成！                            ║${NC}"
    echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}已删除:${NC}"
    echo "  • ${BIN_DIR}/ai-tools"
    echo "  • ${CONFIG_DIR}/core/"
    echo ""

    if [[ "$KEEP_DATA" == "false" ]]; then
        echo -e "${BOLD}已清空:${NC}"
        echo "  • ${CONFIG_DIR}/config/"
        echo "  • ${CONFIG_DIR}/data/"
    else
        echo -e "${BOLD}已保留:${NC}"
        echo "  • ${CONFIG_DIR}/config/"
        echo "  • ${CONFIG_DIR}/data/"
    fi
    echo ""
    echo -e "${BOLD}手动操作:${NC}"
    echo "  • 如有需要，请手动清理 Shell 配置文件中的别名"
    echo "  • 如需完全删除，删除目录: ${CONFIG_DIR}"
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
            --keep-data)
                KEEP_DATA=true
                shift
                ;;
            --backup)
                BACKUP=true
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

    # 确认卸载
    confirm_uninstall

    # 备份（如需要）
    backup_data

    # 执行卸载
    remove_bin
    remove_core_modules
    remove_config
    cleanup_alias
    print_summary
}

main "$@"
