#!/bin/bash

#==============================================================================
# ProbeShell 监控组件管理脚本
# 支持组件: blackbox_exporter, node_exporter, vector
#==============================================================================

set -euo pipefail  # 严格模式：遇到错误立即退出

#==============================================================================
# 全局变量和配置
#==============================================================================

# 版本配置
readonly BLACKBOX_VERSION="0.28.0"
readonly NODE_VERSION="1.11.1"
readonly VECTOR_VERSION="0.56.0"

# 组件配置
readonly AVAILABLE_COMPONENTS=("blackbox" "node_exporter" "vector")
declare -a SELECTED_COMPONENTS=()

# 安装路径
readonly BLACKBOX_PATH="/usr/local/bin/blackbox"
readonly NODE_PATH="/usr/local/bin/node"
readonly VECTOR_PATH="/usr/local/bin/vector"

# 服务名称映射
declare -A SERVICE_MAP=(
    ["blackbox"]="blackbox"
    ["node_exporter"]="node_exporter"
    ["vector"]="vector"
)

# 安装路径映射
declare -A INSTALL_PATH_MAP=(
    ["blackbox"]="$BLACKBOX_PATH"
    ["node_exporter"]="$NODE_PATH"
    ["vector"]="$VECTOR_PATH"
)

# 操作模式
INSTALL=false
UNINSTALL=false
LIST=false
DRY_RUN=false

# 配置参数
MAIN_DOMAIN=""
INSTANCE_NAME=""
METRICS_BEARER_TOKEN=""
LOGS_BEARER_TOKEN=""
DELETE_LOGS="n"
BLACKBOX_TARGETS=""
CACHE_SIZE="512MiB"
CACHE_SIZE_SET=false  # 标记是否显式设置了 cache-size

# 系统信息
ARCH=""
ARCH_SUFFIX=""
VECTOR_ARCH_SUFFIX=""

# 临时文件列表（用于清理）
declare -a TEMP_FILES=()

#==============================================================================
# 颜色和样式
#==============================================================================

# 基础颜色
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# 样式
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'

# 组合颜色
readonly BRIGHT_GREEN='\033[1;32m'
readonly BRIGHT_BLUE='\033[1;34m'
readonly BRIGHT_CYAN='\033[1;36m'
readonly BRIGHT_YELLOW='\033[1;33m'

#==============================================================================
# 工具函数
#==============================================================================

# 打印消息
log_info() {
    echo -e "${BRIGHT_BLUE}ℹ ${NC}${BLUE}$*${NC}"
}

log_success() {
    echo -e "${BRIGHT_GREEN}✓${NC} ${GREEN}$*${NC}"
}

log_warn() {
    echo -e "${BRIGHT_YELLOW}⚠${NC} ${YELLOW}$*${NC}"
}

log_error() {
    echo -e "${RED}✗${NC} ${RED}${BOLD}$*${NC}" >&2
}

# 打印分隔线
print_separator() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 打印标题
print_header() {
    echo ""
    echo -e "${BRIGHT_CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    printf "${BRIGHT_CYAN}║${NC} ${BOLD}${WHITE}%-60s${NC} ${BRIGHT_CYAN}║${NC}\n" "$1"
    echo -e "${BRIGHT_CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 打印子标题
print_subheader() {
    echo ""
    echo -e "${CYAN}┌─ ${BOLD}$1${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────${NC}"
}

# 打印信息框
print_box() {
    local message="$1"
    local color="${2:-$CYAN}"
    echo ""
    echo -e "${color}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    printf "${color}┃${NC} %-60s ${color}┃${NC}\n" "$message"
    echo -e "${color}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
    echo ""
}

# 美化的输入提示
prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local result

    if [ -n "$default_value" ]; then
        echo -e "${CYAN}▸${NC} ${BOLD}${prompt_text}${NC} ${DIM}(默认: ${default_value})${NC}"
    else
        echo -e "${CYAN}▸${NC} ${BOLD}${prompt_text}${NC}"
    fi
    echo -ne "${BRIGHT_CYAN}  ➜ ${NC}"
    read -r result
    echo "$result"
}

# 打印欢迎横幅
print_banner() {
    clear
    echo ""
    echo -e "${BRIGHT_CYAN}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║                                                           ║"
    echo "  ║         ██████╗ ██████╗  ██████╗ ██████╗ ███████╗         ║"
    echo "  ║         ██╔══██╗██╔══██╗██╔═══██╗██╔══██╗██╔════╝         ║"
    echo "  ║         ██████╔╝██████╔╝██║   ██║██████╔╝█████╗           ║"
    echo "  ║         ██╔═══╝ ██╔══██╗██║   ██║██╔══██╗██╔══╝           ║"
    echo "  ║         ██║     ██║  ██║╚██████╔╝██████╔╝███████╗         ║"
    echo "  ║         ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝         ║"
    echo "  ║                                                           ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${DIM}  版本信息:${NC}"
    echo -e "  ${CYAN}•${NC} Blackbox Exporter: ${GREEN}v${BLACKBOX_VERSION}${NC}"
    echo -e "  ${CYAN}•${NC} Node Exporter:     ${GREEN}v${NODE_VERSION}${NC}"
    echo -e "  ${CYAN}•${NC} Vector:           ${GREEN}v${VECTOR_VERSION}${NC}"
    echo ""
    print_separator
    echo ""
}

