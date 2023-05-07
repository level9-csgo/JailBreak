#if defined _JB_NetWorth_included
 #endinput
#endif
#define _JB_NetWorth_included

#define JB_NETWORTH_LIBRARY_NAME "JB_NetWorth"

/**
 * 	Called after a player's networth has been successfully calculated.
 *
 *	@param account_id		Target steam account id.
 *	@param target_name		Target steam name.
 *	@param data          	Handle or value passed to JB_GetPlayerNetWorth() when was called.
 *	@param total_net_worth  Total net worth in credits.
 *	@param credits  		Credits amount.
 *	@param shop_items_value Shop items value sum.
 *	@param runes_value 		Runes inventory value sum.
 *	@param response_time	Response time of all 3 data queries.
*/
typedef PlayerNetWorthSuccessCallback = function void (int account_id, const char[] target_name, any data, int total_net_worth, int credits, int shop_items_value, int runes_value, float response_time);

/**
 * 	Called after a player's networth calculation has been failed.
 *
 *	@param account_id		Target steam account id.
 *	@param data          	Handle or value passed to JB_GetPlayerNetWorth() when was called.
 *	@param response_time	Response time of all 3 data queries.
*/
typedef PlayerNetWorthFailureCallback = function void (int account_id, any data, float response_time);

/**
 * Issues a request to calculate a player's total networth.
 * 
 * @param account_id        Player account id. (GetSteamAccountID())
 * @param success_callback  Callback if the networth has been successfully calculated. Pass 'INVALID_FUNCTION' if unrelevant.
 * @param failure_callback  Callback if the networth has been failed calculated. Pass 'INVALID_FUNCTION' if unrelevant.
 * @param data          	Handle or value to pass through to the success/failure callback function.
 *
 * @error                   Null account id or both callback pointers are invalid.
 */
native void JB_GetPlayerNetWorth(int account_id, PlayerNetWorthSuccessCallback success_callback, PlayerNetWorthFailureCallback failure_callback, any data = 0);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_NetWorth_SetNTVOptional()
{
	MarkNativeAsOptional("JB_GetPlayerNetWorth");
}
#endif

public SharedPlugin __pl_JB_NetWorth = 
{
	name = JB_NETWORTH_LIBRARY_NAME, 
	file = "JB_NetWorth.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
}; 