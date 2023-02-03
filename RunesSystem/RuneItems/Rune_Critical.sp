#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <JailBreak>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define RUNE_CRIT_RATE_NAME "Critical Rate Rune"
#define RUNE_CRIT_DMG_NAME "Critical Damage Rune"

enum
{
	Rune_Crit_Rate, 
	Rune_Crit_Dmg, 
	Rune_Crit_Max
}

// UserMessageId for Fade
UserMsg g_FadeUserMsgId;

bool g_bIsRuneEnabled = true;

int g_iRuneId[Rune_Crit_Max] =  { -1, ... };

float g_CritRateStats[RuneStar_Max - 1][RuneLevel_Max - 1] = 
{
	{ 0.03, 0.05, 0.1, 0.2, 0.3, 0.35, 0.4, 0.6, 0.65, 0.7, 0.8, 0.9, 0.95, 1.0 },  // Star 1
	{ 0.05, 0.1, 0.2, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5 },  // Star 2
	{ 0.1, 0.2, 0.4, 0.6, 0.8, 0.9, 1.1, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0 },  // Star 3
	{ 0.2, 0.3, 0.5, 0.7, 0.9, 1.1, 1.3, 1.5, 1.7, 1.8, 2.0, 2.1, 2.3, 2.4, 2.5 },  // Star 4
	{ 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.5, 2.7, 2.9, 3.0 },  // Star 5
	{ 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 3.2, 3.5, 3.7, 3.9, 4.0 } // Star 6
};

int g_CritDmgStats[RuneStar_Max - 1][RuneLevel_Max - 1] = 
{
	{ 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 },  // Star 1
	{ 6, 8, 10, 12, 14, 16, 18, 20, 24, 26, 28, 30, 32, 34, 36 },  // Star 2
	{ 8, 10, 12, 14, 16, 18, 22, 26, 28, 32, 34, 38, 40, 44, 46 },  // Star 3
	{ 10, 12, 14, 16, 18, 22, 26, 30, 34, 38, 40, 44, 46, 50, 52 },  // Star 4
	{ 12, 14, 18, 22, 26, 30, 34, 38, 42, 46, 50, 54, 58, 62, 66 },  // Star 5
	{ 24, 26, 30, 34, 38, 42, 46, 50, 54, 58, 62, 64, 66, 68, 73 } // Star 6
};

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...RUNE_CRIT_RATE_NAME..." & "...RUNE_CRIT_DMG_NAME, 
	author = PLUGIN_AUTHOR, 
	description = RUNE_CRIT_RATE_NAME..." & "...RUNE_CRIT_DMG_NAME..." perks modules for the runes system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Get 'Fade' user message id.
	g_FadeUserMsgId = GetUserMessageId("Fade");
	
	// Loop through all online clients, for late load support
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			OnClientPostAdminCheck(iCurrentClient);
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_RunesSystem"))
	{
		ArrayList ar = new ArrayList(RuneLevel_Max - 1);
		
		for (int current_benefit = 0; current_benefit < sizeof(g_CritRateStats); current_benefit++)
		{
			ar.PushArray(g_CritRateStats[current_benefit], sizeof(g_CritRateStats[]));
		}
		
		g_iRuneId[Rune_Crit_Rate] = JB_CreateRune("critraterune", RUNE_CRIT_RATE_NAME, "Success rates for critical hit to damage.", "﹪", ar, "{float}% For Success Hit");
		
		delete ar;
		ar = new ArrayList(RuneLevel_Max - 1);
		
		for (int current_benefit = 0; current_benefit < sizeof(g_CritDmgStats); current_benefit++)
		{
			ar.PushArray(g_CritDmgStats[current_benefit], sizeof(g_CritDmgStats[]));
		}
		
		g_iRuneId[Rune_Crit_Dmg] = JB_CreateRune("critdmgrune", RUNE_CRIT_DMG_NAME, "Extra critical damage bonus for every knife attack.", "⚔", ar, "+{int} Damage");
		
		delete ar;
	}
}

public void OnClientPostAdminCheck(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!g_bIsRuneEnabled || weapon == -1 || (GetClientTeam(victim) == GetClientTeam(attacker)))
	{
		return Plugin_Continue;
	}
	
	int iEquippedRune[Rune_Crit_Max];
	
	iEquippedRune[Rune_Crit_Rate] = JB_GetClientEquippedRune(attacker, g_iRuneId[Rune_Crit_Rate]);
	iEquippedRune[Rune_Crit_Dmg] = JB_GetClientEquippedRune(attacker, g_iRuneId[Rune_Crit_Dmg]);
	
	if (iEquippedRune[Rune_Crit_Rate] == -1 || iEquippedRune[Rune_Crit_Dmg] == -1)
	{
		return Plugin_Continue;
	}
	
	ClientRune ClientRuneData;
	
	JB_GetClientRuneData(attacker, iEquippedRune[Rune_Crit_Rate], ClientRuneData);
	
	if (GetRandomFloat(0.0, 100.0) <= g_CritRateStats[ClientRuneData.RuneStar - 1][ClientRuneData.RuneLevel - 1])
	{
		char szWeaponName[32];
		GetEntityClassname(weapon, szWeaponName, sizeof(szWeaponName));
		
		// Make sure the attacker is attacking with a knife
		if (StrContains(szWeaponName, "knife") != -1 || StrContains(szWeaponName, "bayonet") != -1)
		{
			JB_GetClientRuneData(attacker, iEquippedRune[Rune_Crit_Dmg], ClientRuneData);
			
			// Add the damage bonus to the attack
			damage += float(g_CritDmgStats[ClientRuneData.RuneStar - 1][ClientRuneData.RuneLevel - 1]);
			
			PerformCritEffect(attacker, { 0, 0, 155, 45 } );
			PerformCritEffect(victim, { 155, 0, 0, 45 } );
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

void PerformCritEffect(int client, int color[4])
{
	int clients[1];
	clients[0] = client;
	
	int duration = 105;
	int holdtime = 105;
	int flags = 0;
	
	Handle message = StartMessageEx(g_FadeUserMsgId, clients, sizeof(clients));
	
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
		BfWriteShort(message, duration);
		BfWriteShort(message, holdtime);
		BfWriteShort(message, flags);
		BfWriteByte(message, color[0]);
		BfWriteByte(message, color[1]);
		BfWriteByte(message, color[2]);
		BfWriteByte(message, color[3]);
	}
	
	EndMessage();
}

public void JB_OnRuneToggle(int runeIndex, bool toggleMode)
{
	// Make sure the changed rune is the plugin's rune index
	if (runeIndex == g_iRuneId[Rune_Crit_Rate] || runeIndex == g_iRuneId[Rune_Crit_Dmg])
	{
		g_bIsRuneEnabled = toggleMode;
	}
}

//================================================================//
