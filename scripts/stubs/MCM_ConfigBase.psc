Scriptname MCM_ConfigBase extends Quest
{compile-only stub of MCM Helper's MCM_ConfigBase; never deployed}

Int Function GetModSettingInt(String a_settingName) Native
Bool Function GetModSettingBool(String a_settingName) Native
Function SetModSettingInt(String a_settingName, Int a_value) Native
Function SetModSettingBool(String a_settingName, Bool a_value) Native
Function SetModSettingString(String a_settingName, String a_value) Native
Function RefreshMenu() Native
Function SetMenuOptions(String a_ID, String[] a_options, String[] a_shortNames = None) Native

Event OnConfigOpen()
EndEvent

Event OnConfigInit()
EndEvent

Event OnSettingChange(String a_ID)
EndEvent

Event OnInit()
EndEvent
