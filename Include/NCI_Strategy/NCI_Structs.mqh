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

// *** DUAL UNIVERSE MEMORY ***
PointStruct ZigZagPoints_HTF[];
MergedZoneState activeSupply_HTF;
MergedZoneState activeDemand_HTF;
MergedZoneState activeFlippedSupply_HTF; 
MergedZoneState activeFlippedDemand_HTF; 
int currentMarketTrend_HTF = 0;

PointStruct ZigZagPoints_LTF[];
MergedZoneState activeSupply_LTF;
MergedZoneState activeDemand_LTF;
MergedZoneState activeFlippedSupply_LTF; 
MergedZoneState activeFlippedDemand_LTF; 
int currentMarketTrend_LTF = 0;

// Shared State
ulong CurrentOpenTicket = 0;   
datetime CurrentZoneID = 0;
int CurrentZoneTradeCount = 0; 
bool ZoneIsBurned = false;

// *** DASHBOARD VISIBILITY FLAGS ***
bool ShowHTF = true;
bool ShowLTF = true;