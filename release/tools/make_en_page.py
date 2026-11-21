# Writes the English settings page from the Japanese one (the page is edited in Japanese, in the
# mod project's assets/Magelight/.../views/index.html). Every pair below must be found, and no
# Japanese may be left afterwards except in ALLOWED (words the page recognises in old files).
#
# usage: python -I make_en_page.py <japanese index.html> <english index.html>
import re
import sys

PAIRS = [
    ('<html lang="ja">', '<html lang="en">'),
    ('<h1>ダイアログシナリオエディタ</h1>', '<h1>Dialogue Scenario Editor</h1>'),
    ('この画面を開くキーは MCM で変えられます', 'The key that opens this page is set in the MCM'),
    ('title="閉じる">✕ 閉じる</button>', 'title="Close">✕ Close</button>'),
    ('イベント一覧<br><span class="hint">右のスイッチで有効／無効（すぐ保存されます）</span>',
     'Events<br><span class="hint">The switch turns an event on or off (saved at once)</span>'),
    ('＋ 新しいイベント', '+ New event'),
    ('左の一覧からイベントを選ぶか、「新しいイベント」を押してください。', 'Pick an event on the left, or press "New event".'),
    ('class="danger">削除</button>', 'class="danger">Delete</button>'),
    ('class="primary">保存</button>', 'class="primary">Save</button>'),
    ('placeholder="名前で検索"><button id="pclose">キャンセル</button>', 'placeholder="Search by name"><button id="pclose">Cancel</button>'),
    ('すべての NPC を読み込む', 'Load every NPC'),
    ('<h2>保存していない変更があります</h2>', '<h2>Unsaved changes</h2>'),
    ('<button id="cBack">戻る</button>', '<button id="cBack">Back</button>'),
    ('class="danger">保存せずに閉じる</button>', 'class="danger">Close without saving</button>'),
    ('<button id="cSave">保存して閉じる</button>', '<button id="cSave">Save and close</button>'),
    ('const PLAYER_SPEC = "{プレイヤー}";', 'const PLAYER_SPEC = "{player}";'),
    ('["missionary","正常位"],["doggystyle","後背位"],["cowgirl","騎乗位"],["reversecowgirl","背面騎乗位"],["standing","立位"],',
     '["missionary","Missionary"],["doggystyle","Doggy style"],["cowgirl","Cowgirl"],["reversecowgirl","Reverse cowgirl"],["standing","Standing"],'),
    ('["spooning","側位"],["prone","寝バック"],["matingpress","種付けプレス"],["lap","膝の上"],["carry","抱え上げ"],["butterfly","バタフライ"],',
     '["spooning","Spooning"],["prone","Prone"],["matingpress","Mating press"],["lap","On the lap"],["carry","Carry"],["butterfly","Butterfly"],'),
    ('["sixtynine","69"],["facesitting","顔面騎乗"],["spitroast","前後から"],["romantic","ロマンチック"],["lustful","激しい"],["dom","支配"],',
     '["sixtynine","69"],["facesitting","Facesitting"],["spitroast","Spitroast"],["romantic","Romantic"],["lustful","Lustful"],["dom","Dominant"],'),
    ('["femdom","女性が支配"],["foreplay","前戯"],["kissing","キス"],["oral","オーラル"],["blowjob","フェラ"],["anal","アナル"],["dp","二穴"],',
     '["femdom","Femdom"],["foreplay","Foreplay"],["kissing","Kissing"],["oral","Oral"],["blowjob","Blowjob"],["anal","Anal"],["dp","Double penetration"],'),
    ('["vaginalsex","膣性交"],["analsex","アナル性交"],["handjob","手コキ"],["cunnilingus","クンニ"],["hug","ハグ"],["boobjob","パイズリ"],["footjob","足コキ"],',
     '["vaginalsex","Vaginal sex"],["analsex","Anal sex"],["handjob","Handjob"],["cunnilingus","Cunnilingus"],["hug","Hug"],["boobjob","Boobjob"],["footjob","Footjob"],'),
    ('["femalemasturbation","オナニー（女）"],["malemasturbation","オナニー（男）"],["vaginaltoying","おもちゃ（前）"],["analtoying","おもちゃ（後ろ）"]];',
     '["femalemasturbation","Masturbation (female)"],["malemasturbation","Masturbation (male)"],["vaginaltoying","Toy (vaginal)"],["analtoying","Toy (anal)"]];'),
    ('"読み込み中… " + Math.floor(at * 100 / Math.max(1, total)) + "%（数分かかることがあります）"',
     '"Loading... " + Math.floor(at * 100 / Math.max(1, total)) + "% (this can take a few minutes)"'),
    ('+ " 人の NPC を読み込みました"', '+ " NPCs loaded"'),
    ('msg("保存できませんでした。", "err")', 'msg("Could not save.", "err")'),
    ('msg("「" + name + "」を" + (s && s.enabled ? "有効" : "無効") + "にしました。", "ok");',
     'msg("\\"" + name + "\\" is now " + (s && s.enabled ? "on" : "off") + ".", "ok");'),
    ('msg("保存しました。", "ok")', 'msg("Saved.", "ok")'),
    ('msg("削除しました。", "ok")', 'msg("Deleted.", "ok")'),
    ('AUTONAMES = ["短", "中", "長"];', 'AUTONAMES = ["Short", "Medium", "Long"];'),
    ('return isPlayer(a.spec) ? "プレイヤー（" + S.player + "）" : a.label;', 'return isPlayer(a.spec) ? "Player (" + S.player + ")" : a.label;'),
    ('title="有効／無効"', 'title="On / off"'),
    ('msg("保存しています…");', 'msg("Saving...");'),
    ('msg("保存していない変更があります。もう一度押すと変更を捨てて移動します。", "err");',
     'msg("There are unsaved changes. Press again to drop them and move on.", "err");'),
    ('<span class="lbl">名前</span>', '<span class="lbl">Name</span>'),
    ('半角英数字と _ - だけ（ファイル名になります）', 'Letters, digits, _ and - only (it becomes the file name)'),
    ('<span class="lbl">発火条件</span>', '<span class="lbl">Starts when</span>'),
    ('> 対象キャラ以外がいても OK（子供がいるときは発火しない）</label>', '> Others may be around (never with children nearby)</label>'),
    ('> 対象キャラのみ</label>', '> Only the people in it are around</label>'),
    ('<span class="lbl">発火回数</span>', '<span class="lbl">How often</span>'),
    ('> 1 回だけ</label>', '> Once</label>'),
    ("> 繰り返し</label>", "> Again and again</label>"),
    ('"> 日ごと"', '"> days apart"'),
    ('0 にすると、セルを出て入り直すたびに発火します', '0: every time you come back to the place'),
    ('<span class="lbl">場所</span>', '<span class="lbl">Where</span>'),
    ('[["0", "どちらでも"], ["1", "室内のみ"], ["2", "室外のみ"]]', '[["0", "Anywhere"], ["1", "Indoors only"], ["2", "Outdoors only"]]'),
    ('(c + 1) + " 列目" + (c === 0 ? \' <span class="req">必須</span>\' : \' <span class="req">空なら使わない</span>\')',
     '"Column " + (c + 1) + (c === 0 ? \' <span class="req">required</span>\' : \' <span class="req">skipped when empty</span>\')'),
    ('参加キャラ（1〜3 人。別の列と同じキャラでも可。1 人ならタグなしでオナニーのシーン）',
     'People (1 to 3; the same person may be in other columns too; one person alone: a masturbation scene when no tag is chosen)'),
    ('>＋ 選ぶ</button>', '>+ Choose</button>'),
    ('ナレーター（状況の説明。誰も反応せず、会話の背景になります）</div><textarea data-nar="\' + c + \'" placeholder="例：みんな泥酔している">',
     'Narration (the situation; nobody answers it, it sets the background of the talk)</div><textarea data-nar="\' + c + \'" placeholder="e.g. Everyone is drunk">'),
    ('> この列のセリフをすべてオート</label>', '> Every line of this column is Auto</label>'),
    ('セリフ（上から順に話します。AI がそのキャラらしく言い換えます。{プレイヤー} は名前になります）',
     'Lines (spoken from the top; the AI rewords each one in the voice of the speaker; {player} becomes the name)'),
    ('ナレーションと前後の列、それまでの会話をもとに、AI がその場でセリフを作ります。\' +',
     'The AI makes up each line when it is spoken, from the narration, the columns before and after, and the talk so far. \' +'),
    ('AUTONAMES[col.autolen] + "：" + AUTOLINES[col.autolen] + " 回。参加キャラが順番に話します" + (col.actors.length === 1 ? "（1 人なら独り言）" : "") + "。</div>";',
     'AUTONAMES[col.autolen] + ": " + AUTOLINES[col.autolen] + " lines. The people take turns" + (col.actors.length === 1 ? " (one person talks to themselves)" : "") + ".</div>";'),
    ('title="AI がその場でセリフを作ります"', 'title="The AI makes up this line when it is spoken"'),
    ('>オート</label>', '>Auto</label>'),
    ('placeholder="セリフ"', 'placeholder="Line"'),
    ('\'">＋ セリフを追加（\' + col.lines.length + "/" + MAXLINES + "）</button>"', '\'">+ Add a line (\' + col.lines.length + "/" + MAXLINES + ")</button>"'),
    ('> セリフのあと OStim シーンを始める</label>', '> Start an OStim scene after the lines</label>'),
    ('オフにすると、セリフだけの列になります。前の列のシーン中のキャラは、そのシーンを止めてから新しいシーンを始めます（同じシーンにいた全員のシーンが終わります）。',
     'Off: this column is talk only. Anyone still in a scene from an earlier column is taken out of it before the new scene starts (that scene ends for everyone in it).'),
    ('OStim タグ（どれかに合うシーンを選びます。なしならおまかせ）', 'OStim tags (a scene matching any of them is chosen; none: any scene)'),
    ('候補にないタグ（カンマ区切り）', 'Other tags (comma separated)'),
    ('＋ 列を追加<br>', '+ Add a column<br>'),
    ('<h2>AI でシナリオを作る（全生成）</h2>', '<h2>Let the AI write the scenario (Generate)</h2>'),
    ('シナリオライターに選んだ NPC が、その人らしい作風で全部の列（参加キャラ・ナレーション・セリフ・OStim）を書きます。参加者の BIO・記憶・最近の出来事・日記を参考にし、SN Sexual Memories の相関図があればそれも使います。結果は下の列に入るので、確認・修正してから保存してください。',
     'The NPC chosen as the scenario writer writes every column (people, narration, lines, OStim) in their own style. It draws on the bios, memories, recent events and diaries of the people, and on the relationship maps of SN Sexual Memories when there are any. The result goes into the columns below: check it, change what you like, then save.'),
    ('<span class="lbl">テーマ</span>', '<span class="lbl">Theme</span>'),
    ('placeholder="例：酒場で再会した二人。昔の誤解が解けて、思いが通じ合う（空欄ならライターにおまかせ）"',
     'placeholder="e.g. Two old friends meet again at the inn; an old misunderstanding is cleared up (empty: the writer decides)"'),
    ('<span class="lbl">シナリオライター</span>', '<span class="lbl">Scenario writer</span>'),
    ('(g.writer ? "変える" : "＋ 選ぶ")', '(g.writer ? "Change" : "+ Choose")'),
    ('BIO の性格が作風になります', 'Their personality sets the style'),
    ('\'<div class="grow"><span class="lbl">参加者（\' + GEN_MIN + "〜" + GEN_MAX + \' 人）</span>',
     '\'<div class="grow"><span class="lbl">People (\' + GEN_MIN + " to " + GEN_MAX + \')</span>'),
    ('>＋ 追加</button>', '>+ Add</button>'),
    ('<span class="lbl">列の数</span>', '<span class="lbl">Columns</span>'),
    ('>✦ 生成する</button>', '>✦ Generate</button>'),
    ('genStatus("シナリオライターを選んでください。", "err")', 'genStatus("Choose a scenario writer.", "err")'),
    ('genStatus("参加者を " + GEN_MIN + " 人以上選んでください。", "err")', 'genStatus("Choose at least " + GEN_MIN + " people.", "err")'),
    ('genStatus("今の列の内容は生成結果で置き換わります。よければもう一度「生成する」を押してください。", "err")',
     'genStatus("The columns will be replaced by what is generated. Press Generate again to go ahead.", "err")'),
    ('genStatus("生成を始めます…", "")', 'genStatus("Starting...", "")'),
    ('nodll: "DLL（SkyrimNet_DialogueScenarioEditor.dll）が読み込まれていないため生成できません。",',
     'nodll: "Cannot generate: SkyrimNet_DialogueScenarioEditor.dll is not loaded.",'),
    ('noapi: "SkyrimNet の機能が見つからないため生成できません。SkyrimNet が動いているか確認してください。",',
     'noapi: "Cannot generate: SkyrimNet was not found. Check that SkyrimNet is running.",'),
    ('busy: "別の生成がまだ終わっていません。少し待ってください。",', 'busy: "Another scenario is still being written. Wait a moment.",'),
    ('nobody: "選んだ人がゲーム内で見つかりませんでした",', 'nobody: "Someone you chose was not found in the game",'),
    ('llm: "AI が答えませんでした。SkyrimNet のダッシュボード「AI > モデル」の dialogue_scenario_writer のモデルを確認してください",',
     'llm: "The AI did not answer. Check the model of dialogue_scenario_writer in SkyrimNet\'s dashboard: AI > Models",'),
    ('badanswer: "AI の答えを読み取れませんでした。もう一度試すか、dialogue_scenario_writer のモデルを変えてください。",',
     'badanswer: "The AI\'s answer could not be read. Try again, or change the model of dialogue_scenario_writer.",'),
    ('badrequest: "生成の依頼を作れませんでした。",', 'badrequest: "The request could not be made.",'),
    ('genStatus("生成中… " + m.step + "/" + m.total + (m.what === "plan" ? "（筋書き）" : "（" + (m.step - 1) + " 列目）"), "")',
     'genStatus("Writing... " + m.step + "/" + m.total + (m.what === "plan" ? " (plot)" : " (column " + (m.step - 1) + ")"), "")'),
    ('genStatus("筋書きができました：「" + (m.title || "") + "」。列を書いています…", "")',
     'genStatus("Plot done: \\"" + (m.title || "") + "\\". Writing the columns...", "")'),
    ('(GEN_ERRORS[m.code] || "生成できませんでした") + (m.detail ? "（" + m.detail + "）" : "")',
     '(GEN_ERRORS[m.code] || "Could not generate") + (m.detail ? " (" + m.detail + ")" : "")'),
    ('genStatus("生成は終わりましたが、別のイベントに移ったため反映しませんでした。", "err")',
     'genStatus("Generating finished, but another event is open now, so the result was not put in.", "err")'),
    ('genStatus("「" + (m.title || d.name) + "」を生成しました。" + (m.plot ? "筋書き：" + m.plot + " " : "") + "内容を確認して保存してください。", "ok")',
     'genStatus("Generated \\"" + (m.title || d.name) + "\\". " + (m.plot ? "Plot: " + m.plot + " " : "") + "Check it, then save.", "ok")'),
    ('(!q || "プレイヤー".includes(q) || S.player.toLowerCase().includes(q))', '(!q || "player".includes(q) || S.player.toLowerCase().includes(q))'),
    ('<div class="grp">プレイヤー</div>', '<div class="grp">Player</div>'),
    ('esc("プレイヤー（" + S.player + "）")', 'esc("Player (" + S.player + ")")'),
    ('<div class="grp">近くにいる NPC</div>', '<div class="grp">NPCs nearby</div>'),
    ('\'<div class="grp">すべての NPC（\' + all.length + "）</div>"', '\'<div class="grp">All NPCs (\' + all.length + ")</div>"'),
    ('\'<div class="grp" style="color:var(--muted)">ほか \' + (all.length - 400) + " 人。名前で絞り込んでください</div>"',
     '\'<div class="grp" style="color:var(--muted)">\' + (all.length - 400) + " more. Search by name to narrow the list</div>"'),
    ('genStatus("その人はもう参加者にいます。", "err")', 'genStatus("That person is already taking part.", "err")'),
    ('msg("その人はこの列にもういます。", "err")', 'msg("That person is already in this column.", "err")'),
    ('S.fastNpcs ? "読み込み中…" : "読み込み中…（数分かかることがあります）"', 'S.fastNpcs ? "Loading..." : "Loading... (this can take a few minutes)"'),
    ('msg("名前は半角英数字と _ - だけで付けてください。", "err")', 'msg("Use only letters, digits, _ and - in the name.", "err")'),
    ('msg("同じ名前のイベントがもうあります。", "err")', 'msg("An event with that name already exists.", "err")'),
    ('msg("1 列目に参加キャラを 1 人以上選んでください。", "err")', 'msg("Choose at least one person in column 1.", "err")'),
    ('msg((c + 1) + " 列目に、話す人が選ばれていないセリフがあります。", "err")', 'msg("Column " + (c + 1) + " has a line with no speaker chosen.", "err")'),
    ('msg("もう一度「削除」を押すと「" + d.name + "」を削除します。", "err")', 'msg("Press Delete again to delete \\"" + d.name + "\\".", "err")'),
    ('$("ctext").textContent = "「" + d.name + "」の変更はまだ保存されていません。閉じると変更は失われます。";',
     '$("ctext").textContent = "The changes to \\"" + d.name + "\\" are not saved yet. Closing loses them.";'),
    # behaviour, not wording
    ('localeCompare(b.name, "ja")', 'localeCompare(b.name, "en")'),
    ('language: "Japanese"', 'language: "English"'),
]

