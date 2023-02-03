#if defined _shop_jackpot_included
 #endinput
#endif
#define _shop_jackpot_included

/**
 *	Called when the jackpot results are available.
 *	
 *	@param winner			Jackpot winner client index, -1 for no winner.
 *	@param chance			Self chances for winning the bet.
 *	@param bet				Amount of credits placed in the jackpot.
 *  @param prize			Total amount of credits the winner recieved.
*/
forward void Shop_OnJackpotResults(int winner, float chance, int bet, int prize);

public SharedPlugin __pl_shop_jackpot = 
{
	name = "shop_jackpot",
	file = "Shop_Jackpot.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

/*
#if !defined REQUIRE_PLUGIN
public void __pl_shop_jackpot_SetNTVOptional()
{
}
#endif
*/