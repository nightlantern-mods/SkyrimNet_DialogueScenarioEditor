Scriptname SkyrimNet_DialogueScenarioEditorPlayer extends ReferenceAlias
{Runs the timer that checks the event setups, and sets up the settings page hotkey on each load.
An event runs inside the check, so the timer only starts again once that event has finished.}

Event OnInit()
	SetupAll()
	RegisterForSingleUpdate(5.0)
EndEvent

Event OnPlayerLoadGame()
	SetupAll()
	UnregisterForUpdate()
	RegisterForSingleUpdate(5.0)
EndEvent

Function SetupAll()
	(GetOwningQuest() as SkyrimNet_DialogueScenarioEditorMain).Setup()
	(GetOwningQuest() as SkyrimNet_DialogueScenarioEditorUI).Setup()
EndFunction

Event OnUpdate()
	RegisterForSingleUpdate((GetOwningQuest() as SkyrimNet_DialogueScenarioEditorMain).Check())
EndEvent