# 错误处理和清理
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "脚本执行失败，退出码: $exit_code"
    fi

    # 清理临时文件
    for temp_file in "${TEMP_FILES[@]}"; do
        if [ -f "$temp_file" ]; then
            rm -f "$temp_file" 2>/dev/null || true
        fi
    done
}

trap cleanup EXIT

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 确认操作
confirm() {
    local prompt="$1"
    local response
    read -p "$prompt [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

#==============================================================================
# 系统检测和验证
#==============================================================================

# 获取系统架构
detect_architecture() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            ARCH_SUFFIX="linux-amd64"
            VECTOR_ARCH_SUFFIX="x86_64-unknown-linux-musl"
            ;;
        aarch64)
            ARCH_SUFFIX="linux-arm64"
            VECTOR_ARCH_SUFFIX="aarch64-unknown-linux-musl"
            ;;
        *)
            log_error "不支持的架构: $ARCH"
            log_error "仅支持 x86_64 和 aarch64"
            exit 1
            ;;
    esac
    log_info "检测到系统架构: $ARCH ($ARCH_SUFFIX)"
}

# 检查系统依赖
check_system_dependencies() {
    log_info "检查系统依赖..."

    local missing_deps=()
    local required_commands=("wget" "curl" "tar" "systemctl")

    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "缺少以下依赖: ${missing_deps[*]}"
        return 1
    fi

    log_success "系统依赖检查通过"
    return 0
}

# 安装系统依赖
install_system_dependencies() {
    print_header "安装系统依赖"

    if check_system_dependencies; then
        log_info "系统依赖已满足，跳过安装"
        return 0
    fi

    log_info "更新软件包列表..."
    apt update || {
        log_error "apt update 失败"
        return 1
    }

    log_info "安装依赖包..."
    apt install -y ntpsec-ntpdate wget curl || {
        log_error "依赖包安装失败"
        return 1
    }

    log_info "配置时区和时间同步..."
    timedatectl set-timezone Asia/Shanghai || log_warn "设置时区失败"
    ntpdate ntp.aliyun.com || log_warn "时间同步失败"

    # 添加定时任务
    local cron_job="0 3 * * * /usr/sbin/ntpdate ntp.aliyun.com > /dev/null 2>&1"
    if ! crontab -l 2>/dev/null | grep -Fxq "$cron_job"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab - || log_warn "添加 cron 任务失败"
    fi

    log_success "系统依赖安装完成"
}

#==============================================================================
# 组件状态检测
#==============================================================================

# 检查组件是否已安装
is_component_installed() {
    local component="$1"
    local install_path="${INSTALL_PATH_MAP[$component]}"

    if [ -d "$install_path" ] && [ -f "/etc/systemd/system/${SERVICE_MAP[$component]}.service" ]; then
        return 0
    fi
    return 1
}

# 检查服务是否运行
is_service_running() {
    local service="$1"
    systemctl is-active --quiet "$service" 2>/dev/null
}

# 检查服务是否启用
is_service_enabled() {
    local service="$1"
    systemctl is-enabled --quiet "$service" 2>/dev/null
}

# 获取已安装的组件列表
get_installed_components() {
    local -a installed=()
    for component in "${AVAILABLE_COMPONENTS[@]}"; do
        if is_component_installed "$component"; then
            installed+=("$component")
        fi
    done
    echo "${installed[@]}"
}

# 显示组件状态
show_component_status() {
    local has_installed=false

    # 组件名称映射（用于更好的显示）
    declare -A COMPONENT_NAMES=(
        ["blackbox"]="Blackbox Exporter"
        ["node_exporter"]="Node Exporter"
        ["vector"]="Vector"
    )

    for component in "${AVAILABLE_COMPONENTS[@]}"; do
        local service="${SERVICE_MAP[$component]}"
        local status="未安装"
        local status_icon="○"
        local color="$DIM"
        local display_name="${COMPONENT_NAMES[$component]}"

        if is_component_installed "$component"; then
            has_installed=true
            if is_service_running "$service"; then
                status="运行中"
                status_icon="●"
                color="$BRIGHT_GREEN"
            elif is_service_enabled "$service"; then
                status="已停止"
                status_icon="◐"
                color="$YELLOW"
            else
                status="未启用"
                status_icon="○"
                color="$YELLOW"
            fi
        fi

        printf "  ${color}${status_icon}${NC} ${CYAN}%-25s${NC} ${color}%-12s${NC}\n" "$display_name" "$status"
    done

    if ! $has_installed; then
        echo ""
        log_info "没有已安装的组件"
    fi

    echo ""
}

#==============================================================================
# 组件选择和验证
#==============================================================================

# 验证组件名称
validate_component() {
    local component="$1"
    for valid_component in "${AVAILABLE_COMPONENTS[@]}"; do
        if [ "$component" == "$valid_component" ]; then
            return 0
        fi
    done
    return 1
}

# 验证所有选中的组件
validate_selected_components() {
    for component in "${SELECTED_COMPONENTS[@]}"; do
        if ! validate_component "$component"; then
            log_error "无效的组件名称: $component"
            log_error "可用组件: ${AVAILABLE_COMPONENTS[*]}"
            exit 1
        fi
    done
}

