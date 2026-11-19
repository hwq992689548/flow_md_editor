# Flow MD Editor

本地优先的 Markdown 编辑 App（Flutter / macOS）。交互参考 FlowMD 就地预览。

## 运行

```bash
cd /Users/feixiang/Desktop/study/flow_md_editor
flutter pub get
flutter run -d macos
```

## 本版已实现（首期 MVP）

- 三种模式：实时预览 / 阅读 / 源码（记住上次选择）
- 打开、新建、保存、另存为、从磁盘重新载入
- CommonMark + GFM 基础渲染（`flutter_markdown`）
- 任务列表点击写回 `[ ]` / `[x]`（实时预览）
- 代码块语法高亮 + 复制
- Cmd+F 查找（匹配数）、替换；Cmd+G / Shift+Cmd+G
- 字数统计、正文宽度、自动换行、跟随系统浅色/深色
- 导出单文件 HTML（内嵌基础样式）
- 本地图片相对路径显示；外链图片默认不自动加载
- 快捷键：⌘N/O/S、⌘B/I

## 尚未完成（相对 PRD P0）

- 表格交互加行/列、删行/列
- KaTeX 离线公式
- Mermaid 流程图 / 时序图
- YAML front matter 属性面板
- 粘贴截图写入 `assets/`
- 脚注 / 标题锚点跳转
- 更完善的 IME 与块模型边界、撤销栈细化

这些可继续在本地迭代，不使用云端代理。
