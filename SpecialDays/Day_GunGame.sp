#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_GangsUpgrades>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG & Ravid"

//==========[ Settings ]==========//

#define DAY_NAME "Gun Game Day"
#define DEFAULT_HEALTH 100

#define MAX_WEAPONS_GG 20

//====================//

enum
{
	Weapon_Name = 0, 
	Weapon_Tag, 
	Weapon_Max
}

char g_szWeapons[MAX_WEAPONS_GG][Weapon_Max][] = 
{
	{ "Glock-18", "weapon_glock" }, 
	{ "P250", "weapon_p250" }, 
	{ "Desert Eagle", "weapon_deagle" }, 
	{ "USP-S", "weapon_usp_silencer" }, 
	{ "Nova", "weapon_nova" }, 
	{ "XM1014", "weapon_xm1014" }, 
	{ "Mag-7", "weapon_mag7" }, 
	{ "Sawed-Off", "weapon_sawedoff" }, 
	{ "UMP-45", "weapon_ump45" }, 
	{ "MP7", "weapon_mp7" }, 
	{ "PP-Bizon", "weapon_bizon" }, 
	{ "P-90", "weapon_p90" }, 
	{ "Galil AR", "weapon_galilar" }, 
	{ "Famas", "weapon_famas" }, 
	{ "M4A4", "weapon_m4a1" }, 
	{ "AK-47", "weapon_ak47" }, 
	{ "AWP", "weapon_awp" }, 
	{ "SSG 08", "weapon_ssg08" }, 
	{ "HE Grenade", "weapon_hegrenade" }, 
	{ "Golden Knife", "weapon_knifegg" }
};

bool g_bIsDayActivated;

int g_iCurrentWeapon[MAXPLAYERS + 1];
int g_iDayId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...DAY_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginEnd()
{
	if (g_bIsDayActivated)
	{
		JB_StopSpecialDay();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_iDayId = JB_CreateSpecialDay(DAY_NAME, DEFAULT_HEALTH, false, false, false);
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		g_iCurrentWeapon[client] = 0;
		
		SetEntityRenderColor(client);
		
		SetupPlayer(client);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		HookEvent("grenade_thrown", Event_GrenadeThrow, EventHookMode_Post);
		HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
		HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
		
		ServerCommand("mp_ignore_round_win_conditions 1");
		ServerCommand("mp_respawn_on_death_t 1");
		ServerCommand("mp_respawn_on_death_ct 1");
		ServerCommand("mp_death_drop_gun 0");
		
		int iUpgradeIndex = JB_FindGangUpgrade("healthpoints");
		if (iUpgradeIndex != -1) {
			JB_ToggleGangUpgrade(iUpgradeIndex, false);
		}
		
		iUpgradeIndex = JB_FindGangUpgrade("friendlyfire");
		if (iUpgradeIndex != -1) {
			JB_ToggleGangUpgrade(iUpgradeIndex, false);
		}
		
		ToggleBunnyhop(false);
		ToggleRunesState(false);
		
		g_bIsDayActivated = true;
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	if (g_bIsDayActivated && g_iDayId == specialDayId)
	{
		if (!countdown)
		{
			UnhookEvent("grenade_thrown", Event_GrenadeThrow, EventHookMode_Post);
			UnhookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
			UnhookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
			
			ServerCommand("mp_ignore_round_win_conditions 0");
			ServerCommand("mp_respawn_on_death_t 0");
			ServerCommand("mp_respawn_on_death_ct 0");
			ServerCommand("mp_death_drop_gun 1");
			
			int iUpgradeIndex = JB_FindGangUpgrade("healthpoints");
			if (iUpgradeIndex != -1) {
				JB_ToggleGangUpgrade(iUpgradeIndex, true);
			}
			
			iUpgradeIndex = JB_FindGangUpgrade("friendlyfire");
			if (iUpgradeIndex != -1) {
				JB_ToggleGangUpgrade(iUpgradeIndex, true);
			}
			
			ToggleBunnyhop(true);
			ToggleRunesState(true);
		}
		
		g_bIsDayActivated = false;
	}
}

public void OnClientPostAdminCheck(int client)
{
	g_iCurrentWeapon[client] = 0;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	char szWeapon[32];
	event.GetString("weapon", szWeapon, sizeof(szWeapon));
	
	event.BroadcastDisabled = true;
	
	int iVictimIndex = GetClientOfUserId(event.GetInt("userid"));
	int iAttackerIndex = GetClientOfUserId(event.GetInt("attacker"));
	
	if (!iAttackerIndex || iVictimIndex == iAttackerIndex)
	{
		return Plugin_Continue;
	}
	
	if ((StrContains(szWeapon, "knife") != -1 || StrContains(szWeapon, "bayonet") != -1) && g_iCurrentWeapon[iVictimIndex] > 0)
	{
		g_iCurrentWeapon[iVictimIndex]--;
	}
	
	if (StrContains(g_szWeapons[g_iCurrentWeapon[iAttackerIndex]][Weapon_Tag], szWeapon) == -1 && (StrContains(szWeapon, "knife") == -1 && StrContains(szWeapon, "bayonet") == -1))
	{
		return Plugin_Continue;
	}
	
	if (g_iCurrentWeapon[iAttackerIndex] == MAX_WEAPONS_GG - 1)
	{
		EndGame(iAttackerIndex);
		return Plugin_Continue;
	}
	
	SetLevelUp(iAttackerIndex);
	
	Event newEvent = CreateEvent("player_death");
	newEvent.SetInt("userid", GetClientUserId(iVictimIndex));
	newEvent.SetInt("attacker", GetClientUserId(iAttackerIndex));
	newEvent.SetString("weapon", szWeapon);
	newEvent.SetBool("headshot", event.GetBool("headshot"));
	newEvent.SetBool("noscope", event.GetBool("noscope"));
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && (iCurrentClient == iVictimIndex || iCurrentClient == iAttackerIndex) && !IsFakeClient(iCurrentClient))
		{
			newEvent.FireToClient(iCurrentClient);
		}
	}
	
	newEvent.Cancel();
	
	DisplayProgressInfoAll();
	
	return Plugin_Continue;
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	SetupPlayer(GetClientOfUserId(event.GetInt("userid")));
}

