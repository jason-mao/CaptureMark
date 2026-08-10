# Changelog

本项目的版本号遵循 [Semantic Versioning](https://semver.org/)。

## [1.3.0] - 2026-08-11

### Added

- 使用全局快捷键完成框选后，立即把原始截图复制到剪贴板
- 菜单栏和应用菜单新增快捷键设置，可从多组快捷键中选择并持久保存
- 箭头支持独立调整大小、边框开关和边框颜色
- 新增 CaptureMark 个性化 macOS App 图标

### Changed

- 大小和边框工具会根据文字或箭头工具自动切换配置范围
- 箭头边框默认关闭，不再强制绘制黑白双层外缘

## [1.2.0] - 2026-08-08

### Added

- 输入文字时可点击编辑框外部直接确认
- 在“选择”或“文字”工具下双击已确认文字可重新编辑

### Changed

- 切换工具时会确认正在输入的文字，不再将其丢弃

## [1.1.0] - 2026-08-08

### Added

- 新增可开关的文字描边配置，默认关闭
- 支持单独选择文字描边颜色

### Changed

- 全局框选截图快捷键由 `⌘⇧2` 调整为 `⌘⇧6`
- 文字不再强制添加黑白双层描边

## [1.0.0] - 2026-08-08

### Added

- 多显示器框选截图和全局快捷键 `⌘⇧2`
- 文字标注、颜色与字号调整
- 箭头绘制与标注选择
- 撤销、重做、复制和 PNG 导出
- 菜单栏常驻与屏幕录制权限引导
- 通用 macOS App 的 Release 自动构建

[1.3.0]: https://github.com/jason-mao/CaptureMark/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/jason-mao/CaptureMark/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/jason-mao/CaptureMark/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jason-mao/CaptureMark/releases/tag/v1.0.0
