#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <cstrike>
#include <JailBreak>
#include <JB_GuardsSystem>
#include <JB_RunesSystem>

#include <queue>
#include <shop>

//==========[ Settings ]==========//

#define RUNE_MODEL_MINS { -10.536178, 0.000000, 0.000000 }
#define RUNE_MODEL_MAXS { 17.565471, 85.399169, 18.357769 }

#define RUNE_MODEL_PATH "models/vGames/boxes/bigbox.mdl"

#define UPGRADE_SUCCEED_SOUND "playil_jailbreak/runes/upgrades/correct.mp3"
#define UPGRADE_POWERUP_SOUND "playil_jailbreak/runes/upgrades/powerup_220.mp3"

#define CAPACITY_EXPANTION_SOUND "ui/store_item_activated.wav"
#define RUTURNED_TO_INVENTORY_SOUND "survival/zone_chosen_by_friend.wav"

#define PROGRESS_BAR_LENGTH 10

#define RUNE_UPGRADE_PROGRESS_INTERVAL 0.2
#define RUNE_PICKUP_PROGRESS_INTERVAL 0.4

#define RANDOM_RUNE_UNIQUE "randomrune"

//====================//

ConVar g_cvDefaultRunesCapacity;

// [1000] = 100%
// 
// 958 = 95.8%
// 40  = 4.0%
// 2   = 0.2%
enum
{
	SpawnChance_Star1To3 = 958,
	SpawnChance_Star4To5 = 40,
	SpawnChance_Star6 = 2
}

enum struct GarbageCollector
{
	// Whether the garbage collector is enabled.
	bool is_enabled;
	
	// Up to this star items will go into the garbage collector.
	int limited_star;
	
	// Stores the included rune bits that will go into the garbage collector.
	int included_runes_bits;
	
	void Reset()
	{
		this.is_enabled = false;
		this.limited_star = 0;
		this.included_runes_bits = 0;
	}
}

enum struct Client
{
	GarbageCollector GarbageCollectorData;
	
	int AccountID;
	
	Queue PickedRunes;
	
	// Stores the client runes inventory by the data struct: 'ClientRune'
	ArrayList RunesInventory;
	
	// Rune pickup information timer
	Handle ShowRuneInfoTimer;
	
	// Rune upgrade information timer
	Handle ShowUpgradeInfoTimer;
	
	// Represents the next rune equip change based on 'GetGameTime()' for the client
	float fNextEquipChange;
	
	int iRunesCapacity;
	int iRunePickupProgress;
	int iRuneUpgradeProgress;
	
	void Reset()
	{
		this.GarbageCollectorData.Reset();
		
		this.AccountID = 0;
		
		delete this.PickedRunes;
		delete this.RunesInventory;
		
		this.fNextEquipChange = 0.0;
		
		this.iRunesCapacity = 0;
		this.iRunePickupProgress = 0;
		this.iRuneUpgradeProgress = 0;
		
		// Don't leak handles!
		this.Close();
		
		// Delete every active timer
		this.DeleteTimers();
	}
	
	void Init()
	{
		// Delete old handles
		this.Close();
		
		// Create the new handles
		this.PickedRunes = new Queue(ByteCountToCells(16));
		this.RunesInventory = new ArrayList(sizeof(ClientRune));
		
		// Set the default variables values
		this.iRunesCapacity = g_cvDefaultRunesCapacity.IntValue;
		this.iRunePickupProgress = 1;
	}
	
	void Close()
	{
		delete this.PickedRunes;
		delete this.RunesInventory;
	}
	
	//=============================================//
	
	void DeleteTimers()
	{
		if (this.ShowRuneInfoTimer != INVALID_HANDLE)
		{
			KillTimer(this.ShowRuneInfoTimer);
			this.ShowRuneInfoTimer = INVALID_HANDLE;
		}
		
		if (this.ShowUpgradeInfoTimer != INVALID_HANDLE)
		{
			KillTimer(this.ShowUpgradeInfoTimer, true);
			this.ShowUpgradeInfoTimer = INVALID_HANDLE;
		}
	}
	
	void GetClientRuneByIndex(int index, any[] buffer)
	{
		this.RunesInventory.GetArray(index, buffer);
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

ArrayList g_RunesData;

GlobalForward g_fwdOnRunesStarted;
GlobalForward g_fwdOnRuneSpawn;
GlobalForward g_fwdOnRunePickup;
GlobalForward g_fwdOnRuneLevelUpgrade;
GlobalForward g_fwdOnRuneEquipChange;
GlobalForward g_fwdOnRunesCapacityExpand;
GlobalForward g_fwdOnRuneSell;
GlobalForward g_fwdOnRuneToggle;

Database g_Database = null;

CategoryId g_ShopCategoryID;

ConVar g_cvMinPlayersRequired;
ConVar g_cvMaxRuneLevelSell;
ConVar g_cvRuneUpgradeNotifyMinLevel;
ConVar g_cvRunePickupNotifyMinStar;
ConVar g_cvCapacityExpandPrice;
ConVar g_cvRuneEquipCooldown;
ConVar g_cvGarbageCollectorPrice;

char g_szProgressSounds[][] = 
{
	"/ui/coin_pickup_01.wav",  // Last Progress
	"/ui/xp_milestone_01.wav",  // Star 1
	"/ui/xp_milestone_02.wav",  // Star 2
	"/ui/xp_milestone_03.wav",  // Star 3
	"/ui/xp_milestone_04.wav",  // Star 4
	"/ui/xp_milestone_05.wav",  // Star 5
	"/ui/deathmatch_kill_bonus.wav" // Star 6
};

// Stores the steam account id of authorized clients for spceial commands
int g_AuthorizedClients[] = 
{
	912414245,  // KoNLiG 
	928490446 // Ravid
};

// Must be with the same difference between every capacity expantion tier
int g_iCapacityTiers[] = 
{
	55, 
	60, 
	65, 
	70, 
	75
};

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Runes System", 
	author = "KoNLiG", 
	description = "A perks system based on 'runes'. Provides level upgrades, rune sells, trades, etc...", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	// Create the runes arraylist
	g_RunesData = new ArrayList(sizeof(Rune));
	
	// ConVars Configurate
	g_cvMinPlayersRequired = CreateConVar("jb_runes_min_players", "12", "Minimum players required for rune box to be dropped.", _, true, 0.0, true, float(MAXPLAYERS));
	g_cvDefaultRunesCapacity = CreateConVar("jb_runes_default_max_capacity", "50", "Default amount of capacity for the max runes client can hold.", _, true, 25.0, true, 75.0);
	g_cvMaxRuneLevelSell = CreateConVar("jb_runes_max_level_sell", "8", "Maximum rune level to be possible to sell it.", _, true, float(RuneLevel_1), true, float(RuneLevel_Max));
	g_cvRuneUpgradeNotifyMinLevel = CreateConVar("jb_runes_upgrade_notify_min_level", "10", "The minimum level required for a rune level upgrade to be notified to all the players. (If succeed)", _, true, float(RuneLevel_1), true, float(RuneLevel_Max));
	g_cvRunePickupNotifyMinStar = CreateConVar("jb_runes_pickup_notify_min_star", "5", "The minimum star required for a rune pickup to be notified to all the players.", _, true, float(RuneStar_1), true, float(RuneStar_Max));
	g_cvCapacityExpandPrice = CreateConVar("jb_runes_general_data_expantion_price", "500000", "The price for every capacity expantion.", _, true, 250000.0, true, 1000000.0);
	g_cvRuneEquipCooldown = CreateConVar("jb_runes_equip_cooldown", "2.7", "The cooldown seconds, between every rune equip state change.", _, true, 1.5, true, 10.0);
	g_cvGarbageCollectorPrice = CreateConVar("jb_runes_garbage_collector_price", "57500", "The purchase price for the runes garbage collector item.", _, true, 12500.0, true, 500000.0);
	
	AutoExecConfig(true, "RunesSystem", "JailBreak");
	
	// Connect to the database
	Database db = JB_GetDatabase();
	
	if (db != null)
	{
		JB_OnDatabaseConnected(db);
	}
	
	delete db;
	
	// Load the common translation, required for FindTarget() 
	LoadTranslations("common.phrases");
	
	// Admin Commands
	RegAdminCmd("sm_spawnrune", Command_SpawnRune, ADMFLAG_ROOT, "Spawns a rune by the client's aim position.");
	RegAdminCmd("sm_addrune", Command_AddRune, ADMFLAG_ROOT, "Add a rune to a certain client's inventory.");
	
	// Client Commands
	RegConsoleCmd("sm_runes", Command_Runes, "Access the runes list menu.");
	
	// Event Hooks
	HookEvent("player_death", Event_PlayerDeath);
	
	// Shop support for late plugin load
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
}

public void OnPluginEnd()
{
	// Unregister the shop from this plugin
	Shop_UnregisterMe();
	
	// Loop throgh all the online clients, make sure to send their data to the database
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientDisconnect(current_client);
		}
	}
}

//================================[ Events ]================================//

public void Shop_Started()
{
	g_ShopCategoryID = Shop_RegisterCategory("runes", "Runes", "This category is related to the runes system.");
	
	// HACK: Creates duplicate shop item bug, which unloads most of the JailBreak mods.
	if (Shop_IsItemExists(Shop_GetItemId(g_ShopCategoryID, "Runes Garbage Collector")))
	{
		return;
	}
	
	if (Shop_StartItem(g_ShopCategoryID, "Runes Garbage Collector"))
	{
		Shop_SetInfo("Runes Garbage Collector", "Provides garbage collector that can automatically collect runes by your desired filters!", g_cvGarbageCollectorPrice.IntValue, -1, Item_None, 0);
		Shop_SetCallbacks();
		Shop_EndItem();
	}
}

public void OnClientAuthorized(int client, const char[] auth)
{
	// If the authorized client is fake or we couldn't get the client steam account id, don't continue
	if (IsFakeClient(client) || !(g_ClientsData[client].AccountID = GetSteamAccountID(client)))
	{
		return;
	}
	
	g_ClientsData[client].Init();
	
	// Fetch the client data from the database
	SQL_FetchClient(client);
}

