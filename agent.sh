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
        --delete-logs)
            DELETE_LOGS="y"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --install               安装所有组件"
            echo "  --uninstall             卸载所有组件"
            echo "  --victoria, --vm        VictoriaMetrics写入地址"
            echo "  --loki                  Loki写入地址"
            echo "  --name, --instance      VPS名称"
            echo "  --vm-user, --username   VictoriaMetrics用户名"
            echo "  --vm-pass, --password   VictoriaMetrics密码"
            echo "  --delete-logs           卸载时删除日志(默认不删除)"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 菜单
if ! $INSTALL && ! $UNINSTALL; then
    clear
    echo "请选择操作: "
    echo "1) 安装 全部组件"
    echo "2) 卸载 全部组件"
    read -n 1 -p "输入你的选择 (1 或 2): " choice
    echo

    case $choice in
        1) INSTALL=true ;;
        2) UNINSTALL=true ;;
        *) echo "无效选项，请选择 1 或 2."; exit 1 ;;
    esac
fi

install_components() {
    # 安装依赖
    apt install unzip ntpsec-ntpdate -y
    timedatectl set-timezone Asia/Shanghai
    ntpdate ntp.aliyun.com
    CRON_JOB="0 3 * * * /usr/sbin/ntpdate ntp.aliyun.com > /dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -Fxq "$CRON_JOB") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

    # 获取系统架构
    ARCH=$(uname -m)
    if [ "$ARCH" == "x86_64" ]; then
        ARCH_SUFFIX="linux-amd64"
    elif [ "$ARCH" == "aarch64" ]; then
        ARCH_SUFFIX="linux-arm64"
    else
        echo "不支持的架构: $ARCH"
        exit 1
    fi

    # 下载安装 blackbox
    echo "下载安装 blackbox中..."
    BLACKBOX_VERSION="0.27.0"
    wget https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_VERSION}/blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz
    tar -zxvf blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz
    rm blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz
    mv blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}/ /usr/local/bin/blackbox

    # 下载安装 node_exporter
    echo "下载安装 node_exporter 中..."
    NODE_VERSION="1.9.1"
    wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz
    tar -zxvf node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz
    rm node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz
    mv node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}/ /usr/local/bin/node

    # 下载安装 vmagent
    echo "下载安装 vmagent 中..."
    VMAGENT_VERSION="1.128.0"
    wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${VMAGENT_VERSION}/vmutils-${ARCH_SUFFIX}-v${VMAGENT_VERSION}.tar.gz
    tar -zxvf vmutils-${ARCH_SUFFIX}-v${VMAGENT_VERSION}.tar.gz
    rm -rf vmalert-prod vmalert-tool-prod vmauth-prod vmbackup-prod vmctl-prod vmrestore-prod vmutils-${ARCH_SUFFIX}-v${VMAGENT_VERSION}.tar.gz
    mkdir -p /usr/local/bin/vmagent
    mv vmagent-prod /usr/local/bin/vmagent/vmagent
    chmod +x /usr/local/bin/vmagent/vmagent
    chown -v root:root /usr/local/bin/vmagent/vmagent

    # 下载安装 promtail
    echo "下载安装 promtail 中..."
    PROMTAIL_VERSION="3.5.7"
    wget https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-${ARCH_SUFFIX}.zip
    mkdir -p /usr/local/bin/promtail
    unzip promtail-${ARCH_SUFFIX}.zip
    mv promtail-${ARCH_SUFFIX} /usr/local/bin/promtail/promtail
    rm -rf promtail-${ARCH_SUFFIX}.zip
    chmod +x /usr/local/bin/promtail/promtail
    chown -v root:root /usr/local/bin/promtail/promtail

    # 下载服务配置文件
    wget -O /etc/systemd/system/blackbox.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/blackbox.service
    wget -O /etc/systemd/system/node_exporter.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/node_exporter.service
    wget -O /etc/systemd/system/vmagent.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/vmagent.service
    wget -O /etc/systemd/system/promtail.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/promtail.service

    # 如果没有通过命令行获取参数，则交互式获取
    if [ -z "$MAIN_DOMAIN" ]; then
        echo "VictoriaMetrics写入地址一般是<ip>:8428,如果有反代输入域名即可,写入的api会自动拼接"
        read -p "请输入 VictoriaMetrics 写入地址: " MAIN_DOMAIN
    fi
    if [ -z "$LOKI_DOMAIN" ]; then
        read -p "请输入 Loki 写入地址: " LOKI_DOMAIN
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

    # 检查必填参数
    if [[ -z "$MAIN_DOMAIN" || -z "$VM_USERNAME" || -z "$VM_PASSWORD" ]]; then
        echo "错误：域名、用户名和密码不能为空！"
        exit 1
    fi

    # 拼接 VictoriaMetrics /api/v1/write 到主域名
    remote_write_url="${MAIN_DOMAIN}/api/v1/write"

    # 替换 vmagent.service 文件中的配置
    sed -i "s|-remoteWrite.url=.*|-remoteWrite.url=${remote_write_url}|g" /etc/systemd/system/vmagent.service
    sed -i -e "s/-remoteWrite.basicAuth.username=VM_USERNAME/-remoteWrite.basicAuth.username=${VM_USERNAME}/g" -e "s/-remoteWrite.basicAuth.password=VM_PASSWORD/-remoteWrite.basicAuth.password=${VM_PASSWORD}/g" /etc/systemd/system/vmagent.service

    # 下载配置文件
    wget -O /usr/local/bin/blackbox/blackbox.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/blackbox/blackbox.yml
    wget -O /usr/local/bin/vmagent/prometheus.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/vmagent/prometheus.yml
    wget -O /usr/local/bin/promtail/promtail.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/promtail/promtail.yml

    # 检查用户是否输入了值
    if [ -z "$INSTANCE_NAME" ]; then
        echo "错误:instance_name 不能为空！"
        exit 1
    fi

    # 配置 Prometheus 文件路径
    config_file="/usr/local/bin/vmagent/prometheus.yml"
    promtail_file="/usr/local/bin/promtail/promtail.yml"
    loki_push_url="${LOKI_DOMAIN}/loki/api/v1/push"

    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        echo "错误:配置文件 $config_file 不存在！"
        exit 1
    fi

    # 替换值
    sed -i "s/\${instance_name}/${INSTANCE_NAME}/g" "$config_file"
    sed -i "s|instance: ''|instance: '${INSTANCE_NAME}'|g" "$promtail_file"
    sed -i "s|url:|url: ${loki_push_url}|" "$promtail_file"
    sed -i "s|username:|username: ${VM_USERNAME}|" "$promtail_file"
    sed -i "s|password:|password: ${VM_PASSWORD}|" "$promtail_file"

    # 检查替换是否成功
    if grep -q "$INSTANCE_NAME" "$config_file"; then
        echo "成功：${INSTANCE_NAME} 已替换为 $INSTANCE_NAME 在配置文件 $config_file 中。"
    else
        echo "错误：替换失败，请检查配置文件。"
        exit 1
    fi

    # 下载endpoint.yml
    wget -O /usr/local/bin/vmagent/endpoint.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/vmagent/endpoint.yml

    # 设置权限
    chmod 644 /etc/systemd/system/blackbox.service
    chmod 644 /etc/systemd/system/node_exporter.service
    chmod 644 /etc/systemd/system/vmagent.service
    chmod 644 /etc/systemd/system/promtail.service

    # 启动服务
    systemctl daemon-reload
    systemctl start blackbox
    systemctl start node_exporter
    systemctl start vmagent
    systemctl start promtail

    systemctl enable blackbox
    systemctl enable node_exporter
    systemctl enable vmagent
    systemctl enable promtail

    echo "安装完成！服务状态："
    systemctl status blackbox --no-pager
    systemctl status node_exporter --no-pager
    systemctl status vmagent --no-pager
    systemctl status promtail --no-pager
}

