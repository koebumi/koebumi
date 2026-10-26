# サブスクのエンジン（Claude Code・Codex 経由）と各社の規約

調査日: 2026-10-23。一次情報（Anthropic と OpenAI の規約、ポリシー、公式ドキュメント、ヘルプセンター、公式 GitHub）だけを根拠にした。ニュースや個人ブログは、一次情報の場所を探す手がかりとして検索結果に出ただけで、根拠には使っていない（使った箇所には「二次」と書いた）。

各主張に「確認」か「推測」を付けた。
- 確認: ページまたはソースの該当箇所を読んで確かめた。引用は原文のまま（英語）で、日本語は私の要約。
- 推測: 読んだ内容からの推論で、直接は確かめていない。

この文書は法的助言ではない。判断材料を並べたもので、結論は出していない。

## 1. 要約

- Anthropic。Koebumi の方式（利用者本人が入れてログインした、改変なしの Claude Code を、利用者本人の Mac で `claude -p` として呼ぶ）を直接名指しで許可も禁止もした条項は見つからなかった。ただし周辺に、許可寄りの文（利用者本人が改変なしの Claude Code にサブスクでログインするのは妨げない、`claude -p` とサードパーティアプリでもサブスクの枠を使える）と、禁止寄りの文（サードパーティ開発者がサブスクの認証情報を通して利用者のリクエストを流すこと、サブスク経由でリクエストを中継するサービス）の両方がある。判定は「グレー。許可寄りの根拠は新しく具体的、禁止寄りの根拠は文言が広い」。
- OpenAI。Koebumi の方式を名指しした条項は見つからなかった。一方で OpenAI は 2026 年に「Sign in with ChatGPT」を公式に始め、オープンソースのアプリが利用者の ChatGPT プランを使うことを認めている。Codex の README も ChatGPT でのサインインを推奨している。判定は「禁止ではなく、許可寄りのグレー」。ただし Koebumi の経路は、この公式の仕組みそのものではない。
- README と features.md の記述は、Anthropic の部分は正確。OpenAI の部分は「API キーを勧めている」は正確だが（範囲は CI などの自動化）、「公式の連携ではない」は現在の公式ドキュメントと食い違う。書き換えの候補がある。
- 禁止寄りの文は、2026-11-12 発効の Anthropic 利用ポリシーに入っている（「消費者向けサブスク経由でリクエストを中継するサービス」）。Koebumi の設計がこれに当たるかが、一番の争点になる。
- 取得できなかったものが 3 つある（OpenAI のヘルプセンター記事、OpenAI のサービス規約と Codex 固有の規約、OpenAI の Sign in with ChatGPT 発表ページ）。第 8 節に書いた。

## 2. Koebumi の実装（確認）

調べたファイルは `Sources/Koebumi/AI/ClaudeCodeEngine.swift`、`Sources/Koebumi/AI/CodexEngine.swift`、`docs/features.md`（「AI エンジン（BYOK）」と「制限事項」）、`README.md`。

Claude Code エンジン
- 利用者の Mac にある `claude` を探して起動する（`CommandLineTool.locate("claude")`）。1 回の整形ごとに `claude -p --output-format json` を新しく起動する。
- 認証情報は読まない。`ANTHROPIC_API_KEY` と `ANTHROPIC_AUTH_TOKEN` は、環境変数から外して渡す（API の料金ではなくサブスクの枠で動かすため）。ログインは、利用者がターミナルで `claude` の `/login` を行う。
- 設定画面の状態表示のため `claude auth status --json` を呼び、`loggedIn`、`authMethod`、`subscriptionType`（Pro・Max など）だけを読む。
- `--system-prompt` で Koebumi の指示に置き換え、`--setting-sources ""`、`--strict-mcp-config`、`--no-session-persistence`、`--disable-slash-commands`、`--tools ""` を付ける。Claude Code のバイナリは改変していない。
- Claude Code の名前やロゴは使っていない。画面の表示名は「Claude（サブスク）」。

