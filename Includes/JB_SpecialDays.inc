#if defined _JB_SpecialDays_included
 #endinput
#endif
#define _JB_SpecialDays_included

#define INVALID_DAY_WINNER -1

#define SETUP_SECONDS_TIME 7

/**
 * Creates a special day.
 * 
 * @param name               Name of the special day.
 * @param defaultHealth      Default health points set to the players of the special day.
 * @param weaponPickup       Allowing day participants to pick up weapons, false to disable.
 * @param weaponDrop         Allowing day participants to drop their weapons, false to disable.
 * @param hasSetups    		 If false, once the day is chosen it will automatically start.
 * @return                  Special day game index.
 */
native int JB_CreateSpecialDay(char[] name, int defaultHealth, bool weaponPickup, bool weaponDrop, bool hasSetups);

/**
 * Checks if a special day game is running.
 * 
 * @return            True if running, false otherwise.
 */
native bool JB_IsSpecialDayRunning();

/**
 * Checks if a special day vote is running.
 * 
 * @return            True if running, false otherwise.
 */
native bool JB_IsSpecialDayVoteRunning();

/**
 * Finds and returns the special day index, by searching the index with the given name.
 * 
 * @param name               The name for the specified special day.
 * @return                  Special day index, or -1 if there is no special day matching the given name.
 */
native int JB_FindSpecialDay(char[] name);

/**
 * Starts a special day, you should only use this native if the special day has setups.
 * 
 * @param specialDayId       Special day index.
 * @return                  True if the special day successfully started, false if there is another special day running.
 */
native bool JB_StartSpecialDay(int specialDayId);

/**
 * Stops the current running special day game.
 * 
 * @param aborted			True if the special day has aborted, means the Winner/MVP wont be announced, false otherwise.
 *
 * @return 				True if the special day game successfully stopped, false if there is no special day game running.
 *
 */
native bool JB_StopSpecialDay(bool aborted = true);

/**
 * Called when the special day vote has ended.
 * 
 * @param specialDayId              The chosen special day index.
 */
forward void JB_OnSpecialDayVoteEnd(int specialDayId);

/**
 * Called when a special day is starting.
 * 
 * @param specialDayId              Special day index.
 */
forward void JB_OnSpecialDayStart(int specialDayId);

/**
 * Called when a special day has end.
 * 
 * @param specialDayId              Special day index.
 * @param winner           		    Special day winner index, or INVALID_DAY_WINNER if there is no winner. (Day has aborted)
 * @param dayName           		Special day display name.
 * @param aborted           	    True if an admin has stopped the day, false otherwise.
 * @param countdown           	    True if the special day has stopped in the middle of the start countdown, false otherwise.
 */
forward void JB_OnSpecialDayEnd(int specialDayId, const char[] dayName, int winner, bool aborted, bool countdown);

/**
 * Called after the player has setup for a special day. (Disarm, Weapon equipment, etc...)
 * 
 * @param client              		Client index.
 * @param specialDayId              Special day index.
 */
forward void JB_OnClientSetupSpecialDay(int client, int specialDayId);

#include <sdkhooks>

/**
 * An alternative for the function 'SDKHooks_TakeDamage()', but this function calls damage hooks. (OnTakeDamage, TraceAttack, etc...)
 * 
 * @param entity              		Victim index.
 * @param attacker             		Attacker index.
 * @param damage					Damage to hurt.
 * @param damageType				Damage type to send, DMG_GENERIC by default.
 */
stock void JB_DealDamage(int entity, int attacker, float damage, int damageType = DMG_GENERIC, char[] classname = "")
{
	char damageStr[8];
	FloatToString(damage, damageStr, sizeof(damageStr));
	
	char damageTypeStr[11];
	IntToString(damageType, damageTypeStr, sizeof(damageTypeStr));
	
	int pointHurt = CreateEntityByName("point_hurt");
	
	if (pointHurt == -1)
	{
		return;
	}
	
	DispatchKeyValue(entity, "targetname", "war3_hurtme");
	DispatchKeyValue(pointHurt, "DamageTarget", "war3_hurtme");
	DispatchKeyValue(pointHurt, "Damage", damageStr);
	DispatchKeyValue(pointHurt, "DamageType", damageTypeStr);
	
	DispatchSpawn(pointHurt);
	AcceptEntityInput(pointHurt, "Hurt", attacker);
	DispatchKeyValue(pointHurt, "classname", classname[0] ? classname : "point_hurt");
	DispatchKeyValue(entity, "targetname", "war3_donthurtme");
	RemoveEdict(pointHurt);
}

#if !defined REQUIRE_PLUGIN
public void __pl_JB_SpecialDays_SetNTVOptional()
{
	MarkNativeAsOptional("JB_CreateSpecialDay");
	MarkNativeAsOptional("JB_IsSpecialDayRunning");
	MarkNativeAsOptional("JB_IsSpecialDayVoteRunning");
	MarkNativeAsOptional("JB_FindSpecialDay");
	MarkNativeAsOptional("JB_StartSpecialDay");
	MarkNativeAsOptional("JB_StopSpecialDay");
}
#endif

public SharedPlugin __pl_JB_SpecialDays = 
{
	name = "JB_SpecialDays", 
	file = "JB_SpecialDays.smx", 
#if defined REQUIRE_PLUGIN
    required = 1, 
#else
    required = 0, 
#endif
}; 