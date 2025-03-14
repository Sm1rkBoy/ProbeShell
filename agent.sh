#!/bin/bash

clear

echo "请选择操作: "
echo "1) 安装 全部组件"
echo "2) 卸载 全部组件"
read -n 1 -p "输入你的选择 (1 或 2): " choice

case $choice in
1)
    echo

    # 安装依赖
    apt install unzip ntpdate -y
    timedatectl set-timezone Asia/Shanghai
    ntpdate ntp.aliyun.com
    CRON_JOB="0 3 * * * /usr/sbin/ntpdate ntp.aliyun.com > /dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -Fxq "$CRON_JOB") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

    # 获取系统架构
    ARCH=$(uname -m)

    # 下载二进制文件
    if [ "$ARCH" == "x86_64" ]; then
        ARCH_SUFFIX="linux-amd64"
    elif [ "$ARCH" == "aarch64" ]; then
        ARCH_SUFFIX="linux-arm64"
    else
        echo "不支持的架构: $ARCH"
        exit 1
    fi

    echo "下载安装 blackbox中..."
    BLACKBOX_VERSION="0.25.0"
    wget https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_VERSION}/blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz
    tar -zxvf blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz
    rm blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}.tar.gz
    mv blackbox_exporter-${BLACKBOX_VERSION}.${ARCH_SUFFIX}/ /usr/local/bin/blackbox

    echo "下载安装 node_exporter 中..."
    NODE_VERSION="1.8.2"
    wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_VERSION}/node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz
    tar -zxvf node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz
    rm node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}.tar.gz
    mv node_exporter-${NODE_VERSION}.${ARCH_SUFFIX}/ /usr/local/bin/node

    echo "下载安装 vmagent 中..."
    VMAGENT_VERSION="1.109.0"
    wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${VMAGENT_VERSION}/vmutils-${ARCH_SUFFIX}-v${VMAGENT_VERSION}.tar.gz
    tar -zxvf vmutils-${ARCH_SUFFIX}-v${VMAGENT_VERSION}.tar.gz
    rm -rf vmalert-prod vmalert-tool-prod vmauth-prod vmbackup-prod vmctl-prod vmrestore-prod vmutils-${ARCH_SUFFIX}-v${VMAGENT_VERSION}.tar.gz
    mkdir -p /usr/local/bin/vmagent
    mv vmagent-prod /usr/local/bin/vmagent/vmagent
    chmod +x /usr/local/bin/vmagent/vmagent
    chown -v root:root /usr/local/bin/vmagent/vmagent

    echo "下载安装 promtail 中..."
    PROMTAIL_VERSION="3.4.2"
    wget https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-${ARCH_SUFFIX}.zip
    mkdir -p /usr/local/bin/promtail
    unzip promtail-${ARCH_SUFFIX}.zip
    mv promtail-${ARCH_SUFFIX} /usr/local/bin/promtail/promtail
    rm -rf promtail-${ARCH_SUFFIX}.zip
    chmod +x /usr/local/bin/promtail/promtail
    chown -v root:root /usr/local/bin/promtail/promtail

    # ---------------------------------------------------------------------------------------------------
    # 配置blackbox系统服务
    wget -O /etc/systemd/system/blackbox.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/blackbox.service

    # 配置node_exporter系统服务
    wget -O /etc/systemd/system/node_exporter.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/node_exporter.service

    # 配置vmagent系统服务
    wget -O /etc/systemd/system/vmagent.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/vmagent.service

    # 配置promtail系统服务
    wget -O /etc/systemd/system/promtail.service https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/service/promtail.service

    # 提示用户输入主域名
    echo "VictoriaMetrics写入地址一般是<ip>:8428,如果有反代输入域名即可,写入的api会自动拼接"
    read -p "请输入 VictoriaMetrics 写入地址: " main_domain
    read -p "请输入 Loki 写入地址: " loki_domain
    read -p "请输入VPS名(比如GreenCloud.JP.6666): " instance_name
    read -p "请输入 VictoriaMetrics 的用户名: " VM_USERNAME
    read -sp "请输入 VictoriaMetrics 的密码: " VM_PASSWORD

    # 检查输入是否为空
    if [[ -z "$VM_USERNAME" || -z "$VM_PASSWORD" || -z "$main_domain" ]]; then
        echo "错误：域名、用户名和密码不能为空！"
        exit 1
    fi

    # 拼接 VictoriaMetrics /api/v1/write 到主域名
    remote_write_url="${main_domain}/api/v1/write"

    # 替换 vmagent.service 文件中的 remoteWrite URL
    sudo sed -i "s|-remoteWrite.url=.*|-remoteWrite.url=${remote_write_url}|g" /etc/systemd/system/vmagent.service
    sudo sed -i -e "s/-remoteWrite.basicAuth.username=VM_USERNAME/-remoteWrite.basicAuth.username=${VM_USERNAME}/g" -e "s/-remoteWrite.basicAuth.password=VM_PASSWORD/-remoteWrite.basicAuth.password=${VM_PASSWORD}/g" /etc/systemd/system/vmagent.service

    # ---------------------------------------------------------------------------------------------------
    # 配置blackbox.yml
    wget -O /usr/local/bin/blackbox/blackbox.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/blackbox/blackbox.yml

    # 配置prometheus.yml
    wget -O /usr/local/bin/vmagent/prometheus.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/vmagent/prometheus.yml

    # 配置promtail.yml
    wget -O /usr/local/bin/promtail/promtail.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/promtail/promtail.yml

    # 检查用户是否输入了值
    if [ -z "$instance_name" ]; then
        echo "错误:instance_name 不能为空！"
        exit 1
    fi

    # 配置 Prometheus 文件路径
    config_file="/usr/local/bin/vmagent/prometheus.yml"

    # 配置 Loki 文件路径
    promtail_file="/usr/local/bin/promtail/promtail.yml"

    # 拼接 Loki /loki/api/v1/push 到主域名
    loki_push_url="${loki_domain}/loki/api/v1/push"

    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        echo "错误:配置文件 $config_file 不存在！"
        exit 1
    fi

    # 替换值
    sed -i "s/\${instance_name}/$instance_name/g" "$config_file"
    sed -i "s|instance: ''|instance: '$instance_name'|g" "$promtail_file"
    sed -i "s|url:|url: $loki_push_url|" "$promtail_file"
    sed -i "s|username:|username: $VM_USERNAME|" "$promtail_file"
    sed -i "s|password:|password: $VM_PASSWORD|" "$promtail_file"


    # 检查替换是否成功
    if grep -q "$instance_name" "$config_file"; then
        echo "成功：${instance_name} 已替换为 $instance_name 在配置文件 $config_file 中。"
    else
        echo "错误：替换失败，请检查配置文件。"
        exit 1
    fi

    # 配置endpoint.yml
    wget -O /usr/local/bin/vmagent/endpoint.yml https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/vmagent/endpoint.yml
    # ---------------------------------------------------------------------------------------------------

    chmod 644 /etc/systemd/system/blackbox.service
    chmod 644 /etc/systemd/system/node_exporter.service
    chmod 644 /etc/systemd/system/vmagent.service
    chmod 644 /etc/systemd/system/promtail.service

    systemctl daemon-reload

    systemctl start blackbox
    systemctl start node_exporter
    systemctl start vmagent
    systemctl start promtail

    systemctl enable blackbox
    systemctl enable node_exporter
    systemctl enable vmagent
    systemctl enable promtail

    systemctl status blackbox
    systemctl status node_exporter
    systemctl status vmagent
    systemctl status promtail
    ;;
2)
    echo
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

    echo "删除 blackbox_exporter 文件..."
    rm -rf /usr/local/bin/blackbox
    rm -rf /usr/local/bin/node
    rm -rf /usr/local/bin/vmagent
    rm -rf /usr/local/bin/promtail

    # 提示用户输入，设置默认值为n
    read -e -p "是否需要删除系统内生成时间大于1s的日志(谨慎操作!)[y/N]: " delete_log
    delete_log=${delete_log:-n}  # 如果用户未输入，则赋值为 n

    # 将用户输入转换为小写，以便处理大小写不敏感的情况
    delete_log=${delete_log,,}

    # 判断用户输入
    if [[ "$delete_log" == "y" ]]; then
        echo "正在删除系统内生成时间大于1s的日志..."
        journalctl --vacuum-time=1s
        echo "日志删除完成。"
    else
        echo "未删除日志。"
    fi
    ;;
*)
    echo "无效选项，请选择 1 或 2."
    ;;
esac