Codex エンジン
- 利用者の Mac にある `codex` を `codex app-server` として常駐させ、標準入出力で JSON-RPC をやり取りする。10 分使わなければ終了する。
- `initialize` で `clientInfo` に `name: "koebumi"` を渡している。トークンには触れない。`account/read`（`refreshToken: false`）で、アカウントの種類・プラン・メールアドレスを読み、設定画面に出す。
- `codex login` は利用者がターミナルで行う。API キーでログインしている場合は、料金が API になると表示する。
- コマンド実行・プラグイン・MCP などは起動時の `-c` 上書きで止める。承認の依頼は受け付けない。`sandbox` は `read-only`。
- 画面の表示名は「ChatGPT（サブスク）」。

README と features.md の関連記述（確認）
- README L13、L62、L69、L76: サブスクのエンジンの説明。L76 は「ChatGPTのサブスクをCodex経由で使う方法は公式の連携ではないので、OpenAIの方針が変わると使えなくなることがあります」。
- features.md L93: 「Anthropic は他社のアプリが Claude.ai のログインやトークンを扱うことを認めていないので、Koebumi はトークンに触れず、ログインは Claude Code に任せる」。
- features.md L103（制限事項）: 「OpenAI は、プログラムから Codex を使う場合は API キーを使うよう案内しています。ChatGPT のサブスクを Codex 経由で使う方法は公式の連携ではないので、OpenAI の方針が変わると使えなくなることがあります」。
- `ClaudeCodeEngine.swift` L4 のコメントにも、同じ趣旨の記述がある。

## 3. 調べたページの一覧

| 略称 | URL | 取得日 | ページ上の更新日 | 備考 |
|---|---|---|---|---|
| A1 Claude Code 法務 | https://code.claude.com/docs/en/legal-and-compliance | 2026-10-23 | なし | 本文を取得 |
| A2 Claude Code 認証 | https://code.claude.com/docs/en/authentication | 2026-10-23 | なし | 本文を取得 |
| A3 Claude Code ヘッドレス | https://code.claude.com/docs/en/headless | 2026-10-23 | なし | 本文を取得 |
| A4 Agent SDK 概要 | https://code.claude.com/docs/en/agent-sdk/overview | 2026-10-23 | なし | 本文を取得 |
| A5 消費者向け利用規約 | https://www.anthropic.com/legal/consumer-terms | 2026-10-23 | Effective Oct 8, 2025 | HTML を直接取得して原文を確認 |
| A6 利用ポリシー | https://www.anthropic.com/legal/aup | 2026-10-23 | Effective Nov 12, 2026 | 今日（10-23）より後の発効日。HTML を直接取得して原文を確認 |
| A7 ヘルプ: Agent SDK とプラン | https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan | 2026-10-23 | 「Updated over 2 weeks ago」。本文に Update October 7, 2026 と Update June 15, 2026 | 本文を取得 |
| A8 ヘルプ: ログイン | https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account | 2026-10-23 | 「Updated over a week ago」 | 本文を取得 |
| A9 ヘルプ: Pro・Max で Claude Code | https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan | 2026-10-23 | 「Updated over a week ago」 | 本文を取得 |
| A10 ヘルプ: 月次 API クレジット | https://support.claude.com/en/articles/17154008-monthly-api-credits-for-max-and-team-plans | 2026-10-23 | 「Updated this week」 | 本文を取得 |
| O1 Codex 認証 | https://developers.openai.com/codex/auth（https://learn.chatgpt.com/docs/auth に恒久リダイレクト） | 2026-10-23 | なし | 本文を取得 |
| O2 Codex App Server | https://developers.openai.com/codex/app-server（https://learn.chatgpt.com/docs/app-server に恒久リダイレクト） | 2026-10-23 | なし | 本文を取得 |
| O3 Codex 非対話モード | https://developers.openai.com/codex/noninteractive.md | 2026-10-23 | なし | 本文を取得 |
| O4 Codex SDK | https://developers.openai.com/codex/sdk.md | 2026-10-23 | なし | 本文を取得 |
| O5 Sign in with ChatGPT（利用者向け） | https://learn.chatgpt.com/docs/sign-in-with-chatgpt | 2026-10-23 | なし | 本文を取得 |
| O6 Sign in with ChatGPT（開発者向け） | https://developers.openai.com/siwc/quickstart.md 、https://developers.openai.com/siwc/token-sharing-open-source.md 、https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations.md | 2026-10-23 | なし | 本文を取得 |
| O7 openai/codex README | https://github.com/openai/codex（raw の README.md） | 2026-10-23 | なし | 本文を取得。ライセンスは Apache-2.0 |
| O8 利用規約（Terms of Use） | https://openai.com/policies/terms-of-use/ | 2026-10-23 | Effective: January 1, 2026 | openai.com は 403 で直接取得できなかった。Internet Archive の 2026-10-16 の保存（https://web.archive.org/web/20261016001744/https://openai.com/policies/terms-of-use/）で原文を確認。保存日より後の改定は確認できていない |
| O9 利用ポリシー | https://openai.com/policies/usage-policies/ | 2026-10-23 | Effective: October 29, 2025 | 同じく Internet Archive の 2026-10-15 の保存（https://web.archive.org/web/20261015092334/https://openai.com/policies/usage-policies/）で確認 |

