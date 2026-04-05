//+------------------------------------------------------------------+
//| NCI_Helpers.mqh - Utility Functions                              |
//+------------------------------------------------------------------+
#property strict
#include "NCI_Structs.mqh" 
#include "NCI_Constants.mqh"

// --- DATA WRAPPERS (Timeframe Aware) ---
double GetHigh(ENUM_TIMEFRAMES tf, int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyHigh(_Symbol, tf, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
double GetLow(ENUM_TIMEFRAMES tf, int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyLow(_Symbol, tf, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
double GetOpen(ENUM_TIMEFRAMES tf, int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyOpen(_Symbol, tf, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
double GetClose(ENUM_TIMEFRAMES tf, int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyClose(_Symbol, tf, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
datetime GetTime(ENUM_TIMEFRAMES tf, int index) {
   datetime buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyTime(_Symbol, tf, index, 1, buffer) > 0) return buffer[0];
   return 0;
}

// ==================================================================
// [NEW] HELPER: CALCULATE ADR (Inserted here)
// Used by NCI_Trade.mqh for the Logic Gate
// ==================================================================
// ==================================================================
// [RESTORED] HELPER: CALCULATE ADR (Manual High-Low Math)
// ==================================================================
double CalculateADR(int period) {
   double dailyHighs[];
   double dailyLows[];
   
   if(CopyHigh(_Symbol, PERIOD_D1, 1, period, dailyHighs) < period || 
      CopyLow(_Symbol, PERIOD_D1, 1, period, dailyLows) < period) {
       return 0.0;
   }
   
   double sumRange = 0;
   for(int i=0; i<period; i++) {
      sumRange += (dailyHighs[i] - dailyLows[i]);
   }
   
   double avgRangePoints = sumRange / period;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point == 0) return 0.0;
   
   return avgRangePoints / point / 10.0; // Convert Points to Pips
}
// ==================================================================

// --- CANDLE CHECKS ---
bool IsGreen(ENUM_TIMEFRAMES tf, int index) { return GetClose(tf, index)>GetOpen(tf, index); }
bool IsRed(ENUM_TIMEFRAMES tf, int index) { return GetClose(tf, index)<GetOpen(tf, index); }

bool IsMarubozu(ENUM_TIMEFRAMES tf, int index) {
   double high = GetHigh(tf, index);
   double low = GetLow(tf, index);
   double range = high - low;
   if (range == 0) return false;
   double body = MathAbs(GetOpen(tf, index) - GetClose(tf, index));
   return (body / range) >= 0.60; 
}

bool IsStrongBody(ENUM_TIMEFRAMES tf, int index) { 
   double h=GetHigh(tf, index); double l=GetLow(tf, index); 
   if(h-l==0)return false; 
   double b=MathAbs(GetOpen(tf, index)-GetClose(tf, index)); 
   return(b>(h-l)*MinBodyPercent);
}

bool IsBigCandle(ENUM_TIMEFRAMES tf, int index) { 
   double b=MathAbs(GetOpen(tf, index)-GetClose(tf, index)); 
   double s=0; int c=0; 
   int bars = Bars(_Symbol, tf);
   for(int k=1;k<=10;k++){
      if(index+k>=bars)break;
      s+=MathAbs(GetOpen(tf, index+k)-GetClose(tf, index+k));
      c++;
   } 
   if(c==0)return false; return(b>(s/c)*BigCandleFactor);
}

// [REMOVED] CheckADRFilter() 
// Reason: Logic moved to NCI_Trade.mqh to handle Range/Trend switching

// --- UTILITY FUNCTIONS ---
bool IsNewBar() { 
   static datetime last; 
   datetime curr=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE); 
   if(last!=curr){last=curr;return true;} 
   return false;
}

bool CheckVolatility() {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if (point == 0) return false;

   // Check Spread
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if (spread > MaxSpreadPoints) return false;
   
   // Check Candle Size (Current and Previous)
   double size0 = (GetHigh(_Period, 0) - GetLow(_Period, 0)) / point; 
   double size1 = (GetHigh(_Period, 1) - GetLow(_Period, 1)) / point; 
   
   if ((size0/10.0) > MaxCandleSizePips) return false;
   if ((size1/10.0) > MaxCandleSizePips) return false;
   
   return true;
}

void AddPoint(PointStruct &arr[], PointStruct &p) { 
   int s=ArraySize(arr); 
   ArrayResize(arr,s+1); arr[s]=p; 
}

// *** STRICT BREAKOUT LOGIC (Timeframe Aware) ***
bool CheckForBreakout(ENUM_TIMEFRAMES tf, int startBarIdx, int endBarIdx, double level, int type) { 
   for (int i = startBarIdx - 1; i >= endBarIdx; i--) { 
      if (i-1 < 0) return false;
      double c1 = GetClose(tf, i);   
      double c2 = GetClose(tf, i-1); 
      bool isBreak1 = false;
      
      if (type == 1) { // Supply Break (UP)
         if (c1 > level) isBreak1 = true;
         if (isBreak1) {
             if (IsMarubozu(tf, i) && c2 > level) return true;
             if (!IsMarubozu(tf, i) && c2 > c1) return true; 
         }
      } 
      else { // Demand Break (DOWN)
         if (c1 < level) isBreak1 = true;
         if (isBreak1) {
             if (IsMarubozu(tf, i) && c2 < level) return true;
             if (!IsMarubozu(tf, i) && c2 < c1) return true;
         }
      } 
   } 
   return false;
}

// *** TIMING HELPER (Timeframe Aware) ***
datetime FindBreakoutTime(ENUM_TIMEFRAMES tf, int startBar, int endBar, double level, int type) {
   for (int i = startBar - 1; i >= endBar; i--) {
       if (i-1 < 0) return 0;
       
       double c1 = GetClose(tf, i);
       double c2 = GetClose(tf, i-1);
       bool isBreak1 = false;

       if (type == 1) { 
           if (c1 > level) isBreak1 = true;
           if (isBreak1) {
               if (IsMarubozu(tf, i)) {
                   if (c2 > level) return GetTime(tf, i-1);
               } else {
                   if (c2 > c1) return GetTime(tf, i-1);
               }
           }
       } else { 
           if (c1 < level) isBreak1 = true;
           if (isBreak1) {
               if (IsMarubozu(tf, i)) {
                   if (c2 < level) return GetTime(tf, i-1);
               } else {
                   if (c2 < c1) return GetTime(tf, i-1);
               }
           }
       }
   }
   return 0;
}

// *** PULLBACK HELPER (Timeframe Aware) ***
bool CheckForPullback(ENUM_TIMEFRAMES tf, int i, int type) {
   int c1 = i - 1;
   int c2 = i - 2;
   
   if (type == 1) { // Check Pullback DOWN (from a High/Green candle)
      if (IsRed(tf, c1)) {
         if (IsStrongBody(tf, c1)) {
            if (IsRed(tf, c2)) return true;
            if (GetClose(tf, c2) < GetOpen(tf, i)) return true;
         } else {
            double rl = GetLow(tf, c1);
            for (int k = 1; k <= MaxScanDistance; k++) {
               int n = c1 - k;
               if (n < 0 || GetHigh(tf, n) > GetHigh(tf, i)) break;
               if (IsRed(tf, n) && IsStrongBody(tf, n) && GetClose(tf, n) < rl) {
                  return true;
               }
            }
         }
      }
   } 
   else if (type == -1) { // Check Pullback UP (from a Low/Red candle)
      if (IsGreen(tf, c1)) {
         if (IsStrongBody(tf, c1)) {
            if (IsGreen(tf, c2)) return true;
            if (GetClose(tf, c2) > GetOpen(tf, i)) return true;
         } else {
            double rh = GetHigh(tf, c1);
            for (int k = 1; k <= MaxScanDistance; k++) {
               int n = c1 - k;
               if (n < 0 || GetLow(tf, n) < GetLow(tf, i)) break;
               if (IsGreen(tf, n) && IsStrongBody(tf, n) && GetClose(tf, n) > rh) {
                  return true;
               }
            }
         }
      }
   }
   return false;
}