# 检查组件是否被选中
is_component_selected() {
    local component="$1"

    # 如果没有选中任何组件，则全部选中
    if [ ${#SELECTED_COMPONENTS[@]} -eq 0 ]; then
        return 0
    fi

    for selected in "${SELECTED_COMPONENTS[@]}"; do
        if [ "$selected" == "$component" ]; then
            return 0
        fi
    done
    return 1
}

# 交互式选择组件
select_components_interactive() {
    local mode="$1"  # "install" 或 "uninstall"

    local mode_text="安装"
    local mode_action="安装"
    local mode_icon="📦"

    if [ "$mode" == "uninstall" ]; then
        mode_text="卸载"
        mode_action="卸载"
        mode_icon="🗑️"
    fi

    print_header "${mode_icon} 选择要${mode_text}的组件"

    # 如果是卸载模式，显示已安装的组件
    if [ "$mode" == "uninstall" ]; then
        local installed_components=($(get_installed_components))
        if [ ${#installed_components[@]} -eq 0 ]; then
            log_warn "没有已安装的组件"
            exit 0
        fi
        log_info "已安装的组件: ${installed_components[*]}"
        echo ""
    fi

    echo -e "${BOLD}${WHITE}可用组件列表:${NC}"
    echo ""
    echo -e "  ${BRIGHT_CYAN}1)${NC} ${CYAN}blackbox_exporter${NC}  ${DIM}- HTTP/TCP 探测${NC}"
    echo -e "  ${BRIGHT_CYAN}2)${NC} ${CYAN}node_exporter${NC}      ${DIM}- 系统监控${NC}"
    echo -e "  ${BRIGHT_CYAN}3)${NC} ${CYAN}vector${NC}             ${DIM}- 指标和日志收集代理${NC}"
    echo -e "  ${BRIGHT_GREEN}4)${NC} ${GREEN}全部${mode_action}${NC}"
    echo ""
    print_separator
    echo ""
    echo -e "${CYAN}▸${NC} 输入组件编号，用空格分隔 ${DIM}(例如: 1 2 3)${NC}"
    echo -ne "${BRIGHT_CYAN}  ➜ ${NC}"
    read -r choices

    SELECTED_COMPONENTS=()

    for choice in $choices; do
        case $choice in
            1) SELECTED_COMPONENTS+=("blackbox") ;;
            2) SELECTED_COMPONENTS+=("node_exporter") ;;
            3) SELECTED_COMPONENTS+=("vector") ;;
            4) SELECTED_COMPONENTS=("${AVAILABLE_COMPONENTS[@]}"); break ;;
            *)
                log_error "无效选项: $choice"
                exit 1
                ;;
        esac
    done

    if [ ${#SELECTED_COMPONENTS[@]} -eq 0 ]; then
        log_error "至少选择一个组件"
        exit 1
    fi

    echo ""
    log_info "已选择组件: ${SELECTED_COMPONENTS[*]}"
    echo ""
}

#==============================================================================
# 配置验证
#==============================================================================

# 验证 Vector 配置
validate_vector_config() {
    local errors=()

    if [ -z "$MAIN_DOMAIN" ]; then
        errors+=("vmauth 地址不能为空")
    fi

    if [ -z "$INSTANCE_NAME" ]; then
        errors+=("实例名称不能为空")
    fi

    if [ -z "$METRICS_BEARER_TOKEN" ]; then
        errors+=("VictoriaMetrics bearer token 不能为空")
    fi

    if [ -z "$LOGS_BEARER_TOKEN" ]; then
        errors+=("VictoriaLogs bearer token 不能为空")
    fi

    # 验证缓存大小格式
    if ! [[ "$CACHE_SIZE" =~ ^[0-9]+(KB|MB|GB|TB|KiB|MiB|GiB|TiB)$ ]]; then
        errors+=("缓存大小格式无效，应为如: 512MiB, 1GB, 2GB")
    fi

    if [ ${#errors[@]} -gt 0 ]; then
        log_error "Vector 配置验证失败:"
        for error in "${errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    return 0
}

#==============================================================================
# 下载和文件处理
#==============================================================================

# 安全下载文件
safe_download() {
    local url="$1"
    local output="$2"
    local description="${3:-文件}"

    log_info "下载 $description..."
    log_info "URL: $url"

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过下载: $output"
        return 0
    fi

    # 如果文件已存在，先备份
    if [ -f "$output" ]; then
        local backup="${output}.bak.$$"
        mv "$output" "$backup"
        TEMP_FILES+=("$backup")
    fi

    # 使用 wget 下载，显示进度，最多重试 3 次
    if ! wget --progress=bar:force -t 3 -T 30 -O "$output" "$url" 2>&1; then
        log_error "下载失败: $description"
        return 1
    fi

    # 验证文件是否下载成功
    if [ ! -f "$output" ] || [ ! -s "$output" ]; then
        log_error "下载的文件无效: $output"
        return 1
    fi

    log_success "下载完成: $description"
    return 0
}

# 解压 tar.gz 文件
extract_tarball() {
    local archive="$1"
    local description="${2:-压缩包}"

    log_info "解压 $description..."

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过解压: $archive"
        return 0
    fi

    if ! tar -zxf "$archive"; then
        log_error "解压失败: $archive"
        return 1
    fi

    log_success "解压完成: $description"
    TEMP_FILES+=("$archive")  # 标记为待删除
    return 0
}

#==============================================================================
# Blackbox Exporter 安装
#==============================================================================

install_blackbox() {
    print_header "安装 blackbox_exporter"

    if is_component_installed "blackbox" && ! $DRY_RUN; then
        log_warn "blackbox_exporter 已安装"
        if ! confirm "是否重新安装?"; then
            return 0
        fi
        uninstall_component "blackbox"
    fi

    local archive="blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz"
    local url="https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_VERSION}/${archive}"

    safe_download "$url" "$archive" "blackbox_exporter" || return 1
    extract_tarball "$archive" "blackbox_exporter" || return 1

    local extracted_dir="blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}"

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过移动文件到 $BLACKBOX_PATH"
    else
        if [ ! -d "$extracted_dir" ]; then
            log_error "解压目录不存在: $extracted_dir"
            return 1
        fi

        rm -rf "$BLACKBOX_PATH"
        mv "$extracted_dir" "$BLACKBOX_PATH" || return 1
        TEMP_FILES+=("$extracted_dir")
    fi

    # 下载配置文件
    safe_download \
        "https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/blackbox/blackbox.yml" \
        "${BLACKBOX_PATH}/blackbox.yml" \
        "blackbox 配置文件" || return 1

    # 下载服务文件
    safe_download \
        "https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/blackbox.service" \
        "/etc/systemd/system/blackbox.service" \
        "blackbox 服务文件" || return 1

    if ! $DRY_RUN; then
        chmod 644 /etc/systemd/system/blackbox.service
    fi

    log_success "blackbox_exporter 安装完成"
    return 0
}

#==============================================================================
# Node Exporter 安装
#==============================================================================

install_node_exporter() {
    print_header "安装 node_exporter"

    if is_component_installed "node_exporter" && ! $DRY_RUN; then
        log_warn "node_exporter 已安装"
        if ! confirm "是否重新安装?"; then
            return 0
        fi
        uninstall_component "node_exporter"
    fi

    local archive="node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz"
    local url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/${archive}"

    safe_download "$url" "$archive" "node_exporter" || return 1
    extract_tarball "$archive" "node_exporter" || return 1

    local extracted_dir="node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}"

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过移动文件到 $NODE_PATH"
    else
        if [ ! -d "$extracted_dir" ]; then
            log_error "解压目录不存在: $extracted_dir"
            return 1
        fi

        rm -rf "$NODE_PATH"
        mv "$extracted_dir" "$NODE_PATH" || return 1
        TEMP_FILES+=("$extracted_dir")
    fi

    # 下载服务文件
    safe_download \
        "https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/node_exporter.service" \
        "/etc/systemd/system/node_exporter.service" \
        "node_exporter 服务文件" || return 1

    if ! $DRY_RUN; then
        chmod 644 /etc/systemd/system/node_exporter.service
    fi

    log_success "node_exporter 安装完成"
    return 0
}

#==============================================================================
# Vector 安装
#==============================================================================

urlencode() {
    local string="${1}"
    local length="${#string}"
    local encoded=""
    local pos char hex

    for ((pos = 0; pos < length; pos++)); do
        char="${string:$pos:1}"
        case "$char" in
            [a-zA-Z0-9.~_-])
                encoded+="$char"
                ;;
            *)
                printf -v hex '%%%02X' "'$char"
                encoded+="$hex"
                ;;
        esac
    done

    echo "$encoded"
}

cache_size_to_bytes() {
    local size="$1"
    local number unit multiplier

    number="${size//[!0-9]/}"
    unit="${size//$number/}"

    case "$unit" in
        KB) multiplier=1000 ;;
        MB) multiplier=1000000 ;;
        GB) multiplier=1000000000 ;;
        TB) multiplier=1000000000000 ;;
        KiB) multiplier=1024 ;;
        MiB) multiplier=1048576 ;;
        GiB) multiplier=1073741824 ;;
        TiB) multiplier=1099511627776 ;;
        *) return 1 ;;
    esac

    echo $((number * multiplier))
}

