> 当前仓库发布源代码。Windows 可按下方步骤编译并打包为 ZIP；暂未提供 GitHub Release 安装包。


<p align="center">
    <img width="128" src="/assets/logo.png" alt="Simple Live logo">
</p>
<h2 align="center">Simple Live</h2>

<p align="center">
简简单单的看直播
</p>

![浅色模式](/assets/screenshot_light.jpg)

![深色模式](/assets/screenshot_dark.jpg)

## 支持直播平台：

- 虎牙直播

- 斗鱼直播

- 哔哩哔哩直播

- 抖音直播

## APP支持平台

- [x] Android
- [x] iOS
- [x] Windows `BETA`
- [x] MacOS `BETA`
- [x] Linux `BETA`
- [x] Android TV `BETA`

## 项目结构

- `simple_live_core` 项目核心库，实现获取各个网站的信息及弹幕。
- `simple_live_console` 基于simple_live_core的控制台程序。
- `simple_live_app` 基于核心库实现的Flutter APP客户端。
- `simple_live_tv_app` 基于核心库实现的Flutter Android TV客户端。

## 环境

Flutter : `3.44.8`

## Windows 版本

当前 Windows 开发版本：`windows-v1.11.4-20260927`（对应应用版本 `1.11.4+11104`）。

- 支持虎牙、斗鱼、哔哩哔哩和抖音直播。
- 搜索入口可在应用内打开各平台网页；进入可识别的直播间后，可选择用 Simple Live 播放器打开。
- 分类区域展示各平台分类；抖音分类数据读取已针对当前网页格式修复。
- 支持窗口关闭后留在系统托盘，以及播放器快捷键和音量调节。

在 Windows 上安装 Flutter 3.44.8 和 Windows 桌面开发工具后，进入 `simple_live_app` 目录执行：

```powershell
flutter pub get
flutter build windows --release
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath SimpleLive-Windows-x64.zip
```

运行程序时须保留 ZIP 内的 EXE、DLL 和 `data` 目录。各平台网页和接口可能调整；当前版本尚未完成所有平台的实机验收。

## 参考及引用

[AllLive](https://github.com/xiaoyaocz/AllLive) `本项目的C#版，有兴趣可以看看`

[dart_tars_protocol](https://github.com/xiaoyaocz/dart_tars_protocol.git)

[wbt5/real-url](https://github.com/wbt5/real-url)

[lovelyyoshino/Bilibili-Live-API](https://github.com/lovelyyoshino/Bilibili-Live-API/blob/master/API.WebSocket.md)

[IsoaSFlus/danmaku](https://github.com/IsoaSFlus/danmaku)

[BacooTang/huya-danmu](https://github.com/BacooTang/huya-danmu)

[TarsCloud/Tars](https://github.com/TarsCloud/Tars)

[YunzhiYike/douyin-live](https://github.com/YunzhiYike/douyin-live)

[5ime/Tiktok_Signature](https://github.com/5ime/Tiktok_Signature)

## 声明

本项目的所有功能都是基于互联网上公开的资料开发，无任何破解、逆向工程等行为。

本项目仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关。

如果本项目存在侵犯您的合法权益的情况，请及时与开发者联系，开发者将会及时删除有关内容。

## Star History

<a href="https://www.star-history.com/#xiaoyaocz/dart_simple_live&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=xiaoyaocz/dart_simple_live&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=xiaoyaocz/dart_simple_live&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=xiaoyaocz/dart_simple_live&type=Date" />
 </picture>
</a>
