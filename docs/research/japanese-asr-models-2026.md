# 日本語を書き起こせる新しい音声認識モデル（2026 年 5 月以降）

調査日: 2026-11-01。一次情報だけを根拠にした。一次情報とは、Hugging Face（HF）の公式リポジトリのモデルカード（README）と HF の API が返すリポジトリの情報（作成日・ライセンス欄・ファイルの大きさ・パラメータ数・コミット）、公式 GitHub のソースと文書、作者による arXiv の論文、各社の API の公式ドキュメントと変更履歴を指す。第三者の記事・まとめ・SNS は、今回は手がかりとしても使っていない。新しいモデルは HF の API の検索（音声認識のタグと日本語のタグ、作成日順と人気順）で洗い出した。

各主張に「確認」か「推測」を付けた。
- 確認: 一次情報の該当箇所を読んで確かめた。
- 推測: 読んだ内容からの推論で、直接は確かめていない。

読み方の注意。
- モデルカードと GitHub の README は、生の Markdown を取得して読んだ。引用は原文どおり。
- OpenAI、Google、Mistral、Groq のドキュメントは、HTML を取得して文字だけを取り出して読んだ。表の列の対応が崩れている可能性がある。arXiv の論文は HTML 版から文字を取り出した。
- 一部のベンチマークは、モデルカードの中で画像の表やグラフとしてしか公開されていない（IBM の Granite と Third Intelligence の Haas）。その画像だけを取得して目で読んだ。数値の読み違いの可能性がある。該当する数値には「画像」と書いた。
- Haas のモデルカードの比較表は、Third Intelligence が自社の基準（asr-ja-bench v1.1 と jacer の正規化）で他社のモデルも測った結果である。測定の一次情報としては使えるが、各社の公称値ではない。異なる出典の CER は、正規化もデータも違うので、そのままは比べられない。
- モデルの重みはダウンロードしていない。ダウンロードの大きさは、HF の API が返すリポジトリのファイルの大きさの合計（説明用の画像なども含む）。

読んだコミットは次のとおり。外部のリポジトリは新しい一時ディレクトリに shallow clone し、読むだけにした（実行もビルドもしていない）。

| 対象 | SHA |
|---|---|
| speech-swift（Koebumi が固定している版。`.build/checkouts/speech-swift`、2026-10-18） | `3f58a58a8f867a4c87b97dbf4d6050d6a88ef665` |
| speech-swift（upstream の最新、2026-10-31） | `a57702e6f523fa36ac5532d2bdc5f35f701a052c` |
| facebookresearch/omnilingual-asr | `81f51e224ce9e74b02cc2a3eaf21b2d91d743455` |
| third-intelligence/Haas-ASR | `acc614f68769dcbfae9dba96b48439c4a66295af` |
| nyosegawa/speech.cpp（文書だけを GitHub の API で取得。v0.10.0 の後） | `06590811a90041f935a470ba0e2b85346d2fc041` |
| Koebumi（このリポジトリ） | `cdc537b5b837190d45c43d17ccd95a9ea081bf76` |

読んだ HF のモデルカードのコミットは次のとおり。

| リポジトリ | SHA | 最終更新 |
|---|---|---|
| nvidia/nemotron-3.5-asr-streaming-0.6b | `ea30d66debe3740a08b573244286791d423d6b3e` | 2026-09-10 |
| nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B | `c17667641642c4265ff2b7037dd101b7d4567634` | 2026-10-29 |
| ibm-granite/granite-speech-5.0-470m-turboctc | `1dd23f46f6d4e6eae2531982ba2e33220086dd97` | 2026-10-21 |
| ibm-granite/granite-speech-5.0-2b | `c684620bb54fc89d14ba27256b23bbc9e09ba764` | 2026-10-26 |
| third-intelligence/Haas-ja-v1.0 | `660728d39019e5e065046154beca44ac9a66a540` | 2026-10-30 |
| microsoft/VibeVoice-ASR-Streaming-1.5B | `4262d23d8a539a6530cf64fbd0b1751ef9a30853` | 2026-09-03 |
| microsoft/VibeVoice-ASR-Streaming-7B | `60d858b518b4e19d404af3737f848fc185b30177` | 2026-09-03 |
| netease-youdao/Confucius4-R2T2 | `185ce639118ad1362d049ca0d8ed04b6ec5cd6c9` | 2026-09-17 |
| Edge0/ARK-ASR-0.6B | `45776b56d58cdfb2e2eb632f7e110f38684633e0` | 2026-06-27 |
| Edge0/Audio8-ASR-0.1B | `8487da63d581fa4fc9b5c60444cb57c3a523d7aa` | 2026-07-15 |
| moonshine-ai/moonshine-streaming-tiny-ja | `a82871d17fede2efad4540d4a32eabb515fea5fa` | 2026-08-24 |
| ayousanz/kodama-ja-streaming-small | `71287e980fff51b1d185c9ab93d5597766aa4e05` | 2026-08-22 |
| hshispeech/Ruby-ASR-1.7B | `22839f9416eeb4bf993e3f315d84cac33ab27a6f` | 2026-09-24 |
| sbintuitions/hikari-medium | `b59fda0d59f4d8c211687dee08748b31b3d2c411` | 2026-10-26 |
| sbintuitions/kana-whisper | `88ecb3d79c5846cb4fcf76f4107b84c8fa2acd82` | 2026-06-29 |
| nvidia/nemotron-labs-unified-asr-0.6b | `023ce907267a09a308a5cb69239447cb3d0c1597` | 2026-10-27 |
| nvidia/parakeet-tdt_ctc-0.6b-ja（比較用） | `44edb27eea9317daf89333e75eb830db4b1cc298` | 2025-02-18 |
| kotoba-tech/kotoba-whisper-v2.0（比較用） | `7eb575277d18909a4af8a24e3ae8cce2e99794ae` | 2024-10-23 |
| kotoba-tech/kotoba-whisper-v2.2（比較用） | `9d33482a0eb9b57f1ad80708e8ac5538246d8355` | 2024-10-23 |
| reazon-research/japanese-zipformer-base-k2-rs35kh（比較用） | `df19e126d86994fb72a0a3653fcb31ebe49e6081` | 2025-10-20 |
| mistralai/Voxtral-Mini-4B-Realtime-2602（比較用） | `2769294da9567371363522aac9bbcfdd19447add` | 2026-03-11 |
| FunAudioLLM/Fun-ASR-Nano-2512（比較用） | `272c57b82523ada6fd87095e955f8e29100979ab` | 2026-06-20 |

## 1. 要約

- 2026 年 5 月以降に出た、日本語を書き起こせるオープンなモデルの主なものは、NVIDIA の Nemotron 3.5 ASR Streaming 0.6B（6 月）と Nemotron 3.5 Transcribe 30B-A4B（10 月）、IBM の Granite Speech 5.0 470M TurboCTC と 2B（10 月）、Third Intelligence の Haas-ja-v1.0（10 月、日本語専用）、Microsoft の VibeVoice-ASR-Streaming 1.5B と 7B（9 月）、NetEase Youdao の Confucius4-R2T2（9 月）、AutoArk の ARK-ASR（5〜6 月）。ほかに小さな日本語専用のモデル（Moonshine Streaming Tiny ja、kodama-ja-streaming-small）がある（確認）。
- speech-swift で今すぐ動くのは、このうち Nemotron 3.5 ASR Streaming だけ。固定中の SHA にもモジュール（`NemotronStreamingASR`）と aufklarer の変換済みの重み（CoreML INT8、MLX INT5・INT8）がある。日本語（`ja-JP`）、句読点、言語の自動判定、320 ms ごとのストリーミングに対応し、CoreML 版は語彙のブーストもできる（確認）。ほかの新しいモデルは、speech-swift の固定版にも最新版にも対応がない（確認）。
- 日本語の正確さを同じ物差しで比べた表は、Haas のモデルカードにある（5 つの日本語データセット、文字誤り率の加重平均）。公開モデルでは Haas 6.12、Nemotron 3.5 Transcribe 6.89、Whisper large-v3 7.22、NVIDIA の Parakeet ja 7.23、Granite TurboCTC 7.23、Qwen3-ASR 1.7B 7.59、Qwen3-ASR 0.6B 9.77、Cohere Transcribe 12.35（確認、画像）。Nemotron 3.5 ASR Streaming はこの表に入っていない。NVIDIA の公表値は FLEURS の日本語で CER 12.22（320 ms、言語を指定）で、Qwen3-ASR 1.7B よりは不正確と思われる（推測: 出典の違う数値からの推論）。
- アプリの Qwen3-ASR は 4bit の重みを使っている。speech-swift の測定では、FLEURS の日本語の CER が 4bit で 16.11、8bit で 8.64 と大きく違う（確認。表にモデルのサイズの記載はない）。aufklarer は 2026-06-21 に 5bit の重みも出した（確認）。
- クラウドでは、OpenAI が 2026-05-07 に gpt-realtime-whisper、2026-07-28 に gpt-transcribe と gpt-live-transcribe を出した。2026-08-26 に whisper-1、gpt-4o-transcribe、gpt-4o-mini-transcribe、gpt-4o-transcribe-diarize の廃止を予告し、2027-02-26 に止まる（確認）。Koebumi の OpenAI の既定は gpt-4o-transcribe なので、移行が要る（確認: `Sources/Koebumi/Core/Models.swift` L203）。Groq は 2026-11-01 時点でも whisper-large-v3 と whisper-large-v3-turbo だけで、新しい書き起こしモデルはない（確認）。
- speech.cpp（nyosegawa、MIT、2026-09-29 公開）は、ggml の上で Metal を使って音声認識を動かす C/C++ の実行環境。Haas-ja-v1.0、Parakeet TDT-CTC 0.6B ja、ReazonSpeech v2、Qwen3-ASR を Apple Silicon の Mac で動かせる。Haas の公式の Python パッケージは macOS に対応しないが、speech.cpp は M5 の Metal で Haas を動かし、FLEURS の日本語で CER 4.39% と書いている（確認: speech.cpp の文書）。詳しくは 3.14。

