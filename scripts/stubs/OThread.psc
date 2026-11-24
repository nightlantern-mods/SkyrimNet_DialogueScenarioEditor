Scriptname OThread
{compile-only stub of OStim Standalone; never deployed}

bool Function IsRunning(int ThreadID) Global Native

Function Stop(int ThreadID) Global Native

Actor[] Function GetActors(int ThreadID) Global Native

string Function GetFurnitureType(int ThreadID) Global Native

string Function GetScene(int ThreadID) Global Native

Function WarpTo(int ThreadID, string SceneID, bool UseFades = False) Global Native
