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

只安装系统监控（node_exporter + vmagent），自定义缓存大小：

```bash
bash agent.sh --install \
  --components node_exporter,vmagent \
  --vm https://victoria.example.com:8428 \
  --name MyServer.US.001 \
  --vm-user admin \
  --vm-pass secret123 \
  --cache-size 2G
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

| 组件 | 说明 | 端口 | 依赖 | 端口绑定 |
|------|------|------|------|----------|
| `blackbox` | HTTP/TCP/ICMP 探测工具 | 9115 | **依赖 vmagent** | 127.0.0.1（不对外） |
| `node_exporter` | 系统指标收集器 | 9100 | **依赖 vmagent** | 127.0.0.1（不对外） |
| `vmagent` | VictoriaMetrics 指标代理 | 8429 | 需要 VictoriaMetrics 服务端 | 127.0.0.1（不对外） |
| `promtail` | Loki 日志收集器 | 9080 | 需要 Loki 服务端 | - |

### 组件依赖说明

**重要**：
- `blackbox_exporter` 和 `node_exporter` **必须配合 vmagent 使用**
- vmagent 负责从本地的 exporter 采集数据并传输到 VictoriaMetrics
- 所有 exporter 端口都绑定在 `127.0.0.1`，不对外暴露，提高安全性
- `promtail` 是独立组件，可以单独安装使用

**数据流向**：
```
node_exporter (127.0.0.1:9100) ─┐
                                 ├─→ vmagent ──→ VictoriaMetrics
blackbox_exporter (127.0.0.1:9115) ─┘

promtail ──────────────────────────→ Loki
```

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
- `--cache-size <size>` - vmagent 离线缓存大小（默认: 500M）
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

### 交互式卸载

```bash
bash agent.sh
```

然后选择 "2) 卸载组件"，再选择要卸载的组件。

### 命令行卸载

卸载所有组件并删除日志：

```bash
bash agent.sh --uninstall --delete-logs
```

**按需卸载指定组件**：

```bash
# 只卸载 vmagent 和 promtail
bash agent.sh --uninstall --components vmagent,promtail

# 只卸载 blackbox
bash agent.sh --uninstall --components blackbox

# 卸载所有监控组件但保留日志收集
bash agent.sh --uninstall --components blackbox,node_exporter,vmagent
```

**注意**：
- 卸载 vmagent 会导致 blackbox 和 node_exporter 的数据无法被采集
- 建议按需卸载，而不是卸载所有组件后重新安装

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

## vmagent 离线缓存

vmagent 具有离线缓存功能，当无法连接到 VictoriaMetrics 服务端时：

- **自动缓存**：vmagent 会将采集的数据缓存到本地磁盘
- **自动重传**：当连接恢复后，会自动将缓存的数据传输到服务端
- **磁盘限制**：默认配置磁盘使用上限为 **500M**，防止占用过多磁盘空间
- **可自定义**：通过 `--cache-size` 参数按需设置缓存大小

### 安装时指定缓存大小

**命令行方式**：

```bash
# 使用 2G 缓存
bash agent.sh --install \
  --components vmagent \
  --vm https://vm.example.com:8428 \
  --name MyServer \
  --vm-user admin \
  --vm-pass secret \
  --cache-size 2G

# 使用 500M 缓存
bash agent.sh --install \
  --components vmagent \
  --cache-size 500M \
  --vm https://vm.example.com:8428 \
  --name MyServer \
  --vm-user admin \
  --vm-pass secret
```

**交互式方式**：

运行脚本时会提示输入缓存大小：

```
vmagent 离线缓存设置（连接不上服务器时本地缓存数据）
请输入缓存大小 (默认: 500M, 示例: 1G, 2G):
```

直接回车使用默认值 500M，或输入自定义大小如 `1G`、`2G` 等。

### 手动修改缓存大小

如果需要修改已安装的 vmagent 缓存限制：

```bash
vi /etc/systemd/system/vmagent.service
```

找到 `ExecStart` 行，修改 `-remoteWrite.maxDiskUsagePerURL` 参数：

```ini
# 示例：改为 2G
-remoteWrite.maxDiskUsagePerURL=2G

# 示例：改为 500M
-remoteWrite.maxDiskUsagePerURL=500M
```

修改后重启服务：

```bash
systemctl daemon-reload
systemctl restart vmagent
```

### 查看缓存状态

```bash
# 查看 vmagent 日志
journalctl -u vmagent -f

# 检查磁盘使用情况
du -sh /var/lib/vmagent/
```

## 安全说明

- ✅ 所有 exporter 端口都绑定在 `127.0.0.1`，不对外网暴露
- ✅ 只有本地的 vmagent 可以访问 exporter 数据
- ✅ vmagent 通过 Basic Auth 认证连接到 VictoriaMetrics
- ✅ 减少了攻击面，提高系统安全性

## 许可证

[![license](https://img.shields.io/github/license/Sm1rkBoy/ProbeShell.svg?style=flat-square)](https://github.com/Sm1rkBoy/ProbeShell/main/LICENSE)

ProbeShell 使用 MIT 协议开源,请遵守开源协议!

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Sm1rkBoy/ProbeShell&type=Timeline)](https://star-history.com/#Sm1rkBoy/ProbeShell&Timeline)