Koebumi に追加する候補の上位 3 つ。speech.cpp を見つけたあとで、順位を付け直した（推測を含む）。

1. **Haas-ja-v1.0（Third Intelligence）を speech.cpp で動かす**。Apache 2.0。公開モデルで日本語が一番正確（Haas の表で CER 6.12、OpenAI の GPT-Transcribe の 6.07 とほぼ同じ）。speech.cpp の文書では、句読点が付き、表記と読みを組にした語彙を指定でき、M5 での遅延の p50 は 0.042 秒（Qwen3-ASR 0.6B は 0.107 秒）。Q8_0 のファイルは 0.66 GB、ピークのメモリは 0.74 GiB。ただし実行環境が speech-swift と別になり、speech.cpp は公開から 1 か月の若いプロジェクト（確認と推測）。
2. **Nemotron 3.5 ASR Streaming 0.6B（NVIDIA）**。固定中の speech-swift で今すぐ動く唯一の新しい日本語モデル。aufklarer の重みは 565 MB（MLX INT5）か 642 MB（CoreML INT8）。320 ms ごとに文字を出す本物のストリーミングで、句読点が付き、CoreML 版は辞書の語をブーストできる。ライセンスは OpenMDW-1.1 で商用に使える。日本語の CER は FLEURS で約 12 と Qwen3-ASR 1.7B より劣る見込みなので、まずライブ書き起こし（録音中の途中の文字）用に試すのがよい（推測を含む）。
3. **Granite Speech 5.0 470M TurboCTC（IBM）**。Apache 2.0。Haas の表で日本語の CER 7.23 と、Qwen3-ASR 1.7B（7.59）より正確で、0.6B（9.77）よりかなり正確。非自己回帰の CTC で、同じ表の速さ（H200 で RTFx 4,963）は公開モデルで一番速い。句読点も付く。ただし speech-swift にも speech.cpp にも対応がなく、Swift への移植（MLX か CoreML）が要る（確認と推測）。

新しいモデルの追加ではないが、すぐできる改善が 2 つある。
- OpenAI の既定を gpt-transcribe に替える。期限は 2027-02-26。gpt-transcribe には `keywords` があり、辞書の語を渡せる（確認）。
- Qwen3-ASR を 4bit から 5bit か 8bit に替える。repo の名前を替えるだけで、日本語の CER が大きく下がる見込み（推測: speech-swift の FLEURS の測定から）。

## 2. 比較表

### 2.1 基本の情報

| モデル | 組織 | 公開 | ライセンス（商用） | パラメータ | 日本語 |
|---|---|---|---|---|---|
| Nemotron 3.5 ASR Streaming 0.6B | NVIDIA | 2026-06-04 | OpenMDW-1.1（可） | 約 0.6B | 対応（すぐ使える 19 ロケールの 1 つ） |
| Nemotron 3.5 Transcribe 30B-A4B | NVIDIA | 2026-10-28 | OpenMDW-1.1（可） | 34B（動くのは 4.3B） | 対応（Production-ready） |
| Granite Speech 5.0 470M TurboCTC | IBM | 2026-10-21（多言語版） | Apache 2.0（可） | 473M | 対応 |
| Granite Speech 5.0 2B | IBM | 2026-10-20 | Apache 2.0（可） | 2.3B | 対応 |
| Haas-ja-v1.0 | Third Intelligence | 2026-10-08（HF の作成日） | Apache 2.0（可） | 615.8M | 日本語専用 |
| VibeVoice-ASR-Streaming 1.5B / 7B | Microsoft | 2026-09-02 | MIT（可） | 2.8B / 8.7B（HF の値） | 対応（10 言語） |
| Confucius4-R2T2 | NetEase Youdao | 2026-09-10（HF の作成日） | NetEase の独自ライセンス（大企業は別契約） | 2.0B | 主は中国語と英語。日本語は副次的 |
| ARK-ASR 0.6B / 3B | AutoArk（HF は Edge0） | 2026-05-25 / 2026-06-22 | Apache 2.0（可） | 1.3B / 4.1B（HF の値） | 対応（19 言語） |
| Audio8-ASR-0.1B | AutoArk（HF は Edge0） | 2026-07-10 | CC-BY-NC-4.0（不可） | 0.32B | 対応（7 言語） |
| Moonshine Streaming Tiny ja | Moonshine AI | 2026-08-24 | MIT（可） | 27M | 日本語専用 |
| kodama-ja-streaming-small | 個人（ayousanz） | 2026-08-22 | Apache 2.0（可） | 140M | 日本語専用 |
| （アプリにある）Qwen3-ASR 0.6B / 1.7B | Qwen | 2026-01（論文） | Apache 2.0（可） | 0.6B / 1.7B | 対応 |
| （比較）Parakeet TDT-CTC 0.6B ja | NVIDIA | 2024-05 | CC-BY-4.0（可、表示が要る） | 0.6B | 日本語専用 |
| （比較）kotoba-whisper v2.0 / v2.2 | Kotoba Technologies | 2024-09 / 2024-10 | Apache 2.0（可） | 756M | 日本語専用 |
| （比較）japanese-zipformer-base-k2-rs35kh | Reazon Human Interaction Lab | 2025-10 | Apache 2.0（可） | 96.5M | 日本語専用 |
| （比較）Voxtral Mini 4B Realtime 2602 | Mistral AI | 2026-01 | Apache 2.0（可） | 4.4B（HF の値） | 対応（13 言語） |
| （比較）Fun-ASR-Nano-2512 | Tongyi Lab（FunAudioLLM） | 2025-12 | Apache 2.0（可） | 0.8B（HF の値） | 対応 |

「HF の値」は HF の API が返す safetensors のパラメータ数。音声エンコーダーなどを含むので、名前の数字より大きい（確認）。

### 2.2 日本語の正確さ（Haas のモデルカードの表）

Third Intelligence の asr-ja-bench v1.1（JSUT basic5000、JVNV、TEDxJP-10K、FLEURS、SpeechBSD、合計 23.38 時間）。値は CER strict（漢字とかなの書き分けの違いも誤りに数える、%）。加重平均は音声の長さで重み付け。RTFx は公開モデルが H200 での 1 秒あたりに処理できる音声の秒数、API は OpenRouter 経由の応答時間からの値で、比べ方が違う（確認、画像）。出典: https://huggingface.co/third-intelligence/Haas-ja-v1.0 の `assets/cer_table.png`