## 4. Anthropic の条項

### 4.1 サードパーティ開発者への制限（禁止寄り）

A1 Claude Code 法務（Authentication and credential use。確認）
> OAuth authentication is intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic applications.

> Developers building products or services that interact with Claude's capabilities, including those using the Agent SDK, should use API key authentication through Claude Console or a supported cloud provider. Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users.

> Moreover, developers may not collect, store, or intermediate Claude.ai credentials or session tokens

（原文はこの直後にダッシュを挟んで「sign-in to a Claude account must complete through Anthropic's own flow.」と続く。）

> Anthropic reserves the right to take measures to enforce these restrictions and may do so without prior notice.

A1（Acceptable use。確認）
> Advertised usage limits for Pro and Max plans assume ordinary, individual usage of Claude Code and the Agent SDK.

A4 Agent SDK 概要（確認）
> Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK. Use the API key authentication methods described in the Quickstart instead.

A8 ヘルプ: ログイン（Authenticating to subscription plans。確認）
> Subscription plans can only be used by subscribers, and the usage included in these plans is designed to support ordinary use of native Anthropic applications, including the Claude web, desktop, and mobile applications and Claude Code. The preferred way to access Anthropic services using third-party software, tools, or services ("third-party tools"), including open-source projects, is through API key authentication through Claude Console or a supported cloud provider. Anthropic may at its discretion allow paid subscribers who have enabled usage credits to use certain third-party tools to access Anthropic services included in paid subscription plans, but reserves the right to draw use of such third-party tools from usage credits rather than subscription limits. Users are responsible for any usage credit charges incurred this way. Use of third-party tools that misrepresent their identity to Anthropic's servers, attempt to route third-party traffic against subscription limits, or otherwise violate applicable terms or policies is prohibited and such use may be enforced against.

A8（Developers。確認）
> If you're building a product, application, or tool for others, use API key authentication through Claude Console or a supported cloud provider. Applications that misrepresent their identity to Anthropic's servers, attempt to route third-party traffic against subscription limits, or otherwise violate applicable terms or policies are prohibited and may be enforced against.

A6 利用ポリシー（Do Not Abuse Our Platform。発効日 2026-11-12。確認）
> Resell, proxy, or otherwise provide access to Claude through unauthorized means, including services that route requests through consumer subscriptions or misrepresent the product or client being used

A5 消費者向け利用規約（Use of our Services。Effective Oct 8, 2025。確認）
> Except when you are accessing our Services via an Anthropic API Key or where we otherwise explicitly permit it, to access the Services through automated or non-human means, whether through a bot, script, or otherwise.

A5（Account の節。確認）
> You may not share your Account login information, Anthropic API key, or Account credentials with anyone else. You also may not make your Account available to anyone else.

A5（同じ節に、競合サービスの開発と再販の禁止がある。確認）
> To develop any products or services that compete with our Services, including to develop or train any artificial intelligence or machine learning algorithms or models or resell the Services.

A5 は Claude Code に一度も言及しない（確認）。Claude Code の利用条件は A1 が「Pro・Max は Consumer Terms の対象」と案内している。

### 4.2 許可寄りの文

A1（Authentication and credential use の末尾。確認）
> Nor does it prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription, including where a platform hosts Claude Code as described under Can customers offer Claude Code in their products? above.

（「Nor」の前の文は、顧客が自分の API キーやクラウドプロバイダーの認証情報を設定するのを妨げない、という内容。）

A7 ヘルプ: Agent SDK とプラン（確認）
> Update October 7, 2026: Claude Max and Team plans now include monthly API credits, which cover the Claude Agent SDK, claude -p, the Claude API, and Claude Managed Agents. You can still use the Claude Agent SDK, claude -p, and third-party apps with your subscription limits.

