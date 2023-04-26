#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialMods>
#include <JB_CellsSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define MOD_NAME "Hide & Seek"
#define MOD_DESC "An old school hide and seek mod.\nThe guards have 45 seconds to hide, and the prisoners cant see/hear you at all!"

#define PRISONERS_FREEZE_TIME 60 // Time in seconds the prisoners will be freezed in every start of round
#define PRISONERS_SPAWN_PROTECTION_TIME 10 // Time in seconds for the prisoners spawn protection

#define PRISONERS_PRIMARY_WEAPON "weapon_ak47"
#define PRISONERS_SECONDARY_WEAPON "weapon_deagle"

//====================//

// UserMessageId for Fade
UserMsg g_FadeUserMsgId;

Handle g_PrisonersFreezeTimer = INVALID_HANDLE;

bool g_IsModActivated;

int g_SpecialModId = -1;
int g_CountTimer;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...MOD_NAME..." Mod", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Get the fade user message id
	g_FadeUserMsgId = GetUserMessageId("Fade");
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialMods"))
	{
		g_SpecialModId = JB_CreateSpecialMod(MOD_NAME, MOD_DESC);
	}
}

public void JB_OnSpecialModExecute(int client, int specialModId, bool bought)
{
	// Make sure there is mod index match
	if (specialModId == g_SpecialModId)
	{
		ToggleSpecialMod(true);
	}
}

public void JB_OnSpecialModEnd(int specialModId)
{
	if (specialModId == g_SpecialModId && g_IsModActivated)
	{
		ToggleSpecialMod(false);
	}
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
	JB_TogglePrisonersMute(false, false);
	
	DeleteTimer();
	
	g_CountTimer = PRISONERS_FREEZE_TIME;
	g_PrisonersFreezeTimer = CreateTimer(1.0, Timer_PrisonersFreeze, .flags = TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	
	PrintCenterTextAll("<font color='#0000B3'> Hide & Seek</font> will start in <font color='#00FF00'>%ds</font>", g_CountTimer);
}

public void Event_AliveStateChange(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.5, Timer_PerformModFeatures, GetClientSerial(GetClientOfUserId(event.GetInt("userid"))), TIMER_FLAG_NO_MAPCHANGE);
}

//================================[ Timers ]================================//

public Action Timer_PrisonersFreeze(Handle timer)
{
	if (g_CountTimer <= 1)
	{
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
			{
				// Toggle off the current prisoner effects
				TogglePrisonerEffects(current_client, false);
				
				// If the define is greater than 0, apply the spawn protection
				ToggleClientGod(current_client, true);
				
				// Loadout the prisoner
				DisarmPlayer(current_client);
				
				GivePlayerItem(current_client, PRISONERS_PRIMARY_WEAPON);
				GivePlayerItem(current_client, PRISONERS_SECONDARY_WEAPON);
				GivePlayerItem(current_client, "weapon_knife");
			}
		}
		
		JB_OpenCells();
		
		g_PrisonersFreezeTimer = CreateTimer(float(PRISONERS_SPAWN_PROTECTION_TIME), Timer_DisableSpawnProtection, .flags = TIMER_FLAG_NO_MAPCHANGE);
		
		PrintCenterTextAll("<font color='#0000B3'> Hide & Seek</font> has started!");
		
		return Plugin_Stop;
	}
	
	g_CountTimer--;
	
	PrintCenterTextAll("<font color='#0000B3'> Hide & Seek</font> will start in <font color='#00FF00'>%ds</font>", g_CountTimer);
	
	return Plugin_Continue;
}

public Action Timer_DisableSpawnProtection(Handle timer)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
		{
			ToggleClientGod(current_client, false);
		}
	}
	
	g_PrisonersFreezeTimer = INVALID_HANDLE;
}

public Action Timer_PerformModFeatures(Handle timer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is in-game and valid
	if (!client)
	{
		return;
	}
	
	// If the client is a prisoner, and the freeze timer is running / the freeze period is running, perform the effects on him
	if (IsPlayerAlive(client) && GetClientTeam(client) == CS_TEAM_T && (g_PrisonersFreezeTimer != INVALID_HANDLE || GameRules_GetProp("m_bFreezePeriod")))
	{
		TogglePrisonerEffects(client, true);
	}
	
	PerformVoiceEdit(client);
}

//================================[ Functions ]================================//

void ToggleSpecialMod(bool toggle_mode)
{
	if (!toggle_mode && !g_IsModActivated || toggle_mode && g_IsModActivated)
	{
		return;
	}
	
	if (toggle_mode)
	{
		HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_Post);
		HookEvent("player_spawn", Event_AliveStateChange, EventHookMode_Post);
		HookEvent("player_death", Event_AliveStateChange, EventHookMode_Post);
	}
	else
	{
		UnhookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_Post);
		UnhookEvent("player_spawn", Event_AliveStateChange, EventHookMode_Post);
		UnhookEvent("player_death", Event_AliveStateChange, EventHookMode_Post);
		
		for (int current_client = 1; current_client <= MaxClients; current_client++)
		{
			if (IsClientInGame(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
			{
				// Toggle off the current prisoner effects
				TogglePrisonerEffects(current_client, false);
			}
		}
		
		JB_AbortSpecialMod(false);
	}
	
	// Stop the timer
	DeleteTimer();
	
	// Change the special mod state global variable value
	g_IsModActivated = toggle_mode;
}

void PerformVoiceEdit(int client)
{
	int client_team_index = GetClientTeam(client);
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			SetListenOverride(current_client, client, client_team_index == GetClientTeam(current_client) ? Listen_Default : Listen_No);
			SetListenOverride(client, current_client, client_team_index == GetClientTeam(current_client) ? Listen_Default : Listen_No);
		}
	}
}

void TogglePrisonerEffects(int client, bool mode)
{
	// Perform blind effect on the client
	PerformBlind(client, (mode ? 255 : 0));
	
	// Perform god mode on the client
	ToggleClientGod(client, mode);
	
	// Perform freeze on the client
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", mode ? 0.0:1.0);
	
	int color[4]; color = (mode ?  { 0, 128, 255, 192 }  :  { 255, 255, 255, 255 } );
	SetEntityRenderColor(client, color[0], color[1], color[2], color[3]);
}

void PerformBlind(int client, int amount)
{
	int clients[2];
	clients[0] = client;
	
	int duration = 1536;
	int holdtime = 1536;
	
	int flags;
	
	if (amount == 0)
	{
		flags = (0x0001 | 0x0010);
	}
	else
	{
		flags = (0x0002 | 0x0008);
	}
	
	int color[4] =  { 0, 0, 0, 0 };
	color[3] = amount;
	
	Handle message = StartMessageEx(g_FadeUserMsgId, clients, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", duration);
		pb.SetInt("hold_time", holdtime);
		pb.SetInt("flags", flags);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWrite bf = UserMessageToBfWrite(message);
		bf.WriteShort(duration);
		bf.WriteShort(holdtime);
		bf.WriteShort(flags);
		bf.WriteByte(color[0]);
		bf.WriteByte(color[1]);
		bf.WriteByte(color[2]);
		bf.WriteByte(color[3]);
	}
	
	EndMessage();
}

void ToggleClientGod(int client, bool mode)
{
	SetEntProp(client, Prop_Data, "m_takedamage", mode ? 0 : 2, 1);
}

void DeleteTimer()
{
	if (g_PrisonersFreezeTimer != INVALID_HANDLE)
	{
		KillTimer(g_PrisonersFreezeTimer);
		g_PrisonersFreezeTimer = INVALID_HANDLE;
	}
}

//================================================================//