| モデル | 種類 | 加重平均 | FLEURS | JSUT | JVNV | TEDxJP | SpeechBSD | RTFx |
|---|---|---|---|---|---|---|---|---|
| Microsoft AI MAI-Transcribe 2 | API | 4.62 | 1.72 | 4.61 | 4.36 | 6.03 | 3.21 | 9.71 |
| ElevenLabs Scribe v2 | API | 5.44 | 2.21 | 4.71 | 4.14 | 7.88 | 4.28 | 4.60 |
| Google Gemini 3.1 Pro (Preview) | API | 5.54 | 2.25 | 4.85 | 5.08 | 7.59 | 4.52 | 0.46 |
| OpenAI GPT-Transcribe | API | 6.07 | 3.45 | 6.54 | 4.75 | 7.49 | 4.47 | 5.90 |
| **Haas-ja-v1.0** | 公開 | **6.12** | 3.67 | 5.32 | 4.53 | 8.35 | 5.47 | 3,236 |
| Mistral Voxtral Small Transcribe 3 | API | 6.16 | 2.47 | 6.02 | 5.13 | 8.15 | 4.94 | 3.82 |
| AssemblyAI Universal-3.5 Pro | API | 6.46 | 3.55 | 7.06 | 5.82 | 7.68 | 4.58 | 9.98 |
| Mistral Voxtral Mini Transcribe 3 | API | 6.46 | 2.94 | 6.46 | 5.08 | 8.65 | 4.63 | 4.37 |
| Google Gemini 3.5 Transcribe | API | 6.51 | 2.99 | 6.47 | 5.56 | 8.49 | 4.85 | 1.58 |
| **NVIDIA Nemotron 3.5 Transcribe 30B-A4B** | 公開 | 6.89 | 3.54 | 5.90 | 6.02 | 9.53 | 5.36 | 190 |
| OpenAI GPT-4o Transcribe | API | 7.15 | 2.72 | 5.14 | 4.87 | 11.70 | 5.01 | 6.04 |
| OpenAI Whisper large-v3 | 公開 | 7.22 | 4.25 | 6.97 | 7.52 | 8.78 | 5.31 | 212 |
| NVIDIA Parakeet TDT+CTC 0.6B (ja) | 公開 | 7.23 | 5.50 | 6.35 | 9.24 | 8.40 | 4.92 | 3,407 |
| **IBM Granite-Speech 5.0 470m TurboCTC** | 公開 | 7.23 | 4.07 | 5.87 | 8.90 | 8.95 | 6.13 | 4,963 |
| **IBM Granite-Speech 5.0-2b** | 公開 | 7.49 | 4.64 | 6.55 | 8.32 | 9.13 | 6.30 | 294 |
| Fish Audio Transcribe 1 | API | 7.58 | 4.97 | 8.42 | 5.91 | 8.97 | 5.55 | 10.1 |
| Alibaba Qwen3-ASR 1.7B（アプリにある） | 公開 | 7.59 | 4.93 | 8.48 | 5.93 | 8.94 | 5.61 | 323 |
| Kotoba-Whisper v2.0 | 公開 | 8.04 | 6.75 | 8.21 | 6.20 | 9.83 | 5.56 | 432 |
| Deepgram Nova-3 | API | 8.28 | 4.94 | 6.84 | 6.02 | 12.26 | 5.53 | 11.2 |
| Kotoba-Whisper bilingual v1.0 | 公開 | 8.45 | 7.26 | 8.96 | 6.91 | 9.74 | 6.18 | 431 |
| xAI Grok STT 1.0 | API | 8.46 | 11.77 | 6.37 | 13.33 | 8.21 | 5.62 | 11.2 |
| IBM Granite-Speech 4.1-2b (AR) | 公開 | 8.57 | 5.22 | 7.14 | 9.33 | 10.81 | 7.32 | 309 |
| Google Gemini 3.7 Flash | API | 8.87 | 5.10 | 13.28 | 6.71 | 8.19 | 5.83 | 1.22 |
| Alibaba FunASR Nano (2512) | 公開 | 9.42 | 6.21 | 7.66 | 19.14 | 8.75 | 6.73 | 89.2 |
| Alibaba Qwen3-ASR 0.6B（アプリにある） | 公開 | 9.77 | 7.99 | 11.56 | 7.15 | 10.66 | 7.34 | 364 |
| Google Gemma 4 E4B | 公開 | 10.07 | 7.19 | 10.32 | 6.82 | 12.73 | 7.87 | 127 |
| Cohere Transcribe (03-2026)（アプリにある） | 公開 | 12.35 | 3.99 | 7.78 | 24.54 | 15.61 | 6.20 | 640 |

この表にない日本語の数値（出典ごとに正規化が違うので、上の表とは比べられない）。

| モデル | データ | CER | 出典 |
|---|---|---|---|
| Nemotron 3.5 ASR Streaming 0.6B | FLEURS ja（言語を指定、80 ms / 160 ms / 320 ms / 560 ms / 1.12 s） | 13.87 / 12.90 / 12.22 / 11.91 / 11.48 | NVIDIA のモデルカード |
| 同上 | FLEURS ja（自動判定、同じ順） | 14.97 / 13.85 / 13.00 / 12.38 / 11.66 | NVIDIA のモデルカード |
| 同上（speech-swift の MLX、320 ms） | FLEURS ja、50 文 | INT5 12.11、INT8 11.42 | speech-swift の文書 |
| Qwen3-ASR（speech-swift の MLX、サイズの記載なし） | FLEURS ja | 4bit 16.11、8bit 8.64 | speech-swift の文書 |
| Granite TurboCTC / Granite 2B | CSJ eval1 | 17.80 / 18.67 | IBM のモデルカード（画像） |
| 同上 | Common Voice 17 ja | 8.48 / 10.74 | IBM のモデルカード（画像） |
| 同上 | FLEURS ja | 5.26 / 5.51 | IBM のモデルカード（画像） |
| Nemotron 3.5 Transcribe 30B-A4B | FLEURS ja / CoVoST2 ja | 4.42 / 10.61 | NVIDIA のモデルカード |
| VibeVoice-ASR-Streaming 7B | MLC-Challenge の日本語（会話、2.9 s ごと） | 27.85 | Microsoft の論文 |
| Parakeet TDT-CTC 0.6B ja | JSUT / CV 8.0 / CV 16.1 test / TEDxJP-10k | 6.4 / 7.1 / 13.2 / 9.0 | NVIDIA のモデルカード |
| kotoba-whisper v2.0 | CV 8 / JSUT / ReazonSpeech | 9.2 / 8.4 / 11.6 | Kotoba のモデルカード |
| japanese-zipformer-base-k2-rs35kh | JSUT / Common Voice / TEDxJP-10K | 9.71 / 11.00 / 13.07 | Reazon のモデルカード |
| Voxtral Mini 4B Realtime 2602 | FLEURS ja（遅延 480 ms / 960 ms / 2.4 s） | 9.59 / 6.80 / 5.50（指標名の記載なし） | Mistral のモデルカード |
| Moonshine Streaming Tiny ja | FLEURS ja / ReazonSpeech | 11.50 / 26.73 | Moonshine のモデルカード |
| Omnilingual ASR 7B LLM | jpn_Jpan | 19.2 | Meta の GitHub の CSV |

### 2.3 機能と、Mac で動かしやすいか

表の各欄の根拠と、確認か推測かは 3 章に書いた。「記述なし」は、モデルカード（とあれば README）を読んで、その項目の記述が見つからなかったという意味。

| モデル | ストリーミング | 句読点 | 言語の自動判定 | 日英の混在 | 語彙の指示 | Mac 向けの重み | speech-swift（固定 / 最新） | aufklarer | ダウンロード |
|---|---|---|---|---|---|---|---|---|---|
| Nemotron 3.5 ASR Streaming 0.6B | あり（80 ms〜1.12 s。aufklarer の版は 320 ms） | あり | あり（指定より少し不正確） | 発話ごとに言語タグ。発話の中の混在は記述なし | CoreML 版はブーストあり。MLX 版はなし | CoreML INT8、MLX INT5・INT8 ほか | 対応 / 対応 | あり | 565 MB（MLX INT5）、642 MB（CoreML INT8） |
| Nemotron 3.5 Transcribe 30B-A4B | なし（オフラインと明記） | 指示次第 | あり | あり（日本語は code-switching に対応と明記） | 文脈で語彙のヒント | なし（公式は Linux と Windows） | なし / なし | なし | 67.5 GB（BF16） |
| Granite 5.0 470M TurboCTC | 記述なし | あり | 記述なし（言語の指定の口がない） | 記述なし | 記述なし | mlx-audio（Python）で動くと記載 | なし / なし | なし | 0.95 GB |
| Granite 5.0 2B | なし | 指示で付ける | 言語の指定ができる | 記述なし | あり（最大 2,000 語） | mlx-audio と llama.cpp | なし / なし | なし | 5.05 GB |
| Haas-ja-v1.0 | なし（区切って書き直せばライブ字幕は可） | あり（speech.cpp の文書。カードには記述なし） | 日本語のみ | 記述なし | あり（表記と読みの組） | 公式はなし（macOS 非対応と明記）。speech.cpp の GGUF は Metal で動く | なし / なし | なし | 1.23 GB（speech.cpp の Q8_0 は 0.66 GB） |
| VibeVoice-ASR-Streaming | あり（2.9 s ごと、最初の文字まで 3.5 s） | 記述なし | 記述なし | 記述なし | ホットワード | 記述なし | なし / なし | なし | 5.6 GB / 17.4 GB |
| Confucius4-R2T2 | あり（80 ms〜2 s） | 記述なし | 言語の指定か自動 | 記述なし | 文脈とホットワード | 記述なし | なし / なし | なし | 4.1 GB |
| ARK-ASR 0.6B / 3B | 記述なし | 記述なし | 記述なし | 記述なし | 記述なし | なし | なし / なし | なし | 2.6 GB / 8.1 GB |
| Moonshine Streaming Tiny ja | あり | 記述なし | 日本語のみ | 記述なし | 記述なし | なし | なし / なし | なし | 0.11 GB |
| （アプリ）Qwen3-ASR | なし（アプリは書き直しで途中の文字を出す） | あり（推測: 今回は確かめていない） | あり（アプリの `detectsLanguage`） | 1.7B はあり（アプリの説明文） | 文脈（アプリは 60 語まで渡す） | MLX 4・5・8bit、CoreML | 対応 / 対応 | あり | 0.6B: 713 MB（4bit）〜1.1 GB（5bit） |
| （比較）Parakeet TDT-CTC 0.6B ja | 記述なし | あり | 日本語のみ | 記述なし | 記述なし | 公式はなし。speech.cpp の GGUF は Metal で動く | なし（ParakeetASR は v3 用） / なし | なし | 2.49 GB（speech.cpp の Q8_0 は 0.66 GB） |
| （比較）kotoba-whisper v2.0 | なし | v2.2 は別のモデルで付ける | 日本語のみ | 記述なし | 記述なし | 第三者の MLX 版あり（未読） | なし / なし | なし | 1.52 GB |
| （比較）Voxtral Mini 4B Realtime 2602 | あり（240 ms〜2.4 s） | 記述を確認していない | 記述を確認していない | 記述なし | 記述なし | なし | なし（VoxtralASR は 3B 2507 用） / なし | なし | 17.7 GB |

