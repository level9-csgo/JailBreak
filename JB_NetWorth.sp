#include <sourcemod>
#include <regex>
#include <ripext>
#include <profiler>
#include <JailBreak>
#include <JB_NetWorth>
#include <JB_RunesSystem>

#pragma semicolon 1
#pragma newdecls required

Database g_Database;

public Plugin myinfo = 
{
	name = "[JailBreak] Net Worth", 
	author = "KoNLiG", 
	description = "Calculates a player value by net worth including credits, shop items, and personal runes.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Late load database connection.
	Database db = JB_GetDatabase();
	
	if (db != null)
	{
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNatives();
	
	RegPluginLibrary(JB_NETWORTH_LIBRARY_NAME);
	return APLRes_Success;
}

//================================[ API ]================================//

void CreateNatives()
{
	CreateNative("JB_GetPlayerNetWorth", Native_GetPlayerNetWorth);
}

any Native_GetPlayerNetWorth(Handle plugin, int numParams)
{
	int account_id = GetNativeCell(1);
	if (!account_id)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Account id cannot be 0.");
	}
	
	Function success_callback = GetNativeFunction(2);
	Function failure_callback = GetNativeFunction(3);
	
	if (success_callback == INVALID_FUNCTION && failure_callback == INVALID_FUNCTION)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Both callbacks cannot be null.");
	}
	
	any data = GetNativeCell(4);
	
	CalculatePlayerNetWorth(account_id, success_callback, failure_callback, plugin, data);
	
	return 0;
}

void Call_OnPlayerNetWorthSuccess(Function func, Handle plugin, int account_id, const char[] target_name, any data, int total_net_worth, int credits, int shop_items_value, int runes_value, float response_time)
{
	Call_StartFunction(plugin, func);
	Call_PushCell(account_id);
	Call_PushString(target_name);
	Call_PushCell(data);
	Call_PushCell(total_net_worth);
	Call_PushCell(credits);
	Call_PushCell(shop_items_value);
	Call_PushCell(runes_value);
	Call_PushFloat(response_time);
	Call_Finish();
}

void Call_OnPlayerNetWorthFailure(Function func, Handle plugin, int account_id, any data, float response_time)
{
	Call_StartFunction(plugin, func);
	Call_PushCell(account_id);
	Call_PushCell(data);
	Call_PushFloat(response_time);
	Call_Finish();
}

//================================[ Database ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
}

void CalculatePlayerNetWorth(int account_id, Function success_callback, Function failure_callback, Handle plugin, any data)
{
	DataPack dp = new DataPack();
	dp.WriteCell(account_id);
	dp.WriteFunction(success_callback);
	dp.WriteFunction(failure_callback);
	dp.WriteCell(plugin);
	dp.WriteCell(data);
	
	char query[64];
	g_Database.Format(query, sizeof(query), "SELECT GetPlayerNetWorth(%d)", account_id);
	
	Profiler profiler = new Profiler();
	profiler.Start();
	
	dp.WriteCell(profiler);
	
	g_Database.Query(OnPlayerNetWorthCalculatedSuccess, query, dp);
}

void OnPlayerNetWorthCalculatedSuccess(Database db, DBResultSet results, const char[] error, DataPack dp)
{
	dp.Reset();
	
	int account_id = dp.ReadCell();
	
	Function success_callback = dp.ReadFunction();
	Function failure_callback = dp.ReadFunction();
	
	Handle plugin = dp.ReadCell();
	any data = dp.ReadCell();
	Profiler profiler = dp.ReadCell();
	
	profiler.Stop();
	float response_time = profiler.Time;
	
	delete profiler;
	
	dp.Close();
	
	if (!db || !results || error[0])
	{
		if (failure_callback != INVALID_FUNCTION)
		{
			Call_OnPlayerNetWorthFailure(failure_callback, plugin, account_id, data, response_time);
		}
		
		ThrowError("[OnPlayerNetWorthCalculatedSuccess] %s", error);
	}
	
	// Make sure the client has joined the server at least once.
	if (!results.HasResults || !results.FetchRow())
	{
		if (failure_callback != INVALID_FUNCTION)
		{
			Call_OnPlayerNetWorthFailure(failure_callback, plugin, account_id, data, response_time);
		}
		
		return;
	}
	
	char json_str[256];
	results.FetchString(0, json_str, sizeof(json_str));
	
	// No data for 'account_id'.
	if (!json_str[0])
	{
		if (failure_callback != INVALID_FUNCTION)
		{
			Call_OnPlayerNetWorthFailure(failure_callback, plugin, account_id, data, response_time);
		}
		
		return;
	}
	
	EscapeBackslashes(json_str, sizeof(json_str));
	
	JSONObject jsonObject = JSONObject.FromString(json_str);
	
	char target_name[MAX_NAME_LENGTH];
	jsonObject.GetString("player_name", target_name, sizeof(target_name));
	
	int credits = jsonObject.GetInt("credits");
	int shop_items_value = jsonObject.GetInt("items");
	int runes_value = jsonObject.GetInt("runes_value");
	
	delete jsonObject;
	
	if (success_callback != INVALID_FUNCTION)
	{
		Call_OnPlayerNetWorthSuccess(success_callback, plugin, account_id, target_name, data, credits + shop_items_value + runes_value, credits, shop_items_value, runes_value, response_time);
	}
}

void EscapeBackslashes(char[] str, int size)
{
	char[] truncted_str = new char[size];
	
	for (int i; str[i]; i++)
	{
		if (str[i] == '\\')
		{
			strcopy(truncted_str, size, str);
			ReplaceString(truncted_str, size, str[i], "");
			
			Format(str, size, "%s\\%s", truncted_str, str[i]);
			
			i++;
		}
	}
}

//================================================================//