public void OnClientDisconnect(int client)
{
	// Validate the client steam account id, which means the client isn't a bot and his data has been loaded
	if (g_ClientsData[client].AccountID)
	{
		// Update the client data inside the database
		SQL_UpdateClientGeneralData(client);
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// Make sure there are enough players to spawn a rune.
	if (!g_RunesData.Length || GetOnlineTeamCount(CS_TEAM_CT, false) + GetOnlineTeamCount(CS_TEAM_T, false) < g_cvMinPlayersRequired.IntValue)
	{
		return;
	}
	
	int victim_index = GetClientOfUserId(event.GetInt("userid"));
	int attacker_index = GetClientOfUserId(event.GetInt("attacker"));
	
	// Ignore suicides.
	if (victim_index == attacker_index)
	{
		return;
	}
	
	// Make sure atleast 1 rune exists, and the victim index isn't equal to the killer index
	if (g_RunesData.Length && victim_index != attacker_index)
	{
		// Make sure the victim is a guard, or the victim has died in a last request
		if (JB_GetClientGuardRank(victim_index) != Guard_NotGuard || (JB_GetClientGuardRank(victim_index) == Guard_NotGuard && !GetOnlineTeamCount(CS_TEAM_T)))
		{
			// Get the victim death position
			float death_position[3];
			GetClientAbsOrigin(victim_index, death_position);
			
			// Create a random rune box entity
			CreateRuneBox(death_position, GetRandomInt(0, g_RunesData.Length - 1), GenerateRuneStar());
		}
	}
}

//================================[ SDK Hooks ]================================//

// [ Called once client has picked up a rune entity ] //
Action Hook_OnStartTouch(int entity, int other)
{
	// Make sure the entity has touched a client
	if (!(1 <= other <= MaxClients))
	{
		return Plugin_Continue;
	}
	
	// picker_client_index = The client who picked up the rune box entity
	int picker_client_index = other;
	
	char szEntityName[16];
	GetEntPropString(entity, Prop_Data, "m_iName", szEntityName, sizeof(szEntityName));
	
	char szData[3][16];
	ExplodeString(szEntityName, ":", szData, sizeof(szData), sizeof(szData[]));
	
	RunePickupBlockReasons PickupBlockReason;
	
	// Block the rune pickup if the client is a guard and there are alive prisoners
	if (JB_GetClientGuardRank(picker_client_index) != Guard_NotGuard && GetOnlineTeamCount(CS_TEAM_T))
	{
		PickupBlockReason = RUNE_PICKUP_BLOCK_GUARD;
	}
	
	// Blocked the rune pickup if the client capacity is maxed out
	if (g_ClientsData[picker_client_index].RunesInventory.Length >= g_ClientsData[picker_client_index].iRunesCapacity)
	{
		PickupBlockReason = RUNE_PICKUP_BLOCK_CAPACITY;
	}
	
	// Initialize the rune data by the entity name
	int iRuneId = StringToInt(szData[0]);
	int iRuneStar = StringToInt(szData[1]);
	int iRuneLevel = StringToInt(szData[2]);
	
	Rune RuneData; RuneData = GetRuneByIndex(iRuneId);
	
	Action fwdReturn;
	
	//==== [ Execute the rune pickup forward ] =====//
	Call_StartForward(g_fwdOnRunePickup);
	Call_PushCell(picker_client_index); // int client
	Call_PushCell(entity); // int entity
	Call_PushArray(RuneData, sizeof(RuneData)); // Rune runeStruct
	Call_PushCellRef(iRuneId); // int &runeId
	Call_PushCellRef(iRuneStar); // int &star
	Call_PushCellRef(iRuneLevel); // int &level
	Call_PushCell(PickupBlockReason); // RunePickupBlockReasons blockReason
	
	int iError = Call_Finish(fwdReturn);
	
	// Check for forward failure
	if (iError != SP_ERROR_NONE)
	{
		ThrowNativeError(iError, "Global Forward Failed - Error: %d", iError);
		return Plugin_Continue;
	}
	
	// If the forward return is higher then Plugin_Handled, stop the further actions
	if (fwdReturn >= Plugin_Handled)
	{
		PickupBlockReason = RUNE_PICKUP_BLOCK_FORWARD;
	}
	
	// If the rune pickup should be blocked by the plugin, block it
	if (PickupBlockReason != RUNE_PICKUP_BLOCK_NONE)
	{
		switch (PickupBlockReason)
		{
			case RUNE_PICKUP_BLOCK_GUARD:
			{
				PrintCenterText(picker_client_index, " You can't pickup runes,\n unless all the prisoners are dead!");
			}
			case RUNE_PICKUP_BLOCK_CAPACITY:
			{
				PrintCenterText(picker_client_index, " <font color='#CC0000'>Your runes capacity is maxed out!</font>");
			}
		}
		
		return Plugin_Continue;
	}
	
	// Push the current picked up rune to the runes queue
	g_ClientsData[picker_client_index].PickedRunes.PushString(szEntityName);
	
	// Add the rune to the client's inventory
	AddRuneToInventory(picker_client_index, iRuneId, iRuneStar, iRuneLevel, 1);
	
	// Create the rune pickup progress bar, if the client isn't in a middle of a rune upgrade
	if (g_ClientsData[picker_client_index].ShowUpgradeInfoTimer == INVALID_HANDLE)
	{
		CreateRunePickupTimer(picker_client_index);
	}
	
	// Destroy the entity
	AcceptEntityInput(entity, "Kill");
	
	// Write a log to the plugin log file
	JB_WriteLogLine("\"%L\" has picked up a \"%s\" %d star, level %d.", picker_client_index, RuneData.szRuneUnique, iRuneStar, iRuneLevel);
	
	return Plugin_Continue;
}

//================================[ Commands ]================================//

Action Command_SpawnRune(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Block the command access if the client isn't allowed
	if (!IsClientAuthorizedEx(client))
	{
		PrintToChat(client, "%s You do not have access to this command.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Display the command usage if there is no args specified
	if (args < 3)
	{
		PrintToChat(client, "%s Usage: \x04/spawnrune\x01 <rune unique> <star 1-6> <level 1-15> <showcase 1|0>", PREFIX);
		return Plugin_Handled;
	}
	
	char szRuneUnique[64], szCurrentArg[8];
	
	// Get the specified rune unique, and init the rune index
	GetCmdArg(1, szRuneUnique, sizeof(szRuneUnique));
	int iRuneId = GetRuneByUnique(szRuneUnique);
	
	if (iRuneId == -1 && !StrEqual(szRuneUnique, RANDOM_RUNE_UNIQUE))
	{
		PrintToChat(client, "%s Rune unique \"\x02%s\x01\" is not exists!", PREFIX_ERROR, szRuneUnique);
		return Plugin_Handled;
	}
	
	// Get the specified rune star
	GetCmdArg(2, szCurrentArg, sizeof(szCurrentArg));
	int iRuneStar = StringToInt(szCurrentArg);
	
	if (!(RuneStar_1 <= iRuneStar < RuneStar_Max) && iRuneStar)
	{
		PrintToChat(client, "%s Invalid specified rune star (\x02%s\x01). [\x04%d-%d\x01]", PREFIX_ERROR, szCurrentArg, RuneStar_1, RuneStar_Max - 1);
		return Plugin_Handled;
	}
	
	// Get the specified rune level
	GetCmdArg(3, szCurrentArg, sizeof(szCurrentArg));
	int iRuneLevel = StringToInt(szCurrentArg);
	
	if (!(RuneLevel_1 <= iRuneLevel < RuneLevel_Max) && iRuneLevel)
	{
		PrintToChat(client, "%s Invalid specified rune level (\x02%s\x01). [\x04%d-%d\x01]", PREFIX_ERROR, szCurrentArg, RuneLevel_1, RuneLevel_Max - 1);
		return Plugin_Handled;
	}
	
	// Initialize rune spawn position
	float fRunePosition[3];
	GetClientAimPosition(client, fRunePosition);
	
	// If the specified rune unique is random, generate a random rune index
	iRuneId = StrEqual(szRuneUnique, RANDOM_RUNE_UNIQUE) ? GetRandomInt(0, g_RunesData.Length - 1) : iRuneId;
	
	// Spawn the rune entity box
	int iEntity = CreateRuneBox(fRunePosition, iRuneId, !iRuneStar ? GenerateRuneStar() : iRuneStar, !iRuneLevel ? GetRandomInt(1, RuneLevel_Max - 1) : iRuneLevel, false);
	
	GetCmdArg(4, szCurrentArg, sizeof(szCurrentArg));
	
	if (StringToInt(szCurrentArg) && iEntity != -1)
	{
		float origin[3];
		GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", origin);
		
		origin[2] += 30.0;
		
		TeleportEntity(iEntity, origin, NULL_VECTOR, NULL_VECTOR);
		
		RequestFrame(Frame_ShowCase, EntIndexToEntRef(iEntity));
	}
	
	// Write a log to the plugin log file
	JB_WriteLogLine("Admin \"%L\" has spawned a \"%s\" %d star, level %d.", client, GetRuneByIndex(iRuneId).szRuneUnique, iRuneStar, iRuneLevel);
	
	return Plugin_Handled;
}

public Action Command_AddRune(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Block the command access if the client isn't allowed
	if (!IsClientAuthorizedEx(client))
	{
		PrintToChat(client, "%s You do not have access to this command.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Display the command usage if there is no args specified
	if (args != 5)
	{
		PrintToChat(client, "%s Usage: \x04/addrune\x01 <name|#userid> <rune unique> <star 1-6> <level 1-15> <amount>", PREFIX);
		return Plugin_Handled;
	}
	
	char szRuneUnique[64], szCurrentArg[MAX_NAME_LENGTH];
	
	// Get the client index by the specified name/user id
	GetCmdArg(1, szCurrentArg, sizeof(szCurrentArg));
	int iTargetIndex = FindTarget(client, szCurrentArg, true, true);
	
	if (iTargetIndex == -1)
	{
		// Automated message
		return Plugin_Handled;
	}
	
	// Get the specified rune unique, and init the rune index
	GetCmdArg(2, szRuneUnique, sizeof(szRuneUnique));
	int iRuneId = GetRuneByUnique(szRuneUnique);
	
	if (iRuneId == -1)
	{
		PrintToChat(client, "%s Rune unique \"\x02%s\x01\" is not exists!", PREFIX_ERROR, szRuneUnique);
		return Plugin_Handled;
	}
	
	// Get the specified rune star
	GetCmdArg(3, szCurrentArg, sizeof(szCurrentArg));
	int iRuneStar = StringToInt(szCurrentArg);
	
	if (!(RuneStar_1 <= iRuneStar < RuneStar_Max))
	{
		PrintToChat(client, "%s Invalid specified rune star (\x02%s\x01). [\x04%d-%d\x01]", PREFIX_ERROR, szCurrentArg, RuneStar_1, RuneStar_Max - 1);
		return Plugin_Handled;
	}
	
	// Get the specified rune level
	GetCmdArg(4, szCurrentArg, sizeof(szCurrentArg));
	int iRuneLevel = StringToInt(szCurrentArg);
	
	if (!(RuneLevel_1 <= iRuneLevel < RuneLevel_Max))
	{
		PrintToChat(client, "%s Invalid specified rune level (\x02%s\x01). [\x04%d-%d\x01]", PREFIX_ERROR, szCurrentArg, RuneLevel_1, RuneLevel_Max - 1);
		return Plugin_Handled;
	}
	
	// Get the specified rune add amount
	GetCmdArg(5, szCurrentArg, sizeof(szCurrentArg));
	int iAmount = StringToInt(szCurrentArg);
	
	if (g_ClientsData[client].RunesInventory.Length + iAmount > g_ClientsData[client].iRunesCapacity)
	{
		PrintToChat(client, "%s Prevented runes capacity overflow!", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	// Store the target rune data inside the memory
	AddRuneToInventory(iTargetIndex, iRuneId, iRuneStar, iRuneLevel, iAmount);
	
	// Notify client
	PrintToChat(client, "%s Successfully added \x02%s\x01 \x0C%d%s Level %d\x01 to \x04%N\x01 inventory! (\x03Amount: %d\x01)", PREFIX, szRuneUnique, iRuneStar, RUNE_STAR_SYMBOL, iRuneLevel, iTargetIndex, iAmount);
	
	// Write a log to the plugin log file
	JB_WriteLogLine("Admin \"%L\" has added a \"%s\" %d star, level %d to \"%L\" inventory. (Amount: %d)", client, szRuneUnique, iRuneStar, iRuneLevel, iTargetIndex, iAmount);
	
	return Plugin_Handled;
}

public Action Command_Runes(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (g_ClientsData[client].ShowUpgradeInfoTimer != INVALID_HANDLE)
	{
		PrintToChat(client, "%s Please wait until your \x0Frune upgrade\x01 will end.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (args > 0)
	{
		char arg_name[MAX_NAME_LENGTH];
		GetCmdArgString(arg_name, sizeof(arg_name));
		int target_index = FindTarget(client, arg_name, true, false);
		
		if (target_index == -1)
		{
			// Automated message
			return Plugin_Handled;
		}
		
		ShowPersonalRunesMenu(client, target_index);
	}
	else
	{
		ShowRunesMainMenu(client);
	}
	
	return Plugin_Handled;
}

//================================[ Natives & Forwards ]================================//

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("JB_IsRunesStarted", Native_IsRunesStarted);
	CreateNative("JB_CreateRune", Native_CreateRune);
	CreateNative("JB_FindRune", Native_FindRune);
	CreateNative("JB_GetRuneData", Native_GetRuneData);
	CreateNative("JB_GetRunesAmount", Native_GetRunesAmount);
	CreateNative("JB_GetRuneBenefitStats", Native_GetRuneBenefitStats);
	CreateNative("JB_GetClientRuneData", Native_GetClientRuneData);
	CreateNative("JB_SetClientRuneData", Native_SetClientRuneData);
	CreateNative("JB_GetClientEquippedRune", Native_GetClientEquippedRune);
	CreateNative("JB_AddClientRune", Native_AddClientRune);
	CreateNative("JB_RemoveClientRune", Native_RemoveClientRune);
	CreateNative("JB_IsClientHasRune", Native_IsClientHasRune);
	CreateNative("JB_GetClientRunesCapacity", Native_GetClientRunesCapacity);
	CreateNative("JB_GetClientRunesAmount", Native_GetClientRunesAmount);
	CreateNative("JB_GetClientOwnedRunes", Native_GetClientOwnedRunes);
	CreateNative("JB_PerformRuneLevelUpgrade", Native_PerformRuneLevelUpgrade);
	CreateNative("JB_ToggleRune", Native_ToggleRune);
	CreateNative("JB_GetClientRuneInventory", Native_GetClientRuneInventory);
	
	g_fwdOnRunesStarted = new GlobalForward("JB_OnRunesStarted", ET_Ignore);
	g_fwdOnRuneSpawn = new GlobalForward("JB_OnRuneSpawn", ET_Event, Param_Cell, Param_Array, Param_CellByRef, Param_Array, Param_CellByRef, Param_CellByRef, Param_Cell);
	g_fwdOnRunePickup = new GlobalForward("JB_OnRunePickup", ET_Event, Param_Cell, Param_Cell, Param_Array, Param_CellByRef, Param_CellByRef, Param_CellByRef, Param_Cell);
	g_fwdOnRuneLevelUpgrade = new GlobalForward("JB_OnRuneLevelUpgrade", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_CellByRef);
	g_fwdOnRuneEquipChange = new GlobalForward("JB_OnRuneEquipChange", ET_Event, Param_Cell, Param_Cell, Param_CellByRef, Param_CellByRef, Param_CellByRef);
	g_fwdOnRunesCapacityExpand = new GlobalForward("JB_OnRunesCapacityExpand", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnRuneSell = new GlobalForward("JB_OnRuneSell", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	g_fwdOnRuneToggle = new GlobalForward("JB_OnRuneToggle", ET_Event, Param_Cell, Param_Cell);
	
	RegPluginLibrary("JB_RunesSystem");
	return APLRes_Success;
}

public int Native_IsRunesStarted(Handle plugin, int numParams)
{
	return g_Database != null;
}

public int Native_CreateRune(Handle plugin, int numParams)
{
	Rune RuneData;
	GetNativeString(1, RuneData.szRuneUnique, sizeof(RuneData.szRuneUnique));
	
	// Initialize the rune id by the specified rune unique
	int rune_id = GetRuneByUnique(RuneData.szRuneUnique);
	if (rune_id != -1)
	{
		return rune_id;
	}
	
	GetNativeString(2, RuneData.szRuneName, sizeof(RuneData.szRuneName));
	GetNativeString(3, RuneData.szRuneDesc, sizeof(RuneData.szRuneDesc));
	GetNativeString(4, RuneData.szRuneSymbol, sizeof(RuneData.szRuneSymbol));
	
	RuneData.RuneBenefits = view_as<ArrayList>(CloneHandle(GetNativeCell(5)));
	
	GetNativeString(6, RuneData.szRuneBenefitText, sizeof(RuneData.szRuneBenefitText));
	
	// Push the rune struct to the last array in the array list, and return the index
	return g_RunesData.PushArray(RuneData);
}

public int Native_FindRune(Handle plugin, int numParams)
{
	char szRuneUnique[64];
	GetNativeString(1, szRuneUnique, sizeof(szRuneUnique));
	
	// Search and return the rune index by the given unique
	return GetRuneByUnique(szRuneUnique);
}

public int Native_GetRuneData(Handle plugin, int numParams)
{
	// Get and verify the the rune index
	int rune_index = GetNativeCell(1);
	
	if (!(0 <= rune_index < g_RunesData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune index (Got: %d, Max: %d)", rune_index, g_RunesData.Length);
	}
	
	// Initialize the rune data and set it in the native param
	Rune RuneData; RuneData = GetRuneByIndex(rune_index);
	
	SetNativeArray(2, RuneData, sizeof(RuneData));
	
	return 0;
}

public int Native_GetRunesAmount(Handle plugin, int numParams)
{
	return g_RunesData.Length;
}

public any Native_GetRuneBenefitStats(Handle plugin, int numParams)
{
	// Get and verify the the rune index
	int rune_index = GetNativeCell(1);
	
	if (!(0 <= rune_index < g_RunesData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune index (Got: %d, Max: %d)", rune_index, g_RunesData.Length);
	}
	
	// Get and verify the the rune star
	int rune_star = GetNativeCell(2);
	
	if (!(RuneStar_1 <= rune_star < RuneStar_Max))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune star (Got: %d, Max: %d)", rune_star, RuneStar_Max - 1);
	}
	
	// Get and verify the the rune star
	int rune_level = GetNativeCell(3);
	
	if (!(RuneLevel_1 <= rune_level < RuneLevel_Max))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune level (Got: %d, Max: %d)", rune_level, RuneLevel_Max - 1);
	}
	
	return GetRuneBenefit(rune_index, rune_star, rune_level);
}

public int Native_GetClientRuneData(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the the client rune index
	int client_rune_index = GetNativeCell(2);
	
	if (!(0 <= client_rune_index < g_ClientsData[client].RunesInventory.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client rune index (Got: %d, Max: %d)", client_rune_index, g_ClientsData[client].RunesInventory.Length);
	}
	
	// Initialize the client rune data and set it in the native param
	ClientRune ClientRuneData;
	g_ClientsData[client].GetClientRuneByIndex(client_rune_index, ClientRuneData);
	
	SetNativeArray(3, ClientRuneData, sizeof(ClientRuneData));
	
	return 0;
}

public int Native_SetClientRuneData(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the the client rune index
	int client_rune_index = GetNativeCell(2);
	
	if (!(0 <= client_rune_index < g_ClientsData[client].RunesInventory.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client rune index (Got: %d, Max: %d)", client_rune_index, g_ClientsData[client].RunesInventory.Length);
	}
	
	// Initialize the client rune data and set replicate it to the specified client rune index
	ClientRune ClientRuneData;
	GetNativeArray(3, ClientRuneData, sizeof(ClientRuneData));
	
	// Update the client rune data
	g_ClientsData[client].RunesInventory.SetArray(client_rune_index, ClientRuneData);
	
	return 0;
}

public int Native_GetClientEquippedRune(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the the rune index
	int rune_index = GetNativeCell(2);
	
	if (!(0 <= rune_index < g_RunesData.Length)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune index (Got: %d, Max: %d)", rune_index, g_RunesData.Length);
	}
	
	// Return the equipped rune by the specified index
	return GetEquippedRune(client, rune_index);
}

public int Native_AddClientRune(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the the rune index
	int rune_index = GetNativeCell(2);
	
	if (!(0 <= rune_index < g_RunesData.Length) && rune_index != -1) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune index (Got: %d, Max: %d)", rune_index, g_RunesData.Length);
	}
	
	// Get and verify the rune star
	int rune_star = GetNativeCell(3);
	
	if (!(RuneStar_1 <= rune_star < RuneStar_Max) && rune_star)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune star (Got: %d, Max: %d)", rune_star, RuneStar_Max - 1);
	}
	
	// Get and verify the rune level
	int rune_level = GetNativeCell(4);
	
	if (!(RuneLevel_1 <= rune_level < RuneLevel_Max) && rune_level)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune star (Got: %d, Max: %d)", rune_level, RuneLevel_Max - 1);
	}
	
	// Get and verify the amount of times to add the rune
	int add_times = GetNativeCell(5);
	
	if (add_times <= 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune add amount, Must be greater than 0. (Got: %d)", add_times);
	}
	
	// Make sure the client has enough inventory space
	if (g_ClientsData[client].RunesInventory.Length + add_times > g_ClientsData[client].iRunesCapacity)
	{
		// Abort the situation
		return false;
	}
	
	// Store the client rune data inside the memory
	AddRuneToInventory(client, rune_index, rune_star, rune_level, add_times, plugin);
	
	// Return success!
	return true;
}

public int Native_RemoveClientRune(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the the client rune index
	int client_rune_index = GetNativeCell(2);
	
	if (!(0 <= client_rune_index < g_ClientsData[client].RunesInventory.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client rune index (Got: %d, Max: %d)", client_rune_index, g_ClientsData[client].RunesInventory.Length);
	}
	
	// Initialize the client rune data for the log
	ClientRune ClientRuneData;
	g_ClientsData[client].GetClientRuneByIndex(client_rune_index, ClientRuneData);
	
	// Remove the client rune from the mysql database
	SQL_RemoveClientRune(client, client_rune_index);
	
	// Erase the client rune index from the runes inventory array list
	g_ClientsData[client].RunesInventory.Erase(client_rune_index);
	
	// Write a log to the plugin log file
	char plugin_name[64];
	GetPluginFilename(plugin, plugin_name, sizeof(plugin_name));
	JB_WriteLogLine("Rune \"%s\" %d star level %d has been removed, from \"%L\" inventory by plugin \"%s\".", GetRuneByIndex(ClientRuneData.RuneId).szRuneUnique, ClientRuneData.RuneStar, ClientRuneData.RuneLevel, client, plugin_name);
	
	return 0;
}

public int Native_IsClientHasRune(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the the rune index
	int rune_index = GetNativeCell(2);
	
	if (!(0 <= rune_index < g_RunesData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune index (Got: %d, Max: %d)", rune_index, g_RunesData.Length);
	}
	
	// Get and verify the rune star
	int rune_star = GetNativeCell(3);
	
	if (!(RuneStar_1 <= rune_star < RuneStar_Max) && rune_star != -1)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune star (Got: %d, Max: %d)", rune_star, RuneStar_Max - 1);
	}
	
	// Get and verify the rune level
	int rune_level = GetNativeCell(4);
	
	if (!(RuneLevel_1 <= rune_level < RuneLevel_Max) && rune_level != -1)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune star (Got: %d, Max: %d)", rune_level, RuneLevel_Max - 1);
	}
	
	ClientRune CurrentClientRuneData;
	
	for (int iCurrentIndex = 0; iCurrentIndex < g_ClientsData[client].RunesInventory.Length; iCurrentIndex++)
	{
		// Get the client rune data from the current index
		g_ClientsData[client].GetClientRuneByIndex(iCurrentIndex, CurrentClientRuneData);
		
		if (CurrentClientRuneData.RuneId == rune_index)
		{
			if ((rune_star != -1 && rune_level == -1 && CurrentClientRuneData.RuneStar == rune_star)
				 || (rune_level != -1 && rune_star == -1 && CurrentClientRuneData.RuneLevel == rune_level)
				 || (rune_level != -1 && rune_star != -1 && CurrentClientRuneData.RuneStar == rune_star && CurrentClientRuneData.RuneLevel == rune_level)
				 || (rune_level == -1 && rune_star == -1))
			{
				return iCurrentIndex;
			}
		}
	}
	
	return -1;
}

public int Native_GetClientRunesCapacity(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	return g_ClientsData[client].iRunesCapacity;
}

public int Native_GetClientRunesAmount(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	return g_ClientsData[client].RunesInventory.Length;
}

public int Native_GetClientOwnedRunes(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the the rune index
	int rune_index = GetNativeCell(2);
	
	if (!(0 <= rune_index < g_RunesData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune index (Got: %d, Max: %d)", rune_index, g_RunesData.Length);
	}
	
	// Get and verify the rune star
	int rune_star = GetNativeCell(4);
	
	if (!(RuneStar_1 <= rune_star < RuneStar_Max) && rune_star != -1)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune star (Got: %d, Max: %d)", rune_star, RuneStar_Max - 1);
	}
	
	// Get and verify the rune level
	int rune_level = GetNativeCell(5);
	
	if (!(RuneLevel_1 <= rune_level < RuneLevel_Max) && rune_level != -1)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune star (Got: %d, Max: %d)", rune_level, RuneLevel_Max - 1);
	}
	
	return GetOwnedRunesAmount(client, rune_index, GetNativeCell(3), rune_star, rune_level);
}

public int Native_PerformRuneLevelUpgrade(Handle plugin, int numParams)
{
	// Get and verify the the client index
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	// Get and verify the the client rune index
	int client_rune_index = GetNativeCell(2);
	
	if (!(0 <= client_rune_index < g_ClientsData[client].RunesInventory.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client rune index (Got: %d, Max: %d)", client_rune_index, g_ClientsData[client].RunesInventory.Length);
	}
	
	// Initialize the client rune data by the given client rune index
	ClientRune ClientRuneData;
	g_ClientsData[client].GetClientRuneByIndex(client_rune_index, ClientRuneData);
	
	// Make sure the rune level upgrade is available
	if (ClientRuneData.RuneLevel >= RuneLevel_Max - 1)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Unable to level upgrade client rune index %d. (Level is already maxed)", client_rune_index);
	}
	
	// Get and verify the the rune upgrade success chances
	int success_chances = GetNativeCell(3);
	
	if (!(-1 <= success_chances <= 100))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid success chances (Got: %d)", success_chances);
	}
	
	if (success_chances == -1)
	{
		success_chances = CalculateUpgradeSuccessRate(ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
	}
	
	bool replicate_forward = GetNativeCell(4);
	
	// Decides whether or not the rune level upgrade has succeeded
	bool bIsSucceed = GetRandomInt(0, 100) <= success_chances;
	
	if (replicate_forward)
	{
		bool fwdReturn;
		
		//==== [ Execute the rune level upgrade forward ] =====//
		Call_StartForward(g_fwdOnRuneLevelUpgrade);
		Call_PushCell(client);
		Call_PushCell(client_rune_index);
		Call_PushCell(ClientRuneData.RuneLevel + 1);
		Call_PushCellRef(bIsSucceed);
		
		int iError = Call_Finish(fwdReturn);
		
		// Check for forward failure
		if (iError != SP_ERROR_NONE)
		{
			return ThrowNativeError(iError, "Rune Level Upgrade Forward Failed - Error: %d", iError);
		}
		
		// If the forward return is true, stop the further actions
		if (fwdReturn)
		{
			// Show the client the rune detail menu
			ShowRuneDetailMenu(client, client_rune_index);
			
			// Don't Continue
			return false;
		}
	}
	
	// Write a log to the plugin log file
	char file_name[64];
	GetPluginFilename(plugin, file_name, sizeof(file_name));
	JB_WriteLogLine("\"%L\" has upgraded his \"%s\" %d star level %d, to level %d. (Result: %s) [By Plugin: %s]", client, GetRuneByIndex(ClientRuneData.RuneId).szRuneUnique, ClientRuneData.RuneStar, ClientRuneData.RuneLevel, ClientRuneData.RuneLevel + 1, bIsSucceed ? "Success" : "Failure", file_name);
	
	// If the upgrade has succeed update the client's runes inventory
	if (bIsSucceed)
	{
		g_ClientsData[client].RunesInventory.Set(client_rune_index, ClientRuneData.RuneLevel + 1, ClientRune::RuneLevel);
		SQL_UpdateRuneLevel(client, client_rune_index);
	}
	
	// Required to fix the invisible hint text bug
	PrintCenterText(client, "");
	
	// Shrink the varribles into a datapack, and create the rune upgrade information timer
	DataPack dp;
	
	g_ClientsData[client].iRuneUpgradeProgress = RoundToFloor(RUNE_UPGRADE_PROGRESS_INTERVAL * 55.0);
	g_ClientsData[client].ShowUpgradeInfoTimer = CreateDataTimer(RUNE_UPGRADE_PROGRESS_INTERVAL, Timer_ShowRuneUpgradeInfo, dp, TIMER_REPEAT);
	
	dp.WriteCell(GetClientSerial(client));
	dp.WriteCell(client_rune_index);
	dp.WriteCell(bIsSucceed);
	
	// Play the power up upgrade sound effect
	EmitSoundToClient(client, UPGRADE_POWERUP_SOUND);
	
	return bIsSucceed;
}

public int Native_ToggleRune(Handle plugin, int numParams)
{
	// Get and verify the rune index
	int rune_index = GetNativeCell(1);
	
	if (!(0 <= rune_index < g_RunesData.Length))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid rune index (Get: %d | Max: %d)", rune_index, g_RunesData.Length);
	}
	
	bool rune_toggle_mode = GetNativeCell(2);
	
	//==== [ Execute the rune toggle forward ] =====//
	Call_StartForward(g_fwdOnRuneToggle);
	Call_PushCell(rune_index); // int runeIndex
	Call_PushCell(rune_toggle_mode); // bool toggleMode
	Call_Finish();
	
	return true;
}

any Native_GetClientRuneInventory(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (!(1 <= client <= MaxClients))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	
	if (!IsClientConnected(client))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	
	return view_as<ArrayList>(CloneHandle(g_ClientsData[client].RunesInventory, plugin));
}

//================================[ Menus ]================================//

void ShowRunesMainMenu(int client)
{
	Menu menu = new Menu(Handler_RunesMain);
	menu.SetTitle("%s Runes System - Main Menu\n ", PREFIX_MENU);
	
	bool is_garbage_collector_purchased = IsGarbageCollectorPurchased(client);
	
	menu.AddItem("", "Personal Runes");
	menu.AddItem("", is_garbage_collector_purchased ? "Garbage Collector" : "Garbage Collector [Purchasable through the shop]", is_garbage_collector_purchased ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("", "Capacity Expansion\n ");
	
	menu.AddItem("", "╭Auction House\n    ╰┄Marketplace where you can sell your personal runes to everyone!");
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_RunesMain(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		switch (item_position)
		{
			case 0:
			{
				// Display the personal runes menu
				ShowPersonalRunesMenu(client);
			}
			case 1:
			{
				// Display the garbage collector menu
				ShowGarbageCollectorMenu(client);
			}
			case 2:
			{
				// Display the runes capacity expansion menu
				ShowCapacityExpansionMenu(client);
			}
			case 3:
			{
				ClientCommand(client, "sm_ah");
			}
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowPersonalRunesMenu(int client, int client_inventory = 0)
{
	if (!client_inventory)
	{
		client_inventory = client;
	}
	
	char item_display[64], item_info[4];
	
	Menu menu = new Menu(Handler_PersonalRunes);
	menu.SetTitle("%s Runes System - Personal Runes \n• Capacity: [%d/%d]\n ", PREFIX_MENU, g_ClientsData[client_inventory].RunesInventory.Length, g_ClientsData[client_inventory].iRunesCapacity);
	
	ClientRune ClientRuneData;
	
	// Sort the client's personal runes by the rune star, level, and equipped runes. See SortADTRunesInventory for the preferences
	g_ClientsData[client_inventory].RunesInventory.SortCustom(SortADTRunesInventory);
	
	for (int current_client_rune = 0; current_client_rune < g_ClientsData[client_inventory].RunesInventory.Length; current_client_rune++)
	{
		// Get the client rune data from the current index
		g_ClientsData[client_inventory].GetClientRuneByIndex(current_client_rune, ClientRuneData);
		
		// Do not insert garbage collected runes
		if (ClientRuneData.IsInGarbageCollector)
		{
			continue;
		}
		
		// Convert the current index into a string, required for sending through the menu item info
		IntToString(current_client_rune, item_info, sizeof(item_info));
		
		// Format & add the menu item to the menu
		FormatEx(item_display, sizeof(item_display), "%s | %d%s(Level %d)%s", GetRuneByIndex(ClientRuneData.RuneId).szRuneName, ClientRuneData.RuneStar, RUNE_STAR_SYMBOL, ClientRuneData.RuneLevel, ClientRuneData.IsRuneEquipped ? " [Equipped]" : "");
		menu.AddItem(item_info, item_display, client == client_inventory ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	
	// If there is no items inside the menu, add an extra menu item
	if (!menu.ItemCount)
	{
		// Initialize the inventory owner name
		char client_name[MAX_NAME_LENGTH];
		GetClientName(client_inventory, client_name, sizeof(client_name));
		
		// Format & add the item display buffer into the menu
		Format(item_display, sizeof(item_display), "%s don't have any runes.", client == client_inventory ? "You" : client_name);
		menu.AddItem("", item_display, ITEMDRAW_DISABLED);
	}
	
	if (client == client_inventory)
	{
		// Set the exit back button as true, and fix the back button gap
		menu.ExitBackButton = true;
		JB_FixMenuGap(menu);
	}
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

// 1 = Index 2 before index 1
// 0 = both equal
// -1 = Index 1 before index 2
public int SortADTRunesInventory(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList sorter = view_as<ArrayList>(array);
	
	ClientRune Struct1; sorter.GetArray(index1, Struct1, sizeof(Struct1));
	ClientRune Struct2; sorter.GetArray(index2, Struct2, sizeof(Struct2));
	
	// First preference is equipped runes
	if (Struct1.IsRuneEquipped != Struct2.IsRuneEquipped)
	{
		return (Struct1.IsRuneEquipped) ? -1 : 1;
	}
	
	// Second preference is the rune's star
	if (Struct1.RuneStar != Struct2.RuneStar)
	{
		return (Struct1.RuneStar > Struct2.RuneStar) ? -1 : 1;
	}
	
	// Third preference is the rune's level
	if (Struct1.RuneLevel != Struct2.RuneLevel)
	{
		return (Struct1.RuneLevel > Struct2.RuneLevel) ? -1 : 1;
	}
	
	return 0;
}

public int Handler_PersonalRunes(Menu menu, MenuAction action, int client, int item_position)
{
	if (action == MenuAction_Select)
	{
		char item_info[4];
		menu.GetItem(item_position, item_info, sizeof(item_info));
		
		ShowRuneDetailMenu(client, StringToInt(item_info)/* = Client rune index*/);
	}
	else if (action == MenuAction_Cancel && item_position == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		ShowRunesMainMenu(client);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowGarbageCollectorMenu(int client)
{
	char item_display[64], item_info[4];
	
	Menu menu = new Menu(Handler_GarbageCollector);
	menu.SetTitle("%s Runes System - Garbage Collector \n• Capacity: [%d/%d]\n ", PREFIX_MENU, g_ClientsData[client].RunesInventory.Length, g_ClientsData[client].iRunesCapacity);
	
	menu.AddItem("", "Manage Filters");
	
	menu.AddItem("", "Empty Collection\n ", GetGarbageCollectionAmount(client) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	ClientRune ClientRuneData;
	
	for (int current_client_rune = 0; current_client_rune < g_ClientsData[client].RunesInventory.Length; current_client_rune++)
	{
		// Get the client rune data from the current index
		g_ClientsData[client].GetClientRuneByIndex(current_client_rune, ClientRuneData);
		
		// Do not insert not garbage collected runes
		if (!ClientRuneData.IsInGarbageCollector)
		{
			continue;
		}
		
		// Convert the current index into a string, required for sending through the menu item info
		IntToString(current_client_rune, item_info, sizeof(item_info));
		
		// Format & add the menu item to the menu
		FormatEx(item_display, sizeof(item_display), "%s | %d%s(Level %d)%s", GetRuneByIndex(ClientRuneData.RuneId).szRuneName, ClientRuneData.RuneStar, RUNE_STAR_SYMBOL, ClientRuneData.RuneLevel, ClientRuneData.IsRuneEquipped ? " [Equipped]" : "");
		menu.AddItem(item_info, item_display);
	}
	
	// If there is no items inside the garbage collector, add an extra notify menu item
	if (menu.ItemCount == 2)
	{
		menu.AddItem("", "Your garbage collector is empty.", ITEMDRAW_DISABLED);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_GarbageCollector(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		switch (item_position)
		{
			case 0:
			{
				ShowFiltersManagementMenu(client);
			}
			
			case 1:
			{
				// Play the 'empty collection' sound effect
				ClientCommand(client, "play survival/turret_takesdamage_0%d", GetRandomInt(1, 3));
				
				int total_profit;
				
				ClientRune ClientRuneData;
				
				// Loop through all the client runes inside the garbage collector, and sell them
				for (int current_client_rune = 0; current_client_rune < g_ClientsData[client].RunesInventory.Length; current_client_rune++)
				{
					g_ClientsData[client].GetClientRuneByIndex(current_client_rune, ClientRuneData);
					
					if (ClientRuneData.IsInGarbageCollector)
					{
						total_profit += PerformClientRuneSell(client, current_client_rune--);
					}
				}
				
				ShowGarbageCollectorMenu(client);
				
				if (!total_profit)
				{
					return 0;
				}
				
				// Notify the client
				PrintToChat(client, "%s You've \x09emptied\x01 your \x02Garbage Collector\x01 and claimed \x10%s\x01 credits!", PREFIX, JB_AddCommas(total_profit));
				
				// Write a log to the plugin log file
				JB_WriteLogLine("\"%L\" has emptied his garbage collector, and recieved %s credits.", client, JB_AddCommas(total_profit));
			}
			
			default:
			{
				// Initialize the seleceted rune by it's item info
				char item_info[4];
				menu.GetItem(item_position, item_info, sizeof(item_info));
				int client_rune_index = StringToInt(item_info);
				
				ClientRune ClientRuneData;
				g_ClientsData[client].GetClientRuneByIndex(client_rune_index, ClientRuneData);
				
				// Notify the client
				PrintToChat(client, "%s Returned \x02%s\x01 \x0C%d%s Level %d\x01 to your inventory!", PREFIX, GetRuneByIndex(ClientRuneData.RuneId).szRuneName, ClientRuneData.RuneStar, RUNE_STAR_SYMBOL, ClientRuneData.RuneLevel);
				
				// Play the sound effect
				ClientCommand(client, "play %s", RUTURNED_TO_INVENTORY_SOUND);
				
				g_ClientsData[client].RunesInventory.Set(client_rune_index, false, ClientRune::IsInGarbageCollector);
				
				SQL_UpdateRuneGarbageCollected(client, client_rune_index);
				
				ShowRuneDetailMenu(client, client_rune_index);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		ShowRunesMainMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowFiltersManagementMenu(int client)
{
	char item_display[64];
	Menu menu = new Menu(Handler_FiltersManagement);
	menu.SetTitle("%s Garbage Collector - Filters Management\n ", PREFIX_MENU);
	
	FormatEx(item_display, sizeof(item_display), "Collector: %s", g_ClientsData[client].GarbageCollectorData.is_enabled ? "Enabled" : "Disabled");
	menu.AddItem("", item_display);
	
	FormatEx(item_display, sizeof(item_display), "Up to star: %d%s", g_ClientsData[client].GarbageCollectorData.limited_star, RUNE_STAR_SYMBOL);
	menu.AddItem("", item_display);
	
	menu.AddItem("", "Included Runes");
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_FiltersManagement(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		switch (item_position)
		{
			case 0:
			{
				// Change the variable value to it'ss opposite
				g_ClientsData[client].GarbageCollectorData.is_enabled = !g_ClientsData[client].GarbageCollectorData.is_enabled;
				
				// Play the toggle sound effect
				ClientCommand(client, "play %s", g_ClientsData[client].GarbageCollectorData.is_enabled ? "items/nvg_on.wav" : "items/nvg_off.wav");
				
				// Display the same menu again
				ShowFiltersManagementMenu(client);
			}
			case 1:
			{
				// Increase the limiting star over and over until it reach the max star available
				g_ClientsData[client].GarbageCollectorData.limited_star = ++g_ClientsData[client].GarbageCollectorData.limited_star % RuneStar_Max ? g_ClientsData[client].GarbageCollectorData.limited_star : RuneStar_1;
				
				// Display the same menu again
				ShowFiltersManagementMenu(client);
			}
			case 2:
			{
				// Display the included runes filter menu
				ShowIncludedRunesMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		ShowGarbageCollectorMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowIncludedRunesMenu(int client)
{
	char item_display[64];
	Menu menu = new Menu(Handler_IncludedRunes);
	menu.SetTitle("%s Garbage Collector - Included Runes\n ", PREFIX_MENU);
	
	Rune RuneData;
	
	for (int current_rune = 0; current_rune < g_RunesData.Length; current_rune++)
	{
		RuneData = GetRuneByIndex(current_rune);
		
		FormatEx(item_display, sizeof(item_display), "%s [%s]", RuneData.szRuneName, (g_ClientsData[client].GarbageCollectorData.included_runes_bits & (1 << current_rune)) ? "✔" : "✖");
		menu.AddItem("", item_display);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_IncludedRunes(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, rune_index = param2;
		
		int rune_bit = (1 << rune_index);
		
		if (g_ClientsData[client].GarbageCollectorData.included_runes_bits & rune_bit)
		{
			g_ClientsData[client].GarbageCollectorData.included_runes_bits &= ~rune_bit;
		}
		else
		{
			g_ClientsData[client].GarbageCollectorData.included_runes_bits |= rune_bit;
		}
		
		ShowIncludedRunesMenu(client);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		ShowFiltersManagementMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowCapacityExpansionMenu(int client)
{
	char item_display[64];
	Menu menu = new Menu(Handler_CapacityExpansion);
	menu.SetTitle("%s Runes System - Capacity Expansion\n ", PREFIX_MENU);
	
	// Loop through all the runes capacity expantions and add them into the menu
	for (int current_expantion = 0, current_expantion_price; current_expantion < sizeof(g_iCapacityTiers); current_expantion++)
	{
		// Initialize the current expantion price
		current_expantion_price = CalculateExpantionPrice(client, current_expantion);
		
		// Format the item display buffer and insert the item into the menu
		Format(item_display, sizeof(item_display), "%s Credits", JB_AddCommas(current_expantion_price));
		Format(item_display, sizeof(item_display), "Expand To Tier %d (%d Slots) [%s]", current_expantion + 1, g_iCapacityTiers[current_expantion], g_ClientsData[client].iRunesCapacity >= g_iCapacityTiers[current_expantion] ? "Purchased" : item_display);
		menu.AddItem("", item_display, g_ClientsData[client].iRunesCapacity < g_iCapacityTiers[current_expantion] && Shop_GetClientCredits(client) >= current_expantion_price ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_CapacityExpansion(Menu menu, MenuAction action, int client, int item_position)
{
	if (action == MenuAction_Select)
	{
		int expantion_index = item_position;
		
		// Initialize the current expantion price
		int expantion_price = CalculateExpantionPrice(client, expantion_index);
		
		int client_credits = Shop_GetClientCredits(client);
		
		// Make sure the client has enough shop credits for the expantion
		if (client_credits < expantion_price)
		{
			PrintToChat(client, "You don't have enough credits. (missing \x02%s\x01)", JB_AddCommas(expantion_price - client_credits));
			ShowRunesMainMenu(client);
			return 0;
		}
		
		//==== [ Execute the runes capacity expand forward ] =====//
		Call_StartForward(g_fwdOnRunesCapacityExpand);
		Call_PushCell(client);
		Call_PushCell(g_ClientsData[client].iRunesCapacity);
		Call_PushCell(g_iCapacityTiers[expantion_index]);
		Call_Finish();
		
		// Write a log to the plugin log file
		JB_WriteLogLine("\"%L\" has expanded his runes capacity to %d from %d, and paid %s credits.", client, g_iCapacityTiers[expantion_index], g_ClientsData[client].iRunesCapacity, JB_AddCommas(expantion_price));
		
		// Set the runes capacity value to the expantion value
		g_ClientsData[client].iRunesCapacity = g_iCapacityTiers[expantion_index];
		
		// Take the client's credits from the expantion cost
		Shop_TakeClientCredits(client, expantion_price, CREDITS_BY_BUY_OR_SELL);
		
		// Play the expantion sound effect
		ClientCommand(client, "play %s", CAPACITY_EXPANTION_SOUND);
		
		// Notify client
		PrintToChat(client, "%s You've expanded your \x02runes capacity\x01 to \x10%d\x01 for \x04%s\x01!", PREFIX, g_iCapacityTiers[expantion_index], JB_AddCommas(expantion_price));
		
		// Display the runes main menu
		ShowRunesMainMenu(client);
	}
	else if (action == MenuAction_Cancel && item_position == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		ShowRunesMainMenu(client);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowRuneDetailMenu(int client, int clientRuneIndex)
{
	char item_display[64], item_info[4];
	
	Rune RuneData;
	ClientRune ClientRuneData;
	
	// Get the client rune data from the specified index
	g_ClientsData[client].GetClientRuneByIndex(clientRuneIndex, ClientRuneData);
	RuneData = GetRuneByIndex(ClientRuneData.RuneId);
	
	Menu menu = new Menu(Handler_RuneDetail);
	menu.SetTitle("%s Runes System - %s %s Detail \n \n• %s \n• Star: %d%s \n• Level: %d\n• Benefit: %s\n ", PREFIX_MENU, 
		RuneData.szRuneSymbol, 
		RuneData.szRuneName, 
		RuneData.szRuneDesc, 
		ClientRuneData.RuneStar, 
		RUNE_STAR_SYMBOL, 
		ClientRuneData.RuneLevel, 
		GetRuneBenefitDisplay(ClientRuneData)
		);
	
	// Convert the current index into a string, required for sending through the menu item info
	IntToString(clientRuneIndex, item_info, sizeof(item_info));
	
	// Format & add the menu items to the menu
	menu.AddItem(item_info, ClientRuneData.IsRuneEquipped ? "Unequip" : "Equip");
	
	// Initialize the upgrade price with the specified rune stats
	int iUpgradePrice = CalculateRuneUpgradePrice(ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
	
	Format(item_display, sizeof(item_display), "Upgrade to level %d for %s credits", ClientRuneData.RuneLevel + 1, JB_AddCommas(iUpgradePrice));
	menu.AddItem("", ClientRuneData.RuneLevel != RuneLevel_Max - 1 ? item_display : "Rune is MAXED OUT!", (ClientRuneData.RuneLevel != RuneLevel_Max - 1) && Shop_GetClientCredits(client) >= iUpgradePrice ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	// Initialize the sell profit with the specified rune stats
	int iSellProfit = CalculateRuneSellProfit(ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
	
	Format(item_display, sizeof(item_display), "Sell for %s credits\n ", JB_AddCommas(iSellProfit));
	menu.AddItem("", ClientRuneData.RuneLevel <= g_cvMaxRuneLevelSell.IntValue ? item_display : "Rune level is too high for it to be sold!", ClientRuneData.RuneLevel <= g_cvMaxRuneLevelSell.IntValue ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	menu.AddItem("", "Send to Garbage Collection", ClientRuneData.RuneLevel <= g_cvMaxRuneLevelSell.IntValue && IsGarbageCollectorPurchased(client) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_RuneDetail(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		char item_info[4];
		menu.GetItem(0, item_info, sizeof(item_info));
		int iClientRuneIndex = StringToInt(item_info);
		
		ClientRune ClientRuneData;
		
		// Get the client rune data from the specified index
		g_ClientsData[client].GetClientRuneByIndex(iClientRuneIndex, ClientRuneData);
		
		switch (item_position)
		{
			case 0:
			{
				// Initialize the current equipped client rune index
				int iEquippedRuneIndex = GetEquippedRune(client, ClientRuneData.RuneId);
				
				bool bEquippedReplaced = iEquippedRuneIndex != -1 && !ClientRuneData.IsRuneEquipped;
				
				ClientRuneData.IsRuneEquipped = !ClientRuneData.IsRuneEquipped;
				
				bool fwdReturn;
				
				//==== [ Execute the rune equip change forward ] =====//
				Call_StartForward(g_fwdOnRuneEquipChange);
				Call_PushCell(client);
				Call_PushCell(iClientRuneIndex);
				Call_PushCellRef(ClientRuneData.IsRuneEquipped);
				Call_PushCellRef(bEquippedReplaced);
				
				int iError = Call_Finish(fwdReturn);
				
				// Check for forward failure
				if (iError != SP_ERROR_NONE)
				{
					ThrowNativeError(iError, "Rune Equip Change Forward Failed - Error: %d", iError);
					return 0;
				}
				
				// If the forward return is true, stop the further actions
				if (fwdReturn)
				{
					// Show the client the rune detail menu
					ShowRuneDetailMenu(client, iClientRuneIndex);
					
					// Don't Continue
					return 0;
				}
				
				// Check for rune equip cooldown
				if (GetGameTime() < g_ClientsData[client].fNextEquipChange)
				{
					// Notify client
					PrintToChat(client, "%s Please wait \x04%.1f\x01 more seconds before changing the rune equip state again.", PREFIX, g_ClientsData[client].fNextEquipChange - GetGameTime());
					
					// Show the client the rune detail menu
					ShowRuneDetailMenu(client, iClientRuneIndex);
					
					return 0;
				}
				
				ClientRuneData.IsRuneEquipped = !ClientRuneData.IsRuneEquipped;
				
				ClientRune EquippedRuneData;
				
				if (iEquippedRuneIndex != -1 && iEquippedRuneIndex != iClientRuneIndex)
				{
					g_ClientsData[client].GetClientRuneByIndex(iEquippedRuneIndex, EquippedRuneData);
					
					if (EquippedRuneData.IsRuneEquipped)
					{
						// Set the rune equip state to false
						g_ClientsData[client].RunesInventory.Set(iEquippedRuneIndex, false, ClientRune::IsRuneEquipped);
						
						// Update the other equipped rune in mysql
						SQL_UpdateRuneEquipState(client, iEquippedRuneIndex);
					}
				}
				
				// Swtich the local variable to its opposite value
				ClientRuneData.IsRuneEquipped = !ClientRuneData.IsRuneEquipped;
				
				// Update the value inside the client inventory arraylist
				g_ClientsData[client].RunesInventory.Set(iClientRuneIndex, ClientRuneData.IsRuneEquipped, ClientRune::IsRuneEquipped);
				
				// Show the client the rune detail menu
				ShowRuneDetailMenu(client, iClientRuneIndex);
				
				// Update the rune equip state in mysql
				SQL_UpdateRuneEquipState(client, iClientRuneIndex);
				
				// Apply the equip change cooldown
				g_ClientsData[client].fNextEquipChange = GetGameTime() + g_cvRuneEquipCooldown.FloatValue;
				
				// Notify client
				char szMessage[64];
				
				if (bEquippedReplaced)
				{
					Format(szMessage, sizeof(szMessage), ", instead of \x02%s\x01 \x0C%d%s \x10[Level %d]\x01!", GetRuneByIndex(EquippedRuneData.RuneId).szRuneName, EquippedRuneData.RuneStar, RUNE_STAR_SYMBOL, EquippedRuneData.RuneLevel);
				}
				
				PrintToChat(client, "%s You've %s\x01 \x02%s\x01 \x0C%d%s \x10[Level %d]\x01%s", PREFIX, ClientRuneData.IsRuneEquipped ? "\x04✔ Equipped" : "\x02✖ Unquipped", GetRuneByIndex(ClientRuneData.RuneId).szRuneName, ClientRuneData.RuneStar, RUNE_STAR_SYMBOL, ClientRuneData.RuneLevel, bEquippedReplaced ? szMessage : "!");
			}
			case 1:
			{
				// Initialize the upgrade price with the specified rune stats
				int iUpgradePrice = CalculateRuneUpgradePrice(ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
				
				// Make sure the client has enough shop credits for the upgrade
				if (Shop_GetClientCredits(client) < iUpgradePrice)
				{
					PrintToChat(client, "You don't have enough credits. (missing \x02%s\x01)", JB_AddCommas(iUpgradePrice - Shop_GetClientCredits(client)));
					ShowRuneDetailMenu(client, iClientRuneIndex);
					return 0;
				}
				
				ShowUpgradeAgreementMenu(client, iClientRuneIndex);
			}
			case 2:
			{
				ShowSoldAgreementMenu(client, iClientRuneIndex);
			}
			case 3:
			{
				g_ClientsData[client].RunesInventory.Set(iClientRuneIndex, true, ClientRune::IsInGarbageCollector);
				SQL_UpdateRuneGarbageCollected(client, iClientRuneIndex);
				
				if (ClientRuneData.IsRuneEquipped)
				{
					DataPack dp;
					CreateDataTimer(0.35, Timer_UpdateData, dp, TIMER_FLAG_NO_MAPCHANGE);
					dp.WriteCell(client);
					dp.WriteCell(iClientRuneIndex);
					dp.Reset();
				}
				
				// Notify the client
				PrintToChat(client, "%s Sent rune \x02%s\x01 \x0C%d%s Level %d\x01 to your garbage collection!", PREFIX, GetRuneByIndex(ClientRuneData.RuneId).szRuneName, ClientRuneData.RuneStar, RUNE_STAR_SYMBOL, ClientRuneData.RuneLevel);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		ShowPersonalRunesMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

Action Timer_UpdateData(Handle timer, DataPack dp)
{
	int client = dp.ReadCell();
	int client_rune_index = dp.ReadCell();
	
	g_ClientsData[client].RunesInventory.Set(client_rune_index, false, ClientRune::IsRuneEquipped);
	SQL_UpdateRuneEquipState(client, client_rune_index);
	
	return Plugin_Continue;
}

void ShowUpgradeAgreementMenu(int client, int clientRuneIndex)
{
	ClientRune ClientRuneData;
	
	// Get the client rune data from the specified index
	g_ClientsData[client].GetClientRuneByIndex(clientRuneIndex, ClientRuneData);
	
	// Initialize the upgrade price with the specified rune stats
	int iUpgradePrice = CalculateRuneUpgradePrice(ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
	
	char item_info[4];
	
	Menu menu = new Menu(Handler_UpgradeAgreement);
	menu.SetTitle("%s Are you sure you want to upgrade the rune? \n• Target Level: %d \n• Cost: %s credits\n ", PREFIX_MENU, ClientRuneData.RuneLevel + 1, JB_AddCommas(iUpgradePrice));
	
	IntToString(clientRuneIndex, item_info, sizeof(item_info));
	
	menu.AddItem(item_info, "No");
	menu.AddItem("", "Yes");
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_UpgradeAgreement(Menu menu, MenuAction action, int client, int itemNum)
{
	char item_info[4];
	menu.GetItem(0, item_info, sizeof(item_info));
	int iClientRuneIndex = StringToInt(item_info);
	
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				// Send the client back to the rune detail menu
				ShowRuneDetailMenu(client, iClientRuneIndex);
			}
			case 1:
			{
				ClientRune ClientRuneData;
				
				// Get the client rune data from the specified index
				g_ClientsData[client].GetClientRuneByIndex(iClientRuneIndex, ClientRuneData);
				
				// Initialize the upgrade price with the specified rune stats
				int iUpgradePrice = CalculateRuneUpgradePrice(ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
				
				// Make sure the client has enough shop credits for the upgrade
				if (Shop_GetClientCredits(client) < iUpgradePrice)
				{
					PrintToChat(client, "You don't have enough credits. (missing \x02%s\x01)", JB_AddCommas(iUpgradePrice - Shop_GetClientCredits(client)));
					ShowRuneDetailMenu(client, iClientRuneIndex);
					return 0;
				}
				
				// Take the client's credits from the upgrade cost
				Shop_TakeClientCredits(client, iUpgradePrice, CREDITS_BY_BUY_OR_SELL);
				
				// Decides whether or not the rune level upgrade has succeeded
				bool bIsSucceed = GetRandomInt(0, 100) <= CalculateUpgradeSuccessRate(ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
				
				bool fwdReturn;
				
				//==== [ Execute the rune level upgrade forward ] =====//
				Call_StartForward(g_fwdOnRuneLevelUpgrade);
				Call_PushCell(client);
				Call_PushCell(iClientRuneIndex);
				Call_PushCell(ClientRuneData.RuneLevel + 1);
				Call_PushCellRef(bIsSucceed);
				
				int iError = Call_Finish(fwdReturn);
				
				// Check for forward failure
				if (iError != SP_ERROR_NONE)
				{
					ThrowNativeError(iError, "Rune Level Upgrade Forward Failed - Error: %d", iError);
					return 0;
				}
				
				// If the forward return is true, stop the further actions
				if (fwdReturn)
				{
					// Show the client the rune detail menu
					ShowRuneDetailMenu(client, iClientRuneIndex);
					
					// Don't Continue
					return 0;
				}
				
				// Write a log to the plugin log file
				JB_WriteLogLine("\"%L\" has upgraded his \"%s\" %d star level %d, to level %d, paid %s credits. (Result: %s)", client, GetRuneByIndex(ClientRuneData.RuneId).szRuneUnique, ClientRuneData.RuneStar, ClientRuneData.RuneLevel, ClientRuneData.RuneLevel + 1, JB_AddCommas(iUpgradePrice), bIsSucceed ? "Success" : "Failure");
				
				// If the upgrade has succeed update the client's runes inventory
				if (bIsSucceed)
				{
					g_ClientsData[client].RunesInventory.Set(iClientRuneIndex, ClientRuneData.RuneLevel + 1, ClientRune::RuneLevel);
					SQL_UpdateRuneLevel(client, iClientRuneIndex);
				}
				
				// Required to fix the invisible hint text bug
				PrintCenterText(client, "");
				
				// Shrink the vars into a datapack, and create the rune upgrade information timer
				DataPack dp;
				
				g_ClientsData[client].iRuneUpgradeProgress = RoundToFloor(RUNE_UPGRADE_PROGRESS_INTERVAL * 55.0);
				g_ClientsData[client].ShowUpgradeInfoTimer = CreateDataTimer(RUNE_UPGRADE_PROGRESS_INTERVAL, Timer_ShowRuneUpgradeInfo, dp, TIMER_REPEAT);
				
				dp.WriteCell(GetClientSerial(client));
				dp.WriteCell(iClientRuneIndex);
				dp.WriteCell(bIsSucceed);
				
				// Play the power up upgrade sound effect
				EmitSoundToClient(client, UPGRADE_POWERUP_SOUND);
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		ShowRuneDetailMenu(client, iClientRuneIndex);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

void ShowSoldAgreementMenu(int client, int clientRuneIndex)
{
	ClientRune ClientRuneData;
	
	// Get the client rune data from the specified index
	g_ClientsData[client].GetClientRuneByIndex(clientRuneIndex, ClientRuneData);
	
	// Initialize the sell profit with the specified rune stats
	int iSellProfit = CalculateRuneSellProfit(ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
	
	char item_info[4];
	
	Menu menu = new Menu(Handler_SoldAgreement);
	menu.SetTitle("%s Are you sure you want to sell the rune? \n• Profit: %s credits?\n ", PREFIX_MENU, JB_AddCommas(iSellProfit));
	
	IntToString(clientRuneIndex, item_info, sizeof(item_info));
	
	menu.AddItem(item_info, "No");
	menu.AddItem("", "Yes");
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_SoldAgreement(Menu menu, MenuAction action, int client, int itemNum)
{
	char item_info[4];
	menu.GetItem(0, item_info, sizeof(item_info));
	int iClientRuneIndex = StringToInt(item_info);
	
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				// Send the client back to the rune detail menu
				ShowRuneDetailMenu(client, iClientRuneIndex);
			}
			case 1:
			{
				Rune RuneData;
				ClientRune ClientRuneData;
				
				// Get the client rune data from the specified index
				g_ClientsData[client].GetClientRuneByIndex(iClientRuneIndex, ClientRuneData);
				RuneData = GetRuneByIndex(ClientRuneData.RuneId);
				
				int iSellProfit;
				
				if ((iSellProfit = PerformClientRuneSell(client, iClientRuneIndex)))
				{
					// Notify the client
					PrintToChat(client, "%s You've sold your \x02%s\x01 \x0C[%d%s Level %d]\x01 for \x10%s\x01 credits!", PREFIX, 
						RuneData.szRuneName, 
						ClientRuneData.RuneStar, 
						RUNE_STAR_SYMBOL, 
						ClientRuneData.RuneLevel, 
						JB_AddCommas(iSellProfit)
						);
					
					// Write a log to the plugin log file
					JB_WriteLogLine("\"%L\" has sold his \"%s\" %d star level %d, and recieved %s credits.", client, RuneData.szRuneUnique, ClientRuneData.RuneStar, ClientRuneData.RuneLevel, JB_AddCommas(iSellProfit));
					
					// Show the personal runes menu after the rune has sold
					ShowPersonalRunesMenu(client);
				}
				else
				{
					// Show the client the rune detail menu
					ShowRuneDetailMenu(client, iClientRuneIndex);
				}
			}
		}
	}
	else if (action == MenuAction_Cancel && itemNum == MenuCancel_ExitBack)
	{
		// Show the last menu the client was at
		ShowRuneDetailMenu(client, iClientRuneIndex);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	
	return 0;
}

//================================[ Database ]================================//

public void JB_OnDatabaseConnected(Database db)
{
	delete g_Database;
	g_Database = view_as<Database>(CloneHandle(db));
	
	g_Database.Query(SQL_CheckForErrors, 
		"CREATE TABLE IF NOT EXISTS \ 
			`jb_runes_inventory` \
		( \
		     `id` INT NOT NULL AUTO_INCREMENT, \
		     `account_id` INT NOT NULL, \
		     `unique` VARCHAR(64) NOT NULL, \
		     `star` INT NOT NULL, \
		     `level` INT NOT NULL, \
		     `equipped` INT(1) NOT NULL, \
		     `garbage_collected` INT(1) NOT NULL, \
		     PRIMARY KEY(`id`))"
		);
	
	g_Database.Query(SQL_CheckForErrors, 
		"CREATE TABLE IF NOT EXISTS \
			`jb_runes_general_data` \
		( \
		     `account_id` INT NOT NULL, \
		     `capacity_value` INT NOT NULL, \
		     `gc_enabled` INT(1) NOT NULL, \
		     `gc_limiting_star` INT NOT NULL, \
		     `gc_included_runes_bits` INT NOT NULL, \
		     UNIQUE(`account_id`))"
		);
	
	// Loop through all the online clients, for late plugin load
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientAuthorized(current_client, "");
		}
	}
	
	//==== [ Execute the runes started forward ] =====//
	Call_StartForward(g_fwdOnRunesStarted);
	Call_Finish();
}

void SQL_FetchClient(int client)
{
	char query[128];
	
	// Initialize client general data
	g_Database.Format(query, sizeof(query), "SELECT * FROM `jb_runes_general_data` WHERE `account_id` = '%d'", g_ClientsData[client].AccountID);
	g_Database.Query(SQL_FetchClientGeneralData_CB, query, GetClientSerial(client));
	
	// Initialize client runes inventory
	g_Database.Format(query, sizeof(query), "SELECT * FROM `jb_runes_inventory` WHERE `account_id` = '%d'", g_ClientsData[client].AccountID);
	g_Database.Query(SQL_FetchClientInventory_CB, query, GetClientSerial(client));
}

public void SQL_FetchClientGeneralData_CB(Database db, DBResultSet results, const char[] error, int serial)
{
	// An error has occurred
	if (!db || !results || error[0])
	{
		ThrowError("Client fetch databse error, %s", error);
		return;
	}
	
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want
	if (!client)
	{
		return;
	}
	
	// If a result has found, fetch the values
	if (results.FetchRow())
	{
		g_ClientsData[client].iRunesCapacity = results.FetchInt(1);
		g_ClientsData[client].GarbageCollectorData.is_enabled = results.FetchInt(2) == 1;
		
		if ((g_ClientsData[client].GarbageCollectorData.limited_star = results.FetchInt(3)) == 0)
		{
			g_ClientsData[client].GarbageCollectorData.limited_star = RuneStar_1;
		}
		
		g_ClientsData[client].GarbageCollectorData.included_runes_bits = results.FetchInt(4);
	}
	else
	{
		char Query[256];
		g_Database.Format(Query, sizeof(Query), "INSERT INTO `jb_runes_general_data` (`account_id`, `capacity_value`, `gc_enabled`, `gc_limiting_star`, `gc_included_runes_bits`) VALUES (%d, %d, %d, %d, %d)", 
			g_ClientsData[client].AccountID, 
			g_cvDefaultRunesCapacity.IntValue, 
			g_ClientsData[client].GarbageCollectorData.is_enabled, 
			g_ClientsData[client].GarbageCollectorData.limited_star, 
			g_ClientsData[client].GarbageCollectorData.included_runes_bits
			);
		
		g_Database.Query(SQL_CheckForErrors, Query);
	}
}

public void SQL_FetchClientInventory_CB(Database db, DBResultSet results, const char[] error, int serial)
{
	// An error has occurred
	if (!db || !results || error[0])
	{
		ThrowError("Databse error, %s", error);
		return;
	}
	
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want
	if (!client)
	{
		return;
	}
	
	ClientRune ClientRuneData;
	
	char rune_unique[64];
	
	int rune_index = -1;
	
	while (results.FetchRow())
	{
		results.FetchString(2, rune_unique, sizeof(rune_unique));
		
		if ((rune_index = GetRuneByUnique(rune_unique)) == -1)
		{
			continue;
		}
		
		ClientRuneData.RowId = results.FetchInt(0);
		ClientRuneData.RuneId = rune_index;
		ClientRuneData.RuneStar = results.FetchInt(3);
		ClientRuneData.RuneLevel = results.FetchInt(4);
		ClientRuneData.IsRuneEquipped = results.FetchInt(5) == 1;
		ClientRuneData.IsInGarbageCollector = results.FetchInt(6) == 1;
		
		g_ClientsData[client].RunesInventory.PushArray(ClientRuneData);
	}
}

void SQL_UpdateClientGeneralData(int client)
{
	char query[256];
	g_Database.Format(query, sizeof(query), "UPDATE `jb_runes_general_data` SET `capacity_value` = '%d', `gc_enabled` = '%d', `gc_limiting_star` = '%d', `gc_included_runes_bits` = '%d' WHERE `account_id` = '%d'", 
		g_ClientsData[client].iRunesCapacity, 
		g_ClientsData[client].GarbageCollectorData.is_enabled, 
		g_ClientsData[client].GarbageCollectorData.limited_star, 
		g_ClientsData[client].GarbageCollectorData.included_runes_bits, 
		g_ClientsData[client].AccountID
		);
	
	// Make sure to reset the client data, to avoid data override
	g_ClientsData[client].Reset();
	
	// Execute the query to update the client runes general data inside the database
	g_Database.Query(SQL_CheckForErrors, query);
}

void SQL_AddClientRune(int client, int clientRuneIndex)
{
	ClientRune ClientRuneData;
	g_ClientsData[client].GetClientRuneByIndex(clientRuneIndex, ClientRuneData);
	
	Transaction txn = new Transaction();
	
	char query[256];
	
	// Format and add the insert query
	g_Database.Format(query, sizeof(query), "INSERT INTO `jb_runes_inventory`(`account_id`, `unique`, `star`, `level`, `equipped`, `garbage_collected`) VALUES (%d, '%s', %d, %d, %d, %d)", 
		g_ClientsData[client].AccountID, 
		GetRuneByIndex(ClientRuneData.RuneId).szRuneUnique, 
		ClientRuneData.RuneStar, 
		ClientRuneData.RuneLevel, 
		ClientRuneData.IsRuneEquipped, 
		ClientRuneData.IsInGarbageCollector
		);
	
	txn.AddQuery(query);
	
	// Format and add the row id query
	FormatEx(query, sizeof(query), "SELECT MAX(`id`) FROM `jb_runes_inventory` WHERE `account_id` = %d", g_ClientsData[client].AccountID);
	
	txn.AddQuery(query);
	
	// HACK: Pass the enum sturct through the arraylist, due to datapack disabilities
	ArrayList data = new ArrayList(sizeof(ClientRune));
	data.Push(GetClientUserId(client));
	data.PushArray(ClientRuneData);
	
	// Execute the transaction
	g_Database.Execute(txn, SQL_OnTxnSuccess, SQL_OnTxnError, data);
}

void SQL_OnTxnSuccess(Database db, ArrayList data, int numQueries, DBResultSet[] results, any[] queryData)
{
	if (!db || !results)
	{
		delete data;
		ThrowError("Transaction success callback error.");
	}
	
	// Get the client index by the parsed transaction data
	int client = GetClientOfUserId(data.Get(0));
	
	if (!client)
	{
		delete data;
		
		return;
	}
	
	// Get the client rune data struct
	ClientRune ClientRuneData;
	data.GetArray(data.Length - 1, ClientRuneData);
	
	// Don't leak handles
	delete data;
	
	if (!results[numQueries - 1].FetchRow())
	{
		return;
	}
	
	// Get the client rune index, and update the row id by the database results
	int client_rune_index = ClientRuneData.FindIndex(g_ClientsData[client].RunesInventory);
	
	if (client_rune_index != -1)
	{
		g_ClientsData[client].RunesInventory.Set(client_rune_index, results[numQueries - 1].FetchInt(0), ClientRune::RowId);
	}
}

void SQL_OnTxnError(Database db, ArrayList data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	// Don't leak handles
	delete data;
	
	ThrowError("Client rune transaction addition has failed. Query: %d | Error: (%s)", failIndex + 1, error);
}

void SQL_RemoveClientRune(int client, int clientRuneIndex)
{
	ClientRune ClientRuneData;
	g_ClientsData[client].GetClientRuneByIndex(clientRuneIndex, ClientRuneData);
	
	char query[128];
	FormatEx(query, sizeof(query), "DELETE FROM `jb_runes_inventory` WHERE `account_id` = %d AND `id` = %d", g_ClientsData[client].AccountID, ClientRuneData.RowId);
	
	// Execute the query
	g_Database.Query(SQL_CheckForErrors, query);
}

void SQL_UpdateRuneLevel(int client, int clientRuneIndex)
{
	ClientRune ClientRuneData;
	
	g_ClientsData[client].GetClientRuneByIndex(clientRuneIndex, ClientRuneData);
	
	char query[128];
	FormatEx(query, sizeof(query), "UPDATE `jb_runes_inventory` SET `level` = %d WHERE `account_id` = %d AND `id` = %d", ClientRuneData.RuneLevel, g_ClientsData[client].AccountID, ClientRuneData.RowId);
	
	// Execute the query
	g_Database.Query(SQL_CheckForErrors, query);
}

void SQL_UpdateRuneEquipState(int client, int clientRuneIndex)
{
	ClientRune ClientRuneData;
	
	g_ClientsData[client].GetClientRuneByIndex(clientRuneIndex, ClientRuneData);
	
	char query[128];
	FormatEx(query, sizeof(query), "UPDATE `jb_runes_inventory` SET `equipped` = %d WHERE `account_id` = %d AND `id` = %d", ClientRuneData.IsRuneEquipped, g_ClientsData[client].AccountID, ClientRuneData.RowId);
	
	// Execute the query
	g_Database.Query(SQL_CheckForErrors, query);
}

void SQL_UpdateRuneGarbageCollected(int client, int clientRuneIndex)
{
	ClientRune ClientRuneData;
	
	g_ClientsData[client].GetClientRuneByIndex(clientRuneIndex, ClientRuneData);
	
	char query[128];
	FormatEx(query, sizeof(query), "UPDATE `jb_runes_inventory` SET `garbage_collected` = %d WHERE `account_id` = %d AND `id` = %d", ClientRuneData.IsInGarbageCollector, g_ClientsData[client].AccountID, ClientRuneData.RowId);
	
	// Execute the query
	g_Database.Query(SQL_CheckForErrors, query);
}

void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	// An error has occurred
	if (!db || !results || error[0])
	{
		ThrowError("General databse error (Error: %s)", error);
	}
}

//================================[ Timers ]================================//

public Action Timer_ShowRunePickupInfo(Handle timer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want from the serial
	if (!client)
	{
		return Plugin_Stop;
	}
	
	char szRuneData[16], szData[3][16];
	
	int iRuneStar;
	
	if (g_ClientsData[client].iRunePickupProgress)
	{
		g_ClientsData[client].PickedRunes.PeekString(szRuneData, sizeof(szRuneData));
		
		ExplodeString(szRuneData, ":", szData, sizeof(szData), sizeof(szData[]));
		
		int iRuneId = StringToInt(szData[0]);
		iRuneStar = StringToInt(szData[1]);
		
		bool bLastProgress = g_ClientsData[client].iRunePickupProgress == iRuneStar + 1;
		
		char szInfoMessage[256], szStar[16];
		
		Format(szStar, sizeof(szStar), " | %d Stars", iRuneStar);
		
		for (int iCurrentStar = 0; iCurrentStar < g_ClientsData[client].iRunePickupProgress; iCurrentStar++)
		{
			if (iCurrentStar != iRuneStar)
			{
				Format(szInfoMessage, sizeof(szInfoMessage), "%s%s", szInfoMessage, RUNE_STAR_SYMBOL);
			}
		}
		
		Rune RuneData; RuneData = GetRuneByIndex(iRuneId);
		
		// Format the information message and print
		Format(szInfoMessage, sizeof(szInfoMessage), "%s%s", szInfoMessage, bLastProgress ? szStar : "");
		PrintCenterText(client, " %s %s\n %s", RuneData.szRuneSymbol, RuneData.szRuneName, szInfoMessage);
		
		// Play the star sound effect
		if (iRuneStar != RuneStar_Max - 1 || !bLastProgress)
		{
			ClientCommand(client, "play %s", g_szProgressSounds[bLastProgress ? 0 : g_ClientsData[client].iRunePickupProgress]);
		}
		
		g_ClientsData[client].iRunePickupProgress = bLastProgress ? 0 : g_ClientsData[client].iRunePickupProgress + 1;
		
		return Plugin_Continue;
	}
	
	g_ClientsData[client].PickedRunes.PopString(szRuneData, sizeof(szRuneData));
	
	g_ClientsData[client].ShowRuneInfoTimer = INVALID_HANDLE;
	g_ClientsData[client].iRunePickupProgress = 1;
	
	// If there is still picked runes inside the queue, recreate the progress bar time
	if (!g_ClientsData[client].PickedRunes.Empty)
	{
		CreateRunePickupTimer(client);
	}
	
	ExplodeString(szRuneData, ":", szData, sizeof(szData), sizeof(szData[]));
	
	iRuneStar = StringToInt(szData[1]);
	
	// If the rune star is above or equal to the notify convar, print a notify message
	if (iRuneStar >= g_cvRunePickupNotifyMinStar.IntValue)
	{
		PrintToChatAll("%s \x04%N\x01 has obtained a \x02%s\x01 with \x0C%d%s\x01!", PREFIX, client, GetRuneByIndex(StringToInt(szData[0])).szRuneName, iRuneStar, RUNE_STAR_SYMBOL);
	}
	else
	{
		PrintToChat(client, "%s You've obtained a \x02%s\x01 with \x0C%d%s\x01!", PREFIX, GetRuneByIndex(StringToInt(szData[0])).szRuneName, iRuneStar, RUNE_STAR_SYMBOL);
	}
	
	return Plugin_Stop;
}

Action Timer_ShowRuneUpgradeInfo(Handle timer, DataPack dp)
{
	// Reset the data pack position
	dp.Reset();
	
	int client = GetClientFromSerial(dp.ReadCell());
	
	// Make sure the client index is the index we want from the serial
	if (!client)
	{
		return Plugin_Stop;
	}
	
	int iClientRuneIndex = dp.ReadCell();
	
	if (!g_ClientsData[client].iRuneUpgradeProgress)
	{
		if (dp.ReadCell()/* = Upgrade succeed ?*/)
		{
			// Play the upgrade succeed sound effect
			EmitSoundToClient(client, UPGRADE_SUCCEED_SOUND);
			
			// Notify upgrade succeed by hint text
			PrintCenterText(client, " <font color='#00FF00'>Upgrade Succeed!</font>");
			
			// Get the client rune data from the current index
			ClientRune ClientRuneData;
			g_ClientsData[client].GetClientRuneByIndex(iClientRuneIndex, ClientRuneData);
			
			// If the upgraded rune level is above the convar level value, notify all the online players
			if (ClientRuneData.RuneLevel >= g_cvRuneUpgradeNotifyMinLevel.IntValue)
			{
				PrintToChatAll("%s \x04%N\x01 has upgraded his \x02%s %d%s\x01 to \x10level %d\x01!", PREFIX, client, GetRuneByIndex(ClientRuneData.RuneId).szRuneName, ClientRuneData.RuneStar, RUNE_STAR_SYMBOL, ClientRuneData.RuneLevel);
			}
		}
		else
		{
			// Notify upgrade failed by hint text
			PrintCenterText(client, " <font color='#CC0000'>Upgrade Failed!</font>");
		}
		
		// Show the current upgraded rune menu details
		ShowRuneDetailMenu(client, iClientRuneIndex);
		
		// If the client has picked up a rune in the middle of the upgrade, show him the rune info after the upgrade has finished
		if (!g_ClientsData[client].PickedRunes.Empty)
		{
			CreateTimer(RUNE_PICKUP_PROGRESS_INTERVAL * 1.5, Timer_DelayRunePickupTimer, GetClientSerial(client));
		}
		
		// Reset the timers varribles
		g_ClientsData[client].iRuneUpgradeProgress = 0;
		g_ClientsData[client].ShowUpgradeInfoTimer = INVALID_HANDLE;
		
		return Plugin_Stop;
	}
	
	PrintCenterText(client, GetProgressBar(g_ClientsData[client].iRuneUpgradeProgress, 10));
	
	g_ClientsData[client].iRuneUpgradeProgress--;
	
	return Plugin_Continue;
}

Action Timer_DelayRunePickupTimer(Handle timer, int serial)
{
	int client = GetClientFromSerial(serial);
	
	// Make sure the client index is the index we want from the serial
	if (!client)
	{
		return Plugin_Stop;
	}
	
	CreateRunePickupTimer(client);
	
	return Plugin_Continue;
}

//================================[ Functions ]================================//

int GetRuneByUnique(const char[] unique)
{
	// Find the specified rune unique inside the global arraylist
	return g_RunesData.FindString(unique);
}

any[] GetRuneByIndex(int index)
{
	Rune RuneData;
	g_RunesData.GetArray(index, RuneData);
	return RuneData;
}

int CreateRuneBox(float pos[3], int runeId, int star, int level = RuneLevel_1, bool natural = true)
{
	int iEntity = CreateEntityByName("prop_physics_override");
	
	// Make sure the class name has found and the entity is valid
	if (iEntity == -1 || !IsValidEntity(iEntity))
	{
		return -1;
	}
	
	float mins[3] = RUNE_MODEL_MINS, maxs[3] = RUNE_MODEL_MAXS;
	
	// Center the entity prelocation.
	pos[0] = -(mins[0] + maxs[0]) / 2 + pos[0];
	pos[1] = -(mins[1] + maxs[1]) / 2 + pos[1];
	// Reattach only 2D dims.
	// centered_pos[2] = -(mins[2] + maxs[2]) / 2 + pos[2];
	
	Rune RuneData; RuneData = GetRuneByIndex(runeId);
	
	Action fwdReturn;
	
	//==== [ Execute the rune spawn forward ] =====//
	Call_StartForward(g_fwdOnRuneSpawn);
	Call_PushCell(iEntity); // int entity
	Call_PushArray(RuneData, sizeof(RuneData)); // Rune runeStruct
	Call_PushCellRef(runeId); // int &runeId
	Call_PushArray(pos, sizeof(pos)); // float origin[3]
	Call_PushCellRef(star); // int &star
	Call_PushCellRef(level); // int &level
	Call_PushCell(natural); // bool natural
	
	int iError = Call_Finish(fwdReturn);
	
	// Check for forward failure
	if (iError != SP_ERROR_NONE)
	{
		ThrowNativeError(iError, "Global Forward Failed - Error: %d", iError);
		return -1;
	}
	
	// If the forward return is higher then Plugin_Handled, stop the further actions
	if (fwdReturn >= Plugin_Handled)
	{
		return -1;
	}
	
	// Apply the model on the entity
	DispatchKeyValue(iEntity, "model", RUNE_MODEL_PATH);
	// DispatchKeyValue(iEntity, "solid", "1");
	
	DispatchKeyValueVector(iEntity, "origin", pos);
	
	// Store the data inside a unique entity net prop, instead using a global verrible
	char entity_name[16];
	Format(entity_name, sizeof(entity_name), "%d:%d:%d", runeId, star, level);
	DispatchKeyValue(iEntity, "targetname", entity_name);
	
	// Spawn and teleport the entity to the specified position
	DispatchSpawn(iEntity);
	
	// Required for pick up detection
	SDKHook(iEntity, SDKHook_StartTouch, Hook_OnStartTouch);
	
	return iEntity;
}

int GenerateRuneStar()
{
	// Generate a randomize percent number
	int random_percent = GetRandomInt(0, 1000);
	
	// Return the generated rune star by the default stars percentage
	return (random_percent <= SpawnChance_Star1To3 ? GetRandomInt(RuneStar_1, RuneStar_3) : random_percent <= SpawnChance_Star4To5 + SpawnChance_Star1To3 ? GetRandomInt(RuneStar_4, RuneStar_5) : RuneStar_6);
}

void AddRuneToInventory(int client, int rune_index, int star, int level, int add_amount, Handle plugin = INVALID_HANDLE)
{
	ClientRune ClientRuneData;
	
	ClientRuneData.RuneId = rune_index == -1 ? GetRandomInt(0, g_RunesData.Length - 1) : rune_index;
	ClientRuneData.RuneStar = !star ? GenerateRuneStar() : star;
	ClientRuneData.RuneLevel = !level ? GetRandomInt(1, RuneLevel_Max - 1) : level;
	ClientRuneData.IsRuneEquipped = false;
	ClientRuneData.IsInGarbageCollector = IsRuneMatchingFilters(client, ClientRuneData.RuneId, ClientRuneData.RuneStar);
	
	// Push the client rune struct into the client inventory array list
	for (int current_client_rune = 0; current_client_rune < add_amount; current_client_rune++)
	{
		// Add the client rune to the mysql database, and push the rune struct to the client's inventory
		SQL_AddClientRune(client, g_ClientsData[client].RunesInventory.PushArray(ClientRuneData));
	}
	
	// Write a log to the plugin log file
	if (plugin != INVALID_HANDLE)
	{
		char plugin_name[64];
		GetPluginFilename(plugin, plugin_name, sizeof(plugin_name));
		JB_WriteLogLine("Rune \"%s\" %d star level %d has been added %d times, to \"%L\" inventory by plugin \"%s\".", GetRuneByIndex(ClientRuneData.RuneId).szRuneUnique, ClientRuneData.RuneStar, ClientRuneData.RuneLevel, add_amount, client, plugin_name);
	}
}

void CreateRunePickupTimer(int client)
{
	if (g_ClientsData[client].ShowRuneInfoTimer == INVALID_HANDLE)
	{
		g_ClientsData[client].ShowRuneInfoTimer = CreateTimer(RUNE_PICKUP_PROGRESS_INTERVAL, Timer_ShowRunePickupInfo, GetClientSerial(client), TIMER_REPEAT);
	}
}

int PerformClientRuneSell(int client, int client_rune_index)
{
	//Rune RuneData;
	ClientRune ClientRuneData;
	
	// Get the client rune data from the specified index
	g_ClientsData[client].GetClientRuneByIndex(client_rune_index, ClientRuneData);
	//RuneData = GetRuneByIndex(ClientRuneData.RuneId);
	
	// Initialize the sell profit with the specified rune stats
	int iSellProfit = CalculateRuneSellProfit(ClientRuneData.RuneStar, ClientRuneData.RuneLevel);
	
	bool fwdReturn;
	
	//==== [ Execute the rune sell forward ] =====//
	Call_StartForward(g_fwdOnRuneSell);
	Call_PushCell(client);
	Call_PushCell(client_rune_index);
	Call_PushCell(iSellProfit);
	
	int iError = Call_Finish(fwdReturn);
	
	// Check for forward failure
	if (iError != SP_ERROR_NONE)
	{
		ThrowNativeError(iError, "Rune Sell Forward Failed - Error: %d", iError);
		return 0;
	}
	
	// If the forward return is true, stop the further actions
	if (fwdReturn)
	{
		// Don't Continue
		return 0;
	}
	
	// Remove the client rune from the mysql database
	SQL_RemoveClientRune(client, client_rune_index);
	
	// Erase the client rune index from the runes inventory array list
	g_ClientsData[client].RunesInventory.Erase(client_rune_index);
	
	// Give the client the credits from the sold rune
	Shop_GiveClientCredits(client, iSellProfit, CREDITS_BY_BUY_OR_SELL);
	
	return iSellProfit;
}

void GetClientAimPosition(int client, float result[3])
{
	// Initialize the client position and angles.
	float pos[3], ang[3];
	
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, ang);
	
	TR_TraceRayFilter(pos, ang, MASK_ALL, RayType_Infinite, Filter_DontHitPlayer, client);
	
	TR_GetEndPosition(result);
}

bool Filter_DontHitPlayer(int entity, int mask, int data)
{
	return entity != data;
}

char[] GetProgressBar(int value, int all)
{
	char szProgress[PROGRESS_BAR_LENGTH * 8];
	int iLength = PROGRESS_BAR_LENGTH;
	
	Format(szProgress, sizeof(szProgress), "<font color='#CC0000'>");
	
	for (int iCurrentChar = 0; iCurrentChar <= (float(value) / float(all) * PROGRESS_BAR_LENGTH) - 1; iCurrentChar++)
	{
		iLength--;
		StrCat(szProgress, sizeof(szProgress), "⬛");
	}
	
	StrCat(szProgress, sizeof(szProgress), "<font color='#0000B3'>");
	
	for (int iCurrentChar = 0; iCurrentChar < iLength; iCurrentChar++)
	{
		StrCat(szProgress, sizeof(szProgress), "⚫");
	}
	
	StripQuotes(szProgress);
	TrimString(szProgress);
	
	return szProgress;
}

char[] GetRuneBenefitDisplay(ClientRune ClientRuneData)
{
	char benefit_display[32], benefit_value[16];
	strcopy(benefit_display, sizeof(benefit_display), GetRuneByIndex(ClientRuneData.RuneId).szRuneBenefitText);
	
	if (StrContains(benefit_display, "{int}") != -1)
	{
		IntToString(GetRuneBenefit(ClientRuneData.RuneId, ClientRuneData.RuneStar, ClientRuneData.RuneLevel), benefit_value, sizeof(benefit_value));
		ReplaceString(benefit_display, sizeof(benefit_display), "{int}", benefit_value);
	}
	else if (StrContains(benefit_display, "{float}") != -1)
	{
		Format(benefit_value, sizeof(benefit_value), "%.2f", GetRuneBenefit(ClientRuneData.RuneId, ClientRuneData.RuneStar, ClientRuneData.RuneLevel));
		ReplaceString(benefit_display, sizeof(benefit_display), "{float}", benefit_value);
	}
	
	return benefit_display;
}

int GetOwnedRunesAmount(int client, int runeIndex, bool garbage_collected, int runeStar = -1, int runeLevel = -1)
{
	int counter;
	
	ClientRune CurrentClientRuneData;
	
	for (int iCurrentIndex = 0; iCurrentIndex < g_ClientsData[client].RunesInventory.Length; iCurrentIndex++)
	{
		// Get the client rune data from the current index
		g_ClientsData[client].GetClientRuneByIndex(iCurrentIndex, CurrentClientRuneData);
		
		if (CurrentClientRuneData.RuneId == runeIndex)
		{
			if ((runeStar != -1 && runeLevel == -1 && CurrentClientRuneData.RuneStar == runeStar) || (runeLevel != -1 && runeStar == -1 && CurrentClientRuneData.RuneLevel == runeLevel) || (runeLevel != -1 && runeStar != -1 && CurrentClientRuneData.RuneStar == runeStar && CurrentClientRuneData.RuneLevel == runeLevel) || (runeLevel == -1 && runeStar == -1) && CurrentClientRuneData.IsInGarbageCollector == garbage_collected)
			{
				counter++;
			}
		}
	}
	
	return counter;
}

int GetGarbageCollectionAmount(int client)
{
	int counter;
	
	ClientRune CurrentClientRuneData;
	
	for (int iCurrentIndex = 0; iCurrentIndex < g_ClientsData[client].RunesInventory.Length; iCurrentIndex++)
	{
		// Get the client rune data from the current index
		g_ClientsData[client].GetClientRuneByIndex(iCurrentIndex, CurrentClientRuneData);
		
		if (CurrentClientRuneData.IsInGarbageCollector)
		{
			counter++;
		}
	}
	
	return counter;
}

int GetEquippedRune(int client, int runeIndex, int runeStar = -1, int runeLevel = -1)
{
	if (g_ClientsData[client].RunesInventory == null)
	{
		return -1;
	}
	
	ClientRune CurrentClientRuneData;
	
	for (int iCurrentIndex = 0; iCurrentIndex < g_ClientsData[client].RunesInventory.Length; iCurrentIndex++)
	{
		// Get the client rune data from the current index
		g_ClientsData[client].GetClientRuneByIndex(iCurrentIndex, CurrentClientRuneData);
		
		if (CurrentClientRuneData.RuneId == runeIndex && CurrentClientRuneData.IsRuneEquipped)
		{
			if ((runeStar != -1 && runeLevel == -1 && CurrentClientRuneData.RuneStar == runeStar)
				 || (runeLevel != -1 && runeStar == -1 && CurrentClientRuneData.RuneLevel == runeLevel)
				 || (runeLevel != -1 && runeStar != -1 && CurrentClientRuneData.RuneStar == runeStar && CurrentClientRuneData.RuneLevel == runeLevel)
				 || (runeLevel == -1 && runeStar == -1))
			{
				return iCurrentIndex;
			}
		}
	}
	
	return -1;
}

any GetRuneBenefit(int runeIndex, int runeStar, int runeLevel)
{
	Rune RuneData; RuneData = GetRuneByIndex(runeIndex);
	
	any Benefits[RuneLevel_Max - 1];
	
	RuneData.RuneBenefits.GetArray(runeStar - 1, Benefits);
	
	return Benefits[runeLevel - 1];
}

int CalculatePurchasedExpantions(int client)
{
	// Calculate the times that the client has expand his ruens capacity
	return (g_ClientsData[client].iRunesCapacity - g_cvDefaultRunesCapacity.IntValue) / (g_iCapacityTiers[0] - g_cvDefaultRunesCapacity.IntValue);
}

int CalculateExpantionPrice(int client, int expantion_index)
{
	// Calculate the expantion price, by the specified client & expantion index
	return (expantion_index + 1) * g_cvCapacityExpandPrice.IntValue - CalculatePurchasedExpantions(client) * g_cvCapacityExpandPrice.IntValue;
}

int CalculateRuneSellProfit(int star, int level)
{
	// Returns the rune sell profit, by the specified star and level
	return (1000 + ((star - 1) * 400)) + ((level - 1) * 400);
}

int CalculateRuneUpgradePrice(int star, int level)
{
	// Returns the rune level upgrade costs, by the specified star and level
	return (4000 + (1000 * star) - 1000 + (star >= 5 ? 500 : 0)) * level;
}

int CalculateUpgradeSuccessRate(int star, int level)
{
	int success_percent = 10;
	
	switch (level)
	{
		case 1 : success_percent = 100;
		case 2 : success_percent = 90;
		case 3 : success_percent = 80;
		case 4 : success_percent = 75;
		case 5 : success_percent = 60;
		case 6 : success_percent = 50;
		case 7 : success_percent = 45;
		case 8 : success_percent = 40;
		case 9 : success_percent = 35;
		case 10 : success_percent = 25;
		case 11 : success_percent = 23;
		case 12 : success_percent = 20;
		case 13 : success_percent = 18;
		case 14 : success_percent = 15;
		case 15 : success_percent = 11;
	}
	
	// Returns the rune level upgrade success chance rate, by the specified star and level
	return (success_percent = (star < 5 ? success_percent + 10 : star >= 6 ? success_percent - 15 : success_percent));
}

bool IsRuneMatchingFilters(int client, int rune_index, int rune_star)
{
	return (IsGarbageCollectorPurchased(client) && g_ClientsData[client].GarbageCollectorData.is_enabled && rune_star <= g_ClientsData[client].GarbageCollectorData.limited_star && (g_ClientsData[client].GarbageCollectorData.included_runes_bits & (1 << rune_index)));
}

bool IsGarbageCollectorPurchased(int client)
{
	static ItemId item_id;
	
	if (!item_id)
	{
		item_id = Shop_GetItemId(g_ShopCategoryID, "Runes Garbage Collector");
	}
	
	return Shop_IsClientHasItem(client, item_id);
}

void Frame_ShowCase(int ent_ref)
{
	// static int fade_color[3] = { 255, 0, 0 };
	
	int entity = EntRefToEntIndex(ent_ref);
	if (entity == -1)
	{
		return;
	}
	
	/* Fade color handler */
	int fade_color[4];
	GetEntityRenderColor(entity, fade_color[0], fade_color[1], fade_color[2], fade_color[3]);
	
	if (fade_color[0] == 255 && fade_color[1] == 255 && fade_color[2] == 255)
	{
		fade_color[0] = 255;
		fade_color[0] = 0;
		fade_color[0] = 0;
	}
	
	if (fade_color[0] > 0 && !fade_color[2])
	{
		fade_color[0]--;
		fade_color[1]++;
	}
	
	if (fade_color[1] > 0 && !fade_color[0])
	{
		fade_color[1]--;
		fade_color[2]++;
	}
	
	if (fade_color[2] > 0 && !fade_color[1])
	{
		fade_color[2]--;
		fade_color[0]++;
	}
	
	SetEntityRenderColor(entity, fade_color[0], fade_color[1], fade_color[2]);
	
	RequestFrame(Frame_ShowCase, ent_ref);
}

/**
 * Return true if the client's steam account id matched one of specified authorized clients.
 * See g_AuthorizedClients
 */
bool IsClientAuthorizedEx(int client)
{
	int account_id = GetSteamAccountID(client);
	
	for (int current_account_id; current_account_id < sizeof(g_AuthorizedClients); current_account_id++)
	{
		// Check for a match.
		if (account_id == g_AuthorizedClients[current_account_id])
		{
			return true;
		}
	}
	
	// No match has found.
	return false;
}

//================================================================//