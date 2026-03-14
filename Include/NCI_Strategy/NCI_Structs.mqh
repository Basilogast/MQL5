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
   
   // --- [NEW] FVG MEMORY SLOTS ---
   bool hasFVG;
   double fvgTop;
   double fvgBottom;
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
MergedZoneState activeFVGSupply_HTF;     // [NEW] HTF Bearish FVG Zone
MergedZoneState activeFVGDemand_HTF;     // [NEW] HTF Bullish FVG Zone
int currentMarketTrend_HTF = 0;

PointStruct ZigZagPoints_LTF[];
MergedZoneState activeSupply_LTF;
MergedZoneState activeDemand_LTF;
MergedZoneState activeFlippedSupply_LTF; 
MergedZoneState activeFlippedDemand_LTF; 
MergedZoneState activeFVGSupply_LTF;     // [NEW] LTF Bearish FVG Zone
MergedZoneState activeFVGDemand_LTF;     // [NEW] LTF Bullish FVG Zone
int currentMarketTrend_LTF = 0;

// ==========================================
// [FIX] SPLIT BRAIN MEMORY 
// ==========================================

// --- BUY MEMORY ---
ulong CurrentOpenBuyTicket = 0;
datetime CurrentBuyZoneID = 0;
bool BuyZoneIsBurned = false; 
int CurrentBuyZoneTradeCount = 0;

// --- SELL MEMORY ---
ulong CurrentOpenSellTicket = 0;
datetime CurrentSellZoneID = 0;
bool SellZoneIsBurned = false; 
int CurrentSellZoneTradeCount = 0;
// *** DASHBOARD VISIBILITY FLAGS ***
bool ShowHTF = true;
bool ShowLTF = true;