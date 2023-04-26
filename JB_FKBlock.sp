#include <sourcemod>
#include <JailBreak>

#pragma semicolon 1
#pragma newdecls required

Database g_Database;

enum struct Player
{
	// Player account id.
	int account_id;
	
	// Player userid.
	int userid;
	
	// Unix time stamp of the fk block end time.
	int fk_block_end_time;
	
	//================================//
	void Init(int client)
	{
		this.account_id = GetSteamAccountID(client);
		this.userid = GetClientUserId(client);
		
		this.FetchSQLData();
	}
	
	void Close()
	{
		this.UpdateSQLData();
		
		this.account_id = 0;
		this.userid = 0;
		this.fk_block_end_time = 0;
	}
	
	void ApplyFKBlock(int minutes)
	{
		this.fk_block_end_time = GetTime() + (minutes * 60);
	}
	
	bool IsFKBlocked()
	{
		// The player is not fk blocked.
		if (!this.fk_block_end_time)
		{
			return false;
		}
		// The player had an a fk block, and it has expired.
		else if (this.fk_block_end_time - GetTime() <= 0)
		{
			this.fk_block_end_time = 0;
			return false;
		}
		
		// The player is currently fk blocked.
		return true;
	}
	
	// Retrieves the amount of remaining time (in seconds) of the fk block.
	int GetRemainingBlockTime()
	{
		return this.fk_block_end_time - GetTime();
	}
	
	//===============[ MySQL ]=================//
	void FetchSQLData()
	{
		char query[128];
		g_Database.Format(query, sizeof(query), "SELECT `fk_block_end_time` FROM `jb_fkblock` WHERE `account_id` = '%d'", this.account_id);
		g_Database.Query(SQL_FetchData_CB, query, this.userid);
	}
	
	void UpdateSQLData()
	{
		char query[128];
		g_Database.Format(query, sizeof(query), "UPDATE `jb_fkblock` SET `fk_block_end_time` = '%d' WHERE `account_id` = '%d'", this.fk_block_end_time, this.account_id);
		g_Database.Query(SQL_CheckForErrors, query);
	}
}

Player g_Players[MAXPLAYERS + 1];

char g_FKCmds[][] = 
{
	"sm_freekill", 
	"sm_fk"
};

public Plugin myinfo = 
{
	name = "[JailBreak] FK Block", 
	author = "KoNLiG", 
	description = "Provides a system to allow admins to block players from using the /fk command.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Required for 'FindTarget()' responses.
	LoadTranslations("common.phrases");
	
	// Connect to the database
	Database db = JB_GetDatabase();
	
	if (db != null)
	{
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
	
	// ConVars configuration.
	AutoExecConfig(true, "FKBlock", "JailBreak");
	
	// Commands.
	for (int current_cmd; current_cmd < sizeof(g_FKCmds); current_cmd++)
	{
		AddCommandListener(Listener_BlockFKCmd, g_FKCmds[current_cmd]);
	}
	
	RegAdminCmd("sm_fkblock", Command_FKBlock, ADMFLAG_GENERIC, "Prevent a player from issuing any free kill reports.");
	RegAdminCmd("sm_unfkblock", Command_UnFKBlock, ADMFLAG_GENERIC, "Prevent a player from issuing any free kill reports.");
}

public void OnPluginEnd()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			OnClientDisconnect(current_client);
		}
	}
}

//================================[ Events ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	g_Database.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `jb_fkblock`(`account_id` INT NOT NULL, `fk_block_end_time` INT NOT NULL DEFAULT 0)");
	
	Lateload();
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (!IsFakeClient(client))
	{
		g_Players[client].Init(client);
	}
}

public void OnClientDisconnect(int client)
{
	g_Players[client].Close();
}

//================================[ Command callbacks ]================================//

