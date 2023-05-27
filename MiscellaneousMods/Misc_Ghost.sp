#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <shop_premium>
#include <JB_RunesSystem>
#include <JB_SettingsSystem>
#include <JB_SpecialDays>
#include <TransmitManager>

//==========[ Settings ]==========//

#define GHOST_MENU_BUTTON_INFO "become_a_ghost"

#define COLLISION_GROUP_DEBRIS_TRIGGER 2 // Default client collision group, non solid
#define COLLISION_GROUP_IN_VEHICLE 10 // Required ghost collision group, "for any entity inside a vehicle"

#define PLAYER_LIFE_ALIVE 0
#define PLAYER_LIFE_DEAD 2

//====================//

enum struct Player
{
	bool IsClientGhost;
	bool IsGhostDeployed;
	
	void Reset()
	{
		this.IsClientGhost = false;
		this.IsGhostDeployed = false;
	}
}

Player g_Players[MAXPLAYERS + 1];

int m_bAliveOffset, g_AutoGhostRespawnSettingId;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Ghost", 
	author = "KoNLiG", 
	description = "A side ghost misc for premium members only.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Initialize offsets.
	if ((m_bAliveOffset = FindSendPropInfo("CCSPlayerResource", "m_bAlive")) <= 0)
	{
		SetFailState("Unable to find offset for 'CCSPlayerResource::m_bAlive'");
	}
	
	// Premium Command
	RegConsoleCmd("sm_ghost", Command_Ghost, "Allows premium members to turn into a ghost when they're dead.");
	
	// Add Sound Hooks
	AddNormalSoundHook(Hook_OnNormalSound);
	
	// Event Hooks
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	
	AddCommandListener(Listener_Drop, "drop");
	
	// Loop through all the online clients, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
}

public void OnPluginEnd()
{
	// Loop through all the clients who are ghsots, and remove their ghost ability
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_Players[current_client].IsClientGhost)
		{
			ToggleGhostFeature(current_client, false, false);
		}
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SettingsSystem"))
	{
		JB_CreateSettingCategory("Gameplay Settings", "This category is associated with settings that belongs to your gameplay.");
		g_AutoGhostRespawnSettingId = JB_CreateSetting("setting_auto_ghost_respawn", "Once the client has died, he will automatically deploy his ghost ability. (Bool setting)", "Auto Ghost Respawn [Premiums]", "Gameplay Settings", Setting_Bool, 1, "1");
	}
}

public void Shop_OnPremiumMenuDispaly(int client, Menu menu)
{
	// Create and format the item display text
	char item_display[64];
	Format(item_display, sizeof(item_display), "Become A Ghost!%s", g_Players[client].IsClientGhost ? " (Already Deployed)" : IsPlayerAlive(client) ? " (Must Be Dead)" : "");
	
	// Add the item to the premium benefit menu
	menu.AddItem(GHOST_MENU_BUTTON_INFO, item_display, !g_Players[client].IsClientGhost && !IsPlayerAlive(client) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
}

public void Shop_OnPremiumMenuPress(int client, Menu menu, const char[] itemInfo, int item_position)
{
	if (StrEqual(itemInfo, GHOST_MENU_BUTTON_INFO))
	{
		Command_Ghost(client, 0);
	}
}

public Action JB_OnRunePickup(int client, int entity, Rune runeData, int &runeId, int &star, int &level, RunePickupBlockReasons blockReason)
{
	if (g_Players[client].IsClientGhost)
	{
		PrintCenterText(client, "You cannot pick up runes while you are ghost");
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client)
{
	// Reset the local client variables
	g_Players[client].Reset();
}

public void OnMapStart()
{
	// Hook the player manager entity think, required to fake players dead state.
	int cs_player_manager = GetPlayerResourceEntity();
	if (cs_player_manager == -1)
	{
		SetFailState("Unable to retrive 'cs_player_manager' entity index");
	}
	
	SDKHook(cs_player_manager, SDKHook_ThinkPost, Hook_OnThinkPost);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (g_Players[client].IsClientGhost)
	{
		if (buttons & IN_USE)
		{
			buttons &= ~IN_USE;
		}
	}
	
	return Plugin_Continue;
}

Action Listener_Drop(int client, const char[] command, int argc)
{
	if (!g_Players[client].IsClientGhost)
	{
		return Plugin_Continue;
	}
	
	SetEntityMoveType(client, GetEntityMoveType(client) == MOVETYPE_NOCLIP ? MOVETYPE_WALK : MOVETYPE_NOCLIP);
	
	return Plugin_Stop;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			if (g_Players[current_client].IsClientGhost)
			{
				ToggleGhostFeature(current_client, false, false);
			}
			
			g_Players[current_client].Reset();
		}
	}
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	// Make sure the spawned client is a ghost
	if (g_Players[client].IsClientGhost && g_Players[client].IsGhostDeployed)
	{
		ToggleGhostFeature(client, false, false, false);
	}
}

Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	
	// Make sure the victim is a ghost, and he suicided
	if (g_Players[client].IsClientGhost && client == GetClientOfUserId(event.GetInt("attacker")))
	{
		// Kill the ghost ragdoll
		int ragdoll_entity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (ragdoll_entity != -1)
		{
			AcceptEntityInput(ragdoll_entity, "Kill");
		}
		
		// Set the ghost status as false
		g_Players[client].IsClientGhost = false;
		
		// Set the broadcast as false
		event.BroadcastDisabled = true;
		
		return Plugin_Changed;
	}
	
	if (!Shop_IsClientPremium(client) || JB_IsSpecialDayRunning() || g_Players[client].IsGhostDeployed)
	{
		return Plugin_Continue;
	}
	
	// If the client auto ghost respawn setting is enabled, spawn him again as a ghost
	char setting_value[2];
	JB_GetClientSetting(client, g_AutoGhostRespawnSettingId, setting_value, sizeof(setting_value));
	
	if (setting_value[0] == '1')
	{
		CreateTimer(0.1, Timer_DeployGhost, userid, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return Plugin_Continue;
}

Action Hook_OnNormalSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	return 1 <= entity <= MaxClients && g_Players[entity].IsClientGhost && !StrEqual(soundEntry, sample) ? Plugin_Handled : Plugin_Continue;
}

