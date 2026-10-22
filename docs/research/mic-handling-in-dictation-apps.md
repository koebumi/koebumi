# オープンソース音声入力アプリのマイク取得方法（macOS）

調査日: 2026-10-22。一次情報（各アプリのソース、公式ドキュメント、Apple の SDK ヘッダ・ドキュメント、Apple Developer Forums）だけを根拠にした。ブログ記事や二次的なまとめは使っていない。

各主張に「確認」か「推測」を付けた。
- 確認: ソースまたは公式ドキュメントの該当箇所を読んで確かめた。
- 推測: 読んだ内容からの推論で、直接は確かめていない。

調べたコミット（すべて shallow clone。クローンの中のコードは実行していない）:

| 対象 | SHA |
|---|---|
| Amical | `b98f79fb5e7f684b836d407d62878281ffc783eb` |
| VoiceInk | `22e5ec5479b712797c3b338fcb875961e58800b6` |
| Handy | `5a9451e70aedc90648ce2befd9d7e0304746f9c1` |
| handy-recorder（Handy が使うマイク取得ライブラリ） | `55748ee70f7b634ca1e5c635016133eae3608c7e` |
| handy-cpal 0.18.2（handy-recorder が使う cpal のフォーク。crates.io の配布物を読んだ） | `fdbb321242994474f71a8e035f87747038eb099d`（配布物の `.cargo_vcs_info.json`） |
| OpenWhispr | `ba6d61820b4c56d7b08012c61c2ae6b43f3152f3` |

## 1. 要約

- 調べたアプリのうち、マイクを選べる 3 つ（VoiceInk、Handy、Amical）は AVAudioEngine も AVCaptureSession も使っていない。VoiceInk は AUHAL（`kAudioUnitSubType_HALOutput`）を直接使い、Handy は cpal（内部は AUHAL）、Amical は Chromium の `getUserMedia` を使う。AVCaptureSession は 1 つも見つからなかった。
- 3 アプリとも Bluetooth マイクの自動回避は実装していない。VoiceInk は転送種別を取得するが、ログ出力だけに使う。Handy は README に「内蔵マイクを選んで」と書くだけ。Amical は Bluetooth への言及自体がない（Amical は公式ドキュメントにも見つからなかった）。内蔵マイクを自動で優先するのは OpenWhispr（ラベル文字列で判定）だけだった。
- 開始音の扱いは 3 アプリで分かれる。VoiceInk は録音開始の前に鳴らし、完了を待たない。Amical は録音と並行して鳴らし、開始音の最初の 200 ms 以内にくるフレームを捨てる。Handy は最初のマイク入力コールバックが来てから鳴らす。Bluetooth で音が遅れる、または消える問題に直接対処したコードは、どれにもなかった。
- Handy の `handy-recorder` に、本件に近い仕組みがある。`take_headset` は、Bluetooth ヘッドセットの出力側に無音の出力ストリームを張って保持する。ただし Handy 本体は有効にしていない（`take_headset: false` のまま）。
- Apple 側の一次情報では、AVAudioEngine の入力ノードは macOS ではシステム既定デバイスにつながる、と SDK ヘッダが明記している。Bluetooth 高音質録音（AirPods 向け）は iOS 26 専用で、macOS では使えない（SDK ヘッダで確認）。

## 2. 比較表

| | (a) 取得 API | (b) マイク指定と既定への戻り対策 | (c) Bluetooth | (d) 開始・停止音 | (e) 開始の高速化 |
|---|---|---|---|---|---|
| Amical | Electron の `getUserMedia` と Web Audio（AudioWorklet）。macOS の native helper（Swift）は音とミュート専用で、取得には使わない | `getUserMedia` の `deviceId: { exact }` を使い、優先度リストの先頭から接続中のものを選ぶ。AVAudioEngine は使わないので、戻り問題は起きない | 検出・警告・内蔵優先とも見つからなかった（検索語は後述）。無音検出は 5 秒の dead-mic 監視のみ | native helper が AVAudioPlayer で再生。mp3 は起動時に読み込み済み。録音と並行して鳴らし、200 ms 以内のフレームは捨てる。システム音のミュートは設定可 | AudioContext と AudioWorklet を使い回す（無操作 60 分で閉じる）。マイクストリームは毎回開く。デバイス一覧をキャッシュ |
| VoiceInk | AUHAL を直接使う（`CoreAudioRecorder`、入力のみ有効、出力は無効） | `kAudioOutputUnitProperty_CurrentDevice` を AUHAL に設定。システム既定は書き換えない。モードは「システム既定」「指定」「優先順位」の 3 種 | 転送種別（Bluetooth を含む）を取得するが、ログ出力のみ。警告・内蔵優先・先読みバッファはない。内蔵マイクを自動で優先するのは、ふた閉じ（クラムシェル）で内蔵マイクが使えないときの逆方向のフォールバックのみ | AVAudioPlayer。録音開始の前に `playStartSound()` を呼び、完了は待たない。システム音のミュートは録音開始の 220 ms 後 | 起動時とデバイス変更時に AUHAL を `prepare`（初期化まで、開始はしない）。デバイス・形式が同じなら使い回す |
| Handy | Rust の `handy-recorder` 経由で cpal（macOS では AUHAL） | デバイス ID を指定して開く。AVAudioEngine は使わないので、戻り問題は起きない。クラムシェル用マイクの別設定あり | 内蔵マイクか外付けマイクの選択を README で勧めるだけ。コードでの検出・警告はない。ライブラリに `take_headset` があるが Handy は無効 | rodio。開始音は最初のマイク入力コールバックの後に鳴らす（同期再生）。停止音はミュート解除後に鳴らす。出力デバイスは別設定 | 「常時オン」モード（ストリームを開きっぱなし）と、無操作 30 秒で閉じるオンデマンドモード。デバイス ID のキャッシュ。VAD の先読み 450 ms |
| OpenWhispr（補足） | Electron の `getUserMedia` | `deviceId: { exact }`。「内蔵マイクを優先」設定がある | ラベルの文字列で内蔵か外付けかを判定し、内蔵を自動優先できる | 未調査 | 未調査 |

