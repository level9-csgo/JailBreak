/*
	Library of the [Shop] Core v3
	Author: FrozDark
	www.hlmod.ru
*/

#if defined _shop_included
 #endinput
#endif
#define _shop_included

#define SHOP_MAX_STRING_LENGTH	64

enum CategoryId
{
	INVALID_CATEGORY = -1
}

enum ItemId
{
	INVALID_ITEM = 0
}

enum ItemType
{
	Item_None = 0,		/**< Can not be used */
	Item_Finite = 1,	/**< Can be used like a medkit */
	Item_Togglable = 2,	/**< Can be switched on or off */
	Item_BuyOnly = 3	/**< Only for buy */
}

enum ToggleState
{
	Toggle,
	Toggle_On,
	Toggle_Off
}

enum ShopAction
{
	Shop_Raw = 0,
	Shop_UseOn = 1,
	Shop_UseOff = 2
}

enum ShopMenu
{
	Menu_Main,
	Menu_Buy,
	Menu_Inventory,
	Menu_Functions,
	Menu_ExtraFunctions,
	Menu_AdminPanel,
	Menu_CreditsTransfer,
	Menu_ItemTransfer
}

#define	IGNORE_FORWARD_HOOK	-5				//**< Param to set to avoid calling forward hook */
#define	CREDITS_BY_LUCK	-4					//**< Credits being processed by item luck */
#define	CREDITS_BY_TRANSFER	-3				//**< Credits being processed by credits transfer */
#define	CREDITS_BY_BUY_OR_SELL	-2			//**< Credits being processed by buying or selling an item */
#define	CREDITS_BY_NATIVE	-1				//**< Credits being processed by native */
#define	CREDITS_BY_COMMAND	0				//**< Credits being processed by server console or rcon command */
//**< Any higher value is admin index */

#include <shop/admin>
#include <shop/functions>
#include <shop/db>
#include <shop/items>
#include <shop/players>
#include <shop/register>
#include <regex>

/**
 *	Called when the shop is ready to register items
 *	
 *	@noparams
 *	
 *	@noreturn
*/
forward void Shop_Started();

/**
 *	Checks whether the shop has been started
 *	
 *	@noparams
 *	
 *	@return	True if the shop is already started, false otherwise
*/
native bool Shop_IsStarted();

/**
 *	This must be called on PluginEnd. Fully unregisters the plugin. Unregisters items, categories and removes them from the shop and players' inventory
 *	
 *	@noparams
 *	
 *	@noreturn
*/
native void Shop_UnregisterMe();

/**
 *	Get path to the main config folder of the Shop
 *	
 *	@param buffer			Buffer to store the path in
 *	@param size				Max buffer length
 *	@param file				File to retrieve the path for
 *	
 *	@noreturn
*/
stock void Shop_GetCfgFile(char[] buffer, int size, const char[] file)
{
	BuildPath(Path_SM, buffer, size, "configs/shop/%s", file);
}

/**
 *	Adds seperators to the specified integer.
 *	
 *	@param value			Integer value to add the seperators to.
 *	@param seperator		The string seperator.
 *	
 *	@return					Seperated string.
*/
stock char AddCommas(int value, const char[] seperator = ",")
{
	// Static regex insted of a global one.
	static Regex rgxCommasPostions = null;
	
	// Complie our regex only once.
	if (!rgxCommasPostions)
		rgxCommasPostions = CompileRegex("\\d{1,3}(?=(\\d{3})+(?!\\d))");
	
	// The buffer that will store the number so we can use the regex.
	char buffer[MAX_NAME_LENGTH];
	IntToString(value, buffer, MAX_NAME_LENGTH);
	
	// perform the regex.
	rgxCommasPostions.MatchAll(buffer);
	
	// Loop through all Offsets
	for (int iCurrentOffset = 0; iCurrentOffset < rgxCommasPostions.MatchCount(); iCurrentOffset++)
	{
		// Get the offset.
		int offset = rgxCommasPostions.MatchOffset(iCurrentOffset);
		
		offset += iCurrentOffset;
		
		// Insert seperator.
		Format(buffer[offset], sizeof(buffer) - offset, "%c%s", seperator, buffer[offset]);
	}
	
	// Return buffer
	return buffer;
}

stock void WriteLogLine(const char[] log, any...)
{
	char szLogLine[512];
	VFormat(szLogLine, sizeof(szLogLine), log, 2);
	
	static char szPath[128];
	if (strlen(szPath) < 1)
	{
		char szFileName[64];
		GetPluginFilename(INVALID_HANDLE, szFileName, sizeof(szFileName));
		ReplaceString(szFileName, sizeof(szFileName), ".smx", "");
		
		FormatTime(szPath, sizeof(szPath), "%Y%m%d", GetTime());
		BuildPath(Path_SM, szPath, sizeof(szPath), "logs/%s_%s.log", szFileName, szPath);
	}
	
	LogToFile(szPath, szLogLine);
}

/**
 *	Fixes the menu items gap. Can be caused from the exit back button.
 *	
 *	@param menu				Menu handle to fix.
 *	
 *	@noreturn
*/
stock void FixMenuGap(Menu menu)
{
	int iItemCount = menu.ItemCount;
	for (int iCurrentItem = 0; iCurrentItem < (6 - iItemCount); iCurrentItem++) {
		menu.AddItem("", "", ITEMDRAW_NOTEXT); // Fix the back button gap.
	}
}

