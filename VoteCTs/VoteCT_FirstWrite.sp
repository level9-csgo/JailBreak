#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_GuardsSystem>

#define PLUGIN_AUTHOR "KoNLiG"

#define PREPARE_TIME 3
#define FIRST_TIME_TIME 15 // Time in seconds for the first write game to display

Handle g_hGameTimer = INVALID_HANDLE;
Handle g_hEndGameTimer = INVALID_HANDLE;

char g_szRandomWrite[32];

bool g_bIsEventEnabled = false;

int g_iVoteId = -1;
int g_iGameTimer = 0;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - First Write", 
	author = PLUGIN_AUTHOR, 
	description = "First Write game for the guards system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnAllPluginsLoaded()
{
	if (LibraryExists("JB_GuardsSystem"))
	{
		g_iVoteId = JB_AddVoteCT("First Write", "First write game.");
	}
}

/* Events */

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GuardsSystem"))
	{
		g_iVoteId = JB_AddVoteCT("First Write", "First write game.");
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
		g_bIsEventEnabled = true;
		g_iGameTimer = PREPARE_TIME;
		g_hGameTimer = CreateTimer(1.0, Timer_FirstWrite, _, TIMER_REPEAT);
		
		g_szRandomWrite = GetRandomString(6, "abcdefghijklmnopqrstuvwxyz01234556789");
		
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "%s Vote CT - First Write\n \nPrepare! First write will start in %d seconds!", PREFIX_MENU, g_iGameTimer);
		showAlertPanel(szMessage, 1);
		PrintToChatAll("%s \x02Prepare!\x01 \x04First write\x01 will start in \x0C%d\x01 seconds!", PREFIX, g_iGameTimer);
	}
}

public void JB_OnVoteCTStop()
{
	if (g_bIsEventEnabled)
	{
		DeleteAllTimers();
		g_szRandomWrite = "";
		g_bIsEventEnabled = false;
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] szArgs)
{
	if (g_bIsEventEnabled)
	{
		if (StrEqual(g_szRandomWrite, szArgs, true))
		{
			if (JB_IsClientBannedCT(client)) {
				PrintToChat(client, "%s You cannot compete on this game due to your Ban CT.", PREFIX);
				return Plugin_Handled;
			}
			
			JB_SetVoteCTWinner(g_iVoteId, client);
			
			DeleteAllTimers();
			
			g_szRandomWrite = "";
			g_bIsEventEnabled = false;
		}
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

public int Handler_DoNothing(Menu menu, MenuAction action, int client, int itemNum)
{
	/* Do Nothing */
}

/*  */

/* Timers */

public Action Timer_FirstWrite(Handle hTimer)
{
	if (g_iGameTimer <= 1)
	{
		char szMessage[256];
		Format(szMessage, sizeof(szMessage), "%s Vote CT - First Write\n \nThe first one to write %s will become a guard.", PREFIX_MENU, g_szRandomWrite);
		showAlertPanel(szMessage, FIRST_TIME_TIME);
		
		g_hEndGameTimer = CreateTimer(float(FIRST_TIME_TIME), Timer_EndGame);
		g_hGameTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	
	g_iGameTimer--;
	char szMessage[256];
	Format(szMessage, sizeof(szMessage), "%s Vote CT - First Write\n \nPrepare! First write will start in %d seconds!", PREFIX_MENU, g_iGameTimer);
	showAlertPanel(szMessage, 1);
	
	PrintToChatAll("%s \x02Prepare!\x01 \x04First write\x01 will start in \x0C%d\x01 seconds!", PREFIX, g_iGameTimer);
	return Plugin_Continue;
}

public Action Timer_EndGame(Handle hTimer)
{
	g_szRandomWrite = "";
	JB_SetVoteCTWinner(g_iVoteId, -1);
	
	g_bIsEventEnabled = false;
	g_hEndGameTimer = INVALID_HANDLE;
}

/*  */

/* Functions */

char GetRandomString(int length = 32, char[] chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234556789")
{
	char szString[32];
	
	for (int iCurrentChar = 0; iCurrentChar < length; iCurrentChar++)
	{
		Format(szString, sizeof(szString), "%s%c", szString, chars[GetRandomInt(0, strlen(chars) - 1)]);
	}
	
	return szString;
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
