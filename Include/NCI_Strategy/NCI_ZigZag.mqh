//+------------------------------------------------------------------+
//| NCI_ZigZag.mqh - Structure & Trend Engine                        |
//+------------------------------------------------------------------+
#property strict

#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh"

void CalculateTrendsAndLock() { 
   int count = ArraySize(ZigZagPoints); 
   if (count < 2) return; 
   int runningTrend = 0; 
   double lastSupplyLevel = 0; int lastSupplyIdx = -1; 
   double lastDemandLevel = 0; int lastDemandIdx = -1; 
   double prevHigh = 0; double prevLow = 0; 
   for (int i = 1; i < count; i++) { 
      PointStruct p = ZigZagPoints[i]; 
      PointStruct prev = ZigZagPoints[i-1]; 
      if (prev.type == 1) { lastSupplyLevel = prev.zoneLimitTop; lastSupplyIdx = prev.barIndex; prevHigh = prev.price; } 
      if (prev.type == -1) { lastDemandLevel = prev.zoneLimitBottom; lastDemandIdx = prev.barIndex; prevLow = prev.price; } 
      
      bool brokenSupply = false; bool brokenDemand = false; 
      
      // *** CRITICAL FIX: Use Strict 2-Candle Logic for Line Coloring ***
      
      if (lastSupplyIdx != -1) {
          // OLD LOGIC (Simple Touch):
          // if (p.price > lastSupplyLevel) brokenSupply = true; 
          
          // NEW LOGIC (Strict Close):
          // We check if strict breakout rules were met between creation and now.
          brokenSupply = CheckForBreakout(lastSupplyIdx, p.barIndex, lastSupplyLevel, 1);
      }
      
      if (lastDemandIdx != -1) {
          // OLD LOGIC (Simple Touch):
          // if (p.price < lastDemandLevel) brokenDemand = true; 
          
          // NEW LOGIC (Strict Close):
          brokenDemand = CheckForBreakout(lastDemandIdx, p.barIndex, lastDemandLevel, -1);
      }

      if (runningTrend == -1) { if (brokenSupply) runningTrend = 0; } 
      else if (runningTrend == 1) { if (brokenDemand) runningTrend = 0; } 
      else { 
         if (p.type == 1) { if (brokenSupply || (prevHigh != 0 && p.price > prevHigh)) { if (!brokenDemand) runningTrend = 1; } } 
         if (p.type == -1) { if (brokenDemand || (prevLow != 0 && p.price < prevLow)) { if (!brokenSupply) runningTrend = -1; } } 
         if (brokenSupply && p.type == 1 && prevHigh != 0 && p.price > prevHigh) runningTrend = 1; 
         if (brokenDemand && p.type == -1 && prevLow != 0 && p.price < prevLow) runningTrend = -1; 
      } 
      ZigZagPoints[i].assignedTrend = runningTrend; 
   } 
   currentMarketTrend = runningTrend; 
}

void CalculateZoneLimits(PointStruct &p) { 
   p.zoneLimitTop = p.price; 
   p.zoneLimitBottom = p.price; 
   if (p.type == 1) { 
      int gI=-1, rI=-1; 
      for(int k=0;k<=5;k++){ 
         if(p.barIndex+k >= Bars(_Symbol,_Period)) break; 
         if(IsGreen(p.barIndex+k)){gI=p.barIndex+k;break;} 
      } 
      if(gI!=-1) rI=gI-1; 
      if(gI!=-1) { 
         p.zoneLimitBottom = GetOpen(gI); 
         if(IsBigCandle(gI)){ 
            if(rI!=-1){ 
               p.zoneLimitBottom = GetOpen(rI); 
               if(IsBigCandle(rI)) p.zoneLimitBottom=(GetOpen(rI)+GetClose(rI))/2.0; 
            } else p.zoneLimitBottom=(GetOpen(gI)+GetClose(gI))/2.0; 
         } 
      } 
   } else { 
      int rI=-1, gI=-1; 
      for(int k=0;k<=5;k++){ 
         if(p.barIndex+k >= Bars(_Symbol,_Period)) break; 
         if(IsRed(p.barIndex+k)){rI=p.barIndex+k;break;} 
      } 
      if(rI!=-1) gI=rI-1; 
      if(rI!=-1) { 
         p.zoneLimitTop = GetOpen(rI); 
         if(IsBigCandle(rI)){ 
            if(gI!=-1){ 
               p.zoneLimitTop = GetOpen(gI); 
               if(IsBigCandle(gI)) p.zoneLimitTop=(GetOpen(gI)+GetClose(gI))/2.0; 
            } else p.zoneLimitTop=(GetOpen(rI)+GetClose(rI))/2.0; 
         } 
      } 
   } 
}

void DrawZigZagLines() { 
   ObjectsDeleteAll(0, "NCI_ZZ_"); 
   int c=ArraySize(ZigZagPoints); 
   if(c<2)return; 
   for(int i=1;i<c;i++){ 
      int t=ZigZagPoints[i].assignedTrend; 
      color cl=(t==1)?ColorUp:(t==-1)?ColorDown:ColorRange; 
      string n="NCI_ZZ_"+IntegerToString(i); 
      ObjectCreate(0,n,OBJ_TREND,0,ZigZagPoints[i-1].time,ZigZagPoints[i-1].price,ZigZagPoints[i].time,ZigZagPoints[i].price); 
      ObjectSetInteger(0,n,OBJPROP_COLOR,cl); 
      ObjectSetInteger(0,n,OBJPROP_WIDTH,LineWidth); 
      ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false); 
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); 
   } 
   ChartRedraw(); 
}