## 3. アプリごとの詳細

### 3.1 Amical

#### (a) 取得 API
- マイク取得は Electron のレンダラ側で行う。`navigator.mediaDevices.getUserMedia` で取得し、`AudioContext`（サンプルレート指定、`latencyHint: "interactive"`）に `createMediaStreamSource` でつなぎ、AudioWorklet でフレームを取り出す（確認）。
  - 取得: [audioCaptureDevice.ts L111-L117, L159-L172](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/hooks/audioCaptureDevice.ts#L111-L172)（エコー除去・ノイズ抑制・自動ゲインはすべて false）
  - グラフ: [audioCaptureContext.ts L56-L59](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/hooks/audioCaptureContext.ts#L56-L59)
  - worklet: [audio-recorder-processor.js](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/assets/audio-recorder-processor.js)（512 サンプル＝16 kHz で 32 ms ごとに送る）
- macOS の native helper は `packages/native-helpers/swift-helper` にある。マイク取得（AVAudioEngine や AVCaptureSession）は含まれず、開始・停止音の再生とシステム音のミュートだけを担当する（確認。検索語: AVAudioEngine、AVCaptureSession、AudioUnit。helper 内で `AudioService.swift` と `AccessibilityService.swift` が CoreAudio / AVFoundation を使うが、どちらも再生とミュート）。
- Chromium が macOS で内部的にどの API を使うかは、Amical のリポジトリ外であり、今回は読んでいない（推測: Chromium の macOS 実装は AUHAL ベース）。

#### (b) マイク指定
- 優先度リスト（`MicrophonePriorityEntry[]`）を持ち、先頭から接続中のデバイスを `deviceId` で一致判定して選ぶ。見つからなければ `"default"` を使う（確認）。
  - [audio-devices.ts L37-L46](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/utils/audio-devices.ts#L37-L46)
- `getUserMedia({ deviceId: { exact } })` で開く。指定デバイスが `NotFoundError` か `OverconstrainedError` で開けなければ、デバイス一覧を取り直し、そのデバイスを除いて選び直す（確認）。[audioCaptureDevice.ts L182-L203](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/hooks/audioCaptureDevice.ts#L182-L203)
- AVAudioEngine は使わないため、「既定に戻される」問題に当たらず、回避策（既定の書き換え、aggregate device）も存在しない（確認）。

#### (c) Bluetooth
- 検索語: `bluetooth`, `airpod`, `hfp`, `transport`, `built-in`。`apps/` と `packages/` のソース（ts/tsx/swift/cs）、README、docs を対象にした。マイク取得に関係する該当はなかった（`transport` は gRPC/HTTP の通信層で無関係）。検出・警告・内蔵優先・先読みバッファは見つからなかった。
- 近いものとして dead-mic 監視がある。録音準備完了から 5 秒間フレームが 1 つも来ないと `noAudioDetected` にする。Bluetooth 専用ではない（確認）。[recorder.ts L337 付近](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/main/lifecycle/adapters/recorder.ts#L337)、値は [tuning.ts L58](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/main/lifecycle/tuning.ts#L58)

#### (d) 開始・停止音
- 再生は native helper（Swift）の `AVAudioPlayer`。mp3 を起動時に `Data` で読み込んでおき、再生時にプレイヤーを作る。再生のタイムアウトは 1 秒（確認）。[AudioService.swift L119-L140, L142-L148](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/packages/native-helpers/swift-helper/Sources/SwiftHelper/AudioService.swift#L119-L148)
- 開始音は native helper の `startRecording` RPC の中で鳴る。`RecordingAmbianceController.startRecording` は「開始音を鳴らす、その後にシステム音をミュート」の順で、この順序は直列（ミューテックス）。停止時は「ミュート解除、その後に停止音」。[RecordingAmbianceController.swift L22-L39](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/packages/native-helpers/swift-helper/Sources/SwiftHelper/RecordingAmbianceController.swift#L22-L39)（確認）
- 録音は開始音を待たずに始まるが、開始音の最初の 200 ms（`START_RECORDING_SOUND_GATE_MS`）は、非最終フレームを捨てる。開始音がマイクに入るのを避けるため（コードコメントとゲートの構造から読み取った。意図は推測）。ゲートは、native の開始 RPC が完了するか 200 ms 経つか、どちらか早い方で開く。[ambiance.ts L15, L55-L93](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/main/lifecycle/adapters/ambiance.ts#L15-L93)、[recorder.ts L375-L377](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/main/lifecycle/adapters/recorder.ts#L375-L377)（確認）
- システム音のミュートは `kAudioDevicePropertyMute`（既定出力デバイス）を使う設定項目 `muteSystemAudio`（既定 true）。[AccessibilityService.swift L112, L149, L363](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/packages/native-helpers/swift-helper/Sources/SwiftHelper/AccessibilityService.swift#L363)（確認）。ダッキングは見つからなかった。
- Bluetooth 専用の扱いはない（確認）。開始音が Bluetooth で遅れる、または消える問題に対処するコードは見つからなかった。ゲートの 200 ms を超えて音が遅れた場合は、音がマイクに入りうる（推測）。

#### (e) 高速化
- AudioContext と worklet ノードを録音のたびに作り直さず使い回す。無操作 60 分で閉じ、7 分を超えて使った後に 5 秒より長い録音をしたら作り直す（確認）。[audioCaptureRecycle.ts](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/hooks/audioCaptureRecycle.ts#L1-L13)、[audioCaptureContextLifetime.ts L32-L58](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/hooks/audioCaptureContextLifetime.ts#L32-L58)
- マイクストリーム自体は録音のたびに開き、終了時に `track.stop()` で閉じる（確認）。[useAudioCapture.ts L163-L186](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/hooks/useAudioCapture.ts#L163-L186)
- デバイス一覧 `enumerateDevices` の結果をキャッシュし、アイドル中も更新する（確認）。[audioCaptureDevice.ts L17-L90](https://github.com/amicalhq/amical/blob/b98f79fb5e7f684b836d407d62878281ffc783eb/apps/desktop/src/hooks/audioCaptureDevice.ts#L17-L90)
- 開始時の先読み（pre-roll）バッファは見つからなかった。

### 3.2 VoiceInk

#### (a) 取得 API
- AUHAL を直接使う。`kAudioUnitSubType_HALOutput` のコンポーネントを作り、入力エレメント 1 を有効、出力エレメント 0 を無効にする。Apple の TN2091 の手順どおり（確認）。
  - [CoreAudioRecorder.swift L366-L420](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift#L366-L420)
  - TN2091: https://developer.apple.com/library/archive/technotes/tn2091/_index.html（「Input must be explicitly enabled ... on element 1」「disable IO on the output scope」）
- AVAudioEngine と AVCaptureSession は使っていない（検索語: AVAudioEngine、AVCaptureSession。AVCaptureDevice は権限確認の `authorizationStatus` だけに使う。[Recorder.swift L158](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Features/Recording/Capture/Recorder.swift#L158)）。
- 出力は無効にしているので、このユニットはヘッドセットの出力側を開かない（確認）。ただし、システムが Bluetooth の入力開始に合わせて A2DP から HFP へ切り替える挙動に対して何かをするコードはない。

#### (b) マイク指定
- `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` で AUHAL にデバイス ID を設定する（確認）。[L422-L440](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift#L422-L440)。AudioDeviceConfiguration の冒頭コメントは「システムの既定デバイスは変更しない」と明記している（[L11](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/Devices/AudioDeviceConfiguration.swift#L11)）。
- 3 つのモード: システム既定／指定（UID＋モデル UID で再検索）／優先順位リスト。[AudioDeviceManager+RecordingRouting.swift L91-L108](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/Devices/AudioDeviceManager%2BRecordingRouting.swift#L91-L108)（確認）
- 入力チャンネルの選択（複数チャンネルの外付けデバイスのみ）がある。

#### (c) Bluetooth
- 検索語: `bluetooth`, `airpod`, `transport`, `hfp`, `builtin`。該当は次のとおり。
  - `kAudioDevicePropertyTransportType` を読み、`Bluetooth` / `Bluetooth LE` などの文字列にしてログに出す。それ以外には使わない（確認）。[CoreAudioRecorder.swift L1124-L1150, L1180-L1215](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift#L1180-L1215)
  - `isInternalMicrophone` は転送種別が内蔵（`BuiltIn`）かどうかを見て、ふたを閉じたときに内蔵マイクが使えない問題を扱う。つまり「内蔵を優先」ではなく「ふた閉じなら内蔵を避ける」ために使う（確認）。[AudioDeviceManager.swift L636-L670](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/Devices/AudioDeviceManager.swift#L636-L670)
  - 指定がなく優先順位でも決まらない場合のフォールバック順は、ふたが開いていれば内蔵マイクが先、閉じていれば外付けが先（確認）。[RecordingRouting.swift L110-L114](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/Devices/AudioDeviceManager%2BRecordingRouting.swift#L110-L114)。ただしこれはユーザー指定のデバイスが無いときの順序で、Bluetooth の既定入力を内蔵に差し替える動作ではない。「システム既定」モードでは既定の入力（Bluetooth でも）をそのまま使う（確認）。
- AUHAL を使い回す際の「準備済みか」の判定で、Bluetooth の経路変更に触れている。デバイス ID が同じでも、サンプルレートや形式が変わると古いクライアント形式のまま「開始は成功するが無音になる」ので、サンプルレートと形式を比べて作り直す（確認）。[L705-L737](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift#L705-L737)
- 録音が 150 ms 未満だったときは、準備済み AUHAL を破棄して次回に作り直す（確認）。[L210-L237](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift#L210-L237)。Bluetooth 専用ではないが、先頭が失われたときの救済になりうる。
- 警告 UI、先読みバッファ、先頭のゼロ区間の除去、ドキュメントでの推奨は、いずれも見つからなかった（README に該当なし）。

#### (d) 開始・停止音
- `AVAudioPlayer` を事前に作り `prepareToPlay()` しておく。開始音の音量は 0.3（既定音）。[SoundPlaybackEngine.swift L21-L36, L68-L98](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/SoundPlaybackEngine.swift#L21-L98)（確認）
- 開始音は録音開始の前に鳴らす。`SoundManager.shared.playStartSound()` を呼んだ直後に `engine.toggleRecord` を呼ぶ。再生完了は待たない（確認）。[RecorderUIManager.swift L244-L248](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Features/Recording/Presentation/RecorderUIManager.swift#L244-L248)
  - 帰結（推測）: 音の出力が先に始まるので、Bluetooth の入力開始（A2DP から HFP への切替）に邪魔される前に鳴り始める可能性が高い。これは Speak の「NSSound を録音開始の後に鳴らす」順序の逆で、Speak の症状（音が約 1.7 秒遅れる、または消える）の回避になりうる。ただし VoiceInk が Bluetooth でこの順序を意図して選んだ証拠はなく、実機でも確かめていない。
- 停止音は `TranscriptionDelivery` が文字起こし後に鳴らす。
- システム音のミュート／メディア一時停止は録音開始の 220 ms 後（`recordingAudioActionDelayNanoseconds`）に実行する。ミュートは `kAudioDevicePropertyMute`（既定出力）。[Recorder.swift L18, L139-L147](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Features/Recording/Capture/Recorder.swift#L139-L147)、[MediaController.swift L86-L112](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/SystemIntegration/Media/MediaController.swift#L86-L112)（確認。220 ms の理由はコードに書かれておらず、開始音を聞かせるためだと推測）

#### (e) 高速化
- `Recorder.init` で `schedulePrepareForCurrentDevice` を呼び、AUHAL を作って初期化（`AudioUnitInitialize`）まで済ませておく。録音開始時は同じデバイス・形式なら再利用し、`AudioOutputUnitStart` だけを行う（確認）。[Recorder.swift L39-L50, L157-L182](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Features/Recording/Capture/Recorder.swift#L157-L182)、[CoreAudioRecorder.swift L111-L144, L689-L703](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift#L111-L144)
- デバイス変更・スリープ・復帰の通知で準備済みユニットを破棄する（確認）。[Recorder.swift L41-L47, L184-L189](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Features/Recording/Capture/Recorder.swift#L184-L189)
- ハードウェア操作は専用のシリアルキューで行う。
- 注意（推測）: 初期化だけで Bluetooth の HFP 切替が始まるかどうかは、コードからは分からない。初期化済みで未開始の AUHAL が切替を起こすかどうかは未確認。

### 3.3 Handy

Handy 本体のマイク取得は、自社の別リポジトリ `handy-recorder`（Cargo の依存。バージョン 0.1）に移されている。本体の依存宣言は [Cargo.toml L54-L56](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/Cargo.toml#L54-L56)（「マイク取得は handy-recorder の仕事」というコメントがある）。

#### (a) 取得 API
- Rust。`handy-recorder` が `handy-cpal`（cpal のフォーク）を呼ぶ。macOS では cpal が AUHAL（`HalOutput` ユニット）を作り、`kAudioOutputUnitProperty_CurrentDevice` でデバイスを設定する（確認）。[handy-cpal macos/device.rs L236-L255](https://github.com/handy-computer/cpal/blob/fdbb321242994474f71a8e035f87747038eb099d/src/host/coreaudio/macos/device.rs#L236-L255)
  - 補足: 入力側は `audio_unit_from_device_id_uninitialized(device, true)` を呼ぶ。出力側のコメントによると、この関数は「デバイス ID がシステム既定と同じなら、`DefaultOutput` モードに切り替える」動作をする（出力側のコメントから読み取った。入力側の内部は読んでいない）。
- 開始音は別に rodio（cpal）で再生する。

#### (b) マイク指定
- 設定の `selected_microphone`（名前）を `handy_recorder::list_input_devices()` で ID に変換し、`RecorderConfig.device` に渡す。`None` ならシステム既定。名前から ID への解決結果はキャッシュし、開けなければキャッシュを捨てて再列挙して 1 回だけ再試行する（確認）。[managers/audio.rs L567-L631, L845-L860](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/managers/audio.rs#L567-L631)
- AVAudioEngine を使わないので「既定に戻される」問題はない。システム既定の書き換えも、aggregate device も使っていない（確認。検索語: aggregate、DefaultInputDevice）。
- クラムシェル（ふた閉じ）用に別のマイクを設定できる。判定は `ioreg` を呼ぶ子プロセス（約 10-20 ms）。[audio.rs L541-L561](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/managers/audio.rs#L541-L561)

#### (c) Bluetooth
- 公式 README に既知の問題として明記されている（確認）: 「macOS で Bluetooth ヘッドセットのマイクを使うと、録音中は Bluetooth が双方向に切り替わるため、再生品質や音量が一時的に下がることがある。ヘッドホンは出力のままにして、Handy では Mac の内蔵マイクか外付けマイクを選ぶとよい」。[README.md L129-L131](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/README.md#L129-L131)
- コードでの検出・警告・内蔵の自動優先は、Handy 本体にはない（検索語: bluetooth、airpod、hfp。該当は README とコメントのみ）。
- コメントで挙動を認識している。「ストリームは動いているが、デバイスがまだ音を届けていないことがある（Bluetooth は数秒かかることがある）。録音の準備完了は最初のチャンクを待つ」。[audio.rs L875-L877](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/managers/audio.rs#L875-L877)（確認）
- 先読みバッファ: VAD（音声区間検出）が 450 ms の先読み（`VAD_PREFILL_MS`）を持つ。これは発話の立ち上がりを逃さないための一般的な仕組みで、Bluetooth 専用ではない（確認）。[vad/mod.rs L5](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/audio_toolkit/vad/mod.rs#L5)。ただし、デバイスが先頭 1-2.5 秒をゼロで返す場合は、ゼロのまま先読みに入るだけで、救済にはならない（推測）。
- ライブラリ側の仕組み `take_headset`（後述）はある。

##### handy-recorder の `take_headset`
- `RecorderConfig.take_headset`: 「Bluetooth ヘッドセット（AirPods）を録音中だけこの Mac に移す。macOS のみ」。Handy は `..RecorderConfig::speech()` を使い、`speech()` は `take_headset: false` なので、Handy 本体では無効（確認）。[types.rs L19-L33](https://github.com/handy-computer/handy-recorder/blob/55748ee70f7b634ca1e5c635016133eae3608c7e/crates/handy-recorder/src/types.rs#L19-L33)、[Handy audio.rs L389-L400](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/managers/audio.rs#L389-L400)
- 実装: 入力デバイスの転送種別が Bluetooth / Bluetooth LE なら、関連デバイス（`kAudioDevicePropertyRelatedDevices`）か UID（アドレス＋`:input`/`:output`）から同じヘッドセットの出力デバイスを探し、そこに無音（全ゼロ）の出力ストリームを張って、録音中だけ保持する（確認）。[headset_macos.rs L1-L75](https://github.com/handy-computer/handy-recorder/blob/55748ee70f7b634ca1e5c635016133eae3608c7e/crates/handy-recorder/src/backend/headset_macos.rs#L1-L75)、[cpal/mod.rs L321-L380](https://github.com/handy-computer/handy-recorder/blob/55748ee70f7b634ca1e5c635016133eae3608c7e/crates/handy-recorder/src/backend/cpal/mod.rs#L321-L380)、保持の開始と解除は [engine.rs L404-L406, L425-L427](https://github.com/handy-computer/handy-recorder/blob/55748ee70f7b634ca1e5c635016133eae3608c7e/crates/handy-recorder/src/capture/engine.rs#L404-L427)
- モジュール先頭のコメントは次のとおり（確認）: 「出力を再生するとヘッドセットはこの Mac に移る。そのマイクだけから録音しても移らない」。つまり目的は、AirPods のようにマルチ接続のヘッドセットが別の端末に取られたままになるのを防ぐこと。A2DP から HFP への切替遅延の短縮が目的かどうかは、書かれていない。
- 示唆（推測）: 録音中に出力側を開きっぱなしにすると、出力が止まって開始音が消える問題（Speak のログの `HALC_ProxyIOContext::_StartIO(): Start failed ... error 35`）を避けられる可能性がある。旧 AVAudioEngine 経路で開始音が即座に鳴ったのと同じ原理に見える。ただし、Handy 側でこの効果を測った記録は見つからなかった。

#### (d) 開始・停止音
- 開始音は、最初の実マイクコールバック（最初のチャンク）が届いてから鳴らす。コメント（要旨）: 開始音は「準備完了」の合図なので、`Stream::play()` や固定の待ち時間ではなく、最初の実入力の後に鳴らす。その後にミュートを適用する。[actions.rs L490-L538](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/actions.rs#L528-L537)（確認）
  - 帰結（推測）: Bluetooth で先頭が数秒ゼロなら、開始音も同じだけ遅れる。それをユーザーへの「準備完了」の合図と割り切る設計。
  - 開始音のあとにミュートする順序なので、開始音自体はミュートされない。
- 再生は rodio。毎回 `DeviceSinkBuilder::open_stream()` で出力ストリームを開き、`sleep_until_end()` で再生が終わるまで待つ。開始音は同期（別スレッド内で完了を待つ）、停止音は別スレッドで非同期。出力デバイスは設定で選べ、無ければ既定。[audio_feedback.rs L49-L137](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/audio_feedback.rs#L49-L137)（確認）
- 停止音の前に `remove_mute()`（ミュート解除）を呼ぶ。「停止音が聞こえるように」とコメントがある。[actions.rs L604-L608](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/actions.rs#L604-L608)（確認）
- ミュートの方法は macOS では `osascript` の `set volume output muted`。[audio.rs L102-L110](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/managers/audio.rs#L102-L110)（確認）
- ダッキングは見つからなかった。Bluetooth 専用の扱いもない。

#### (e) 高速化
- 「常時オンのマイク」設定（`always_on_microphone`）: 起動時にストリームを開き、開きっぱなしにする。オフの場合はオンデマンドで開き、録音終了後 30 秒（`STREAM_IDLE_TIMEOUT`）無操作で閉じる（確認）。[audio.rs L20, L491-L535, L653-L675](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/managers/audio.rs#L491-L535)
  - ストリームを開きっぱなしにすれば、Bluetooth が HFP のまま維持されるので、先頭ゼロの問題は初回以外起きないはず（推測）。反面、常時 HFP になって再生品質が下がり、macOS のマイク使用インジケータも出続ける（後者は一般論で、コードの確認ではない）。
- デバイス ID キャッシュ、VAD の事前ロード。開始までの各段階の所要時間を `debug!` で記録している。

### 3.4 補足: OpenWhispr と Wispr Flow（公式ドキュメント）

#### OpenWhispr
- 「内蔵マイクを優先」設定があり、ラベルの文字列で内蔵か外付けかを判定する。`built-in`、`internal`、`macbook`、`integrated` を含めば内蔵。`microphone` を含むラベルは、`bluetooth`、`airpods`、`wireless`、`usb`、`external`、`headset`、`iphone`、`phone` などが無ければ内蔵とみなす（確認）。[src/utils/audioDeviceUtils.ts L10-L54](https://github.com/OpenWhispr/openwhispr/blob/ba6d61820b4c56d7b08012c61c2ae6b43f3152f3/src/utils/audioDeviceUtils.ts#L10-L54)
  - 外付けを内蔵と誤判定する害が大きいため、「phone」を含む文字列は外付け扱いにする、とコメントで説明している。転送種別 API ではなくラベル判定である点が弱い。
- 公式ドキュメントの推奨: Bluetooth ヘッドセット（AirPods など）には「内蔵マイクを優先し、ヘッドセットは聞くために使う」。理由は「Bluetooth ヘッドセットは入力に使うと低品質・低帯域のモードに切り替わる」。「内蔵マイクを優先」設定の説明には「外付けマイクは遅延や文字起こし品質の低下を招くことがある」とある。https://docs.openwhispr.com/help/customise/choose-your-microphone.md
- CHANGELOG に「内蔵マイクを優先して、Bluetooth による音声の中断を防ぐ」という項目がある（確認）。[CHANGELOG.md L2240](https://github.com/OpenWhispr/openwhispr/blob/ba6d61820b4c56d7b08012c61c2ae6b43f3152f3/CHANGELOG.md?plain=1#L2240)

#### Wispr Flow（公式ヘルプ。ソースは非公開）
- 「最初の数語が欠ける」記事: 無線マイクでは、ホットキーを押した後に少し待ってから話すよう案内。Mac・Windows のマイク選択に「Built-in mic (recommended)」が出る。「Mac の内蔵マイクはふたを閉じると使えない」と警告する。https://docs.wisprflow.ai/articles/3566082841-fix-missing-first-words-in-transcriptions
- iOS では「内蔵マイクを使う」トグルがある（記事の記載）。
- 検索結果の要約には、Mac のマイク一覧で AirPods に警告マークが付くとあったが、ページ本文では確認できなかった（本文の警告はふた閉じに関するテキスト）。この点は未確認として扱う。

#### superwhisper
- 公式の音声設定ページには、入力を選ぶか、自動（システム既定）にするかの説明があるだけで、Bluetooth や AirPods への言及は見つからなかった（検索で確認。ページ本文は取得していない）。https://superwhisper.com/docs/get-started/settings-sound

## 4. AVAudioEngine の入力デバイス選択についての一次情報

1. SDK ヘッダ（Xcode 27.1 付属の MacOSX SDK、`AVAudioIONode.h` L103-L107）には、次のように書かれている（確認）。
   > When the engine is configured to render to/from an audio device, on macOS, AVAudioInputNode and AVAudioOutputNode communicate with the system's default input and output devices.
   また L173-L186 では、入力ノードは「システムの音声入力に接続し」、デバイスから描画するときは形式変換をサポートしない（出力側の形式は入力と同じでなければならない）と書かれている。これが、Speak のログの "formats don't match"（入力 48000、タップ 16000）と整合する（推測）。
2. Apple Developer Forums「Select the audio device for AVAudioEngine」（https://developer.apple.com/forums/thread/71008）:
   - 返信者 theanalogkid（2017 年 1 月）は、`AVAudioIONode.h` の文言を引用し、「AVFoundation のレベルでシステム既定デバイスを変える API はないが、AudioObject レベルにはある。`AudioObjectSetPropertyData()` で DefaultInput などを設定する」と述べた。さらに「`AVAudioInputNode` は `kAudioUnitSubType_HALOutput` をラップしているが、I/O ユニットを自分でラップしてエンジンに追加することはできない。より良い入力サポートのために enhancement request を出すのがよい」と述べた。
   - 注意: ページ上では Apple スタッフのバッジを確認できなかった（取得結果では全員が "OP" 表示）。theanalogkid は Core Audio 担当の Apple エンジニアとして知られているが、ここでは「Apple スタッフと断定はできない」と扱う。
   - 同スレッドの別の投稿者（コミュニティ）は、`inputNode.audioUnit` に `kAudioOutputUnitProperty_CurrentDevice` を設定する方法と、aggregate device を作って既定入力に設定する方法を紹介している。Apple の回答ではない。Speak で観察した「約 0.3 秒後にエンジンが元に戻す」挙動と、この方法が一時的に効いて見える話とは矛盾しない（推測）。
3. 「AVAudioEngine selecting inputs/outputs」（https://developer.apple.com/forums/thread/133080）と「Is it possible to use AVAudioEngine...」（https://developer.apple.com/forums/thread/671584）は、どちらも質問のみで返信が 0 件だった。前者は「既定以外を使う場合、入力ノードと出力ノードに設定できるのは、入出力の両方を持つ単一のデバイスだけのようだ」と報告し、後者は出力デバイスを変えると `inputNode` へのアクセスで -10875 になると報告している。Apple の回答はない。
4. TN2091（アーカイブ、2004 年ごろの文書）: AUHAL で入力する手順は、(1) 入力エレメント 1 を有効にし出力エレメント 0 を無効にする、(2) デバイスを `kAudioOutputUnitProperty_CurrentDevice` で設定する（IO を有効にした後でなければ設定できない）。VoiceInk と cpal はこの手順に沿っている（確認）。https://developer.apple.com/library/archive/technotes/tn2091/_index.html
5. 同じ SDK の `AudioUnitProperties.h`（L2426-）に `kAudioOutputUnitProperty_CurrentDevice` の定義がある。
6. AirPods 向けの Bluetooth 高音質録音は iOS 26 以降専用。`AVCaptureSession.configuresApplicationAudioSessionForBluetoothHighQualityRecording` は `API_AVAILABLE(ios(26.0)) API_UNAVAILABLE(macos, ...)`（`AVCaptureSession.h` L569）、`AVAudioSessionCategoryOptionBluetoothHighQualityRecording` も macOS では使えない（`AVAudioSessionTypes.h` L635）。macOS で HFP を避ける公式の API は見つからなかった（確認。SDK ヘッダを検索した範囲）。
7. 見つからなかったもの: HFP への切替中に出力が失敗する件（error 35）を説明する Apple スタッフの投稿。AVCaptureSession でのマイク指定が正式な手段だと述べた Apple スタッフの投稿。

## 5. Speak への示唆

前提: Speak は現在 AVCaptureSession で、指定デバイスは選べる。残る問題は Bluetooth（HFP）での先頭ゼロ、ゼロでの無音ゲート、小音量、開始音の遅れ・消失。以下は実現しやすさと効果の見込みで並べた。効果は他アプリのコードからの推測であり、Speak の実機では未検証。

### 案 1: 開始音を録音開始の前に鳴らす（VoiceInk 方式）
- 内容: `NSSound`（または事前に `prepareToPlay` した AVAudioPlayer）を再生してから、録音を開始する。完了は待たない。
- 根拠: VoiceInk が実際にこの順序（[RecorderUIManager.swift L244-L248](https://github.com/Beingpax/VoiceInk/blob/22e5ec5479b712797c3b338fcb875961e58800b6/VoiceInk/Features/Recording/Presentation/RecorderUIManager.swift#L244-L248)）。出力が先に始まれば、A2DP から HFP への切替に出力の開始を邪魔されにくいはず（推測）。
- 利点: 変更が小さい。Bluetooth 以外にも影響しない。
- 欠点: 音が鳴ってもまだ録れていない。Bluetooth では「音が鳴った」と「録れている」が一致しない。音の再生中に HFP への切替が始まれば、音が途切れる可能性がある（推測）。実機での確認が必須。
- 補足: 音が録音に混入しうる。Amical は最初の 200 ms を捨てることで対処している（案 4 参照）。

### 案 2: 開始音を「最初の非ゼロ入力」の後に鳴らす（Handy 方式）
- 内容: 録音開始後、最初の実入力（できれば非ゼロのサンプル）が届いてから音を鳴らす。Handy は最初のコールバックを待つ（[actions.rs L528-L537](https://github.com/cjpais/Handy/blob/5a9451e70aedc90648ce2befd9d7e0304746f9c1/src-tauri/src/actions.rs#L528-L537)）。
- 利点: 音が鳴る時点で「話してよい」が保証される。先頭ゼロで話し出して欠ける問題を、ユーザーの行動で避けられる。
- 欠点: Bluetooth では音が 1-2.5 秒遅れる（Speak で観察済みの遅延と同じ）。Handy はコールバック到着を基準にするが、Speak の観察ではゼロのサンプルも「到着」するので、非ゼロ判定が必要になる。判定を入れても、無音ゲートで常にゼロの場合に誤判定しうる（推測）。出力が HFP 切替で失敗する問題は残る。

### 案 3: 録音中に Bluetooth ヘッドセットの出力側へ無音の出力ストリームを張る（handy-recorder の `take_headset` 方式）
- 内容: 入力デバイスの転送種別が Bluetooth のとき、同じヘッドセットの出力デバイス（`kAudioDevicePropertyRelatedDevices` またはアドレスが同じ UID）に、無音を流す出力ストリームを開く。録音開始の前に開いておけば、開始音の出力が即座に通る可能性がある（推測。旧 AVAudioEngine 経路で音がすぐ鳴った理由と同じ原理に見える）。
- 根拠: [headset_macos.rs](https://github.com/handy-computer/handy-recorder/blob/55748ee70f7b634ca1e5c635016133eae3608c7e/crates/handy-recorder/src/backend/headset_macos.rs#L1-L75)、[cpal/mod.rs L321-L380](https://github.com/handy-computer/handy-recorder/blob/55748ee70f7b634ca1e5c635016133eae3608c7e/crates/handy-recorder/src/backend/cpal/mod.rs#L321-L380)。ただし作者の目的は別（ヘッドセットを Mac に移すこと）で、Handy 本体は無効にしており、開始音の問題に効くという証拠はない。
- 利点: AVCaptureSession を維持したまま足せる。内蔵マイクへは影響しない。
- 欠点: 実装量が最も多い。HFP 中は出力も低品質になる（避けられない）。先頭ゼロ自体は解決しない可能性が高い（リンクの切替は変わらない）。

### 案 4: 先頭ゼロの区間と無音ゲートを後処理で扱う（アプリ側）
- 内容: 先頭の完全ゼロのサンプルを、最初の非ゼロまで切り捨てる。無音ゲートで挟まれた完全ゼロの区間は、ASR に渡す前に詰める。小音量はゲイン補正（正規化）する。
- 他アプリの状況: 調べた範囲では、これを実装したアプリはなかった（Handy の VAD 先読みはゼロを救えない。Amical の 200 ms 捨ては音の混入防止が目的）。つまり前例がなく、完全に自前の実装になる。
- 利点: デバイスに依存せず、ASR の「空または別言語の出力」には直接効くはず（推測）。
- 欠点: 失われたはずの先頭の語は戻らない。録音開始のタイミングを UI で知らせる案 2 と組み合わせる必要がある。

### 案 5: Bluetooth のとき内蔵マイクを自動で優先する、または警告する
- 他アプリの状況: 自動優先は OpenWhispr のみ（ラベルの文字列判定、設定でオン・オフ、[audioDeviceUtils.ts](https://github.com/OpenWhispr/openwhispr/blob/ba6d61820b4c56d7b08012c61c2ae6b43f3152f3/src/utils/audioDeviceUtils.ts#L10-L54)）。VoiceInk は「ふた閉じなら内蔵を避ける」逆方向のみ。Handy と Wispr Flow はドキュメントで内蔵を勧めるだけ（Wispr Flow のピッカーには "Built-in mic (recommended)"）。
- Speak での実装: `kAudioDevicePropertyTransportType` が `kAudioDeviceTransportTypeBluetooth` / `BluetoothLE` のときに限り、（a）設定で「Bluetooth のときは内蔵を使う」をオンにできるようにする、または（b）マイク一覧に警告を出す。ラベル判定より転送種別のほうが確実（VoiceInk と handy-recorder が転送種別を使っている）。ふた閉じ（クラムシェル）の場合は内蔵が使えないので、VoiceInk の `isInternalMicrophone` と同様に例外を設ける必要がある。
- 利点: 先頭ゼロ・無音ゲート・小音量・開始音の遅れを、まとめて避けられる唯一の方法。最終的な品質も最も高い（内蔵マイクは常にフルバンド）。
- 欠点: 「AirPods で話したい」というユーザーの意図を上書きしうる。デフォルトでオンにするか、確認ダイアログを出すか、設定で選べるようにするかは、製品判断。ユーザーが明示的に選んだデバイスは尊重するのが無難。

### 案 6: マイクを温めておく（Handy の常時オン方式）
- 内容: 録音しないときも入力を開きっぱなしにして（または Fn 押下の直前に開いて）、HFP への切替を済ませておく。
- 他アプリの状況: Handy が `always_on_microphone` と 30 秒のアイドル後クローズを実装している。VoiceInk は AUHAL を初期化まで済ませる（開始はしない）。Amical は AudioContext だけ温めておき、マイクは毎回開く。
- 利点: 初回以降の先頭ゼロが避けられる可能性がある。
- 欠点: Bluetooth のとき、常時 HFP になって再生音質が落ちる。macOS のマイク使用インジケータが出続ける（一般論）。VoiceInk 方式の「初期化だけ」で HFP 切替が始まるかは、コードからは分からず、実機での検証が必要。Speak が AVCaptureSession なら、`startRunning` のコスト（0.04-0.2 秒）はもともと小さいので、温める利点は Bluetooth に限られる。

### 案 7: AVCaptureSession をやめて AUHAL に戻す（VoiceInk 方式）
- 内容: 入力のみの AUHAL（`kAudioUnitSubType_HALOutput`、EnableIO 入力 1・出力 0）を直接使う。VoiceInk と cpal が同じ構成。
- 利点: 3 アプリの前例があり、Apple の TN2091 の手順どおり。出力側を開かないので、出力ストリームに影響されない。
- 欠点: AVAudioEngine や AVCaptureSession より実装量が多い（形式変換、バッファ管理、スレッド処理は VoiceInk の約 1,300 行を参考）。Bluetooth の先頭ゼロ・無音ゲート・小音量・開始音の遅れは、この API に変えても解決しない（HFP 切替はシステム側の挙動）。AVCaptureSession で指定デバイスの選択が既に動いているので、移す理由は薄い。

### 総合の推奨
1. 最優先: 案 5（Bluetooth を転送種別で検出し、警告、または設定で内蔵優先）。Bluetooth 起因の 4 症状を根本から避けられる唯一の方法で、前例（OpenWhispr、Wispr Flow、Handy）もある。
2. 次に案 1 を実機で試す。変更が最小で、他アプリ（VoiceInk）の順序と同じ。開始音が出れば、Bluetooth でも音が欠けないかを確認する。
3. Bluetooth を使うユーザー向けの保険として案 4（先頭ゼロの切り捨てとゲイン補正）と案 2（最初の非ゼロ入力で「話してよい」を知らせる）。
4. 案 3 は、案 1 で開始音が欠ける場合の追加手段。案 6 と案 7 は優先度が低い。

### 未検証の点（実機で確かめる）
- 録音開始の前に出力を始めた場合に、Speak の環境（macOS 27.0.1、soundcore P42i）で HFP 切替後も音が鳴り終わるか。
- 初期化済みで未開始の入力（VoiceInk 方式）が、Bluetooth の HFP 切替を起こすか。
- 無音の出力ストリームを保持した場合に、開始音の遅延が解消するか。
- Amical の Chromium が macOS で使う内部 API（今回はソース未確認）。
