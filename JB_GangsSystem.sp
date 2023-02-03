#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <JailBreak>
#include <JB_GangsSystem>
#include <rtler>
#include <shop>
#include <regex>

#define PLUGIN_AUTHOR "Ravid"
#define PLUGIN_VERSION "1.00"

#define SECONDS_WEEK 604800
#define MAX_MEMBERS 64

#define MAX_WEEKLY_PAYMENT_WEEKS 2

#define ABORT_SYMBOL "-1"

#define MAX_DESC_LINES 3
#define DEFAULT_CREATION_DESC "Welcome to your new gang! \nYou may edit the description in the managment menu."

enum
{
	Write_None = 0, 
	Write_Name, 
	Write_Donate, 
	Write_Desc
}

enum struct Gangs
{
	char szName[128];
	char szDesc[256];
	int iCash;
	int iMembers;
	int iSlots;
	int iExpiration;
	int iColor;
	
	void reset()
	{
		this.szName[0] = '\0';
		this.szDesc[0] = '\0';
		this.iCash = 0;
		this.iMembers = 0;
		this.iSlots = 0;
		this.iExpiration = 0;
		this.iColor = -1;
	}
}

enum struct Clients
{
	char szAuth[64];
	char szName[MAX_NAME_LENGTH];
	int iGang;
	int iRank;
	int iDonations;
	
	int iLookingGang;
	bool bLookFromMainMenu;
	
	int iWrite;
	
	void reset()
	{
		this.szAuth[0] = 0;
		this.szName[0] = 0;
		this.iGang = NO_GANG;
		this.iRank = Rank_NoGang;
		this.iDonations = 0;
		this.iLookingGang = NO_GANG;
		this.iWrite = Write_None;
		this.bLookFromMainMenu = false;
	}
}

enum struct CreateGang
{
	char szName[128];
	int iColor;
	
	void reset()
	{
		this.szName[0] = 0;
		this.iColor = 0;
	}
}

enum struct MemberDetails
{
	char szAuth[64];
	char szName[MAX_NAME_LENGTH];
	int iRank;
	int iGang;
	
	void reset()
	{
		this.szAuth[0] = 0;
		this.szName[0] = 0;
		this.iGang = NO_GANG;
		this.iRank = Rank_NoGang;
	}
}

Gangs g_esGangs[MAX_GANGS];
Clients g_esClients[MAXPLAYERS + 1];
CreateGang g_esCreateGang[MAXPLAYERS + 1];
MemberDetails g_esMemberDetails[MAXPLAYERS + 1];

Database g_dbDatabase = null;

/* Convars */

ConVar g_cvGangCost;
ConVar g_cvColorCost;
ConVar g_cvNameCost;
ConVar g_cvWeekCost;
ConVar g_cvMinGangDonate;

/* */

/* Forward */

GlobalForward g_fwdGangsLoaded;
GlobalForward g_fwdUserLoaded;
GlobalForward g_fwdUserOpenMainMenu;
GlobalForward g_fwdUserPressMainMenu;
GlobalForward g_fwdUserOpenGangDetails;
GlobalForward g_fwdUserPressGangDetails;
GlobalForward g_fwdUpdateName;
GlobalForward g_fwdCreateGang;
GlobalForward g_fwdDeleteGang;

/*  */

char g_szRanks[][] =  { "Member", "Manager", "Deputy Leader", "Leader" };

int g_iNumOfGangs = 0;

public Plugin myinfo = 
{
	name = "[CS:GO] JailBreak - Gangs System", 
	author = PLUGIN_AUTHOR, 
	description = "", 
	version = PLUGIN_VERSION, 
	url = ""
};

public void OnPluginStart()
{
	SQL_MakeConnection();
	
	LoadTranslations("common.phrases");
	
	RegConsoleCmd("sm_gangs", Command_Gangs, "Access the server gangs list menu.");
	RegConsoleCmd("sm_gang", Command_Gang, "Opens the gang managment menu.");
	
	g_cvGangCost = CreateConVar("gangs_cost", "125000", "The amount of cash cost to create a new gang.", _, true, 0.0);
	g_cvColorCost = CreateConVar("gangs_colorcost", "85000", "The amount of cash cost to change a gang's color.", _, true, 1.0);
	g_cvNameCost = CreateConVar("gangs_namecost", "85000", "The amount of cash cost to change a gang's name.", _, true, 1.0);
	g_cvWeekCost = CreateConVar("gangs_weekcost", "75000", "The amount of cash cost to pay the gang's weekly payment.", _, true, 1.0);
	g_cvMinGangDonate = CreateConVar("gangs_min_donate_amount", "300", "Minimum amount of cash to be possible to donate.", _, true, 0.0, true, 1000.0);
	
	AutoExecConfig(true, "GangsSystem", "JailBreak");
}

/* Events */

public void OnClientPostAdminCheck(int client)
{
	g_esClients[client].reset();
	g_esCreateGang[client].reset();
	g_esMemberDetails[client].reset();
	
	if (!IsFakeClient(client))
	{
		if (!GetClientAuthId(client, AuthId_Steam2, g_esClients[client].szAuth, sizeof(g_esClients[].szAuth)))
		{
			KickClient(client, "Verification problem, Please reconnect");
			return;
		}
		
		GetClientName(client, g_esClients[client].szName, sizeof(g_esClients[].szName));
		SQL_FetchUser(client);
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] szArgs)
{
	int gangId = g_esClients[client].iGang;
	if (g_esClients[client].iWrite == Write_None)
	{
		if (szArgs[0] == '~' && gangId != NO_GANG)
		{
			PrintGangMessage(gangId, "\x0B%N\x01 : %s", client, szArgs[1]);
			return Plugin_Handled;
		}
		return Plugin_Continue;
	}
	
	int iWrite = g_esClients[client].iWrite;
	
	if (StrEqual(szArgs, ABORT_SYMBOL))
	{
		PrintToChat(client, "%s Operation aborted.", PREFIX);
		
		switch (iWrite)
		{
			case Write_Name:
			{
				if (gangId == NO_GANG)
					showCreateGang(client);
				else
					showManageGang(client, gangId);
			}
			case Write_Donate:
			{
				showMainMenu(client);
			}
			case Write_Desc:
			{
				if (g_esClients[client].iRank >= Rank_Deputy_Leader)
				{
					showManageGang(client, gangId);
				}
			}
		}
		
		g_esClients[client].iWrite = Write_None;
		return Plugin_Handled;
	}
	
	switch (iWrite)
	{
		case Write_Name:
		{
			if (getGangIdByName(szArgs) != -1)
			{
				PrintToChat(client, "%s Name \x02%s\x01 is already taken, please try anoter name.", PREFIX_ERROR, szArgs);
			} else {
				if (gangId == NO_GANG)
				{
					strcopy(g_esCreateGang[client].szName, sizeof(g_esCreateGang[].szName), szArgs);
					showCreateGang(client);
				} else if (g_esClients[client].iRank == Rank_Manager || g_esClients[client].iRank == Rank_Leader) {
					PrintGangMessage(gangId, "\x04%N\x01 has changed the gang name to \x0C%s\x01 from \x0B%s\x01.", client, szArgs, g_esGangs[gangId].szName);
					WriteLogLine("\"%L\" has changed gang \"%s\"'s name to \"%s\". (Costs: %d)", client, g_esGangs[gangId].szName, szArgs, AddCommas(g_cvNameCost.IntValue));
					
					SQL_ChangeGangName(gangId, szArgs);
					g_esGangs[gangId].iCash -= g_cvNameCost.IntValue;
					SQL_UpdateCash(gangId);
				}
			}
		}
		case Write_Donate:
		{
			if (g_esClients[client].iRank != Rank_NoGang)
			{
				int iAmount = StringToInt(szArgs);
				int iClientCash = Shop_GetClientCredits(client);
				
				if (StrContains(szArgs, "k", false) != -1) {
					iAmount *= 1000;
				}
				
				if (iClientCash < iAmount)
				{
					PrintToChat(client, "%s You don't have enough cash. (missing \x02%s\x01)", PREFIX_ERROR, AddCommas(iAmount - iClientCash));
				} else if (iAmount < g_cvMinGangDonate.IntValue) {
					PrintToChat(client, "%s You have specified an invalid cash amount. (\x02Minimum: %d | Enter: %s\x01)", PREFIX_ERROR, g_cvMinGangDonate.IntValue, szArgs);
				} else {
					PrintGangMessage(gangId, "\x07%N\x01 has donated \x02%s\x01 cash to the gang.", client, AddCommas(iAmount));
					WriteLogLine("Player \"%L\" has donated %s cash to the gang \"%s\"", client, AddCommas(iAmount), g_esGangs[gangId].szName);
					
					Shop_TakeClientCredits(client, iAmount, CREDITS_BY_BUY_OR_SELL);
					
					SQL_Donate(client, gangId, iAmount);
					SQL_UpdateCash(gangId);
				}
			}
		}
		case Write_Desc:
		{
			char szMessage[256];
			strcopy(szMessage, sizeof(szMessage), szArgs);
			
			int iReplace = ReplaceString(szMessage, sizeof(szMessage), "  ", "\n") + 1;
			if (iReplace > MAX_DESC_LINES)
			{
				PrintToChat(client, "%s Maximum description lines is \x04%d\x01, please change your description.", PREFIX, MAX_DESC_LINES);
				
				showManageGang(client, gangId);
				
				return Plugin_Handled;
			}
			
			RTLify(szMessage, sizeof(szMessage), szMessage); // rtl support
			
			strcopy(g_esGangs[gangId].szDesc, sizeof(g_esGangs[].szDesc), szMessage);
			
			SQL_UpdateGangDesc(gangId);
			
			g_esClients[client].iWrite = Write_None;
			
			PrintGangMessage(gangId, "\x04%N\x01 has updated the \x03Gang Description\x01.", client);
			showManageGang(client, gangId);
			
			JB_WriteLogLine("%N has updated the description of the gang %s (new description: %s)", client, g_esGangs[gangId].szName, szMessage);
		}
	}
	
	g_esClients[client].iWrite = Write_None;
	return Plugin_Handled;
}

