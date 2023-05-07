#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <JailBreak>
#include <shop>
#include <multicolors>
#include <rtler>
#include <basecomm>

#define PLUGIN_AUTHOR "KoNLiG"

//==========[ Settings ]==========//

#define CONFIG_PATH "addons/sourcemod/configs/ChatBotData.cfg"

#define BOT_PREFIX " \x02[BOT]\x01"
#define BOT_NAME_EN "moti"
#define BOT_NAME_HE "מוטי"

#define MAX_TRIGGER_WORDS 4
#define MAX_ANSWERS 4

#define ABORT_SYMBOL "-1"

//====================//

enum
{
	Edit_None, 
	Edit_Trigger, 
	Edit_Answer, 
	Edit_Max
}

enum struct Sentence
{
	char trigger_1[64];
	char trigger_2[64];
	char trigger_3[64];
	char trigger_4[64];
	
	char answer_1[128];
	char answer_2[128];
	char answer_3[128];
	char answer_4[128];
	
	void Reset() {
		this.trigger_1[0] = '\0';
		this.trigger_2[0] = '\0';
		this.trigger_3[0] = '\0';
		this.trigger_4[0] = '\0';
		
		this.answer_1[0] = '\0';
		this.answer_2[0] = '\0';
		this.answer_3[0] = '\0';
		this.answer_4[0] = '\0';
	}
}

enum struct Client
{
	Sentence EditSentenceData;
	
	int edit_state;
	int current_edit_index[Edit_Max];
	int NextCreditsRequest;
	
	void Reset() {
		this.EditSentenceData.Reset();
		this.edit_state = Edit_None;
		
		for (int current_edit = 0; current_edit < Edit_Max; current_edit++)
		{
			this.current_edit_index[current_edit] = Edit_None;
		}
	}
}

Client g_ClientsData[MAXPLAYERS + 1];

ArrayList g_BotSentences;

Handle g_ChatSilenceTimer = INVALID_HANDLE;

ConVar g_cvCreditsRequestCooldown;
ConVar g_cvMinCreditsRequest;
ConVar g_cvMaxCreditsRequest;
ConVar g_cvChatSilenceMsgTime;
ConVar jb_bot_tip_interval;

// Stores the steam account id of authorized clients for commands
int g_AuthorizedClients[] = 
{
	912414245,  // KoNLiG 
	928490446 // Ravid
};

char g_Tips[][] = 
{
	" \x07אל תשכח!\x01 - לכתוב \x04/gc\x01 כל סיבוב מחדש כדי שתרדו לי מהגב", 
	" \x07הידעת?\x01 - אם שוטר הורג אותך ללא סיבה מוצדקת, רשום \x02/fk\x01 והאדמין ידאג לך", 
	" \x07באמא שלי כל השרת הזה מכור להימורים\x01 - \x04'/gamble'\x01 ו \x04'/xgamble'\x01!", 
	"!\x04/gang\x01 באמא שלי למי שאין גאנג לא ישרוד פה יומיים, כתבו", 
	" \x07אל תשכח!\x01 - לכתוב \x04/wish\x01 כל יום, מי יודע אולי תזכה ברון 6 כוכבים?", 
	" \x07הידעת?\x01 - רוצה לכבות את השירים בדיי לתמיד? כתוב \x04/settings\x01.", 
	"החבר לתא יותר חתיך? כתוב \x04/shop\x01!", 
	"מרגיש שהגאמבל שבור? עזוב אותך ותעבור ל \x04/cf\x01.", 
	"הסיטי חונק? תנסה \x04/rps, /pong, /snake\x01", 
	" \x07הידעת?\x01 - שלח לחבר שלך הודעה פרטית עם \x04/pm\x01 ותפסיק לזיין את המוח בשרת.", 
	" \x07הידעת?\x01 - חבר שלך חופר לך בפרטי? דפוק לו בלוק! \x02/blockpm\x01", 
	" אין לך מזל עם רונים? קנה ב \x04/ah\x01!", 
	" באמא שלי המשימות שיצאו לי ב \x04/quests\x01 לא הגיוניות.", 
};

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Chat Bot", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = JAILBREAK_VERSION, 
	url = "https://steamcommunity.com/id/KoNLiG/ || KoNLiG#6417"
};

