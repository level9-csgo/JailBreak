void Commands_OnSettingsLoad(KeyValues kv)
{
	if (kv.JumpToKey("Commands", false))
	{
		char buffer[SHOP_MAX_STRING_LENGTH];
		
		kv.GetString("Give_Credits", buffer, sizeof(buffer));
		TrimString(buffer);
		RegConsoleCmd(buffer, Commands_GiveCredits, "How many credits to give to players");
		
		kv.GetString("Take_Credits", buffer, sizeof(buffer));
		TrimString(buffer);
		RegConsoleCmd(buffer, Commands_TakeCredits, "How many credits to take from players");
		
		kv.GetString("Set_Credits", buffer, sizeof(buffer));
		TrimString(buffer);
		RegConsoleCmd(buffer, Commands_SetCredits, "How many credits to set to players");
		
		kv.GetString("Main_Menu", buffer, sizeof(buffer));
		TrimString(buffer);
		
		char part[64];
		int reloc_idx, var2;
		int row;
		while ((var2 = SplitString(buffer[reloc_idx], ",", part, sizeof(part))))
		{
			if (var2 == -1)
				strcopy(part, sizeof(part), buffer[reloc_idx]);
			else
				reloc_idx += var2;
			
			TrimString(part);
			
			if (!part[0])
				continue;
			
			if (!row)
			{
				int start;
				if (!StrContains(part, "sm_", true))
				{
					start = 3;
				}
				strcopy(g_sChatCommand, sizeof(g_sChatCommand), part[start]);
			}
			
			RegConsoleCmd(part, Commands_Shop, "Open up main menu");
			
			if (var2 == -1)
				break;
			
			row++;
		}
		
		kv.GetString("View_Credits", buffer, sizeof(buffer));
		TrimString(buffer);
		
		part[0] = '\0';
		reloc_idx = 0; var2 = 0; row = 0;
		
		while ((var2 = SplitString(buffer[reloc_idx], ",", part, sizeof(part))))
		{
			if (var2 == -1)
				strcopy(part, sizeof(part), buffer[reloc_idx]);
			else
				reloc_idx += var2;
			
			TrimString(part);
			
			if (!part[0])
				continue;
			
			RegConsoleCmd(part, Commands_Credits, "View credits amount");
			
			if (var2 == -1)
				break;
			
			row++;
		}
		
		kv.Rewind();
	}
}

public Action Commands_Shop(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (!IsAuthorizedIn(client))
	{
		CPrintToChat(client, "%t", "DataLoading");
		return Plugin_Handled;
	}
	
	ShowMainMenu(client);
	
	return Plugin_Handled;
}

public Action Commands_GiveCredits(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (!IsAdmin(client))
	{
		CPrintToChat(client, "%t", "NoAccessToCommand");
		return Plugin_Handled;
	}
	
	char buffer[96];
	if (args < 2)
	{
		GetCmdArg(0, buffer, sizeof(buffer));
		ReplyToCommand(client, " \x04[Play-IL]\x01 Usage: %s <name|#userid> <credits>", buffer);
		return Plugin_Handled;
	}
	
	char pattern[96], money[32];
	GetCmdArg(1, pattern, sizeof(pattern));
	GetCmdArg(2, money, sizeof(money));
	
	int[] targets = new int[MaxClients];
	bool ml;
	
	int imoney = StringToInt(money);
	
	int count = ProcessTargetString(pattern, client, targets, MaxClients, COMMAND_FILTER_NO_BOTS, buffer, sizeof(buffer), ml);
	
	if (count < 1)
	{
		if (client)
		{
			CPrintToChat(client, "%t", "TargetNotFound", pattern);
		}
		else
		{
			ReplyToCommand(client, "%t", "TargetNotFound", pattern);
		}
	}
	else
	{
		for (int i = 0; i < count; i++)
		{
			if (targets[i] != client && !CanUserTarget(client, targets[i]))continue;
			
			GiveCredits(targets[i], imoney, client);
		}
		if (ml)
		{
			Format(buffer, sizeof(buffer), "%T", buffer, client);
		}
		if (client)
		{
			CPrintToChat(client, "%t", "give_credits_success", AddCommas(imoney), buffer);
		}
		else
		{
			ReplyToCommand(client, "%t", "give_credits_success", AddCommas(imoney), buffer);
		}
	}
	
	return Plugin_Handled;
}

