#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_AUTHOR "@f0rce & KoNLiG"
#define PLUGIN_VERSION "1.0"

ConVar g_ForceCamera;

public Plugin myinfo = 
{
	name = "[CS:GO] Spectate Manager", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiGrL/ || KoNLiG#2325"
};

public void OnPluginStart()
{
	// ConVars Configurate
	g_ForceCamera = FindConVar("mp_forcecamera");
	
	if (g_ForceCamera == null)
	{
		SetFailState("Failed to find 'mp_forcecamera'");
	}
	
	g_ForceCamera.IntValue = 0;
	
	// Add all the required command listeners
	AddCommandListener(Listener_SpecPrev, "spec_prev");
	AddCommandListener(Listener_SpecNext, "spec_next");
	AddCommandListener(Listener_SpecPlayer, "spec_player");
	AddCommandListener(Listener_SpecMode, "spec_mode");
	
	// Event Hooks
	HookEvent("player_death", Event_PlayerDeath);
}

//================================[ Events ]================================//

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim_index = GetClientOfUserId(event.GetInt("userid"));
	
	if (GetUserAdmin(victim_index) != INVALID_ADMIN_ID)
	{
		return;
	}
	
	int attacker_index = GetClientOfUserId(event.GetInt("attacker"));
	int target_index = FindNextPlayer(attacker_index - 1, false, GetClientTeam(victim_index));
	
	if (target_index == -1)
	{
		return;
	}
	
	ChangeObserverTarget(victim_index, target_index);
}

//================================[ Command Listeners ]================================//

public Action Listener_SpecPrev(int client, const char[] command, int argc)
{
	if (GetUserAdmin(client) != INVALID_ADMIN_ID)
	{
		return Plugin_Continue;
	}
	
	if (IsFakeClient(client) || IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}
	
	int target_index = FindNextPlayer(GetObservingTarget(client), true, GetClientTeam(client));
	
	if (target_index == -1)
	{
		return Plugin_Continue;
	}
	
	ChangeObserverTarget(client, target_index);
	return Plugin_Stop;
}

public Action Listener_SpecNext(int client, const char[] command, int argc)
{
	if (GetUserAdmin(client) != INVALID_ADMIN_ID)
	{
		return Plugin_Continue;
	}
	
	if (!IsClientInGame(client) || IsFakeClient(client) || IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}
	
	int target_index = FindNextPlayer(GetObservingTarget(client), false, GetClientTeam(client));
	
	if (target_index == -1)
	{
		return Plugin_Continue;
	}
	
	ChangeObserverTarget(client, target_index);
	return Plugin_Stop;
}

public Action Listener_SpecPlayer(int client, const char[] command, int argc)
{
	if (GetUserAdmin(client) != INVALID_ADMIN_ID)
	{
		return Plugin_Continue;
	}
	
	if (IsFakeClient(client) || IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}
	
	char arg[4];
	GetCmdArg(1, arg, sizeof(arg));
	int temp_target = StringToInt(arg);
	
	if (!(1 <= temp_target <= MaxClients) || !IsClientInGame(temp_target))
	{
		temp_target = GetObservingTarget(client) + 1;
	}
	
	int target_index = FindNextPlayer(temp_target - 1, false, GetClientTeam(client));
	
	if (target_index == -1)
	{
		return Plugin_Continue;
	}
	
	ChangeObserverTarget(client, target_index);
	return Plugin_Stop;
}

public Action Listener_SpecMode(int client, const char[] command, int argc)
{
	if (GetUserAdmin(client) != INVALID_ADMIN_ID)
	{
		return Plugin_Continue;
	}
	
	if (IsFakeClient(client) || IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}
	
	int iTarget = -1;
	int pMode;
	
	if (IsClientObserver(client) && (pMode = GetEntProp(client, Prop_Send, "m_iObserverMode", 4, 0)) != 0 && (iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget")) != -1 && 0 < iTarget <= MaxClients && IsClientInGame(iTarget) && IsPlayerAlive(iTarget))
	{
		switch (pMode)
		{
			case 4:
			{
				SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
			}
			default:
			{
				SetEntProp(client, Prop_Send, "m_iObserverMode", 4);
			}
		}
		
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

//================================[ Functions ]================================//

int FindNextPlayer(int iStart, bool bReverse, int iTeam)
{
	if (!(1 <= iStart <= MaxClients))
	{
		iStart = 1;
	}
	
	if (iTeam == 1)
	{
		iTeam = 2;
	}
	
	int iCurrent = iStart;
	int iDir;
	
	if (bReverse)
	{
		iDir = -1;
	}
	else
	{
		iDir = 1;
	}
	
	do {
		iCurrent = iDir + iCurrent;
		if (iCurrent > MaxClients)
		{
			iCurrent = 1;
		}
		if (iCurrent < 1)
		{
			iCurrent = MaxClients;
		}
		
		if (IsClientInGame(iCurrent) && !IsClientObserver(iCurrent) && (iTeam != -1 && iTeam == GetClientTeam(iCurrent)) && IsPlayerAlive(iCurrent))
		{
			return iCurrent;
		}
	} while (iStart != iCurrent);
	
	return -1;
}

void ChangeObserverTarget(int client, int target)
{
	if (!(0 < target <= MaxClients))
	{
		return;
	}
	
	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);
	
	if (IsInFreeLook(client))
	{
		float origin[3];
		GetEntPropVector(target, Prop_Send, "m_vecOrigin", origin);
		SetEntPropVector(client, Prop_Send, "m_vecOrigin", origin);
	}
}

int GetObservingTarget(int client)
{
	return GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
}

bool IsInFreeLook(int client)
{
	return GetEntProp(client, Prop_Send, "m_iObserverMode") == 6;
}

//================================================================//