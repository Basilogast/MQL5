//+------------------------------------------------------------------+
//|         NCI_Structure_V31.0_SpecialCases.mq5                     |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "31.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 1000;  
input color LineColor       = clrWhite; 
input int LineWidth         = 2;
input bool DrawZones        = true;
input color SupplyColor     = clrMaroon; 
input color DemandColor     = clrDarkGreen; 

//--- 2. STRUCTURE RULES
input group "Structure Rules"
input double MinBodyPercent = 0.50;  
input int MaxScanDistance   = 3;     

//--- 3. SPECIAL CASE RULES
input group "Special Cases"
input double BigCandleFactor = 1.3; // If candle is 1.3x average, it's "Big"

//--- GLOBALS
CTrade trade;
struct PointStruct {
   double price;
   datetime time;
   int type; // 1=High, -1=Low
   int barIndex;
};
PointStruct ZigZagPoints[]; 

int OnInit()
{
   trade.SetExpertMagicNumber(111222); 
   ObjectsDeleteAll(0, "NCI_ZZ_"); 
   ObjectsDeleteAll(0, "NCI_Zone_");
   UpdateZigZagMap();
   Print(">>> V31 INIT: Special Cases (Big Candle Logic) Loaded.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(IsNewBar()) UpdateZigZagMap();
}

// ==========================================================
//    THE ENGINE
// ==========================================================
void UpdateZigZagMap()
{
   // [Step 1: Gather Alarms - Unchanged]
   PointStruct Alarms[];
   int alarmCount = 0;
   int startBar = MathMin(HistoryBars, iBars(_Symbol, _Period)-10);
   
   for (int i = startBar; i >= 5; i--) 
   {
      if (IsGreen(i)) {
         int c1 = i-1; int c2 = i-2;
         if (IsRed(c1)) {
            bool valid = false;
            if (IsStrongBody(c1)) { if (IsRed(c2)) valid = true; }
            else {
               double rangeLow = iLow(_Symbol, _Period, c1);
               for (int k=1; k<=MaxScanDistance; k++) {
                  int next = c1-k; if(next<0) break;
                  if(iHigh(_Symbol, _Period, next) > iHigh(_Symbol, _Period, i)) break;
                  if(IsRed(next) && IsStrongBody(next) && iClose(_Symbol, _Period, next) < rangeLow) {
                     valid = true; break;
                  }
               }
            }
            if (valid) {
               ArrayResize(Alarms, alarmCount+1);
               Alarms[alarmCount].price = iHigh(_Symbol, _Period, i);
               Alarms[alarmCount].time = iTime(_Symbol, _Period, i);
               Alarms[alarmCount].type = 1; Alarms[alarmCount].barIndex = i;
               alarmCount++;
            }
         }
      }
      if (IsRed(i)) {
         int c1 = i-1; int c2 = i-2;
         if (IsGreen(c1)) {
            bool valid = false;
            if (IsStrongBody(c1)) { if (IsGreen(c2)) valid = true; }
            else {
               double rangeHigh = iHigh(_Symbol, _Period, c1);
               for (int k=1; k<=MaxScanDistance; k++) {
                  int next = c1-k; if(next<0) break;
                  if(iLow(_Symbol, _Period, next) < iLow(_Symbol, _Period, i)) break;
                  if(IsGreen(next) && IsStrongBody(next) && iClose(_Symbol, _Period, next) > rangeHigh) {
                     valid = true; break;
                  }
               }
            }
            if (valid) {
               ArrayResize(Alarms, alarmCount+1);
               Alarms[alarmCount].price = iLow(_Symbol, _Period, i);
               Alarms[alarmCount].time = iTime(_Symbol, _Period, i);
               Alarms[alarmCount].type = -1; Alarms[alarmCount].barIndex = i;
               alarmCount++;
            }
         }
      }
   }
   
   if (alarmCount < 2) return;

   // [Step 2: Greedy State Machine - Unchanged]
   ArrayResize(ZigZagPoints, 0);
   int state = 0; 
   PointStruct pendingPoint; 
   int lastCommittedIndex = startBar + 5; 
   
   if (Alarms[0].type == 1) { 
       AddPoint(ZigZagPoints, Alarms[0]); lastCommittedIndex = Alarms[0].barIndex; state = -1; pendingPoint.price = 999999; 
   } else {
       AddPoint(ZigZagPoints, Alarms[0]); lastCommittedIndex = Alarms[0].barIndex; state = 1; pendingPoint.price = 0; 
   }

   for (int i = 1; i < alarmCount; i++)
   {
      int searchStart = Alarms[i].barIndex;
      int searchEnd   = lastCommittedIndex - 1; 
      int count       = searchEnd - searchStart + 1;
      if (count <= 0) continue;

      if (state == 1) {
         int highestIdx = iHighest(_Symbol, _Period, MODE_HIGH, count, searchStart);
         double highestPrice = iHigh(_Symbol, _Period, highestIdx);
         if (highestPrice > pendingPoint.price) {
            pendingPoint.price = highestPrice; pendingPoint.time = iTime(_Symbol, _Period, highestIdx);
            pendingPoint.barIndex = highestIdx; pendingPoint.type = 1;
         }
         if (Alarms[i].type == -1) {
            AddPoint(ZigZagPoints, pendingPoint); lastCommittedIndex = pendingPoint.barIndex;
            state = -1; pendingPoint.price = 999999; i--; 
         }
      }
      else if (state == -1) {
         int lowestIdx = iLowest(_Symbol, _Period, MODE_LOW, count, searchStart);
         double lowestPrice = iLow(_Symbol, _Period, lowestIdx);
         if (lowestPrice < pendingPoint.price) {
            pendingPoint.price = lowestPrice; pendingPoint.time = iTime(_Symbol, _Period, lowestIdx);
            pendingPoint.barIndex = lowestIdx; pendingPoint.type = -1;
         }
         if (Alarms[i].type == 1) { 
            AddPoint(ZigZagPoints, pendingPoint); lastCommittedIndex = pendingPoint.barIndex;
            state = 1; pendingPoint.price = 0; i--; 
         }
      }
   }
   
   DrawZigZag();
   if(DrawZones) DrawSupplyDemandZones(); 
}

// ==========================================================
//    NEW: ZONE DRAWING WITH SPECIAL CASES
// ==========================================================
void DrawSupplyDemandZones()
{
   ObjectsDeleteAll(0, "NCI_Zone_");
   int count = ArraySize(ZigZagPoints);
   
   for (int i = 0; i < count; i++)
   {
      PointStruct p = ZigZagPoints[i];
      double zoneTop = 0;
      double zoneBottom = 0;
      color zoneColor = clrNONE;
      string name = "NCI_Zone_" + IntegerToString(i);
      
      datetime startTime = iTime(_Symbol, _Period, p.barIndex);
      datetime endTime   = 0;
      for (int j = i + 1; j < count; j++) {
         if (ZigZagPoints[j].type == p.type) { endTime = ZigZagPoints[j].time; break; }
      }
      if (endTime == 0) endTime = TimeCurrent() + (PeriodSeconds() * 10);
      
      // --- LOGIC CASCADE FOR ZONES ---
      if (p.type == 1) // SUPPLY
      {
         zoneTop = p.price;
         zoneColor = SupplyColor;
         
         // 1. Find Candidates
         int greenIdx = -1; // Last Up Candle
         int redIdx   = -1; // First Down Candle
         
         // Search back/forward slightly around vertex
         for (int k=0; k<=5; k++) { 
             if (IsGreen(p.barIndex + k)) { greenIdx = p.barIndex + k; break; }
         }
         if(greenIdx != -1) redIdx = greenIdx - 1; // Candle after green is usually the red one
         
         // 2. Logic Cascade
         if (greenIdx != -1) 
         {
            // GENERAL CASE: Open of Green Candle
            zoneBottom = iOpen(_Symbol, _Period, greenIdx);
            
            // SPECIAL CASE 1: Green Candle too big?
            if (IsBigCandle(greenIdx)) 
            {
               // Try using the Red Candle Open
               if (redIdx != -1) {
                  zoneBottom = iOpen(_Symbol, _Period, redIdx);
                  
                  // SPECIAL CASE 2: Red Candle ALSO too big?
                  if (IsBigCandle(redIdx)) {
                     // Use Middle of Red Candle
                     zoneBottom = (iOpen(_Symbol, _Period, redIdx) + iClose(_Symbol, _Period, redIdx)) / 2.0;
                  }
               }
               else {
                   // No red candle found (weird), fallback to Middle of Green
                   zoneBottom = (iOpen(_Symbol, _Period, greenIdx) + iClose(_Symbol, _Period, greenIdx)) / 2.0;
               }
            }
         }
      }
      else if (p.type == -1) // DEMAND
      {
         zoneBottom = p.price;
         zoneColor = DemandColor;
         
         // 1. Find Candidates
         int redIdx   = -1; // Last Down Candle
         int greenIdx = -1; // First Up Candle
         
         for (int k=0; k<=5; k++) {
             if (IsRed(p.barIndex + k)) { redIdx = p.barIndex + k; break; }
         }
         if(redIdx != -1) greenIdx = redIdx - 1; 
         
         // 2. Logic Cascade
         if (redIdx != -1) 
         {
            // GENERAL CASE: Open of Red Candle
            zoneTop = iOpen(_Symbol, _Period, redIdx);
            
            // SPECIAL CASE 1: Red Candle too big?
            if (IsBigCandle(redIdx)) 
            {
               // Try using the Green Candle Open
               if (greenIdx != -1) {
                  zoneTop = iOpen(_Symbol, _Period, greenIdx);
                  
                  // SPECIAL CASE 2: Green Candle ALSO too big?
                  if (IsBigCandle(greenIdx)) {
                     // Use Middle of Green Candle
                     zoneTop = (iOpen(_Symbol, _Period, greenIdx) + iClose(_Symbol, _Period, greenIdx)) / 2.0;
                  }
               }
               else {
                   zoneTop = (iOpen(_Symbol, _Period, redIdx) + iClose(_Symbol, _Period, redIdx)) / 2.0;
               }
            }
         }
      }
      
      // --- DRAW ---
      if (zoneColor != clrNONE && zoneTop > zoneBottom) 
      {
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, startTime, zoneTop, endTime, zoneBottom);
         ObjectSetInteger(0, name, OBJPROP_COLOR, zoneColor);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true); 
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      }
   }
   ChartRedraw();
}