# 生成 blackbox 探测目标配置
generate_blackbox_targets() {
    local endpoint_file="${VECTOR_PATH}/endpoint.yml"

    if [ -n "$BLACKBOX_TARGETS" ]; then
        log_info "配置自定义 blackbox 探测目标..."

        if $DRY_RUN; then
            log_info "[DRY RUN] 跳过生成探测目标配置"
            return 0
        fi

        mkdir -p "$VECTOR_PATH"

        cat > "$endpoint_file" << 'EOF'
# Blackbox Exporter Targets - Auto Generated
# Format: Prometheus file_sd_configs

EOF

        IFS=',' read -ra TARGET_ARRAY <<< "$BLACKBOX_TARGETS"

        for target in "${TARGET_ARRAY[@]}"; do
            target=$(echo "$target" | xargs)
            local label
            label=$(echo "$target" | sed -E 's|https?://||' | sed 's|/.*||' | sed 's|:.*||')

            cat >> "$endpoint_file" << EOF
- targets:
    - "$target"
  labels:
    endpoint: "$label"

EOF
        done

        log_success "已生成探测目标配置: $endpoint_file"
        log_info "配置了 ${#TARGET_ARRAY[@]} 个探测目标"
    else
        if $DRY_RUN; then
            log_info "[DRY RUN] 跳过下载默认探测目标配置"
            return 0
        fi

        mkdir -p "$VECTOR_PATH"

        if [ ! -f "$endpoint_file" ] || confirm "探测目标配置已存在，是否覆盖?"; then
            safe_download \
                "https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/vector/endpoint.yml" \
                "$endpoint_file" \
                "默认探测目标配置" || return 1
        fi
    fi

    return 0
}

