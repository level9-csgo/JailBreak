#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_GangsUpgrades>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DAY_NAME "Zeus Day"
#define DAY_WEAPON "weapon_taser"
#define DAY_HEALTH 50

#define REFILL_TIME 3.0

//====================//

Handle g_RefillTimer[MAXPLAYERS + 1] =  { INVALID_HANDLE, ... };

bool g_bIsDayActivated;

int g_iDayId = -1;

int g_flSimulationTime;
int g_flProgressBarStartTime;
int g_iProgressBarDuration;
int g_iBlockingUseActionInProgress;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...DAY_NAME, 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_flSimulationTime = FindSendPropInfo("CBaseEntity", "m_flSimulationTime");
	g_flProgressBarStartTime = FindSendPropInfo("CCSPlayer", "m_flProgressBarStartTime");
	g_iProgressBarDuration = FindSendPropInfo("CCSPlayer", "m_iProgressBarDuration");
	g_iBlockingUseActionInProgress = FindSendPropInfo("CCSPlayer", "m_iBlockingUseActionInProgress");
}

public void OnPluginEnd()
{
	if (g_bIsDayActivated) {
		JB_StopSpecialDay();
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SpecialDays"))
	{
		g_iDayId = JB_CreateSpecialDay(DAY_NAME, DAY_HEALTH, false, false, false);
	}
}

public void JB_OnClientSetupSpecialDay(int client, int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		DisarmPlayer(client);
		GivePlayerItem(client, DAY_WEAPON);
		
		SetEntProp(client, Prop_Data, "m_iMaxHealth", DAY_HEALTH);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
		
		int iUpgradeIndex = JB_FindGangUpgrade("healthpoints");
		if (iUpgradeIndex != -1) {
			JB_ToggleGangUpgrade(iUpgradeIndex, false);
		}
		
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
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			{
				if (IsClientInGame(iCurrentClient))
				{
					ResetProgressBar(iCurrentClient);
					
					if (g_RefillTimer[iCurrentClient] != INVALID_HANDLE)
					{
						KillTimer(g_RefillTimer[iCurrentClient]);
						g_RefillTimer[iCurrentClient] = INVALID_HANDLE;
					}
					
					SetEntProp(iCurrentClient, Prop_Data, "m_iMaxHealth", 100);
				}
			}
			
			UnhookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
			
			int iUpgradeIndex = JB_FindGangUpgrade("healthpoints");
			if (iUpgradeIndex != -1) {
				JB_ToggleGangUpgrade(iUpgradeIndex, true);
			}
			
			ToggleRunesState(true);
		}
		
		g_bIsDayActivated = false;
	}
}

public void OnClientDisconnect(int client)
{
	// FIX: Set the timer handle back to invalid to avoid connection error
	if (g_RefillTimer[client] != INVALID_HANDLE)
	{
		KillTimer(g_RefillTimer[client]);
		g_RefillTimer[client] = INVALID_HANDLE;
	}
}

public Action Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	int iPrimary = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
	
	// Make sure the primary weapon is exists and valid
	if (iPrimary != -1 && IsValidEntity(iPrimary))
	{
		// Set clip2 bullets to 1, prevents the taser from dropping
		SetEntProp(iPrimary, Prop_Data, "m_iClip2", 1);
		
		// If the client has successfully shot, create the refill timer
		if (GetEntProp(iPrimary, Prop_Data, "m_iClip1") == 1)
		{
			g_RefillTimer[client] = CreateTimer(REFILL_TIME, Timer_RefillTaser, GetClientSerial(client));
			SetProgressBarFloat(client, REFILL_TIME);
		}
	}
}

//================================[ Timers ]================================//

public Action Timer_RefillTaser(Handle hTimer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want
	if (client)
	{
		int iPrimary = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
		
		if (iPrimary != -1 && IsValidEntity(iPrimary)) {
			SetEntProp(iPrimary, Prop_Data, "m_iClip2", 0);
			SetEntProp(iPrimary, Prop_Data, "m_iClip1", 1);
		}
		
		ResetProgressBar(client);
	}
	
	// Set the timer handle as invalid, to prevent timer errors
	g_RefillTimer[client] = INVALID_HANDLE;
}

//================================[ Functions ]================================//

void SetProgressBarFloat(int client, float progress_time)
{
	int iProgressTime = RoundToCeil(progress_time);
	float fGameTime = GetGameTime();
	
	SetEntDataFloat(client, g_flSimulationTime, fGameTime + progress_time, true);
	SetEntData(client, g_iProgressBarDuration, iProgressTime, 4, true);
	SetEntDataFloat(client, g_flProgressBarStartTime, fGameTime - (iProgressTime - progress_time), true);
	SetEntData(client, g_iBlockingUseActionInProgress, 0, 4, true);
}

void ResetProgressBar(int client)
{
	SetEntDataFloat(client, g_flProgressBarStartTime, 0.0, true);
	SetEntData(client, g_iProgressBarDuration, 0, 1, true);
}

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

//================================================================//