### 2.4 クラウド

| サービスとモデル | 公開 | 日本語 | 使い方 | 語彙 | 価格 | Koebumi から |
|---|---|---|---|---|---|---|
| OpenAI gpt-transcribe | 2026-07-28 | 言語ヒントは ISO 639-1（ja の明記はない）。Haas の表で CER 6.07 | ファイル（`/v1/audio/transcriptions`）。Realtime の確定したターン | `prompt`、`keywords`、`languages` | $0.0045/分 | 今の送り方に近い。`language` を `languages` に替える必要がある（推測） |
| OpenAI gpt-live-transcribe | 2026-07-28 | 同上 | Realtime（WebSocket）。遅延を 5 段階で選ぶ | `keywords`、`languages` | $0.017/分 | WebSocket の実装が要る |
| OpenAI gpt-realtime-whisper | 2026-05-07 | 記述を確認していない | Realtime | 記述を確認していない | $0.017/分 | WebSocket の実装が要る |
| OpenAI whisper-1、gpt-4o-transcribe、gpt-4o-mini-transcribe | 2026-08-26 に廃止を予告 | | 2027-02-26 に停止 | | | 既定の gpt-4o-transcribe を替える必要がある |
| Groq whisper-large-v3、whisper-large-v3-turbo | 新しいモデルはない | | ファイル | | $0.111/時、$0.04/時 | 今のまま |
| Google gemini-3.5-transcribe / -live | 2026-08（最終更新） | 対応（言語の表に Japanese） | ファイルと Live | カスタム語彙（最大 1,000 語） | 記述を確認していない | OpenAI 互換の口は確認していない |
| Mistral Voxtral Mini / Small Transcribe 3、Realtime 3 | 2026-10-20（Public Preview） | 言語の一覧は確認していない。Haas の表で 6.46 / 6.16 | ファイルと Realtime | 確認していない | 確認していない | 確認していない |

## 3. モデルごとの詳細

### 3.1 Nemotron 3.5 ASR Streaming 0.6B（NVIDIA）

出典: https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b 、speech-swift の文書とソース。

#### 公開日、ライセンス、大きさ
- 公開は「Hugging Face [06/04/2026]」（確認）。HF のリポジトリの作成は 2026-05-15（確認: HF の API）。
- 「This model is ready for commercial use.」（確認）。ライセンスは OpenMDW-1.1（確認）。OpenMDW-1.1 は「permission is hereby granted, free of charge, to deal in the Model Materials without restriction」で、配るときはライセンスの写しと表示を残す条件がある（確認: https://openmdw.ai/license/1-1/ ）。Koebumi は重みを配らず利用者の Mac で HF から落とすので、表示の義務は主にアプリの外の話になる（推測）。
- 「this 600M parameter model transcribes speech into text with native support for punctuation and capitalization」（確認）。HF の API のパラメータ数は 637,997,088（確認）。

#### 日本語
- 40 のロケールのうち、すぐ使える「Transcription-ready (19 locales)」に「Japanese (ja-JP)」がある（確認）。
- FLEURS の日本語の CER は、言語を指定すると 80 ms で 13.87、320 ms で 12.22、1.12 s で 11.48。自動判定では 80 ms で 14.97、320 ms で 13.00、1.12 s で 11.66（確認: カードの「Transcription-ready (19 locales)」の表）。JSUT、ReazonSpeech、CSJ、Common Voice の日本語の値はカードにない（確認）。
- speech-swift の測定（M5 Pro、FLEURS の 50 文、320 ms のストリーミング）では、日本語の CER は MLX INT5 で 12.11、INT8 で 11.42（確認: `docs/benchmarks/nemotron-asr-streaming.md` L47、固定版と最新版で同じ）。INT4 は「meaningfully lossier especially on Hindi and Japanese」で、Swift の実行環境は INT4 を受け付けない（確認: `docs/models/nemotron-asr-streaming.md`）。

#### ストリーミング、句読点、言語の判定、混在
- キャッシュを持つ FastConformer と RNN-T で、80、160、320、560、1120 ms の区切りを選べる（確認）。aufklarer の CoreML INT8、MLX INT5、MLX INT8 は 320 ms だけ（確認: speech-swift の文書）。
- `target_lang=auto` で言語を判定し、文末の句読点の後ろに `<ja-JP>` のようなタグを付ける。speech-swift はタグを取り除いてから返す（確認: カード、speech-swift の文書の「Vocabulary」）。
- 「mixed-language traffic」を発話ごとにラベル付けできるとある。1 つの発話の中で日本語と英語が混ざる場合の記述はない（確認）。

#### 語彙
- speech-swift の CoreML 版は、辞書の語をトークンに分けて RNN-T の出力にバイアスをかける（「word boosting」）。NVIDIA の CTC-WS とは違う簡易な方式（確認: `docs/models/nemotron-asr-streaming.md`「Word boosting」）。
- 「Native MLX currently uses unboosted greedy decoding.」（確認: 同 L55）。辞書を使うなら CoreML 版を選ぶことになる（推測）。

#### speech-swift と aufklarer
- 固定中の SHA に `NemotronStreamingASR` のライブラリがある（確認: `Package.swift` L117-L120）。既定のモデルは `aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8`（確認: `Sources/NemotronStreamingASR/NemotronStreamingASR.swift` L23）。MLX は INT5 と INT8 を選べ、既定は INT5（確認: `NemotronMLXConfiguration.swift` L4-L12、`NemotronMLXRuntime.swift` L13）。
- セッションは `createSession(language:wordBoosting:languageGuide:)` で作り、言語は「`"ja-JP"`」のような BCP-47 か、nil で自動（確認: `NemotronStreamingASR.swift` L78-L92）。
- CoreML 版は `SpeechRecognitionModel` と `StreamingRecognitionModel` の両方に準拠する（確認: `NemotronStreamingASR+Protocols.swift` L4、`NemotronStreamingASR.swift` L396）。MLX 版は `StreamingRecognitionModel` だけ（確認: `NemotronMLXRuntime.swift` L326）。Koebumi の `LocalSpeechRuntime` は `SpeechRecognitionModel` を返す作りなので、CoreML 版はそのまま入る（確認: `Sources/Koebumi/Speech/LocalSpeechRuntime.swift` L41、L61。入るかどうかは推測）。
- 固定版と最新版の違いは、ダウンロードの設定（`downloadOptions`）と MLX のキャッシュの上限の調整だけだった（確認: 2 つの版の diff）。
- aufklarer の重み（確認: HF の API）。

| リポジトリ | 作成 | 大きさ |
|---|---|---|
| aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-5bit | 2026-07-24 | 564.8 MB |
| aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-8bit | 2026-06-04 | 768.2 MB |
| aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8 | 2026-06-04 | 642.2 MB |
| aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-MLX-4bit | 2026-06-04 | 496.6 MB（Swift は読まない） |

