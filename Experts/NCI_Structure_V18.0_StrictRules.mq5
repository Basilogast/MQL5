//+------------------------------------------------------------------+
//|         NCI_Structure_V20.0_ZigZagEngine.mq5                     |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "20.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 1000;  // How far back to draw lines
input color LineColor       = clrDodgerBlue; 
input int LineWidth         = 2;

//--- 2. STRICT RULES (From Slide)
input group "Strict Rules"
input double MinBodyPercent = 0.50;  // Body > 50% (Slightly relaxed for better visuals)
input int ReversalCandles   = 2;     // 2 Candles to confirm

//--- 3. TRADING LOGIC
input group "Trading Logic"
input double MagnetPips     = 3.0;
input double RiskPercent    = 1.0;
input double TargetRR       = 3.0;

//--- GLOBALS
CTrade trade;
struct PointStruct {
   double price;
   datetime time;
   int type; // 1=High, -1=Low
   int barIndex;
};
PointStruct ZigZagPoints[]; // The final clean list of points

int OnInit()
{
   trade.SetExpertMagicNumber(111222); 
   ObjectsDeleteAll(0, "NCI_ZZ_"); // Clear old lines
   
   // Initial Draw
   UpdateZigZagMap();
   
   Print(">>> V20 INIT: ZigZag State Machine Loaded.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   // Update the map on every new bar
   if(IsNewBar()) UpdateZigZagMap();
   
   // (Trading Logic using ZigZagPoints would go here)
   // For now, we focus on fixing the Visuals as requested.
}

// ==========================================================
//    THE ZIGZAG STATE MACHINE
// ==========================================================
void UpdateZigZagMap()
{
   // 1. IDENTIFY ALL CANDIDATES (Raw Points)
   PointStruct Candidates[];
   int candCount = 0;
   
   int startBar = MathMin(HistoryBars, iBars(_Symbol, _Period)-ReversalCandles-1);
   
   // Iterate from PAST to PRESENT
   for (int i = startBar; i >= ReversalCandles; i--) 
   {
      // CHECK FOR SWING HIGH CANDIDATE
      // Pattern: Green Candle (i) -> 2 Strong Red Candles (i-1, i-2)
      if (IsGreen(i)) 
      {
         bool isHigh = true;
         for(int k=1; k<=ReversalCandles; k++) {
            if(!IsRed(i-k) || !IsStrongBody(i-k)) { isHigh = false; break; }
         }
         
         if(isHigh) {
            ArrayResize(Candidates, candCount + 1);
            Candidates[candCount].price = iHigh(_Symbol, _Period, i);
            Candidates[candCount].time  = iTime(_Symbol, _Period, i);
            Candidates[candCount].type  = 1; // High Candidate
            Candidates[candCount].barIndex = i;
            candCount++;
         }
      }

      // CHECK FOR SWING LOW CANDIDATE
      // Pattern: Red Candle (i) -> 2 Strong Green Candles (i-1, i-2)
      if (IsRed(i))
      {
         bool isLow = true;
         for(int k=1; k<=ReversalCandles; k++) {
            if(!IsGreen(i-k) || !IsStrongBody(i-k)) { isLow = false; break; }
         }
         
         if(isLow) {
            ArrayResize(Candidates, candCount + 1);
            Candidates[candCount].price = iLow(_Symbol, _Period, i);
            Candidates[candCount].time  = iTime(_Symbol, _Period, i);
            Candidates[candCount].type  = -1; // Low Candidate
            Candidates[candCount].barIndex = i;
            candCount++;
         }
      }
   }
   
   if (candCount < 2) return;

   // 2. FILTER CANDIDATES (The ZigZag Logic)
   ArrayResize(ZigZagPoints, 0);
   int zzCount = 0;
   
   // State Tracking
   int currentMode = 0; // 0=Unknown, 1=Looking for High, -1=Looking for Low
   int bestCandIndex = -1;
   
   // Initialize with first point
   AddPoint(ZigZagPoints, Candidates[0]);
   currentMode = (Candidates[0].type == 1) ? -1 : 1; // If started with High, look for Low
   bestCandIndex = 0; // Current "Anchor"

   for (int i = 1; i < candCount; i++)
   {
      // MODE: LOOKING FOR HIGH (We just made a Low)
      if (currentMode == 1)
      {
         if (Candidates[i].type == 1) // Found a High Candidate
         {
             // Is this High higher than our current best High?
             // Or is it just the first one we found?
             // We don't add it yet. We wait to see if a higher one comes along before a Low.
             
             // Simple Logic: Store pending High. 
             // Ideally: We need to find the HIGHEST High between two Lows.
         }
      }
   }
   
   // --- SIMPLIFIED ZIGZAG ALGORITHM (Robust) ---
   // This replaces the complex loop above with a standard "Extreme" finder
   ArrayResize(ZigZagPoints, 0);
   
   // Assume first candidate is a starting point
   AddPoint(ZigZagPoints, Candidates[0]);
   
   int lastType = Candidates[0].type;
   double extremePrice = Candidates[0].price;
   int extremeIndex = 0; // Index in Candidates array
   
   for (int i = 1; i < candCount; i++)
   {
      // If we last found a High, we are looking for a Low
      if (lastType == 1) 
      {
         // If we find another High that is HIGHER, we update the previous point!
         if (Candidates[i].type == 1 && Candidates[i].price > extremePrice) {
            // Update the "Last Point" in our final array
            UpdateLastPoint(ZigZagPoints, Candidates[i]);
            extremePrice = Candidates[i].price;
         }
         // If we find a Low (Swing confirmed)
         else if (Candidates[i].type == -1) {
            AddPoint(ZigZagPoints, Candidates[i]); // Add the Low
            lastType = -1; // Now looking for High
            extremePrice = Candidates[i].price;
         }
      }
      // If we last found a Low, we are looking for a High
      else if (lastType == -1)
      {
         // If we find another Low that is LOWER, update previous
         if (Candidates[i].type == -1 && Candidates[i].price < extremePrice) {
            UpdateLastPoint(ZigZagPoints, Candidates[i]);
            extremePrice = Candidates[i].price;
         }
         // If we find a High
         else if (Candidates[i].type == 1) {
            AddPoint(ZigZagPoints, Candidates[i]); // Add the High
            lastType = 1; // Now looking for Low
            extremePrice = Candidates[i].price;
         }
      }
   }
   
   // 3. DRAW THE LINES
   DrawZigZag();
}

// ==========================================================
//    DRAWING & HELPERS
// ==========================================================
void DrawZigZag()
{
   ObjectsDeleteAll(0, "NCI_ZZ_");
   int count = ArraySize(ZigZagPoints);
   if (count < 2) return;
   
   for (int i = 1; i < count; i++)
   {
      string name = "NCI_ZZ_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_TREND, 0, ZigZagPoints[i-1].time, ZigZagPoints[i-1].price, ZigZagPoints[i].time, ZigZagPoints[i].price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, LineColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ChartRedraw();
}

void AddPoint(PointStruct &arr[], PointStruct &p) {
   int s = ArraySize(arr);
   ArrayResize(arr, s+1);
   arr[s] = p;
}

void UpdateLastPoint(PointStruct &arr[], PointStruct &p) {
   int s = ArraySize(arr);
   if (s > 0) arr[s-1] = p; // Overwrite last point with better extreme
}

bool IsStrongBody(int index) {
   double h = iHigh(_Symbol, _Period, index);
   double l = iLow(_Symbol, _Period, index);
   if (h-l == 0) return false;
   double b = MathAbs(iOpen(_Symbol, _Period, index) - iClose(_Symbol, _Period, index));
   return (b > (h-l) * MinBodyPercent);
}

bool IsGreen(int index) { return iClose(_Symbol, _Period, index) > iOpen(_Symbol, _Period, index); }
bool IsRed(int index) { return iClose(_Symbol, _Period, index) < iOpen(_Symbol, _Period, index); }

bool IsNewBar() {
   static datetime last;
   datetime curr = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last != curr) { last = curr; return true; }
   return false;
}