> Update June 15, 2026: We've paused the previously-announced changes to Claude Agent SDK usage. For now, nothing has changed: Claude Agent SDK, claude -p, and third-party app usage still draw from your subscription limits.

A10 ヘルプ: 月次 API クレジット（確認）。Max と Team にだけ付く。対象は「The Claude Agent SDK」を含み、「Interactive Claude Code in the terminal, IDE, desktop, or web」は対象外。Pro と Enterprise は対象外。つまり Pro の利用者には、A7 の「サブスクの枠で使える」が引き続き唯一の経路になる（推測を含む読み方。A10 の原文は上のとおり）。

A3 ヘッドレス（確認）。`claude -p` は公式の機能で、Agent SDK の CLI 版として説明されている。冒頭に次の記述がある。
> The Agent SDK gives you the same tools, agent loop, and context management that power Claude Code. It's available as a CLI for scripts and CI/CD, or as Python and TypeScript packages for full programmatic control.

また、A3 は `--bare` について次のように書く（Koebumi は `--bare` を使っていない。使うとサブスクのログインを読まないため）。
> Set ANTHROPIC_API_KEY before running it, because bare mode doesn't use your subscription login

A2 認証（確認）。`claude setup-token` で作る 1 年間有効のトークンは「CI pipelines, scripts」向けで、「This token authenticates with your Claude subscription and requires a Pro, Max, Team, or Enterprise plan.」と書かれている。Koebumi はこれを使っていない。

### 4.3 過去の経緯（二次。一次情報の場所を探す手がかりとしてのみ）

検索結果に、2026 年 2 月にドキュメントの文言が変わり、サードパーティでのサブスクの OAuth 利用が「禁止」と読める形になった、という報道が複数出た（GIGAZINE、winbuzzer、alternativeto など）。2026 年 4 月にサードパーティのハーネスがサブスクの枠から外れた、という報道もあった。これらは二次情報で、私は本文を確認していない。一次情報では、今の A7 が「June 15, 2026 に変更を一時停止した」「October 7, 2026 時点でサブスクの枠で使える」と書いている。つまり、ルールが過去に何度か動いており、今後も動く可能性がある（推測）。A7 の「previously-announced changes」が何を指すかは、一次情報では確認できていない（第 8 節）。

## 5. OpenAI の条項

### 5.1 利用規約・ポリシー

O8 利用規約（Effective: January 1, 2026。Internet Archive の保存で確認）
> You may not share your account credentials or make your account available to anyone else and are responsible for all activities that occur under your account.

> What you cannot do. You may not use our Services for any illegal, harmful, or abusive activity. For example, you may not: ... Automatically or programmatically extract data or Output (defined below). ... Interfere with or disrupt our Services, including circumvent any rate limits or restrictions or bypass any protective measures or safety mitigations we put on our Services.

（引用中の「...」は私が省いた箇所。原文は箇条書きで、間に別の項目がある。）

> Third party Services. Our services may include third party software, products, or services, ("Third Party Services") ...

（これは OpenAI のサービスに含まれる他社サービスの話で、Koebumi のような外部アプリの話ではない。確認。）

O9 利用ポリシー（Effective: October 29, 2025。確認）。サブスク経由の利用や中継を名指しした条項は見つからなかった。関係しそうな文は次の 2 つだけ。
> breaking or circumventing our rules and safeguards may mean you lose access to our systems or experience other penalties.

> circumventing our safeguards

### 5.2 Codex のドキュメント

O1 Codex 認証（確認）
> Sign in with ChatGPT for subscription access

> Sign in with an API key for usage-based access

> Use API key authentication for programmatic Codex CLI workflows, such as CI/CD jobs.

> API keys are still the recommended default for automation.

> Codex caches login details locally in a plaintext file at ~/.codex/auth.json or in your OS-specific credential store. If you use file-based storage, treat ~/.codex/auth.json like a password: it contains access tokens.

O3 非対話モード（確認）
> codex exec reuses saved CLI authentication by default.

> API keys are the right default for automation because they are simpler to ...

（文は先が続く。同ページに、ChatGPT のログインを CI で使う「advanced」の手順が公式に載っている。）

