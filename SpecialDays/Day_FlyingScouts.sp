#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define DAY_NAME "Flying Scouts Day"
#define DAY_WEAPON "weapon_ssg08"
#define DAY_GRAVITY 220
#define DAY_HEALTH 350

ConVar g_cvWeaponAccuracyNospread;
ConVar g_cvGravity;

bool g_bIsDayActivated;

int g_iDayId = -1;

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
	g_cvWeaponAccuracyNospread = FindConVar("weapon_accuracy_nospread");
	g_cvGravity = FindConVar("sv_gravity");
}

public void OnPluginEnd()
{
	if (g_bIsDayActivated)
	{
		JB_StopSpecialDay();
	}
}

/* Events */

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
		GivePlayerItem(client, "weapon_knife");
		GivePlayerItem(client, DAY_WEAPON);
		
		SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		g_cvWeaponAccuracyNospread.BoolValue = true;
		
		g_cvGravity.IntValue = DAY_GRAVITY;
		
		ToggleParachute(false);
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
					SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				}
			}
			
			g_cvGravity.IntValue = 800;
			
			g_cvWeaponAccuracyNospread.BoolValue = false;
			ToggleParachute(true);
			ToggleRunesState(true);
		}
		
		g_bIsDayActivated = false;
	}
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if (!(1 <= attacker <= MaxClients))
	{
		return Plugin_Continue;
	}
	
	char szWeapon[64];
	GetClientWeapon(attacker, szWeapon, sizeof(szWeapon));
	
	if (StrContains(szWeapon, "knife") != -1 || StrContains(szWeapon, "bayonet") != -1)
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

/*  */