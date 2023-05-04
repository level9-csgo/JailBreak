#if defined _shop_wish_included
 #endinput
#endif
#define _shop_wish_included

enum
{
	Award_Rnd1, 
	Award_Rnd2, 
	Award_Context, 
	Award_Percent
}

char g_WishAwards[][][] = 
{
	{ "1", "7", "%d Premium Days", "0.3" }, 
	{ "3", "4", "%d✰ Rune", "8.0" }, 
	{ "45000", "60000", "%d Credits", "10.8" }, 
	{ "", "", "6✰ Rune", "0.5" }, 
	{ "5000", "20000", "%d Credits", "20.0" }, 
	{ "", "", "Guaranteed Rune Upgrade", "0.25" }, 
	{ "30000", "45000", "%d Credits", "13.0" }, 
	{ "", "", "Rewish", "15.0" }, 
	{ "55000", "70000", "%d Credits", "7.15" }, 
	{ "", "", "5✰ Rune", "5.0" }, 
	{ "20000", "30000", "%d Credits", "15.0" }, 
	{ "", "", "2 Wishes", "5.0" }
};

/**
 *	Returns the amount of wishes the client is holding in queue.
 *	
 *	@param client			Client index.
 *
 *  @return 				Amount of wishes, 0 if none.
 *  @error                  If the client is not connected, an error will be thrown.
*/
native int Shop_GetClientWishes(int client);

/**
 *	Gives a certain client a wish.
 *	
 *	@param client			Client index to give the wish to.
 *  @param amount			Amount of wishes to give the client, 1 by default.
 *
 *  @return 				True if the wish has successfully given, false otherwise.
 *  @error                  If the client is not connected, an error will be thrown.
*/
native bool Shop_GiveClientWish(int client, int amount = 1);

/**
 *	Removes a wish from a certain client.
 *	
 *	@param client			Client index to remove the wish from.
 *  @param amount			Amount of wishes to remove from the client, 1 by default.
 *
 *  @return 				True if the wish has successfully removed, false otherwise.
 *  @error                  If the client is not connected, an error will be thrown.
*/
native bool Shop_RemoveClientWish(int client, int amount = 1);

/**
 *	Called when the a rewish has exected and given to a certain client.
 *	
 *	@param client			Awarded client index.
 *	@param giver			The giver client index, will always be admin index. (Will be 0 if the rewish is natural)
 *	@param natural			True if the rewish has given by the server (natural), false otherwise.
*/
forward void Shop_OnRewishExecuted(int client, int giver, bool natural);

/**
 *	Called when a client has start a wish animation.
 *	
 *	@param client			Client index.
 *	@param wishesLeft		Amount of wishes left to spend, not includes the current.
 *  @param award_index		Wish award index.
 *
 * @return					Plugin_Handled or higher to block the pickup, and prevent any further actions.
*/
forward Action Shop_OnWishAnimationStart(int client, int wishesLeft, int award_index);

/**
 *	Called when a client has end a wish animation.
 *	
 *	@param client			Client index.
 *	@param wishesLeft		Amount of wishes left to spend, not includes the current.
 *  @param award_index		Wish award index.
*/
forward void Shop_OnWishAnimationEnd(int client, int wishesLeft, int award_index);

/**
 *	Returns formatted wish award string, and randomized award by the global variable.
 *	
 *	@param index			Wish index.
 *	@param award			An integer buffer to store the final award.
 *
 *	@return					Formatted wish award string.
*/
stock char[] GetFormattedWishAward(int index, int &award)
{
	char str[32];
	strcopy(str, sizeof(str), g_WishAwards[index][Award_Context]);
	
	if (g_WishAwards[index][Award_Rnd1][0] != '\0')
	{
		Format(str, sizeof(str), str, award = GetRandomInt(StringToInt(g_WishAwards[index][Award_Rnd1]), StringToInt(g_WishAwards[index][Award_Rnd2])));
	}
	else if ((award = StringToInt(g_WishAwards[index][Award_Context])) == 0)
	{
		award++;
	}
	
	return str;
}

/**
 *	Returns the award win percentage by the specified index.
 *	
 *	@param index			Wish index.
 *
 *	@return					Award win percentage.
*/
stock float Shop_GetWishAwardPercent(int index)
{
	return StringToFloat(g_WishAwards[index][Award_Percent]);
}

public SharedPlugin __pl_shop_wish = 
{
	name = "shop_wish",
	file = "Shop_Wish.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shop_wish_SetNTVOptional()
{
	MarkNativeAsOptional("Shop_IsClientPremium");
	MarkNativeAsOptional("Shop_GivePremium");
	MarkNativeAsOptional("Shop_RemovePremium");
}
#endif
