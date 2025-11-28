#!/bin/bash

# 默认参数
INSTALL=false
UNINSTALL=false
MAIN_DOMAIN=""
LOKI_DOMAIN=""
INSTANCE_NAME=""
VM_USERNAME=""
VM_PASSWORD=""
DELETE_LOGS="n"
BLACKBOX_TARGETS=""
CACHE_SIZE="500M"  # vmagent 默认缓存大小

# 可用组件列表
AVAILABLE_COMPONENTS=("blackbox" "node_exporter" "vmagent" "promtail")
SELECTED_COMPONENTS=()

# 读取参数
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
        --components)
            IFS=',' read -ra SELECTED_COMPONENTS <<< "$2"
            shift 2
            ;;
        --victoria|--vm)
            MAIN_DOMAIN="$2"
            shift 2
            ;;
        --loki)
            LOKI_DOMAIN="$2"
            shift 2
            ;;
        --name|--instance)
            INSTANCE_NAME="$2"
            shift 2
            ;;
        --vm-user|--username)
            VM_USERNAME="$2"
            shift 2
            ;;
        --vm-pass|--password)
            VM_PASSWORD="$2"
            shift 2
            ;;
        --blackbox-targets)
            BLACKBOX_TARGETS="$2"
            shift 2
            ;;
        --cache-size)
            CACHE_SIZE="$2"
            shift 2
            ;;
        --delete-logs)
            DELETE_LOGS="y"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --install                   安装组件"
            echo "  --uninstall                 卸载组件"
            echo "  --components <list>         指定要安装的组件(逗号分隔)"
            echo "                              可选: blackbox,node_exporter,vmagent,promtail"
            echo "                              示例: --components blackbox,node_exporter"
            echo "  --victoria, --vm <url>      VictoriaMetrics写入地址"
            echo "  --loki <url>                Loki写入地址"
            echo "  --name, --instance <name>   VPS名称"
            echo "  --vm-user, --username       VictoriaMetrics用户名"
            echo "  --vm-pass, --password       VictoriaMetrics密码"
            echo "  --blackbox-targets <urls>   Blackbox探测目标(逗号分隔)"
            echo "                              示例: --blackbox-targets http://google.com,https://baidu.com"
            echo "  --cache-size <size>         vmagent离线缓存大小(默认: 500M)"
            echo "                              示例: 1G, 500M, 2G"
            echo "  --delete-logs               卸载时删除日志(默认不删除)"
            echo ""
            echo "示例:"
            echo "  # 安装所有组件"
            echo "  $0 --install --vm https://vm.example.com --loki https://loki.example.com --name MyVPS --vm-user admin --vm-pass secret"
            echo ""
            echo "  # 只安装 node_exporter 和 vmagent，自定义缓存大小"
            echo "  $0 --install --components node_exporter,vmagent --vm https://vm.example.com --name MyVPS --vm-user admin --vm-pass secret --cache-size 2G"
            echo ""
            echo "  # 安装blackbox并指定探测目标"
            echo "  $0 --install --components blackbox --blackbox-targets http://google.com,https://baidu.com"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

# 验证组件名称
validate_components() {
    for comp in "${SELECTED_COMPONENTS[@]}"; do
        if [[ ! " ${AVAILABLE_COMPONENTS[@]} " =~ " ${comp} " ]]; then
            echo "错误: 未知的组件 '$comp'"
            echo "可用组件: ${AVAILABLE_COMPONENTS[*]}"
            exit 1
        fi
    done
}

