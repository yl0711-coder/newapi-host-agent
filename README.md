# newapi-host-agent

> **状态(2026-06-24):备选实现,当前未部署。** 线上 Master/Slave/Redis 实际部署的是
> [newapi-monitor](https://github.com/yl0711-coder/newapi-monitor) 的 **`cmd/hostagent`(容器版,Go)**,镜像 `newapi-monitor-hostagent`。
> 本仓是 **systemd + shell 的备选版(不依赖 docker,适合无 docker 的节点如 Ubuntu-1)**,功能可能落后于容器版。
> **以线上为准:改/部署以容器版为标准**;本仓作无 docker 场景的备选/参考,要用前需先与容器版对齐。

NexusAPI 主机指标采集器。采集 **AWS 接口拿不到的主机 OS 指标**(内存 / 磁盘 / swap / load),
推送给 [newapi-monitor](https://github.com/yl0711-coder/newapi-monitor) 的 `/internal/host` 接收端点,
在 monitor 的「服务端监控」Tab 展示。

> 实例存活 / CPU / 网络、数据库(含内存/swap)、负载均衡这些 **AWS Lightsail 指标接口能取的**,
> 由 monitor 后端直接拉,不需要本 agent。本 agent 只补 AWS 给不了的主机 OS 内存/磁盘。
> 设计依据:`文档/NexusAPI/13-运维手册/10-monitor实例健康监控技术方案.md`。

## 形态与资源占用

- **不是常驻进程**:systemd timer 每 60s 以 oneshot 拉起 `report.sh`,跑约 0.1–0.3s 即退出。
- 内存:运行瞬间几 MB(shell+curl),退出即归还 → **平均常驻 ≈ 0**。
- CPU:每分钟约 0.1–0.3 CPU-秒 → 平均 ≈0%。
- 不开端口、无常驻连接(只出站 POST)、**不依赖 docker**。
- 依赖:`awk`/`df`/`curl`(系统自带)+ 读 `/proc/meminfo`、`/proc/loadavg`。

## 安装(每台实例一次)

```sh
MONITOR_URL=http://172.26.10.97:8090 \
INGEST_TOKEN=<monitor 的 MONITOR_INGEST_TOKEN> \
NODE_NAME=Ubuntu-NexusAPI-Slave-1 \
  sudo -E sh install-agent.sh
```

- `NODE_NAME` 建议填**该机对应的 Lightsail 实例名**,这样 host 指标能和 monitor 云侧指标对应到同一资源;留空则用 hostname。
- 安装后立即测一次:
  ```sh
  sudo systemctl start nexus-hostagent.service
  journalctl -u nexus-hostagent.service -n 20 --no-pager
  ```

## 自动部署(新实例免手动)

`install-agent.sh` 全程非交互、幂等,三种机制任选:
- **Lightsail 启动脚本**:创建实例时把"拉取本仓库 + 跑 install-agent.sh"放进 Launch script,首次开机自动装。
- **黄金快照**:在装好 agent 的节点做快照,新节点从快照克隆即自带。
- **一行 bootstrap**:`curl -fsSL <install-agent.sh 地址> | sudo -E sh`(给已存在的机补装)。

> token 若内嵌进启动脚本/快照会留在实例元数据/镜像里(内部 ingest token,敏感度较低);
> 要更严可首启占位、开机后再注入。

## 故障与韧性

- 单次推送失败(monitor 不可达/超时):仅丢该次数据点,**下个 60s 周期自动重试**,自愈。
- agent 异常:它是 timer 拉起的 oneshot,**不会"崩了就一直死"**,每分钟必再拉起;失败记入 journald。
- agent 持续失联:由 monitor 端 **staleness 检测**(某节点超 N 分钟未上报即告警)兜底,不会变成无声盲区。
- agent 挂 **不影响被监控的服务**(它只是只读、出站推送的旁路观察者)。
- 卸载:`sudo systemctl disable --now nexus-hostagent.timer` + 删 `/opt/nexus-hostagent` 与 systemd 单元,无残留。

## 安全

- 只上报**非敏感数值**(内存/磁盘/load 的数字),不含任何密钥或业务数据。
- token 存 `agent.env`(600),不写进脚本本体、不入 git(见 `.gitignore`)。
- 走内网到 monitor 的 ingest 端点,Bearer 鉴权。

## 文件

| 文件 | 用途 |
|---|---|
| `report.sh` | 采集 + 推送(timer 调用) |
| `install-agent.sh` | 幂等安装(写文件 + 装 timer + enable) |
| `systemd/nexus-hostagent.{service,timer}` | systemd 单元 |
| `agent.env.example` | 配置示例(复制为 agent.env,600) |