public SharedPlugin __pl_shop = 
{
	name = "shop",
	file = "shop.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shop_SetNTVOptional()
{
	MarkNativeAsOptional("Shop_IsStarted");
	MarkNativeAsOptional("Shop_UnregisterMe");
	MarkNativeAsOptional("Shop_ShowItemPanel");
	MarkNativeAsOptional("Shop_OpenMainMenu");
	MarkNativeAsOptional("Shop_ShowCategory");
	MarkNativeAsOptional("Shop_ShowInventory");
	MarkNativeAsOptional("Shop_ShowItemsOfCategory");
	MarkNativeAsOptional("Shop_GetDatabase");
	MarkNativeAsOptional("Shop_GetDatabasePrefix");
	
	MarkNativeAsOptional("Shop_ShowAdminMenu");
	MarkNativeAsOptional("Shop_AddToAdminMenu");
	MarkNativeAsOptional("Shop_RemoveFromAdminMenu");
	
	MarkNativeAsOptional("Shop_ShowFunctionsMenu");
	MarkNativeAsOptional("Shop_AddToFunctionsMenu");
	MarkNativeAsOptional("Shop_RemoveFromFunctionsMenu");
	
	MarkNativeAsOptional("Shop_RegisterCategory");
	MarkNativeAsOptional("Shop_StartItem");
	MarkNativeAsOptional("Shop_SetInfo");
	MarkNativeAsOptional("Shop_SetLuckChance");
	MarkNativeAsOptional("Shop_SetCallbacks");
	MarkNativeAsOptional("Shop_SetCustomInfo");
	MarkNativeAsOptional("Shop_SetCustomInfoFloat");
	MarkNativeAsOptional("Shop_SetCustomInfoString");
	MarkNativeAsOptional("Shop_KvCopySubKeysCustomInfo");
	MarkNativeAsOptional("Shop_EndItem");
	
	MarkNativeAsOptional("Shop_GetItemCustomInfo");
	MarkNativeAsOptional("Shop_SetItemCustomInfo");
	MarkNativeAsOptional("Shop_GetItemCustomInfoFloat");
	MarkNativeAsOptional("Shop_SetItemCustomInfoFloat");
	MarkNativeAsOptional("Shop_GetItemCustomInfoString");
	MarkNativeAsOptional("Shop_SetItemCustomInfoString");
	MarkNativeAsOptional("Shop_KvCopySubKeysItemCustomInfo");
	MarkNativeAsOptional("Shop_GetItemPrice");
	MarkNativeAsOptional("Shop_SetItemPrice");
	MarkNativeAsOptional("Shop_GetItemGoldPrice");
	MarkNativeAsOptional("Shop_SetItemGoldPrice");
	MarkNativeAsOptional("Shop_GetItemSellPrice");
	MarkNativeAsOptional("Shop_SetItemSellPrice");
	MarkNativeAsOptional("Shop_GetItemGoldSellPrice");
	MarkNativeAsOptional("Shop_SetItemGoldSellPrice");
	MarkNativeAsOptional("Shop_GetItemLuckChance");
	MarkNativeAsOptional("Shop_SetItemLuckChance");
	MarkNativeAsOptional("Shop_GetItemValue");
	MarkNativeAsOptional("Shop_SetItemValue");
	MarkNativeAsOptional("Shop_IsItemExists");
	MarkNativeAsOptional("Shop_IsValidCategory");
	MarkNativeAsOptional("Shop_GetItemId");
	MarkNativeAsOptional("Shop_GetItemById");
	MarkNativeAsOptional("Shop_GetItemType");
	MarkNativeAsOptional("Shop_GetItemCategoryId");
	MarkNativeAsOptional("Shop_GetCategoryId");
	MarkNativeAsOptional("Shop_GetCategoryById");
	MarkNativeAsOptional("Shop_GetCategoryNameById");
	MarkNativeAsOptional("Shop_FillArrayByItems");
	MarkNativeAsOptional("Shop_FormatItem");
	
	MarkNativeAsOptional("Shop_GetClientId");
	MarkNativeAsOptional("Shop_SetClientItemTimeleft");
	MarkNativeAsOptional("Shop_GetClientItemTimeleft");
	MarkNativeAsOptional("Shop_GetClientItemSellPrice");
	MarkNativeAsOptional("Shop_IsClientItemToggled");
	MarkNativeAsOptional("Shop_IsClientHasItem");
	MarkNativeAsOptional("Shop_ToggleClientItem");
	MarkNativeAsOptional("Shop_ToggleClientCategoryOff");
	MarkNativeAsOptional("Shop_IsAuthorized");
	MarkNativeAsOptional("Shop_IsAdmin");
	MarkNativeAsOptional("Shop_GiveClientCredits");
	MarkNativeAsOptional("Shop_TakeClientCredits");
	MarkNativeAsOptional("Shop_GetClientCredits");
	MarkNativeAsOptional("Shop_SetClientCredits");
	MarkNativeAsOptional("Shop_GiveClientGold");
	MarkNativeAsOptional("Shop_TakeClientGold");
	MarkNativeAsOptional("Shop_GetClientGold");
	MarkNativeAsOptional("Shop_SetClientGold");
	MarkNativeAsOptional("Shop_GiveClientItem");
	MarkNativeAsOptional("Shop_BuyClientItem");
	MarkNativeAsOptional("Shop_SellClientItem");
	MarkNativeAsOptional("Shop_RemoveClientItem");
	MarkNativeAsOptional("Shop_GetClientItemCount");
	MarkNativeAsOptional("Shop_UseClientItem");
	MarkNativeAsOptional("Shop_SetHide");
}
#endif
