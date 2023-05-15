#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <shop>
#include <EconAPI>

#pragma semicolon 1
#pragma newdecls required

// Default agents model file paths.
#define DEFAULT_TERRORIST_SKIN "models/player/custom_player/legacy/tm_phoenix.mdl"
#define DEFAULT_COUNTER_TERRORIST_SKIN "models/player/custom_player/legacy/ctm_st6.mdl"

enum struct Agent
{
	// Display name after token modification.
	char base_name[64];
	
	// Description after token modification.
	char description[256];
	
	// Econ image path. Required for previewing the agent.
	char econ_image[PLATFORM_MAX_PATH];
	
	// Agent entity model.
	char entity_model[PLATFORM_MAX_PATH];
	
	// Team index the agent is associated to.
	int associated_team;
	
	// Purchase price.
	int price;
}

ArrayList g_Agents;
ArrayList g_Models;

enum
{
	Agent_Prisoner, 
	Agent_Guard, 
	
	// Enum size.
	Agent_Max
}

CategoryId g_ShopCategoryID[Agent_Max];

char g_ClientAgent[MAXPLAYERS + 1][Agent_Max][PLATFORM_MAX_PATH];

int g_RarityValue[] = 
{
	0, 
	100000, 
	250000, 
	400000, 
	650000, 
	850000, 
	1250000
};

public Plugin myinfo = 
{
	name = "[Shop Integrated] Agents", 
	author = "KoNLiG", 
	description = "Implemention of EconAPI to shop.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_Agents = new ArrayList(sizeof(Agent));
	g_Models = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	LoadTranslations("localization.phrases");
	
	CacheAgents();
	
	// Late load.
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
	
	HookEvent("player_spawn", Event_PlayerSpawn);
}

public void OnPluginEnd()
{
	Shop_UnregisterMe();
}

public void OnMapStart()
{
	PrecacheModel(DEFAULT_TERRORIST_SKIN);
	PrecacheModel(DEFAULT_COUNTER_TERRORIST_SKIN);
	
	PrecacheAgentModels();
}

public void Shop_Started()
{
	g_ShopCategoryID[Agent_Prisoner] = Shop_RegisterCategory("prisoners_agents", "Prisoners Agents", "The agent that will appear when you play as a prisoner");
	g_ShopCategoryID[Agent_Guard] = Shop_RegisterCategory("guards_agents", "Guards Agents", "The agent that will appear when you play as a guard");
	
	Agent agent;
	for (int current_agent; current_agent < g_Agents.Length; current_agent++)
	{
		g_Agents.GetArray(current_agent, agent);
		
		// Store the new agent object.
		if (Shop_StartItem(g_ShopCategoryID[agent.associated_team - Agent_Max], agent.base_name))
		{
			Shop_SetInfo(agent.base_name, agent.description, agent.price, agent.price / 2, Item_Togglable, 0, -1, -1);
			Shop_SetCallbacks(.use_toggle = OnEquipItem, .preview = OnItemPreview);
			
			Shop_SetCustomInfoString("econ_image", agent.econ_image);
			Shop_SetCustomInfoString("entity_model", agent.entity_model);
			
			Shop_EndItem();
		}
	}
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	RequestFrame(Frame_SetClientAgent, event.GetInt("userid"));
}

void Frame_SetClientAgent(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client)
	{
		SetClientAgent(client);
	}
}

ShopAction OnEquipItem(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
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
	
	Shop_GetItemCustomInfoString(item_id, "entity_model", g_ClientAgent[client][model_index], sizeof(g_ClientAgent[][]));
	
	if (IsPlayerAlive(client))
	{
		SetClientAgent(client);
	}
	
	return Shop_UseOn;
}

void OnItemPreview(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item)
{
	char econ_image[PLATFORM_MAX_PATH];
	Shop_GetItemCustomInfoString(item_id, "econ_image", econ_image, sizeof(econ_image));
	
	PreviewEconImage(client, econ_image);
}

// Reset client data.
public void OnClientDisconnect(int client)
{
	g_ClientAgent[client][Agent_Prisoner][0] = '\0';
	g_ClientAgent[client][Agent_Guard][0] = '\0';
}

void SetClientAgent(int client)
{
	int client_team = GetClientTeam(client);
	if (client_team <= CS_TEAM_SPECTATOR)
	{
		return;
	}
	
	char model_path[PLATFORM_MAX_PATH]; model_path = g_ClientAgent[client][client_team - Agent_Max];
	
	SetEntityModel(client, model_path[0] ? model_path : client_team == CS_TEAM_T ? DEFAULT_TERRORIST_SKIN : DEFAULT_COUNTER_TERRORIST_SKIN);
}