uninstall_components() {
    echo "停止所有服务..."
    systemctl stop blackbox
    systemctl stop node_exporter
    systemctl stop vmagent
    systemctl stop promtail

    echo "禁用开机自启..."
    systemctl disable blackbox
    systemctl disable node_exporter
    systemctl disable vmagent
    systemctl disable promtail

    echo "删除服务文件..."
    rm -f /etc/systemd/system/blackbox.service
    rm -f /etc/systemd/system/node_exporter.service
    rm -f /etc/systemd/system/vmagent.service
    rm -f /etc/systemd/system/promtail.service

    echo "重载服务配置..."
    systemctl daemon-reload

    echo "删除安装文件..."
    rm -rf /usr/local/bin/blackbox
    rm -rf /usr/local/bin/node
    rm -rf /usr/local/bin/vmagent
    rm -rf /usr/local/bin/promtail

    # 处理日志删除
    if [ "$DELETE_LOGS" == "y" ]; then
        echo "正在删除系统内生成时间大于1s的日志..."
        journalctl --vacuum-time=1s
        echo "日志删除完成。"
    else
        echo "未删除日志。"
    fi

    echo "卸载完成！"
}

# 执行操作
if $INSTALL; then
    install_components
elif $UNINSTALL; then
    uninstall_components
fi