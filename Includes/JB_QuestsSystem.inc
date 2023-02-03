#if defined _JB_QuestsSystem_included_
 #endinput
#endif
#define _JB_QuestsSystem_included_

enum
{
	QuestType_Daily = 0, 
	QuestType_Weekly,
	QuestType_Max
}

enum ExecuteType
{
	ExecuteType_Pre,
	ExecuteType_Post
}

enum struct QuestStats
{
	bool is_quest_skipped;
	bool is_quest_reward_claimed;
	int reward_amount;
	int quest_progress;
	int quest_target_progress;
}

/**
 * Creates a new quest mission.
 * 
 * @param unique             Unique phrase for the quest.
 * @param name               Display name for the quest.
 * @param desc        		 Description for the quest, must contain {progress} which represented the progress.
 *							 For example, "Kill {progress} players." -> "Kill 35 players."
 * @param type               Duration of time type for the quest, see the enum above.
 * @param skip_price		 The charge price for skipping the quest.
 * @param min_progress       Minimum possible target progress for the quest.
 * @param max_progress       Maximum possible target progress for the quest.
 *
 * @return                	 Created quest index.
 */
native int JB_CreateQuest(char[] unique, char[] name, char[] desc, int type, int skip_price, int min_progress, int max_progress);

/**
 * Finds and returns the quest index, by searching the index with the given quest unique.
 * 
 * @param unique             Quest unique.
 *
 * @return                   Quest index, or -1 if there is no quest matching the given unique.
 */
native int JB_FindQuest(char[] unique);

/**
 * Gets a client progress from a certain quest.
 * 
 * @param client             Client Index.
 * @param quest_id           Quest index to get the progress from.
 *
 * @return                   The client quest progress points.
 * @error          			 If the client is not connected or the specified quest index is invalid, an error will be thrown.
 */
native int JB_GetQuestProgress(int client, int quest_id);

/**
 * Adds quest progress points to a certain client.
 * 
 * @param client          	 Client index.
 * @param quest_id        	 Quest index to add the progress to.
 * @param progress        	 Progress points amount to add.
 * 
 * @return               	 True on success, false otherwise.
 * @error          			 If the client is not connected or the specified quest index is invalid, an error will be thrown.
 */
native bool JB_AddQuestProgress(int client, int quest_id, int progress = 1);

/**
 * Takes quest progress points from a certain client.
 * 
 * @param client          	 Client index.
 * @param quest_id        	 Quest index to take the progress from.
 * @param progress        	 Progress points amount to take.
 * 
 * @return               	 True on success, false otherwise.
 * @error          			 If the client is not connected or the specified quest index is invalid, an error will be thrown.
 */
native bool JB_TakeQuestProgress(int client, int quest_id, int progress = 1);

/**
 * Sets quest progress points to a certain client.
 * 
 * @param client          	 Client index.
 * @param quest_id        	 Quest index to set the progress to.
 * @param progress        	 Progress points amount to set.
 * 
 * @return               	 True on success, false otherwise.
 * @error          			 If the client is not connected or the specified quest index is invalid, an error will be thrown.
 */
native bool JB_SetQuestProgress(int client, int quest_id, int progress);

/**
 * Gets the quest stats from a certain client data.
 * 
 * @param client          	 Client index.
 * @param quest_id        	 Quest index to get the stats data from.
 * @param buffer        	 'QuestStats' data struct to store the quest stats data.
 * 
 * @error          			 If the client is not connected or the specified quest index is invalid, an error will be thrown.
 */
native void JB_GetClientQuestStats(int client, int quest_id, any[] buffer);

/**
 * Called when a quests type has reset.
 * 
 * @param type            The type of the quests that has been reset, see the enum above.
 */
forward void JB_OnQuestsReset(int quests_type);

/**
 * Called when a quest reward string is displayed to a client.
 * 
 * @param client            Client index.
 * @param quest_id        	Quest index.
 * @param display_text		Reward display text string.
 * @param length			Reward display text string length.
 * @param execute_type		Forward execute type, see the enum above.
 */
forward void JB_OnQuestRewardDisplay(int client, int quest_id, char[] display_text, int length, ExecuteType execute_type);

/**
 * Called when a client is claiming a quest reward.
 * 
 * @param client            Client index.
 * @param quest_id        	Quest index.
 * @param display_text		Reward display text string.
 * @param length			Reward display text string length.
 * @param execute_type		Forward execute type, see the enum above.
 */
forward void JB_OnQuestRewardClaim(int client, int quest_id, char[] display_text, int length, ExecuteType execute_type);

/**
 * Called when a quest assigned is claiming a quest reward.
 * 
 * @param client            Client index.
 * @param quest_id        	Quest index.
 * @param target_progress	Quest target progress points for completion.
 * @param reward			Represents the amount of given rewards for the quest. (Example: 1-x Credits)
 *							Note that in pre execute type this will always be equal to 0, and the plugin must to place a reward.
 *
 * @param execute_type		Forward execute type, see the enum above.
 */
forward void JB_OnQuestAssigned(int client, int quest_id, int target_progress, int &reward, ExecuteType execute_type);

/**
 * Rounds an integer variable value with the given divider.
 * 
 * @param value          	 Variable start value.
 * @param divider        	 Number to divide the value with, or 0 for auto divide.
 * 
 * @return               	 Rounded value.
 */
stock int RoundToDivider(int value, int divider = 0)
{
	if (!divider)
	{
		divider = (value < 1000 ? 100 : value > 100000 ? 10000 : 1000);
	}
	
	if (value % divider != 0 && value >= 5)
	{
		if (value % divider >= divider / 2 || value - value % divider == 0)
		{
			value += divider - value % divider;
		}
		else
		{
			value -= value % divider;
		}
	}
	
	return value;
}

#if !defined REQUIRE_PLUGIN
public void __pl_JB_QuestsSystem_SetNTVOptional()
{
	MarkNativeAsOptional("JB_CreateQuest");
	MarkNativeAsOptional("JB_FindQuest");
	MarkNativeAsOptional("JB_GetQuestProgress");
	MarkNativeAsOptional("JB_AddQuestProgress");
	MarkNativeAsOptional("JB_TakeQuestProgress");
	MarkNativeAsOptional("JB_SetQuestProgress");
	MarkNativeAsOptional("JB_GetClientQuestStats");
}
#endif

public SharedPlugin __pl_JB_QuestsSystem = 
{
	name = "JB_QuestsSystem", 
	file = "JB_QuestsSystem.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
}; 