get_vector_config() {
    if [ -z "$MAIN_DOMAIN" ]; then
        read -p "请输入 vmauth 地址: " MAIN_DOMAIN
    fi

    if [ -z "$INSTANCE_NAME" ]; then
        read -p "请输入VPS名称(如: GreenCloud.JP.6666): " INSTANCE_NAME
    fi

    if [ -z "$METRICS_BEARER_TOKEN" ]; then
        read -sp "请输入 VictoriaMetrics bearer token: " METRICS_BEARER_TOKEN
        echo ""
    fi

    if [ -z "$LOGS_BEARER_TOKEN" ]; then
        read -sp "请输入 VictoriaLogs bearer token: " LOGS_BEARER_TOKEN
        echo ""
    fi

    if [ "$CACHE_SIZE_SET" = false ]; then
        echo ""
        log_info "Vector 离线缓存设置（每个 sink 的本地磁盘缓存）"
        read -p "请输入缓存大小 (默认: 512MiB, 示例: 1GB, 2GB): " user_cache_size
        if [ -n "$user_cache_size" ]; then
            CACHE_SIZE="$user_cache_size"
        fi
    fi

    validate_vector_config || exit 1
}

generate_vector_config() {
    local config_file="${VECTOR_PATH}/vector.yaml"
    local endpoint_file="${VECTOR_PATH}/endpoint.yml"
    local metrics_url="${MAIN_DOMAIN%/}/api/v1/write"
    local logs_url="${MAIN_DOMAIN%/}/insert/jsonline?_stream_fields=instance,job,file&_msg_field=message&_time_field=timestamp"
    local buffer_bytes
    local blackbox_transform_inputs=""

    buffer_bytes=$(cache_size_to_bytes "$CACHE_SIZE") || return 1

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过生成 Vector 配置"
        return 0
    fi

    mkdir -p "$VECTOR_PATH" /var/lib/vector

    cat > "$config_file" << EOF
data_dir: /var/lib/vector

sources:
  node_exporter:
    type: prometheus_scrape
    endpoints:
      - http://127.0.0.1:9100/metrics
    scrape_interval_secs: 15
    scrape_timeout_secs: 5
EOF

    local line trimmed target="" label="" encoded_target index=0
    while IFS= read -r line; do
        trimmed=$(echo "$line" | xargs)

        if [[ "$trimmed" == "- "* ]] && [[ "$trimmed" != "- targets:" ]]; then
            target="${trimmed#- }"
            continue
        fi

        if [[ "$trimmed" == endpoint:* ]]; then
            label="${trimmed#endpoint: }"

            if [ -n "$target" ]; then
                encoded_target=$(urlencode "$target")
                cat >> "$config_file" << EOF

  blackbox_${index}:
    type: prometheus_scrape
    endpoints:
      - http://127.0.0.1:9115/probe?module=tcping&target=${encoded_target}
    scrape_interval_secs: 15
    scrape_timeout_secs: 5
EOF

                blackbox_transform_inputs+="      - blackbox_${index}_labels"$'\n'
                index=$((index + 1))
            fi

            target=""
            label=""
        fi
    done < "$endpoint_file"

    if [ "$index" -eq 0 ]; then
        log_warn "未从 $endpoint_file 解析到 blackbox 探测目标，Vector 将只采集 node_exporter 和日志"
    fi

    cat >> "$config_file" << EOF

  system_logs:
    type: file
    include:
      - /var/log/syslog
      - /var/log/auth.log
      - /var/log/kern.log
      - /var/log/cron.log
      - /var/log/user.log
      - /var/log/fail2ban.log
    ignore_not_found: true
    read_from: end

transforms:
  node_labels:
    type: remap
    inputs:
      - node_exporter
    source: |-
      .tags.instance = "${INSTANCE_NAME}"
      .tags.job = "node"

EOF

    target=""
    label=""
    index=0
    while IFS= read -r line; do
        trimmed=$(echo "$line" | xargs)

        if [[ "$trimmed" == "- "* ]] && [[ "$trimmed" != "- targets:" ]]; then
            target="${trimmed#- }"
            continue
        fi

        if [[ "$trimmed" == endpoint:* ]]; then
            label="${trimmed#endpoint: }"

            if [ -n "$target" ]; then
                cat >> "$config_file" << EOF
  blackbox_${index}_labels:
    type: remap
    inputs:
      - blackbox_${index}
    source: |-
      .tags.instance = "${INSTANCE_NAME}"
      .tags.job = "blackbox"
      .tags.endpoint = "${label}"
      .tags.target = "${target}"

EOF
                index=$((index + 1))
            fi

            target=""
            label=""
        fi
    done < "$endpoint_file"

    cat >> "$config_file" << EOF
  log_labels:
    type: remap
    inputs:
      - system_logs
    source: |-
      .instance = "${INSTANCE_NAME}"
      .timestamp = now()
      if .file == "/var/log/syslog" {
        .job = "syslog"
      } else if .file == "/var/log/auth.log" {
        .job = "auth"
      } else if .file == "/var/log/kern.log" {
        .job = "kern"
      } else if .file == "/var/log/cron.log" {
        .job = "cron"
      } else if .file == "/var/log/user.log" {
        .job = "user"
      } else if .file == "/var/log/fail2ban.log" {
        .job = "fail2ban"
      } else {
        .job = "system"
      }

sinks:
  metrics_remote_write:
    type: prometheus_remote_write
    inputs:
      - node_labels
${blackbox_transform_inputs}
    endpoint: ${metrics_url}
    auth:
      strategy: bearer
      token: "${METRICS_BEARER_TOKEN}"
    healthcheck:
      enabled: false
    buffer:
      type: disk
      max_size: ${buffer_bytes}
      when_full: block

  victorialogs:
    type: http
    inputs:
      - log_labels
    uri: "${logs_url}"
    method: post
    auth:
      strategy: bearer
      token: "${LOGS_BEARER_TOKEN}"
    encoding:
      codec: json
    framing:
      method: newline_delimited
    compression: gzip
    healthcheck:
      enabled: false
    buffer:
      type: disk
      max_size: ${buffer_bytes}
      when_full: block
EOF

    log_success "已生成 Vector 配置: $config_file"
}

