#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_RunesSystem>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define RETRIVE_HEALTH_AMOUNT 100

#define MAX_START_TIME 5

//====================//

enum struct BoxData
{
	bool bIsFreezePrisoners;
	bool bIsBackstabOnly;
	int iStartTime;
	
	void Reset()
	{
		this.bIsFreezePrisoners = false;
		this.bIsBackstabOnly = false;
		this.iStartTime = 0;
	}
}

BoxData g_esClientsData[MAXPLAYERS + 1];
BoxData g_esBoxData;

Handle g_hBoxTimer = INVALID_HANDLE;

ConVar g_cvFriendlyFire;
ConVar g_cvTeammatesAreEnemies;

bool g_bIsBoxEnabled;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Box", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// ConVars Configurate
	g_cvFriendlyFire = FindConVar("mp_friendlyfire");
	g_cvTeammatesAreEnemies = FindConVar("mp_teammates_are_enemies");
	
	// Admin & Guard Commands
	RegConsoleCmd("sm_box", Command_Box, "Access the box settings configuration menu.");
	
	// Event hooks
	HookEvent("player_death", Event_PlayerDeath);
	
	// Loop through all the online clients, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPostAdminCheck(current_client);
		}
	}
}

//================================[ Events ]================================//

public void JB_OnRunesStarted()
{
	char plugin_name[PLATFORM_MAX_PATH];
	GetPluginFilename(INVALID_HANDLE, plugin_name, sizeof(plugin_name));
	
	ServerCommand("sm plugins reload %s", plugin_name);
}

