#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DAY_NAME "Shotgun Day"
#define DAY_WEAPON "weapon_nova"
#define DAY_HEALTH 300

#define DAMAGE_MULTIPLIER 1.5

#define SUPERJUMP_COOLDOWN 10.0

//====================//

ConVar g_cvInfiniteAmmo;
ConVar g_cvFallDamageScale;

float g_fNextSuperJump[MAXPLAYERS + 1];

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
	g_cvInfiniteAmmo = FindConVar("sv_infinite_ammo");
	g_cvFallDamageScale = FindConVar("sv_falldamage_scale");
	
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
		g_fNextSuperJump[client] = 0.0;
		
		DisarmPlayer(client);
		GivePlayerItem(client, DAY_WEAPON);
		
		SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		g_cvInfiniteAmmo.SetInt(2);
		g_cvFallDamageScale.SetInt(0);
		
		HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
		
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
					g_fNextSuperJump[iCurrentClient] = 0.0;
					
					SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				}
			}
			
			g_cvInfiniteAmmo.SetInt(0);
			g_cvFallDamageScale.SetInt(1);
			
			UnhookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
			
			ToggleRunesState(true);
		}
		
		g_bIsDayActivated = false;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (g_bIsDayActivated && IsPlayerAlive(client) && buttons && (buttons & IN_USE) && g_fNextSuperJump[client] <= GetGameTime())
	{
		// Apply super jump cooldown
		g_fNextSuperJump[client] = GetGameTime() + SUPERJUMP_COOLDOWN;
		
		// Progress bar cooldown effect	
		CreateTimer(SUPERJUMP_COOLDOWN, Timer_ResetProgressBar, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(0.05, Timer_DisplayProgressBar, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		
		// Boost the client upwards
		float fClientAng[3], fUp[3];
		GetClientAbsAngles(client, fClientAng);
		
		GetAngleVectors(fClientAng, NULL_VECTOR, NULL_VECTOR, fUp);
		ScaleVector(fUp, 920.0);
		
		float fVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);
		AddVectors(fUp, fVelocity, fVelocity);
		
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVelocity);
	}
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	event.SetInt("dmg_health", event.GetInt("dmg_health") * FloatToInt(DAMAGE_MULTIPLIER));
	return Plugin_Changed;
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	damage *= DAMAGE_MULTIPLIER;
	return Plugin_Changed;
}

//================================[ Timers ]================================//

public Action Timer_ResetProgressBar(Handle hTimer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want
	if (client) {
		ResetProgressBar(client);
	}
}

public Action Timer_DisplayProgressBar(Handle hTimer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want
	if (client) {
		SetProgressBarFloat(client, SUPERJUMP_COOLDOWN);
	}
}

//================================[ Functions ]================================//

int FloatToInt(float floatValue)
{
	char szFloat[64];
	FloatToString(floatValue, szFloat, sizeof(szFloat));
	return StringToInt(szFloat);
}

void SetProgressBarFloat(int client, float fProgressTime)
{
	int iProgressTime = RoundToCeil(fProgressTime);
	float fGameTime = GetGameTime();
	
	SetEntDataFloat(client, g_flSimulationTime, fGameTime + fProgressTime, true);
	SetEntData(client, g_iProgressBarDuration, iProgressTime, 4, true);
	SetEntDataFloat(client, g_flProgressBarStartTime, fGameTime - (iProgressTime - fProgressTime), true);
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