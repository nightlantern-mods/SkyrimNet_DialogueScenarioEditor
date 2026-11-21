Scriptname OActorUtil
{compile-only stub of OStim Standalone; never deployed}

Actor[] Function EmptyArray() Global Native
Actor[] Function CreateArray(int Size, Actor Filler = None) Global Native
Actor[] Function Sort(Actor[] Actors, Actor[] DominantActors, int PlayerIndex = -1) Global Native
Actor[] Function GetActorsInRangeV2(ObjectReference Center, float Range, bool IncludeCenter = false, bool IncludePlayer = true, bool OStimActorsOnly = false, Perk Condition = None) Global Native

