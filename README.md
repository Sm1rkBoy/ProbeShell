# ProbeShell

<div align="center">

**生产级监控组件一键部署脚本**

[![License](https://img.shields.io/github/license/Sm1rkBoy/ProbeShell.svg?style=flat-square)](https://github.com/Sm1rkBoy/ProbeShell/blob/main/LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/Sm1rkBoy/ProbeShell.svg?style=flat-square)](https://github.com/Sm1rkBoy/ProbeShell/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/Sm1rkBoy/ProbeShell.svg?style=flat-square)](https://github.com/Sm1rkBoy/ProbeShell/issues)

[功能特性](#-功能特性) • [快速开始](#-快速开始) • [使用文档](#-使用文档) • [故障排查](#-故障排查) • [更新日志](#-更新日志)

</div>

---

## 📖 项目简介

ProbeShell 是一个用于快速部署 **VictoriaMetrics** 和 **Loki** 监控栈被控端的自动化脚本。支持模块化选择组件、交互式安装、命令行批量部署，适用于生产环境的监控系统快速搭建。

### 支持的组件

| 组件 | 用途 | 默认端口 | 依赖 |
|------|------|---------|------|
| **blackbox_exporter** | HTTP/TCP/ICMP 网络探测 | 9115 | 需要 vmagent |
| **node_exporter** | 系统指标采集（CPU/内存/磁盘等） | 9100 | 需要 vmagent |
| **vmagent** | 指标收集代理，推送到 VictoriaMetrics | 8429 | - |
| **promtail** | 日志收集器，推送到 Loki | 9080 | - |

> **安全设计**: 所有 exporter 端口仅绑定 `127.0.0.1`，不对外暴露，仅本地 vmagent 可访问。

---

## ✨ 功能特性

### 🎯 核心功能

- **模块化安装** - 自由选择需要的组件，按需部署
- **智能状态管理** - 自动检测组件安装状态和运行状态
- **双模式操作** - 支持交互式菜单和命令行参数两种方式
- **配置验证** - 安装前自动验证所有必需参数
- **安全可靠** - 严格错误处理，操作前确认，支持试运行

### 🆕 v2.0 重构版亮点

| 特性 | 说明 |
|------|------|
| **状态查看** | `--status` 快速查看所有组件运行状态 |
| **试运行模式** | `--dry-run` 模拟执行，不实际修改系统 |
| **智能卸载** | 自动识别已安装组件，卸载前确认 |
| **错误重试** | 下载失败自动重试 3 次，超时 30 秒 |
| **彩色日志** | INFO/SUCCESS/WARN/ERROR 分级彩色输出 |
| **部分容错** | 单个组件失败不影响其他组件安装 |
| **重装保护** | 检测到已安装组件时提示确认 |
| **配置校验** | 缓存大小格式、必填参数完整性验证 |

---

## 🚀 快速开始

### 方式一：一键安装（推荐）

在线执行脚本，进入交互式安装界面：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/agent.sh)
```

> **系统要求**:
> - 需要 `root` 权限
> - 支持系统: Debian/Ubuntu
> - 支持架构: x86_64 / aarch64

### 方式二：命令行快速部署

适合批量部署或自动化场景：

```bash
# 下载脚本
wget https://raw.githubusercontent.com/Sm1rkBoy/ProbeShell/main/agent.sh
chmod +x agent.sh

# 安装完整监控栈
./agent.sh --install \
  --vm https://victoria.example.com:8428 \
  --loki https://loki.example.com:3100 \
  --name Production.WebServer.01 \
  --vm-user admin \
  --vm-pass secret123
```

### 方式三：选择性安装组件

```bash
# 只安装系统监控（node_exporter + vmagent）
./agent.sh --install \
  --components node_exporter,vmagent \
  --vm https://vm.example.com:8428 \
  --name MyServer \
  --vm-user admin \
  --vm-pass secret \
  --cache-size 2G

# 只安装网络探测（blackbox + vmagent）
./agent.sh --install \
  --components blackbox,vmagent \
  --vm https://vm.example.com:8428 \
  --name ProbeServer \
  --vm-user admin \
  --vm-pass secret \
  --blackbox-targets https://google.com,https://github.com

# 只安装日志收集（promtail）
./agent.sh --install \
  --components promtail \
  --loki https://loki.example.com:3100 \
  --name LogServer \
  --vm-user admin \
  --vm-pass secret
```

---

## 📚 使用文档

### 命令行参数完整列表

```bash
./agent.sh --help
```

#### 操作选项

| 参数 | 说明 |
|------|------|
| `--install` | 安装模式 |
| `--uninstall` | 卸载模式 |
| `--status` / `--list` | 显示组件状态 |
| `--dry-run` | 试运行模式（不实际执行） |
| `--help` / `-h` | 显示帮助信息 |

#### 组件选择

| 参数 | 说明 | 示例 |
|------|------|------|
| `--components <列表>` | 指定要安装/卸载的组件 | `--components blackbox,vmagent` |

**可用组件**: `blackbox`, `node_exporter`, `vmagent`, `promtail`

#### 配置参数

| 参数 | 说明 | 必需组件 | 示例 |
|------|------|----------|------|
| `--vm <地址>` | VictoriaMetrics 写入地址 | vmagent | `--vm https://vm.example.com:8428` |
| `--loki <地址>` | Loki 写入地址 | promtail | `--loki https://loki.example.com:3100` |
| `--name <名称>` | 实例名称（用于标识机器） | vmagent/promtail | `--name WebServer.US.01` |
| `--vm-user <用户名>` | 认证用户名 | vmagent/promtail | `--vm-user admin` |
| `--vm-pass <密码>` | 认证密码 | vmagent/promtail | `--vm-pass secret123` |
| `--blackbox-targets <URL列表>` | Blackbox 探测目标（逗号分隔） | blackbox | `--blackbox-targets https://google.com,https://baidu.com` |
| `--cache-size <大小>` | vmagent 离线缓存大小 | vmagent | `--cache-size 2G` (默认: 500M) |
| `--delete-logs` | 卸载时删除系统日志 | - | - |

### 常用操作示例

#### 1️⃣ 查看组件状态

```bash
./agent.sh --status
```

**输出示例**:
```
======================================
组件状态
======================================
● blackbox: 运行中
● node_exporter: 运行中
● vmagent: 运行中
● promtail: 未安装
```

#### 2️⃣ 试运行测试

在实际执行前预览操作：

```bash
# 测试安装
./agent.sh --install --components vmagent --dry-run

# 测试卸载
./agent.sh --uninstall --dry-run
```

#### 3️⃣ 智能卸载

自动检测并卸载所有已安装的组件：

```bash
# 卸载所有组件（带确认提示）
./agent.sh --uninstall

# 卸载所有组件并删除日志（跳过确认）
./agent.sh --uninstall --delete-logs
```

#### 4️⃣ 选择性卸载

```bash
# 只卸载指定组件
./agent.sh --uninstall --components blackbox,promtail

# 保留 vmagent，卸载 exporter
./agent.sh --uninstall --components blackbox,node_exporter
```

---

## ⚙️ 高级配置

### Blackbox 探测目标配置

#### 方法一：安装时指定

```bash
./agent.sh --install \
  --components blackbox,vmagent \
  --blackbox-targets https://google.com,https://github.com,http://localhost:8080 \
  --vm https://vm.example.com:8428 \
  --name ProbeServer \
  --vm-user admin \
  --vm-pass secret
```

#### 方法二：手动编辑配置文件

配置文件路径: `/usr/local/bin/vmagent/endpoint.yml`

```yaml
# Blackbox Exporter Targets - Auto Generated
# Format: Prometheus file_sd_configs

- targets:
    - "https://google.com"
  labels:
    endpoint: "google.com"

- targets:
    - "https://github.com"
  labels:
    endpoint: "github.com"

- targets:
    - "tcp://example.com:22"
  labels:
    endpoint: "example.com"
```

修改后重启 vmagent:
```bash
systemctl restart vmagent
```

**支持的探测类型**:
- HTTP/HTTPS: `https://example.com`
- 带端口: `http://example.com:8080`
- TCP: `tcp://example.com:22`

### vmagent 离线缓存配置

vmagent 支持在无法连接到 VictoriaMetrics 时本地缓存数据，连接恢复后自动回传。

#### 安装时配置缓存大小

```bash
./agent.sh --install \
  --components vmagent \
  --vm https://vm.example.com:8428 \
  --name MyServer \
  --vm-user admin \
  --vm-pass secret \
  --cache-size 2GB    # 可选: 500MB, 1GB, 2GB, 5GB 等
```

#### 手动修改缓存大小

编辑服务文件:
```bash
vi /etc/systemd/system/vmagent.service
```

找到并修改 `-remoteWrite.maxDiskUsagePerURL` 参数:
```ini
-remoteWrite.maxDiskUsagePerURL=2GB
```

重启服务:
```bash
systemctl daemon-reload
systemctl restart vmagent
```

#### 查看缓存使用情况

```bash
# 查看日志
journalctl -u vmagent -f

# 检查磁盘占用
du -sh /var/lib/vmagent/
```

---

## 🔍 故障排查

### 快速诊断

#### 1. 检查组件状态

```bash
# 使用脚本快速查看
./agent.sh --status

# 使用 systemctl 查看详细状态
systemctl status blackbox
systemctl status node_exporter
systemctl status vmagent
systemctl status promtail
```

#### 2. 查看实时日志

```bash
# 查看最近 50 行日志
journalctl -u vmagent -n 50

# 实时跟踪日志
journalctl -u vmagent -f

# 查看启动失败的错误
systemctl status vmagent --no-pager -l
```

#### 3. 验证配置文件

```bash
# 检查 vmagent 配置
cat /usr/local/bin/vmagent/prometheus.yml

# 检查 blackbox 探测目标
cat /usr/local/bin/vmagent/endpoint.yml

# 检查 promtail 配置
cat /usr/local/bin/promtail/promtail.yml
```

### 常见问题解决

<details>
<summary><b>问题 1: 下载失败</b></summary>

**症状**: 提示 `[ERROR] 下载失败: xxx`

**原因**: 网络问题或 GitHub 访问受限

**解决方案**:
1. v2.0 版本会自动重试 3 次，请等待重试完成
2. 检查网络连接: `ping github.com`
3. 配置代理或更换网络环境
4. 手动下载组件后放置到相应目录

</details>

<details>
<summary><b>问题 2: 服务启动失败</b></summary>

**症状**: 安装完成但服务未运行

**排查步骤**:
```bash
# 1. 查看服务状态
systemctl status vmagent --no-pager -l

# 2. 查看详细日志
journalctl -u vmagent -n 100

# 3. 检查配置文件语法
/usr/local/bin/vmagent/vmagent -promscrape.config=/usr/local/bin/vmagent/prometheus.yml -dryRun

# 4. 检查端口占用
ss -tlnp | grep 8429
```

**常见原因**:
- VictoriaMetrics 地址无法访问
- 认证用户名/密码错误
- 配置文件格式错误
- 端口被占用

</details>

<details>
<summary><b>问题 3: 配置验证失败</b></summary>

**症状**: 安装时提示 `[ERROR] vmagent 配置验证失败`

**常见错误**:
- `VictoriaMetrics 地址不能为空` → 使用 `--vm` 参数指定地址
- `缓存大小格式无效` → 格式应为 `500M`、`1G`、`2G` 等
- `用户名不能为空` → 使用 `--vm-user` 指定用户名
- `密码不能为空` → 使用 `--vm-pass` 指定密码

**解决方案**: 根据错误提示补充缺失的参数后重新运行

</details>

<details>
<summary><b>问题 4: 数据未上报到 VictoriaMetrics</b></summary>

**排查步骤**:
```bash
# 1. 检查 vmagent 是否正常运行
systemctl status vmagent

# 2. 查看 vmagent 日志，关注连接错误
journalctl -u vmagent -f | grep -i error

# 3. 测试到 VictoriaMetrics 的连接
curl -u admin:password https://vm.example.com:8428/health

# 4. 检查 exporter 是否正常暴露指标
curl http://127.0.0.1:9100/metrics
curl http://127.0.0.1:9115/metrics

# 5. 检查 vmagent 配置
cat /usr/local/bin/vmagent/prometheus.yml
```

</details>

<details>
<summary><b>问题 5: Blackbox 探测未生效</b></summary>

**排查步骤**:
```bash
# 1. 检查探测目标配置
cat /usr/local/bin/vmagent/endpoint.yml

# 2. 检查 blackbox_exporter 是否运行
systemctl status blackbox

# 3. 手动测试探测
curl "http://127.0.0.1:9115/probe?target=https://google.com&module=http_2xx"

# 4. 重启服务
systemctl restart vmagent
systemctl restart blackbox
```

</details>

---

## 🔒 安全最佳实践

### 端口绑定策略

所有 exporter 组件仅监听 `127.0.0.1`，不对外暴露：

```bash
# 验证端口绑定
ss -tlnp | grep -E '9100|9115|8429|9080'

# 预期输出（仅绑定 127.0.0.1）
127.0.0.1:9100    # node_exporter
127.0.0.1:9115    # blackbox_exporter
127.0.0.1:8429    # vmagent
```

### 认证机制

- ✅ vmagent → VictoriaMetrics: **Basic Auth** 认证
- ✅ promtail → Loki: **Basic Auth** 认证（可选）
- ✅ 本地 exporter: 仅本地访问，无需认证

### 数据传输

- ✅ 建议使用 **HTTPS** 协议连接 VictoriaMetrics/Loki
- ✅ 支持通过反向代理（Nginx/Traefik）进行 TLS 终止
- ✅ vmagent 离线缓存数据加密存储

---

## 📦 组件版本

脚本当前使用的组件版本：

| 组件 | 版本 | 架构支持 |
|------|------|----------|
| blackbox_exporter | 0.27.0 | amd64, arm64 |
| node_exporter | 1.9.1 | amd64, arm64 |
| vmagent | 1.128.0 | amd64, arm64 |
| promtail | 3.5.7 | amd64, arm64 |

> 版本在脚本顶部集中定义，可按需修改

---

## 🔄 更新日志

### v2.0.0 (2024-11-28) - 重构版

**重大更新**:
- ✨ 全新架构，使用 `set -euo pipefail` 严格模式
- ✨ 新增 `--status` 命令，快速查看组件状态
- ✨ 新增 `--dry-run` 试运行模式
- ✨ 智能组件状态检测和管理
- ✨ 自动检测已安装组件，智能卸载

**功能改进**:
- 🚀 下载失败自动重试（3次，超时30秒）
- 🚀 配置参数完整性验证
- 🚀 重新安装前确认提示
- 🚀 部分组件失败不影响其他组件
- 🚀 彩色分级日志输出（INFO/SUCCESS/WARN/ERROR）
- 🚀 临时文件自动清理机制

**用户体验**:
- 💡 更友好的交互式菜单
- 💡 清晰的安装/卸载进度提示
- 💡 详细的错误信息和解决建议
- 💡 操作前确认，防止误操作

**安全性**:
- 🔒 严格的错误处理，避免部分执行
- 🔒 操作前参数验证
- 🔒 Root 权限检查

### v1.0.0 (2024-XX-XX) - 初始版本

- 基础的模块化安装功能
- 支持 4 个组件的安装和卸载
- 交互式和命令行两种模式

---

## 🤝 贡献指南

欢迎贡献代码、报告问题或提出建议！

### 报告问题

如果遇到 Bug 或有功能建议，请 [提交 Issue](https://github.com/Sm1rkBoy/ProbeShell/issues/new)，并包含：
- 系统信息（`uname -a`）
- 脚本版本
- 完整的错误日志
- 复现步骤

### 提交 Pull Request

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

---

## 📄 许可证

本项目采用 [MIT License](LICENSE) 开源协议。

---

## 📞 联系方式

- **项目主页**: [https://github.com/Sm1rkBoy/ProbeShell](https://github.com/Sm1rkBoy/ProbeShell)
- **问题反馈**: [Issues](https://github.com/Sm1rkBoy/ProbeShell/issues)
- **Pull Requests**: [PRs](https://github.com/Sm1rkBoy/ProbeShell/pulls)

---

## ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Sm1rkBoy/ProbeShell&type=Timeline)](https://star-history.com/#Sm1rkBoy/ProbeShell&Timeline)

---

<div align="center">

**如果这个项目对你有帮助，请给一个 ⭐ Star 支持一下！**

Made with ❤️ by [Sm1rkBoy](https://github.com/Sm1rkBoy)

</div>
