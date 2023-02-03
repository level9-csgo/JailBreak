#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <JB_GamesSystem>
#include <rtler>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define GAME_NAME "Trivia"

#define CONFIG_PATH "addons/sourcemod/configs/TriviaQuestions.cfg"

//====================//

enum struct Question
{
	char question[256];
	char answer[64];
}

ArrayList g_QuestionsData;

char g_GameAnswer[64];

bool g_IsGameRunning;

int g_iGameId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - "...GAME_NAME..." Game", 
	author = PLUGIN_AUTHOR, 
	description = GAME_NAME..." side game.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_QuestionsData = new ArrayList(sizeof(Question));
}

public void OnPluginEnd()
{
	if (g_IsGameRunning)
	{
		JB_StopGame(g_iGameId, -1);
	}
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_GamesSystem"))
	{
		g_iGameId = JB_CreateGame(GAME_NAME);
	}
}

public void OnMapStart()
{
	KV_LoadTriviaQuestions();
}

public void JB_OnGameStart(int gameId, int client)
{
	if (g_iGameId == gameId)
	{
		Question QuestionData; QuestionData = GetQuestionByIndex(GetRandomInt(0, g_QuestionsData.Length - 1));
		
		strcopy(g_GameAnswer, sizeof(g_GameAnswer), QuestionData.answer);
		
		// Rtlify the formatted message
		char rtlify_question[128];
		RTLify(rtlify_question, sizeof(rtlify_question), QuestionData.question);
		
		ShowAlertPanel("%s Games System - %s\n \n?%s", PREFIX_MENU, GAME_NAME, rtlify_question);
		
		g_IsGameRunning = true;
	}
}

public void JB_OnGameStop(int gameId, int winner)
{
	if (g_iGameId == gameId && g_IsGameRunning)
	{
		g_IsGameRunning = false;
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!g_IsGameRunning || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T || StrContains(g_GameAnswer, sArgs, false) == -1)
	{
		return Plugin_Continue;
	}
	
	JB_StopGame(g_iGameId, client);
	
	g_IsGameRunning = false;
	
	g_GameAnswer[0] = '\0';
	
	return Plugin_Continue;
}

//================================[ Menus ]================================//

void ShowAlertPanel(const char[] message, any...)
{
	char formatted_message[256];
	VFormat(formatted_message, sizeof(formatted_message), message, 2);
	
	Panel panel = new Panel();
	panel.DrawText(formatted_message);
	
	panel.CurrentKey = 8;
	panel.DrawItem("", ITEMDRAW_SPACER);
	panel.DrawItem("Exit");
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			panel.Send(current_client, Handler_DoNothing, MENU_TIME_FOREVER);
		}
	}
	
	delete panel;
}

public int Handler_DoNothing(Menu menu, MenuAction action, int client, int itemNum)
{
	/* Do Nothing */
}

//================================[ Key Values ]================================//

void KV_LoadTriviaQuestions()
{
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Cannot find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Questions");
	kv.SetEscapeSequences(true);
	
	kv.ImportFromFile(CONFIG_PATH);
	kv.GotoFirstSubKey();
	
	g_QuestionsData.Clear();
	
	Question QuestionData;
	
	do {
		kv.GetString("question", QuestionData.question, sizeof(QuestionData.question));
		kv.GetString("answer", QuestionData.answer, sizeof(QuestionData.answer));
		
		g_QuestionsData.PushArray(QuestionData);
	} while (kv.GotoNextKey());
	
	kv.Close();
}

//================================[ Functions ]================================//

any[] GetQuestionByIndex(int index)
{
	Question QuestionData;
	g_QuestionsData.GetArray(index, QuestionData);
	return QuestionData;
}

//================================================================//
