#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <shop>
#include <JB_SettingsSystem>
#include <shop_premium>

#define PLUGIN_AUTHOR "KoNLiG"
#define PLUGIN_VERSION "1.00"

//==========[ Settings ]==========//

#define PREFIX " \x04[Play-IL]\x01"
#define PREFIX_ERROR " \x02[Error]\x01"

#define GAMBLE_MIN_BET 300
#define GAMBLE_MAX_BET 1500000

#define XGAMBLE_MIN_BET_TIMES 5
#define XGAMBLE_MAX_BET_TIMES 100

#define GAMBLE_COOLDOWN 1.2

//====================//

GlobalForward g_fwdOnClientGamble;

ConVar g_cvGambleWinChancePercent;
ConVar g_cvEnableXGamble;

float g_fNextGambleUnixstamp[MAXPLAYERS + 1];

int g_iGambleMessagesMinSettingId = -1;
int g_iGambleMessagesVisibleSettingId = -1;

public Plugin myinfo = 
{
	name = "[CS:GO] Shop System - Gamble", 
	author = PLUGIN_AUTHOR, 
	description = "An additional gamble Add-On to the shop system.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// ConVars Configurate
	g_cvGambleWinChancePercent = CreateConVar("shop_gamble_win_chance_percent", "40", "Controls the gamble win percentage. (Both gamble types)", _, true, 1.0, true, 100.0);
	g_cvEnableXGamble = CreateConVar("shop_enable_xgamble", "1", "Decides whether or not the x-gamble feature will function.", _, true, 0.0, true, 1.0);
	
	AutoExecConfig(true, "Gamble", "shop");
	
	// If the shop already started, call the started callback, for late plugin load
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	// Client Commands
	RegConsoleCmd("sm_gamble", Command_Gamble, "Allows players to gamble on their credits.");
	RegConsoleCmd("sm_g", Command_Gamble, "Allows players to gamble on their credits. (An Alias)");
	
	RegConsoleCmd("sm_xgamble", Command_XGamble, "Allows players to gamble on their credits multiply times in once.");
	RegConsoleCmd("sm_xg", Command_XGamble, "Allows players to gamble on their credits multiply times in once. (An Alias)");
}

//================================[ Events ]================================//

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "JB_SettingsSystem"))
	{
		JB_CreateSettingCategory("Shop Settings", "This category is associated with settings that related to the shop.", -1);
		
		g_iGambleMessagesMinSettingId = JB_CreateSetting("setting_gamble_msg_min", "Represents the minimum gamble amount for the chat message to be visible. (Int setting)", "Gamble Messages Minimum", "Shop Settings", Setting_Int, GAMBLE_MAX_BET, "0");
		g_iGambleMessagesVisibleSettingId = JB_CreateSetting("setting_gamble_msg_visible", "Controls whether the gamble messages will be visible to the player. (Bool setting)", "Gamble Messages Visible", "Shop Settings", Setting_Bool, 1.0, "1");
	}
}

public void Shop_Started()
{
	Shop_AddToFunctionsMenu(OnGambleShopDisplay, OnGambleShopSelect);
}

public void OnGambleShopDisplay(int client, char[] buffer, int maxlength)
{
	FormatEx(buffer, maxlength, "Gamble Your Credits\n  > +%d%% For Premium Members!", PREMIUM_GAMBLE_BONUS_CHANCES);
}