O7 openai/codex README（確認）
> Run codex and select Sign in with ChatGPT. We recommend signing into your ChatGPT account to use Codex as part of your Plus, Pro, Business, Edu, or Enterprise plan.

O2 Codex App Server（確認）
> Codex app-server is the interface Codex uses to power rich clients (for example, the Codex VS Code extension). Use it when you want a deep integration inside your own product: authentication, conversation history, approvals, and streamed agent events.

> If you are automating jobs or running Codex in CI, use the Codex SDK instead.

> The app-server command and WebSocket transport are experimental and aren't supported for production workloads.

（最後の文は、WebSocket の節にある。stdio での利用そのものを指すのかは、原文から読み取れない。）

O2（Auth endpoints の冒頭。確認）。Koebumi に最も近い一文。
> If you've built a local or open-source application using Codex app-server authentication, you can continue using it, though we recommend migrating to Sign in with ChatGPT so users have greater control over and visibility into their usage. ... App-server authentication has never been permitted for commercial or hosted services. We launched Sign in with ChatGPT to support these use cases, and we're excited to see what you build.

O2（認証モード。確認）。`apikey`、`chatgpt`（「Codex owns the ChatGPT OAuth flow, persists tokens, and refreshes them automatically」）、`chatgptAuthTokens`（「experimental and intended for host apps that already own the user's ChatGPT auth lifecycle」）がある。Koebumi が使うのは、`chatgpt` モードで Codex が持っているログインを、そのまま使う形（推測。Koebumi は `account/login/start` を呼ばず、`account/read` だけを呼ぶため。ソースは確認済み）。

### 5.3 Sign in with ChatGPT（公式の第三者向け仕組み）

O5 利用者向け（確認）
> Sign in with ChatGPT lets you sign in to participating apps and sites with your ChatGPT account. In supported apps, eligible ChatGPT Plus and Pro subscribers can also choose to use their ChatGPT plan for AI requests.

> App usage counts toward your existing plan limits. Connecting an app does not add a new allowance, and the app may have its own fees.

同ページのパートナー一覧に、オープンソースとして OpenClaw、OpenCode、Pi、T3 が載っている（確認）。

O6 開発者向け（確認）
> For open-source developers: Let users run AI workloads in your tools with their ChatGPT plan, without requiring them to provide an API key.

> Sign in with ChatGPT is currently available to selected commercial partners through a limited trial. ChatGPT plan usage is available to all open-source partners and selected private clients.

> These docs explain ChatGPT plan usage for open-source and locally hosted apps. If you're interested in offering it in a paid or remotely hosted app, complete the interest form.

O6 の Codex app-server の節は、アプリが OAuth のアクセストークンを自分で取得して、子プロセスの app-server に渡す方式を説明している（確認）。クライアント ID の登録（Request a client ID）が前提になる。Koebumi はこの登録をしていない。

### 5.4 OpenAI の「公式発表」について

検索結果に、2026-09-29 に OpenAI が ChatGPT プランをサードパーティのツールで使えるようにした、という The New Stack の記事が出た（二次）。私は OpenAI 自身の発表ページを見つけられなかった（第 8 節）。一次情報としては、O5 と O6 が、その仕組みが現に公開されていることを示す。

## 6. README と features.md の記述の検証

| 記述 | 判定 | 根拠と補足 |
|---|---|---|
| Anthropic は他社のアプリが Claude.ai のログインやトークンを扱うことを認めていない | 正確 | A1「Anthropic does not permit third-party developers to offer Claude.ai login into their own applications」と「developers may not collect, store, or intermediate Claude.ai credentials or session tokens」（確認）。A4 の「Unless previously approved」の但し書きは書かれていない。Koebumi は扱っていないので、この文は Koebumi の方式の説明としても成立する |
| OpenAI は、プログラムから Codex を使う場合は API キーを使うよう案内している | 概ね正確。範囲を足すとよい | O1「Use API key authentication for programmatic Codex CLI workflows, such as CI/CD jobs.」。対象は CI/CD などの自動化。対話的な利用者が自分の Mac で使う場合は書かれていない（確認）。「案内している」は「推奨」であり禁止ではない |
| ChatGPT のサブスクを Codex 経由で使う方法は公式の連携ではない | 現状と合わない | O7 は ChatGPT でのサインインを推奨。O2 は app-server を「deep integration inside your own product」用と説明し、ローカル・オープンソースのアプリの利用継続を認めている。O5・O6 は、ChatGPT プランをサードパーティのオープンソースのアプリで使う仕組みを公式に提供している。ただし Koebumi の経路（利用者の Codex のログインを借りる）は、O6 の登録済みクライアントの方式ではない。「公式ドキュメントに載っている連携ではない」とは言えるが、「公式の連携ではない」だけでは、OpenAI が Sign in with ChatGPT を用意した事実と合わず、誤解を招く（推測を含む） |
| 使えなくなることがある（方針が変わる場合） | 妥当 | O2 が app-server を experimental と書いている。Anthropic も A7 のとおり、規則が過去に動いた |

