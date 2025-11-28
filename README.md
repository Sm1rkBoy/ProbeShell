# ProbeShell

## 是什么?

Grafana + VictoriaMetrics 被控端模块化安装脚本，支持灵活选择监控组件。

## 功能特性

- **模块化安装**: 可自由选择要安装的组件（blackbox、node_exporter、vmagent、promtail）
- **交互式界面**: 提供友好的菜单式操作
- **命令行支持**: 完整的命令行参数支持，适合自动化部署
- **可配置探测**: blackbox_exporter 支持自定义探测地址

## 快速开始

### 交互式安装（推荐新手）

请使用 `root` 用户运行以下命令：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/agent.sh)
```

然后按照提示选择要安装的组件和输入配置参数。

### 命令行安装（推荐自动化）

#### 安装所有组件

```bash
bash agent.sh --install \
  --vm https://victoria.example.com:8428 \
  --loki https://loki.example.com:3100 \
  --name MyServer.US.001 \
  --vm-user admin \
  --vm-pass secret123
```

#### 只安装指定组件

只安装系统监控（node_exporter + vmagent）：

```bash
bash agent.sh --install \
  --components node_exporter,vmagent \
  --vm https://victoria.example.com:8428 \
  --name MyServer.US.001 \
  --vm-user admin \
  --vm-pass secret123
```

只安装网络探测（blackbox + vmagent）：

```bash
bash agent.sh --install \
  --components blackbox,vmagent \
  --vm https://victoria.example.com:8428 \
  --name ProbeServer.01 \
  --vm-user admin \
  --vm-pass secret123 \
  --blackbox-targets https://google.com,https://baidu.com,https://github.com
```

**注意**: blackbox_exporter 需要配合 vmagent 使用才能采集探测数据

## 可用组件

| 组件 | 说明 | 端口 | 依赖 |
|------|------|------|------|
| `blackbox` | HTTP/TCP/ICMP 探测工具 | 9115 | 需要 vmagent 采集数据 |
| `node_exporter` | 系统指标收集器 | 9100 | 需要 vmagent 采集数据 |
| `vmagent` | VictoriaMetrics 指标代理 | 8429 | 需要 VictoriaMetrics 服务端 |
| `promtail` | Loki 日志收集器 | 9080 | 需要 Loki 服务端 |

## 命令行参数

查看完整的参数说明：

```bash
bash agent.sh --help
```

### 主要参数

- `--install` - 安装组件
- `--uninstall` - 卸载组件
- `--components <list>` - 指定要安装的组件（逗号分隔）
- `--vm <url>` - VictoriaMetrics 写入地址
- `--loki <url>` - Loki 写入地址
- `--name <name>` - VPS/服务器名称
- `--vm-user <user>` - 认证用户名
- `--vm-pass <pass>` - 认证密码
- `--blackbox-targets <urls>` - Blackbox 探测目标（逗号分隔）
- `--delete-logs` - 卸载时删除系统日志

## 使用场景

### 完整监控栈

安装所有组件（默认行为）：

```bash
bash agent.sh --install \
  --vm https://vm.example.com:8428 \
  --loki https://loki.example.com:3100 \
  --name Production.WebServer.01 \
  --vm-user monitoring \
  --vm-pass P@ssw0rd
```

### 仅系统监控

只收集系统指标：

```bash
bash agent.sh --install \
  --components node_exporter,vmagent \
  --vm https://vm.example.com:8428 \
  --name WebServer.01 \
  --vm-user monitoring \
  --vm-pass P@ssw0rd
```

### 仅日志收集

只部署日志收集器：

```bash
bash agent.sh --install \
  --components promtail \
  --loki https://loki.example.com:3100 \
  --name LogServer.01 \
  --vm-user loki \
  --vm-pass secret
```

## 卸载

卸载所有组件：

```bash
bash agent.sh --uninstall --delete-logs
```

卸载指定组件：

```bash
bash agent.sh --uninstall --components vmagent,promtail
```

## Blackbox 探测目标配置

### 通过命令行指定探测目标

```bash
bash agent.sh --install \
  --components blackbox,vmagent \
  --blackbox-targets https://google.com,https://baidu.com,https://github.com \
  --vm https://vm.example.com:8428 \
  --name ProbeServer \
  --vm-user admin \
  --vm-pass secret
```

### 手动编辑探测目标

探测目标配置文件位于：`/usr/local/bin/vmagent/endpoint.yml`

格式示例：

```yaml
# Blackbox Exporter Targets
- targets:
    - "https://google.com"
  labels:
    endpoint: "google.com"

- targets:
    - "https://baidu.com"
  labels:
    endpoint: "baidu.com"
```

修改后重启 vmagent：

```bash
systemctl restart vmagent
```

### 探测目标说明

- 支持 HTTP/HTTPS URL（如：`https://example.com`）
- 支持带端口的地址（如：`http://example.com:8080`）
- 支持 TCP 探测（如：`tcp://example.com:22`）
- 每个目标会自动提取域名作为 `endpoint` 标签

## 故障排查

查看服务状态：

```bash
systemctl status blackbox
systemctl status node_exporter
systemctl status vmagent
systemctl status promtail
```

查看服务日志：

```bash
journalctl -u blackbox -f
journalctl -u vmagent -f
journalctl -u promtail -f
```

查看 blackbox 探测配置：

```bash
cat /usr/local/bin/vmagent/endpoint.yml
```

## 许可证

[![license](https://img.shields.io/github/license/Sm1rkBoy/ProbeShell.svg?style=flat-square)](https://github.com/Sm1rkBoy/ProbeShell/main/LICENSE)

ProbeShell 使用 MIT 协议开源,请遵守开源协议!

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Sm1rkBoy/ProbeShell&type=Timeline)](https://star-history.com/#Sm1rkBoy/ProbeShell&Timeline)