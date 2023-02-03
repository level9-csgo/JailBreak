#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_SpecialDays>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define RUNE_NAME "HE-Grenade Rune"

enum
{
	Benefit_Name, 
	Benefit_Tag
}

char g_szBenefits[2][2][64] = 
{
	{ "HE-Grenade", "weapon_hegrenade" }, 
	{ "Tactical awareness grenade", "weapon_tagrenade" }
};

float g_fBonusChances[][] = 
{
	{ 0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0 },  // Star 1
	{ 1.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0 },  // Star 2
	{ 2.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 18.0, 20.0 },  // Star 3
	{ 4.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 22.0, 24.0 },  // Star 4
	{ 6.0, 8.0, 9.0, 10.0, 12.0, 14.0, 15.0, 17.0, 19.0, 22.0, 23.0, 24.0, 25.0, 26.0, 28.0 },  // Star 5
	{ 8.0, 10.0, 11.0, 12.0, 14.0, 16.0, 17.0, 19.0, 21.0, 23.0, 25.0, 27.0, 29.0, 30.0, 32.0 } // Star 6
};

bool g_bIsRuneEnabled = true;

int g_iRuneId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...RUNE_NAME, 
	author = PLUGIN_AUTHOR, 
	description = RUNE_NAME..." perk module for the runes system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_RunesSystem"))
	{
		ArrayList ar = new ArrayList(RuneLevel_Max - 1);
		
		for (int current_benefit = 0; current_benefit < sizeof(g_fBonusChances); current_benefit++)
		{
			ar.PushArray(g_fBonusChances[current_benefit], sizeof(g_fBonusChances[]));
		}
		
		g_iRuneId = JB_CreateRune("hegrenaderune", RUNE_NAME, "A chance to get a HE Grenade as a prisoner,\n   and Tactical awareness grenade as a guard every round.", "☣", ar, "{float}% To Achieve");
	}
}

public void JB_OnSpecialDayStart(int specialDayId)
{
	g_bIsRuneEnabled = false;
}

public void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winner, bool aborted, bool countdown)
{
	g_bIsRuneEnabled = true;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bIsRuneEnabled)
	{
		return;
	}
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	int iEquippedRune = JB_GetClientEquippedRune(client, g_iRuneId);
	
	if (iEquippedRune == -1)
	{
		return;
	}
	
	ClientRune ClientRuneData;
	
	JB_GetClientRuneData(client, iEquippedRune, ClientRuneData);
	
	if (GetRandomFloat(0.0, 100.0) <= g_fBonusChances[ClientRuneData.RuneStar - 1][ClientRuneData.RuneLevel - 1])
	{
		RequestFrame(RF_GiveClientBenefit, GetClientUserId(client));
	}
}

void RF_GiveClientBenefit(int userid)
{
	// Initialize the client index and make sure it's valid
	int client = GetClientOfUserId(userid);
	
	if (!client || !IsPlayerAlive(client))
	{
		return;
	}
	
	int iBenefit = JB_GetClientGuardRank(client) != Guard_NotGuard;
	
	GivePlayerItem(client, g_szBenefits[iBenefit][Benefit_Tag]);
	
	PrintToChat(client, "%s \x07Rune Benefit: \x06%s\x01 has been recieved!", PREFIX, g_szBenefits[iBenefit][Benefit_Name]);
}

public void JB_OnRuneToggle(int runeIndex, bool toggleMode)
{
	// Make sure the changed rune is the plugin's rune index
	if (runeIndex == g_iRuneId)
	{
		g_bIsRuneEnabled = toggleMode;
	}
}

//================================================================//