## 7. エンジンごとの判定

### 7.1 Claude Code 経由

判定: グレー。

禁止に傾く読み方
- A1・A4・A8 は「サードパーティ開発者が、利用者の代わりにサブスクの認証情報を通して流す」ことを禁じる。Koebumi は、利用者の Mac のログイン済み Claude Code を、アプリが自動で何度も起動し、アプリの機能（整形・翻訳・Ask）のために使う。サブスクの枠を、サードパーティのアプリの機能の動力にしている点は同じに見える（推測）。
- A6（2026-11-12 発効）の「services that route requests through consumer subscriptions」は、中継サービス全般に読める。Koebumi は中継サーバーではなくローカルのアプリだが、文言上「サービス」と「サブスク経由」の両方を満たしうる（推測）。
- A5 の「automated or non-human means, whether through a bot, script, or otherwise」は、API キー以外の自動アクセスを禁じる。例外は「where we otherwise explicitly permit it」。Claude Code 自体が `claude -p` を公式機能として提供しているので、Claude Code の中での自動実行は許可の範囲と読める。Koebumi が外から呼ぶ場合が許可の範囲かは、文言から決まらない（推測）。
- A1 の「ordinary, individual usage」。ディクテーションは 1 日に何十回も呼ぶので、Claude Code の通常の使い方より回数が多くなりうる（推測）。

許可に傾く読み方
- A1 の末尾は、利用者が「unmodified Claude Code binary」に自分のサブスクでサインインすることを妨げない、と明記する。Koebumi は改変なしのバイナリを起動し、サインインは利用者自身が Claude Code で行う。トークンを集めない・保存しない・中継しない点で、A1 の「collect, store, or intermediate」にも当たらない（確認した事実と上の A1 の文言の照らし合わせ。当てはまるという結論は推測）。
- A7 は 2026-10-07 時点で「You can still use the Claude Agent SDK, claude -p, and third-party apps with your subscription limits.」と書く。`claude -p` と「third-party apps」を、サブスクの枠で使えるものとして名指ししている。これが Koebumi の使い方を指すかは分からないが、最も近い公式の文（推測）。
- A8 は、サードパーティのツールを「at its discretion allow」するとし、サブスクの枠ではなく usage credits から引く権利を留保している。つまり、サブスクの枠から外れて有料化される可能性が、公式に予告されている。

結論の置き方（推測）: 利用者本人が自分の環境で改変なしの Claude Code を使う、という構図は A1 の許可寄りの文に合う。一方、アプリがそれを製品機能として呼ぶ構図は、A6 の「route requests through consumer subscriptions」と、A8 の「route third-party traffic against subscription limits」に触れうる。どちらが優先されるかを示す一次情報はなかった。Anthropic に直接確認するのが、確実な唯一の方法（A1 は「contact sales」を案内している）。

### 7.2 Codex 経由

判定: 禁止ではない。許可寄りのグレー。

許可に傾く根拠
- O7 が ChatGPT でのサインインを推奨している。O1 が `codex exec` で保存済みの認証を再利用することを、仕様として書いている。
- O2 が、ローカル・オープンソースのアプリが app-server の認証を使い続けることを認め、「商用・ホスト型は不可」と線を引いている。Koebumi は無料のオープンソースで、利用者の Mac で動く。線の内側に入る（推測。O2 の「app-server authentication」が、Koebumi のように「Codex に任せたログインを使う」場合を含むかは原文から確定しない）。
- O5・O6 は、サードパーティのオープンソースのアプリが ChatGPT プランを使うことを、公式の機能として提供している。OpenAI の方針は「認める方向」だと読める（推測）。
- Koebumi は `clientInfo.name` に `koebumi` を渡している。O2 は、この値をコンプライアンスログでクライアントを識別するために使うと書く（確認）。実装は文書の想定に沿っている。