public void OnClientPostAdminCheck(int client)
{
	g_esClientsData[client].Reset();
	
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void OnMapEnd()
{
	if (g_bIsBoxEnabled)
	{
		ToggleBox(0, false);
	}
	
	if (g_hBoxTimer != INVALID_HANDLE)
	{
		KillTimer(g_hBoxTimer);
		g_hBoxTimer = INVALID_HANDLE;
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bIsBoxEnabled && (GetOnlineTeamCount(CS_TEAM_T) <= 1 || GetOnlineTeamCount(CS_TEAM_CT) <= 0))
	{
		// Disable the box
		ToggleBox(0, false);
		
		// Notify server
		PrintToChatAll("%s Box has \x02turned off\x01 due to dying of all the guards or 1 prisoner left.", PREFIX);
	}
}

//================================[ SDK Hooks ]================================//

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!g_bIsBoxEnabled || !(1 <= attacker <= MaxClients))
	{
		return Plugin_Continue;
	}
	
	if (GetClientTeam(victim) == CS_TEAM_CT && GetClientTeam(attacker) == CS_TEAM_CT)
	{
		return Plugin_Handled;
	}
	
	char weapon_name[32];
	GetClientWeapon(attacker, weapon_name, sizeof(weapon_name));
	
	if (g_esBoxData.bIsBackstabOnly)
	{
		if (StrContains(weapon_name, "knife") != -1 || StrContains(weapon_name, "bayonet") != -1)
		{
			if (!IsStabBackstab(attacker, victim))
			{
				return Plugin_Handled;
			}
		}
		else if (!(damagetype & CS_DMG_HEADSHOT))
		{
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

//================================[ Commands ]================================//

public Action Command_Box(int client, int args)
{
	if (args == 1)
	{
		// Block the feature to administrators only
		if (GetUserAdmin(client) == INVALID_ADMIN_ID)
		{
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int iTargetIndex = FindTarget(client, szArg, true, false);
		
		if (iTargetIndex == -1)
		{
			// Automated message
			return Plugin_Handled;
		}
		
		if (!IsClientAllowed(iTargetIndex)) {
			PrintToChat(client, "%s Box menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
		} else {
			ShowBoxMenu(iTargetIndex);
		}
	}
	else
	{
		if (!IsClientAllowed(client)) {
			PrintToChat(client, "%s Box menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
		} else {
			ShowBoxMenu(client);
		}
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowBoxMenu(int client)
{
	char szItem[32];
	Menu menu = new Menu(Handler_Box);
	menu.SetTitle("%s Box Menu:\n ", PREFIX_MENU);
	
	Format(szItem, sizeof(szItem), "Box Status: %s", g_bIsBoxEnabled ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Box Start Timer: %ds", g_esClientsData[client].iStartTime);
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Freeze Prisoners: %s", g_esClientsData[client].bIsFreezePrisoners ? "ON":"OFF");
	menu.AddItem("", szItem);
	Format(szItem, sizeof(szItem), "Backstab Only: %s", g_esClientsData[client].bIsBackstabOnly ? "ON":"OFF");
	menu.AddItem("", szItem);
	
	menu.AddItem("", "Retrive Prisoners Health");
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_Box(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!IsClientAllowed(client))
		{
			PrintToChat(client, "%s Box menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
			return 0;
		}
		
		switch (itemNum)
		{
			case 0:
			{
				if (GetOnlineTeamCount(CS_TEAM_T) < 2)
				{
					PrintToChat(client, "%s Cannot start box with less then \x102 prisoner\x01 alive!", PREFIX_ERROR);
					return 0;
				}
				
				g_bIsBoxEnabled = !g_bIsBoxEnabled;
				
				ToggleBox(client, g_bIsBoxEnabled);
			}
			case 1:g_esClientsData[client].iStartTime = ++g_esClientsData[client].iStartTime % (MAX_START_TIME + 1);
			case 2:g_esClientsData[client].bIsFreezePrisoners = !g_esClientsData[client].bIsFreezePrisoners;
			case 3:g_esClientsData[client].bIsBackstabOnly = !g_esClientsData[client].bIsBackstabOnly;
			case 4:
			{
				for (int current_client = 1; current_client <= MaxClients; current_client++)
				{
					if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
					{
						SetEntityHealth(current_client, RETRIVE_HEALTH_AMOUNT);
					}
				}
				
				PrintToChatAll("%s \x0C%N\x01 has retrieved prisoners health back to \x04%d\x01!", PREFIX, client, RETRIVE_HEALTH_AMOUNT);
			}
		}
		
		ShowBoxMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	
	return 0;
}

//================================[ API ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_IsBoxEnabled", Native_IsBoxEnabled);
	
	return APLRes_Success;
}

any Native_IsBoxEnabled(Handle plugin, int numParams)
{
	return g_bIsBoxEnabled;
}

//================================[ Timers ]================================//

public Action Timer_Box(Handle hTimer)
{
	if (!g_bIsBoxEnabled)
	{
		FreezePrisoners(false);
		
		g_hBoxTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	if (g_esBoxData.iStartTime <= 1)
	{
		FreezePrisoners(false);
		PrintCenterTextAll(" Box has started! <font color='#ff0000'>Fight!</font>");
		
		g_cvFriendlyFire.BoolValue = true;
		g_cvTeammatesAreEnemies.BoolValue = true;
		
		g_hBoxTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_esBoxData.iStartTime--;
	PrintCenterTextAll(" <font color='#ffcc00'>Prepare!</font> Box will start in <font color='#ff0000'>%ds</font>!", g_esBoxData.iStartTime);
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void ToggleBox(int client, bool toggleMode)
{
	if (toggleMode) {
		g_esBoxData = g_esClientsData[client];
	}
	else {
		g_bIsBoxEnabled = false;
	}
	
	if (client)
	{
		char szText[32];
		Format(szText, sizeof(szText), " \x02%d\x01 seconds.", g_esBoxData.iStartTime);
		PrintToChatAll("%s \x04%N\x01 has %s box!%s%s", PREFIX, client, toggleMode ? "enabled":"disabled", !g_esBoxData.iStartTime || !toggleMode ? "":szText, g_esBoxData.bIsBackstabOnly && toggleMode ? " \x0B*Backstab Only*" : "");
	}
	
	if (toggleMode)
	{
		if (g_esBoxData.bIsFreezePrisoners)
		{
			FreezePrisoners();
		}
		
		g_esBoxData.iStartTime++;
		g_hBoxTimer = CreateTimer(1.0, Timer_Box, _, TIMER_REPEAT);
		
		Timer_Box(g_hBoxTimer);
		
		return;
	}
	
	if (g_hBoxTimer != INVALID_HANDLE)
	{
		KillTimer(g_hBoxTimer);
		g_hBoxTimer = INVALID_HANDLE;
	}
	
	PrintCenterTextAll("");
	
	FreezePrisoners(false);
	g_cvFriendlyFire.BoolValue = false;
	g_cvTeammatesAreEnemies.BoolValue = false;
}

void FreezePrisoners(bool freeze = true)
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsPlayerAlive(current_client) && GetClientTeam(current_client) == CS_TEAM_T)
		{
			SetEntPropFloat(current_client, Prop_Data, "m_flLaggedMovementValue", freeze ? 0.0 : 1.0);
		}
	}
}

bool IsStabBackstab(int attacker, int victim)
{
	float abs_angles[3], victim_forward[3], attacker_origin[3], victim_origin[3], vec_los[3];
	
	GetClientAbsAngles(victim, abs_angles);
	GetAngleVectors(abs_angles, victim_forward, NULL_VECTOR, NULL_VECTOR);
	
	GetClientAbsOrigin(attacker, attacker_origin);
	GetClientAbsOrigin(victim, victim_origin);
	
	attacker_origin[2] = victim_origin[2];
	
	SubtractVectors(victim_origin, attacker_origin, vec_los);
	NormalizeVector(vec_los, vec_los);
	
	return GetVectorDotProduct(victim_forward, vec_los) > 0.475;
} 

bool IsClientAllowed(int client)
{
	return (GetUserAdmin(client) != INVALID_ADMIN_ID || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client)));
}

//================================================================//