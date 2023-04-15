#if defined _shop_premium_included
 #endinput
#endif
#define _shop_premium_included

#define PREMIUM_WISHES_BONUS 1
#define PREMIUM_GAMBLE_BONUS_CHANCES 2
#define PREMIUM_SHOP_DISCOUNT_PERCENT 10

/**
 *	Checks if a client is a premium member.
 *	
 *	@param client			Client index to check.
 *
 *  @return 				True if the specified client is a premium member, false otherwise.
 *  @error                  If the client is not connected, an error will be thrown.
*/
native bool Shop_IsClientPremium(int client);

/**
 *	Gives a certain client premium membership.
 *	
 *	@param client			Client index to give the premium to.
 *  @param days				Amount of premium days to give.
 *
 *  @return 				True if the premium has successfully given, false otherwise.
 *  @error                  If the client is not connected, an error will be thrown.
*/
native bool Shop_GivePremium(int client, int days);

/**
 *	Removes the premium membership from a certain client.
 *	
 *	@param client			Client index to remove the premium to.
 *  @param days				Amount of premium days to remove, or -1 for complete remove.
 *
 *  @return 				True if the premium successfully removed, false otherwise.
 *  @error                  If the client is not connected, an error will be thrown.
*/
native bool Shop_RemovePremium(int client, int days);

/**
 *	Called when the premium menu is being opened.
 *	
 *	@param client			Client index to who the menu is displayed.
 *	@param menu				Dispalyed menu Handle.
*/
forward void Shop_OnPremiumMenuDispaly(int client, Menu menu);

/**
 *	Called when a client pressed an item inside the premium menu.
 *	
 *	@param client			Client index.
 *	@param menu				Menu Handle.
 *  @param itemInfo			Pressed menu item parsed information.
 *  @param item_position    Item position inside the menu.
*/
forward void Shop_OnPremiumMenuPress(int client, Menu menu, const char[] itemInfo, int item_position);

public SharedPlugin __pl_shop_premium = 
{
	name = "shop_premium",
	file = "Shop_Premium.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shop_premium_SetNTVOptional()
{
	MarkNativeAsOptional("Shop_IsClientPremium");
	MarkNativeAsOptional("Shop_GivePremium");
	MarkNativeAsOptional("Shop_RemovePremium");
}
#endif
