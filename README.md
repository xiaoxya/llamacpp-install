# llama.cpp Server 一键部署脚本

这是面向 Debian、Ubuntu 和 Arch Linux 的交互式部署工具框架，用于从源码编译 CUDA 版 `llama-server`，并部署一个本地 GGUF 模型作为单一 systemd 服务。

> 当前状态：框架预览版。交互、检测、配置校验、部署阶段和服务模板已经定义，但依赖安装、源码编译和系统文件写入尚未启用，因此运行不会修改系统。

## 已确认的部署约束

- 从 llama.cpp 官方源码编译
- NVIDIA GPU 与 CUDA 后端
- 单模型、单 systemd 服务
- 监听 `0.0.0.0:80`
- 只使用本地 GGUF，不下载模型
- 更新时保留上一个版本用于回滚
- 自动选择 `whiptail`、`dialog` 或纯文本界面
- 自动检测 NVIDIA/CUDA，最终由用户确认

## 预期用法

```bash
chmod +x install.sh tests/*.sh
sudo ./install.sh
```

查看非交互式计划：

```bash
sudo ./install.sh --dry-run --ui text --action install
```

## 部署布局

```text
/opt/llama.cpp/releases/<ref>/   独立构建版本
/opt/llama.cpp/current           当前版本软链接
/etc/llama.cpp/server.env        运行参数
/var/lib/llama.cpp/models/       本地 GGUF 模型
/var/lib/llama.cpp/install.state 安装状态
```

`llama-server` 将以专用的 `llama` 用户运行。systemd 仅授予 `CAP_NET_BIND_SERVICE`，使非 root 进程可以监听 80 端口。

模型不会被重复复制；正式实现会验证 `llama` 用户对所选 GGUF 文件及其父目录具有读取/遍历权限。由于服务启用了 `ProtectHome=true`，模型不应放在 `/home`、`/root` 或 `/run/user` 下，推荐放入 `/var/lib/llama.cpp/models/` 或独立的数据盘目录。

## 安全提示

`0.0.0.0:80` 会向所有网络接口开放未加密的 HTTP 服务。正式实现不会自动修改防火墙；如服务器可从公网访问，应在前方配置带 TLS 和身份认证的反向代理，或用防火墙限制来源地址。

## 开发阶段

1. 框架与交互确认
2. Debian/Ubuntu、Arch 依赖适配
3. CUDA 预检和源码编译
4. systemd 安装、健康检查与回滚
5. 虚拟机/容器中的发行版测试

基础测试：

```bash
bash tests/run.sh
```