public bool OnGambleShopSelect(int client)
{
	Command_Gamble(client, 0);
	return true;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_fwdOnClientGamble = new GlobalForward("Shop_OnClientGamble", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	
	RegPluginLibrary("ShopGamble");
	
	return APLRes_Success;
}

public void OnClientPostAdminCheck(int client)
{
	g_fNextGambleUnixstamp[client] = 0.0;
}

//================================[ Commands ]================================//

public Action Command_Gamble(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Display the command usage if there is no arguments specified
	if (args != 1)
	{
		PrintToChat(client, "%s Usage: \x04/gamble\x01 <credits>", PREFIX);
		return Plugin_Handled;
	}
	
	// Get the typed chat argument
	char szArg[16];
	GetCmdArg(1, szArg, sizeof(szArg));
	
	int iClientCredits = Shop_GetClientCredits(client);
	
	// Calculate the bet amount
	int iBetAmount = (StrEqual(szArg, "all") ? iClientCredits : StrContains(szArg, "k") != -1 ? StringToInt(szArg) * 1000 : StringToInt(szArg));
	
	// Abort the action if the client does'nt have enough credits
	if (iBetAmount > iClientCredits)
	{
		PrintToChat(client, "%s You don't have enough credits to gamble on.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Abort the action if the client has went out of the gamble bounds
	if (!(GAMBLE_MIN_BET <= iBetAmount <= GAMBLE_MAX_BET))
	{
		PrintToChat(client, "%s Gamble bet went out of bounds! \x04(Min: %s, Max: %s)\x01", PREFIX_ERROR, AddCommas(GAMBLE_MIN_BET), AddCommas(GAMBLE_MAX_BET));
		return Plugin_Handled;
	}
	
	// Check for the gamble cooldown
	if (GetGameTime() < g_fNextGambleUnixstamp[client])
	{
		PrintToChat(client, "%s Gambling is currently on cooldown for \x04%.1f\x01 more seconds, consider using \x07/xgamble\x01.", PREFIX, g_fNextGambleUnixstamp[client] - GetGameTime());
		return Plugin_Handled;
	}
	
	bool IsClientPremium = Shop_IsClientPremium(client);
	
	bool IsGambleWon = GetRandomInt(1, 100) <= (g_cvGambleWinChancePercent.IntValue + (IsClientPremium ? PREMIUM_GAMBLE_BONUS_CHANCES : 0));
	
	if (IsClientPremium)
	{
		Format(szArg, sizeof(szArg), "\x0B(+%d%%%%%%)\x01", PREMIUM_GAMBLE_BONUS_CHANCES);
	}
	
	// Notify every online client
	PrintToChatBySetting(client, iBetAmount, "%s \x04%N\x01 has gambled on \x07%s\x01 credits and %s%s!", PREFIX, client, AddCommas(iBetAmount), IsGambleWon ? "\x04WON" : "\x07LOST", IsClientPremium && IsGambleWon ? szArg : "");
	
	// Update the client credits value 
	IsGambleWon ? Shop_GiveClientCredits(client, iBetAmount, CREDITS_BY_LUCK) : Shop_TakeClientCredits(client, iBetAmount, CREDITS_BY_LUCK);
	
	// Execute the client gamble forward
	ExecuteClientGambleForward(client, iBetAmount, IsGambleWon, false);
	
	// Apply the gamble cooldown
	g_fNextGambleUnixstamp[client] = GetGameTime() + GAMBLE_COOLDOWN;
	
	return Plugin_Handled;
}

public Action Command_XGamble(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// If the xgamble feature if disabled at the moment, abort the action
	if (!g_cvEnableXGamble.BoolValue)
	{
		PrintToChat(client, "%s \x0EXGamble\x01 is unavailable!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Display the command usage if there is no arguments specified
	if (args != 2)
	{
		PrintToChat(client, "%s Usage: \x04/xgamble\x01 <times> <credits>", PREFIX);
		return Plugin_Handled;
	}
	
	// Get the specified gamble times
	char szCurrentArg[16];
	GetCmdArg(1, szCurrentArg, sizeof(szCurrentArg));
	int iGambleTimes = StringToInt(szCurrentArg);
	
	if (!(XGAMBLE_MIN_BET_TIMES <= iGambleTimes <= XGAMBLE_MAX_BET_TIMES))
	{
		PrintToChat(client, "%s XGamble roll times went out of bounds! \x04(Min: %d, Max: %d)\x01", PREFIX_ERROR, XGAMBLE_MIN_BET_TIMES, XGAMBLE_MAX_BET_TIMES);
		return Plugin_Handled;
	}
	
	// Get the specified gamble bet amount
	GetCmdArg(2, szCurrentArg, sizeof(szCurrentArg));
	
	int iClientCredits = Shop_GetClientCredits(client);
	
	// Calculate the bet amount
	int iBetAmount = (StrEqual(szCurrentArg, "all") ? iClientCredits : StrContains(szCurrentArg, "k") != -1 ? StringToInt(szCurrentArg) * 1000 : StringToInt(szCurrentArg));
	
	// Abort the action if the client does'nt have enough credits
	if ((iBetAmount * iGambleTimes) > iClientCredits)
	{
		PrintToChat(client, "%s You don't have enough credits to gamble on.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Abort the action if the client has went out of the gamble bounds
	if (!(GAMBLE_MIN_BET <= (iBetAmount * iGambleTimes) <= GAMBLE_MAX_BET) || !(GAMBLE_MIN_BET <= iBetAmount <= GAMBLE_MAX_BET))
	{
		PrintToChat(client, "%s Gamble bet went out of bounds! \x04(Min: %s, Max: %s)\x01", PREFIX_ERROR, AddCommas(GAMBLE_MIN_BET), AddCommas(GAMBLE_MAX_BET));
		return Plugin_Handled;
	}
	
	bool IsClientPremium = Shop_IsClientPremium(client);
	
	int iRewardResult;
	
	// Creates a loop that is executed for the roll times
	for (int iCurrentRoll = 0; iCurrentRoll < iGambleTimes; iCurrentRoll++)
	{
		bool gamble_result = GetRandomInt(1, 100) <= (g_cvGambleWinChancePercent.IntValue + (IsClientPremium ? PREMIUM_GAMBLE_BONUS_CHANCES : 0));
		
		iRewardResult = gamble_result ? iRewardResult + iBetAmount : iRewardResult - iBetAmount;
		
		// Execute the client gamble forward
		ExecuteClientGambleForward(client, iBetAmount / iGambleTimes, gamble_result, true);
	}
	
	// If the client has earned nothing, notify the clients and abort the action
	if (!iRewardResult)
	{
		PrintToChatBySetting(client, iBetAmount * iGambleTimes, "%s \x04%N\x01 xgambled \x03%d times\x01 for \x07%s credits\x01 and he \x02earned nothing\x01.", PREFIX, client, iGambleTimes, AddCommas(iBetAmount));
		return Plugin_Handled;
	}
	
	bool bIsGambleProfit = iRewardResult > 0;
	
	// Recalculate the reward result
	iRewardResult = bIsGambleProfit ? iRewardResult : iRewardResult * -1;
	
	if (IsClientPremium)
	{
		Format(szCurrentArg, sizeof(szCurrentArg), " \x0B(+%d%%%%%%)\x01", PREMIUM_GAMBLE_BONUS_CHANCES);
	}
	
	// Notify every online client
	PrintToChatBySetting(client, iBetAmount * iGambleTimes, "%s \x04%N\x01 xgambled \x03%d times\x01 for \x07%s credits\x01 and he earned: %s%s credits\x01.%s", PREFIX, client, iGambleTimes, AddCommas(iBetAmount), bIsGambleProfit ? "\x04+" : "\x02-", AddCommas(iRewardResult), IsClientPremium && bIsGambleProfit ? szCurrentArg : "");
	
	// Update the client credits value 
	bIsGambleProfit ? Shop_GiveClientCredits(client, iRewardResult, CREDITS_BY_LUCK) : Shop_TakeClientCredits(client, iRewardResult, CREDITS_BY_LUCK);
	
	return Plugin_Handled;
}

//================================[ Functions ]================================//

void PrintToChatBySetting(int gambler_index, int bet_amount, const char[] message, any...)
{
	char szFormatedMessage[256];
	VFormat(szFormatedMessage, sizeof(szFormatedMessage), message, 4);
	
	char szSettingValue[2][8];
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client) && !IsFakeClient(current_client))
		{
			JB_GetClientSetting(current_client, g_iGambleMessagesMinSettingId, szSettingValue[0], sizeof(szSettingValue[]));
			JB_GetClientSetting(current_client, g_iGambleMessagesVisibleSettingId, szSettingValue[1], sizeof(szSettingValue[]));
			
			if (current_client == gambler_index || (StringToInt(szSettingValue[0]) <= bet_amount && StringToInt(szSettingValue[1])))
			{
				PrintToChat(current_client, szFormatedMessage);
			}
		}
	}
}

void ExecuteClientGambleForward(int client, int credits, bool result, bool xgamble)
{
	Call_StartForward(g_fwdOnClientGamble);
	Call_PushCell(client);
	Call_PushCell(credits);
	Call_PushCell(result);
	Call_PushCell(xgamble);
	Call_Finish();
}

//================================================================//
