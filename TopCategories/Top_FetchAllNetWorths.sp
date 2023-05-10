#include <sourcemod>
#include <JailBreak>
#include <JB_NetWorth>

#pragma semicolon 1
#pragma newdecls required

Database g_Database;

public Plugin myinfo = 
{
	name = "Fetches all players networth", 
	author = "KoNLiG", 
	description = "Top net worth module for the top system.", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Connect to the database
	Database db = JB_GetDatabase();
	
	if (db != null)
	{
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
}

//================================[ JailBreak Events ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	g_Database.Query(SQL_LoadAuths, "SELECT `auth` FROM `shop_players`");
}

void SQL_LoadAuths(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("[SQL_LoadAuths] %s", error);
	}
	
	char steamid2[MAX_AUTHID_LENGTH];
	int account_id;
	
	while (results.FetchRow())
	{
		results.FetchString(0, steamid2, sizeof(steamid2));
		account_id = GetAccountIdFromSteam2(steamid2);
		
		JB_GetPlayerNetWorth(account_id, OnPlayerNetWorthSuccess, INVALID_FUNCTION);
	}
}

void OnPlayerNetWorthSuccess(int account_id, const char[] target_name, any data, int total_net_worth, int credits, int shop_items_value, int runes_value, float response_time)
{
	char query[256];
	g_Database.Format(query, sizeof(query), "INSERT INTO `top_networth`(`account_id`, `name`, `net_worth`) VALUES(%d, '%s', %d) ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `net_worth` = VALUES(`net_worth`)", account_id, target_name, total_net_worth);
	g_Database.Query(SQL_CheckForErrors, query);
}

void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("General databse error, %s", error);
	}
}

int GetAccountIdFromSteam2(const char[] steamid2)
{
	return StringToInt(steamid2[10]) * 2 + (steamid2[8] - 48);
}

//================================================================//