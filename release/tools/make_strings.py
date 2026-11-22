# Writes the MCM texts of one language under all ten game-language file names (Skyrim reads only
# the file of its own language; without one the MCM shows raw $keys). UTF-16 LE with BOM, one
# "$KEY<TAB>text" per line.
#
# usage: python -I make_strings.py <en|ja> <Interface\Translations folder>
import os
import sys

NAME = 'SkyrimNet_DialogueScenarioEditor'
GAME_LANGUAGES = ['CHINESE', 'CZECH', 'ENGLISH', 'FRENCH', 'GERMAN', 'ITALIAN', 'JAPANESE', 'POLISH', 'RUSSIAN', 'SPANISH']

TEXTS = {
    'en': {
        '$DSE_ModName': 'SkyrimNet Dialogue Scenario Editor',
        '$DSE_HeaderPage': 'Settings page',
        '$DSE_PageKey': 'Key that opens the settings page',
        '$DSE_PageKeyHelp': 'Opens the page where you make and change scenarios. No key is set at first: pick one that no other mod uses.',
        '$DSE_HeaderScenario': 'Scenarios',
        '$DSE_TriggerKey': 'Key that starts a hotkey scenario',
        '$DSE_TriggerKeyHelp': 'Starts a scenario whose start is set to Hotkey on the settings page, if its conditions are met where you are. No key is set at first: pick one that no other mod uses.',
    },
    'ja': {
        '$DSE_ModName': 'SkyrimNet Dialogue Scenario Editor',
        '$DSE_HeaderPage': '設定画面',
        '$DSE_PageKey': '設定画面を開くキー',
        '$DSE_PageKeyHelp': 'シナリオを作る・直す画面を開くキーです。最初は割り当てていません。ほかの MOD と重ならないキーを選んでください。',
        '$DSE_HeaderScenario': 'シナリオ',
        '$DSE_TriggerKey': 'ホットキーのシナリオを始めるキー',
        '$DSE_TriggerKeyHelp': '設定画面で発火方法を「ホットキー」にしたシナリオを、今いる場所で条件がそろっていれば始めます。最初は割り当てていません。ほかの MOD と重ならないキーを選んでください。',
    },
}


def main():
    language, folder = sys.argv[1], sys.argv[2]
    texts = TEXTS[language]
    os.makedirs(folder, exist_ok=True)
    body = ''.join(f'{key}\t{text}\r\n' for key, text in texts.items())
    for game in GAME_LANGUAGES:
        with open(os.path.join(folder, f'{NAME}_{game}.txt'), 'wb') as out:
            out.write(b'\xff\xfe' + body.encode('utf-16-le'))
    print(f'{folder}: {len(texts)} texts in {language} x {len(GAME_LANGUAGES)} files')


if __name__ == '__main__':
    main()
