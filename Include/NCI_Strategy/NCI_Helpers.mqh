//+------------------------------------------------------------------+
//| NCI_Helpers.mqh - Utility Functions                              |
//+------------------------------------------------------------------+
#property strict

// Includes
#include "NCI_Structs.mqh" 
#include "NCI_Constants.mqh"

// --- DATA WRAPPERS ---
double GetHigh(int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyHigh(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
double GetLow(int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyLow(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
double GetOpen(int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyOpen(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
double GetClose(int index) {
   double buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyClose(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0.0;
}
datetime GetTime(int index) {
   datetime buffer[]; ArraySetAsSeries(buffer, true);
   if(CopyTime(_Symbol, _Period, index, 1, buffer) > 0) return buffer[0];
   return 0;
}

// --- CANDLE CHECKS ---
bool IsGreen(int index) { return GetClose(index)>GetOpen(index); }
bool IsRed(int index) { return GetClose(index)<GetOpen(index); }

bool IsStrongBody(int index) { 
   double h=GetHigh(index); double l=GetLow(index); 
   if(h-l==0)return false; 
   double b=MathAbs(GetOpen(index)-GetClose(index)); 
   return(b>(h-l)*MinBodyPercent); 
}

bool IsBigCandle(int index) { 
   double b=MathAbs(GetOpen(index)-GetClose(index)); 
   double s=0; int c=0; 
   int bars = Bars(_Symbol, _Period); 
   for(int k=1;k<=10;k++){
      if(index+k>=bars)break;
      s+=MathAbs(GetOpen(index+k)-GetClose(index+k));
      c++;
   } 
   if(c==0)return false; return(b>(s/c)*BigCandleFactor); 
}

bool IsNewBar() { 
   static datetime last; 
   datetime curr=(datetime)SeriesInfoInteger(_Symbol,_Period,SERIES_LASTBAR_DATE); 
   if(last!=curr){last=curr;return true;} 
   return false; 
}

bool CheckVolatility() {
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if (spread > MaxSpreadPoints) return false;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double size0 = (GetHigh(0) - GetLow(0)) / point / 10.0; 
   double size1 = (GetHigh(1) - GetLow(1)) / point / 10.0; 
   if (size0 > MaxCandleSizePips) return false;
   if (size1 > MaxCandleSizePips) return false;
   return true;
}

// --- SHARED LOGIC HELPERS ---
void AddPoint(PointStruct &arr[], PointStruct &p) { 
   int s=ArraySize(arr); ArrayResize(arr,s+1); arr[s]=p; 
}

// *** STRICT BREAKOUT LOGIC (Used by ZigZag AND Zones) ***
bool CheckForBreakout(int startBarIdx, int endBarIdx, double level, int type) { 
   for (int i = startBarIdx - 1; i >= endBarIdx; i--) { 
      if (i-1 < 0) return false; 
      if (type == 1) { 
         double c1 = GetClose(i); 
         double c2 = GetClose(i-1); 
         if (c1 > level && c2 > level && c2 > c1) return true; 
      } else { 
         double c1 = GetClose(i); 
         double c2 = GetClose(i-1); 
         if (c1 < level && c2 < level && c2 < c1) return true; 
      } 
   } 
   return false; 
}

// *** UPDATED: TIMING HELPER (Now uses Strict Confirmation) ***
datetime FindBreakoutTime(int startBar, int endBar, double level, int type) {
   for (int i = startBar - 1; i >= endBar; i--) {
       if (i-1 < 0) return 0; // Ensure we have space for the 2nd candle
       
       if (type == 1) { // Supply Break (Up)
           double c1 = GetClose(i);     // 1st Candle (The Break)
           double c2 = GetClose(i-1);   // 2nd Candle (The Confirmation)
           
           // Strict Momentum Rule: Both above level, 2nd higher than 1st
           if (c1 > level && c2 > level && c2 > c1) {
               return GetTime(i-1); // Return TIME of CONFIRMATION (2nd Candle)
           }
       } 
       else { // Demand Break (Down)
           double c1 = GetClose(i);     // 1st Candle (The Break)
           double c2 = GetClose(i-1);   // 2nd Candle (The Confirmation)
           
           // Strict Momentum Rule: Both below level, 2nd lower than 1st
           if (c1 < level && c2 < level && c2 < c1) {
               return GetTime(i-1); // Return TIME of CONFIRMATION (2nd Candle)
           }
       }
   }
   return 0;
}