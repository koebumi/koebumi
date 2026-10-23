# Koebumi

[日本語](README.md) | [English](README.en.md) | 简体中文

可以在[网站](https://koebumi.github.io)（日语）上看到实际演示。

Koebumi 是一款 macOS 语音输入应用。在任何应用中按下 Fn 键说话，Koebumi 会去掉口头禅和改口，把整理好的文字输入到光标位置。它特别注重两点：把日语整理成规范的书面语，以及用语音操作 Claude Code 和 Codex。Koebumi 免费，并且开源。

对于日语，标点和用字按固定规则统一（〜して下さい → 〜してください，三時 → 3時）。即使说得很随意，也可以改写成商务敬语；人名会按照屏幕上显示的写法输入。

可以用语音操作 Claude Code 和 Codex。用英语说 "slash compact" 会输入 /compact；遇到权限确认时，可以用 "yes" 或 "no" 回答。在句末说 "submit"，会连 Enter 键一起按下。说出的文件名会被改成工作文件夹中的实际写法。

不需要 API 密钥也能使用。没有密钥时，Koebumi 使用 Apple 的设备端模型和在这台 Mac 上运行的语音识别模型，处理都在这台 Mac 上进行。历史记录、录音和词典只保存在这台 Mac 上。

也可以使用你已有的 AI：Claude 或 OpenAI 兼容服务的 API 密钥，或者通过 Claude Code、Codex 使用 Claude 或 ChatGPT 的订阅。

## 安装

需要搭载 Apple 芯片、运行 macOS 26 或更高版本的 Mac。

1. 从 [Releases](https://github.com/koebumi/koebumi/releases/latest) 下载 `Koebumi-<版本>.zip` 并打开
2. 把解压出来的 Koebumi.app 放进"应用程序"文件夹，然后打开
3. 如果系统提示未能打开，点击"完成"。然后打开"系统设置 > 隐私与安全性"，在下方找到 Koebumi，点击"仍要打开"
4. 按照设置界面的提示，允许麦克风和辅助功能权限，并更改按下 Fn（地球仪）键时的操作

第 3 步只在第一次需要，因为应用还没有经过 Apple 公证。有新版本时，Koebumi 会提示你。如果要用 Apple 的设备端模型整理文字，请打开 Apple 智能（Apple Intelligence）。

## 使用方法

| 操作 | 默认快捷键 | 说明 |
|---|---|---|
| 听写 | `Fn` | 短按开始免手持录音，再按一次结束。也可以按住说话，松开时结束（按住说话） |
| 翻译 | `Fn + Left ⇧` | 把说的话翻译成目标语言后输入。目标语言可以在语音栏中切换 |
| Ask anything | `Fn + Space` | 选中文字后说"更礼貌一些"之类的指令即可改写。提问会在卡片中回答；"在 YouTube 上看猫的视频"之类的请求会打开网页 |
| 粘贴上一次的结果 | `Left ⌥ + Left ⌘ + V` | 在光标位置再次输入上一次的结果。松开所有按键时粘贴 |
| 取消 | `Esc` | 停止录音或处理，并关闭回答卡片 |

按住 Fn 说话时再按 Shift 或 Space，可以在不中断录音的情况下切换到翻译或 Ask。快捷键可以在设置中更改，一个操作可以设置多个快捷键。

在访达（桌面）中没有选中输入框时说话，结果会复制到剪贴板，而不会粘贴。

## 功能

| 功能 | 说明 |
|---|---|
| 整理 | 去掉口头禅、重复和改口。列举的内容会整理成列表，说 "new line" 会换行 |
| 日语书写 | 可以选择标点的样式，以及英文单词前后是否加空格。补助动词用平假名书写（〜して下さい → 〜してください） |
| 按应用调整语气 | 把输入目标应用分成 6 类，可以为每一类选择语气，例如商务敬语。归为聊天类的应用默认不加标点 |
| Claude Code・Codex | 支持输入斜杠命令、回答权限确认、修正文件名，以及说 "submit" 时按下 Enter |
| 词典 | 可以登记单词以及它容易被听成的样子。输入后 1 分钟内修改的单词会自动加入词典（主要针对日语和英语的修改） |
| 文体学习 | 每说 6 次，学习一次礼貌程度和用词习惯。不会保存说话的内容本身 |
| 翻译・Ask | 把说的话翻译后输入。也可以改写选中的文字，或者回答问题 |
| 历史・统计 | 可以搜索和重新处理历史记录，下载录音。还会记录说话的字数和节省的时间 |

详细说明见 [docs/features.md](docs/features.md)（日语）。

## AI 引擎

在 Settings > AI engines 中选择（界面语言为日语和英语）。没有 API 密钥时，也可以使用 Apple 的设备端模型。

| 用途 | 可选项 |
|---|---|
| 语音识别 | Apple（默认）、在这台 Mac 上运行的模型（Qwen3-ASR、Whisper 等 5 种）、OpenAI、Groq、OpenAI 兼容的服务器 |
| 整理、翻译、Ask | Apple（默认）、Claude、Claude 订阅（通过 Claude Code）、ChatGPT 订阅（通过 Codex）、OpenAI 兼容服务（OpenAI、Groq、OpenRouter、Gemini、Ollama 等） |

## 隐私

- 历史记录、录音、词典和学习到的文体只保存在这台 Mac 上。API 密钥保存在钥匙串中
- 选择云端引擎或订阅引擎时，录音或转写出的文字会发送到你选择的服务
- 屏幕上下文（光标前后的文字，以及屏幕上的人名和用语）默认只在这台 Mac 上整理文字时使用。读取的内容不会保存
- Koebumi 每天访问一次 GitHub，检查是否有新版本。可以在 Settings > General 中关闭

## 主要限制

- Apple 的设备端模型较小，在复杂的改口、翻译和用 Ask 改写方面不如 Claude 等模型。整理 1,000 字以上的长段语音需要 10 到 20 秒左右
- 订阅引擎与 Claude Code、Codex 共用使用额度。通过 Codex 使用 ChatGPT 订阅并非官方集成，如果 OpenAI 改变政策，可能无法继续使用
- 界面语言只有日语和英语
- 屏幕上下文只能在通过辅助功能 API 公开文字的应用中使用

更多限制见 [docs/features.md](docs/features.md#制限事項)（日语）。

## 开发

从源码构建的方法和开发用命令见 [docs/development.md](docs/development.md)（日语）。问题和建议请提交到 [Issues](https://github.com/koebumi/koebumi/issues)。

## 许可证

MIT（[LICENSE](LICENSE)）。Koebumi 所用软件包的许可证文本包含在应用的 `Contents/Resources/ThirdPartyLicenses.txt` 中。
