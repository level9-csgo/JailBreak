#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_GuardsSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define RANDOM_NUMBER_GAME 15 // Time in seconds for the random number game to display.

#define MIN_NUMBER 1
#define MAX_NUMBER 350

Handle g_hGameTimer = INVALID_HANDLE;

bool g_bIsEventEnabled = false;

int g_iVoteId = -1;
int g_iGameTimer = 0;
int g_iClientNumber[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Random Number", 
	author = PLUGIN_AUTHOR, 
	description = "Random Number ", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnAllPluginsLoaded()
{
	if (LibraryExists("JB_GuardsSystem"))
	{
		g_iVoteId = JB_AddVoteCT("Random Number", "Random number game.");
	}
}

/* Events */

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GuardsSystem"))
	{
		g_iVoteId = JB_AddVoteCT("Random Number", "Random number game.");
	}
}

public void OnMapStart()
{
	if (g_hGameTimer != INVALID_HANDLE) {
		KillTimer(g_hGameTimer);
	}
	g_hGameTimer = INVALID_HANDLE;
}

public void OnClientDisconnect(int client)
{
	g_iClientNumber[client] = 0;
}

public void JB_OnVoteCTEnd(int voteId)
{
	if (g_iVoteId == voteId)
	{
		g_bIsEventEnabled = true;
		g_iGameTimer = RANDOM_NUMBER_GAME;
		g_hGameTimer = CreateTimer(1.0, Timer_RandomNumber, _, TIMER_REPEAT);
		
		char szMessage[128];
		Format(szMessage, sizeof(szMessage), "%s Vote CT - Random Number\n \nRandom number will end in %d seconds. \nGuess a number between %d-%d.", PREFIX_MENU, g_iGameTimer, MIN_NUMBER, MAX_NUMBER);
		showAlertPanel(szMessage, 1);
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) {
				g_iClientNumber[iCurrentClient] = 0;
			}
		}
	}
}

public void JB_OnVoteCTStop()
{
	if (g_bIsEventEnabled)
	{
		if (g_hGameTimer != INVALID_HANDLE) {
			KillTimer(g_hGameTimer);
		}
		g_hGameTimer = INVALID_HANDLE;
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) {
				g_iClientNumber[iCurrentClient] = 0;
			}
		}
		
		g_bIsEventEnabled = false;
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] szArgs)
{
	if (g_bIsEventEnabled && IsStringNumric(szArgs))
	{
		int iNumber = StringToInt(szArgs);
		
		if (JB_IsClientBannedCT(client)) {
			PrintToChat(client, "%s You cannot compete on this game due to your Ban CT.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		if (g_iClientNumber[client] != 0) {
			PrintToChat(client, "%s You have already guessed the number \x04%d\x01.", PREFIX_ERROR, g_iClientNumber[client]);
			return Plugin_Handled;
		}
		if (!(MIN_NUMBER <= iNumber <= MAX_NUMBER)) {
			PrintToChat(client, "%s Number \x04%d\x01 is out of range! [\x02%d-%d\x01].", PREFIX_ERROR, iNumber, MIN_NUMBER, MAX_NUMBER);
			return Plugin_Handled;
		}
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient) && g_iClientNumber[iCurrentClient] == iNumber) {
				PrintToChat(client, "%s Number \x04%d\x01 is already taken, please choose another numner.", PREFIX_ERROR, iNumber);
				return Plugin_Handled;
			}
		}
		
		g_iClientNumber[client] = iNumber;
		PrintToChat(client, "%s You have guessed the number \x04%d\x01, wait till the random number will end!", PREFIX, iNumber);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

/*  */

/* Menus */

void showAlertPanel(char[] szMessage, int iTime = MENU_TIME_FOREVER)
{
	Panel panel = new Panel();
	panel.DrawText(szMessage);
	
	for (int iCurrentItem = 0; iCurrentItem < 7; iCurrentItem++) {
		panel.DrawItem("", ITEMDRAW_NOTEXT);
	}
	panel.DrawItem("", ITEMDRAW_SPACER);
	panel.DrawItem("Exit");
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			panel.Send(iCurrentClient, Handler_DoNothing, iTime);
		}
	}
	
	delete panel;
}

int Handler_DoNothing(Menu menu, MenuAction action, int client, int itemNum)
{
	/* Do Nothing */
	return 0;
}

/*  */

/* Timers */

public Action Timer_RandomNumber(Handle hTimer)
{
	if (g_iGameTimer <= 1)
	{
		int iFinalNumber = GetRandomInt(MIN_NUMBER, MAX_NUMBER), iGameWinner = -1, iClosestNumber = MAX_NUMBER;
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient) && g_iClientNumber[iCurrentClient] != 0)
			{
				if (Math_Abs(iFinalNumber - g_iClientNumber[iCurrentClient]) < iClosestNumber) {
					iClosestNumber = Math_Abs(iFinalNumber - g_iClientNumber[iCurrentClient]);
					iGameWinner = iCurrentClient;
				}
			}
		}
		
		char szMessage[128];
		if (iGameWinner != -1) {
			Format(szMessage, sizeof(szMessage), "the random number was \x07%d\x01 and he wrote \x07%d\x01.", iFinalNumber, g_iClientNumber[iGameWinner]);
		}
		
		JB_SetVoteCTWinner(g_iVoteId, iGameWinner, szMessage);
		
		g_bIsEventEnabled = false;
		g_hGameTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iGameTimer--;
	
	char szMessage[128];
	Format(szMessage, sizeof(szMessage), "%s Vote CT - Random Number\n \nRandom number will end in %d seconds. \nGuess a number between %d-%d.", PREFIX_MENU, g_iGameTimer, MIN_NUMBER, MAX_NUMBER);
	showAlertPanel(szMessage, 1);
	return Plugin_Continue;
}

/* Functions */

bool IsStringNumric(const char[] string)
{
	for (int iCurrentChar = 0; iCurrentChar < strlen(string); iCurrentChar++)
	{
		if (!IsCharNumeric(string[iCurrentChar])) {
			return false;
		}
	}
	
	return true;
}

int Math_Abs(int value)
{
	return value < 0 ? value * -1:value;
}

/*  */