#### 速さとメモリ
- speech-swift の測定（63.7 秒の英語、320 ms）で、MLX INT5 はディスク 538.6 MB、ピーク 800 MB、RTF 0.0467。1 区切りの処理は中央値 13.8 ms（確認: `docs/benchmarks/nemotron-asr-streaming.md`）。Swift のネイティブ実行では INT5 の RTF 0.0360、ピーク 611 MB（確認: 同）。
- iOS 27.2 の iPhone で CoreML の Neural Engine のコンパイルに失敗する報告がある。同じ報告の中で、macOS 27.2 では問題なく動くと書かれている（確認: https://github.com/soniqo/speech-swift/issues/503 ）。

### 3.2 Granite Speech 5.0 470M TurboCTC と 2B（IBM）

出典: https://huggingface.co/ibm-granite/granite-speech-5.0-470m-turboctc 、https://huggingface.co/ibm-granite/granite-speech-5.0-2b

#### TurboCTC
- 「NEW (October 21, 2026): Granite Speech 5.0 TurboCTC is now multilingual!」。対応は英語、フランス語、ドイツ語、スペイン語、ポルトガル語、イタリア語、日本語の 7 言語（確認）。最初の英語だけの版は 2026-08-25（確認）。
- 「a compact 470 million parameter multilingual ASR model ... well suited for deployment on laptops, smartphones and other edge devices」。「The model outputs punctuated and capitalized transcripts.」（確認）。
- 構造はブロック自己注意の Conformer と CTC。推論は「non-autoregressively with greedy decoding」（確認）。
- 日本語の CER は CSJ eval1 で 17.80、Common Voice 17 で 8.48、FLEURS で 5.26。2B（18.67、10.74、5.51）より良い（確認、画像: `assets/granite-speech-5.0-470m-turboctc-cer-ja.png`）。
- Apple シリコンでは「Usage with `mlx-audio` for Apple Silicon M series chips」（Python）が書かれている（確認）。Swift の実装、CoreML の重み、語彙の指示、ストリーミングの記述はない（確認）。
- ライセンスは Apache 2.0（確認）。リポジトリは 0.95 GB（確認: HF の API）。
- CTC で構造が単純なので、speech-swift の Omnilingual（wav2vec2 と CTC）や Parakeet の移植に近い手間で MLX に移せると思われる（推測）。

#### 2B
- 2026-10-20 公開。Granite 4.0 1B を土台にした音声言語モデルで、英、仏、独、西、葡、日の書き起こしと翻訳（確認）。
- 語彙のバイアスは「Increased keyword list size (up to 2000)」で、指示は「transcribe the speech to text. Keywords: <kw1>, <kw2>, ...」（確認）。
- 言語の指定は「The speech is in <language>. ...」の指示で行う（確認）。句読点は「transcribe the speech with proper punctuation and capitalization.」の指示で付ける（確認）。
- mlx-audio と llama.cpp での使い方が書かれている（確認）。
- Haas の表では 2B（7.49）より TurboCTC（7.23）の方が正確で、速さは 294 と 4,963 で大きく違う（確認、画像）。Koebumi には TurboCTC の方が合う（推測）。

### 3.3 Haas-ja-v1.0（Third Intelligence）

出典: https://huggingface.co/third-intelligence/Haas-ja-v1.0 、https://github.com/third-intelligence/Haas-ASR

- 日本語専用。Parakeet-TDT の構造で、予測ネットワークの LSTM を Kimi Delta Attention（KDA）に替えた（確認）。パラメータは 615.8M（確認）。
- 学習は ReazonSpeech、Common Voice 26.0、YODAS と社内のデータで約 46,000 時間。評価データは学習に使っていない（確認）。
- 「the most accurate of the open models we evaluated (CER strict 6.12%)」「on par with GPT-Transcribe (6.07%)」（確認）。
- 速さは「almost the same speed as Parakeet (RTFx 3,236 vs. 3,407)」（確認）。
- 語彙: `haas_asr.Vocabulary({"Haas": ["ハース"], ...})` のように、表記と読み（かな）を組で渡す。NeMo の GPU のフレーズブーストを使い、語彙なしの結果と比べて、語全体が入る変更だけを残す。時間は約 1.3 倍（確認）。
- 制約: 「The prediction network runs on kernels from flash-linear-attention, which needs Triton and CUDA, so CPU and macOS are not supported.」（確認: カードと GitHub の README L46）。ストリーミングは学習していない（確認）。フィラーは省きがちで、出力の書き方は変えられない（確認）。句読点の記述はない（確認）。
- ライセンスは Apache 2.0（確認）。リポジトリは 1.23 GB（確認）。
- HF には第三者の ONNX と GGUF の変換がある（Sanami/haas-ja-onnx、oboroge0/Haas-ja-v1.0-onnx、sakasegawa/Haas-ja-v1.0-GGUF。確認: HF の API の検索結果）。このうち sakasegawa/Haas-ja-v1.0-GGUF は speech.cpp のカタログが取得するファイルで、speech.cpp は Haas を M5 の Metal で動かしている（確認: speech.cpp の README と `docs/models/fastconformer.md`）。speech.cpp の文書は、Haas の出力に句読点が付くと書いている（確認）。詳しくは 3.14。

### 3.4 Nemotron 3.5 Transcribe 30B-A4B（NVIDIA）

出典: https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B

- 2026-10-28 公開。全体 34B、動くのは 4.3B の Mamba-2 と Transformer の混成の MoE（確認）。「ready for commercial or non-commercial use」、OpenMDW-1.1（確認）。
- 日本語は ASR、翻訳、話者付き、code-switching のすべてに対応し、品質は「Production-ready」（確認: Language Support Matrix）。
- FLEURS の日本語の CER は 4.42、CoVoST2 は 10.61（確認）。Haas の表では 6.89（確認、画像）。
- 「This is an offline model.」（確認）。文脈で語彙のヒントを渡せる（「Text context can supply task instructions and vocabulary hints.」確認）。
- 動かす環境は H100 80 GB が 1 枚、OS は Linux と Windows（確認）。BF16 の重みは 67.5 GB（確認: HF の API）。Mac の手元で動かす対象ではない（推測）。OpenAI 互換の API の後ろに置く使い方（vLLM）はカードにあり、Koebumi のカスタムのクラウドから使える可能性がある（推測）。

### 3.5 VibeVoice-ASR-Streaming 1.5B / 7B（Microsoft）

出典: https://huggingface.co/microsoft/VibeVoice-ASR-Streaming-1.5B 、https://arxiv.org/abs/2609.02812

- 2026-09-02 公開、MIT（確認）。話者付きのストリーミングの書き起こしで、10 言語に日本語を含む。「Customized Hotwords」（確認）。
- 2.9 秒の区切りに 0.5 秒の先読みで、話者の確定までの遅れは 2.00 秒。最初の出力は 3.5 秒後。録音は 8 分まで（確認: 論文）。
- 会話のベンチマーク MLC-Challenge の日本語の CER は、7B で 27.85。比べた Gemini 3.5 Transcribe Live は 16.54、GPT Realtime Whisper は 36.50、GPT Live Transcribe は 33.48、ElevenLabs Scribe v2 Realtime は 33.17（確認: 論文の Table 1。API はすべて 2.9 秒ずつ送った条件）。
- Koebumi の短い口述には、遅れ（最初の文字まで 3.5 秒）と大きさ（5.6 GB、17.4 GB）が合わない（推測）。

### 3.6 Confucius4-R2T2（NetEase Youdao）

出典: https://huggingface.co/netease-youdao/Confucius4-R2T2

- 2026-09 公開のストリーミング音声認識。平均の遅れは 200〜600 ms、区切りは 80 ms〜2 s、出した文字は後から変えない（「Emitted text is committed as it arrives and remains unchanged.」確認）。
- 文脈とホットワードの指示に対応（確認）。
- 「optimized for streaming recognition in Chinese and English ... retains useful cross-lingual streaming capability on languages such as ... Japanese」（確認）。日本語の数値はカードにない（確認）。
- `config.json` の構造は `Qwen3ASRForConditionalGeneration` で、パラメータ数も Qwen3-ASR 1.7B と同じ（確認）。speech-swift の Qwen3ASR の変換の仕組みで読める可能性がある（推測）。
- ライセンスは NetEase の独自のもの。前月の月間利用者が 1 億を超えるか、前年の売上が 10 億元を超える場合は別の契約が要る（確認: MODEL_LICENSE 2.2）。

### 3.7 ARK-ASR と Audio8-ASR（AutoArk）

出典: https://huggingface.co/Edge0/ARK-ASR-0.6B 、https://huggingface.co/Edge0/Audio8-ASR-0.1B

