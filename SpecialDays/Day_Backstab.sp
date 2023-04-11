#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define DAY_NAME "Backstab Day"
#define DAY_WEAPON "weapon_knife"
#define DEFAULT_HEALTH 100

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
		DisarmPlayer(client);
		GivePlayerItem(client, DAY_WEAPON);
		SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		ToggleRunesState(false);
		
		g_bIsDayActivated = true;
	}
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winnerIndex, bool aborted, bool countdown)
{
	if (g_bIsDayActivated && g_iDayId == specialDayId)
	{
		// If there is a countdown, these things didn't hook
		if (!countdown)
		{
			for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
			{
				if (IsClientInGame(iCurrentClient)) {
					SDKUnhook(iCurrentClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
				}
			}
			
			ToggleRunesState(true);
		}
		
		g_bIsDayActivated = false;
	}
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	return IsStabBackstab(attacker, victim) ? Plugin_Continue : Plugin_Handled;
}

bool IsStabBackstab(int attacker, int victim)
{
	if (!(1 <= attacker <= MaxClients))
	{
		return false;
	}
	
	// Initialize buffers.
	float abs_angles[3], victim_forward[3], attacker_origin[3], victim_origin[3], vec_los[3];
	
	GetClientAbsAngles(victim, abs_angles);
	GetAngleVectors(abs_angles, victim_forward, NULL_VECTOR, NULL_VECTOR);
	
	GetClientAbsOrigin(attacker, attacker_origin);
	GetClientAbsOrigin(victim, victim_origin);
	
	SubtractVectors(victim_origin, attacker_origin, vec_los);
	NormalizeVector(vec_los, vec_los);
	
	// 2D Vectors representation.
	vec_los[2] = 0.0;
	victim_forward[2] = 0.0;
	
	return GetVectorDotProduct(victim_forward, vec_los) > 0.475;
}

//================================[ Functions ]================================//

void ToggleRunesState(bool state)
{
	int health_rune_index = JB_FindRune("healthrune");
	
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		if (health_rune_index != current_rune)
		{
			JB_ToggleRune(current_rune, state);
		}
	}
}

//================================================================//