注意が要る根拠
- O2 の「never been permitted for commercial or hosted services」。Koebumi は今は無料だが、将来有料化したり、サーバー側で動かしたりすると線を越える（確認した文言からの推測）。
- O8 の「Automatically or programmatically extract data or Output」と「circumvent any rate limits or restrictions」。文言は広いが、OpenAI 自身が Codex の app-server・SDK・`codex exec` を公式に用意しているので、Codex の公式インターフェースを通る限り、この条項の対象とは読みにくい（推測）。
- O2 が app-server を「experimental」と書いている。プロトコルが変わると動かなくなる。規約の問題ではなく、技術的な安定性の問題。
- O6 の公式の経路は「クライアント ID を登録し、OAuth でトークンを得る」。Koebumi はこれをしていない。OpenAI が公式に想定する形からは外れる。

結論の置き方（推測）: 規約違反になる根拠は見つからず、むしろ OpenAI は第三者のオープンソースアプリが ChatGPT プランを使う方向に動いている。最も安全に寄せるなら、Koebumi が O6 の Sign in with ChatGPT の登録クライアントになる（大きな実装の変更になる。Koebumi は今は「トークンに触れない」を売りにしており、方針が変わる）。

## 8. 取得できなかったもの・確認できなかったもの

- OpenAI のヘルプセンター「Using Codex with your ChatGPT plan」（https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan）。HTTP 403 で本文を取得できなかった。検索結果の要約（二次）によれば、ChatGPT のサインインはプランの利用枠と課金、API キーは API 料金、という内容。第三者ツールに関する記述の有無は未確認。
- OpenAI のサービス規約（Service Terms）、ビジネス規約、Codex 固有の規約。openai.com が 403 で、Internet Archive でも取得していない。O8 の本文は「Service Terms」を含むと書いている。Codex や ChatGPT プランの第三者利用に関する追加条項があるかは未確認。
- OpenAI の Sign in with ChatGPT の公式発表ページ（ブログやリリースノート）。見つけられなかった。O5・O6 の公開は確認できたが、公開日は一次情報では確認できていない（The New Stack は 2026-09-29 と報じている。二次）。
- O6 の「Request a client ID」と「UI/UX guidelines」の条件の全文。登録の審査基準や、利用者に表示すべき文言は読んでいない。
- Anthropic の A7 が言う「previously-announced changes to Claude Agent SDK usage」の中身。一次情報（Anthropic のブログ・メール・ヘルプの旧版）を見つけられなかった。
- A6 利用ポリシーの旧版（2026-11-12 より前）の同じ節の文言。バージョン履歴は取得していない。「services that route requests through consumer subscriptions」が新しい文なのか、以前からあった文なのかは未確認。
- Anthropic の Commercial Terms（https://www.anthropic.com/legal/commercial-terms）。取得していない。A1 は、Claude Code を製品に組み込む顧客に Commercial Terms への同意を求める。Koebumi が「製品に Claude Code を組み込んでいる」側に当たるかは、A1 の文言（preinstalling or running Claude Code in your products or services）からは判断できない。Koebumi は Claude Code を同梱せず、利用者が自分で入れる。この点は推測。
- Anthropic・OpenAI のどちらも、Koebumi のような「アプリがユーザーのログイン済み CLI を子プロセスとして呼ぶ」形を名指しした記述は見つからなかった（検索語: `claude -p` third-party、subprocess、wrapper、app-server third-party。ページ内の全文検索ではなく、読んだページとサイト内検索の範囲）。
- `claude --help` と `codex login --help` は実行して中身を見た。プロンプトを送るコマンドは実行していない。

## 9. 判断のための選択肢（Koebumi 側の対応）

どれを選ぶかは決めない。以下は、上の調査から言える利点と欠点。

### 9.1 README と features.md の書き換え

