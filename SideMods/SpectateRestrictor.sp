#include <sourcemod>
#include <cstrike>
#include <spec_hooks>

#pragma semicolon 1
#pragma newdecls required

enum struct Player
{
	int index;
	
	bool is_admin;
	
	int team;
	//================================//
	void InitIndex(int client)
	{
		this.index = client;
	}
	
	void InitAdmin()
	{
		this.is_admin = (GetUserAdmin(this.index) != INVALID_ADMIN_ID);
	}
	
	void Close()
	{
		this.index = 0;
		this.is_admin = false;
		this.team = CS_TEAM_NONE;
	}
	
	void OnObserverTargetChange(int &target)
	{
		// Full observe access to admins.
		if (this.is_admin)
		{
			return;
		}
		
		// Don't override killer targets.
		if (!SpecHooks_GetObserverMode(this.index))
		{
			return;
		}
		
		ArrayList exclude_array = this.BuildExcludeArray();
		
		int override_target = FindNextObserverTarget(this.index, false, exclude_array);
		if (override_target != -1)
		{
			target = override_target;
		}
		
		delete exclude_array;
	}
	
	Action OnObserverModeChange(int &mode)
	{
		// Always allow to enter death camera observer mode.
		if (mode == OBS_MODE_DEATHCAM || mode == OBS_MODE_FREEZECAM || mode == OBS_MODE_FIXED)
		{
			return Plugin_Continue;
		}
		
		// Full observe access to admins.
		if (this.is_admin)
		{
			return Plugin_Continue;
		}
		
		if (GetAliveClientCount() <= 0)
		{
			return Plugin_Continue;
		}
		
		if (!(mode == OBS_MODE_IN_EYE || mode == OBS_MODE_CHASE))
		{
			mode = OBS_MODE_IN_EYE;
			return Plugin_Changed;
		}
		
		return Plugin_Continue;
	}
	
	ArrayList BuildExcludeArray()
	{
		ArrayList arr = new ArrayList();
		
		for (int current_client = 1, team; current_client <= MaxClients; current_client++)
		{
			team = GetClientTeamEx(current_client);
			
			if (team != CS_TEAM_NONE && team != this.team)
			{
				arr.Push(current_client);
			}
		}
		
		return arr;
	}
}

Player g_Players[MAXPLAYERS + 1];

bool g_Lateload;

public Plugin myinfo = 
{
	name = "[CS:GO] Spectate Restrictor", 
	author = "KoNLiG", 
	description = "Restricts non-admin players to observe only their teammates, while admins can spectate everyone.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// ConVars Configurate
	ConVar mp_forcecamera = FindConVar("mp_forcecamera");
	if (!mp_forcecamera)
	{
		SetFailState("Failed to find 'mp_forcecamera' convar");
	}
	
	mp_forcecamera.IntValue = 0;
	
	HookEvent("player_team", Event_PlayerTeam);
	
	if (g_Lateload)
	{
		Lateload();
	}
}


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_Lateload = late;
	return APLRes_Success;
}

public void OnClientPutInServer(int client)
{
	g_Players[client].InitIndex(client);
}

public void OnClientPostAdminCheck(int client)
{
	g_Players[client].InitAdmin();
}

public void OnClientDisconnect(int client)
{
	g_Players[client].Close();
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
	{
		g_Players[client].team = event.GetInt("team");
	}
}

public Action SpecHooks_OnObserverTargetChange(int client, int &target, int last_target)
{
	g_Players[client].OnObserverTargetChange(target);
	return Plugin_Continue;
}

public Action SpecHooks_OnObserverModeChange(int client, int &mode, int last_mode)
{
	return g_Players[client].OnObserverModeChange(mode);
}

void Lateload()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			g_Players[current_client].Close();
			g_Players[current_client].InitIndex(current_client);
			g_Players[current_client].InitAdmin();
			
			g_Players[current_client].team = GetClientTeam(current_client);
		}
	}
}

int GetClientTeamEx(int client)
{
	return g_Players[client].team;
}

// CBaseEntity * CBasePlayer::FindNextObserverTarget(bool bReverse)
int FindNextObserverTarget(int client, bool reverse, ArrayList exclude_list)
{
	int startIndex = GetNextObserverSearchStartPoint(client, reverse);
	
	if (startIndex > MaxClients)
		startIndex = 1;
	else if (startIndex < 1)
		startIndex = MaxClients;
	
	int currentIndex = startIndex;
	int iDir = reverse ? -1 : 1;
	
	do
	{
		if (IsClientInGame(currentIndex) && SpecHooks_IsValidObserverTarget(client, currentIndex) && exclude_list.FindValue(currentIndex) == -1)
		{
			return currentIndex; // found next valid player
		}
		
		currentIndex += iDir;
		
		// Loop through the clients
		if (currentIndex > MaxClients)
			currentIndex = 1;
		else if (currentIndex < 1)
			currentIndex = MaxClients;
		
	} while (currentIndex != startIndex);
	
	return -1;
}

// int CBasePlayer::GetNextObserverSearchStartPoint( bool bReverse )
int GetNextObserverSearchStartPoint(int client, bool reverse)
{
	int iDir = reverse ? -1 : 1;
	
	int startIndex;
	
	int target = SpecHooks_GetObserverTarget(client);
	if (target != -1)
	{
		// start using last followed player
		startIndex = target;
	}
	else
	{
		// start using own player index
		startIndex = client;
	}
	
	startIndex += iDir;
	if (startIndex > MaxClients)
		startIndex = 1;
	else if (startIndex < 1)
		startIndex = MaxClients;
	
	return startIndex;
}

int GetAliveClientCount()
{
	int count;
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client))
		{
			count++;
		}
	}
	
	return count;
} 