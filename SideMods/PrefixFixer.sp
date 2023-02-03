#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define PREFIX " \x04[Play-IL]\x01"

char g_szPrefixs[][] =  { "[SM]", "[MCE]", "[RTVE]", "[NE]", "Comm: [SM]", "Comm:", "[SourceBans]", "[Vgames]", "[vGames]", "[vGames.co.il]" };

public Plugin myinfo = 
{
	name = "[CS:GO] Prefix Fixer", 
	author = "Ravid", 
	description = "", 
	version = "1.0", 
};

public void OnPluginStart()
{
	if (GetUserMessageType() == UM_Protobuf)
	{
		HookUserMessage(GetUserMessageId("TextMsg"), TextMsg, true);
	}
}

public Action TextMsg(UserMsg msg_id, Protobuf pb, char[] players, int playersNum, bool reliable, bool init)
{
	if (!reliable || PbReadInt(pb, "msg_dst") != 3)
	{
		return Plugin_Continue;
	}
	
	char buffer[256];
	PbReadString(pb, "params", buffer, sizeof(buffer), 0);
	
	if (ContainsPrefix(buffer))
	{
		DataPack dPack;
		CreateDataTimer(0.0, Timer_ChangePrefix, dPack, TIMER_FLAG_NO_MAPCHANGE);
		dPack.WriteCell(playersNum);
		
		for (int i = 0; i < playersNum; i++)
		{
			dPack.WriteCell(players[i]);
		}
		
		dPack.WriteCell(strlen(buffer));
		dPack.WriteString(buffer);
		dPack.Reset();
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Timer_ChangePrefix(Handle timer, DataPack dPack)
{
	int playersNum = dPack.ReadCell();
	int[] players = new int[playersNum];
	int player, players_count;
	
	for (int i = 0; i < playersNum; i++)
	{
		player = dPack.ReadCell();
		
		if (IsClientInGame(player))
		{
			players[players_count++] = player;
		}
	}
	
	playersNum = players_count;
	
	if (playersNum < 1)
	{
		return Plugin_Stop;
	}
	
	Handle pb = StartMessage("TextMsg", players, playersNum, USERMSG_BLOCKHOOKS);
	PbSetInt(pb, "msg_dst", 3);
	
	int buffer_size = dPack.ReadCell() + 15;
	char[] buffer = new char[buffer_size];
	dPack.ReadString(buffer, buffer_size);
	
	replacePrefixs(buffer, buffer_size);
	
	PbAddString(pb, "params", buffer);
	PbAddString(pb, "params", NULL_STRING);
	PbAddString(pb, "params", NULL_STRING);
	PbAddString(pb, "params", NULL_STRING);
	PbAddString(pb, "params", NULL_STRING);
	
	EndMessage();
	
	return Plugin_Continue;
}

bool ContainsPrefix(char[] buffer)
{
	for (int iCurrentPrefix; iCurrentPrefix < sizeof(g_szPrefixs); iCurrentPrefix++)
	{
		if (StrContains(buffer, g_szPrefixs[iCurrentPrefix]) != -1)
		{
			return true;
		}
	}
	
	if (StrContains(buffer, "[SM]") != -1)
	{
		return true;
	}
	
	return false;
}

void replacePrefixs(char[] buffer, int length)
{
	for (int iCurrentPrefix; iCurrentPrefix < sizeof(g_szPrefixs); iCurrentPrefix++)
	{
		if (!StrEqual(g_szPrefixs[iCurrentPrefix], "[SM]"))
		{
			ReplaceString(buffer, length, g_szPrefixs[iCurrentPrefix], PREFIX);
		}
	}
	
	ReplaceString(buffer, length, "[SM]", PREFIX);
} 