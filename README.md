# CaptureMark

简体中文 | [English](README_EN.md)

CaptureMark 是一个纯 AppKit 实现的原生 macOS 截图标注小工具。它轻量、菜单栏常驻，适合快速截取屏幕内容并添加文字或箭头。

<img src="Resources/AppIcon.png" alt="CaptureMark App 图标" width="128">

## 功能

- 多显示器框选截图，默认全局快捷键 `⌘⇧6`，按 `Esc` 取消
- 使用全局快捷键框选完成后自动复制原图，可直接粘贴到其他应用，也可继续标注
- 从菜单栏的“截图快捷键”子菜单切换快捷键；设置会自动保存
- 点击添加文字，文字输入框随字号自适应高度
- 输入完成后按 Return 或点击编辑框外部即可确认
- 使用“选择”或“文字”工具双击已确认文字可重新编辑
- 调整文字和箭头的颜色与大小
- 文字和箭头边框默认关闭，可分别开关并选择边框颜色
- 拖拽绘制箭头
- 选择、删除标注以及撤销/重做
- 将合成图片复制到剪贴板
- 按原截图分辨率导出 PNG

## 下载与使用

从 [GitHub Releases](https://github.com/jason-mao/CaptureMark/releases) 下载最新的 `macOS-universal.zip`，解压后打开 `CaptureMark.app`。

首次截图时，macOS 会要求“屏幕录制”权限：

1. 打开“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”。
2. 允许 CaptureMark 录制屏幕。
3. 完全退出并重新打开 CaptureMark。

CaptureMark 默认注册 `⌘⇧6`，不会禁用系统的 `⌘⇧3`、`⌘⇧4` 和 `⌘⇧5` 截图功能。可从菜单栏 CaptureMark 图标的“截图快捷键”子菜单切换组合；如果新组合已被占用，CaptureMark 会保留原来的快捷键并提示冲突。

注意：在带 Touch Bar 的旧款 Mac 上，macOS 默认使用 `⌘⇧6` 截取 Touch Bar。可在 CaptureMark 的“截图快捷键”子菜单中直接改用其他组合。

Release 中的 App 使用临时签名，尚未进行 Apple Developer ID 签名和公证。macOS 首次阻止打开时，可在 Finder 中右键 App 后选择“打开”。每次更换或重建 App 后，系统可能要求重新授予屏幕录制权限。

## 本地开发

要求 macOS 13 或更高版本，以及 Xcode 15 / Swift 5.10 或更高版本。

```bash
git clone https://github.com/jason-mao/CaptureMark.git
cd CaptureMark
swift run CaptureMark
```

打包当前架构的 `.app`：

```bash
./Scripts/package_app.sh release
open dist/CaptureMark.app
```

打包同时支持 Apple Silicon 和 Intel 的通用 `.app`：

```bash
CAPTUREMARK_UNIVERSAL=1 ./Scripts/package_app.sh release
```

## 版本与发布

项目遵循 [Semantic Versioning](https://semver.org/)。`VERSION` 是唯一版本来源，Git 标签使用对应的 `vMAJOR.MINOR.PATCH` 格式。

发布步骤：

```bash
# 先更新 VERSION 和 CHANGELOG.md，然后提交
version="$(tr -d '[:space:]' < VERSION)"
git tag -a "v$version" -m "CaptureMark $version"
git push origin main --follow-tags
gh release create "v$version" --verify-tag --generate-notes --title "CaptureMark $version"
```

Release 发布后，GitHub Actions 会校验标签与 `VERSION`，构建通用 macOS App，并把 ZIP 与 SHA-256 校验文件上传到该 Release。

## 许可证

本项目采用 [MIT License](LICENSE) 开源。