Action Listener_BlockFKCmd(int client, const char[] command, int argc)
{
	if (!IsClientInGame(client))
	{
		return Plugin_Continue;
	}
	
	if (g_Players[client].IsFKBlocked())
	{
		int remaining_time = g_Players[client].GetRemainingBlockTime(), minutes = remaining_time / 60, seconds = remaining_time % 60;
		
		PrintToChat(client, "%s \x02You are blocked from issuing any free kill reports.\x01 The block will expire in \x07%s%d:%s%d\x01 minutes.", PREFIX, minutes < 10 ? "0" : "", minutes, seconds < 10 ? "0" : "", seconds);
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

Action Command_FKBlock(int client, int argc)
{
	if (argc != 2)
	{
		PrintToChat(client, "%s Usage: sm_fkblock <name|#userid> <minutes>", PREFIX);
		return Plugin_Handled;
	}
	
	char name_arg[MAX_NAME_LENGTH];
	GetCmdArg(1, name_arg, sizeof(name_arg));
	
	int target = FindTarget(client, name_arg, true);
	if (target == -1)
	{
		return Plugin_Handled;
	}
	
	if (g_Players[target].IsFKBlocked())
	{
		int remaining_time = g_Players[target].GetRemainingBlockTime(), minutes = remaining_time / 60, seconds = remaining_time % 60;
		
		PrintToChat(client, "%s Player \x02%N\x01 is already blocked from issuing any free kill reports for \x07%s%d:%s%d\x01 more minutes.", PREFIX, target, minutes < 10 ? "0" : "", minutes, seconds < 10 ? "0" : "", seconds);
		return Plugin_Handled;
	}
	
	char minutes_arg[11];
	GetCmdArg(2, minutes_arg, sizeof(minutes_arg));
	
	int minutes_int;
	if (!StringToIntEx(minutes_arg, minutes_int) || !minutes_int)
	{
		PrintToChat(client, "%s Invalid minutes arg was specified.", PREFIX);
		return Plugin_Handled;
	}
	
	g_Players[target].ApplyFKBlock(minutes_int);
	
	int remaining_time = g_Players[target].GetRemainingBlockTime(), minutes = remaining_time / 60, seconds = remaining_time % 60;
	
	PrintToChatAll("%s \x04%N\x01 has fk blocked \x02%N\x01 for \x03%s%d:%s%d\x01 minutes.", PREFIX, client, target, minutes < 10 ? "0" : "", minutes, seconds < 10 ? "0" : "", seconds);
	
	return Plugin_Handled;
}

Action Command_UnFKBlock(int client, int argc)
{
	if (argc != 1)
	{
		PrintToChat(client, "%s Usage: sm_unfkblock <name|#userid>", PREFIX);
		return Plugin_Handled;
	}
	
	char name_arg[MAX_NAME_LENGTH];
	GetCmdArg(1, name_arg, sizeof(name_arg));
	
	int target = FindTarget(client, name_arg, true);
	if (target == -1)
	{
		return Plugin_Handled;
	}
	
	if (!g_Players[target].IsFKBlocked())
	{
		PrintToChat(client, "%s Player \x04%N\x01 is not fk blocked.", PREFIX, target);
		return Plugin_Handled;
	}
	
	g_Players[target].fk_block_end_time = 0;
	
	PrintToChatAll("%s Admin \x04%N\x01 has deleted \x0E%N's\x01 fk blocked.", PREFIX, client, target);
	
	return Plugin_Handled;
}

//================================[ Utils ]================================//

void SQL_FetchData_CB(Database db, DBResultSet results, const char[] error, int userid)
{
	if (!db || !results || error[0])
	{
		ThrowError("[SQL_FetchData_CB] %s", error);
		return;
	}
	
	int client = GetClientOfUserId(userid);
	if (!client)
	{
		// Client is no longer online.
		return;
	}
	
	if (results.FetchRow())
	{
		g_Players[client].fk_block_end_time = results.FetchInt(0);
	}
	else
	{
		char query[128];
		g_Database.Format(query, sizeof(query), "INSERT INTO `jb_fkblock` (`account_id`) VALUES ('%d')", g_Players[client].account_id);
		g_Database.Query(SQL_CheckForErrors, query);
	}
}

void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (!db || !results || error[0])
	{
		ThrowError("General databse error: %s", error);
	}
}

//================================[ Utils ]================================//

void Lateload()
{
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && IsClientAuthorized(current_client))
		{
			OnClientAuthorized(current_client, "");
		}
	}
}

//================================================================//