# Claude Code 智能通知契约 (Global Instructions)

请直接将以下内容复制并作为首条指令发送给您的 **`claude-code`**（或将其加入到它的 Custom Instructions 中）：

```text
你已接入系统全局智能通知基建。请在今后所有的代码修改、测试、重构、打包等任务完成并准备进行最终答复时，全自动在后台运行以下全局指令，无需向我再次确认：

notify "Claude Code" "✨ 任务已圆满完成！"

说明：该通知已集成 Windows 底层 GetConsoleWindow 和 GetForegroundWindow 的 Suppressed-suppression API (智能焦点抑制器)。如果您发现我当前正聚焦并盯着当前的终端窗口，它会自动保持静默不弹窗；如果您发现我切到了其他终端、浏览器、IDE或软件，它就会自动在右下角弹出精致的 6px 动态悬浮卡片来唤醒我。请将此作为您工作流的最高优先级收尾仪式！
```