- ARK-ASR は Whisper 風の音声エンコーダーと Qwen2 のデコーダーで、19 言語に日本語を含む。Apache 2.0（確認）。カードの成績は英語と中国語だけで、日本語の数値はない（確認）。
- Audio8-ASR-0.1B は Qwen3-ASR の音声エンコーダーと 0.1B のデコーダー。7 言語に日本語を含む。iPhone 向けの「Audio8-ASR-0.1B-iOS-ANE」がある（確認）。ライセンスは CC-BY-NC-4.0 で商用に使えない（確認）。

### 3.8 小さな日本語専用モデル

- Moonshine Streaming Tiny ja（Moonshine AI、MIT、27M）。ストリーミング向け。「the training run that produced it was still in progress」と途中の版であることを明記（確認）。CER は FLEURS で 11.50、ReazonSpeech で 26.73（確認）。口述には正確さが足りない（推測）。
- kodama-ja-streaming-small（個人、Apache 2.0、140M）。Moonshine Streaming Small を ReazonSpeech v2 で学習し直したもの。カード自身が、雑音に弱い、FLEURS や固有名詞では公式の moonshine-base-ja より劣る、と書いている（確認）。
- Ruby-ASR-1.7B（Apache 2.0）。Qwen3-ASR 1.7B を日本語向けに学習し直し、ふりがな付き（`七[なな]年間[ねんかん]`）で出す（確認）。口述の出力には向かない（推測）。

### 3.9 日本語の書き起こしに使えない新しいモデル

調べたが、日本語の書き起こしに対応しないもの（確認: HF の API の `language` 欄かカード）。
- sbintuitions/hikari-medium（2026-05）: ストリーミングの書き起こしは英語だけ。日本語は翻訳（EN→JA、JA→EN）だけ。
- sbintuitions/kana-whisper（2026-05）: 日本語をカタカナで出す（「キョーワイイテンキデスネ」）。TTS の読みの評価用。
- nvidia/nemotron-labs-unified-asr-0.6b（2026-08）: 欧州の 25 言語。
- XiaomiMiMo/MiMo-V2.5-ASR（中、英、粤）、inclusionAI/Ming-3.0-asr-tiny（中、英）、zhifeixie/Mega-ASR（英、中）、Edge0/Audio8-ASR-Infinite（中、英）、Cactus-Compute/whistle（欧州の 7 言語）、moondream/parakeet-ultra と parakeet-redux（欧州の 25 言語）、FermionResearch/Phonon-2.5（欧州の 25 言語）、ai-sage/GigaAM-Multilingual（露など 5 言語）、microsoft/VibeVoice-ASR-BitNet（7 言語に日本語なし）、OpenMOSS-Team/MOSS-Transcribe-preview-2B（英）。
- Qwen/Qwen3-ASR-0.6B-hf と 1.7B-hf（2026-06-26）は、名前から既存の Qwen3-ASR を transformers の形式にしたものと思われる（推測）。

### 3.10 比較: 2026 年 5 月より前の日本語に強いモデル

- **Parakeet TDT-CTC 0.6B ja（NVIDIA、2024）**。句読点付きの日本語。CC-BY-4.0。JSUT 6.4、CV 8.0 7.1、TEDxJP 9.0（確認）。Haas の表で 7.23 と RTFx 3,407（確認、画像）。speech-swift の ParakeetASR は Parakeet TDT 0.6B v3（欧州 25 言語）用で、日本語版の変換済みの重みはない（確認）。構造が近いので変換できる見込みはあるが、speech-swift の変換の仕組みは公開されていないとの指摘がある（推測と確認: issue #503 の「the speech-models export repo is closed」）。
- **kotoba-whisper v2.0 / v2.2（Kotoba Technologies、2024）**。Whisper large-v3 を蒸留した 756M。CV 8 で 9.2、JSUT で 8.4、ReazonSpeech で 11.6（確認）。v2.2 は話者分離と句読点（punctuators）を後処理で足す（確認）。Haas の表で 8.04（確認、画像）。Whisper の構造なので speech-swift の WhisperASR で読める可能性はあるが、CoreML への変換が要る（推測）。
- **japanese-zipformer-base-k2-rs35kh（Reazon、2025-10）**。96.5M の CTC。JSUT 9.71、Common Voice 11.00、TEDxJP 13.07（確認）。句読点は記述なし（確認）。
- **Voxtral Mini 4B Realtime 2602（Mistral、2026-01）**。Apache 2.0、13 言語に日本語。遅延は 240 ms〜2.4 s で選べ、FLEURS の日本語は 480 ms で 9.59、2.4 s で 5.50（確認、指標名は表にない）。speech-swift の VoxtralASR は別の Voxtral Mini 3B 2507（8 言語、日本語なし）用（確認: `docs/models/voxtral-asr.md`）。
- **Fun-ASR-Nano-2512（Tongyi Lab、2025-12）**。Apache 2.0。中国語、英語、日本語。ホットワードとストリーミング（確認）。Haas の表で 9.42 で、JVNV が 19.14 と悪い（確認、画像）。
- **Omnilingual ASR（Meta、2025）**。speech-swift に `OmnilingualASR` がある（固定版にもある、確認）。日本語（`jpn_Jpan`）に対応するが、一番大きい 7B の LLM 版でも CER 19.2（確認: `per_language_results_table_7B_llm_asr.csv`）。speech-swift の CTC 版は言語の指定を無視し、公開版はストリーミングしない（確認: `docs/models/omnilingual-asr.md`）。
- NVIDIA の日本語の Canary は見つからなかった。canary-1b-v2 は欧州の 25 言語、canary-180m-flash は英独西仏の 4 言語（確認: HF の API の `language` 欄）。

### 3.11 speech-swift のほかの ASR モジュールの日本語

| モジュール | 既定のモデル | 日本語 | 根拠 |
|---|---|---|---|
| NemotronStreamingASR | Nemotron 3.5 ASR Streaming 0.6B | 対応 | 3.1 |
| OmnilingualASR | Omnilingual CTC 300M〜7B | 対応（CER が高い） | 3.10 |
| ParakeetASR | Parakeet TDT 0.6B v3 | なし（欧州 25 言語） | `docs/models/parakeet-asr.md`、`docs/benchmarks/asr-wer.md`「no CJK」 |
| ParakeetStreamingASR | Parakeet EOU 120M | なし | 文書は「25 European languages」、元の nvidia/parakeet_realtime_eou_120m-v1 は英語のみ（HF の API） |
| CanaryASR | Canary 180M Flash | なし（英独西仏） | `CanaryASR.swift` L41、HF の API |
| KyutaiSTT | Kyutai STT 1B | なし（英仏） | `docs/models/kyutai-stt.md` |
| VoxtralASR | Voxtral Mini 3B 2507 | なし（8 言語） | `docs/models/voxtral-asr.md` |

すべて固定版と最新版で同じ（確認: 2 つの版の `Sources` の diff は、ダウンロードの設定とメモリの調整だけ）。

### 3.12 アプリの Qwen3-ASR の量子化

- アプリは `aufklarer/Qwen3-ASR-0.6B-MLX-4bit` と `aufklarer/Qwen3-ASR-1.7B-MLX-4bit` を使う（確認: `Sources/Koebumi/Speech/LocalSpeechModels.swift`）。
- speech-swift の FLEURS の測定で、日本語の CER は 4bit 16.11、8bit 8.64。「Largest gains on Korean ... and Japanese (16.11% → 8.64%, 46% reduction)」（確認: `docs/benchmarks/asr-wer.md` L116-L129）。この表は 0.6B か 1.7B かを書いていない（確認）。
- 英語の LibriSpeech では、0.6B の 5bit が 4bit より誤りを 25% 減らし、8bit との差は 0.09 ポイント。1.7B の 5bit は 8bit より良かった（確認: `docs/models/asr-model.md`）。
- aufklarer の 5bit は 2026-06-21 公開で、0.6B が 1.10 GB、1.7B が 2.44 GB（確認: HF の API）。4bit は 0.71 GB と 2.23 GB（確認）。

### 3.13 クラウド