# 检查组件是否被选中
is_component_selected() {
    local component=$1
    # 如果没有指定组件，则全部安装
    if [ ${#SELECTED_COMPONENTS[@]} -eq 0 ]; then
        return 0
    fi
    for comp in "${SELECTED_COMPONENTS[@]}"; do
        if [ "$comp" == "$component" ]; then
            return 0
        fi
    done
    return 1
}

# 交互式选择组件
select_components_interactive() {
    echo "======================================"
    echo "请选择要安装的组件 (可多选):"
    echo "======================================"
    echo "1) blackbox_exporter  - HTTP/TCP探测"
    echo "2) node_exporter      - 系统监控"
    echo "3) vmagent            - 指标收集代理"
    echo "4) promtail           - 日志收集"
    echo "5) 全部安装"
    echo "======================================"
    echo "输入组件编号，用空格分隔 (如: 1 2 3) 或输入 5 安装全部:"
    read -p "> " choices

    SELECTED_COMPONENTS=()

    for choice in $choices; do
        case $choice in
            1) SELECTED_COMPONENTS+=("blackbox") ;;
            2) SELECTED_COMPONENTS+=("node_exporter") ;;
            3) SELECTED_COMPONENTS+=("vmagent") ;;
            4) SELECTED_COMPONENTS+=("promtail") ;;
            5) SELECTED_COMPONENTS=("${AVAILABLE_COMPONENTS[@]}"); break ;;
            *) echo "无效选项: $choice"; exit 1 ;;
        esac
    done

    if [ ${#SELECTED_COMPONENTS[@]} -eq 0 ]; then
        echo "错误: 至少选择一个组件"
        exit 1
    fi

    echo ""
    echo "已选择组件: ${SELECTED_COMPONENTS[*]}"
    echo ""
}

# 菜单
if ! $INSTALL && ! $UNINSTALL; then
    clear
    echo "======================================"
    echo "ProbeShell 监控组件管理脚本"
    echo "======================================"
    echo "请选择操作:"
    echo "1) 安装组件"
    echo "2) 卸载组件"
    echo "======================================"
    read -n 1 -p "输入你的选择 (1 或 2): " choice
    echo
    echo

    case $choice in
        1) INSTALL=true ;;
        2) UNINSTALL=true ;;
        *) echo "无效选项，请选择 1 或 2."; exit 1 ;;
    esac

    # 交互式选择组件
    select_components_interactive
fi

# 验证选择的组件
if [ ${#SELECTED_COMPONENTS[@]} -gt 0 ]; then
    validate_components
fi

# 检查组件依赖关系
check_component_dependencies() {
    local has_error=false

    # 如果是安装模式，检查依赖
    if $INSTALL; then
        # 检查 node_exporter 依赖
        if is_component_selected "node_exporter" && ! is_component_selected "vmagent"; then
            echo "⚠️  警告: node_exporter 依赖 vmagent 来采集和传输数据"
            echo "   建议同时安装 vmagent 组件"
            read -p "是否继续安装？(y/n): " continue_install
            if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
                echo "安装已取消"
                exit 0
            fi
        fi

        # 检查 blackbox 依赖
        if is_component_selected "blackbox" && ! is_component_selected "vmagent"; then
            echo "⚠️  警告: blackbox_exporter 依赖 vmagent 来采集和传输探测数据"
            echo "   建议同时安装 vmagent 组件"
            read -p "是否继续安装？(y/n): " continue_install
            if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
                echo "安装已取消"
                exit 0
            fi
        fi

        # 检查 vmagent 是否有配置
        if is_component_selected "vmagent"; then
            if [ -z "$MAIN_DOMAIN" ] && [ -z "$1" ]; then
                # 如果是交互式模式，稍后会提示输入，这里不检查
                :
            fi
        fi
    fi
}

# 获取系统架构
get_architecture() {
    ARCH=$(uname -m)
    if [ "$ARCH" == "x86_64" ]; then
        ARCH_SUFFIX="linux-amd64"
    elif [ "$ARCH" == "aarch64" ]; then
        ARCH_SUFFIX="linux-arm64"
    else
        echo "不支持的架构: $ARCH"
        exit 1
    fi
}

# 安装系统依赖
install_system_dependencies() {
    echo "======================================"
    echo "安装系统依赖..."
    echo "======================================"
    apt update
    apt install -y unzip ntpsec-ntpdate wget curl
    timedatectl set-timezone Asia/Shanghai
    ntpdate ntp.aliyun.com
    CRON_JOB="0 3 * * * /usr/sbin/ntpdate ntp.aliyun.com > /dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -Fxq "$CRON_JOB") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "系统依赖安装完成"
    echo ""
}

# 生成 blackbox 探测目标配置文件
generate_blackbox_targets() {
    local endpoint_file="/usr/local/bin/vmagent/endpoint.yml"

    # 确保目录存在
    mkdir -p /usr/local/bin/vmagent

    if [ -n "$BLACKBOX_TARGETS" ]; then
        echo "配置自定义 blackbox 探测目标..."
        # 生成 Prometheus file_sd_configs 格式的配置
        echo "# Blackbox Exporter Targets - Auto Generated" > "$endpoint_file"
        echo "# Format: Prometheus file_sd_configs" >> "$endpoint_file"
        echo "" >> "$endpoint_file"

        # 将逗号分隔的目标转换为数组
        IFS=',' read -ra TARGET_ARRAY <<< "$BLACKBOX_TARGETS"

        for target in "${TARGET_ARRAY[@]}"; do
            # 移除前后空格
            target=$(echo "$target" | xargs)

            # 提取域名作为标签（去掉协议和路径）
            label=$(echo "$target" | sed -E 's|https?://||' | sed 's|/.*||' | sed 's|:.*||')

            # 生成配置条目
            cat >> "$endpoint_file" << EOF
- targets:
    - "$target"
  labels:
    endpoint: "$label"

EOF
        done

        echo "✓ 已生成探测目标配置: $endpoint_file"
        echo "  配置了 ${#TARGET_ARRAY[@]} 个探测目标"
    else
        # 没有自定义目标，使用默认配置
        if [ ! -f "$endpoint_file" ]; then
            echo "下载默认探测目标配置..."
            wget -O "$endpoint_file" https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/vmagent/endpoint.yml
        fi
    fi
}

# 安装 blackbox_exporter
install_blackbox() {
    echo "======================================"
    echo "安装 blackbox_exporter..."
    echo "======================================"
    BLACKBOX_VERSION="0.27.0"
    wget https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_VERSION}/blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz
    tar -zxvf blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz
    rm blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz
    mv blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}/ /usr/local/bin/blackbox

    # 下载配置文件
    wget -O /usr/local/bin/blackbox/blackbox.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/blackbox/blackbox.yml

    # 下载服务文件
    wget -O /etc/systemd/system/blackbox.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/blackbox.service
    chmod 644 /etc/systemd/system/blackbox.service

    # 如果安装了blackbox但没有安装vmagent，提示用户
    if ! is_component_selected "vmagent"; then
        echo ""
        echo "注意: blackbox_exporter 已安装，但未安装 vmagent"
        echo "      探测目标需要通过 vmagent 配置才能生效"
        echo "      建议同时安装 vmagent 组件"
        echo ""
    fi

    echo "blackbox_exporter 安装完成"
    echo ""
}

