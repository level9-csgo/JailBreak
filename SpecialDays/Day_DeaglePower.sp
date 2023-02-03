#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define DAY_NAME "Deagle Power Day"
#define DAY_WEAPON "weapon_deagle"
#define DAY_HEALTH 350

#define BASE_KNOCKBACK 65.0

//====================//

ConVar g_cvInfiniteAmmo;
ConVar g_cvFallDamageScale;

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
	g_cvInfiniteAmmo = FindConVar("sv_infinite_ammo");
	g_cvFallDamageScale = FindConVar("sv_falldamage_scale");
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
		
		SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	if (g_iDayId == specialDayId)
	{
		g_cvInfiniteAmmo.SetInt(2);
		g_cvFallDamageScale.SetInt(0);
		
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
			
			g_cvInfiniteAmmo.SetInt(0);
			g_cvFallDamageScale.SetInt(1);
			
			ToggleRunesState(true);
		}
		
		g_bIsDayActivated = false;
	}
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int HitGroup)
{
	if (1 <= attacker <= MaxClients)
	{
		DamageOnClientKnockBack(victim, attacker, damage, !!(damagetype & CS_DMG_HEADSHOT));
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

void DamageOnClientKnockBack(int victimIndex, int attackerIndex, float damageAmount, bool headshot)
{
	// Initialize vectors
	float fVictimPos[3];
	float fEyeAngle[3];
	float fAttackerPos[3];
	float fVelocity[3];
	
	// Get victim's position
	GetClientAbsOrigin(victimIndex, fVictimPos);
	
	// Get attacker's position
	GetClientEyeAngles(attackerIndex, fEyeAngle);
	GetClientEyePosition(attackerIndex, fAttackerPos);
	
	// Get vector from the given starting and ending points
	MakeVectorFromPoints(fAttackerPos, fVictimPos, fVelocity);
	
	// Normalize the vector (equal magnitude at varying distances)
	NormalizeVector(fVelocity, fVelocity);
	
	// Apply the magnitude by scaling the vector
	ScaleVector(fVelocity, BASE_KNOCKBACK * ((damageAmount <= 0.01 ? 115.0 : damageAmount) / (headshot ? 4.5 : 2.2)));
	
	// Push the player
	TeleportEntity(victimIndex, NULL_VECTOR, NULL_VECTOR, fVelocity);
}

public bool Filter_OnlyPlayers(int entity, int mask)
{
	return (1 <= entity <= MaxClients);
}

void ToggleRunesState(bool state)
{
	for (int current_rune = 0; current_rune < JB_GetRunesAmount(); current_rune++)
	{
		JB_ToggleRune(current_rune, state);
	}
}

//================================================================//