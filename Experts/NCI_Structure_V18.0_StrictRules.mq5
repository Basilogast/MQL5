//+------------------------------------------------------------------+
//|         NCI_Structure_V27.0_ColorCheck.mq5                       |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "27.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 1000;  
input color LineColor       = clrWhite; 
input int LineWidth         = 2;

//--- 2. STRUCTURE RULES
input group "Structure Rules"
input double MinBodyPercent = 0.50;  
input int MaxScanDistance   = 3;     

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
   UpdateZigZagMap();
   Print(">>> V27 INIT: Color Consistency Check Loaded.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(IsNewBar()) UpdateZigZagMap();
}

// ==========================================================
//    THE LOGIC ENGINE
// ==========================================================
void UpdateZigZagMap()
{
   PointStruct Alarms[];
   int alarmCount = 0;
   
   int startBar = MathMin(HistoryBars, iBars(_Symbol, _Period)-10);
   
   for (int i = startBar; i >= 5; i--) 
   {
      // --- CHECK FOR SWING HIGH (Pullback) ---
      if (IsGreen(i)) 
      {
         int c1_idx = i - 1; 
         int c2_idx = i - 2; // The 2nd Candle

         if (IsRed(c1_idx)) 
         {
            bool isValid = false;
            
            // === LOGIC BRANCH 1: STRONG START ===
            if (IsStrongBody(c1_idx)) 
            {
               // FIX: Even if C1 is Strong, C2 MUST BE RED (Continuous Reversal).
               // It does not matter if C2 is weak/strong/inside, but it MUST be RED.
               if (IsRed(c2_idx)) {
                  isValid = true;
               }
            }
            // === LOGIC BRANCH 2: WEAK START ===
            else 
            {
               double rangeLow = iLow(_Symbol, _Period, c1_idx);
               // Scan for Breakout
               for (int k = 1; k <= MaxScanDistance; k++) 
               {
                  int next_idx = c1_idx - k;
                  if (next_idx < 0) break;
                  if (iHigh(_Symbol, _Period, next_idx) > iHigh(_Symbol, _Period, i)) break;
                  
                  // Must be Strong RED and Break Low
                  if (IsRed(next_idx) && IsStrongBody(next_idx)) 
                  {
                     if (iClose(_Symbol, _Period, next_idx) < rangeLow) {
                        isValid = true;
                        break; 
                     }
                  }
               }
            }
            
            if (isValid) {
               ArrayResize(Alarms, alarmCount + 1);
               Alarms[alarmCount].price = iHigh(_Symbol, _Period, i); 
               Alarms[alarmCount].time  = iTime(_Symbol, _Period, i);
               Alarms[alarmCount].type  = 1; 
               Alarms[alarmCount].barIndex = i; 
               alarmCount++;
            }
         }
      }

      // --- CHECK FOR SWING LOW (Rally) ---
      if (IsRed(i))
      {
         int c1_idx = i - 1; 
         int c2_idx = i - 2;

         if (IsGreen(c1_idx)) 
         {
            bool isValid = false;
            
            // === LOGIC BRANCH 1: STRONG START ===
            if (IsStrongBody(c1_idx)) 
            {
               // FIX: C2 MUST BE GREEN (Continuous Reversal)
               if (IsGreen(c2_idx)) {
                  isValid = true;
               }
            }
            // === LOGIC BRANCH 2: WEAK START ===
            else 
            {
               double rangeHigh = iHigh(_Symbol, _Period, c1_idx);
               
               for (int k = 1; k <= MaxScanDistance; k++) 
               {
                  int next_idx = c1_idx - k;
                  if (next_idx < 0) break;
                  if (iLow(_Symbol, _Period, next_idx) < iLow(_Symbol, _Period, i)) break;
                  
                  // Must be Strong GREEN and Break High
                  if (IsGreen(next_idx) && IsStrongBody(next_idx)) 
                  {
                     if (iClose(_Symbol, _Period, next_idx) > rangeHigh) {
                        isValid = true;
                        break; 
                     }
                  }
               }
            }
            
            if (isValid) {
               ArrayResize(Alarms, alarmCount + 1);
               Alarms[alarmCount].price = iLow(_Symbol, _Period, i);
               Alarms[alarmCount].time  = iTime(_Symbol, _Period, i);
               Alarms[alarmCount].type  = -1; 
               Alarms[alarmCount].barIndex = i; 
               alarmCount++;
            }
         }
      }
   }
   
   if (alarmCount < 2) return;

   // 3. CONNECT AND REFINE (Vertex Engine - Unchanged)
   ArrayResize(ZigZagPoints, 0);
   AddPoint(ZigZagPoints, Alarms[0]);
   
   int lastType = Alarms[0].type;     
   int lastPointIndex = Alarms[0].barIndex; 
   
   for (int i = 1; i < alarmCount; i++)
   {
      if (lastType == -1) {
         if (Alarms[i].type == 1) {
            int searchStart = Alarms[i].barIndex; 
            int pIndex = iHighest(_Symbol, _Period, MODE_HIGH, (lastPointIndex - searchStart + 5), searchStart);
            if (pIndex != -1) {
               PointStruct p; p.price = iHigh(_Symbol, _Period, pIndex); p.time = iTime(_Symbol, _Period, pIndex); p.type = 1; p.barIndex = pIndex;
               AddPoint(ZigZagPoints, p);
               lastType = 1; lastPointIndex = pIndex;
            }
         }
      }
      else if (lastType == 1) {
         if (Alarms[i].type == -1) {
            int searchStart = Alarms[i].barIndex;
            int pIndex = iLowest(_Symbol, _Period, MODE_LOW, (lastPointIndex - searchStart + 5), searchStart);
            if (pIndex != -1) {
               PointStruct p; p.price = iLow(_Symbol, _Period, pIndex); p.time = iTime(_Symbol, _Period, pIndex); p.type = -1; p.barIndex = pIndex;
               AddPoint(ZigZagPoints, p);
               lastType = -1; lastPointIndex = pIndex;
            }
         }
      }
   }
   
   DrawZigZag();
}

void DrawZigZag()
{
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
   int s = ArraySize(arr);
   ArrayResize(arr, s+1);
   arr[s] = p;
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