# 安装 node_exporter
install_node_exporter() {
    echo "======================================"
    echo "安装 node_exporter..."
    echo "======================================"
    NODE_VERSION="1.9.1"
    wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz
    tar -zxvf node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz
    rm node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz
    mv node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}/ /usr/local/bin/node

    # 下载服务文件
    wget -O /etc/systemd/system/node_exporter.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/node_exporter.service
    chmod 644 /etc/systemd/system/node_exporter.service

    echo "node_exporter 安装完成"
    echo ""
}

# 安装 vmagent
install_vmagent() {
    echo "======================================"
    echo "安装 vmagent..."
    echo "======================================"
    VMAGENT_VERSION="1.128.0"
    wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${VMAGENT_VERSION}/vmutils-${ARCH_SUFFIX}-v${VMAGENT_VERSION}.tar.gz
    tar -zxvf vmutils-${ARCH_SUFFIX}-v${VMAGENT_VERSION}.tar.gz
    rm -rf vmalert-prod vmalert-tool-prod vmauth-prod vmbackup-prod vmctl-prod vmrestore-prod vmutils-${ARCH_SUFFIX}-v${VMAGENT_VERSION}.tar.gz
    mkdir -p /usr/local/bin/vmagent
    mv vmagent-prod /usr/local/bin/vmagent/vmagent
    chmod +x /usr/local/bin/vmagent/vmagent
    chown -v root:root /usr/local/bin/vmagent/vmagent

    # 获取配置参数
    if [ -z "$MAIN_DOMAIN" ]; then
        echo "VictoriaMetrics写入地址一般是<ip>:8428,如果有反代输入域名即可,写入的api会自动拼接"
        read -p "请输入 VictoriaMetrics 写入地址: " MAIN_DOMAIN
    fi
    if [ -z "$INSTANCE_NAME" ]; then
        read -p "请输入VPS名(比如GreenCloud.JP.6666): " INSTANCE_NAME
    fi
    if [ -z "$VM_USERNAME" ]; then
        read -p "请输入 VictoriaMetrics 的用户名: " VM_USERNAME
    fi
    if [ -z "$VM_PASSWORD" ]; then
        read -sp "请输入 VictoriaMetrics 的密码: " VM_PASSWORD
        echo
    fi

    # 询问缓存大小（仅在命令行未指定时）
    if [ "$CACHE_SIZE" == "500M" ]; then
        echo ""
        echo "vmagent 离线缓存设置（连接不上服务器时本地缓存数据）"
        read -p "请输入缓存大小 (默认: 500M, 示例: 1G, 2G): " user_cache_size
        if [ -n "$user_cache_size" ]; then
            CACHE_SIZE="$user_cache_size"
        fi
    fi

    # 验证参数
    if [[ -z "$MAIN_DOMAIN" || -z "$VM_USERNAME" || -z "$VM_PASSWORD" || -z "$INSTANCE_NAME" ]]; then
        echo "错误：VictoriaMetrics 相关参数不能为空！"
        exit 1
    fi

    # 拼接 VictoriaMetrics /api/v1/write 到主域名
    remote_write_url="${MAIN_DOMAIN}/api/v1/write"

    # 下载服务文件和配置文件
    wget -O /etc/systemd/system/vmagent.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/vmagent.service
    wget -O /usr/local/bin/vmagent/prometheus.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/vmagent/prometheus.yml

    # 生成或下载 blackbox 探测目标配置
    generate_blackbox_targets

    # 替换配置
    sed -i "s|-remoteWrite.url=.*|-remoteWrite.url=${remote_write_url}|g" /etc/systemd/system/vmagent.service
    sed -i -e "s/-remoteWrite.basicAuth.username=VM_USERNAME/-remoteWrite.basicAuth.username=${VM_USERNAME}/g" -e "s/-remoteWrite.basicAuth.password=VM_PASSWORD/-remoteWrite.basicAuth.password=${VM_PASSWORD}/g" /etc/systemd/system/vmagent.service
    sed -i "s/-remoteWrite.maxDiskUsagePerURL=CACHE_SIZE/-remoteWrite.maxDiskUsagePerURL=${CACHE_SIZE}/g" /etc/systemd/system/vmagent.service
    sed -i "s/\${instance_name}/${INSTANCE_NAME}/g" /usr/local/bin/vmagent/prometheus.yml

    chmod 644 /etc/systemd/system/vmagent.service

    echo "vmagent 安装完成"
    echo ""
}

