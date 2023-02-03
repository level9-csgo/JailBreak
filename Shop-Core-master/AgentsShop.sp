#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <shop>
#include <PTaH>

#define MAX_TEAMS 2

#define DEFAULT_PRISONER_SKIN "models/player/custom_player/legacy/tm_phoenix.mdl"
#define DEFAULT_GUARD_SKIN "models/player/custom_player/legacy/ctm_st6.mdl"

enum
{
	Agent_Prisoner, 
	Agent_Guard
}

CategoryId g_ShopCategoryID[MAX_TEAMS];

char g_ClientAgent[MAXPLAYERS + 1][MAX_TEAMS][PLATFORM_MAX_PATH];

public Plugin myinfo = 
{
	name = "[Shop Integrated] Agents", 
	author = "LuqS", 
	description = "", 
	version = "1.0.0", 
	url = "https://github.com/Natanel-Shitrit || https://steamcommunity.com/id/luqsgood || Discord: LuqS#6505"
};

public void OnPluginStart()
{
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
}

public void OnPluginEnd()
{
	Shop_UnregisterMe();
}

public void Shop_Started()
{
	g_ShopCategoryID[Agent_Prisoner] = Shop_RegisterCategory("prisoners_agents", "Prisoners Agents", "The agent that will appear when you play as a prisoner");
	g_ShopCategoryID[Agent_Guard] = Shop_RegisterCategory("guards_agents", "Guards Agents", "The agent that will appear when you play as a guard");
	
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("Agents");
	
	// Find the Config
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/shop/agents.cfg");
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(sFilePath) || !kv.GotoFirstSubKey())
	{
		SetFailState("Couldn't load plugin config.");
	}
	
	char name[64], description[64], model_path[PLATFORM_MAX_PATH];
	int team;
	
	// Parse agents one by one.
	do
	{
		// Get team team
		team = kv.GetNum("team");
		
		// Get name
		kv.GetString("name", name, sizeof(name));
		
		// Get description
		kv.GetString("description", description, sizeof(description));
		
		// Get model path
		kv.GetString("model_path", model_path, sizeof(model_path));
		
		if (Shop_StartItem(g_ShopCategoryID[team - MAX_TEAMS], name))
		{
			Shop_SetInfo(name, description, kv.GetNum("price"), kv.GetNum("sell_price"), Item_Togglable, 0, kv.GetNum("price_gold"), kv.GetNum("sell_price_gold"));
			Shop_SetCallbacks(.use_toggle = OnEquipItem, .preview = OnItemPreview);
			
			Shop_SetCustomInfo("definition_index", kv.GetNum("definition_index"));
			Shop_SetCustomInfoString("model_path", model_path);
			
			Shop_EndItem();
		}
	} while (kv.GotoNextKey());
	
	// Don't leak handles
	kv.Close();
}

public void OnMapStart()
{
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("Agents");
	
	// Find the Config
	char file_path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, file_path, sizeof(file_path), "configs/shop/agents.cfg");
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(file_path) || !kv.GotoFirstSubKey())
	{
		SetFailState("Couldn't load plugin config.");
	}
	
	char model_path[PLATFORM_MAX_PATH];
	
	// Precache agents one by one
	do
	{
		// Get model path
		kv.GetString("model_path", model_path, sizeof(model_path));
		
		// Precache the model
		PrecacheModel(model_path);
	} while (kv.GotoNextKey());
	
	// Don't leak handles
	kv.Close();
	
	// Precache the default agents
	PrecacheModel(DEFAULT_PRISONER_SKIN);
	PrecacheModel(DEFAULT_GUARD_SKIN);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(RF_SetClientAgent, GetClientSerial(GetClientOfUserId(event.GetInt("userid"))));
}

void RF_SetClientAgent(int serial)
{
	int client = GetClientFromSerial(serial)
	
	// Make sure the client index is in-game and valid
	if (client)
	{
		SetClientAgent(client);
	}
}

public ShopAction OnEquipItem(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	int model_index = (category_id == g_ShopCategoryID[Agent_Prisoner] ? Agent_Prisoner : Agent_Guard);
	
	// If already equiped, just unequip.
	if (isOn)
	{
		g_ClientAgent[client][model_index][0] = '\0';
		
		if (IsPlayerAlive(client))
		{
			SetClientAgent(client);
		}
		
		return Shop_UseOff;
	}
	
	// Toggle off all other items off.
	Shop_ToggleClientCategoryOff(client, category_id);
	
	Shop_GetItemCustomInfoString(item_id, "model_path", g_ClientAgent[client][model_index], sizeof(g_ClientAgent[][]));
	
	if (IsPlayerAlive(client))
	{
		SetClientAgent(client);
	}
	
	// Player
	return Shop_UseOn;
}

public void OnItemPreview(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item)
{
	int definition_index = Shop_GetItemCustomInfo(item_id, "definition_index", -1);
	
	if (definition_index != -1)
	{
		PreviewAgent(client, PTaH_GetItemDefinitionByDefIndex(definition_index));
	}
}

public void OnClientPostAdminCheck(int client)
{
	// Reset local variable
	g_ClientAgent[client][Agent_Prisoner] = DEFAULT_PRISONER_SKIN;
	g_ClientAgent[client][Agent_Guard] = DEFAULT_GUARD_SKIN;
}

void SetClientAgent(int client)
{
	int client_team = GetClientTeam(client);
	
	if (client_team < 2)
	{
		return;
	}
	
	char model_path[PLATFORM_MAX_PATH]; model_path = g_ClientAgent[client][client_team - MAX_TEAMS];
	
	if (!model_path[0])
	{
		return;
	}
	
	SetEntityModel(client, model_path[0] ? model_path : GetClientTeam(client) == CS_TEAM_T ? DEFAULT_PRISONER_SKIN : DEFAULT_GUARD_SKIN);
}

void PreviewAgent(int client, CEconItemDefinition item_definition, bool firstRun = true)
{
	if (!item_definition)
	{
		return;
	}
	
	char buffer[PLATFORM_MAX_PATH];
	
	Protobuf msg = view_as<Protobuf>(StartMessageOne("TextMsg", client));
	
	item_definition.GetEconImage(buffer, sizeof(buffer));
	Format(buffer, sizeof(buffer), "</font><img src='file://{images_econ}/%s.png'/><script>", buffer);
	
	msg.SetInt("msg_dst", 4);
	msg.AddString("params", "#SFUI_ContractKillStart");
	msg.AddString("params", buffer);
	msg.AddString("params", NULL_STRING);
	msg.AddString("params", NULL_STRING);
	msg.AddString("params", NULL_STRING);
	msg.AddString("params", NULL_STRING);
	
	EndMessage();
	
	// show again so it won't be a small icon!
	if (firstRun)
	{
		DataPack dp;
		CreateDataTimer(0.1, Timer_PrintHintEconRepeat, dp);
		dp.WriteCell(item_definition);
		dp.WriteCell(GetClientSerial(client));
		dp.Reset();
	}
}

Action Timer_PrintHintEconRepeat(Handle timer, DataPack dp)
{
	CEconItemDefinition itemDef = dp.ReadCell();
	
	int client = GetClientFromSerial(dp.ReadCell());
	
	if (!client)
	{
		return;
	}
	
	PreviewAgent(client, itemDef, false);
} 