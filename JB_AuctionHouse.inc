#if defined _JB_AuctionHouse_included
 #endinput
#endif
#define _JB_AuctionHouse_included

enum
{
	AuctionType_Regular, // Regular auction item
	AuctionType_Bin,     // Buy it now auction
	AuctionType_Max		 // Maximum enum index
}

enum struct AuctionBid
{
	char szBidderAuth[32];
	char szBidderName[MAX_NAME_LENGTH];
	
	int iBidUnixTime;
	int iBidSpentCash;
}

enum struct AuctionItem
{
	char szAuctionItemUnique[64];
	
	int iAuctionItemStar;
	int iAuctionItemLevel;
	
	void Init() {
		this.iAuctionItemStar = -1;
		this.iAuctionItemLevel = -1;
	}
	
	void Reset() {
		this.szAuctionItemUnique[0] = '\0';
	}
}

enum struct Auction
{
	int iAuctionType;
	
	int auction_seller_account_id;
	char szAuctionSellerName[MAX_NAME_LENGTH];
	
	int iAuctionUnixTime;
	int iAuctionValue;
	int iAuctionDuration;
	
	AuctionItem AuctionItemData;
	
	ArrayList arAuctionPlacedBids;
	
	void Init()
	{
		this.iAuctionUnixTime = GetTime();
		
		delete this.arAuctionPlacedBids;
		this.arAuctionPlacedBids = new ArrayList(sizeof(AuctionBid));
	}
	
	void Reset() {
		this.iAuctionType = AuctionType_Regular;
		
		this.auction_seller_account_id = 0;
		this.szAuctionSellerName[0] = '\0';
		
		this.iAuctionUnixTime = 0;
		this.iAuctionValue = 0;
		this.iAuctionDuration = 0;
		
		this.AuctionItemData.Reset();
		
		delete this.arAuctionPlacedBids;
	}
	
	void GetBidByIndex(int index, any[] buffer)
	{
		this.arAuctionPlacedBids.GetArray(index, buffer);
	}
}

/**
 * Shows the auction house main menu to a certain client.
 * 
 * @param client              Client index to display the menu to.
 *
 * @error					  Invalid client index.
 */
native void JB_ShowAuctionHouseMainMenu(int client);

#if !defined REQUIRE_PLUGIN
public void __pl_JB_AuctionHouse_SetNTVOptional()
{
	MarkNativeAsOptional("JB_ShowAuctionHouseMainMenu");
}
#endif

public SharedPlugin __pl_JB_AuctionHouse = 
{
	name = "JB_AuctionHouse", 
	file = "JB_AuctionHouse.smx", 
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
}; 