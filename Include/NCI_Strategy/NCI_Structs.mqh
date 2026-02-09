//+------------------------------------------------------------------+
//| NCI_Structs.mqh - Data Structures & Globals                      |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

// --- STRUCTURES ---
struct PointStruct {
   double price;
   datetime time;
   int type; 
   int barIndex;
   double zoneLimitTop;
   double zoneLimitBottom;
   int assignedTrend; 
};

struct MergedZoneState {
   bool isActive;
   double top;
   double bottom;
   datetime startTime; 
   datetime endTime; 
   int lastBarIndex;
};

// --- GLOBAL VARIABLES ---
CTrade trade;
PointStruct ZigZagPoints[];

MergedZoneState activeSupply;
MergedZoneState activeDemand;
MergedZoneState activeFlippedSupply; 
MergedZoneState activeFlippedDemand; 

int currentMarketTrend = 0;
ulong CurrentOpenTicket = 0;   
datetime CurrentZoneID = 0;
int CurrentZoneTradeCount = 0; 
bool ZoneIsBurned = false;