# 安装 promtail
install_promtail() {
    echo "======================================"
    echo "安装 promtail..."
    echo "======================================"
    PROMTAIL_VERSION="3.5.7"
    wget https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-${ARCH_SUFFIX}.zip
    mkdir -p /usr/local/bin/promtail
    unzip promtail-${ARCH_SUFFIX}.zip
    mv promtail-${ARCH_SUFFIX} /usr/local/bin/promtail/promtail
    rm -rf promtail-${ARCH_SUFFIX}.zip
    chmod +x /usr/local/bin/promtail/promtail
    chown -v root:root /usr/local/bin/promtail/promtail

    # 获取配置参数
    if [ -z "$LOKI_DOMAIN" ]; then
        read -p "请输入 Loki 写入地址: " LOKI_DOMAIN
    fi
    if [ -z "$INSTANCE_NAME" ]; then
        read -p "请输入VPS名(比如GreenCloud.JP.6666): " INSTANCE_NAME
    fi
    if [ -z "$VM_USERNAME" ]; then
        read -p "请输入认证用户名: " VM_USERNAME
    fi
    if [ -z "$VM_PASSWORD" ]; then
        read -sp "请输入认证密码: " VM_PASSWORD
        echo
    fi

    # 验证参数
    if [[ -z "$LOKI_DOMAIN" || -z "$INSTANCE_NAME" ]]; then
        echo "错误: Loki 地址和实例名不能为空！"
        exit 1
    fi

    loki_push_url="${LOKI_DOMAIN}/loki/api/v1/push"

    # 下载服务文件和配置文件
    wget -O /etc/systemd/system/promtail.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/promtail.service
    wget -O /usr/local/bin/promtail/promtail.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/promtail/promtail.yml

    # 替换配置
    sed -i "s|instance: ''|instance: '${INSTANCE_NAME}'|g" /usr/local/bin/promtail/promtail.yml
    sed -i "s|url:|url: ${loki_push_url}|" /usr/local/bin/promtail/promtail.yml

    if [ -n "$VM_USERNAME" ] && [ -n "$VM_PASSWORD" ]; then
        sed -i "s|username:|username: ${VM_USERNAME}|" /usr/local/bin/promtail/promtail.yml
        sed -i "s|password:|password: ${VM_PASSWORD}|" /usr/local/bin/promtail/promtail.yml
    fi

    chmod 644 /etc/systemd/system/promtail.service

    echo "promtail 安装完成"
    echo ""
}