public Action Commands_TakeCredits(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (!IsAdmin(client))
	{
		CPrintToChat(client, "%t", "NoAccessToCommand");
		return Plugin_Handled;
	}
	char buffer[96];
	if (args < 2)
	{
		GetCmdArg(0, buffer, sizeof(buffer));
		ReplyToCommand(client, " \x04[Play-IL]\x01 Usage: %s <name|#userid> <credits>", buffer);
		return Plugin_Handled;
	}
	
	char pattern[96], money[32];
	GetCmdArg(1, pattern, sizeof(pattern));
	GetCmdArg(2, money, sizeof(money));
	
	int[] targets = new int[MaxClients];
	bool ml;
	
	int imoney = StringToInt(money);
	
	int count = ProcessTargetString(pattern, client, targets, MaxClients, COMMAND_FILTER_NO_BOTS, buffer, sizeof(buffer), ml);
	
	if (count < 1)
	{
		if (client)
		{
			CPrintToChat(client, "%t", "TargetNotFound", pattern);
		}
		else
		{
			ReplyToCommand(client, "%t", "TargetNotFound", pattern);
		}
	}
	else
	{
		for (int i = 0; i < count; i++)
		{
			if (targets[i] != client && !CanUserTarget(client, targets[i]))continue;
			
			RemoveCredits(targets[i], imoney, client);
		}
		if (ml)
		{
			Format(buffer, sizeof(buffer), "%T", buffer, client);
		}
		if (client)
		{
			CPrintToChat(client, "%t", "remove_credits_success", AddCommas(imoney), buffer);
		}
		else
		{
			ReplyToCommand(client, "%t", "remove_credits_success", AddCommas(imoney), buffer);
		}
	}
	
	return Plugin_Handled;
}

public Action Commands_SetCredits(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (!IsAdmin(client))
	{
		CPrintToChat(client, "%t", "NoAccessToCommand");
		return Plugin_Handled;
	}
	
	char buffer[96];
	if (args < 2)
	{
		GetCmdArg(0, buffer, sizeof(buffer));
		ReplyToCommand(client, " \x04[Play-IL]\x01 Usage: %s <name|#userid> <credits>", buffer);
		return Plugin_Handled;
	}
	
	char pattern[96], money[32];
	GetCmdArg(1, pattern, sizeof(pattern));
	GetCmdArg(2, money, sizeof(money));
	
	int[] targets = new int[MaxClients];
	bool ml;
	
	int imoney = StringToInt(money);
	
	int count = ProcessTargetString(pattern, client, targets, MaxClients, COMMAND_FILTER_NO_BOTS, buffer, sizeof(buffer), ml);
	
	if (count < 1)
	{
		if (client)
		{
			CPrintToChat(client, "%t", "TargetNotFound", pattern);
		}
		else
		{
			ReplyToCommand(client, "%t", "TargetNotFound", pattern);
		}
	}
	else
	{
		for (int i = 0; i < count; i++)
		{
			if (targets[i] != client && !CanUserTarget(client, targets[i]))continue;
			
			Shop_SetClientCredits(targets[i], imoney);
		}
		if (ml)
		{
			Format(buffer, sizeof(buffer), "%T", buffer, client);
		}
		if (client)
		{
			CPrintToChat(client, "%t", "set_credits_success", AddCommas(imoney), buffer);
		}
		else
		{
			ReplyToCommand(client, "%t", "set_credits_success", AddCommas(imoney), buffer);
		}
	}
	
	return Plugin_Handled;
}

public Action Commands_Credits(int client, int args)
{
	if (!client)
	{
		return Plugin_Handled;
	}
	
	if (!IsAuthorizedIn(client))
	{
		CPrintToChat(client, "%t", "DataLoading");
		return Plugin_Handled;
	}
	
	if (args == 1)
	{
		char szArg[MAX_NAME_LENGTH];
		GetCmdArg(1, szArg, sizeof(szArg));
		int targetIndex = FindTarget(client, szArg, true, false);
		
		if (targetIndex == -1)
		{
			// Automated message
			return Plugin_Handled;
		}
		
		CPrintToChat(client, "%T", "view_other_credits", client, targetIndex, AddCommas(GetCredits(targetIndex)));
	}
	else
	{
		CPrintToChat(client, "%T", "view_own_credits", client, AddCommas(GetCredits(client)));
	}
	
	return Plugin_Handled;
} 