// --- HELPER: DETECT BIG CANDLE ---
bool IsBigCandle(int index)
{
   double body = MathAbs(iOpen(_Symbol, _Period, index) - iClose(_Symbol, _Period, index));
   
   // Calculate average body of previous 10 candles
   double sum = 0;
   int count = 0;
   for(int k=1; k<=10; k++) {
      if(index+k >= iBars(_Symbol, _Period)) break;
      sum += MathAbs(iOpen(_Symbol, _Period, index+k) - iClose(_Symbol, _Period, index+k));
      count++;
   }
   if (count == 0) return false;
   double avg = sum / count;
   
   return (body > avg * BigCandleFactor);
}

// --- OTHER HELPERS (Same as before) ---
void DrawZigZag() {
   ObjectsDeleteAll(0, "NCI_ZZ_");
   int count = ArraySize(ZigZagPoints);
   if (count < 2) return;
   for (int i = 1; i < count; i++) {
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
   int s = ArraySize(arr); ArrayResize(arr, s+1); arr[s] = p;
}
bool IsStrongBody(int index) {
   double h = iHigh(_Symbol, _Period, index); double l = iLow(_Symbol, _Period, index);
   if (h-l == 0) return false;
   double b = MathAbs(iOpen(_Symbol, _Period, index) - iClose(_Symbol, _Period, index));
   return (b > (h-l) * MinBodyPercent);
}
bool IsGreen(int index) { return iClose(_Symbol, _Period, index) > iOpen(_Symbol, _Period, index); }
bool IsRed(int index) { return iClose(_Symbol, _Period, index) < iOpen(_Symbol, _Period, index); }
bool IsNewBar() {
   static datetime last; datetime curr = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last != curr) { last = curr; return true; } return false;
}