uninstall_legacy_component() {
    local component="$1"
    local service="$2"
    local install_path="$3"

    if [ ! -d "$install_path" ] && [ ! -f "/etc/systemd/system/${service}.service" ]; then
        return 0
    fi

    log_info "清理旧组件 $component..."

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过清理旧组件: $component"
        return 0
    fi

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        systemctl stop "$service" || log_warn "停止 $service 失败"
    fi

    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        systemctl disable "$service" || log_warn "禁用 $service 失败"
    fi

    rm -f "/etc/systemd/system/${service}.service" || log_warn "删除服务文件失败: ${service}.service"
    rm -rf "$install_path" || log_warn "删除安装目录失败: $install_path"

    log_success "旧组件 $component 已清理"
}

install_vector() {
    print_header "安装 Vector"

    if is_component_installed "vector" && ! $DRY_RUN; then
        log_warn "Vector 已安装"
        if ! confirm "是否重新安装?"; then
            return 0
        fi
        uninstall_component "vector"
    fi

    get_vector_config

    local archive="vector-${VECTOR_VERSION}-${VECTOR_ARCH_SUFFIX}.tar.gz"
    local url="https://packages.timber.io/vector/${VECTOR_VERSION}/${archive}"

    safe_download "$url" "$archive" "Vector" || return 1
    extract_tarball "$archive" "Vector" || return 1

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过安装 Vector 二进制"
    else
        local vector_binary=""

        if [ -f "vector-${VECTOR_ARCH_SUFFIX}/bin/vector" ]; then
            vector_binary="vector-${VECTOR_ARCH_SUFFIX}/bin/vector"
        elif [ -f "vector-${VECTOR_VERSION}-${VECTOR_ARCH_SUFFIX}/bin/vector" ]; then
            vector_binary="vector-${VECTOR_VERSION}-${VECTOR_ARCH_SUFFIX}/bin/vector"
        else
            vector_binary=$(find . -maxdepth 3 -path "*/bin/vector" -type f | head -n 1)
        fi

        if [ -z "$vector_binary" ]; then
            log_error "未找到 Vector 二进制文件"
            return 1
        fi

        mkdir -p "$VECTOR_PATH"
        mv "$vector_binary" "${VECTOR_PATH}/vector" || return 1
        chmod +x "${VECTOR_PATH}/vector"
        chown root:root "${VECTOR_PATH}/vector"
    fi

    generate_blackbox_targets || return 1
    generate_vector_config || return 1

    uninstall_legacy_component "vmagent" "vmagent" "/usr/local/bin/vmagent"
    uninstall_legacy_component "promtail" "promtail" "/usr/local/bin/promtail"

    if ! $DRY_RUN; then
        cat > /etc/systemd/system/vector.service << 'EOF'
[Unit]
Description=Vector
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vector/vector --config /usr/local/bin/vector/vector.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        chmod 644 /etc/systemd/system/vector.service
    else
        log_info "[DRY RUN] 跳过生成 Vector 服务文件"
    fi

    log_success "Vector 安装完成"
    return 0
}

#==============================================================================
# 组件启动和停止
#==============================================================================

# 启动组件服务
start_component() {
    local component="$1"
    local service="${SERVICE_MAP[$component]}"

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过启动服务: $service"
        return 0
    fi

    log_info "启动 $service..."

    systemctl daemon-reload || {
        log_error "systemctl daemon-reload 失败"
        return 1
    }

    if ! systemctl start "$service"; then
        log_error "$service 启动失败"
        systemctl status "$service" --no-pager -l || true
        return 1
    fi

    if ! systemctl enable "$service"; then
        log_warn "$service 设置开机自启失败"
    fi

    # 等待服务启动
    sleep 2

    if is_service_running "$service"; then
        log_success "$service 已启动并设置开机自启"
    else
        log_error "$service 启动后未运行"
        systemctl status "$service" --no-pager -l || true
        return 1
    fi

    return 0
}

