# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 与 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added
- 初始版本:主机指标采集脚本 `report.sh`(内存/磁盘/swap/load,POST 给 newapi-monitor `/internal/host`)。
- 幂等安装脚本 `install-agent.sh` + systemd service/timer(每 60s,oneshot)。
- 支持三种部署:手动安装、Lightsail 启动脚本、黄金快照。