public void OnPluginStart()
{
	g_BotSentences = new ArrayList(sizeof(Sentence));
	
	// ConVars Configurate
	g_cvCreditsRequestCooldown = CreateConVar("jb_bot_cash_request_cd", "300", "Time (in seconds) for the cooldown once a client requested credits from the bot.");
	g_cvMinCreditsRequest = CreateConVar("jb_bot_min_credits_request", "599", "Mimimum possible cash amount that client can get from the bot.");
	g_cvMaxCreditsRequest = CreateConVar("jb_bot_max_credits_request", "999", "Maximum possible cash amount that client can get from the bot.");
	g_cvChatSilenceMsgTime = CreateConVar("jb_bot_chat_silence_msg_time", "60", "Time (in seconds) for any player to send a message in chat, for the bot to send a message about it.");
	jb_bot_tip_interval = CreateConVar("jb_bot_tip_interval", "300", "Time in seconds between tip chat messages.");
	
	AutoExecConfig(true, "ChatBot", "JailBreak");
	
	// Admin Commands
	RegAdminCmd("sm_bot", Command_Bot, ADMFLAG_ROOT, "Access the server bot main menu.");
	
	// Create the chat silence timer
	g_ChatSilenceTimer = CreateTimer(g_cvChatSilenceMsgTime.FloatValue, Timer_ChatSilence);
	
	// Config Creation
	char szDirPath[PLATFORM_MAX_PATH];
	strcopy(szDirPath, sizeof(szDirPath), CONFIG_PATH);
	BuildPath(Path_SM, szDirPath, sizeof(szDirPath), szDirPath[17]);
	delete OpenFile(szDirPath, "a+");
	
	CreateTimer(jb_bot_tip_interval.FloatValue, Timer_SendTipMessage, .flags = TIMER_REPEAT);
}

//================================[ Events ]================================//

public void OnMapStart()
{
	KV_LoadBotSentences();
}

public void OnClientPostAdminCheck(int client)
{
	g_ClientsData[client].Reset();
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// Make sure the client's edit state isn't none
	if (g_ClientsData[client].edit_state != Edit_None)
	{
		// Check for the abort symbol inside the arguments
		if (StrEqual(sArgs, ABORT_SYMBOL))
		{
			// Notify the client
			PrintToChat(client, "%s Operation aborted!", PREFIX);
			
			// Reset the client edit state variable
			g_ClientsData[client].edit_state = Edit_None;
			
			// Dispaly the sentence creation menu
			ShowCreateSentenceMenu(client);
			
			// Block the message send
			return Plugin_Handled;
		}
		
		switch (g_ClientsData[client].edit_state)
		{
			case Edit_Trigger:
			{
				switch (g_ClientsData[client].current_edit_index[Edit_Trigger])
				{
					case 0:strcopy(g_ClientsData[client].EditSentenceData.trigger_1, sizeof(Sentence::trigger_1), sArgs);
					case 1:strcopy(g_ClientsData[client].EditSentenceData.trigger_2, sizeof(Sentence::trigger_2), sArgs);
					case 2:strcopy(g_ClientsData[client].EditSentenceData.trigger_3, sizeof(Sentence::trigger_3), sArgs);
					case 3:strcopy(g_ClientsData[client].EditSentenceData.trigger_4, sizeof(Sentence::trigger_4), sArgs);
				}
			}
			case Edit_Answer:
			{
				switch (g_ClientsData[client].current_edit_index[Edit_Answer])
				{
					case 0:strcopy(g_ClientsData[client].EditSentenceData.answer_1, sizeof(Sentence::answer_1), sArgs);
					case 1:strcopy(g_ClientsData[client].EditSentenceData.answer_2, sizeof(Sentence::answer_2), sArgs);
					case 2:strcopy(g_ClientsData[client].EditSentenceData.answer_3, sizeof(Sentence::answer_3), sArgs);
					case 3:strcopy(g_ClientsData[client].EditSentenceData.answer_4, sizeof(Sentence::answer_4), sArgs);
				}
			}
		}
		
		// Reset the client edit state variable
		g_ClientsData[client].edit_state = Edit_None;
		
		// Dispaly the sentence creation menu
		ShowCreateSentenceMenu(client);
		
		// Block the message send
		return Plugin_Handled;
	}
	
	RecreateChatSilenceTimer();
	
	if (StrEqual(command, "say") && sArgs[0] != '~' && !BaseComm_IsClientGagged(client) && (StrContains(sArgs, BOT_NAME_EN, false) != -1 || StrContains(sArgs, BOT_NAME_HE, false) != -1))
	{
		char args_exp[128];
		strcopy(args_exp, sizeof(args_exp), sArgs);
		ReplaceString(args_exp, sizeof(args_exp), StrContains(sArgs, BOT_NAME_EN, false) != -1 ? BOT_NAME_EN : BOT_NAME_HE, "");
		
		int sentence_index = -1;
		
		if (strlen(args_exp) <= 1)
		{
			BotAnswerNoArgs(client);
		}
		else if ((sentence_index = CheckForTriggerWord(sArgs)) != -1)
		{
			AnswerToSentence(sentence_index);
		}
		else if (StrContains(sArgs, "credits", false) != -1 || StrContains(sArgs, "קרדיטס", false) != -1 || StrContains(sArgs, "כסף", false) != -1 || StrContains(sArgs, "money", false) != -1)
		{
			BotAnswerCredits(client);
		}
		else if (StrContains(sArgs, "time", false) != -1 || StrContains(sArgs, "שעה", false) != -1)
		{
			BotAnswerTime(client);
		}
		else if ((StrContains(sArgs, "whats", false) != -1 || StrContains(sArgs, "מה", false) != -1 || StrContains(sArgs, "איך", false) != -1) && (StrContains(sArgs, "up", false) != -1 || StrContains(sArgs, "קורה", false) != -1 || (StrContains(sArgs, "איתך", false) != -1 || StrContains(sArgs, "הולך", false) != -1 || StrContains(sArgs, "ניש", false) != -1 || StrContains(sArgs, "אתה", false) != -1 || StrContains(sArgs, "אומר", false) != -1)))
		{
			BotAnswerHowAreYou();
		}
		else
		{
			BotAnswerRandom();
		}
	}
	
	return Plugin_Continue;
}

