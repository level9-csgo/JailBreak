#include <sourcemod>
#include <sdkhooks>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

bool g_bLateLoad;

public Plugin myinfo = 
{
	name = "vPhysics fix on Linux", 
	author = "Lerrdy", 
	description = "Automatically disables vPhysics on prop_dynamics with no physics model.", 
	version = "1.3", 
	url = "https://ggeasy.pl"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	DHookAddEntityListener(ListenType_Created, DHook_OnEntityCreated);
	
	if (g_bLateLoad)
	{
		int entity = INVALID_ENT_REFERENCE;
		while ((entity = FindEntityByClassname(entity, "prop_dynamic*")) != INVALID_ENT_REFERENCE)
		{
			CheckModel(entity);
		}
	}
}

void DHook_OnEntityCreated(int entity, const char[] classname)
{
	if (StrContains(classname, "prop_dynamic", false) != -1)
	{
		SDKHook(entity, SDKHook_SpawnPost, OnEntitySpawn_Post);
	}
}

void OnEntitySpawn_Post(int entity)
{
	CheckModel(entity);
}

void CheckModel(int entity)
{
	int solid = GetEntProp(entity, Prop_Send, "m_nSolidType", 1);
	if (solid != 6)
	{
		return;
	}
	
	char sModelName[PLATFORM_MAX_PATH];
	GetEntPropString(entity, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
	
	ReplaceString(sModelName, sizeof(sModelName), ".mdl", ".phy", true);
	
	bool bDoesHavePhysics = FileExists(sModelName, true, NULL_STRING);
	if (!bDoesHavePhysics)
		SetEntProp(entity, Prop_Data, "m_nSolidType", 0);
} 