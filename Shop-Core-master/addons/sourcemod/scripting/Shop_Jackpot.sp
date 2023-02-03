#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <shop>

#define PLUGIN_AUTHOR "KoNLiG & IlayBro"
#define PLUGIN_VERSION "1.00"

//==========[ Settings ]==========//

#define PREFIX " \x04[Play-IL]\x01"
#define PREFIX_ERROR " \x02[Error]\x01"

//====================//

enum struct Bet
{
	int client_serial;
	int bet_amount;
	
	float win_chance;
}

ArrayList g_Jackpot;

GlobalForward g_OnJackpotResults;

ConVar g_cvMinJackpotBetAmount;

public Plugin myinfo = 
{
	name = "[CS:GO] Shop System - Jackpot", 
	author = PLUGIN_AUTHOR, 
	description = "An additional jackpot Add-On to the shop system.", 
	version = PLUGIN_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the jackpot arraylist
	g_Jackpot = new ArrayList(sizeof(Bet));
	
	// ConVars Configurate
	g_cvMinJackpotBetAmount = CreateConVar("shop_min_jackpot_bet_amount", "50", "Minimum possible amount for a jackpot bet Bet.", _, true, 1.0, true, 500.0);
	
	AutoExecConfig(true, "Jackpot", "shop");
	
	// If the shop already started, call the started callback, for late plugin load
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	// Client Commands
	RegConsoleCmd("sm_jackpot", Command_Jackpot, "Bet a bet into the jackpot.");
	RegConsoleCmd("sm_jp", Command_Jackpot, "Bet a bet into the jackpot. (An Alias)");
	
	// Command Listeners
	AddCommandListener(Listener_RetriveJackpot, "sm_map");
	AddCommandListener(Listener_RetriveJackpot, "map");
	AddCommandListener(Listener_RetriveJackpot, "changelevel");
	
	// Event Hooks
	HookEvent("round_end", Event_RoundEnd);
}

public void OnPluginEnd()
{
	// If the plugin has managed to end, means the server has crashed/shutted down, execute the jackpot roll back
	ExecuteRollBack();
}

//================================[ API ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_OnJackpotResults = new GlobalForward(
		"Shop_OnJackpotResults", 
		ET_Ignore,  // Always return 0.
		Param_Cell,  // int winner
		Param_Float,  // float chance 
		Param_Cell,  // int bet
		Param_Cell // int prize
		);
	
	RegPluginLibrary("shop_jackpot");
	
	return APLRes_Success;
}

<<<<<<< HEAD
void Call_OnJackpotResults(int winner, float chance, int bet, int prize)
=======
void Call_OnQuestsReset(int winner, float chance, int bet, int prize)
>>>>>>> 2d57143d7a5e8f106bd8fca2a91e560f144a9eab
{
	Call_StartForward(g_OnJackpotResults);
	Call_PushCell(winner);
	Call_PushFloat(chance);
	Call_PushCell(bet);
	Call_PushCell(prize);
	
	int error = Call_Finish();
	if (error != SP_ERROR_NONE)
	{
		ThrowNativeError(error, "Shop jackpot results forward failed - Error: (%d)", error);
	}
}

//================================[ Events ]================================//

public void OnClientDisconnect(int client)
{
	int client_bet_index = GetBetIndexByClient(client);
	if (client_bet_index == -1)
	{
		return;
	}
	
	Bet BetData; BetData = GetBetByIndex(client_bet_index);
	
	float jackpot_chance_bonus = BetData.win_chance / (g_Jackpot.Length - 1);
	
	for (int current_bet = 0; current_bet < g_Jackpot.Length; current_bet++)
	{
		// Initialize the current Bet data
		BetData = GetBetByIndex(current_bet);
		
		// If the current Bet client index is invalid, or the Bet index is equal to the disconnected client, skip the current loop
		if (!GetClientFromSerial(BetData.client_serial) || current_bet == client_bet_index)
		{
			continue;
		}
		
		BetData.win_chance += jackpot_chance_bonus;
		
		g_Jackpot.SetArray(current_bet, BetData);
	}
}

public void Shop_Started()
{
	Shop_AddToFunctionsMenu(OnJackpotShopDisplay, OnJackpotShopSelect);
}

void OnJackpotShopDisplay(int client, char[] buffer, int maxlength)
{
	FormatEx(buffer, maxlength, "Jackpot\n  > Current Jackpot: %s Credits", AddCommas(GetJackpotSum()));
}

bool OnJackpotShopSelect(int client)
{
	Command_Jackpot(client, 0);
	return true;
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	int jackpot_sum = GetJackpotSum();
	if (!jackpot_sum)
	{
		return;
	}
	
	Bet BetData;
	
	float random_winner = GetRandomFloat(0.0, 100.0);
	
	int jackpot_bet_winner = -1;
	
	for (int current_bet = 0; current_bet < g_Jackpot.Length; current_bet++)
	{
		// Initialize the current bet data
		BetData = GetBetByIndex(current_bet);
		
		if (!GetClientFromSerial(BetData.client_serial))
		{
			continue;
		}
		
		random_winner -= BetData.win_chance;
		
		if (random_winner <= 0.0)
		{
			jackpot_bet_winner = current_bet;
			break;
		}
	}
	
	if (jackpot_bet_winner == -1)
	{
		PrintToChatAll("%s All players disconnect, nobody get his credits back, lol. The jackpot was \x02%s credits\x01!", PREFIX, AddCommas(jackpot_sum));
		
		g_Jackpot.Clear();
		
<<<<<<< HEAD
		Call_OnJackpotResults(-1, 0.0, 0, jackpot_sum);
=======
		Call_OnQuestsReset(-1, 0.0, 0, jackpot_sum);
>>>>>>> 2d57143d7a5e8f106bd8fca2a91e560f144a9eab
		
		return;
	}
	
	BetData = GetBetByIndex(jackpot_bet_winner);
	
	int winner_index = GetClientFromSerial(BetData.client_serial);
	
	PrintToChatAll(" \x06%N\x01 has won the \x03%s credits\x01 jackpot with \x04%.2f%%\x01.", winner_index, AddCommas(jackpot_sum), float(BetData.bet_amount) / float(jackpot_sum) * 100.0);
	
	Shop_GiveClientCredits(winner_index, jackpot_sum, CREDITS_BY_LUCK);
	
	g_Jackpot.Clear();
	
<<<<<<< HEAD
	PrintToConsoleAll("%f", BetData.win_chance);
	
	Call_OnJackpotResults(winner_index, BetData.win_chance, BetData.bet_amount, jackpot_sum);
=======
	Call_OnQuestsReset(winner_index, BetData.win_chance, BetData.bet_amount, jackpot_sum);
>>>>>>> 2d57143d7a5e8f106bd8fca2a91e560f144a9eab
}