#### OpenAI
出典: https://developers.openai.com/api/docs/changelog 、https://developers.openai.com/api/docs/guides/speech-to-text 、https://developers.openai.com/api/docs/guides/realtime-transcription 、各モデルのページ。
- 2026-05-07: 「GPT-Realtime-Whisper for streaming speech-to-text」（確認）。
- 2026-07-28: 「Released GPT Transcribe for accurate file transcription and final transcripts of committed Realtime turns, along with GPT Live Transcribe for low-latency streaming transcription. Both models support free-form transcription context, keyword hints, and multiple expected input languages.」（確認）。
- 2026-08-26: whisper-1、gpt-4o-transcribe、gpt-4o-mini-transcribe、gpt-4o-transcribe-diarize の廃止を予告。「These models will shut down on February 26, 2027. Migrate to gpt-live-transcribe or gpt-transcribe.」（確認）。gpt-4o-transcribe のページには「Deprecated」とある（確認）。
- gpt-transcribe は `/v1/audio/transcriptions` に送る。「Use prompt for unstructured context about the recording. Use keywords for literal terms you expect to hear. Use languages for the expected input languages.」「For gpt-transcribe, languages replaces the singular language field. Don't send both fields.」（確認）。キーワードに `<`、`>`、改行を含めると、リクエスト全体が拒否される（確認）。
- 言語コードは ISO 639-1（例: en、es、fr）、一部の ISO 639-3、zh の地域コード。日本語の明記はない（確認）。ja を受け付けると思われる（推測）。日本語の精度は Haas の表で 6.07（確認、画像）。
- 価格は gpt-transcribe が 1 分 $0.0045、gpt-live-transcribe と gpt-realtime-whisper が 1 分 $0.017（確認: 各モデルのページ）。
- gpt-live-transcribe は WebSocket（`wss://api.openai.com/v1/realtime?intent=transcription`）で、`audio.input.transcription.delay` を minimal、low、medium、high、xhigh から選ぶ。検出した言語は返さず、単語のタイムスタンプ、話者、信頼度も返さない（確認）。

#### Groq
出典: https://console.groq.com/docs/models 、https://console.groq.com/docs/speech-to-text
- 書き起こしは whisper-large-v3（1 時間 $0.111）と whisper-large-v3-turbo（1 時間 $0.04）だけ（確認）。廃止の履歴の最新は 2026-09-21 の groq/compound で、書き起こしの変更はない（確認: deprecations）。

#### そのほか（参考）
- Google の gemini-3.5-transcribe と gemini-3.5-transcribe-live。最終更新は 2026-08。85 以上の言語を自動判定し、発話の途中の言語の切り替えに対応。カスタム語彙は最大 1,000 語（「best results with up to 100 terms」）。言語の表に Japanese がある（確認: https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe ）。
- Mistral の Voxtral 3。「October 20 We released the Voxtral 3 audio family ... All four models are in Public Preview.」書き起こしは voxtral-mini-transcribe-3-0、voxtral-small-transcribe-3-0、voxtral-mini-transcribe-realtime-3-0（確認: https://docs.mistral.ai/getting-started/changelog ）。Voxtral Mini Transcribe 2 は 2026-10-31 に非推奨、2027-04-30 に停止（確認: Mistral のモデルの一覧）。
- MAI-Transcribe 2、ElevenLabs Scribe v2、AssemblyAI Universal-3.5 Pro、xAI Grok STT 1.0、Fish Audio Transcribe 1 は、Haas の表に数値があるだけで、公式ドキュメントは確かめていない。

### 3.14 speech.cpp（実行環境）

出典: https://github.com/nyosegawa/speech.cpp の `README.ja.md`、`docs/models/fastconformer.md`、`docs/server.md`。リリースとコントリビューターは GitHub の API で見た。ソースは読んでおらず、実行もしていない。

- 何か: ggml の上で音声合成・音声認識・発話区間検出・話者分離を動かす C/C++ の実行環境。コマンド `speech` と共有ライブラリ `libspeech` があり、どちらも 1 つの C API の上に作られている。macOS は Apple Silicon の Metal で動く。ライセンスは MIT（確認）。
- 若さ: リポジトリの作成は 2026-09-29。最新のリリースは 2026-10-31 の v0.10.0 で、2026-10-30〜31 の 2 日で v0.9.3、v0.9.4、v0.10.0 が出た。コミットは nyosegawa の 189 件だけ（確認: GitHub の API）。API や形式が今後も変わる見込み（推測）。
- 日本語の認識モデル: `haas-ja-v1.0`、`parakeet-tdt_ctc-0.6b-ja`、`reazonspeech-v2`（いずれも日本語専用）と、`qwen3-asr-0.6b`、`qwen3-asr-1.7b`、`nemotron-3.5-transcribe`（19.0 GB）。重みは sakasegawa の HF のリポジトリの GGUF を取得する（確認: README）。
- 正確さ（speech.cpp の作者が speech-bench で測った値。確認）:

  | モデル（Q8_0） | Common Voice 8.0 ja の CER（括弧は別の表記を正解と認めたとき） | FLEURS ja の CER | 遅延の p50（M5） |
  |---|---|---|---|
  | haas-ja-v1.0 | 測っていない（Haas は Common Voice で学習したため） | 4.39% | 0.042 秒 |
  | parakeet-tdt_ctc-0.6b-ja | 7.93%（3.01%） | 5.00% | 0.025 秒 |
  | reazonspeech-v2 | 12.04%（7.12%） | 7.95% | 0.049 秒 |
  | qwen3-asr-0.6b | 11.9%（7.0%） | 記載なし | 0.107 秒 |
  | qwen3-asr-1.7b | 9.5%（4.7%） | 記載なし | 0.257 秒 |

  Haas の表（2.2）とは、データも正規化も違う。それでも順位は Haas の表と同じで、Parakeet ja は Qwen3-ASR より正確（Common Voice）、Haas は Parakeet ja より正確（FLEURS）（確認）。
- 大きさ: Haas と Parakeet ja の Q8_0 は 0.66 GB で、M5 でのピークのメモリは 0.74 GiB。Q4_K は 0.36 GB まで小さくなる（確認: `fastconformer.md` の表）。
- 語彙: Haas は表記と読みを組にした語彙を受け付ける（`Haas=ハース,ハウス`）。HTTP では `keywords[]` で渡す。Qwen3-ASR は `prompt` で人名や用語を渡す（確認）。
- 長い音声: FastConformer 系（Haas、Parakeet、ReazonSpeech）は、複数の文を含む長い区間をまとめて渡すと、文が丸ごと抜けることがある。NeMo でも同じ。長い録音は `--vad silero-vad` か `chunking_strategy` で区切って渡す（確認）。
- 言語: FastConformer 系は言語を受け取らない。`language` はモデルの言語と合っているかを確かめるだけ（確認）。日本語と英語が混ざる発話の振る舞いは、文書に記述がない（確認）。
- 使い方は 3 つ: C API（`speech.h`）をリンクする、`speech worker MODEL` を子プロセスで起動して JSON Lines でやりとりする、`speech serve` で OpenAI 互換の HTTP サーバーを立てる（確認）。macOS のリリースのアーカイブは 5.97 MB（確認: GitHub の API）。
- `speech serve` の OpenAI 互換の範囲: `/v1/audio/transcriptions` は `file`（WAV）、`model`（読み込んだ認識モデルの id か省略）、`language`、`prompt`、`keywords[]`、`response_format` などを受け付ける。`temperature` などそれ以外の項目は、無視せずに 400 で拒否する（確認: `docs/server.md`）。

## 4. Koebumi への示唆

Koebumi の現状（コードで確認した範囲）。ローカルは 5 つのモデルを `SpeechRecognitionModel` として読み込む（`Sources/Koebumi/Speech/LocalSpeechRuntime.swift` L41、L61）。辞書の語は 60 語まで、Qwen3-ASR には文脈、MOSS には「热词提示」として渡す（同 L163-L197）。クラウドは `/audio/transcriptions` に `model`、`response_format`、`temperature`、言語が 1 つなら `language`、辞書を `prompt` で送る（`Sources/Koebumi/Speech/Transcriber.swift` L369-L377）。既定のモデルは OpenAI が gpt-4o-transcribe、Groq が whisper-large-v3-turbo、カスタムが whisper-1（`Sources/Koebumi/Core/Models.swift` L203-L205）。

### 4.1 Nemotron 3.5 ASR Streaming を入れるとき（推測を含む提案）

- CoreML INT8 の版を選ぶ。`SpeechRecognitionModel` に準拠するので今の読み込みの形に入り、辞書のブーストも使える。MLX 版は軽い（565 MB、ピーク 611 MB）が、ブーストがなく、`SpeechRecognitionModel` に準拠しない。
- 音声バーで日本語だけを選んだときは `"ja-JP"` を渡す。自動判定より CER が少し良い（320 ms で 12.22 と 13.00）。
- 一番の利点はライブ書き起こし。今は Qwen3-ASR で 0.7 秒ごとに書き直している（前回の調査メモ `live-transcript-ui-in-dictation-apps.md` の 4 章）。Nemotron なら 320 ms ごとに差分が出て、出した文字の書き直しもない。録音中の札は Nemotron、話し終えた後の確定は Qwen3-ASR、という組み合わせが考えられる。2 つのモデルを同時にメモリに置くことになるので、メモリの量を測ってから決める。
- 確定の文字としては、日本語の正確さが Qwen3-ASR 1.7B より劣る見込みなので、単独の既定にはしない方がよい。読み上げ音声でアプリの 5 段階の評価（速さ、正確さ）を付け直してから決める。