# 停止组件服务
stop_component() {
    local component="$1"
    local service="${SERVICE_MAP[$component]}"

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过停止服务: $service"
        return 0
    fi

    log_info "停止 $service..."

    if systemctl is-active --quiet "$service"; then
        systemctl stop "$service" || log_warn "停止 $service 失败"
    fi

    if systemctl is-enabled --quiet "$service"; then
        systemctl disable "$service" || log_warn "禁用 $service 失败"
    fi

    return 0
}

#==============================================================================
# 组件卸载
#==============================================================================

uninstall_component() {
    local component="$1"
    local service="${SERVICE_MAP[$component]}"
    local install_path="${INSTALL_PATH_MAP[$component]}"

    log_info "卸载 $component..."

    if $DRY_RUN; then
        log_info "[DRY RUN] 跳过卸载: $component"
        return 0
    fi

    # 停止并禁用服务
    stop_component "$component"

    # 删除服务文件
    local service_file="/etc/systemd/system/${service}.service"
    if [ -f "$service_file" ]; then
        rm -f "$service_file" || log_warn "删除服务文件失败: $service_file"
    fi

    # 删除安装目录
    if [ -d "$install_path" ]; then
        rm -rf "$install_path" || log_warn "删除安装目录失败: $install_path"
    fi

    systemctl daemon-reload || log_warn "systemctl daemon-reload 失败"

    log_success "$component 已卸载"
    return 0
}

#==============================================================================
# 主要流程
#==============================================================================

# 安装组件
install_components() {
    print_header "开始安装组件"
    log_info "安装列表: ${SELECTED_COMPONENTS[*]}"
    echo ""

    # 检测架构
    detect_architecture

    # 安装系统依赖
    install_system_dependencies || {
        log_error "系统依赖安装失败"
        exit 1
    }

    # 安装各个组件
    local failed_components=()

    for component in "${SELECTED_COMPONENTS[@]}"; do
        case "$component" in
            blackbox)
                install_blackbox || failed_components+=("blackbox")
                ;;
            node_exporter)
                install_node_exporter || failed_components+=("node_exporter")
                ;;
            vector)
                install_vector || failed_components+=("vector")
                ;;
        esac
    done

    # 检查是否有失败的组件
    if [ ${#failed_components[@]} -gt 0 ]; then
        log_error "以下组件安装失败: ${failed_components[*]}"
        log_warn "继续启动已成功安装的组件..."
    fi

    # 启动服务
    if ! $DRY_RUN; then
        print_header "启动服务"

        for component in "${SELECTED_COMPONENTS[@]}"; do
            # 跳过安装失败的组件
            if [[ " ${failed_components[*]} " =~ " ${component} " ]]; then
                continue
            fi

            start_component "$component" || log_warn "$component 启动失败"
        done
    fi

    # 显示最终状态
    echo ""
    show_component_status

    if [ ${#failed_components[@]} -eq 0 ]; then
        print_header "安装完成！"
        log_success "所有组件安装成功"
    else
        print_header "安装完成（部分失败）"
        log_error "失败的组件: ${failed_components[*]}"
        exit 1
    fi
}

# 卸载组件
uninstall_components() {
    print_header "开始卸载组件"
    log_info "卸载列表: ${SELECTED_COMPONENTS[*]}"
    echo ""

    # 确认操作
    if ! $DRY_RUN && ! confirm "确认要卸载选中的组件吗?"; then
        log_info "操作已取消"
        exit 0
    fi

    # 卸载各个组件
    for component in "${SELECTED_COMPONENTS[@]}"; do
        if is_component_installed "$component" || $DRY_RUN; then
            uninstall_component "$component"
        else
            log_warn "$component 未安装，跳过"
        fi
    done

    if ! $DRY_RUN; then
        systemctl daemon-reload
    fi

    # 处理日志删除
    if [ "$DELETE_LOGS" == "y" ]; then
        echo ""
        log_info "正在删除系统日志（保留最近1秒）..."

        if $DRY_RUN; then
            log_info "[DRY RUN] 跳过删除日志"
        else
            journalctl --vacuum-time=1s || log_warn "日志删除失败"
            log_success "日志删除完成"
        fi
    fi

    echo ""
    show_component_status

    print_header "卸载完成！"
}

#==============================================================================
# 参数解析
#==============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install)
                INSTALL=true
                shift
                ;;
            --uninstall)
                UNINSTALL=true
                shift
                ;;
            --list|--status)
                LIST=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --components)
                IFS=',' read -ra SELECTED_COMPONENTS <<< "$2"
                shift 2
                ;;
            --victoria|--vm)
                MAIN_DOMAIN="$2"
                shift 2
                ;;
            --name|--instance)
                INSTANCE_NAME="$2"
                shift 2
                ;;
            --metrics-token)
                METRICS_BEARER_TOKEN="$2"
                shift 2
                ;;
            --logs-token)
                LOGS_BEARER_TOKEN="$2"
                shift 2
                ;;
            --blackbox-targets)
                BLACKBOX_TARGETS="$2"
                shift 2
                ;;
            --cache-size)
                CACHE_SIZE="$2"
                CACHE_SIZE_SET=true
                shift 2
                ;;
            --delete-logs)
                DELETE_LOGS="y"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                echo "使用 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done
}

