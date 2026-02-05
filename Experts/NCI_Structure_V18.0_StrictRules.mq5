//+------------------------------------------------------------------+
//|         NCI_Structure_V28.0_GreedyMachine.mq5                    |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "28.00"
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
   Print(">>> V28 INIT: Greedy State Machine (Time-Flow Fixed).");
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
   // --- STEP 1: GATHER ALL RAW ALARMS (LOGIC SPLIT V27) ---
   PointStruct Alarms[];
   int alarmCount = 0;
   int startBar = MathMin(HistoryBars, iBars(_Symbol, _Period)-10);
   
   for (int i = startBar; i >= 5; i--) 
   {
      // [Logic Split Code from V27 - Detecting Valid Starts]
      // 1. SWING HIGH (Pullback)
      if (IsGreen(i)) {
         int c1 = i-1; int c2 = i-2;
         if (IsRed(c1)) {
            bool valid = false;
            // Strong Start (Continuous Color Rule)
            if (IsStrongBody(c1)) {
               if (IsRed(c2)) valid = true; 
            }
            // Weak Start (Breakout Rule)
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
      // 2. SWING LOW (Rally)
      if (IsRed(i)) {
         int c1 = i-1; int c2 = i-2;
         if (IsGreen(c1)) {
            bool valid = false;
            if (IsStrongBody(c1)) {
               if (IsGreen(c2)) valid = true;
            }
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

   // --- STEP 2: GREEDY STATE MACHINE (FIXED TIME FLOW) ---
   ArrayResize(ZigZagPoints, 0);
   
   // Init State
   int state = 0; // 0=Init, 1=SeekingHigh, -1=SeekingLow
   PointStruct pendingPoint; 
   int lastCommittedIndex = startBar + 5; // Start boundary
   
   // Set initial state based on first alarm
   if (Alarms[0].type == 1) { // First is High
       AddPoint(ZigZagPoints, Alarms[0]); // Commit it to start
       lastCommittedIndex = Alarms[0].barIndex;
       state = -1; // Look for Low
       pendingPoint.price = 999999; // Init for Low search
   } else {
       AddPoint(ZigZagPoints, Alarms[0]);
       lastCommittedIndex = Alarms[0].barIndex;
       state = 1; // Look for High
       pendingPoint.price = 0; // Init for High search
   }

   for (int i = 1; i < alarmCount; i++)
   {
      // RANGE CALCULATION (Crucial Fix for Time Travel)
      // We scan from LastCommittedIndex-1 down to Alarm.Index
      // This ensures we NEVER go behind the last point.
      int searchStart = Alarms[i].barIndex;
      int searchEnd   = lastCommittedIndex - 1; 
      int count       = searchEnd - searchStart + 1;
      
      if (count <= 0) continue; // Safety

      // --- STATE: SEEKING HIGH ---
      if (state == 1) 
      {
         // 1. Scan the range for the highest price
         int highestIdx = iHighest(_Symbol, _Period, MODE_HIGH, count, searchStart);
         double highestPrice = iHigh(_Symbol, _Period, highestIdx);
         
         // 2. Greedy Update: Is this better than our pending High?
         if (highestPrice > pendingPoint.price) {
            pendingPoint.price = highestPrice;
            pendingPoint.time  = iTime(_Symbol, _Period, highestIdx);
            pendingPoint.barIndex = highestIdx;
            pendingPoint.type = 1;
         }
         
         // 3. If we hit a LOW Alarm -> COMMIT the pending High
         if (Alarms[i].type == -1) {
            AddPoint(ZigZagPoints, pendingPoint);
            lastCommittedIndex = pendingPoint.barIndex;
            
            // Switch State
            state = -1;
            pendingPoint.price = 999999; // Reset for Low search
            // Re-evaluate this range for Low? 
            // Better to let next iteration handle strict low search from the new committed high
            i--; // Hack: Rewind one step to process this Low Alarm in the new state
         }
      }
      
      // --- STATE: SEEKING LOW ---
      else if (state == -1) 
      {
         int lowestIdx = iLowest(_Symbol, _Period, MODE_LOW, count, searchStart);
         double lowestPrice = iLow(_Symbol, _Period, lowestIdx);
         
         if (lowestPrice < pendingPoint.price) {
            pendingPoint.price = lowestPrice;
            pendingPoint.time  = iTime(_Symbol, _Period, lowestIdx);
            pendingPoint.barIndex = lowestIdx;
            pendingPoint.type = -1;
         }
         
         if (Alarms[i].type == 1) { // Hit a HIGH Alarm
            AddPoint(ZigZagPoints, pendingPoint);
            lastCommittedIndex = pendingPoint.barIndex;
            
            state = 1;
            pendingPoint.price = 0; 
            i--; // Rewind to process this High Alarm in new state
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