#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_GuardsSystem>

#define PLUGIN_AUTHOR "KoNLiG & Ravid"

#define BUTTONS_AMOUNT 8
#define COMBO_CONTEST_TIME 15 // Time in seconds for the combo contest game to display.

#define COLOR_DARKBLUE "<font color='#0000B3'>"
#define COLOR_MAGENTA "<font color='#FF00FF'>"
#define COLOR_END "</font>"

Handle g_hGameTimer = INVALID_HANDLE;
Handle g_hEndGameTimer = INVALID_HANDLE;

char g_szButtons[][] = 
{
	"Attack", 
	"Attack 2", 
	"Jump", 
	"Duck", 
	"Forward", 
	"Back", 
	"Use", 
	"Move Left", 
	"Move Right", 
	"Reload", 
	"Scoreboard", 
	"Shift"
};

int g_iButtons[] = 
{
	IN_ATTACK, 
	IN_ATTACK2, 
	IN_JUMP, 
	IN_DUCK, 
	IN_FORWARD, 
	IN_BACK, 
	IN_USE, 
	IN_MOVELEFT, 
	IN_MOVERIGHT, 
	IN_RELOAD, 
	IN_SCORE, 
	IN_SPEED
};

bool g_bIsEventEnabled = false;

int g_iVoteId = -1;
int g_iGameTimer = 0;
int g_iRandomButtons[BUTTONS_AMOUNT] = { -1, ... };

int g_iClientButton[MAXPLAYERS + 1] = { 0, ... };
int g_iOldButtons[MAXPLAYERS + 1] = { 0, ... };

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Combo Contest", 
	author = PLUGIN_AUTHOR, 
	description = "Combo Contest game for the guards sysetm.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnAllPluginsLoaded()
{
	if (LibraryExists("JB_GuardsSystem"))
	{
		g_iVoteId = JB_AddVoteCT("Combo Contest", "Combo contest game.");
	}
}

/* Events */

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GuardsSystem"))
	{
		g_iVoteId = JB_AddVoteCT("Combo Contest", "Combo contest game.");
	}
}

public void OnMapStart()
{
	DeleteAllTimers();
}

public void JB_OnVoteCTEnd(int voteId)
{
	if (g_iVoteId == voteId)
	{
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient))
			{
				if (!IsPlayerAlive(iCurrentClient))
				{
					CS_RespawnPlayer(iCurrentClient);
				}
			}
			
			g_iClientButton[iCurrentClient] = 0;
		}
		
		g_iGameTimer = 3;
		g_hGameTimer = CreateTimer(1.0, Timer_ComboContest, _, TIMER_REPEAT);
		
		GetRandomButtons();
		
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "%s Vote CT - Combo Contest\n \nPrepare! Combo contest will start in %d seconds!", PREFIX_MENU, g_iGameTimer);
		showAlertPanel(szMessage, 1);
		PrintToChatAll("%s \x02Prepare!\x01 \x04Combo contest\x01 will start in \x0C%d\x01 seconds!", PREFIX, g_iGameTimer);
	}
}