### 4.2 OpenAI の移行

- 既定を gpt-transcribe に替える。2027-02-26 に gpt-4o-transcribe が止まる。
- gpt-transcribe では `language` の代わりに `languages[]` を使う。辞書は `prompt` のままでも送れるが、`keywords[]` に分けると語をそのまま渡せる。キーワードに `<`、`>`、改行が入るとリクエスト全体が拒否されるので、辞書の語を送る前に取り除く。
- `temperature` を gpt-transcribe が受け付けるかは確かめていない。ガイドの例には出てこない。
- カスタム（OpenAI 互換）の既定の whisper-1 も OpenAI では廃止になる。Groq などの互換サービスでは名前が違うので、既定の名前を見直す。

### 4.3 正確さを上げる順番

1. Qwen3-ASR の 4bit を 5bit か 8bit に替える（コードの変更は repo の名前とダウンロードの大きさだけ）。日本語の差を、アプリの読み上げ音声で確かめる。
2. Nemotron 3.5 ASR Streaming を、ライブ書き起こし用に試す。
3. Haas-ja-v1.0 を speech.cpp で試す（4.4）。まず CLI で、アプリの読み上げ音声と自分の声を Qwen3-ASR と比べる。
4. Granite TurboCTC を MLX に移植する。CTC なのでデコードは単純だが、speech-swift の外で持つことになる。

### 4.4 speech.cpp を使うとき（推測を含む提案）

- 一番手軽な確かめ方は、CLI で `speech asr haas-ja-v1.0 録音.wav` と `speech asr qwen3-asr-0.6b 録音.wav` を比べること。入力は WAV だけ。
- 今のカスタム（OpenAI 互換）の設定で `speech serve` に送ると、400 で失敗する。Koebumi は `temperature=0` を必ず送り（`Sources/Koebumi/Speech/Transcriber.swift` L371）、`speech serve` はこれを拒否する。辞書の語は `prompt` で送るが、Haas は `keywords[]` で受け取る。この 2 点を直せば、カスタムの設定から試せる。
- アプリに組み込むなら、`speech worker` を同梱して子プロセスで動かすのが、C API をリンクするより手間が少ない。ただし、同梱するバイナリの署名と公証、MLX と ggml の 2 つの実行環境を持つことによるメモリ、モデルのダウンロードの画面を考える必要がある。
- Koebumi の 1 回の発話は長いことがあるので、FastConformer 系に渡す前に発話区間で区切る（3.14 の「長い音声」）。
- Haas と Parakeet ja は日本語専用なので、日本語と英語が混ざる発話や、英語だけのときは Qwen3-ASR に任せる形が考えられる。

## 5. わからなかったこと

- Nemotron 3.5 ASR Streaming の、JSUT、ReazonSpeech、CSJ での CER。Haas の表に入っていない。Qwen3-ASR との差は、出典の違う数値からの推測にとどまる。
- 1 つの発話の中で日本語と英語が混ざるときの振る舞い（Nemotron、Granite、Haas）。どのカードにも記述がなかった。
- Granite TurboCTC を区切って流すストリーミングができるか。カードに記述がない。
- Haas の句読点と Mac での動作は、speech.cpp の文書で確かめた（3.14）。ただし speech.cpp で実際に動かしてはいない。第三者の ONNX の変換の中身は読んでいない。
- speech.cpp の測定は作者自身によるもので、第三者が同じ条件で測り直した結果は見つけていない。日本語と英語が混ざる発話での Haas と Parakeet ja の振る舞い。
- speech-swift の asr-wer の多言語の表の Qwen3-ASR が 0.6B か 1.7B か。
- gpt-transcribe と gpt-realtime-whisper が日本語を公式に対応言語としているか（ドキュメントに日本語の明記がない）。gpt-transcribe が `temperature` と単数の `language` をどう扱うか。
- Voxtral 3 の対応言語の一覧、MAI-Transcribe 2 と Scribe v2 の公式ドキュメント（今回は読んでいない）。
- ARK-ASR の日本語の成績。論文（arXiv 2605.28139）は読んでいない。
- Confucius4-R2T2 の日本語の成績と、speech-swift の Qwen3ASR で変換した重みが読めるか。
- speech-swift の変換の仕組み（speech-models）が非公開かどうか。issue #503 の記述だけで、公式の説明は確かめていない。

## 出典

モデルカード（Hugging Face）
- https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
- https://huggingface.co/nvidia/NVIDIA-Nemotron-3.5-Transcribe-30B-A4B
- https://huggingface.co/ibm-granite/granite-speech-5.0-470m-turboctc （画像 `assets/granite-speech-5.0-470m-turboctc-cer-ja.png`）
- https://huggingface.co/ibm-granite/granite-speech-5.0-2b （画像 `assets/granite-speech-5.0-2b-wer-cv.png`）
- https://huggingface.co/third-intelligence/Haas-ja-v1.0 （画像 `assets/cer_table.png`）
- https://huggingface.co/microsoft/VibeVoice-ASR-Streaming-1.5B
- https://huggingface.co/microsoft/VibeVoice-ASR-Streaming-7B
- https://huggingface.co/netease-youdao/Confucius4-R2T2 （`config.json`、ライセンス https://raw.githubusercontent.com/netease-youdao/Confucius4-R2T2/refs/heads/master/MODEL_LICENSE ）
- https://huggingface.co/Edge0/ARK-ASR-0.6B
- https://huggingface.co/Edge0/ARK-ASR-3B
- https://huggingface.co/Edge0/Audio8-ASR-0.1B
- https://huggingface.co/moonshine-ai/moonshine-streaming-tiny-ja
- https://huggingface.co/ayousanz/kodama-ja-streaming-small
- https://huggingface.co/hshispeech/Ruby-ASR-1.7B
- https://huggingface.co/sbintuitions/hikari-medium
- https://huggingface.co/sbintuitions/kana-whisper
- https://huggingface.co/nvidia/nemotron-labs-unified-asr-0.6b
- https://huggingface.co/nvidia/parakeet-tdt_ctc-0.6b-ja
- https://huggingface.co/kotoba-tech/kotoba-whisper-v2.0
- https://huggingface.co/kotoba-tech/kotoba-whisper-v2.2
- https://huggingface.co/reazon-research/japanese-zipformer-base-k2-rs35kh
- https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602
- https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-2512
- aufklarer の変換済みの重み（HF の API `https://huggingface.co/api/models?author=aufklarer` と各リポジトリの API）
- 日本語の新しいモデルの洗い出し（HF の API `https://huggingface.co/api/models?pipeline_tag=automatic-speech-recognition&filter=ja&sort=createdAt&direction=-1`）

論文
- https://arxiv.org/abs/2609.02812 （VibeVoice-ASR-Streaming Technical Report）

ライセンス
- https://openmdw.ai/license/1-1/

GitHub
- https://github.com/soniqo/speech-swift （固定版 `3f58a58a`、最新版 `a57702e6`。`Package.swift`、`Sources/NemotronStreamingASR`、`docs/models`、`docs/benchmarks`）
- https://github.com/soniqo/speech-swift/issues/503
- https://github.com/facebookresearch/omnilingual-asr （`README.md`、`per_language_results_table_7B_llm_asr.csv`）
- https://github.com/third-intelligence/Haas-ASR （`README.md`）
- https://github.com/nyosegawa/speech.cpp （`README.ja.md`、`docs/models/fastconformer.md`、`docs/server.md`、リリースとコントリビューターの API）

API の公式ドキュメント
- https://developers.openai.com/api/docs/changelog
- https://developers.openai.com/api/docs/guides/speech-to-text
- https://developers.openai.com/api/docs/guides/realtime-transcription
- https://developers.openai.com/api/docs/models/gpt-transcribe
- https://developers.openai.com/api/docs/models/gpt-live-transcribe
- https://developers.openai.com/api/docs/models/gpt-realtime-whisper
- https://developers.openai.com/api/docs/models/gpt-4o-transcribe
- https://console.groq.com/docs/models
- https://console.groq.com/docs/speech-to-text
- https://console.groq.com/docs/deprecations
- https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe
- https://docs.mistral.ai/getting-started/changelog
- https://docs.mistral.ai/getting-started/models

Koebumi のソース（比較用）
- `Sources/Koebumi/Speech/LocalSpeechModels.swift`
- `Sources/Koebumi/Speech/LocalSpeechRuntime.swift`
- `Sources/Koebumi/Speech/Transcriber.swift`
- `Sources/Koebumi/Core/Models.swift`
