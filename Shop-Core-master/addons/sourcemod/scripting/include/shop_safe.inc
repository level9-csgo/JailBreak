#if defined _shop_safe_included
 #endinput
#endif
#define _shop_safe_included

#define COMBINATION_DIGITS 4

enum struct SafeBox
{
	int code;
	int credits;
	int failures;
	char last_winner_name[MAX_NAME_LENGTH];
}

/**
 *	Retrives the safe box data struct.
 *	
 *	@param buffer			An 'SafeBox' enum struct to store the safe box data in.
*/
native void Shop_GetSafeBoxData(any[] buffer);

/**
 *	Called when a client is trying to guess the safe box combination code.
 *	
 *	@param client			Client index.
 *	@param code				The desired client combination code.
 *	@param succeed			True if the client has successfully cracked the safe box, false otherwise.
 *
 * @return					Plugin_Handled or higher to block the guess, and prevent any further actions.
*/
forward Action Shop_OnClientSafeGuess(int client, int &code, bool &succeed);

/**
 *	Called after a client has been tried to guess the safe box combination code.
 *	
 *	@param client			Client index.
 *	@param code				The desired client combination code.
 *	@param succeed			True if the client has successfully cracked the safe box, false otherwise.
*/
forward void Shop_OnClientSafeGuessPost(int client, int code, bool succeed);

public SharedPlugin __pl_shop_safe = 
{
	name = "shop_safe",
	file = "Shop_Safe.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shop_safe_SetNTVOptional()
{
	MarkNativeAsOptional("Shop_GetSafeBoxData");
}
#endif