public void JB_OnVoteCTStop()
{
	if (g_hGameTimer != INVALID_HANDLE)
	{
		for (int iCurrentButton = 0; iCurrentButton < BUTTONS_AMOUNT; iCurrentButton++) {
			g_iRandomButtons[iCurrentButton] = -1;
		}
		
		DeleteAllTimers();
		PrintCenterTextAll("");
		g_bIsEventEnabled = false;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (g_bIsEventEnabled && g_hGameTimer != INVALID_HANDLE && !JB_IsClientBannedCT(client))
	{
		int iClientButton = g_iRandomButtons[g_iClientButton[client]];
		if (buttons != 0 && buttons != g_iOldButtons[client])
		{
			if (!g_iOldButtons[client] && (buttons & g_iButtons[iClientButton]))
			{
				g_iClientButton[client]++;
				if (g_iClientButton[client] == BUTTONS_AMOUNT)
				{
					EndGame(client);
					return Plugin_Continue;
				}
				PrintClientButtons(client);
			}
			else
			{
				g_iClientButton[client] = 0;
				PrintClientButtons(client);
			}
		}
		g_iOldButtons[client] = buttons;
	}
	
	return Plugin_Continue;
}

/*  */

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

public Action Timer_ComboContest(Handle hTimer)
{
	if (g_iGameTimer <= 1)
	{
		g_hEndGameTimer = CreateTimer(float(COMBO_CONTEST_TIME), Timer_EndGame);
		g_hGameTimer = CreateTimer(1.0, Timer_HintText, _, TIMER_REPEAT);
		
		for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
		{
			if (IsClientInGame(iCurrentClient)) {
				if (JB_IsClientBannedCT(iCurrentClient)) {
					PrintCenterText(iCurrentClient, " %sYou cannot compete on this game due to your Ban CT.%s", COLOR_MAGENTA, COLOR_END);
					continue;
				}
				PrintClientButtons(iCurrentClient);
			}
		}
		
		g_bIsEventEnabled = true;
		return Plugin_Stop;
	}
	
	g_iGameTimer--;
	char szMessage[256];
	Format(szMessage, sizeof(szMessage), "%s Vote CT - Combo Contest\n \nPrepare! Combo contest will start in %d seconds!", PREFIX_MENU, g_iGameTimer);
	showAlertPanel(szMessage, 1);
	PrintToChatAll("%s \x02Prepare!\x01 \x04Combo contest\x01 will start in \x0C%d\x01 seconds!", PREFIX, g_iGameTimer);
	
	return Plugin_Continue;
}

Action Timer_HintText(Handle timer)
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !JB_IsClientBannedCT(iCurrentClient))
		{
			PrintClientButtons(iCurrentClient);
		}
	}
	
	return Plugin_Continue;
}

Action Timer_EndGame(Handle hTimer)
{
	g_bIsEventEnabled = false;
	for (int iCurrentButton = 0; iCurrentButton < BUTTONS_AMOUNT; iCurrentButton++) {
		g_iRandomButtons[iCurrentButton] = -1;
	}
	
	PrintCenterTextAll("");
	JB_SetVoteCTWinner(g_iVoteId, -1);
	
	if (g_hGameTimer != INVALID_HANDLE)
	{
		KillTimer(g_hGameTimer);
		g_hGameTimer = INVALID_HANDLE;
	}
	
	g_hEndGameTimer = INVALID_HANDLE;
	
	return Plugin_Continue;
}

/*  */

/* Stocks & Functions */

void PrintClientButtons(int client)
{
	char szMessage[512];
	Format(szMessage, sizeof(szMessage), "%sCombo Contest:%s", COLOR_MAGENTA, COLOR_END);
	for (int iCurrectButton = 0; iCurrectButton < BUTTONS_AMOUNT; iCurrectButton++)
	{
		Format(szMessage, sizeof(szMessage), "%s\n%s%s%s", szMessage, g_iClientButton[client] == iCurrectButton ? COLOR_DARKBLUE..."-- ":"", g_szButtons[g_iRandomButtons[iCurrectButton]], g_iClientButton[client] == iCurrectButton ? " --"...COLOR_END:"");
	}
	PrintCenterText(client, szMessage);
}

void EndGame(int client)
{
	for (int iCurrentButton = 0; iCurrentButton < BUTTONS_AMOUNT; iCurrentButton++) {
		g_iRandomButtons[iCurrentButton] = -1;
	}
	
	g_bIsEventEnabled = false;
	JB_SetVoteCTWinner(g_iVoteId, client);
	
	PrintCenterTextAll("");
	DeleteAllTimers();
}

void GetRandomButtons()
{
	ArrayList alCurrentArray = new ArrayList(sizeof(g_iButtons));
	
	for (int iCurrectButton = 0; iCurrectButton < sizeof(g_iButtons); iCurrectButton++) {
		alCurrentArray.Push(iCurrectButton);
	}
	
	int NumOfItems = sizeof(g_iButtons);
	int iCounter = 0;
	
	for (int iCurrectButton = 0; iCurrectButton < BUTTONS_AMOUNT; iCurrectButton++)
	{
		int iTemporary = GetRandomInt(0, NumOfItems - 1);
		g_iRandomButtons[iCounter] = alCurrentArray.Get(iTemporary);
		iCounter++;
	}
	delete alCurrentArray;
}

void DeleteAllTimers()
{
	if (g_hGameTimer != INVALID_HANDLE) {
		KillTimer(g_hGameTimer);
	}
	g_hGameTimer = INVALID_HANDLE;
	if (g_hEndGameTimer != INVALID_HANDLE) {
		KillTimer(g_hEndGameTimer);
	}
	g_hEndGameTimer = INVALID_HANDLE;
}

/*  */