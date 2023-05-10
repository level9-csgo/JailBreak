#include <sourcemod>
#include <JailBreak>
#include <JB_NetWorth>

#pragma semicolon 1
#pragma newdecls required

#define LINE_BREAK "\xE2\x80\xA9"

#define SEPERATOR " \x07\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E" ... \
"\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF\xE2\x8E\xAF"

Regex g_Steamid2;

public Plugin myinfo = 
{
	name = "[JailBreak Misc]", 
	author = "KoNLiG", 
	description = "Implementation of JB_NetWorth into commands.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Required for 'FindTarget' responses.
	LoadTranslations("common.phrases");
	
	// Compile a steam id2 regex expression.
	g_Steamid2 = new Regex("^STEAM_[0-5]:[0-1]:[0-9]+$");
	
	// Register commands.
	RegConsoleCmd("sm_networth", Command_NetWorth, "Displays the calculated net worth of a certain player, offline or online.");
	RegConsoleCmd("sm_nw", Command_NetWorth, "Displays the calculated net worth of a certain player, offline or online. (alias)");
}

Action Command_NetWorth(int client, int argc)
{
	if (!client)
	{
		ReplyToCommand(client, "[SM] This command is unavailable via the server console.");
		return Plugin_Handled;
	}
	
	int account_id;
	
	// 0 arguments means client is the target itself.
	if (!argc)
	{
		account_id = GetSteamAccountID(client);
	}
	else
	{
		// Can be whether a steamid, name, or userid.
		char target_arg[MAX_NAME_LENGTH];
		GetCmdArgString(target_arg, sizeof(target_arg));
		
		int matches = g_Steamid2.Match(target_arg);
		if (matches > 1)
		{
			PrintToChat(client, "%s You cannot enter multiple steam id(s)!", PREFIX_ERROR);
			return Plugin_Handled;
		}
		// A single match has been found.
		else if (matches == 1)
		{
			char steamid2[MAX_AUTHID_LENGTH];
			g_Steamid2.GetSubString(0, steamid2, sizeof(steamid2));
			
			account_id = StringToInt(steamid2[10]) * 2 + (steamid2[8] - 48);
		}
		// No steamid matches.
		else
		{
			int target = FindTarget(client, target_arg, true, false);
			if (target != -1)
			{
				account_id = GetSteamAccountID(target);
			}
		}
	}
	
	if (!account_id)
	{
		PrintToChat(client, "%s Failed to initialize an account id, please enter a valid name/steamid2.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	JB_GetPlayerNetWorth(account_id, OnNetWorthSuccess, OnNetWorthFailure, GetClientUserId(client));
	
	return Plugin_Handled;
}

void OnNetWorthSuccess(int account_id, const char[] target_name, int userid, int total_net_worth, int credits, int shop_items_value, int runes_value, float response_time)
{
	int client = GetClientOfUserId(userid);
	if (!client)
	{
		return;
	}
	
	PrintToChat(client, SEPERATOR);
	PrintToChat(client, " \x06%s\x07's Networth:"...LINE_BREAK..."\x0E◾ \x10%s\x01", target_name, JB_AddCommas(total_net_worth));
	PrintToChat(client, " \x0E| \x0BCredits: \x10%s\x01", JB_AddCommas(credits));
	PrintToChat(client, " \x0E| \x0BShop Items: \x10%s\x01", JB_AddCommas(shop_items_value));
	PrintToChat(client, " \x0E| \x0BRunes: \x10%s\x01", JB_AddCommas(runes_value));
	PrintToChat(client, " \x06Processing time: \x0E%.4fs\x01", response_time);
	PrintToChat(client, SEPERATOR);
}

void OnNetWorthFailure(int account_id, int userid, float response_time)
{
	int client = GetClientOfUserId(userid);
	if (client)
	{
		PrintToChat(client, "%s Failed to find data for account id - \x07%d\x01! [\x07%fs\x01]", PREFIX_ERROR, account_id, response_time);
	}
} 