#include <sourcemod>
#include <shop>
#include <RareAnimationController>

#pragma semicolon 1
#pragma newdecls required

bool g_ClientOwnRareInspectAnimation[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "[Shop Integrated] Rare Inspect Animation", 
	author = "KoNLiG", 
	description = "Unlocks for players the ability to trigger rare inspect animations manually.", 
	version = "1.0.0", 
	url = "https://steamcommunity.com/id/KoNLiG || Discord: KoNLiG#6417"
};

public void OnPluginStart()
{
	if (Shop_IsStarted())
	{
		Shop_Started();
	}
}

public void OnPluginEnd()
{
	Shop_UnregisterMe();
}

public void Shop_Started()
{
	CategoryId shop_category_id = Shop_RegisterCategory("misc", "Misc", "Miscellaneous shop items with special benefits.");
	if (Shop_StartItem(shop_category_id, "Rare Inspect Animation"))
	{
		Shop_SetInfo("Rare Inspect Animation", "Displays the rare item animation on double inpect key press. (F by default)", 350000, 85000, Item_Togglable, 0);
		Shop_SetCallbacks(.use_toggle = OnEquipItem);
		Shop_EndItem();
	}
}

ShopAction OnEquipItem(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	if (isOn)
	{
		g_ClientOwnRareInspectAnimation[client] = false;
		return Shop_UseOff;
	}
	
	g_ClientOwnRareInspectAnimation[client] = true;
	
	Shop_ToggleClientCategoryOff(client, category_id);
	return Shop_UseOn;
}

public Action OnRareAnimation(int client, int weapon, int sequence_type, int sequence_index, float duration)
{
	return g_ClientOwnRareInspectAnimation[client] ? Plugin_Continue : Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
	g_ClientOwnRareInspectAnimation[client] = false;
} 