# Japanese the English page keeps on purpose: words that mean the player in files written by the
# Japanese page (they still have to be recognised).
ALLOWED = ['return ["player", "{player}", "プレイヤー", "{プレイヤー}"].includes(spec);']

JAPANESE = re.compile(r'[　-ヿ一-鿿＀-￯]')


def main():
    source, target = sys.argv[1], sys.argv[2]
    text = open(source, encoding='utf-8').read()
    missing = [ja for ja, _ in PAIRS if ja not in text]
    if missing:
        sys.exit('not found in the Japanese page:\n  ' + '\n  '.join(missing))
    for ja, en in PAIRS:
        text = text.replace(ja, en)
    left = []
    for number, line in enumerate(text.split('\n'), 1):
        if JAPANESE.search(line) and not any(a in line for a in ALLOWED):
            left.append(f'{number}: {line.strip()}')
    if left:
        sys.exit('Japanese left in the English page:\n  ' + '\n  '.join(left))
    # (An apostrophe in a text inside a single-quoted script string breaks the page: the build
    # checks the script with node --check.)
    with open(target, 'w', encoding='utf-8', newline='\n') as out:
        out.write(text)
    print(f'{target}: {len(PAIRS)} replacements, no Japanese left')


if __name__ == '__main__':
    main()