void Hook_OnThinkPost(int entity)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && g_Players[current_client].IsClientGhost)
		{
			SetEntData(entity, m_bAliveOffset + (current_client * 4), false, true);
		}
	}
}

//================================[ SDK Hooks ]================================//

Action Hook_OnWeaponCanUse(int client, int weapon)
{
	// Prevent items pick up
	return Plugin_Handled;
}

//================================[ Commands ]================================//

Action Command_Ghost(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Deny the command access to non-premium clients
	if (!Shop_IsClientPremium(client))
	{
		PrintToChat(client, "%s \x03Ghost\x01 is available for \x04premium members\x01 only!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (IsPlayerAlive(client) && !g_Players[client].IsClientGhost)
	{
		PrintToChat(client, "%s \x03Ghost\x01 feature available for \x07dead players\x01 only!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (JB_IsSpecialDayRunning())
	{
		PrintToChat(client, "%s \x03Ghost\x01 feature is unavailable while \x04Special Day\x01 is running!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (g_Players[client].IsGhostDeployed && !g_Players[client].IsClientGhost)
	{
		PrintToChat(client, "%s \x03Ghost\x01 feature can be used once per round!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Toggle the ghost feature
	ToggleGhostFeature(client, !g_Players[client].IsClientGhost);
	
	// Notify client
	if (g_Players[client].IsClientGhost)
	{
		PrintToChat(client, "%s You've became a \x03ghost\x01! Type \x04/ghost\x01 to turn back to dead man!", PREFIX);
	}
	else
	{
		PrintToChat(client, "%s You've turned back to \x02dead man\x01, there is no going back!", PREFIX);
	}
	
	return Plugin_Handled;
}

//================================[ API ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_IsClientGhost", Native_IsClientGhost);
	
	RegPluginLibrary("Misc_Ghost");
	return APLRes_Success;
}

int Native_IsClientGhost(Handle plugin, int numParams)
{
	// Param 1: 'client'
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	return g_Players[client].IsClientGhost;
}

//================================[ Timers ]================================//

Action Timer_DisableGhostEffect(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client)
	{
		SetEntProp(client, Prop_Send, "m_bIsPlayerGhost", false);
	}
	
	return Plugin_Continue;
}

Action Timer_DeployGhost(Handle timer, int userid)
{
	// Initialize the client index, and make sure it's valid
	int client = GetClientOfUserId(userid);
	
	if (!client || IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}
	
	// Deploy the client's ghost ability!
	Command_Ghost(client, 0);
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void ToggleGhostFeature(int client, bool toggle_mode, bool apply_effect = true, bool kill = true)
{
	if (g_Players[client].IsClientGhost == toggle_mode || GetClientTeam(client) <= CS_TEAM_SPECTATOR)
	{
		return;
	}
	
	if (toggle_mode)
	{
		CS_RespawnPlayer(client);
		DisarmPlayer(client);
		
		SetEntProp(client, Prop_Data, "m_ArmorValue", 0);
		SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);
		
		g_Players[client].IsGhostDeployed = true;
		
		// Perform sdk hook on the client
		SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
		
		// Set client god mode on
		SetEntProp(client, Prop_Data, "m_takedamage", 0, 1);
		
		PrintCenterText(client, "<font color='#1CC752' class='fontSize-xl'>Press G to noclip</font>");
	}
	else
	{
		SDKUnhook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
		
		// Set client god mode off
		SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
		
		if (kill)
		{
			SetEntProp(client, Prop_Send, "m_lifeState", PLAYER_LIFE_ALIVE);
			ForcePlayerSuicide(client);
		}
	}
	
	g_Players[client].IsClientGhost = toggle_mode;
	
	SetEntityCollisionGroup(client, toggle_mode ? COLLISION_GROUP_IN_VEHICLE : COLLISION_GROUP_DEBRIS_TRIGGER);
	EntityCollisionRulesChanged(client);
	
	if (apply_effect)
	{
		SetEntProp(client, Prop_Send, "m_lifeState", PLAYER_LIFE_DEAD);
		ApplyGhostEffect(client);
	}
	
	UpdateClientTransmitState(client);
}

void ApplyGhostEffect(int client)
{
	SetEntProp(client, Prop_Send, "m_bIsPlayerGhost", GetEntProp(client, Prop_Send, "m_bIsPlayerGhost") ^ 1);
	
	CreateTimer(0.5, Timer_DisableGhostEffect, GetClientUserId(client));
}

void UpdateClientTransmitState(int client)
{
	int client_team = GetClientTeam(client);
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (!IsClientInGame(current_client) || IsFakeClient(current_client) || client == current_client)
		{
			continue;
		}
		
		TransmitManager_SetEntityState(client, current_client, !g_Players[client].IsClientGhost);
		TransmitManager_SetEntityState(current_client, client, client_team == GetClientTeam(current_client) || !g_Players[client].IsClientGhost);
	}
}

//================================================================//