Anthropic について（現行の記述は正確。足せるもの）
- 案 A: 現状のまま。正確で、短い。
- 案 B: 「Koebumi は Claude のトークンやログイン情報を読まず、利用者が入れた Claude Code を動かすだけです。Anthropic の規約が変わると使えなくなることがあります」のように、Koebumi の側の事実と、変わりうることを書く。A8 が「サブスクの枠から usage credits に切り替える権利」を留保しているので、「サブスクの枠ではなく従量課金になる可能性がある」まで書くかを選べる。
- 案 C: 「Anthropic は、サードパーティのアプリがサブスクの枠を使うことを、裁量で認めています」のような積極的な書き方は避ける。A8 の「at its discretion」と A7 の更新履歴から、根拠が動きうるため。

OpenAI について（現行の記述に誤解を招く部分がある）
- 案 D: 「公式の連携ではない」を削る。「OpenAI は、自動化には API キーを勧めています」だけ残す。
- 案 E: 「Codex 経由は、OpenAI の公式の仕組み（Sign in with ChatGPT）とは別の経路で、OpenAI の方針が変わると使えなくなることがあります」と、事実を分けて書く。
- 案 F: Sign in with ChatGPT に対応してから、「公式の仕組みで対応」と書く（9.2 の案 4）。

features.md L103 と README L76、ClaudeCodeEngine.swift L4 のコメントは、同じ趣旨を別々の言い方で書いている。直すときは 3 か所を合わせる必要がある。

### 9.2 エンジンの扱い

| 案 | 内容 | 利点 | 欠点・リスク |
|---|---|---|---|
| 1 現状のまま残す | 設定で選べる。既定は Apple のまま（現状も既定ではない） | 利用者の選択肢が減らない。実装の変更なし | 規約が動いたときに、アプリが規約違反の機能を配っている形になる。特に Claude Code は、A6 発効後に「サブスク経由のサービス」と見なされる可能性がある（推測） |
| 2 初回に警告を出す | エンジンを選ぶときに 1 回、「Anthropic／OpenAI の規約に従って使ってください。規約の変更で使えなくなったり、従量課金になることがあります」と確認を出し、同意しないと有効にならない | 利用者が危険を知った上で選んだ、という形が作れる。実装が小さい | 警告は法的な免責にならない（推測）。文言で「違反ではない」と言い切れないので、書き方が難しい |
| 3 エンジンごとに分ける | Codex は残し、Claude Code だけ警告付き、または外す | 一次情報のリスクの差を反映できる。OpenAI 側は公式の動きが許可寄り | 同じ見た目の 2 つの機能で扱いが違う理由の説明が要る。Anthropic に確認した結果によっては見直しになる |
| 4 Codex を Sign in with ChatGPT に移す | O6 の登録クライアントになり、OAuth でトークンを得る | OpenAI の公式の仕組みに乗る。「公式の連携」と書ける | 「トークンに触れない」という現在の売りが変わる。トークンの保存・更新・失効の実装と、クライアント ID の登録が要る。実装が大きい。審査の条件は未確認（第 8 節） |
| 5 Claude Code エンジンを外す | API キー（Claude）に一本化する | Anthropic の規約リスクがなくなる | Pro・Max の利用者が、追加の料金なしで Claude を使えなくなる。Max と Team には A10 の月次 API クレジットがあるが、Pro にはない |
| 6 Anthropic に問い合わせる | A1 が案内する窓口（contact sales）に、Koebumi の方式を説明して確認する | 一次の答えが得られる唯一の方法 | 返答が来ない、または一般的な回答になる可能性がある。回答は文書として残す |
| 7 既定でオフにして、非表示の設定にする | 設定の通常の一覧には出さず、「実験的」の中に置く | 目立たなくでき、利用者が自分で探した場合だけ使われる | 隠すこと自体が、疑わしいという印象を与えうる。README に書くなら意味が薄い |

案は組み合わせられる。たとえば「案 6 を先にやり、返答が来るまで案 2 と案 3 を適用する」。

### 9.3 判断の前に確かめるとよい点

- 2026-11-12 に A6 の利用ポリシーが発効する。Anthropic について、結論を急ぐなら、この日の前後で A1・A7・A8 の文言が変わらないかを再確認する。
- Koebumi が将来有料化・ホスト型にする予定があるか。ある場合は、O2 の「commercial or hosted services には認めない」に直接かかる。
- 回数の問題。ディクテーションの利用頻度の実測（1 日の呼び出し回数）。A1 の「ordinary, individual usage」と照らす材料になる。
