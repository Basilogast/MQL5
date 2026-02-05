//+------------------------------------------------------------------+
//|         NCI_Structure_V23.0_VertexFix.mq5                        |
//|                                  Copyright 2024, NCI Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "23.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 1000;  
input color LineColor       = clrWhite; 
input int LineWidth         = 2;

//--- 2. STRICT RULES (The "Alarm")
input group "Strict Rules"
input double MinBodyPercent = 0.50;  
input int ReversalCandles   = 2;     

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
   Print(">>> V23 INIT: Vertex Precision Engine Loaded.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(IsNewBar()) UpdateZigZagMap();
}

// ==========================================================
//    THE VERTEX ENGINE
// ==========================================================
void UpdateZigZagMap()
{
   // 1. FIND "ALARMS" (Strict Candidates)
   // These are just the bars where the 2-candle pattern COMPLETED.
   PointStruct Alarms[];
   int alarmCount = 0;
   
   int startBar = MathMin(HistoryBars, iBars(_Symbol, _Period)-ReversalCandles-1);
   
   for (int i = startBar; i >= ReversalCandles; i--) 
   {
      // CHECK FOR HIGH SIGNAL (Green -> 2 Red)
      if (IsGreen(i)) 
      {
         bool isHigh = true;
         for(int k=1; k<=ReversalCandles; k++) {
            if(!IsRed(i-k) || !IsStrongBody(i-k)) { isHigh = false; break; }
         }
         if(isHigh) {
            ArrayResize(Alarms, alarmCount + 1);
            Alarms[alarmCount].price = iHigh(_Symbol, _Period, i); // Temp price
            Alarms[alarmCount].time  = iTime(_Symbol, _Period, i);
            Alarms[alarmCount].type  = 1; 
            Alarms[alarmCount].barIndex = i; // This is the "Peak" candle before the drop
            alarmCount++;
         }
      }

      // CHECK FOR LOW SIGNAL (Red -> 2 Green)
      if (IsRed(i))
      {
         bool isLow = true;
         for(int k=1; k<=ReversalCandles; k++) {
            if(!IsGreen(i-k) || !IsStrongBody(i-k)) { isLow = false; break; }
         }
         if(isLow) {
            ArrayResize(Alarms, alarmCount + 1);
            Alarms[alarmCount].price = iLow(_Symbol, _Period, i);
            Alarms[alarmCount].time  = iTime(_Symbol, _Period, i);
            Alarms[alarmCount].type  = -1; 
            Alarms[alarmCount].barIndex = i; // This is the "Valley" candle before the rally
            alarmCount++;
         }
      }
   }
   
   if (alarmCount < 2) return;

   // 2. CONNECT AND REFINE (Find the True Vertex)
   ArrayResize(ZigZagPoints, 0);
   
   // Logic:
   // We have a list of Alarms.
   // We need to find the EXTREME PRICE between the previous point and the current Alarm.
   
   // Start with the first alarm as a baseline
   AddPoint(ZigZagPoints, Alarms[0]);
   
   int lastType = Alarms[0].type;     
   int lastPointIndex = Alarms[0].barIndex; // Where the last line ended
   
   for (int i = 1; i < alarmCount; i++)
   {
      // --- LOOKING FOR HIGH ---
      if (lastType == -1) // We last made a Low, now we want a High
      {
         if (Alarms[i].type == 1) // Found a High Alarm
         {
            // KEY FIX: Don't just use the Alarm's price.
            // Find the HIGHEST HIGH between the previous Low(lastPointIndex) and this Alarm(Alarms[i].barIndex)
            
            // We search from the Alarm index BACK to the Last Point index
            // Note: Indices go from High (Past) to Low (Present). 
            // So we search from Alarms[i].barIndex UP TO lastPointIndex
            
            double trueHighPrice = -1.0;
            int trueHighIndex = -1;
            
            // Safety check for range
            int searchEnd = lastPointIndex;
            int searchStart = Alarms[i].barIndex; // Note: In MT4/5, Start < End (Start is newer)
            
            // Search backwards from the alarm to the previous low
            // Actually, the alarm 'barIndex' is the candle BEFORE the 2 reversal candles.
            // But the true high could be slightly before that if it was a cluster.
            // Let's search the range.
            
            int pIndex = iHighest(_Symbol, _Period, MODE_HIGH, (searchEnd - searchStart + 1), searchStart);
            
            if (pIndex != -1) {
               PointStruct refinedPoint;
               refinedPoint.price = iHigh(_Symbol, _Period, pIndex);
               refinedPoint.time  = iTime(_Symbol, _Period, pIndex);
               refinedPoint.type  = 1;
               refinedPoint.barIndex = pIndex;
               
               AddPoint(ZigZagPoints, refinedPoint);
               
               lastType = 1;
               lastPointIndex = pIndex; // Start next search from this true peak
            }
         }
      }
      
      // --- LOOKING FOR LOW ---
      else if (lastType == 1) // We last made a High, now we want a Low
      {
         if (Alarms[i].type == -1) // Found a Low Alarm
         {
            // KEY FIX: Find the LOWEST LOW between previous High and this Alarm
            int searchEnd = lastPointIndex;
            int searchStart = Alarms[i].barIndex;
            
            int pIndex = iLowest(_Symbol, _Period, MODE_LOW, (searchEnd - searchStart + 1), searchStart);
            
            if (pIndex != -1) {
               PointStruct refinedPoint;
               refinedPoint.price = iLow(_Symbol, _Period, pIndex);
               refinedPoint.time  = iTime(_Symbol, _Period, pIndex);
               refinedPoint.type  = -1;
               refinedPoint.barIndex = pIndex;
               
               AddPoint(ZigZagPoints, refinedPoint);
               
               lastType = -1;
               lastPointIndex = pIndex; // Start next search from this true valley
            }
         }
      }
   }
   
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