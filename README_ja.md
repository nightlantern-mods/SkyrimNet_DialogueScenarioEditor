# SkyrimNet Dialogue Scenario Editor 0.3.4（ダイアログシナリオエディタ）

> [!CAUTION]
> **成人向けの内容を含みます。** シナリオは性的なシーン（OStim または SexLab）で終わることがあります。18 歳未満の方は使わないでください。

近くにいる実際の NPC が演じる、短いシナリオを作れる MOD です。誰が参加するか、どんな状況か、誰が何を言うか、そのあと性的なシーンに進むかを決められます。シナリオ全体を NPC に書かせることもできます。セリフは SkyrimNet の AI が話し手らしい言葉で話すので、同じシナリオがどんなキャラクターにも合います。

英語の説明は `README.md` にあります。

## できること

- **列で組み立てるシナリオ**：1 つのシナリオは最大 10 列で、左の列から順に進みます。各列には次のものを決められます。
  - 参加キャラ 1〜3 人（プレイヤーも可）
  - 状況を示すナレーション
  - 最大 10 個のセリフ（順番も話し手も自由。同じ人が何度話しても構いません）
  - 列の終わり方：なし（セリフだけ）、セックスシーン（タグを選べます。近くのベッドで始めることもできます。OStim か SexLab P+ / 1.6x。両方あるときは MCM で選びます）、**シーンを終わらせる**（参加キャラが入っているシーンを終わらせます）、**移動して待機**（選んだ人が室内の場所へ歩いて行き、別のシナリオが終わるか何日かたつまでそこで待ちます）、**SkyrimNet のアクション**（参加者の 1 人が実行します。入っている MOD のアクションだけを選べます。例：SeverActions）

  同じ人を複数の列に入れられます。1 人だけの列はオナニーのシーンにできます。