void PreviewEconImage(int client, char[] econ_image, bool first_run = true)
{
	char buffer[PLATFORM_MAX_PATH];
	Format(buffer, sizeof(buffer), "</font><img src='file://{images_econ}/%s.png'/><script>", econ_image);
	
	Protobuf msg = view_as<Protobuf>(StartMessageOne("TextMsg", client));
	
	msg.SetInt("msg_dst", 4);
	msg.AddString("params", "#SFUI_ContractKillStart");
	msg.AddString("params", buffer);
	msg.AddString("params", NULL_STRING);
	msg.AddString("params", NULL_STRING);
	msg.AddString("params", NULL_STRING);
	msg.AddString("params", NULL_STRING);
	
	EndMessage();
	
	// Show again so it won't be a small icon!
	if (first_run)
	{
		DataPack dp;
		CreateDataTimer(0.1, Timer_PrintHintEconRepeat, dp);
		dp.WriteCell(GetClientUserId(client));
		dp.WriteString(econ_image);
		dp.Reset();
	}
}

Action Timer_PrintHintEconRepeat(Handle timer, DataPack dp)
{
	int client = GetClientOfUserId(dp.ReadCell());
	if (!client)
	{
		return Plugin_Continue;
	}
	
	char econ_image[PLATFORM_MAX_PATH];
	dp.ReadString(econ_image, sizeof(econ_image));
	
	PreviewEconImage(client, econ_image, false);
	return Plugin_Continue;
}

void CacheAgents()
{
	// Clear old data.
	g_Agents.Clear();
	g_Models.Clear();
	
	// Prepare variables for the loop.
	CEconItemDefinition item_defenition;
	char type_name[32];
	Agent new_agent;
	
	for (int i = CEconItemDefinition.Count() - 1; i >= 0; i--)
	{
		if (!(item_defenition = CEconItemDefinition.Get(i)))
		{
			continue;
		}
		
		// Skip on non-agents item defenitions.
		item_defenition.GetTypeName(type_name, sizeof(type_name));
		if (!StrEqual(type_name, "#Type_CustomPlayer"))
		{
			continue;
		}
		
		// Retrieve and precache the agent model.
		item_defenition.GetModel(ViewModel, new_agent.entity_model, sizeof(Agent::entity_model));
		g_Models.PushString(new_agent.entity_model);
		
		// Don't parse default agents.
		if (StrEqual(new_agent.entity_model, DEFAULT_TERRORIST_SKIN) || StrEqual(new_agent.entity_model, DEFAULT_COUNTER_TERRORIST_SKIN))
		{
			continue;
		}
		
		// Parse basic data.
		item_defenition.GetBaseName(new_agent.base_name, sizeof(Agent::base_name));
		StringToLower(new_agent.base_name);
		if (TranslationPhraseExists(new_agent.base_name[1]))
		{
			Format(new_agent.base_name, sizeof(Agent::base_name), "%t", new_agent.base_name[1]);
		}
		else
		{
			continue;
		}
		
		item_defenition.GetDescription(new_agent.description, sizeof(Agent::description));
		StringToLower(new_agent.description);
		if (TranslationPhraseExists(new_agent.description[1]))
		{
			Format(new_agent.description, sizeof(Agent::description), "%t", new_agent.description[1]);
		}
		else
		{
			continue;
		}
		
		item_defenition.GetInventoryImage(new_agent.econ_image, sizeof(Agent::econ_image));
		
		new_agent.associated_team = item_defenition.UsedByTeam;
		
		// Calculate price by rarity.
		new_agent.price = g_RarityValue[item_defenition.ItemRarity.DBValue];
		
		g_Agents.PushArray(new_agent);
	}
	
	g_Agents.SortCustom(SortByValue);
}

void PrecacheAgentModels()
{
	char model[PLATFORM_MAX_PATH];
	for (int current_model; current_model < g_Models.Length; current_model++)
	{
		g_Models.GetString(current_model, model, sizeof(model));
		
		PrecacheModel(model);
	}
	
	g_Models.Clear();
}

/**
 * Sort comparison function for ADT Array elements. Function provides you with
 * indexes currently being sorted, use ADT Array functions to retrieve the
 * index values and compare.
 *
 * @param index1        First index to compare.
 * @param index2        Second index to compare.
 * @param array         Array that is being sorted (order is undefined).
 * @param hndl          Handle optionally passed in while sorting.
 * @return              -1 if first should go before second
 *                      0 if first is equal to second
 *                      1 if first should go after second
 */
int SortByValue(int index1, int index2, Handle array, Handle hndl)
{
	ArrayList arr = view_as<ArrayList>(array);
	
	Agent agent1; arr.GetArray(index1, agent1);
	Agent agent2; arr.GetArray(index2, agent2);
	
	return FloatCompare(float(agent2.price), float(agent1.price));
}

void StringToLower(char[] str)
{
	for (int i; str[i]; i++)
	{
		str[i] = CharToLower(str[i]);
	}
} 