Scriptname OLibrary
{compile-only stub of OStim Standalone; never deployed}

string Function GetRandomScene(Actor[] Actors) Global Native
string Function GetRandomSceneWithAnySceneTagCSV(Actor[] Actors, string Tags) Global Native
string Function GetRandomSceneWithAllSceneTagsCSV(Actor[] Actors, string Tags) Global Native
string Function GetRandomSceneWithAnyActionCSV(Actor[] Actors, string Types) Global Native

string Function GetRandomFurnitureScene(Actor[] Actors, string FurnitureType) Global Native
string Function GetRandomFurnitureSceneWithAnySceneTagCSV(Actor[] Actors, string FurnitureType, string Tags) Global Native
string Function GetRandomFurnitureSceneWithAllSceneTagsCSV(Actor[] Actors, string FurnitureType, string Tags) Global Native
string Function GetRandomFurnitureSceneWithAnyActionCSV(Actor[] Actors, string FurnitureType, string Types) Global Native
