# Koebumi

[日本語](README.md) | English | [简体中文](README.zh-CN.md)

See it in action on the [website](https://koebumi.github.io) (in Japanese).

Koebumi is a voice input app for macOS. Press the Fn key in any app and speak, and Koebumi types clean text at your cursor, with fillers and self-corrections removed. It focuses on two things: polished written Japanese, and controlling Claude Code and Codex by voice. It is free and open source.

For Japanese, punctuation and spelling follow fixed rules (〜して下さい → 〜してください, 三時 → 3時). Casual speech can be turned into business keigo, and people's names follow the spelling shown on your screen.

You can drive Claude Code and Codex by voice. Say "slash compact" to type /compact, and answer permission prompts with "yes" or "no". End a sentence with "submit" to press Enter as well. File names you say are corrected to the actual names in the working folder.

No API key is required. Without one, Koebumi uses Apple's on-device models and speech models that run on your Mac, so processing happens on your Mac. History, audio and your dictionary are stored only on your Mac.

You can also use the AI you already have: API keys for Claude or OpenAI-compatible services, or your Claude or ChatGPT subscription through Claude Code or Codex.

## Install

Requires an Apple silicon Mac with macOS 26 or later.

1. Download `Koebumi-<version>.zip` from [Releases](https://github.com/koebumi/koebumi/releases/latest) and open it
2. Move Koebumi.app to the Applications folder and open it
3. If macOS says the app was not opened, click Done. Then open System Settings > Privacy & Security, scroll down, and click "Open Anyway" for Koebumi
4. Follow the setup screen: allow microphone and Accessibility access, and change what the Fn (globe) key does

Step 3 is needed only the first time, because the app is not notarized by Apple yet. Koebumi tells you when a new version is available. To polish text with Apple's on-device model, turn on Apple Intelligence.

## Usage

| Action | Default shortcut | What it does |
|---|---|---|
| Dictation | `Fn` | Tap to start hands-free and tap again to finish. Or hold while you speak and release to finish (push-to-talk) |
| Translate | `Fn + Left ⇧` | Types what you said in the target language. Switch the target on the voice bar |
| Ask anything | `Fn + Space` | Select text and say something like "make it more polite" to rewrite it. Questions are answered in a card, and requests like "cat videos on YouTube" open the page |
| Paste last result | `Left ⌥ + Left ⌘ + V` | Types the previous result at the cursor again, when you release all keys |
| Cancel | `Esc` | Stops recording or processing, and closes the answer card |

While holding Fn, add Shift or Space to switch to Translate or Ask without stopping the recording. You can change shortcuts in Settings and assign several shortcuts to one action.

If you speak in Finder (the desktop) with no text field focused, the result is copied to the clipboard instead of being pasted.

## Features

| Feature | What it does |
|---|---|
| Cleanup | Removes fillers, repetitions and self-corrections. Lists become bullet points, and saying "new line" starts a new line |
| Japanese style | Choose the punctuation style and whether to put spaces around English words. Helper verbs are written in hiragana (〜して下さい → 〜してください) |
| Tone per app | Sorts apps into six kinds and lets you pick a tone for each kind, such as business keigo. Apps in the Chat kind get no punctuation by default |
| Claude Code and Codex | Types slash commands, answers permission prompts, fixes file names, and presses Enter when you say "submit" |
| Dictionary | Add words and how speech recognition tends to hear them. Words you fix within a minute after dictating are added automatically |
| Style learning | Every six dictations, learns your formality and phrasing habits. What you said is never stored |
| Translate and Ask | Types a translation of what you said. Also rewrites selected text and answers questions |
| History and stats | Search and reprocess your history and download recordings. Also tracks words spoken and time saved |

The detailed documentation is in [docs/features.md](docs/features.md) (Japanese).

## AI engines

Choose them in Settings > AI engines. Without an API key, Koebumi works with Apple's on-device models.

| Used for | Options |
|---|---|
| Speech recognition | Apple (default), models that run on your Mac (five, including Qwen3-ASR and Whisper), OpenAI, Groq, OpenAI-compatible servers |
| Cleanup, translation, Ask | Apple (default), Claude, Claude subscription (through Claude Code), ChatGPT subscription (through Codex), OpenAI-compatible services (OpenAI, Groq, OpenRouter, Gemini, Ollama and more) |

## Privacy

- History, recordings, your dictionary and learned style are stored only on your Mac. API keys are stored in the Keychain
- If you choose a cloud engine or a subscription engine, the recording or the transcript is sent to the service you chose
- Screen context (the text around your cursor and names or terms shown on screen) is used only when cleanup runs on your Mac by default. Koebumi does not store what it reads
- Koebumi checks GitHub for a new version once a day. You can turn this off in Settings > General

## Limitations

- Apple's on-device model is small, so complex self-corrections, translation and rewriting with Ask are weaker than with Claude and similar models. Cleaning up a long dictation (over 1,000 characters) takes about 10 to 20 seconds
- Subscription engines share the usage limits of Claude Code and Codex. Using a ChatGPT subscription through Codex is not an official integration, so it may stop working if OpenAI changes its policy
- The interface is available in Japanese and English only
- Screen context works only in apps that expose their text through the Accessibility API

More limitations are listed in [docs/features.md](docs/features.md#制限事項) (Japanese).

## Development

Build instructions and developer commands are in [docs/development.md](docs/development.md) (Japanese). Please report bugs and requests in [Issues](https://github.com/koebumi/koebumi/issues).

## License

MIT ([LICENSE](LICENSE)). The licenses of the packages Koebumi uses are included in the app at `Contents/Resources/ThirdPartyLicenses.txt`.