#==============================================================================
# 帮助信息
#==============================================================================

show_help() {
    cat << 'EOF'
ProbeShell 监控组件管理脚本 (重构版)

用法: ./agent.sh [选项]

操作选项:
  --install                   安装组件
  --uninstall                 卸载组件
  --list, --status            显示组件状态
  --help, -h                  显示此帮助信息

组件选项:
  --components <列表>         指定组件(逗号分隔)
                              可选: blackbox,node_exporter,vector
                              示例: --components blackbox,node_exporter

配置选项:
  --victoria, --vm <地址>     vmauth 地址
  --name, --instance <名称>   实例名称
  --metrics-token <token>     VictoriaMetrics bearer token
  --logs-token <token>        VictoriaLogs bearer token
  --blackbox-targets <列表>   Blackbox 探测目标(逗号分隔)
                              示例: --blackbox-targets http://google.com,https://baidu.com
  --cache-size <大小>         Vector 每个 sink 的磁盘缓存大小(默认: 512MiB)
                              示例: 1GB, 512MiB, 2GiB

其他选项:
  --delete-logs               卸载时删除日志(默认不删除)
  --dry-run                   试运行模式(不实际执行)

示例:
  # 显示组件状态
  ./agent.sh --status

  # 安装所有组件
  ./agent.sh --install --vm https://vmauth.example.com --name MyVPS \
             --metrics-token METRICS_TOKEN --logs-token LOGS_TOKEN

  # 只安装 node_exporter、blackbox 和 Vector
  ./agent.sh --install --components node_exporter,blackbox,vector \
             --vm https://vmauth.example.com --name MyVPS \
             --metrics-token METRICS_TOKEN --logs-token LOGS_TOKEN

  # 卸载所有组件并删除日志
  ./agent.sh --uninstall --delete-logs

  # 试运行模式（不实际执行）
  ./agent.sh --install --dry-run

EOF
}

#==============================================================================
# 主菜单
#==============================================================================

show_main_menu() {
    print_banner

    echo -e "${BOLD}${WHITE}📊 当前组件状态${NC}"
    echo ""
    show_component_status

    echo ""
    echo -e "${BOLD}${WHITE}🎯 请选择操作${NC}"
    echo ""
    echo -e "  ${BRIGHT_GREEN}1)${NC} ${CYAN}安装组件${NC}      ${DIM}(Install components)${NC}"
    echo -e "  ${BRIGHT_YELLOW}2)${NC} ${CYAN}卸载组件${NC}      ${DIM}(Uninstall components)${NC}"
    echo -e "  ${BRIGHT_BLUE}3)${NC} ${CYAN}显示状态${NC}      ${DIM}(Show status)${NC}"
    echo -e "  ${RED}4)${NC} ${CYAN}退出${NC}          ${DIM}(Exit)${NC}"
    echo ""
    print_separator
    echo ""

    echo -ne "${BRIGHT_CYAN}➜${NC} ${BOLD}输入你的选择 (1-4):${NC} "
    read -n 1 choice
    echo ""
    echo ""

    case $choice in
        1)
            INSTALL=true
            select_components_interactive "install"
            ;;
        2)
            UNINSTALL=true
            select_components_interactive "uninstall"
            ;;
        3)
            LIST=true
            ;;
        4)
            log_info "退出"
            exit 0
            ;;
        *)
            log_error "无效选项，请选择 1-4"
            exit 1
            ;;
    esac
}

#==============================================================================
# 主程序
#==============================================================================

main() {
    # 检查 root 权限
    check_root

    # 解析命令行参数
    parse_arguments "$@"

    # 如果只是查看状态
    if $LIST; then
        show_component_status
        exit 0
    fi

    # 如果没有指定操作，显示交互式菜单
    if ! $INSTALL && ! $UNINSTALL; then
        show_main_menu
    fi

    # 如果选择了组件，验证组件名称
    if [ ${#SELECTED_COMPONENTS[@]} -gt 0 ]; then
        validate_selected_components
    fi

    # 卸载模式下，如果没有指定组件，默认卸载所有组件
    if $UNINSTALL && [ ${#SELECTED_COMPONENTS[@]} -eq 0 ]; then
        log_info "未指定组件，将卸载所有已安装的组件"
        SELECTED_COMPONENTS=("${AVAILABLE_COMPONENTS[@]}")
    fi

    # 安装模式下，如果没有选择组件，进入交互式选择
    if $INSTALL && [ ${#SELECTED_COMPONENTS[@]} -eq 0 ]; then
        select_components_interactive "install"
    fi

    # 如果是试运行模式，显示提示
    if $DRY_RUN; then
        log_warn "=== 试运行模式 - 不会实际执行操作 ==="
        echo ""
    fi

    # 执行相应操作
    if $INSTALL; then
        install_components
    elif $UNINSTALL; then
        uninstall_components
    fi
}

# 运行主程序
main "$@"
