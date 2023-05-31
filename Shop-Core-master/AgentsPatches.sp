 // NumSupportedStickerSlots - agent
// identifier: ()

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <shop>
#include <EconAPI>

#pragma semicolon 1
#pragma newdecls required

#define PATCH_IDENTIFIER "#PatchKit_patch"

enum struct Patch
{
	// Unique patch id which will be applied later on 'm_vecPlayerPatchEconIndices'.
	int ID;
	
	// Display name after token modification.
	char base_name[64];
	
	// Description after token modification.
	char description[256];
	
	// Econ image path. Required for previewing the patch.
	char econ_image[PLATFORM_MAX_PATH];
	
	int price;
}

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

ArrayList g_Patches;

public Plugin myinfo = 
{
	name = "[Shop Integrated] Agents Patches", 
	author = "KoNLiG", 
	description = "Implemention of EconAPI to agents patches.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_Patches = new ArrayList(sizeof(Patch));
	
	LoadTranslations("localization.phrases");
	
	CachePatches();
	
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

public void Shop_Started()
{
	CategoryId category_id = Shop_RegisterCategory("agent_patches", "Agent Patches", "Shiny stickers to lie on your agent.");
	
	Patch patch;
	for (int current_patch; current_patch < g_Patches.Length; current_patch++)
	{
		g_Patches.GetArray(current_patch, patch);
		
		// Store the new patch object.
		if (Shop_StartItem(category_id, patch.base_name))
		{
			Shop_SetInfo(patch.base_name, patch.description, patch.price, patch.price / 2, Item_Togglable, 0);
			Shop_SetCallbacks(.use_toggle = OnEquipItem, .preview = OnItemPreview);
			
			Shop_SetCustomInfo("id", patch.ID);
			Shop_SetCustomInfoString("econ_image", patch.econ_image);
			
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
		// SetClientAgent(client);
	}
}

ShopAction OnEquipItem(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	/*int model_index = (category_id == g_ShopCategoryID[Agent_Prisoner] ? Agent_Prisoner : Agent_Guard);
	
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
	
	return Shop_UseOn;*/
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
}

// PrintCenterText(activator, "<font color='#A64452' class='fontSize-l'>Whow! Slow down there!</font>");
void PreviewEconImage(int client, char[] econ_image, bool first_run = true)
{
	PrintCenterText(client, "<img src='file://{images_econ}/%s.png'/>", econ_image);
	
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

void CachePatches()
{
	// Clear old data.
	g_Patches.Clear();
	
	// Prepare variables for the loop.
	CStickerKit sticker_kit;
	Patch new_patch;
	
	for (int i = CStickerKit.Count() - 1; i >= 0; i--)
	{
		if (!(sticker_kit = CStickerKit.Get(i)))
		{
			continue;
		}
		
		// Skip on non-patch sticker kits.
		sticker_kit.GetsItemName(new_patch.base_name, sizeof(Patch::base_name));
		if (StrContains(new_patch.base_name, PATCH_IDENTIFIER) == -1)
		{
			continue;
		}
		
		new_patch.ID = sticker_kit.ID;
		
		// Parse basic data.
		StringToLower(new_patch.base_name);
		if (TranslationPhraseExists(new_patch.base_name[1]))
		{
			Format(new_patch.base_name, sizeof(Patch::base_name), "%t", new_patch.base_name[1]);
		}
		else
		{
			continue;
		}
		
		sticker_kit.GetDescriptionString(new_patch.description, sizeof(Patch::description));
		StringToLower(new_patch.description);
		if (TranslationPhraseExists(new_patch.description[1]))
		{
			Format(new_patch.description, sizeof(Patch::description), "%t", new_patch.description[1]);
		}
		else
		{
			continue;
		}
		
		sticker_kit.GetInventoryImage(new_patch.econ_image, sizeof(Patch::econ_image));
		
		g_Patches.PushArray(new_patch);
	}
}

void StringToLower(char[] str)
{
	for (int i; str[i]; i++)
	{
		str[i] = CharToLower(str[i]);
	}
} 