void UpdateZigZagMap() { 
   int totalBars = Bars(_Symbol, _Period); 
   if (totalBars < 500) return; 
   PointStruct Alarms[]; 
   int alarmCount = 0; 
   int startBar = MathMin(HistoryBars, totalBars - 10); 
   for (int i = startBar; i >= 5; i--) { 
      if (IsGreen(i)) { 
         int c1=i-1; 
         int c2=i-2; 
         if(IsRed(c1)){ 
            if(IsStrongBody(c1)){ 
               bool confirm = false; 
               if(IsRed(c2)) confirm = true; 
               else if(GetClose(c2) < GetOpen(i)) confirm = true; 
               if(confirm) { 
                  ArrayResize(Alarms,alarmCount+1); 
                  Alarms[alarmCount].price=GetHigh(i); 
                  Alarms[alarmCount].time=GetTime(i); 
                  Alarms[alarmCount].type=1; 
                  Alarms[alarmCount].barIndex=i; 
                  alarmCount++; 
               } 
            } else { 
               double rl=GetLow(c1); 
               for(int k=1;k<=MaxScanDistance;k++){ 
                  int n=c1-k; 
                  if(n<0||GetHigh(n)>GetHigh(i))break; 
                  if(IsRed(n)&&IsStrongBody(n)&&GetClose(n)<rl){ 
                     ArrayResize(Alarms,alarmCount+1); 
                     Alarms[alarmCount].price=GetHigh(i); 
                     Alarms[alarmCount].time=GetTime(i); 
                     Alarms[alarmCount].type=1; 
                     Alarms[alarmCount].barIndex=i; 
                     alarmCount++; 
                     break; 
                  } 
               } 
            } 
         } 
      } 
      if (IsRed(i)) { 
         int c1=i-1; 
         int c2=i-2; 
         if(IsGreen(c1)){ 
            if(IsStrongBody(c1)){ 
               bool confirm = false; 
               if(IsGreen(c2)) confirm = true; 
               else if(GetClose(c2) > GetOpen(i)) confirm = true; 
               if(confirm) { 
                  ArrayResize(Alarms,alarmCount+1); 
                  Alarms[alarmCount].price=GetLow(i); 
                  Alarms[alarmCount].time=GetTime(i); 
                  Alarms[alarmCount].type=-1; 
                  Alarms[alarmCount].barIndex=i; 
                  alarmCount++; 
               } 
            } else { 
               double rh=GetHigh(c1); 
               for(int k=1;k<=MaxScanDistance;k++){ 
                  int n=c1-k; 
                  if(n<0||GetLow(n)<GetLow(i))break; 
                  if(IsGreen(n)&&IsStrongBody(n)&&GetClose(n)>rh){ 
                     ArrayResize(Alarms,alarmCount+1); 
                     Alarms[alarmCount].price=GetLow(i); 
                     Alarms[alarmCount].time=GetTime(i); 
                     Alarms[alarmCount].type=-1; 
                     Alarms[alarmCount].barIndex=i; 
                     alarmCount++; 
                     break; 
                  } 
               } 
            } 
         } 
      } 
   } 
   if (alarmCount < 2) return; 
   ArrayResize(ZigZagPoints, 0); 
   int state = 0; 
   PointStruct pendingPoint; 
   int lastCommittedIndex = startBar + 5; 
   if (Alarms[0].type == 1) { 
      AddPoint(ZigZagPoints, Alarms[0]); 
      lastCommittedIndex = Alarms[0].barIndex; 
      state = -1; 
      pendingPoint.price = 999999; 
   } else { 
      AddPoint(ZigZagPoints, Alarms[0]); 
      lastCommittedIndex = Alarms[0].barIndex; 
      state = 1; 
      pendingPoint.price = 0; 
   } 
   for (int i = 1; i < alarmCount; i++) { 
      int searchStart = Alarms[i].barIndex; 
      int searchEnd = lastCommittedIndex - 1; 
      int count = searchEnd - searchStart + 1; 
      if (count <= 0) continue; 
      if (state == 1) { 
         int hI = iHighest(_Symbol, _Period, MODE_HIGH, count, searchStart); 
         double hP = GetHigh(hI); 
         if (hP > pendingPoint.price) { 
            pendingPoint.price=hP; 
            pendingPoint.time=GetTime(hI); 
            pendingPoint.barIndex=hI; 
            pendingPoint.type=1; 
         } 
         if (Alarms[i].type == -1) { 
            AddPoint(ZigZagPoints, pendingPoint); 
            lastCommittedIndex=pendingPoint.barIndex; 
            state=-1; 
            pendingPoint.price=999999; 
            i--; 
         } 
      } else if (state == -1) { 
         int lI = iLowest(_Symbol, _Period, MODE_LOW, count, searchStart); 
         double lP = GetLow(lI); 
         if (lP < pendingPoint.price) { 
            pendingPoint.price=lP; 
            pendingPoint.time=GetTime(lI); 
            pendingPoint.barIndex=lI; 
            pendingPoint.type=-1; 
         } 
         if (Alarms[i].type == 1) { 
            AddPoint(ZigZagPoints, pendingPoint); 
            lastCommittedIndex=pendingPoint.barIndex; 
            state=1; 
            pendingPoint.price=0; 
            i--; 
         } 
      } 
   } 
   for(int i=0; i<ArraySize(ZigZagPoints); i++) CalculateZoneLimits(ZigZagPoints[i]); 
   CalculateTrendsAndLock(); 
   DrawZigZagLines(); 
}