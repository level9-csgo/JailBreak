#include <sourcemod>
#include <cstrike>
#include <spec_hooks>

#pragma semicolon 1
#pragma newdecls required

enum struct Player
{
	bool is_admin;
	
	int team;
	//================================//
	void Init(int client)
	{
		this.is_admin = GetUserAdmin(client) != INVALID_ADMIN_ID;
	}
	
	void Close()
	{
		this.is_admin = false;
		this.team = CS_TEAM_NONE;
	}
	
	Action IsValidObserverTarget(Player target)
	{
		// Full observe access to admins.
		if (this.is_admin)
		{
			return Plugin_Continue;
		}
		
		return this.team == target.team ? Plugin_Handled : Plugin_Continue;
	}
	
	Action OnObserverModeChange(int &mode)
	{
		// Full observe access to admins.
		if (this.is_admin)
		{
			return Plugin_Continue;
		}
		
		if (mode == OBS_MODE_IN_EYE || mode == OBS_MODE_CHASE)
		{
			return Plugin_Continue;
		}
		else
		{
			mode = OBS_MODE_IN_EYE;
			return Plugin_Changed;
		}
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

public void OnClientPostAdminCheck(int client)
{
	g_Players[client].Init(client);
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
	{
		g_Players[client].team = event.GetInt("team");
	}
}

public Action SpecHooks_OnValidObserverTarget(int client, int target)
{
	return g_Players[client].IsValidObserverTarget(g_Players[target]);
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
			OnClientPostAdminCheck(current_client);
			
			g_Players[current_client].team = GetClientTeam(current_client);
		}
	}
} 