//================================[ Commands ]================================//

public Action Command_Bot(int client, int args)
{
	// Deny the command access from the console
	if (!client)
	{
		return Plugin_Handled;
	}
	
	// Block the command access if the client isn't allowed
	if (!IsClientAllowed(client))
	{
		PrintToChat(client, "%s You do not have access to this command.", PREFIX_ERROR);
		return Plugin_Handled;
	}
	
	if (args == 1)
	{
		// Block the feature to administrators only
		if (GetUserAdmin(client) == INVALID_ADMIN_ID)
		{
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char arg_name[MAX_NAME_LENGTH];
		GetCmdArgString(arg_name, sizeof(arg_name));
		int target_index = FindTarget(client, arg_name, true, false);
		
		if (target_index == -1)
		{
			// Automated message
			return Plugin_Handled;
		}
		
		if (!IsClientAllowed(target_index)) {
			PrintToChat(client, "%s The player do not have access to this command.", PREFIX_ERROR);
		} else {
			ShowBotMainMenu(target_index);
		}
	}
	else
	{
		ShowBotMainMenu(client);
	}
	
	return Plugin_Handled;
}

//================================[ Menus ]================================//

void ShowBotMainMenu(int client)
{
	char item_display[32];
	Menu menu = new Menu(Handler_BotMain);
	menu.SetTitle("%s Chat Bot - Main Menu\n ", PREFIX_MENU);
	
	menu.AddItem("", "Create New Sentence");
	menu.AddItem("", "Reload Bot Data\n ");
	
	// Loop through all the bot sentences, add insert them into the menu
	for (int current_sentence = 0; current_sentence < g_BotSentences.Length; current_sentence++)
	{
		FormatEx(item_display, sizeof(item_display), "Sentence #%d", current_sentence + 1);
		menu.AddItem("", item_display);
	}
	
	// If no bot sentence was found, add an extra notify menu item
	if (menu.ItemCount == 2)
	{
		menu.AddItem("", "No bot sentence was found.", ITEMDRAW_DISABLED);
	}
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_BotMain(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		switch (item_position)
		{
			case 0:
			{
				ShowCreateSentenceMenu(client);
			}
			case 1:
			{
				// Reload the bot configuartion file
				KV_LoadBotSentences();
				
				// Notify the client
				PrintToChat(client, "%s Successfully reload the bot configuration file!", PREFIX);
			}
			default:
			{
				ShowSentenceDetailMenu(client, item_position - 2);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	return 0;
}

void ShowCreateSentenceMenu(int client)
{
	char item_display[128];
	Menu menu = new Menu(Handler_CreateSentence);
	menu.SetTitle("%s Chat Bot - Sentence Creation\n ", PREFIX_MENU);
	
	switch (g_ClientsData[client].current_edit_index[Edit_Trigger])
	{
		case 0:Format(item_display, sizeof(item_display), g_ClientsData[client].EditSentenceData.trigger_1);
		case 1:Format(item_display, sizeof(item_display), g_ClientsData[client].EditSentenceData.trigger_2);
		case 2:Format(item_display, sizeof(item_display), g_ClientsData[client].EditSentenceData.trigger_3);
		case 3:Format(item_display, sizeof(item_display), g_ClientsData[client].EditSentenceData.trigger_4);
	}
	
	RTLify(item_display, sizeof(item_display), item_display);
	
	Format(item_display, sizeof(item_display), "Trigger #%d: %s", g_ClientsData[client].current_edit_index[Edit_Trigger] + 1, item_display[0] == '\0' ? "None" : item_display);
	menu.AddItem("", item_display);
	menu.AddItem("", "Switch Trigger\n ");
	
	switch (g_ClientsData[client].current_edit_index[Edit_Answer])
	{
		case 0:Format(item_display, sizeof(item_display), g_ClientsData[client].EditSentenceData.answer_1);
		case 1:Format(item_display, sizeof(item_display), g_ClientsData[client].EditSentenceData.answer_2);
		case 2:Format(item_display, sizeof(item_display), g_ClientsData[client].EditSentenceData.answer_3);
		case 3:Format(item_display, sizeof(item_display), g_ClientsData[client].EditSentenceData.answer_4);
	}
	
	RTLify(item_display, sizeof(item_display), item_display);
	
	Format(item_display, sizeof(item_display), "Answer #%d: %s", g_ClientsData[client].current_edit_index[Edit_Answer] + 1, item_display[0] == '\0' ? "None" : item_display);
	menu.AddItem("", item_display)
	menu.AddItem("", "Switch Answer\n ");
	
	menu.AddItem("", "Create Sentence");
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_CreateSentence(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		switch (item_position)
		{
			case 0:
			{
				// Change the client's edit state to trigger
				g_ClientsData[client].edit_state = Edit_Trigger;
				
				// Notify the client
				PrintToChat(client, "%s Type your desired \x04sentence trigger word\x01, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			}
			case 1:
			{
				// Incease the variable value by 1
				g_ClientsData[client].current_edit_index[Edit_Trigger] = ++g_ClientsData[client].current_edit_index[Edit_Trigger] % MAX_TRIGGER_WORDS;
				
				// Display the sentence creation menu
				ShowCreateSentenceMenu(client);
			}
			case 2:
			{
				// Change the client's edit state to answer
				g_ClientsData[client].edit_state = Edit_Answer;
				
				// Notify the client
				PrintToChat(client, "%s Type your desired \x04sentence answer\x01, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
			}
			case 3:
			{
				// Incease the variable value by 1
				g_ClientsData[client].current_edit_index[Edit_Answer] = ++g_ClientsData[client].current_edit_index[Edit_Answer] % MAX_ANSWERS;
				
				// Display the sentence creation menu
				ShowCreateSentenceMenu(client);
			}
			case 4:
			{
				if (!g_ClientsData[client].EditSentenceData.trigger_1[0] && !g_ClientsData[client].EditSentenceData.trigger_2[0] && !g_ClientsData[client].EditSentenceData.trigger_3[0] && !g_ClientsData[client].EditSentenceData.trigger_4[0])
				{
					// Notify the client
					PrintToChat(client, "%s You must enter atleast 1 trigger word!", PREFIX_ERROR);
					
					// Display the menu again
					ShowCreateSentenceMenu(client);
					
					return 0;
				}
				
				if (!g_ClientsData[client].EditSentenceData.answer_1[0] && !g_ClientsData[client].EditSentenceData.answer_2[0] && !g_ClientsData[client].EditSentenceData.answer_3[0] && !g_ClientsData[client].EditSentenceData.answer_4[0])
				{
					// Notify the client
					PrintToChat(client, "%s You must enter atleast 1 answer!", PREFIX_ERROR);
					
					// Display the menu again
					ShowCreateSentenceMenu(client);
					
					return 0;
				}
				
				// Create the bot sentence
				KV_AddBotSentence(client);
				
				// Notify the client
				PrintToChat(client, "%s Successfully created bot sentence \x04#%d\x01!", PREFIX, g_BotSentences.Length);
				
				// Display the bot main menu
				ShowBotMainMenu(client);
				
				// Reset the client data struct
				g_ClientsData[client].Reset();
			}
		}
	}
	else if (action == MenuAction_Cancel && (param2 == MenuCancel_ExitBack || param2 == MenuCancel_Exit))
	{
		// Reset the client data struct
		g_ClientsData[param1].Reset();
		
		if (param2 == MenuCancel_ExitBack)
		{
			ShowBotMainMenu(param1);
		}
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	return 0;
}

void ShowSentenceDetailMenu(int client, int sentence_index)
{
	char item_display[128], item_info[4];
	Menu menu = new Menu(Handler_SentenceDetail);
	menu.SetTitle("%s Chat Bot - Sentence #%d Detail\n ", PREFIX_MENU, sentence_index + 1);
	
	Sentence SentenceData; SentenceData = GetSentenceByIndex(sentence_index);
	
	switch (g_ClientsData[client].current_edit_index[Edit_Trigger])
	{
		case 0:Format(item_display, sizeof(item_display), SentenceData.trigger_1);
		case 1:Format(item_display, sizeof(item_display), SentenceData.trigger_2);
		case 2:Format(item_display, sizeof(item_display), SentenceData.trigger_3);
		case 3:Format(item_display, sizeof(item_display), SentenceData.trigger_4);
	}
	
	RTLify(item_display, sizeof(item_display), item_display);
	
	IntToString(sentence_index, item_info, sizeof(item_info));
	Format(item_display, sizeof(item_display), "Next Trigger Word\n• Trigger #%d: %s\n ", g_ClientsData[client].current_edit_index[Edit_Trigger] + 1, item_display[0] == '\0' ? "None" : item_display);
	menu.AddItem(item_info, item_display);
	
	switch (g_ClientsData[client].current_edit_index[Edit_Answer])
	{
		case 0:Format(item_display, sizeof(item_display), SentenceData.answer_1);
		case 1:Format(item_display, sizeof(item_display), SentenceData.answer_2);
		case 2:Format(item_display, sizeof(item_display), SentenceData.answer_3);
		case 3:Format(item_display, sizeof(item_display), SentenceData.answer_4);
	}
	
	RTLify(item_display, sizeof(item_display), item_display);
	
	Format(item_display, sizeof(item_display), "Next Answer\n• Answer #%d: %s\n ", g_ClientsData[client].current_edit_index[Edit_Answer] + 1, item_display[0] == '\0' ? "None" : item_display);
	menu.AddItem("", item_display)
	
	menu.AddItem("", "Delete Sentence");
	
	// Set the exit back button as true, and fix the back button gap
	menu.ExitBackButton = true;
	JB_FixMenuGap(menu);
	
	// Display the menu to the client
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_SentenceDetail(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1, item_position = param2;
		
		char item_info[4];
		menu.GetItem(0, item_info, sizeof(item_info));
		int sentence_index = StringToInt(item_info);
		
		switch (item_position)
		{
			case 0:
			{
				// Incease the variable value by 1
				g_ClientsData[client].current_edit_index[Edit_Trigger] = ++g_ClientsData[client].current_edit_index[Edit_Trigger] % MAX_TRIGGER_WORDS;
				
				// Display the sentence creation menu
				ShowSentenceDetailMenu(client, sentence_index);
			}
			case 1:
			{
				// Incease the variable value by 1
				g_ClientsData[client].current_edit_index[Edit_Answer] = ++g_ClientsData[client].current_edit_index[Edit_Answer] % MAX_ANSWERS;
				
				// Display the sentence creation menu
				ShowSentenceDetailMenu(client, sentence_index);
			}
			case 2:
			{
				// Delete the bot sentence from the configuration file, and from the memory itself
				KV_DeleteBotSentence(client, sentence_index);
				
				// Notify the client
				PrintToChat(client, "%s Successfully deleted bot sentence \x02#%d\x01!", PREFIX, sentence_index + 1);
				
				// Display the bot main menu
				ShowBotMainMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowBotMainMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		// Delete the menu handle to avoid memory problems
		delete menu;
	}
	return 0;
}

//================================[ Responde Functions ]================================//

void BotAnswerNoArgs(int client)
{
	char szResponde[11][64];
	
	Format(szResponde[0], sizeof(szResponde[]), "?אה שותף");
	Format(szResponde[1], sizeof(szResponde[]), "מה צריך אח יקר");
	Format(szResponde[2], sizeof(szResponde[]), "מי אתה ילד");
	Format(szResponde[3], sizeof(szResponde[]), "קח כרטיס ועמוד בתור");
	Format(szResponde[4], sizeof(szResponde[]), "?יש בעיות");
	Format(szResponde[5], sizeof(szResponde[]), "אה כפרע");
	Format(szResponde[6], sizeof(szResponde[]), "?אתה מדבר אליי");
	Format(szResponde[7], sizeof(szResponde[]), "?%N אה", client);
	Format(szResponde[8], sizeof(szResponde[]), "מה יש");
	Format(szResponde[9], sizeof(szResponde[]), "?מה צריך");
	Format(szResponde[10], sizeof(szResponde[]), "דקה איתך");
	
	PrintBotMessage(szResponde[GetRandomInt(0, sizeof(szResponde) - 1)]);
}

void BotAnswerCredits(int client)
{
	char szResponde[11][MAX_NAME_LENGTH * 2];
	
	int random_client = GetRandomClient(client);
	
	if ((GetTime() - g_ClientsData[client].NextCreditsRequest) < g_cvCreditsRequestCooldown.IntValue)
	{
		Format(szResponde[0], sizeof(szResponde[]), "אתה עוד חייב לי על פעם קודמת גבר");
		Format(szResponde[1], sizeof(szResponde[]), "?אתה מחפש בעיות %N", client);
		Format(szResponde[2], sizeof(szResponde[]), "לך חפש תחברים שלך");
		Format(szResponde[3], sizeof(szResponde[]), "רד לכאפת שטות");
		
		if (random_client != -1)
		{
			Format(szResponde[4], sizeof(szResponde[]), "שמעתי שיש לו הרבה %N תבקש מ", random_client);
		}
		else
		{
			Format(szResponde[4], sizeof(szResponde[]), "עזוב אותי תבקש ממישהו אחר");
		}
		
		Format(szResponde[5], sizeof(szResponde[]), "שותף בכיר חכה קצת");
		Format(szResponde[6], sizeof(szResponde[]), "אני קצר במזומנים");
		Format(szResponde[7], sizeof(szResponde[]), "דודה שך מכוערת");
		Format(szResponde[8], sizeof(szResponde[]), "נראה לך שכסף גדל על העצים %N תגיד לי?", client);
		Format(szResponde[9], sizeof(szResponde[]), "פעם הבאה שאתה מבקש אתה לא מקבל יותר");
		Format(szResponde[10], sizeof(szResponde[]), "וואלק לא היו טיפים היום");
	}
	else
	{
		int credits_amount = GetRandomInt(g_cvMinCreditsRequest.IntValue, g_cvMaxCreditsRequest.IntValue);
		
		Format(szResponde[0], sizeof(szResponde[]), "מה מילת הקסם?");
		Format(szResponde[1], sizeof(szResponde[]), "קיבלת ממני %d קאש בגלל שאתה גבר", credits_amount);
		Format(szResponde[2], sizeof(szResponde[]), "קיבלת %d קאש רק כי זה אתה!", credits_amount);
		Format(szResponde[3], sizeof(szResponde[]), "וואלה רציתי לקנות איזה סקין אבל נו קח %d קאש", credits_amount);
		Format(szResponde[4], sizeof(szResponde[]), "שווה זהב %d", credits_amount);
		Format(szResponde[5], sizeof(szResponde[]), "טוב קח %d שיהיה לך לתרופות", credits_amount);
		
		if (random_client != -1)
		{
			Format(szResponde[6], sizeof(szResponde[]), "ניראלי הוא עני %N קיבלת %d אבל תשלח ל", GetRandomClient(client), credits_amount);
		}
		else
		{
			Format(szResponde[6], sizeof(szResponde[]), "קיבלת %d אבל תפרגן לאחרים", credits_amount);
		}
		
		Format(szResponde[7], sizeof(szResponde[]), "%d מפרגן לך, שלחתי", credits_amount);
		Format(szResponde[8], sizeof(szResponde[]), "%d כואב לי להביא לך, אבל נו קח", credits_amount);
		Format(szResponde[9], sizeof(szResponde[]), "%d רק בגלל שביקשת יפה, קבל", credits_amount);
		Format(szResponde[10], sizeof(szResponde[]), "אבל תסתום תפה %d קח", credits_amount);
		
		Shop_GiveClientCredits(client, credits_amount);
		g_ClientsData[client].NextCreditsRequest = GetTime();
	}
	
	PrintBotMessage(szResponde[GetRandomInt(0, sizeof(szResponde) - 1)]);
}

void BotAnswerTime(int client)
{
	char szResponde[10][MAX_NAME_LENGTH * 2], sTime[32];
	
	FormatTime(sTime, sizeof(sTime), "%H:%M:%S", GetTime());
	
	Format(szResponde[0], sizeof(szResponde[]), "השעה %s, יעצלן יכולת למעזר ולבדוק...", sTime);
	Format(szResponde[1], sizeof(szResponde[]), "%s השעה כרגע.", sTime);
	Format(szResponde[2], sizeof(szResponde[]), "וואלה אין לי מושג אחינו הייתי ער כל הלילה");
	Format(szResponde[3], sizeof(szResponde[]), "25:00!!!");
	Format(szResponde[4], sizeof(szResponde[]), "אני נראה לך שעון %N תגיד לי?", client);
	Format(szResponde[5], sizeof(szResponde[]), "%s פעם אחרונה שבדקתי השעה", sTime);
	Format(szResponde[6], sizeof(szResponde[]), "שתקנה שעון");
	Format(szResponde[7], sizeof(szResponde[]), "שתהיה בן אדם?");
	Format(szResponde[8], sizeof(szResponde[]), "%s זמן לעבוד זמן לעבוד", sTime);
	Format(szResponde[9], sizeof(szResponde[]), "ניראלי אני אפרוש %s כבר", sTime);
	
	PrintBotMessage(szResponde[GetRandomInt(0, sizeof(szResponde) - 1)]);
}

void BotAnswerHowAreYou()
{
	char szResponde[9][128];
	
	Format(szResponde[0], sizeof(szResponde[]), "תאמת חרא כל היום מבקשים ממני קאש");
	Format(szResponde[1], sizeof(szResponde[]), "היה טוב עד ששאלת...");
	Format(szResponde[2], sizeof(szResponde[]), "וואלה טיל אחי ואתה?");
	Format(szResponde[3], sizeof(szResponde[]), "הכל טוב אחי מה איתך?");
	Format(szResponde[4], sizeof(szResponde[]), "הכל טוב נשמה מה הולך?");
	Format(szResponde[5], sizeof(szResponde[]), "הפסדתי את כל הקאש שלי :( חרא של יום");
	Format(szResponde[6], sizeof(szResponde[]), "מה איתך ילדון פאן?");
	Format(szResponde[7], sizeof(szResponde[]), "וואלה חרא מפה שימו כבר rtv");
	Format(szResponde[8], sizeof(szResponde[]), "אל תפנה אליי או שתקבל PGAG");
	
	PrintBotMessage(szResponde[GetRandomInt(0, sizeof(szResponde) - 1)]);
}

void BotAnswerRandom()
{
	char szResponde[11][64];
	
	Format(szResponde[0], sizeof(szResponde[]), "!ברור");
	Format(szResponde[1], sizeof(szResponde[]), "כן");
	Format(szResponde[2], sizeof(szResponde[]), "ברורר מה השאלה בכלל.");
	Format(szResponde[3], sizeof(szResponde[]), "כןןן");
	
	Format(szResponde[4], sizeof(szResponde[]), "...נראה לי");
	Format(szResponde[5], sizeof(szResponde[]), "יש מצב");
	Format(szResponde[6], sizeof(szResponde[]), "אולי");
	
	Format(szResponde[7], sizeof(szResponde[]), "לא חושב");
	Format(szResponde[8], sizeof(szResponde[]), "!לא");
	Format(szResponde[9], sizeof(szResponde[]), "!נראה לך בחיים לא");
	Format(szResponde[10], sizeof(szResponde[]), "ממש לא");
	
	PrintBotMessage(szResponde[GetRandomInt(0, sizeof(szResponde) - 1)]);
}

void BotAnswerChatSilence()
{
	char szResponde[6][128];
	
	Format(szResponde[0], sizeof(szResponde[]), "?הלו? אפשר קצת יחס");
	Format(szResponde[1], sizeof(szResponde[]), "אדמין אני פה אל תקיק");
	Format(szResponde[2], sizeof(szResponde[]), "וואו שקט פה רצח");
	Format(szResponde[3], sizeof(szResponde[]), "D: אם יש לי חברים אז למה אף אחד לא מדבר איתי");
	Format(szResponde[4], sizeof(szResponde[]), "קיצר מה אומרים");
	
	int random_client = GetRandomClient();
	if (random_client != -1)
	{
		Format(szResponde[5], sizeof(szResponde[]), "סתום תפה %N", random_client);
	}
	
	PrintBotMessage(szResponde[GetRandomInt(0, sizeof(szResponde) - 1)]);
}

//================================[ Key Values ]================================//

void KV_LoadBotSentences()
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Sentences");
	kv.ImportFromFile(CONFIG_PATH);
	
	g_BotSentences.Clear();
	
	Sentence SentenceData;
	
	char data[4][64];
	
	if (kv.GotoFirstSubKey())
	{
		do {
			kv.GetString("TriggerWords", SentenceData.trigger_1, sizeof(SentenceData.trigger_1));
			
			ExplodeString(SentenceData.trigger_1, ":", data, sizeof(data), sizeof(data[]));
			
			strcopy(SentenceData.trigger_1, sizeof(SentenceData.trigger_1), data[0]);
			strcopy(SentenceData.trigger_2, sizeof(SentenceData.trigger_2), data[1]);
			strcopy(SentenceData.trigger_3, sizeof(SentenceData.trigger_3), data[2]);
			strcopy(SentenceData.trigger_4, sizeof(SentenceData.trigger_4), data[3]);
			
			kv.GetString("Answer_1", SentenceData.answer_1, sizeof(SentenceData.answer_1));
			kv.GetString("Answer_2", SentenceData.answer_2, sizeof(SentenceData.answer_2));
			kv.GetString("Answer_3", SentenceData.answer_3, sizeof(SentenceData.answer_3));
			kv.GetString("Answer_4", SentenceData.answer_4, sizeof(SentenceData.answer_4));
			
			g_BotSentences.PushArray(SentenceData);
		}
		while (kv.GotoNextKey());
	}
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	kv.Close();
}

void KV_AddBotSentence(int client)
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Sentences");
	kv.ImportFromFile(CONFIG_PATH);
	
	char key_num[4];
	IntToString(g_BotSentences.Length, key_num, sizeof(key_num));
	kv.JumpToKey(key_num, true);
	
	Sentence SentenceData; SentenceData = g_ClientsData[client].EditSentenceData;
	
	g_BotSentences.PushArray(SentenceData);
	
	JB_WriteLogLine("Admin \"%L\" added the bot sentence \"#%d\".", client, g_BotSentences.Length);
	
	char trigger_words[128];
	Format(trigger_words, sizeof(trigger_words), "%s%s%s%s%s%s%s", SentenceData.trigger_1, SentenceData.trigger_2[0] ? ":" : "", SentenceData.trigger_2, SentenceData.trigger_3[0] ? ":" : "", SentenceData.trigger_3, SentenceData.trigger_4[0] ? ":" : "", SentenceData.trigger_4);
	kv.SetString("TriggerWords", trigger_words);
	
	int counter;
	
	if (SentenceData.answer_1[0])
	{
		kv.SetString(!counter ? "Answer_1" : counter == 1 ? "Answer_2" : counter == 2 ? "Answer_3" : "Answer_4", SentenceData.answer_1);
		counter++;
	}
	
	if (SentenceData.answer_2[0])
	{
		kv.SetString(!counter ? "Answer_1" : counter == 1 ? "Answer_2" : counter == 2 ? "Answer_3" : "Answer_4", SentenceData.answer_2);
		counter++;
	}
	
	if (SentenceData.answer_3[0])
	{
		kv.SetString(!counter ? "Answer_1" : counter == 1 ? "Answer_2" : counter == 2 ? "Answer_3" : "Answer_4", SentenceData.answer_3);
		counter++;
	}
	
	if (SentenceData.answer_4[0])
	{
		kv.SetString(!counter ? "Answer_1" : counter == 1 ? "Answer_2" : counter == 2 ? "Answer_3" : "Answer_4", SentenceData.answer_4);
		counter++;
	}
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	kv.Close();
}

void KV_DeleteBotSentence(int client, int sentence_index)
{
	// Make sure the configuration file is exists
	if (!FileExists(CONFIG_PATH))
	{
		SetFailState("Unable to find file %s", CONFIG_PATH);
	}
	
	KeyValues kv = new KeyValues("Sentences");
	kv.ImportFromFile(CONFIG_PATH);
	kv.SetEscapeSequences(true);
	
	char key_num[4];
	IntToString(sentence_index, key_num, sizeof(key_num));
	
	if (kv.JumpToKey(key_num))
	{
		kv.DeleteThis();
		kv.Rewind();
	}
	
	JB_WriteLogLine("Admin \"%L\" deleted the bot sentence \"#%d\".", client, sentence_index + 1);
	g_BotSentences.Erase(sentence_index);
	
	char szSectionName[16];
	int iStartPosition = sentence_index;
	
	kv.GotoFirstSubKey();
	
	do {
		kv.GetSectionName(szSectionName, sizeof(szSectionName));
		
		if (StringToInt(szSectionName) < sentence_index) {
			continue;
		}
		
		IntToString(iStartPosition, key_num, sizeof(key_num));
		kv.SetSectionName(key_num);
		iStartPosition++;
	} while (kv.GotoNextKey());
	
	kv.Rewind();
	kv.SetSectionName("Sentences"); // In case it will be changed by the index fixer
	
	kv.Rewind();
	kv.ExportToFile(CONFIG_PATH);
	kv.Close();
}

//================================[ Timers ]================================//

Action Timer_SendTipMessage(Handle timer)
{
	PrintBotMessage(g_Tips[GetURandomInt() % sizeof(g_Tips)]);
	return Plugin_Continue;
}

public Action Timer_PrintBotMessage(Handle timer, DataPack dp)
{
	char message[128];
	dp.ReadString(message, sizeof(message));
	
	char bot_name[32] = BOT_NAME_EN;
	if (!IsCharUpper(bot_name[0]))
	{
		bot_name[0] = CharToUpper(bot_name[0]);
	}
	
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			CPrintToChat(current_client, "%s {%s}%s :\x01 %s", BOT_PREFIX, GetClientTeam(current_client) == CS_TEAM_T ? "red" : "blue", bot_name, message);
		}
	}
	return Plugin_Continue;
}

public Action Timer_ChatSilence(Handle timer)
{
	BotAnswerChatSilence();
	
	g_ChatSilenceTimer = INVALID_HANDLE;
	
	RecreateChatSilenceTimer();
	return Plugin_Continue;
}

//================================[ Functions ]================================//

any[] GetSentenceByIndex(int index)
{
	Sentence SentenceData;
	g_BotSentences.GetArray(index, SentenceData);
	return SentenceData;
}

void PrintBotMessage(const char[] message)
{
	DataPack dp;
	CreateDataTimer(0.1, Timer_PrintBotMessage, dp);
	dp.WriteString(message);
	dp.Reset();
}

void RecreateChatSilenceTimer()
{
	// Kill the timer, if it's running
	if (g_ChatSilenceTimer != INVALID_HANDLE)
	{
		KillTimer(g_ChatSilenceTimer);
		g_ChatSilenceTimer = INVALID_HANDLE;
	}
	
	// Create the timer again
	g_ChatSilenceTimer = CreateTimer(g_cvChatSilenceMsgTime.FloatValue, Timer_ChatSilence);
}

int CheckForTriggerWord(const char[] text)
{
	Sentence SentenceData;
	
	for (int current_sentence = 0; current_sentence < g_BotSentences.Length; current_sentence++)
	{
		SentenceData = GetSentenceByIndex(current_sentence);
		
		if (SentenceData.trigger_1[0] != '\0' && StrContains(text, SentenceData.trigger_1) != -1)
		{
			return current_sentence;
		}
		
		if (SentenceData.trigger_2[0] != '\0' && StrContains(text, SentenceData.trigger_2) != -1)
		{
			return current_sentence;
		}
		
		if (SentenceData.trigger_3[0] != '\0' && StrContains(text, SentenceData.trigger_3) != -1)
		{
			return current_sentence;
		}
		
		if (SentenceData.trigger_4[0] != '\0' && StrContains(text, SentenceData.trigger_4) != -1)
		{
			return current_sentence;
		}
	}
	
	return -1;
}

void AnswerToSentence(int sentence_index)
{
	Sentence SentenceData; SentenceData = GetSentenceByIndex(sentence_index);
	
	char answer[128];
	
	do
	{
		switch (GetRandomInt(1, 4))
		{
			case 1:
			{
				strcopy(answer, sizeof(answer), SentenceData.answer_1);
			}
			case 2:
			{
				strcopy(answer, sizeof(answer), SentenceData.answer_2);
			}
			case 3:
			{
				strcopy(answer, sizeof(answer), SentenceData.answer_3);
			}
			case 4:
			{
				strcopy(answer, sizeof(answer), SentenceData.answer_4);
			}
		}
	} while (!answer[0]);
	
	PrintBotMessage(answer);
}

int GetRandomClient(int client = 0)
{
	int counter = 0;
	int[] clients = new int[MaxClients];
	
	for (int current_client = 1; current_client <= MaxClients; ++current_client)
	{
		if (IsClientInGame(current_client) && (!client || current_client != client))
		{
			clients[counter++] = current_client;
		}
	}
	
	return counter ? clients[GetRandomInt(0, counter - 1)] : -1;
}

/**
 * Return true if the client's steam account id matched one of specified authorized clients.
 * See g_AuthorizedClients
 * 
 */
bool IsClientAllowed(int client)
{
	for (int iCurrentAccountID = 0; iCurrentAccountID < sizeof(g_AuthorizedClients); iCurrentAccountID++)
	{
		// Check for a match
		if (GetSteamAccountID(client) == g_AuthorizedClients[iCurrentAccountID])
		{
			return true;
		}
	}
	
	// Match has failed
	return false;
}

//================================================================//