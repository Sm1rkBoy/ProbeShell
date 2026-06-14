# ProbeShell

用于在被控端一键部署 `blackbox_exporter`、`node_exporter` 和 `Vector`。

当前版本使用 Vector 替代旧的 `vmagent` 和 `promtail`：

- `node_exporter` 和 `blackbox_exporter` 继续只监听本机 `127.0.0.1`。
- Vector 抓取 exporter 的 Prometheus 指标，并写入 VictoriaMetrics。
- Vector 采集系统日志，并写入 VictoriaLogs。
- 安装 Vector 时会自动停用并删除旧的 `vmagent`、`promtail` 服务和安装目录。

## 组件

| 组件 | 用途 | 默认监听 | 数据去向 |
| --- | --- | --- | --- |
| `blackbox` | HTTP/TCP/ICMP 网络探测 | `127.0.0.1:9115` | Vector -> VictoriaMetrics |
| `node_exporter` | 主机 CPU/内存/磁盘/网络指标 | `127.0.0.1:9100` | Vector -> VictoriaMetrics |
| `vector` | 指标抓取、日志采集和转发 | 无公开端口 | VictoriaMetrics / VictoriaLogs |

## 版本

| 组件 | 版本 | 架构 |
| --- | --- | --- |
| `blackbox_exporter` | `0.28.0` | amd64, arm64 |
| `node_exporter` | `1.11.1` | amd64, arm64 |
| `vector` | `0.56.0` | amd64, arm64 |

## 快速安装

```bash
bash agent.sh --install \
  --components blackbox,node_exporter,vector \
  --vm https://vmauth.example.com \
  --name MyServer \
  --metrics-token METRICS_BEARER_TOKEN \
  --logs-token LOGS_BEARER_TOKEN
```

## 数据路由

Vector 生成的配置路径：`/usr/local/bin/vector/vector.yaml`

指标：

```text
node_exporter  -> Vector prometheus_scrape -> Vector prometheus_remote_write -> https://vmauth.example.com/api/v1/write
blackbox       -> Vector prometheus_scrape -> Vector prometheus_remote_write -> https://vmauth.example.com/api/v1/write
```

日志：

```text
/var/log/syslog
/var/log/auth.log
/var/log/kern.log
/var/log/cron.log
/var/log/user.log
/var/log/fail2ban.log
  -> Vector file source
  -> Vector http sink
  -> https://vmauth.example.com/insert/jsonline
```

## Blackbox 探测目标

默认探测目标会写入：

```text
/usr/local/bin/vector/endpoint.yml
```

自定义目标：

```bash
bash agent.sh --install \
  --components blackbox,node_exporter,vector \
  --vm https://vmauth.example.com \
  --name ProbeServer \
  --metrics-token METRICS_BEARER_TOKEN \
  --logs-token LOGS_BEARER_TOKEN \
  --blackbox-targets bj-ct-v4.ip.zstaticcdn.com:80,https://github.com
```

脚本会保留旧配置里的 `endpoint` 标签，Vector 会把 blackbox 指标写入 VictoriaMetrics。

## 常用命令

查看状态：

```bash
bash agent.sh --status
```

只安装 Vector：

```bash
bash agent.sh --install \
  --components vector \
  --vm https://vmauth.example.com \
  --name MyServer \
  --metrics-token METRICS_BEARER_TOKEN \
  --logs-token LOGS_BEARER_TOKEN
```

卸载：

```bash
bash agent.sh --uninstall --components blackbox,node_exporter,vector
```

试运行：

```bash
bash agent.sh --install \
  --components blackbox,node_exporter,vector \
  --vm https://vmauth.example.com \
  --name MyServer \
  --metrics-token METRICS_BEARER_TOKEN \
  --logs-token LOGS_BEARER_TOKEN \
  --cache-size 512MiB \
  --dry-run
```

## 参数

| 参数 | 说明 |
| --- | --- |
| `--install` | 安装组件 |
| `--uninstall` | 卸载组件 |
| `--status`, `--list` | 查看组件状态 |
| `--components` | 组件列表：`blackbox,node_exporter,vector` |
| `--vm` | vmauth 地址 |
| `--name` | 实例名称，会写入 metrics/logs 标签 |
| `--metrics-token` | VictoriaMetrics bearer token |
| `--logs-token` | VictoriaLogs bearer token |
| `--blackbox-targets` | Blackbox 探测目标，逗号分隔 |
| `--cache-size` | Vector 每个 sink 的磁盘缓存大小，默认 `512MiB` |
| `--delete-logs` | 卸载时清理系统日志 |
| `--dry-run` | 试运行，不实际安装 |

## 排查

```bash
systemctl status blackbox
systemctl status node_exporter
systemctl status vector
journalctl -u vector -n 100 --no-pager
/usr/local/bin/vector/vector validate --config /usr/local/bin/vector/vector.yaml
```

检查本机 exporter：

```bash
curl http://127.0.0.1:9100/metrics
curl 'http://127.0.0.1:9115/probe?module=tcping&target=bj-ct-v4.ip.zstaticcdn.com:80'
```