void Event_GrenadeThrow(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	DisarmPlayer(client);
	EquipPlayerWeapon(client, GivePlayerItem(client, g_szWeapons[g_iCurrentWeapon[client]][Weapon_Tag]));
}

//================================[ Functions ]================================//

void SetupPlayer(int client)
{
	DisarmPlayer(client);
	
	int iWeapon = g_iCurrentWeapon[client];
	
	int iWeaponIndex = GivePlayerItem(client, g_szWeapons[iWeapon][Weapon_Tag]);
	
	if (iWeaponIndex != -1) {
		EquipPlayerWeapon(client, iWeaponIndex);
	}
	
	if (StrContains(g_szWeapons[iWeapon][Weapon_Tag], "knife") == -1 && StrContains(g_szWeapons[iWeapon][Weapon_Tag], "bayonet") == -1 && !StrEqual(g_szWeapons[iWeapon][Weapon_Tag], "weapon_hegrenade"))
	{
		iWeaponIndex = GivePlayerItem(client, "weapon_knife");
		
		if (iWeaponIndex != -1) {
			EquipPlayerWeapon(client, iWeaponIndex);
		}
	}
}

void EndGame(int winner)
{
	ServerCommand("mp_respawn_on_death_t 0");
	ServerCommand("mp_respawn_on_death_ct 0");
	ServerCommand("mp_death_drop_gun 1");
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && iCurrentClient != winner)
		{
			ForcePlayerSuicide(iCurrentClient);
		}
	}
	
	RequestFrame(RF_EndSpecialDay);
}

void RF_EndSpecialDay()
{
	JB_StopSpecialDay(false);
}

int GetLeader()
{
	int iLeader;
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && (!iLeader || !IsClientInGame(iLeader) || g_iCurrentWeapon[iCurrentClient] > g_iCurrentWeapon[iLeader]))
		{
			iLeader = iCurrentClient;
		}
	}
	
	return iLeader;
}

void SetLevelUp(int client)
{
	g_iCurrentWeapon[client]++;
	
	if (g_iCurrentWeapon[client] == MAX_WEAPONS_GG - 1)
	{
		PrintCenterTextAll("<font color='#FF00FF'>%N has reached the Golden Knife!", client);
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				ClientCommand(iCurrentClient, "play weapons/knife/knife_deploy1.wav");
				ClientCommand(iCurrentClient, "play weapons/knife/knife_deploy1.wav");
				ClientCommand(iCurrentClient, "play weapons/knife/knife_deploy1.wav");
				ClientCommand(iCurrentClient, "play weapons/knife/knife_deploy1.wav");
			}
		}
	}
	
	RequestFrame(RF_SetupPlayer, GetClientSerial(client));
}

void RF_SetupPlayer(int serial)
{
	int client = GetClientFromSerial(serial);
	
	if (client) {
		SetupPlayer(client);
	}
}

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

void DisplayProgressInfo(int client, int leading_client)
{
	PrintCenterText(client, "<font color='#CC0000'> Gun Game:</font> \n<font color='#FFA500'>%N</font> is leading with %s | <font color='#8AC7DB'>%d/%d</font>\nCurrent Weapon: %s | %d/%d\nNext %s: %s", 
		leading_client, 
		g_szWeapons[g_iCurrentWeapon[leading_client]][Weapon_Name], 
		g_iCurrentWeapon[leading_client] + 1 == MAX_WEAPONS_GG ? MAX_WEAPONS_GG:g_iCurrentWeapon[leading_client] + 1, 
		MAX_WEAPONS_GG, 
		g_szWeapons[g_iCurrentWeapon[client]][Weapon_Name], 
		g_iCurrentWeapon[client] + 1, 
		MAX_WEAPONS_GG, 
		g_iCurrentWeapon[client] == MAX_WEAPONS_GG - 1 ? "Kill":"Weapon", 
		g_iCurrentWeapon[client] == MAX_WEAPONS_GG - 1 ? "Victory!":g_szWeapons[g_iCurrentWeapon[client] + 1][Weapon_Name]
		);
}

void DisplayProgressInfoAll()
{
	for (int current_client = 1, leading_client = GetLeader(); current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			DisplayProgressInfo(current_client, leading_client);
		}
	}
}

//================================================================//