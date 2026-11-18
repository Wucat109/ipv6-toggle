# IPv6 Toggle：Linux IPv6 临时开关

## 服务器一键运行

复制下面这一行，在服务器终端执行，即可打开菜单，选择开启、关闭或查看 IPv6 状态：

    curl -fsSL https://raw.githubusercontent.com/Wucat109/ipv6-toggle/main/ipv6-toggle.sh -o ipv6-toggle.sh && sudo bash ipv6-toggle.sh

如果已经用 `root` 登录，去掉命令里的 `sudo` 即可。脚本会下载到当前目录；如果想先检查内容，可以只执行 `&&` 前面的下载命令。

> **远程操作提醒：**如果你正通过 IPv6 登录 SSH，关闭 IPv6 会断开连接。请先用 IPv4 登录，或确认能通过服务商的网页控制台重新进入服务器。

## 脚本能做什么

脚本会自动识别 Linux 发行版、系统版本和内核版本，再检查是否存在可用的 IPv6 运行时开关。支持的发行版统一使用 Linux 内核接口操作，不需要修改 Netplan、NetworkManager 或其他网络配置文件。

关闭或开启时，脚本会同时设置当前网卡（包括回环接口 `lo`）和新建网卡的内核默认值，并在写入后核对状态。修改只在运行时生效，不会写入配置文件；重启后以系统原有配置为准。

## 命令行用法

下载后，也可以直接指定操作，不进入菜单：

    sudo bash ipv6-toggle.sh off      # 临时关闭 IPv6
    sudo bash ipv6-toggle.sh on       # 临时开启 IPv6
    sudo bash ipv6-toggle.sh toggle   # 自动切换
    bash ipv6-toggle.sh status       # 查看状态，无需 sudo
    bash ipv6-toggle.sh --help       # 查看帮助

`toggle` 会根据当前网卡状态切换：全部开启就关闭，全部关闭就开启。如果部分网卡开启、部分关闭，脚本不会猜测，请明确执行 `on` 或 `off`。

## 支持的系统

| Linux 发行版 | 支持版本 |
| --- | --- |
| Debian | 11、12、13 |
| Ubuntu | 20.04、22.04、24.04、26.04 |
| RHEL、Rocky Linux、AlmaLinux、Oracle Linux | 8、9、10 |
| CentOS / CentOS Stream | 8、9、10 |

脚本需要 Bash；上面的一键下载命令还需要 `curl`。不在支持列表中的系统或版本不会被修改。部分容器或受限 VPS 即使用 `root` 登录，也可能不允许写入内核参数。

## 常见问题

**开启后，为什么还是没有公网 IPv6 地址？**  
`on` 只是开启网卡的 IPv6 功能，不会自动分配公网地址。能否获得地址，还取决于服务商是否提供 IPv6，以及服务器的网络配置是否正确。

**如果提示找不到 IPv6 运行时开关，怎么办？**  
IPv6 可能已通过内核启动参数 `ipv6.disable=1` 禁用，或者当前环境没有提供对应的内核接口。脚本会退出，不会修改引导配置。

**关闭 IPv6 后，怎样重新开启？**  
建议保留下载好的 `ipv6-toggle.sh`。之后直接运行 `sudo bash ipv6-toggle.sh on`，无需再次访问 GitHub。
