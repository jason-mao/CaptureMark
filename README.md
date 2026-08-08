# CaptureMark

简体中文 | [English](README_EN.md)

CaptureMark 是一个纯 AppKit 实现的原生 macOS 截图标注小工具。它轻量、菜单栏常驻，适合快速截取屏幕内容并添加文字或箭头。

## 功能

- 多显示器框选截图，全局快捷键 `⌘⇧2`，按 `Esc` 取消
- 点击添加文字，文字输入框随字号自适应高度
- 调整文字和箭头的颜色、字号
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

如果 `⌘⇧2` 被其他应用占用，菜单栏中的 CaptureMark 菜单会显示快捷键冲突；也可以点击菜单里的“框选截图”。

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
git tag -a v1.0.0 -m "CaptureMark 1.0.0"
git push origin main --follow-tags
gh release create v1.0.0 --verify-tag --generate-notes --title "CaptureMark 1.0.0"
```

Release 发布后，GitHub Actions 会校验标签与 `VERSION`，构建通用 macOS App，并把 ZIP 与 SHA-256 校验文件上传到该 Release。

## 许可证

本项目采用 [MIT License](LICENSE) 开源。