//================================[ Commands ]================================//

Action Listener_RetriveJackpot(int client, const char[] command, int argc)
{
	// If the map has changed manumally, and the round didnt end, execute the jackpot roll back
	ExecuteRollBack();
	
	return Plugin_Continue;
}

Action Command_Jackpot(int client, int args)
{
	// Deny the command access from the server console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	int client_jackpot_bet = GetClientJackpotBet(client), jackpot_sum = GetJackpotSum();
	
	if (client_jackpot_bet)
	{
		PrintToChat(client, "%s The jackpot value is \x03%s\x01.", PREFIX, AddCommas(jackpot_sum));
		PrintToChat(client, "%s Your jackpot winning chance is %.2f%% with \x0B%s\x01/\x0C%s\x01 credits!", PREFIX, float(client_jackpot_bet) / float(jackpot_sum) * 100.0, AddCommas(client_jackpot_bet), AddCommas(jackpot_sum));
		return Plugin_Handled;
	}
	
	// Display the jackpot value if there is no args specified
	if (args != 1)
	{
		PrintToChat(client, "%s Jackpot value is \x03%s\x01 credits.", PREFIX, AddCommas(jackpot_sum));
		return Plugin_Handled;
	}
	
	// Initialize the specified bet amount, and make sure it's valid
	char arg[16];
	GetCmdArg(1, arg, sizeof(arg));
	
	int client_credits = Shop_GetClientCredits(client);
	
	// Calculate the specified bet amount by the first arg
	int bet_amount = (StrEqual(arg, "all") ? client_credits : StrContains(arg, "k") != -1 ? StringToInt(arg) * 1000 : StringToInt(arg));
	
	if (bet_amount < g_cvMinJackpotBetAmount.IntValue)
	{
		PrintToChat(client, "%s Minimum jackpot bet is \x04%d\x01 credits!", PREFIX_ERROR, g_cvMinJackpotBetAmount.IntValue);
		return Plugin_Handled;
	}
	
	// Make sure the client has enough credits to enter the jackpot
	if (client_credits < bet_amount)
	{
		PrintToChat(client, "%s You don't have enough credits to enter the jacpot!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Charge the client for the jackpot bet
	Shop_TakeClientCredits(client, bet_amount);
	
	jackpot_sum += bet_amount;
	
	Bet BetData;
	
	BetData.client_serial = GetClientSerial(client);
	BetData.bet_amount = bet_amount;
	
	g_Jackpot.PushArray(BetData);
	
	for (int current_bet = 0; current_bet < g_Jackpot.Length; current_bet++)
	{
		// Initialize the current Bet data
		BetData = GetBetByIndex(current_bet);
		
		BetData.win_chance = float(BetData.bet_amount) / float(jackpot_sum) * 100.0;
		
		g_Jackpot.SetArray(current_bet, BetData);
	}
	
	// Notify every online client
	PrintToChatAll(" \x04%N\x01 has increased the jackpot by \x03%s credits\x01 \x05(%.2f%%)\x01.", client, AddCommas(bet_amount), float(bet_amount) / float(jackpot_sum) * 100.0);
	
	return Plugin_Handled;
}

//================================[ Functions ]================================//

any[] GetBetByIndex(int index)
{
	Bet BetData;
	g_Jackpot.GetArray(index, BetData);
	return BetData;
}

int GetBetIndexByClient(int client)
{
	return g_Jackpot.FindValue(GetClientSerial(client));
}

void ExecuteRollBack()
{
	// Make sure there is atleast 1 jackpot bet
	if (!g_Jackpot || !g_Jackpot.Length)
	{
		return;
	}
	
	for (int current_client = 1, current_bet_amount; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			current_bet_amount = GetClientJackpotBet(current_client);
			
			if (current_bet_amount)
			{
				Shop_GiveClientCredits(current_client, current_bet_amount);
			}
		}
	}
	
	g_Jackpot.Clear();
}

int GetJackpotSum()
{
	int jackpot_sum;
	
	for (int current_bet = 0; current_bet < g_Jackpot.Length; current_bet++)
	{
		jackpot_sum += GetBetByIndex(current_bet).bet_amount;
	}
	
	return jackpot_sum;
}

int GetClientJackpotBet(int client)
{
	// Initialize the client serial
	int client_serial = GetClientSerial(client);
	
	Bet CurrentBetData;
	
	for (int current_bet = 0; current_bet < g_Jackpot.Length; current_bet++)
	{
		// Initialize the current Bet data
		CurrentBetData = GetBetByIndex(current_bet);
		
		// Check for a serial match
		if (CurrentBetData.client_serial == client_serial)
		{
			return CurrentBetData.bet_amount;
		}
	}
	
	return 0;
}

//================================================================//
