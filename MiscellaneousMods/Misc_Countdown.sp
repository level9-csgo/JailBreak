#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>

#define PLUGIN_AUTHOR "KoNLiG"

enum struct Client
{
	bool bIsFreezePrisoners;
	int iTimeStage;
	
	void Reset() {
		this.bIsFreezePrisoners = false;
		this.iTimeStage = 0;
	}
}

Client g_esClientsData[MAXPLAYERS + 1];

Handle g_hCountdownTimer = INVALID_HANDLE;

bool g_bIsCountdownOn;

int g_iOperatorIndex = -1;
int g_iStartTimer;

int g_iCountdownTimes[] = 
{
	5, 
	10, 
	15
};

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak Misc - Countdown", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	// Guards & Admins Commands
	RegConsoleCmd("sm_countdown", Command_Countdown, "Access the countdown menu.");
	RegConsoleCmd("sm_cd", Command_Countdown, "Access the countdown menu. (An Alias)");
}

//================================[ Events ]================================//

public void OnMapEnd()
{
	if (g_bIsCountdownOn)
	{
		ToggleCountdown(false);
	}
	
	if (g_hCountdownTimer != INVALID_HANDLE) {
		KillTimer(g_hCountdownTimer);
		g_hCountdownTimer = INVALID_HANDLE;
	}
}

public void OnClientPostAdminCheck(int client)
{
	g_esClientsData[client].Reset();
}

//================================[ Commands ]================================//

public Action Command_Countdown(int client, int args)
{
	if (args == 1)
	{
		// Block the feature to administrators only
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
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
			PrintToChat(client, "%s Countdown menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
		} else {
			ShowCountdownMenu(iTargetIndex);
		}
	}
	else
	{
		if (!IsClientAllowed(client)) {
			PrintToChat(client, "%s Countdown menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
		} else {
			ShowCountdownMenu(client);
		}
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowCountdownMenu(int client)
{
	char szItem[32];
	Menu menu = new Menu(Handler_Countdown);
	menu.SetTitle("%s Countdown Menu:\n ", PREFIX_MENU);
	
	Format(szItem, sizeof(szItem), "Countdown Time: %ds", g_iCountdownTimes[g_esClientsData[client].iTimeStage]);
	menu.AddItem("", szItem);
	
	Format(szItem, sizeof(szItem), "Prisoners Freeze: %s", g_esClientsData[client].bIsFreezePrisoners ? "ON" : "OFF");
	menu.AddItem("", szItem);
	
	menu.AddItem("", g_bIsCountdownOn ? "Stop Countdown" : "Start Countdown");
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_Countdown(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, iItemNum = param2;
		
		if (!IsClientAllowed(client))
		{
			PrintToChat(client, "%s Countdown menu is allowed only for \x04admins and guards\x01.", PREFIX_ERROR);
			return;
		}
		
		switch (iItemNum)
		{
			case 0:g_esClientsData[client].iTimeStage = ++g_esClientsData[client].iTimeStage % sizeof(g_iCountdownTimes);
			case 1:g_esClientsData[client].bIsFreezePrisoners = !g_esClientsData[client].bIsFreezePrisoners;
			case 2:
			{
				g_bIsCountdownOn = !g_bIsCountdownOn;
				g_iOperatorIndex = client;
				ToggleCountdown(g_bIsCountdownOn);
			}
		}
		
		ShowCountdownMenu(client);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu to avoid memory problems
		delete menu;
	}
}

//================================[ Timers ]================================//

public Action Timer_Countdown(Handle hTimer)
{
	if (g_iStartTimer <= 1)
	{
		g_iOperatorIndex = -1;
		
		ToggleCountdown(false);
		
		g_hCountdownTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iStartTimer--;
	PrintCenterTextAll(" Countdown Timer: <font color='#ffcc00'>%d</font>\n Priosners Freeze: %s</font>", g_iStartTimer, g_esClientsData[g_iOperatorIndex].bIsFreezePrisoners ? "<font color='#00FF00'>ON" : "<font color='#ff0000'>OFF");
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

void ToggleCountdown(bool toggleMode)
{
	if (g_iOperatorIndex != -1)
	{
		char szText[32];
		Format(szText, sizeof(szText), " for \x02%d\x01 seconds!", g_iCountdownTimes[g_esClientsData[g_iOperatorIndex].iTimeStage]);
		PrintToChatAll("%s \x04%N\x01 has %s the countdown%s%s", PREFIX, g_iOperatorIndex, toggleMode ? "started":"stopped", !toggleMode ? "!":szText, g_esClientsData[g_iOperatorIndex].bIsFreezePrisoners && toggleMode ? " \x0B*Prisoners Freezed*" : "");
	}
	
	if (g_iOperatorIndex != -1 && toggleMode)
	{
		if (g_esClientsData[g_iOperatorIndex].bIsFreezePrisoners)
		{
			FreezePrisoners();
		}
		
		g_iStartTimer = g_iCountdownTimes[g_esClientsData[g_iOperatorIndex].iTimeStage] + 1;
		g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT);
		
		Timer_Countdown(g_hCountdownTimer);
		
		return;
	}
	
	if (g_hCountdownTimer != INVALID_HANDLE) {
		KillTimer(g_hCountdownTimer);
		g_hCountdownTimer = INVALID_HANDLE;
	}
	
	FreezePrisoners(false);
	
	PrintCenterTextAll("");
	
	g_bIsCountdownOn = false;
}

void FreezePrisoners(bool freeze = true)
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && IsPlayerAlive(iCurrentClient) && GetClientTeam(iCurrentClient) == CS_TEAM_T)
		{
			SetEntPropFloat(iCurrentClient, Prop_Data, "m_flLaggedMovementValue", freeze ? 0.0 : 1.0);
		}
	}
}

bool IsClientAllowed(int client)
{
	return (GetUserAdmin(client) != INVALID_ADMIN_ID || (GetClientTeam(client) == CS_TEAM_CT && IsPlayerAlive(client)));
}

//================================================================//