# 启动组件
start_component() {
    local component=$1
    local service_name=""

    case $component in
        blackbox) service_name="blackbox" ;;
        node_exporter) service_name="node_exporter" ;;
        vmagent) service_name="vmagent" ;;
        promtail) service_name="promtail" ;;
    esac

    if [ -n "$service_name" ]; then
        systemctl daemon-reload
        systemctl start $service_name
        systemctl enable $service_name
        echo "✓ $service_name 已启动并设置开机自启"
    fi
}

# 停止和卸载组件
uninstall_component() {
    local component=$1
    local service_name=""
    local install_path=""

    case $component in
        blackbox)
            service_name="blackbox"
            install_path="/usr/local/bin/blackbox"
            ;;
        node_exporter)
            service_name="node_exporter"
            install_path="/usr/local/bin/node"
            ;;
        vmagent)
            service_name="vmagent"
            install_path="/usr/local/bin/vmagent"
            ;;
        promtail)
            service_name="promtail"
            install_path="/usr/local/bin/promtail"
            ;;
    esac

    if [ -n "$service_name" ]; then
        echo "卸载 $service_name..."
        systemctl stop $service_name 2>/dev/null || true
        systemctl disable $service_name 2>/dev/null || true
        rm -f /etc/systemd/system/${service_name}.service
        rm -rf $install_path
        echo "✓ $service_name 已卸载"
    fi
}

# 主安装流程
install_components() {
    echo ""
    echo "======================================"
    echo "开始安装组件..."
    echo "======================================"
    echo "安装列表: ${SELECTED_COMPONENTS[*]}"
    echo "======================================"
    echo ""

    get_architecture
    install_system_dependencies

    for component in "${SELECTED_COMPONENTS[@]}"; do
        case $component in
            blackbox) install_blackbox ;;
            node_exporter) install_node_exporter ;;
            vmagent) install_vmagent ;;
            promtail) install_promtail ;;
        esac
    done

    # 如果安装了blackbox但没有安装vmagent，且指定了探测目标，仍然生成配置文件
    if is_component_selected "blackbox" && ! is_component_selected "vmagent" && [ -n "$BLACKBOX_TARGETS" ]; then
        echo ""
        echo "======================================"
        echo "配置 blackbox 探测目标..."
        echo "======================================"
        generate_blackbox_targets
        echo "注意: 探测目标已配置，但需要安装 vmagent 才能采集数据"
        echo ""
    fi

    echo "======================================"
    echo "启动服务..."
    echo "======================================"
    for component in "${SELECTED_COMPONENTS[@]}"; do
        start_component $component
    done

    echo ""
    echo "======================================"
    echo "安装完成！服务状态："
    echo "======================================"
    for component in "${SELECTED_COMPONENTS[@]}"; do
        case $component in
            blackbox) systemctl status blackbox --no-pager -l || true ;;
            node_exporter) systemctl status node_exporter --no-pager -l || true ;;
            vmagent) systemctl status vmagent --no-pager -l || true ;;
            promtail) systemctl status promtail --no-pager -l || true ;;
        esac
        echo "--------------------------------------"
    done
}

# 主卸载流程
uninstall_components() {
    echo ""
    echo "======================================"
    echo "开始卸载组件..."
    echo "======================================"
    echo "卸载列表: ${SELECTED_COMPONENTS[*]}"
    echo "======================================"
    echo ""

    for component in "${SELECTED_COMPONENTS[@]}"; do
        uninstall_component $component
    done

    systemctl daemon-reload

    # 处理日志删除
    if [ "$DELETE_LOGS" == "y" ]; then
        echo ""
        echo "正在删除系统内生成时间大于1s的日志..."
        journalctl --vacuum-time=1s
        echo "✓ 日志删除完成"
    fi

    echo ""
    echo "======================================"
    echo "卸载完成！"
    echo "======================================"
}

# 执行操作
if $INSTALL; then
    check_component_dependencies
    install_components
elif $UNINSTALL; then
    uninstall_components
fi
