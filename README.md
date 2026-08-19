# llamacpp-install

一个独立的 Bash 脚本，用于在 Debian、Ubuntu 和 Arch Linux 上从源码编译 CUDA 版 `llama-server`，选择本地 GGUF 模型并部署为 systemd 服务。

整个部署工具只有一个文件：`install.sh`。

## 功能

- 自动识别 Debian、Ubuntu 和 Arch Linux
- 检测 NVIDIA 驱动与 CUDA Toolkit
- 使用 `GGML_CUDA=ON` 从官方源码编译 `llama-server`
- 扫描指定目录并交互式选择本地 GGUF 模型
- 显示模型相对路径及文件大小
- 自定义监听地址、端口、上下文、GPU 层数、线程和并发数
- 支持附加任意 `llama-server` 参数
- 自动选择 `whiptail`、`dialog` 或紧凑纯文本界面
- 统一的紧凑界面：顶栏、操作说明、默认项高亮和清晰的确认提示
- 安装为单一 systemd 服务
- 支持重新选择模型、修改参数、更新、回滚和卸载
- 提供服务管理子菜单：状态、启动、停止、重启、日志和自定义配置
- 更新时只保留当前版本和上一版本
- 卸载时不会删除 GGUF 模型

## 前置条件

- NVIDIA GPU 和可用的 NVIDIA 驱动
- root 或 sudo 权限
- 本地已有至少一个 `.gguf` 模型
- 可访问 GitHub 以获取 llama.cpp 源码

脚本会安装 CMake、Ninja、Git 等编译依赖。如果找不到 `nvcc`，脚本会询问是否从发行版仓库安装 CUDA Toolkit，但不会自动安装或替换 NVIDIA 内核驱动。

## 使用

```bash
chmod +x install.sh
sudo ./install.sh
```

主菜单：

```text
╭─ llama.cpp CUDA 部署  选择操作
│  1  安装 / 重新部署  · CUDA 源码编译
│  2  模型与运行参数   · 选择 GGUF、自定义参数
│  3  更新 llama.cpp    · 编译并保留上一版
│  4  回滚上一版本     · 恢复 previous 构建
│  5  服务状态 / 管理   · 启停、日志与配置
│  6  卸载             · 保留本地模型
│  7  退出
╰─ 选择 [默认 1] ›
```

纯文本模式在交互式终端中使用颜色；设置 `NO_COLOR=1` 可关闭颜色。`whiptail` 和 `dialog` 模式使用统一顶栏、紧凑窗口及一致的中文按钮。

也可以直接指定操作：

```bash
sudo ./install.sh --action install
sudo ./install.sh --action configure
sudo ./install.sh --action update
sudo ./install.sh --action rollback
sudo ./install.sh --action service
sudo ./install.sh --action status
sudo ./install.sh --action uninstall
```

## 服务状态与管理

在主菜单选择“服务状态 / 管理”后，可以执行：

```text
1  查看服务状态
2  启动服务
3  停止服务
4  重启服务
5  查看最近 200 行日志
6  选择模型 / 自定义运行参数
7  返回主菜单
```

状态和日志在 `whiptail` 或 `dialog` 中使用可滚动文本框显示。纯文本模式会直接输出到终端。

`--action service` 打开服务管理子菜单；`--action status` 仍可直接显示服务状态。

## 模型选择

安装或重新配置时，先输入 GGUF 模型目录。脚本会递归扫描该目录三层，并生成选择菜单：

```text
1  Qwen/Qwen3-8B-Q4_K_M.gguf · 5.0 GiB
2  Llama/Llama-8B-Q5_K_M.gguf · 5.7 GiB
3  手动输入 GGUF 文件路径
```

脚本不会复制、移动或删除模型。systemd 服务用户必须能够读取模型文件及其父目录。

## 自定义运行参数

交互界面会逐项询问：

- systemd 服务用户
- 监听地址，默认 `0.0.0.0`
- 监听端口，默认 `80`
- 上下文长度，默认 `4096`
- GPU 层数，支持数字、`auto` 或 `all`
- CPU 线程数
- 并发槽位
- 附加 `llama-server` 参数

附加参数示例：

```text
--flash-attn on --alias "Qwen Local" --no-webui
```

附加参数支持单引号、双引号和反斜线，但不会执行变量展开、命令替换、管道或重定向。模型、地址、端口等已由交互界面管理的参数不能在附加参数中重复覆盖。

## 部署位置

```text
/opt/llama.cpp/releases/       编译版本
/opt/llama.cpp/current         当前版本
/opt/llama.cpp/previous        上一版本
/etc/llama.cpp/install.conf    当前配置
/etc/systemd/system/llama-server.service
```

常用命令：

```bash
systemctl status llama-server
journalctl -u llama-server -f
curl http://127.0.0.1:80/health
```

## 安全说明

默认监听 `0.0.0.0:80`，这会向所有网络接口提供未加密 HTTP 服务。脚本不会修改防火墙。公网部署时建议使用防火墙限制来源，或在前方配置带 TLS 和身份认证的反向代理。

服务以选定的普通用户运行。监听小于 1024 的端口时，systemd 只授予 `CAP_NET_BIND_SERVICE`，不会以 root 身份运行 `llama-server`。

## 脚本测试

内置测试不会检测 Linux、不会安装软件，也不会修改系统：

```bash
bash install.sh --self-test
```

官方参考：

- [llama.cpp CUDA 构建文档](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md#cuda)
- [llama-server 文档](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