- **話し手らしい言葉で話す**：セリフはそのまま読み上げられません。SkyrimNet に「話し手は今から、こういう意味のことを言おうとしている」と伝え、AI がそのキャラクターらしい言葉にします。プレイヤーのセリフは、SkyrimNet を通してプレイヤーのキャラクターが話します。
- **オート**：セリフ 1 つずつ、または列全体（短 3・中 6・長 10 回）を「オート」にできます。オートのセリフは、話す番が来たときに AI が作ります。手がかりは、その列のナレーション、前後の列、それまでの会話です。
- **全生成**：シナリオライター（NPC）、参加者（NPC とプレイヤーから 2〜10 人）、列の数、必要ならテーマを選びます。ライターがその人らしい作風で全部の列を書きます。各列の参加キャラ、ナレーション、話し手つきのセリフ、セックスシーンがふさわしい列とそのタグです。参考にするのは、参加者の BIO・記憶・最近の出来事・最新の日記と、[SN Sexual Memories](https://github.com/nightlantern-mods/SN_SexualMemories) の相関図（あれば）です。結果は編集画面に入るので、確認・修正してから保存します。**限定生成（セリフはオート）** は、各列の参加キャラ・ナレーション・セックスシーン（タグ）だけを書き、セリフはオート（中）にします（ゲーム内でその場で作られます）。
- **始まる条件**：参加者全員がプレイヤーの近く（同じ室内、または屋外でそばにいる）にいると始まります。次のことを選べます。
  - 自動で始まるか、ホットキー（MCM で設定）を押したときに始まるか
  - ほかの人がいてもよいか、参加者だけのときか
  - 室内・室外・どちらでもか
  - 特定のセルだけにするか（室内の場所の一覧から選ぶか、今いるセル）
  - 1 回だけか、何日かごとに繰り返すか（0 日なら、その場所に入り直すたびに始まります）
  - 先に終わっている必要があるシナリオ（前提）
- **列の進み方**：参加者がプレイヤーのところへ（プレイヤーが列にいないときは 1 人目のところへ）歩いて集まります。数秒たっても来ない人は移動させます。話しているあいだは近くにとどまります。そのあと列の終わり方（セックスシーン、シーンを終わらせる、移動して待機、アクション）に進み、話している人が話し終わったら次の列に進みます（最大 20 秒。それでも残っている発話は捨てます）。シナリオの途中でプレイヤーがその場所を離れると（別のセルに入る、屋外で遠く離れる）、シナリオは中止され、まだ起きていない扱いになります（あとでまた始まります）。
- **セックスシーンの選び方**：タグにいちばん合うシーンを選びます。まずタグを全部持つシーン、次に何をするかを表すタグ（体位や行為）を持つシーンで、雰囲気のタグ（ロマンチック・激しい・支配）だけが合うシーンは最後です。「ベッドを使う」にすると、近くの空いているベッドでシーンを始めます。プレイヤーが参加するときは、始める直前に全員をベッドへ移します。前の列のシーンに同じ顔ぶれだけでいるときは、シーンを続けたままアニメだけを切り替えます（立ち上がって服を着ることはありません）。顔ぶれが違うときは、そのシーンを止めてから新しいシーンを始めます（そのシーンにいた全員のシーンが終わります）。

## 前提 MOD

- [SKSE64](https://skse.silverlock.org/) と [Address Library for SKSE Plugins](https://www.nexusmods.com/skyrimspecialedition/mods/32444)
- [SkyrimNet](https://www.nexusmods.com/skyrimspecialedition/mods/198346)
- セックスシーン用に [OStim Standalone](https://www.nexusmods.com/skyrimspecialedition/mods/98163) か [SexLab P+](https://www.loverslab.com/files/file/31574-sexlab-p/) / SexLab 1.6x のどちらか（なくても、会話・移動して待機・アクションのシナリオは動きます）
- [PapyrusUtil SE](https://www.nexusmods.com/skyrimspecialedition/mods/13048)
- [powerofthree's Papyrus Extender](https://www.nexusmods.com/skyrimspecialedition/mods/22854)
- [MCM Helper](https://www.nexusmods.com/skyrimspecialedition/mods/53000) と [SkyUI](https://www.nexusmods.com/skyrimspecialedition/mods/12604)
- 設定画面用に [Magelight UI](https://www.nexusmods.com/skyrimspecialedition/mods/193303) か [Prisma UI](https://www.nexusmods.com/skyrimspecialedition/mods/148718) のどちらか。両方あるときは Magelight UI を使います。動作確認は Magelight UI で行いました。Prisma UI での画面は、まだゲーム内で確認していません。

任意：[SN Sexual Memories](https://github.com/nightlantern-mods/SN_SexualMemories)（全生成でその相関図を使います）

動作確認した環境：Skyrim SE 1.6.1170、SkyrimNet（Nexus 版 2026-11-16）、OStim Standalone 7.5.1、SexLab P+、PapyrusUtil 4.6、powerofthree's Papyrus Extender 6.5.2、MCM Helper 1.6.2、SkyUI 6.11、Magelight UI 16

## 導入

Mod Organizer 2 か Vortex で、アーカイブをそのままインストールしてください。インストーラーで、設定メニューと設定画面の言語（English / 日本語）を選べます。ゲーム本体の言語は問いません。MOD マネージャーを使わない場合は、`core/ja`（または `core/en`）の中身を `Data` にコピーしてください。

## 使い方

1. MCM の **SkyrimNet Dialogue Scenario Editor** で「設定画面を開くキー」を割り当てます。最初は割り当てていません。
2. そのキーを押して設定画面を開きます。「新しいイベント」を押し、名前（半角英数字と `_` `-`）を付けて列を埋めるか、「全生成」を使います。
3. 「保存」を押します。一覧の各イベントの横のスイッチで、すぐに有効／無効を切り替えられます。
4. 有効なシナリオの参加者がいる場所に行くと、全員がそろったときに始まります（ホットキーのシナリオは、MCM の「ホットキーのシナリオを始めるキー」を押したときに始まります）。

画面上部の「画面の大きさ」で、設定画面全体を拡大・縮小できます（70〜200%）。スライダーをドラッグするか、−／+ を押します。大きさは次に開いたときも保たれます。

無効にした例 `example_riverwood` を同梱しています。削除したシナリオは、MOD を更新しても削除されたままです。

このセーブで実行したシナリオには、一覧に「済」が付きます。編集画面には、いつ始まったか、最後まで終わったか、セルを出るまで始まらないセルが出ます。「実行済みをクリア」（2 回押します）で、まだ一度も起きていない扱いに戻せます。

### 除外するシーン

「新しいイベント」の下の「除外するシーン」に、選ばせたくないセックスシーンを書けます（全シナリオ共通）。1 行に 1 つシーン ID を書くと、ID がその文字で始まるシーンはすべて選ばれなくなります（`BillyyCcg` と書くと BillyyCcg-1、BillyyCcg-2… が外れます）。最初は空です。ログには、シーンを始める直前にそのシーンの名前が出ます（`OStim scene ～`。SexLab は始まったあとに `scene ～`）。うまく動かないシーンは、そこで名前を調べて書き加えられます。

### 全生成の AI モデル

全生成では、筋書きに 1 回、列ごとに 1 回ずつ SkyrimNet の AI に依頼します。使うモデルは、SkyrimNet のダッシュボードの **AI > モデル** にある `dialogue_scenario_writer` で設定します。空欄なら SkyrimNet の default のモデルが使われます。答えは JSON なので、指示に忠実なモデルが向いています。

### シナリオの保存場所

シナリオは 1 つずつ JSON ファイルとして `Data/SKSE/Plugins/StorageUtilData/SkyrimNet_DialogueScenarioEditor/` に保存されます（Mod Organizer 2 では新しいファイルは overwrite に入ります）。どのセーブでも同じシナリオが使われます。そのシナリオがもう起きたかどうかは、セーブデータに記録されます。

### うまく動かないとき：ログ

MOD の動きは `Documents\My Games\Skyrim Special Edition\SKSE\SkyrimNet_DialogueScenarioEditor.log` に記録されます（INI の設定は不要）。ロードのたびにシナリオの一覧と SkyrimNet の音声設定を、シナリオが始まらない理由を（理由が変わるたびに 1 回）、実行中はセリフごとの話者・SkyrimNet の音声イベント・待ち時間を書きます。ゲームを起動するたびに作り直されるので、問題が起きたら次に起動する前に（`SKSE\SkyrimNet.log` と一緒に）コピーしてください。

## わかっている制限

- 椅子に座っている NPC は、歩いて集まるために立ち上がらないことがあります。数秒たつと移動させます。
- Prisma UI：対応していますが、まだゲーム内で確認していません。
- SexLab：ベッドの設定と、次の列に続くシーンのアニメ切り替えは、OStim でしかゲーム内で確認していません。
- 列の最後に設定したアクションとは別に、SkyrimNet 自身がナレーションやセリフの内容を見てアクション（喧嘩、物を渡す、ついて行く、など）を選ぶことがあります。セリフをオートにすると、この傾向が強くなります。設定した場所で確実にアクションを起こしたいときは、ナレーションとセリフはその直前まで（殴るのではなく言い争いまで）にして、開始は列の最後のアクションにまかせてください。

## ライセンスと権利表記

- この MOD（スクリプト、プラグイン、設定画面、プロンプト、文言）は © 2026 takafumi、**MIT ライセンス**です（THIRD_PARTY_NOTICES.txt の 1 節）。SkyrimNet 用の 2 つのプロンプト（`dse_scenario_plan`、`dse_scenario_column`）はこの MOD のために書いたものです。SkyrimNet のテンプレート関数とイベント履歴の部品を呼び出しますが、それらは同梱していません。
- **SKSE/Plugins/SkyrimNet_DialogueScenarioEditor.dll** は CommonLibSSE NG（GPL-3.0-or-later、Modding Exception と GPL-3.0 Linking Exception 付き）を静的にリンクしているため、**GNU General Public License 第 3 版以降**で配布します（COPYING.txt）。DLL の完全なソースとビルド用ファイルは `Source/SKSE/SkyrimNet_DialogueScenarioEditor/` に、Papyrus のソースは `Source/Scripts/` に入っています。
- DLL には、SkyrimNet のプラグイン API ヘッダ（MIT、© Fateless.Ai）、Prisma UI の API ヘッダ、JSON for Modern C++、spdlog、DirectXMath、DirectX Tool Kit、rapidcsv も含まれます。それぞれのライセンスは **THIRD_PARTY_NOTICES.txt** にあります。
- SkyrimNet、OStim、SexLab、PapyrusUtil、powerofthree's Papyrus Extender、MCM Helper、SkyUI、Magelight UI、Prisma UI、SN Sexual Memories は、それぞれの作者による別の MOD で、この MOD には含まれていません。
- これは非公式のファンメイド MOD です。Bethesda Softworks、ZeniMax Media、Fateless.Ai、上記 MOD の作者が作成・承認・サポートしているものではありません。The Elder Scrolls と Skyrim は ZeniMax Media Inc. の商標です。