/* */

/* Commands */

public Action Command_Gang(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int iTargetIndex = FindTarget(client, szArg, true, false);
		
		if (iTargetIndex == -1) {
			/* Automated message from SourceMod. */
			return Plugin_Handled;
		}
		
		showMainMenu(iTargetIndex);
	}
	else {
		showMainMenu(client);
	}
	
	return Plugin_Handled;
}

public Action Command_Gangs(int client, int args)
{
	if (args == 1)
	{
		if (GetUserAdmin(client) == INVALID_ADMIN_ID) {
			PrintToChat(client, "%s This feature is allowed for administrators only.", PREFIX_ERROR);
			return Plugin_Handled;
		}
		
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int iTargetIndex = FindTarget(client, szArg, true, false);
		
		if (iTargetIndex == -1) {
			/* Automated message from SourceMod. */
			return Plugin_Handled;
		}
		
		SQL_ShowGangsList(iTargetIndex);
	}
	else {
		SQL_ShowGangsList(client);
	}
	
	return Plugin_Handled;
}

/* */

/* Menus */

void showMainMenu(int client)
{
	char szItem[128], szGangName[128];
	Menu menu = new Menu(Handler_Main);
	int gangId = g_esClients[client].iGang;
	int rankId = g_esClients[client].iRank;
	
	if (gangId == NO_GANG)
	{
		menu.SetTitle("%s Gangs Menu - Main Menu\n \nWelcome to Play-IL JailBreak, enjoy your stay!\n ", PREFIX_MENU);
		Format(szItem, sizeof(szItem), "Create New Gang [%s Cash]", AddCommas(g_cvGangCost.IntValue));
		menu.AddItem("creategang", szItem, g_iNumOfGangs == MAX_GANGS || Shop_GetClientCredits(client) < g_cvGangCost.IntValue ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	} else {
		int iColor = g_esGangs[gangId].iColor;
		
		RTLify(szGangName, sizeof(szGangName), g_esGangs[gangId].szName);
		FormatTime(szItem, sizeof(szItem), "%d/%m/%Y - %H:%M:%S", g_esGangs[gangId].iExpiration);
		menu.SetTitle("%s Gangs Menu - Main Menu\n \n• Gang: %s | Cash: %s Cash\n• Online: %d/%d\n• Color: %s\n \n%s\n ", PREFIX_MENU, szGangName, AddCommas(g_esGangs[gangId].iCash), getOnlinePlayers(gangId), g_esGangs[gangId].iMembers, g_szColors[iColor][Color_Name], g_esGangs[gangId].szDesc);
		
		menu.AddItem("donatecash", "Donate Cash");
		menu.AddItem("memberlist", "Member List");
		menu.AddItem("managegang", "Manage Gang", rankId < Rank_Deputy_Leader ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
		menu.AddItem("leavegang", "Leave Gang\n ", rankId == Rank_Leader ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}
	
	menu.AddItem("gangslist", "Gangs List");
	
	Call_StartForward(g_fwdUserOpenMainMenu);
	Call_PushCell(client);
	Call_PushCell(menu);
	Call_Finish();
	
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_Main(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[64];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int iClientGangId = g_esClients[client].iGang;
		
		if (StrEqual(szItem, "creategang")) {
			if (iClientGangId != NO_GANG) {
				showMainMenu(client);
			}
			
			setFreeColor(client);
			showCreateGang(client);
		}
		else if (StrEqual(szItem, "donatecash")) {
			if (iClientGangId == NO_GANG) {
				showMainMenu(client);
				return;
			}
			
			PrintToChat(client, "%s Type the amount of cash you would like to donate, or \x02-1\x01 to abort.", PREFIX);
			g_esClients[client].iWrite = Write_Donate;
		}
		else if (StrEqual(szItem, "memberlist")) {
			if (iClientGangId == NO_GANG) {
				showMainMenu(client);
				return;
			}
			
			g_esClients[client].bLookFromMainMenu = true;
			SQL_ShowMembersList(client, iClientGangId);
		}
		else if (StrEqual(szItem, "managegang")) {
			if (iClientGangId == NO_GANG) {
				showMainMenu(client);
				return;
			}
			
			showManageGang(client, iClientGangId);
		}
		else if (StrEqual(szItem, "leavegang")) {
			if (iClientGangId == NO_GANG) {
				showMainMenu(client);
				return;
			}
			
			showLeaveGang(client);
		}
		else if (StrEqual(szItem, "gangslist")) {
			SQL_ShowGangsList(client);
		}
		else {
			Call_StartForward(g_fwdUserPressMainMenu);
			Call_PushCell(client);
			Call_PushString(szItem);
			Call_Finish();
		}
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void showCreateGang(int client)
{
	char szItem[128];
	Menu menu = new Menu(Handler_Create);
	menu.SetTitle("%s Gangs Menu - Creating a Gang\n ", PREFIX_MENU);
	
	RTLify(szItem, sizeof(szItem), g_esCreateGang[client].szName);
	Format(szItem, sizeof(szItem), "Name: %s", g_esCreateGang[client].szName[0] == '\0' ? "Press to select":szItem);
	menu.AddItem("", szItem);
	
	int iColor = g_esCreateGang[client].iColor;
	Format(szItem, sizeof(szItem), "Color: %s", g_szColors[iColor][Color_Name]);
	menu.AddItem("", szItem);
	
	Format(szItem, sizeof(szItem), "Create The Gang [%s Cash]", AddCommas(g_cvGangCost.IntValue));
	menu.AddItem("", szItem, g_esCreateGang[client].szName[0] == '\0' ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_Create(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		switch (itemNum)
		{
			case 0:
			{
				PrintToChat(client, "%s Type your desired \x04gang\x01 name, or \x02%s\x01 to abort.", PREFIX, ABORT_SYMBOL);
				g_esClients[client].iWrite = Write_Name;
			}
			case 1:
			{
				g_esClients[client].iWrite = Write_None;
				showColors(client);
			}
			case 2:
			{
				if (Shop_GetClientCredits(client) < g_cvGangCost.IntValue)
				{
					PrintToChat(client, "%s you don't have enough cash (missing \x02%s\x01).", PREFIX_ERROR, AddCommas(g_cvGangCost.IntValue - Shop_GetClientCredits(client)));
					return;
				}
				
				if (getGangIdByColor(g_esCreateGang[client].iColor) != -1)
				{
					PrintToChat(client, "%s This color is already taken, please choose another color.", PREFIX_ERROR);
					setFreeColor(client);
					showCreateGang(client);
					return;
				}
				
				if (getGangIdByName(g_esCreateGang[client].szName) != -1)
				{
					PrintToChat(client, "%s The name is already taken, please try new name.", PREFIX_ERROR);
					showCreateGang(client);
					return;
				}
				
				Shop_TakeClientCredits(client, g_cvGangCost.IntValue, CREDITS_BY_BUY_OR_SELL);
				PrintToChat(client, "%s Welcome to \x07%s\x01, to type in the gang chat prefix your message with: \x02~\x01.", PREFIX, g_esCreateGang[client].szName);
				WriteLogLine("Player \"%L\" has created the gang \"%s\" for %s cash", client, g_esCreateGang[client].szName, AddCommas(g_cvGangCost.IntValue));
				SQL_CreateGang(client);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (itemNum == MenuCancel_ExitBack || itemNum == MenuCancel_Exit)
		{
			g_esCreateGang[client].reset();
			HideHud(client, false);
			if (itemNum == MenuCancel_ExitBack)
				showMainMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void showColors(int client)
{
	char szItem[256];
	Menu menu = new Menu(Handler_Colors);
	menu.SetTitle("%s Gangs Menu - Select a Color\n ", PREFIX_MENU);
	
	for (int i = 0; i < sizeof(g_szColors); i++)
	{
		int gangId = getGangIdByColor(i);
		if (gangId != -1)
		{
			RTLify(szItem, sizeof(szItem), g_esGangs[gangId].szName);
			Format(szItem, sizeof(szItem), "[taken by %s]", szItem);
		}
		Format(szItem, sizeof(szItem), "%s %s", g_szColors[i][Color_Name], gangId == -1 ? "":szItem);
		menu.AddItem("", szItem, gangId == -1 ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_Colors(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		int gangId = g_esClients[client].iGang;
		if (gangId == NO_GANG)
		{
			g_esCreateGang[client].iColor = itemNum;
			showCreateGang(client);
		} else {
			if (g_esClients[client].iRank >= Rank_Deputy_Leader)
			{
				g_esGangs[gangId].iColor = itemNum;
				SQL_ChangeGangColor(gangId, itemNum);
				g_esGangs[gangId].iCash -= g_cvColorCost.IntValue;
				SQL_UpdateCash(gangId);
				
				PrintGangMessage(gangId, "\x07%N\x01 has changed the gang color to \x02%s\x01.", client, g_szColors[itemNum][Color_Name]);
				
				WriteLogLine("\"%L\" has changed their color: \"%s\", payed: %s", client, g_esGangs[gangId].szName, AddCommas(g_cvColorCost.IntValue));
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
		{
			int gangId = g_esClients[client].iGang;
			if (gangId == NO_GANG)
				showCreateGang(client);
			else
			{
				showManageGang(client, gangId);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void showManageGang(int client, int gangId)
{
	char szItem[256], szItemInfo[8], szGangName[128];
	IntToString(gangId, szItemInfo, sizeof(szItemInfo));
	
	int iGangCash = g_esGangs[gangId].iCash;
	int iColor = g_esGangs[gangId].iColor;
	int iRank = g_esClients[client].iRank;
	
	RTLify(szGangName, sizeof(szGangName), g_esGangs[gangId].szName);
	FormatTime(szItem, sizeof(szItem), "%d/%m/%Y - %H:%M:%S", g_esGangs[gangId].iExpiration);
	
	Menu menu = new Menu(Handler_Manage);
	menu.SetTitle("%s Gangs Menu - Manage Gang\n• Gang: %s\n• Color: %s\n• Gang Cash: %s Cash\n• Expire: %s\n ", PREFIX_MENU, szGangName, g_szColors[iColor][Color_Name], AddCommas(iGangCash), szItem);
	
	bool weekly_paymet_available = (g_esGangs[gangId].iExpiration - GetTime() < SECONDS_WEEK * MAX_WEEKLY_PAYMENT_WEEKS);
	
	Format(szItem, sizeof(szItem), " (Cannot pay for more than %d weeks!)", MAX_WEEKLY_PAYMENT_WEEKS);
	Format(szItem, sizeof(szItem), "Weekly Payment [%s cash]%s", AddCommas(g_cvWeekCost.IntValue), weekly_paymet_available ? "" : szItem);
	menu.AddItem(szItemInfo, szItem, weekly_paymet_available ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	Format(szItem, sizeof(szItem), "Change Name [%s cash]", AddCommas(g_cvNameCost.IntValue));
	menu.AddItem(szItemInfo, szItem);
	
	Format(szItem, sizeof(szItem), "Change Color [%s cash]", AddCommas(g_cvColorCost.IntValue));
	menu.AddItem(szItemInfo, szItem);
	
	menu.AddItem(szItemInfo, "Change Description\n ");
	
	menu.AddItem(szItemInfo, "Transfer Ownership [Leader Only]", iRank != Rank_Leader ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	menu.AddItem(szItemInfo, "Disband the Gang [Leader Only]", iRank != Rank_Leader ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_Manage(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int gangId = StringToInt(szItem);
		int iGangCash = g_esGangs[gangId].iCash;
		
		if (g_esClients[client].iRank < Rank_Deputy_Leader)
		{
			showManageGang(client, gangId);
			return;
		}
		
		switch (itemNum)
		{
			case 0:
			{
				if (iGangCash < g_cvWeekCost.IntValue)
				{
					PrintToChat(client, "%s The gang doesn't have enough cash (missing \x02%s\x01).", PREFIX, AddCommas(g_cvWeekCost.IntValue - iGangCash));
					showManageGang(client, gangId);
					return;
				}
				
				if (g_esGangs[gangId].iExpiration - GetTime() >= SECONDS_WEEK * MAX_WEEKLY_PAYMENT_WEEKS)
				{
					PrintToChat(client, "%s You cannot extand weekly pay for more than %d weeks!", PREFIX, MAX_WEEKLY_PAYMENT_WEEKS);
					
					showManageGang(client, gangId);
					
					return;
				}
				
				SQL_AddWeek(gangId);
				g_esGangs[gangId].iCash = iGangCash - g_cvWeekCost.IntValue;
				SQL_UpdateCash(gangId);
				showManageGang(client, gangId);
				
				PrintGangMessage(gangId, "\x07%N\x01 has paid the \x02weekly payment\x01.", client);
				
				WriteLogLine("\"%L\" has upgraded their weekly payment: \"%s\", payed: %s", client, g_esGangs[gangId].szName, AddCommas(g_cvWeekCost.IntValue));
			}
			case 1:
			{
				if (iGangCash < g_cvNameCost.IntValue)
				{
					PrintToChat(client, "%s The gang doesn't have enough cash (missing \x02%s\x01).", PREFIX, AddCommas(g_cvNameCost.IntValue - iGangCash));
					showManageGang(client, gangId);
					return;
				}
				PrintToChat(client, "%s Write the new name you would like to set, or \x02-1\x01 to abort.", PREFIX);
				g_esClients[client].iWrite = Write_Name;
			}
			case 2:
			{
				if (iGangCash < g_cvColorCost.IntValue)
				{
					PrintToChat(client, "%s The gang doesn't have enough cash (missing \x02%s\x01).", PREFIX, AddCommas(g_cvColorCost.IntValue - iGangCash));
					showManageGang(client, gangId);
					return;
				}
				showColors(client);
			}
			case 3:
			{
				PrintToChat(client, "%s Write the desired description you want, use double \x03SPACE\x01 for a new line (Max \x04%d\x01 lines) or type \x02%s\x01 to abort.", PREFIX, MAX_DESC_LINES, ABORT_SYMBOL);
				g_esClients[client].iWrite = Write_Desc;
			}
			case 4:
			{
				if (g_esClients[client].iRank < Rank_Leader)
				{
					showManageGang(client, gangId);
					return;
				}
				
				showTransferOwnerMembers(client, gangId);
			}
			case 5:
			{
				if (g_esClients[client].iRank < Rank_Leader)
				{
					showManageGang(client, gangId);
					return;
				}
				
				showDisbandGang(client);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
			showMainMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void SQL_GangsList_CB(Database db, DBResultSet results, const char[] error, any data)
{
	if (!StrEqual(error, ""))
	{
		LogError("Gangs List error, %s", error);
		return;
	}
	
	int iClient = GetClientFromSerial(data);
	
	char szItemInfo[8], szItem[256];
	
	Menu menu = new Menu(Handler_GangsList);
	menu.SetTitle("%s Gangs Menu - Top Gangs\n*The gangs are ordered by their cash amount\n ", PREFIX_MENU);
	
	while (results.FetchRow())
	{
		results.FetchString(0, szItem, sizeof(szItem));
		
		int gangId = getGangIdByName(szItem);
		IntToString(gangId, szItemInfo, sizeof(szItemInfo));
		
		RTLify(szItem, sizeof(szItem), szItem);
		Format(szItem, sizeof(szItem), "%s - [%s Cash]", szItem, AddCommas(results.FetchInt(1)));
		menu.AddItem(szItemInfo, szItem);
	}
	
	if (!menu.ItemCount) {
		menu.AddItem("", "No gang was found.", ITEMDRAW_DISABLED);
	}
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(iClient, MENU_TIME_FOREVER);
	HideHud(iClient, true);
}

public int Handler_GangsList(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int gangId = StringToInt(szItem);
		showGangDetails(client, gangId);
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
			showMainMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void showGangDetails(int client, int gangId)
{
	char szItem[128], szItemInfo[8], szTime[64];
	
	RTLify(szItem, sizeof(szItem), g_esGangs[gangId].szName);
	IntToString(gangId, szItemInfo, sizeof(szItemInfo));
	
	int iColor = g_esGangs[gangId].iColor;
	FormatTime(szTime, sizeof(szTime), "%d/%m/%Y - %H:%M:%S", g_esGangs[gangId].iExpiration);
	Menu menu = new Menu(Handler_GangDetails);
	menu.SetTitle("%s Gang Menu - \"%s\" Gang\n• Cash: %s Cash\n• Color: %s\n• Expire: %s\n• Online: %d/%d\n ", PREFIX_MENU, szItem, AddCommas(g_esGangs[gangId].iCash), g_szColors[iColor][Color_Name], szTime, getOnlinePlayers(gangId), g_esGangs[gangId].iMembers);
	
	menu.AddItem(szItemInfo, "Gang Members");
	
	Call_StartForward(g_fwdUserOpenGangDetails);
	Call_PushCell(client);
	Call_PushCell(menu);
	Call_Finish();
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_GangDetails(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[32];
		menu.GetItem(0, szItem, sizeof(szItem));
		int gangId = StringToInt(szItem);
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		
		Call_StartForward(g_fwdUserPressGangDetails);
		Call_PushCell(client);
		Call_PushCell(gangId);
		Call_PushString(szItem);
		Call_Finish();
		
		if (itemNum == 0)
		{
			SQL_ShowMembersList(client, gangId);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
			SQL_ShowGangsList(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void SQL_ShowMembersList_CB(Database db, DBResultSet results, const char[] error, any data)
{
	if (!StrEqual(error, ""))
	{
		LogError("Members List error, %s", error);
		return;
	}
	
	int iClient = GetClientFromSerial(data);
	
	char szItemInfo[8], szItem[256];
	
	int gangId = g_esClients[iClient].iLookingGang;
	RTLify(szItem, sizeof(szItem), g_esGangs[gangId].szName);
	
	Menu menu = new Menu(Handler_MembersList);
	menu.SetTitle("%s Gangs Menu - Gang \"%s\" Members\n• Total Members: %d/%s\n ", PREFIX_MENU, szItem, g_esGangs[gangId].iMembers, AddCommas(g_esGangs[gangId].iSlots));
	
	if (gangId == g_esClients[iClient].iGang)
	{
		int iFreeSlots = g_esGangs[gangId].iSlots - g_esGangs[gangId].iMembers;
		Format(szItem, sizeof(szItem), "Invite a Player [%d Free Slots]", iFreeSlots);
		menu.AddItem("", szItem, iFreeSlots == 0 || g_esClients[iClient].iRank == Rank_Member ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}
	
	char szName[MAX_NAME_LENGTH], szAuth[64];
	int iCount = 0;
	
	while (results.FetchRow())
	{
		results.FetchString(0, szAuth, sizeof(szAuth));
		results.FetchString(1, szName, sizeof(szName));
		int iRank = results.FetchInt(2);
		
		IntToString(iCount, szItemInfo, sizeof(szItemInfo));
		
		Format(szItem, sizeof(szItem), "%s [%s]", szName, g_szRanks[iRank]);
		menu.AddItem(szAuth, szItem);
		iCount++;
	}
	
	if (iCount == 0)
	{
		SQL_DeleteGang(gangId, false);
	}
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(iClient, MENU_TIME_FOREVER);
	HideHud(iClient, true);
}

void showLeaveGang(int client)
{
	Menu menu = new Menu(Handler_LeaveGang);
	menu.SetTitle("%s Are you sure you want to leave the gang?\n ", PREFIX_MENU);
	
	menu.AddItem("", "Yes");
	menu.AddItem("", "No");
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_LeaveGang(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		int gangId = g_esClients[client].iGang;
		switch (itemNum)
		{
			case 0:
			{
				PrintGangMessage(gangId, "\x02%N\x01 left the gang.", client);
				
				WriteLogLine("Player \"%L\" left the gang \"%s\"", client, g_esGangs[gangId].szName);
				
				SQL_UserLeaveGang(client);
				g_esGangs[gangId].iMembers--;
				char szQuery[512];
				g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `members` = %d WHERE `name` = '%s'", g_esGangs[gangId].iMembers, g_esGangs[gangId].szName);
				g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
			}
			case 1:
			{
				showMainMenu(client);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
		{
			showMainMenu(client);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public int Handler_MembersList(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		int gangId = g_esClients[client].iLookingGang;
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		
		
		switch (itemNum)
		{
			case 0:
			{
				if (gangId == g_esClients[client].iGang)
				{
					if (g_esGangs[gangId].iSlots - g_esGangs[gangId].iMembers == 0 || g_esClients[client].iRank == Rank_Member)
					{
						SQL_ShowMembersList(client, gangId);
						return;
					}
					showInviteMembers(client);
					return;
				}
				
				SQL_ShowMemberDetails(client, gangId, szItem);
				return;
			}
			default:
			{
				SQL_ShowMemberDetails(client, gangId, szItem);
			}
		}
		
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
		{
			int gangId = g_esClients[client].iLookingGang;
			if (g_esClients[client].bLookFromMainMenu)
			{
				g_esClients[client].bLookFromMainMenu = false;
				showMainMenu(client);
			} else {
				showGangDetails(client, gangId);
			}
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void showInviteMembers(int client)
{
	char szItem[MAX_NAME_LENGTH], szItemInfo[8];
	Menu menu = new Menu(Handler_InviteMembers);
	menu.SetTitle("%s Gangs Menu - Select a Player\n ", PREFIX_MENU);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && i != client && g_esClients[i].iGang == NO_GANG)
		{
			IntToString(i, szItemInfo, sizeof(szItemInfo));
			GetClientName(i, szItem, sizeof(szItem));
			menu.AddItem(szItemInfo, szItem);
		}
	}
	
	if (!menu.ItemCount)
	{
		menu.AddItem("", "No players are currently online.", ITEMDRAW_DISABLED);
	}
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_InviteMembers(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		int gangId = g_esClients[client].iLookingGang;
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int target = StringToInt(szItem);
		
		if (g_esGangs[gangId].iSlots - g_esGangs[gangId].iMembers <= 0 || g_esClients[client].iRank == Rank_Member)
		{
			SQL_ShowMembersList(client, gangId);
			return;
		}
		
		g_esClients[target].iWrite = Write_None;
		
		PrintGangMessage(gangId, "\x07%N\x01 has been invited to the gang by \x02%N\x01.", target, client);
		
		WriteLogLine("Player \"%L\" has invited %N to the gang \"%s\"", client, target, g_esGangs[gangId].szName);
		
		sendInviteToClient(target, gangId);
		
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
		{
			int gangId = g_esClients[client].iLookingGang;
			SQL_ShowMembersList(client, gangId);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void sendInviteToClient(int client, int gangId)
{
	char szItemInfo[8];
	IntToString(gangId, szItemInfo, sizeof(szItemInfo));
	Menu menu = new Menu(Handler_InviteClient);
	menu.SetTitle("%s You have been invited to join \"%s\" gang\n ", PREFIX_MENU, g_esGangs[gangId].szName);
	
	menu.AddItem(szItemInfo, "Agree");
	menu.AddItem("", "Decline");
	
	menu.ExitButton = false;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_InviteClient(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int gangId = StringToInt(szItem);
		
		if (itemNum != 0)
			return;
		
		if (g_esGangs[gangId].iSlots - g_esGangs[gangId].iMembers <= 0)
		{
			PrintToChat(client, "%s The gang doesn't have more slots.", PREFIX);
			return;
		}
		
		SQL_UserJoinGang(client, gangId, false);
		
		PrintGangMessage(gangId, "\x07%N\x01 has joined the gang.", client);
		
		WriteLogLine("Player \"%L\" has joined the gang \"%s\"", client, g_esGangs[gangId].szName);
		
		HideHud(client, false);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public void SQL_ShowMemberDetails_CB(Database db, DBResultSet results, const char[] error, any data)
{
	if (!StrEqual(error, ""))
	{
		LogError("Member Details error, %s", error);
		return;
	}
	
	int iClient = GetClientFromSerial(data);
	
	char szName[MAX_NAME_LENGTH], szAuth[64], szItem[128];
	
	if (results.FetchRow())
	{
		results.FetchString(0, szAuth, sizeof(szAuth));
		results.FetchString(1, szName, sizeof(szName));
		results.FetchString(2, szItem, sizeof(szItem));
		int iGang = getGangIdByName(szItem);
		int iRank = results.FetchInt(3);
		
		if (iRank == -1)
		{
			PrintToChat(iClient, "%s The selected player isn't available anymore.", PREFIX);
			return;
		}
		
		int iDonations = results.FetchInt(4);
		int iJoinDate = results.FetchInt(5);
		
		FormatTime(szItem, sizeof(szItem), "%d/%m/%Y", iJoinDate);
		
		Menu menu = new Menu(Handler_MemberDetails);
		menu.SetTitle("%s Gang Menu - Player Data\n \n%s | %s\n• Rank: %s\n• Join Date: %s\n• Cash Donations: %s Cash\n ", PREFIX_MENU, szName, szAuth, g_szRanks[iRank], szItem, AddCommas(iDonations));
		
		menu.AddItem("", "Promote Rank", (iRank > Rank_Manager || g_esClients[iClient].iRank <= Rank_Manager || g_esClients[iClient].iRank <= Rank_Manager || iRank >= g_esClients[iClient].iRank || iGang != g_esClients[iClient].iGang || GetClientFromAuthId(szAuth) == iClient) ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
		
		menu.AddItem("", "Demote Rank", (iRank == Rank_Leader || iRank == Rank_Member || g_esClients[iClient].iRank <= Rank_Manager || iRank >= g_esClients[iClient].iRank || iGang != g_esClients[iClient].iGang || GetClientFromAuthId(szAuth) == iClient) ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
		
		menu.AddItem("", "Kick Player", (iRank == Rank_Leader || g_esClients[iClient].iRank == Rank_Member || iRank >= g_esClients[iClient].iRank || iGang != g_esClients[iClient].iGang || GetClientFromAuthId(szAuth) == iClient) ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
		
		FixMenuGap(menu);
		
		menu.ExitBackButton = true;
		menu.Display(iClient, MENU_TIME_FOREVER);
		HideHud(iClient, true);
		
		strcopy(g_esMemberDetails[iClient].szAuth, sizeof(g_esMemberDetails[].szAuth), szAuth);
		strcopy(g_esMemberDetails[iClient].szName, sizeof(g_esMemberDetails[].szName), szName);
		g_esMemberDetails[iClient].iRank = iRank;
		g_esMemberDetails[iClient].iGang = iGang;
	}
}

public int Handler_MemberDetails(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		int gangId = g_esClients[client].iLookingGang;
		
		int clientId = GetClientFromAuthId(g_esMemberDetails[client].szAuth);
		
		switch (itemNum)
		{
			case 0:
			{
				if (g_esMemberDetails[client].iRank > Rank_Manager)
				{
					SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
					return;
				}
				if (g_esClients[client].iRank <= Rank_Manager)
				{
					SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
					return;
				}
				if (g_esMemberDetails[client].iRank >= g_esClients[client].iRank)
				{
					SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
					return;
				}
				if (g_esMemberDetails[client].iGang != g_esClients[client].iGang)
				{
					SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
					return;
				}
				int iRank = g_esMemberDetails[client].iRank + 1;
				if (clientId != -1)
				{
					g_esClients[clientId].iRank = iRank;
				}
				
				PrintGangMessage(gangId, "\x07%s\x01 has been \x04promoted\x01 to \x04%s\x01 by \x02%N\x01.", g_esMemberDetails[client].szName, g_szRanks[iRank], client);
				
				WriteLogLine("Player \"%L\" has promoted %s (Auth: %s) to %s", client, g_esMemberDetails[client].szName, g_esMemberDetails[client].szAuth, g_szRanks[iRank]);
				
				char szQuery[512];
				g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `rank` = %d WHERE `steam_id` = '%s'", iRank, g_esMemberDetails[client].szAuth);
				g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
				
				SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
			}
			case 1:
			{
				if (g_esMemberDetails[client].iRank == Rank_Leader || g_esMemberDetails[client].iRank == Rank_Member)
				{
					SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
					return;
				}
				if (g_esClients[client].iRank <= Rank_Manager)
				{
					SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
					return;
				}
				if (g_esMemberDetails[client].iRank >= g_esClients[client].iRank)
				{
					SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
					return;
				}
				if (g_esMemberDetails[client].iGang != g_esClients[client].iGang)
				{
					SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
					return;
				}
				int iRank = g_esMemberDetails[client].iRank - 1;
				if (clientId != -1)
				{
					g_esClients[clientId].iRank = iRank;
				}
				
				PrintGangMessage(gangId, "\x07%s\x01 has been \x02demoted\x01 to \x04%s\x01 by \x02%N\x01.", g_esMemberDetails[client].szName, g_szRanks[iRank], client);
				
				WriteLogLine("Player \"%L\" has demoted %s (Auth: %s) to %s", client, g_esMemberDetails[client].szName, g_esMemberDetails[client].szAuth, g_szRanks[iRank]);
				
				char szQuery[512];
				g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `rank` = %d WHERE `steam_id` = '%s'", iRank, g_esMemberDetails[client].szAuth);
				g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
				
				SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
			}
			case 2:
			{
				if (g_esMemberDetails[client].iRank >= g_esClients[client].iRank)
				{
					SQL_ShowMemberDetails(client, gangId, g_esMemberDetails[client].szAuth);
					return;
				}
				
				PrintGangMessage(gangId, "\x07%s\x01 has been kicked by \x02%N\x01.", g_esMemberDetails[client].szName, client);
				
				WriteLogLine("Player \"%L\" has kicked %s (Auth: %s) from the gang \"%s\"", client, g_esMemberDetails[client].szName, g_esMemberDetails[client].szAuth, g_esGangs[g_esMemberDetails[client].iGang].szName);
				
				if (clientId != -1)
				{
					if (g_esClients[clientId].iGang == -1)
					{
						return;
					}
					
					g_esClients[clientId].iGang = -1;
					g_esClients[clientId].iRank = Rank_NoGang;
				}
				
				g_esGangs[g_esMemberDetails[client].iGang].iMembers--;
				
				char szQuery[512];
				g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `members` = %d WHERE `name` = '%s'", g_esGangs[g_esMemberDetails[client].iGang].iMembers, g_esGangs[g_esMemberDetails[client].iGang].szName);
				g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
				g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `gang` = '', `rank` = %d WHERE `steam_id` = '%s'", Rank_NoGang, g_esMemberDetails[client].szAuth);
				g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
				HideHud(client, false);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
		{
			int gangId = g_esClients[client].iLookingGang;
			SQL_ShowMembersList(client, gangId);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void showTransferOwnerMembers(int client, int gangId)
{
	char szItem[MAX_NAME_LENGTH], szItemInfo[8];
	Menu menu = new Menu(Handler_TransferOwnerMembers);
	menu.SetTitle("%s Gangs Menu - Select a Player\n ", PREFIX_MENU);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && i != client && g_esClients[i].iGang == gangId)
		{
			IntToString(i, szItemInfo, sizeof(szItemInfo));
			GetClientName(i, szItem, sizeof(szItem));
			menu.AddItem(szItemInfo, szItem);
		}
	}
	
	if (!menu.ItemCount)
	{
		menu.AddItem("", "No players are currently online", ITEMDRAW_DISABLED);
	}
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_TransferOwnerMembers(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		int gangId = g_esClients[client].iGang;
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		int target = StringToInt(szItem);
		g_esClients[client].iRank = Rank_Deputy_Leader;
		g_esClients[target].iRank = Rank_Leader;
		
		PrintGangMessage(gangId, "\x07%N\x01 transfered the ownership to \x02%N\x01.", client, target);
		
		WriteLogLine("\"%L\" transfer the ownership to %N, Gang: \"%s\"", client, target, g_esGangs[gangId].szName);
		
		SQL_TransferOwner(gangId, client, target);
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
		{
			int gangId = g_esClients[client].iGang;
			if (g_esClients[client].iRank == Rank_Leader)
				showManageGang(client, gangId);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

void showDisbandGang(int client)
{
	Menu menu = new Menu(Handler_DisbandGang);
	menu.SetTitle("%s Are you sure you want to disband the gang?\n ", PREFIX_MENU);
	
	menu.AddItem("", "Yes");
	menu.AddItem("", "No");
	
	FixMenuGap(menu);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	HideHud(client, true);
}

public int Handler_DisbandGang(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		int gangId = g_esClients[client].iGang;
		char szItem[32];
		menu.GetItem(itemNum, szItem, sizeof(szItem));
		switch (itemNum)
		{
			case 0:
			{
				PrintGangMessage(gangId, "\x07%N\01 has disbanded the gang.", client);
				
				WriteLogLine("Player \"%L\" has disbanded his gang (%s)", client, g_esGangs[gangId].szName);
				
				SQL_DeleteGang(gangId, false);
			}
			case 1:
			{
				showManageGang(client, gangId);
			}
		}
	}
	else if (action == MenuAction_Cancel)
	{
		HideHud(client, false);
		if (itemNum == MenuCancel_ExitBack)
		{
			int gangId = g_esClients[client].iGang;
			if (g_esClients[client].iRank == Rank_Leader)
				showManageGang(client, gangId);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/* */

/* Natives */

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Gangs_GetGangCash", Native_GetGangCash);
	CreateNative("Gangs_SetGangCash", Native_SetGangCash);
	CreateNative("Gangs_GetGangSlots", Native_GetGangSlots);
	CreateNative("Gangs_SetGangSlots", Native_SetGangSlots);
	CreateNative("Gangs_GetGangName", Native_GetGangName);
	CreateNative("Gangs_GetGangColor", Native_GetGangColor);
	CreateNative("Gangs_GetGangsCount", Native_GetGangsCount);
	CreateNative("Gangs_GetPlayerGang", Native_GetPlayerGang);
	CreateNative("Gangs_GetPlayerGangRank", Native_GetPlayerGangRank);
	CreateNative("Gangs_SendMessageToGang", Native_SendMessageToGang);
	CreateNative("Gangs_ShowMainMenu", Native_ShowMainMenu);
	CreateNative("Gangs_ShowGangDetails", Native_ShowGangDetails);
	CreateNative("Gangs_CreateDBColumn", Native_CreateDBColumn);
	
	g_fwdGangsLoaded = CreateGlobalForward("Gangs_GangsLoaded", ET_Event, Param_Cell, Param_Cell);
	g_fwdUserLoaded = CreateGlobalForward("Gangs_GangsUserLoaded", ET_Event, Param_Cell, Param_Cell);
	g_fwdUserOpenMainMenu = CreateGlobalForward("Gangs_GangsUserOpenMainMenu", ET_Event, Param_Cell, Param_Cell);
	g_fwdUserPressMainMenu = CreateGlobalForward("Gangs_GangsUserPressMainMenu", ET_Event, Param_Cell, Param_String);
	g_fwdUserOpenGangDetails = CreateGlobalForward("Gangs_GangsUserOpenGangDetails", ET_Event, Param_Cell, Param_Cell);
	g_fwdUserPressGangDetails = CreateGlobalForward("Gangs_GangsUserPressGangDetails", ET_Event, Param_Cell, Param_Cell, Param_String);
	g_fwdUpdateName = CreateGlobalForward("Gangs_GangNameUpdated", ET_Event, Param_Cell, Param_String, Param_String);
	g_fwdCreateGang = CreateGlobalForward("Gangs_OnGangCreate", ET_Event, Param_Cell);
	g_fwdDeleteGang = CreateGlobalForward("Gangs_OnGangDelete", ET_Event, Param_Cell, Param_String);
	
	RegPluginLibrary("JB_GangsSystem");
	return APLRes_Success;
}

public int Native_GetGangCash(Handle plugin, int numParams)
{
	int gangId = GetNativeCell(1);
	
	if (gangId < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid gang (%d)", gangId);
	
	return g_esGangs[gangId].iCash;
}

public int Native_SetGangCash(Handle plugin, int numParams)
{
	int gangId = GetNativeCell(1);
	int amount = GetNativeCell(2);
	
	if (gangId < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid gang (%d)", gangId);
	if (amount < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid amount (%d)", amount);
	
	char szFile[64];
	GetPluginFilename(plugin, szFile, sizeof(szFile));
	WriteLogLine("Cash of gang \"%s\" was changed to %s from %s by plugin %s", g_esGangs[gangId].szName, AddCommas(amount), AddCommas(g_esGangs[gangId].iCash), szFile);
	
	g_esGangs[gangId].iCash = amount;
	SQL_UpdateCash(gangId);
	return 0;
}

public int Native_GetGangSlots(Handle plugin, int numParams)
{
	int gangId = GetNativeCell(1);
	
	if (gangId < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid gang (%d)", gangId);
	
	return g_esGangs[gangId].iSlots;
}

public int Native_SetGangSlots(Handle plugin, int numParams)
{
	int gangId = GetNativeCell(1);
	int amount = GetNativeCell(2);
	
	if (gangId < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid gang (%d)", gangId);
	if (amount < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid amount (%d)", amount);
	
	char szFile[64];
	GetPluginFilename(plugin, szFile, sizeof(szFile));
	WriteLogLine("Slots of gang \"%s\" was changed to %s from %s by plugin %s", g_esGangs[gangId].szName, AddCommas(amount), AddCommas(g_esGangs[gangId].iSlots), szFile);
	
	g_esGangs[gangId].iSlots = amount;
	SQL_UpdateSlot(gangId);
	return 0;
}

public int Native_GetGangName(Handle plugin, int numParams)
{
	int gangId = GetNativeCell(1);
	int len = GetNativeCell(3);
	
	if (len <= 0)
	{
		return 0;
	}
	
	char[] buffer = new char[len + 1];
	GetNativeString(2, buffer, len);
	
	if (gangId < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid gang (%d)", gangId);
	
	strcopy(buffer, len, g_esGangs[gangId].szName);
	SetNativeString(2, buffer, len);
	return 0;
}

public int Native_GetGangColor(Handle plugin, int numParams)
{
	int gangId = GetNativeCell(1);
	
	if (gangId < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid gang (%d)", gangId);
	
	return g_esGangs[gangId].iColor;
}

public int Native_GetGangsCount(Handle plugin, int numParams)
{
	return g_iNumOfGangs;
}

public int Native_GetPlayerGang(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client == 0)
		return 0;
	if (!IsClientInGame(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	
	return g_esClients[client].iGang;
}

public int Native_GetPlayerGangRank(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client == 0)
		return 0;
	if (!IsClientInGame(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	
	return g_esClients[client].iRank;
}

public int Native_SendMessageToGang(Handle plugin, int numParams)
{
	int gangId = GetNativeCell(1);
	
	char message[256];
	GetNativeString(2, message, sizeof(message));
	
	if (gangId < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid gang (%d)", gangId);
	
	PrintGangMessage(gangId, message);
	return 0;
}

public int Native_ShowMainMenu(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	
	if (client == 0)
		return 0;
	if (!IsClientInGame(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	
	showMainMenu(client);
	return 0;
}

public int Native_ShowGangDetails(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int gangId = GetNativeCell(2);
	
	if (client == 0)
		return 0;
	if (!IsClientInGame(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	if (gangId < 0)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid gang (%d)", gangId);
	
	showGangDetails(client, gangId);
	return 0;
}

public int Native_CreateDBColumn(Handle plugin, int numParams)
{
	char szColumn[128], szType[32], szDefaultValue[64];
	GetNativeString(1, szColumn, sizeof(szColumn));
	GetNativeString(2, szType, sizeof(szType));
	GetNativeString(3, szDefaultValue, sizeof(szDefaultValue));
	
	DataPack dPack = new DataPack();
	dPack.WriteString(szColumn);
	dPack.WriteString(szType);
	dPack.WriteString(szDefaultValue);
	dPack.Reset();
	
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "SHOW COLUMNS FROM `jb_gangs` LIKE '%s'", szColumn);
	g_dbDatabase.Query(SQL_CreateDBColumn_CB, szQuery, dPack);
}

/* */

void SQL_MakeConnection()
{
	delete g_dbDatabase;
	Database.Connect(SQL_CB_OnDatabaseConnected, DATABASE_ENTRY);
}

public void SQL_CB_OnDatabaseConnected(Database db, const char[] error, any data)
{
	if (db == null)
		SetFailState("Cannot Connect To MySQL Server! | Error: %s", error);
	
	g_dbDatabase = db;
	
	g_dbDatabase.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `jb_gangs` (`name` VARCHAR(128) NOT NULL, `desc` VARCHAR(256) NOT NULL, `cash` INT NOT NULL, `members` INT NOT NULL, `slots` INT NOT NULL, `expiration` INT NOT NULL, `color` VARCHAR(64) NOT NULL, UNIQUE(`name`))");
	g_dbDatabase.Query(SQL_CheckForErrors, "CREATE TABLE IF NOT EXISTS `jb_gangs_players` (`steam_id` VARCHAR(128) NOT NULL, `name` VARCHAR(128) NOT NULL, `gang` VARCHAR(128) NOT NULL, `rank` INT NOT NULL DEFAULT -1, `donations` INT NOT NULL, `joindate` INT NOT NULL, UNIQUE(`steam_id`))");
	SQL_AfterTableCreated();
}

void SQL_AfterTableCreated()
{
	for (int iCurrentGang = 0; iCurrentGang < MAX_GANGS; iCurrentGang++) {
		g_esGangs[iCurrentGang].reset();
	}
	
	SQL_FetchGangs(false);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient)) {
			OnClientPostAdminCheck(iCurrentClient);
		}
	}
}

void SQL_FetchGangs(bool fixGang)
{
	char szQuery[32];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "SELECT * FROM `jb_gangs`");
	g_dbDatabase.Query(SQL_FetchGangs_CB, szQuery, fixGang);
}

public void SQL_FetchGangs_CB(Database db, DBResultSet results, const char[] error, bool fixGang)
{
	if (!StrEqual(error, ""))
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	g_iNumOfGangs = 0;
	char szColor[64];
	
	if (results.FetchRow())
	{
		do {
			results.FetchString(0, g_esGangs[g_iNumOfGangs].szName, sizeof(g_esGangs[].szName));
			results.FetchString(1, g_esGangs[g_iNumOfGangs].szDesc, sizeof(g_esGangs[].szDesc));
			g_esGangs[g_iNumOfGangs].iCash = results.FetchInt(2);
			g_esGangs[g_iNumOfGangs].iMembers = results.FetchInt(3);
			g_esGangs[g_iNumOfGangs].iSlots = results.FetchInt(4);
			g_esGangs[g_iNumOfGangs].iExpiration = results.FetchInt(5);
			results.FetchString(6, szColor, sizeof(szColor));
			g_esGangs[g_iNumOfGangs].iColor = getColorId(szColor);
			
			if (g_esGangs[g_iNumOfGangs].iExpiration <= GetTime())
			{
				WriteLogLine("Gang %s has been closed for not paying their weekly payment (Slots [%d] | Cash [%s] | Members [%d] | Expire-Stamp [%d] | Current-Stamp [%d])", g_esGangs[g_iNumOfGangs].szName, g_esGangs[g_iNumOfGangs].iSlots, AddCommas(g_esGangs[g_iNumOfGangs].iCash), g_esGangs[g_iNumOfGangs].iMembers, g_esGangs[g_iNumOfGangs].iExpiration, GetTime());
				SQL_DeleteGang(g_iNumOfGangs, true);
			}
			else
			{
				g_iNumOfGangs++;
			}
		}
		while (results.FetchRow());
	}
	
	if (!fixGang)
	{
		Call_StartForward(g_fwdGangsLoaded);
		Call_PushCell(db);
		Call_PushCell(g_iNumOfGangs);
		Call_Finish();
	}
}

void SQL_FetchUser(int client)
{
	char szQuery[128];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "SELECT * FROM `jb_gangs_players` WHERE `steam_id` = '%s'", g_esClients[client].szAuth);
	g_dbDatabase.Query(SQL_FetchUser_CB, szQuery, GetClientSerial(client));
}

public void SQL_FetchUser_CB(Database db, DBResultSet results, const char[] error, any data)
{
	if (!StrEqual(error, ""))
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	int iClient = GetClientFromSerial(data);
	
	char szGang[128], szName[MAX_NAME_LENGTH], szAuth[64];
	
	if (results.FetchRow())
	{
		results.FetchString(0, szAuth, sizeof(szAuth));
		results.FetchString(1, szName, sizeof(szName));
		if (!StrEqual(szName, g_esClients[iClient].szName))
		{
			SQL_UpdateClientName(szAuth, g_esClients[iClient].szName);
		}
		results.FetchString(2, szGang, sizeof(szGang));
		g_esClients[iClient].iGang = getGangIdByName(szGang);
		g_esClients[iClient].iRank = results.FetchInt(3);
		g_esClients[iClient].iDonations = results.FetchInt(4);
	} else {
		char szQuery[512];
		g_dbDatabase.Format(szQuery, sizeof(szQuery), "INSERT INTO `jb_gangs_players` (`steam_id`, `name`) VALUES ('%s', '%s')", g_esClients[iClient].szAuth, g_esClients[iClient].szName);
		g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
		
		g_esClients[iClient].iGang = NO_GANG;
		g_esClients[iClient].iRank = Rank_NoGang;
		g_esClients[iClient].iDonations = 0;
	}
	
	Call_StartForward(g_fwdUserLoaded);
	Call_PushCell(iClient);
	Call_PushCell(g_esClients[iClient].iGang);
	Call_Finish();
}

void SQL_UpdateClientName(char[] auth, char[] newName)
{
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `name` = '%s' WHERE `steam_id` = '%s'", newName, auth);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
}

void SQL_CreateGang(int client)
{
	int iColor = g_esCreateGang[client].iColor;
	strcopy(g_esGangs[g_iNumOfGangs].szName, sizeof(g_esGangs[].szName), g_esCreateGang[client].szName);
	strcopy(g_esGangs[g_iNumOfGangs].szDesc, sizeof(g_esGangs[].szDesc), DEFAULT_CREATION_DESC);
	g_esGangs[g_iNumOfGangs].iSlots = DEFAULT_GANG_SLOTS;
	g_esGangs[g_iNumOfGangs].iExpiration = GetTime() + SECONDS_WEEK;
	g_esGangs[g_iNumOfGangs].iColor = iColor;
	
	Call_StartForward(g_fwdCreateGang);
	Call_PushCell(g_iNumOfGangs);
	Call_Finish();
	
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "INSERT INTO `jb_gangs` (`name`, `desc`, `members`, `slots`, `expiration`, `color`) VALUES ('%s', '%s', 1, %d, %d, '%s')", g_esGangs[g_iNumOfGangs].szName, g_esGangs[g_iNumOfGangs].szDesc, g_esGangs[g_iNumOfGangs].iSlots, g_esGangs[g_iNumOfGangs].iExpiration, g_szColors[iColor][Color_Name]);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
	SQL_UserJoinGang(client, g_iNumOfGangs, true);
	g_iNumOfGangs++;
	
	g_esCreateGang[client].reset();
}

void SQL_UserJoinGang(int client, int gangId, bool gangCreate)
{
	char szQuery[512];
	g_esClients[client].iGang = gangId;
	g_esClients[client].iRank = gangCreate ? Rank_Leader:Rank_Member;
	g_esClients[client].iDonations = 0;
	g_esGangs[gangId].iMembers++;
	
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `members` = %d WHERE `name` = '%s'", g_esGangs[gangId].iMembers, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `gang` = '%s', `rank` = %d, `donations` = 0, `joindate` = %d WHERE `steam_id` = '%s'", g_esGangs[gangId].szName, g_esClients[client].iRank, GetTime(), g_esClients[client].szAuth);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
}

void SQL_UserLeaveGang(int client)
{
	char szQuery[512];
	
	g_esClients[client].iGang = NO_GANG;
	g_esClients[client].iRank = Rank_NoGang;
	
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `gang` = '', `rank` = %d WHERE `steam_id` = '%s'", Rank_NoGang, g_esClients[client].szAuth);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
}

void SQL_ChangeGangName(int gangId, const char[] newName)
{
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `name` = '%s' WHERE `name` = '%s'", newName, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
	
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `gang` = '%s' WHERE `gang` = '%s'", newName, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
	
	Call_StartForward(g_fwdUpdateName);
	Call_PushCell(gangId);
	Call_PushString(g_esGangs[gangId].szName);
	Call_PushString(newName);
	Call_Finish();
	
	strcopy(g_esGangs[gangId].szName, sizeof(g_esGangs[].szName), newName);
}

void SQL_ChangeGangColor(int gangId, int iColor)
{
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `color` = '%s' WHERE `name` = '%s'", g_szColors[iColor][Color_Name], g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
}

void SQL_UpdateSlot(int gangId)
{
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `slots` = %d WHERE `name` = '%s'", g_esGangs[gangId].iSlots, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
}

void SQL_AddWeek(int gangId)
{
	g_esGangs[gangId].iExpiration = g_esGangs[gangId].iExpiration + SECONDS_WEEK;
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `expiration` = %d WHERE `name` = '%s'", g_esGangs[gangId].iExpiration, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
}

void SQL_DeleteGang(int gangId, bool expire)
{
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && g_esClients[iCurrentClient].iGang == gangId)
		{
			SQL_UserLeaveGang(iCurrentClient);
		}
	}
	
	g_esGangs[gangId].iColor = -1;
	
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "DELETE FROM `jb_gangs` WHERE `name` = '%s'", g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
	
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `gang` = '', `rank` = %d WHERE `gang` = '%s'", Rank_NoGang, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
	
	Call_StartForward(g_fwdDeleteGang);
	Call_PushCell(gangId);
	Call_PushString(g_esGangs[gangId].szName);
	Call_Finish();
	
	if (!expire)
	{
		FixGangs();
	}
}

void SQL_Donate(int client, int gangId, int amount)
{
	g_esClients[client].iDonations += amount;
	int iDonations = g_esClients[client].iDonations;
	g_esGangs[gangId].iCash += amount;
	
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `cash` = %d WHERE `name` = '%s'", g_esGangs[gangId].iCash, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
	
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `donations` = %d WHERE `steam_id` = '%s' AND `gang` = '%s'", iDonations, g_esClients[client].szAuth, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
}

void SQL_UpdateCash(int gangId)
{
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs` SET `cash` = %d WHERE `name` = '%s'", g_esGangs[gangId].iCash, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
}

void SQL_TransferOwner(int gangId, int client, int newOwner)
{
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `rank` = %d WHERE `steam_id` = '%s' AND `gang` = '%s'", Rank_Manager, g_esClients[client].szAuth, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
	
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "UPDATE `jb_gangs_players` SET `rank` = %d WHERE `steam_id` = '%s' AND `gang` = '%s'", Rank_Leader, g_esClients[newOwner].szAuth, g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
}

void SQL_ShowGangsList(int client)
{
	char szQuery[512];
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "SELECT `name`, `cash` FROM `jb_gangs` ORDER BY `cash` DESC");
	g_dbDatabase.Query(SQL_GangsList_CB, szQuery, GetClientSerial(client));
}

void SQL_ShowMembersList(int client, int gangId)
{
	char szQuery[512];
	g_esClients[client].iLookingGang = gangId;
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "SELECT `steam_id`, `name`, `rank` FROM `jb_gangs_players` WHERE `gang` = '%s' ORDER BY `rank` DESC", g_esGangs[gangId].szName);
	g_dbDatabase.Query(SQL_ShowMembersList_CB, szQuery, GetClientSerial(client));
}

void SQL_ShowMemberDetails(int client, int gangId, char[] szAuth)
{
	char szQuery[512];
	g_esClients[client].iLookingGang = gangId;
	g_dbDatabase.Format(szQuery, sizeof(szQuery), "SELECT * FROM `jb_gangs_players` WHERE `steam_id` = '%s'", szAuth);
	g_dbDatabase.Query(SQL_ShowMemberDetails_CB, szQuery, GetClientSerial(client));
}

public void SQL_CreateDBColumn_CB(Database db, DBResultSet results, const char[] error, DataPack dPack)
{
	if (!StrEqual(error, ""))
	{
		LogError("Databse error, %s", error);
		return;
	}
	
	char szColumn[128], szType[32], szDefaultValue[64];
	dPack.ReadString(szColumn, sizeof(szColumn));
	dPack.ReadString(szType, sizeof(szType));
	dPack.ReadString(szDefaultValue, sizeof(szDefaultValue));
	dPack.Close();
	
	if (!results.FetchRow())
	{
		char szQuery[128];
		Format(szQuery, sizeof(szQuery), " DEFAULT '%s'", szDefaultValue);
		g_dbDatabase.Format(szQuery, sizeof(szQuery), "ALTER TABLE `jb_gangs` ADD COLUMN `%s` %s NOT NULL%s", szColumn, szType, szDefaultValue[0] ? szQuery:"");
		g_dbDatabase.Query(SQL_CheckForErrors, szQuery);
	}
}

void SQL_UpdateGangDesc(int gang_index)
{
	char Query[512];
	g_dbDatabase.Format(Query, sizeof(Query), "UPDATE `jb_gangs` SET `desc` = '%s' WHERE `name` = '%s'", g_esGangs[gang_index].szDesc, g_esGangs[gang_index].szName);
	g_dbDatabase.Query(SQL_CheckForErrors, Query);
}

public void SQL_CheckForErrors(Database db, DBResultSet results, const char[] error, any data)
{
	if (!StrEqual(error, ""))
	{
		LogError("Databse error, %s", error);
		return;
	}
}

/* Functions */

int getGangIdByName(const char[] name)
{
	for (int iCurrentGang = 0; iCurrentGang < g_iNumOfGangs; iCurrentGang++)
	{
		if (StrEqual(g_esGangs[iCurrentGang].szName, name, true)) {
			return iCurrentGang;
		}
	}
	return -1;
}

int getGangIdByColor(int color)
{
	for (int iCurrentGang = 0; iCurrentGang < g_iNumOfGangs; iCurrentGang++)
	{
		if (g_esGangs[iCurrentGang].iColor == color) {
			return iCurrentGang;
		}
	}
	return -1;
}

int getColorId(char[] color)
{
	for (int iCurrentColor = 0; iCurrentColor < sizeof(g_szColors); iCurrentColor++)
	{
		if (StrEqual(g_szColors[iCurrentColor][Color_Name], color)) {
			return iCurrentColor;
		}
	}
	
	return -1;
}

int GetClientFromAuthId(const char[] auth)
{
	char szAuth[MAX_NAME_LENGTH];
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient))
		{
			GetClientAuthId(iCurrentClient, AuthId_Steam2, szAuth, sizeof(szAuth));
			if (StrEqual(szAuth, auth, true)) {
				return iCurrentClient;
			}
		}
	}
	return -1;
}

void setFreeColor(int client)
{
	int color = 0;
	int iGangIndex = getGangIdByColor(color);
	while (iGangIndex != -1)
	{
		color++;
		iGangIndex = getGangIdByColor(color);
	}
	g_esCreateGang[client].iColor = color;
}

int getOnlinePlayers(int gangId)
{
	int nCount = 0;
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && !IsFakeClient(iCurrentClient) && g_esClients[iCurrentClient].iGang == gangId)
		{
			nCount++;
		}
	}
	return nCount;
}

void PrintGangMessage(int gangId, char[] message, any...)
{
	char szMessage[256];
	VFormat(szMessage, sizeof(szMessage), message, 3);
	
	for (int iCurrentClient = 1; iCurrentClient <= MaxClients; iCurrentClient++)
	{
		if (IsClientInGame(iCurrentClient) && g_esClients[iCurrentClient].iGang == gangId) {
			PrintToChat(iCurrentClient, " \x04[%s]\x01 %s", g_esGangs[gangId].szName, szMessage);
		}
	}
}

void FixGangs()
{
	for (int iCurrentGang = 0; iCurrentGang < MAX_GANGS; iCurrentGang++)
	{
		g_esGangs[iCurrentGang].reset();
	}
	
	SQL_FetchGangs(true);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPostAdminCheck(i);
		}
	}
}

/* */