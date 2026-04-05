//+------------------------------------------------------------------+
//| NCI_ZigZag.mqh - Structure & Trend Engine                        |
//+------------------------------------------------------------------+
#property strict
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh"

// --- [FIXED] TREND CALCULATOR (STOP SIGN ADDED TO PREVENT DOMINO EFFECT) ---
void CalculateTrendsAndLock(ENUM_TIMEFRAMES tf, PointStruct &points[], int &marketTrend, string suffix, bool &resolved[]) { 
   int count = ArraySize(points);
   if (count < 2) return; 
   int runningTrend = 0; 

   // --- THE PRIVATE NOTEBOOK (Clean SMC State Machine) ---
   double activeBossSupply = 0; 
   double activeBossDemand = 0; 
   double internalHigh = 0; 
   double internalLow = 999999; 

   // --- STATIC MEMORY CACHE ---
   static datetime tCacheTime_HTF[]; static int tCacheTrend_HTF[];
   static double tCacheSL_HTF[]; static double tCacheDL_HTF[];
   static double tCacheIH_HTF[]; static double tCacheIL_HTF[];

   static datetime tCacheTime_LTF[]; static int tCacheTrend_LTF[];
   static double tCacheSL_LTF[]; static double tCacheDL_LTF[];
   static double tCacheIH_LTF[]; static double tCacheIL_LTF[];

   for (int i = 1; i < count; i++) { 
      PointStruct p = points[i];
      PointStruct prev = points[i-1]; 

      bool useCache = false;
      if (resolved[i]) { 
         int cacheSize = (suffix == "_HTF") ? ArraySize(tCacheTime_HTF) : ArraySize(tCacheTime_LTF);
         for (int c = 0; c < cacheSize; c++) {
            datetime cTime = (suffix == "_HTF") ? tCacheTime_HTF[c] : tCacheTime_LTF[c];
            if (cTime == p.time) {
               useCache = true;
               if (suffix == "_HTF") {
                  runningTrend = tCacheTrend_HTF[c];
                  activeBossSupply = tCacheSL_HTF[c]; activeBossDemand = tCacheDL_HTF[c];
                  internalHigh = tCacheIH_HTF[c]; internalLow = tCacheIL_HTF[c];
               } else {
                  runningTrend = tCacheTrend_LTF[c];
                  activeBossSupply = tCacheSL_LTF[c]; activeBossDemand = tCacheDL_LTF[c];
                  internalHigh = tCacheIH_LTF[c]; internalLow = tCacheIL_LTF[c];
               }
               points[i].assignedTrend = runningTrend;
               break;
            }
         }
      }

      if (useCache) continue; 

      if (prev.type == 1) { 
          internalHigh = prev.price;
          if (prev.zoneLimitTop > 0) activeBossSupply = prev.zoneLimitTop; 
      } 
      if (prev.type == -1) { 
          internalLow = prev.price;
          if (prev.zoneLimitBottom > 0) activeBossDemand = prev.zoneLimitBottom; 
      } 
      
      bool brokeSupplyBoss = false;
      bool brokeDemandBoss = false; 
      bool brokeInternalHigh = false;
      bool brokeInternalLow = false;
      
      if (activeBossSupply > 0) {
         brokeSupplyBoss = CheckForBreakout(tf, prev.barIndex, p.barIndex, activeBossSupply, 1);
      }
      if (activeBossDemand > 0) {
         brokeDemandBoss = CheckForBreakout(tf, prev.barIndex, p.barIndex, activeBossDemand, -1);
      }
      if (internalHigh > 0) {
         brokeInternalHigh = CheckForBreakout(tf, prev.barIndex, p.barIndex, internalHigh, 1);
      }
      if (internalLow < 999999) {
         brokeInternalLow = CheckForBreakout(tf, prev.barIndex, p.barIndex, internalLow, -1);
      }

      bool stateChanged = false;

      if (runningTrend == 1) { 
          if (brokeDemandBoss) {
              runningTrend = 0; 
              activeBossDemand = 0; 
              stateChanged = true; 
          }
      } 
      else if (runningTrend == -1) { 
          if (brokeSupplyBoss) {
              runningTrend = 0; 
              activeBossSupply = 0; 
              stateChanged = true; 
          }
      } 
      else { 
          if (brokeInternalHigh) { 
              runningTrend = 1; 
              activeBossDemand = 0; 
              stateChanged = true; 
          } 
          else if (brokeInternalLow) { 
              runningTrend = -1; 
              activeBossSupply = 0; 
              stateChanged = true; 
          } 
      } 
      
      if (!stateChanged && runningTrend == 0) {
          if (brokeSupplyBoss) { runningTrend = 1; activeBossDemand = 0; }
          else if (brokeDemandBoss) { runningTrend = -1; activeBossSupply = 0; }
      }

      points[i].assignedTrend = runningTrend; 

      if (resolved[i]) {
         if (suffix == "_HTF") {
            int s = ArraySize(tCacheTime_HTF);
            ArrayResize(tCacheTime_HTF, s + 1); ArrayResize(tCacheTrend_HTF, s + 1);
            ArrayResize(tCacheSL_HTF, s + 1); ArrayResize(tCacheDL_HTF, s + 1);
            ArrayResize(tCacheIH_HTF, s + 1); ArrayResize(tCacheIL_HTF, s + 1);

            tCacheTime_HTF[s] = p.time; tCacheTrend_HTF[s] = runningTrend;
            tCacheSL_HTF[s] = activeBossSupply; tCacheDL_HTF[s] = activeBossDemand;
            tCacheIH_HTF[s] = internalHigh; tCacheIL_HTF[s] = internalLow;
         } else {
            int s = ArraySize(tCacheTime_LTF);
            ArrayResize(tCacheTime_LTF, s + 1); ArrayResize(tCacheTrend_LTF, s + 1);
            ArrayResize(tCacheSL_LTF, s + 1); ArrayResize(tCacheDL_LTF, s + 1);
            ArrayResize(tCacheIH_LTF, s + 1); ArrayResize(tCacheIL_LTF, s + 1);

            tCacheTime_LTF[s] = p.time; tCacheTrend_LTF[s] = runningTrend;
            tCacheSL_LTF[s] = activeBossSupply; tCacheDL_LTF[s] = activeBossDemand;
            tCacheIH_LTF[s] = internalHigh; tCacheIL_LTF[s] = internalLow;
         }
      }
   } 
   marketTrend = runningTrend;
}

// --- [UPDATED] INDEPENDENT FVG MEMORY INJECTION ---
void CalculateZoneLimits(ENUM_TIMEFRAMES tf, PointStruct &p) { 
   p.zoneLimitTop = p.price; 
   p.zoneLimitBottom = p.price;
   
   // Initialize new FVG memory slots
   p.hasFVG = false;
   p.fvgTop = 0;
   p.fvgBottom = 0;
   
   int bars = Bars(_Symbol, tf);

   if (p.type == 1) { // DEMAND (Green)
      int gI=-1, rI=-1;
      for(int k=0;k<=5;k++){ 
         if(p.barIndex+k >= bars) break;
         if(IsGreen(tf, p.barIndex+k)){gI=p.barIndex+k;break;} 
      } 
      if(gI!=-1) rI=gI-1;
      if(gI!=-1) { 
         p.zoneLimitBottom = GetOpen(tf, gI);
         if(IsBigCandle(tf, gI)){ 
            if(rI!=-1){ 
               p.zoneLimitBottom = GetOpen(tf, rI);
               if(IsBigCandle(tf, rI)) p.zoneLimitBottom=(GetOpen(tf, rI)+GetClose(tf, rI))/2.0; 
            } else p.zoneLimitBottom=(GetOpen(tf, gI)+GetClose(tf, gI))/2.0;
         } 
         
         // --- FVG MEMORY INJECTION (DEMAND) ---
         if (Enable_FVG_Zones) {
             for (int i = gI - 1; i >= MathMax(0, gI - FVG_Max_Scan_Bars); i--) {
                 if (i - 1 < 0) break;
                 double low_current = GetLow(tf, i - 1);  // Candle 3 Low (Top of the gap)
                 double high_prev = GetHigh(tf, i + 1);   // Candle 1 High (Bottom of the gap)
                 
                 if (low_current > high_prev) { // Bullish FVG Found!
                     p.hasFVG = true;
                     p.fvgTop = low_current;    
                     p.fvgBottom = high_prev;   
                     break; 
                 }
             }
         }
      } 
   } else { // SUPPLY (Red)
      int rI=-1, gI=-1;
      for(int k=0;k<=5;k++){ 
         if(p.barIndex+k >= bars) break;
         if(IsRed(tf, p.barIndex+k)){rI=p.barIndex+k;break;} 
      } 
      if(rI!=-1) gI=rI-1;
      if(rI!=-1) { 
         p.zoneLimitTop = GetOpen(tf, rI);
         if(IsBigCandle(tf, rI)){ 
            if(gI!=-1){ 
               p.zoneLimitTop = GetOpen(tf, gI);
               if(IsBigCandle(tf, gI)) p.zoneLimitTop=(GetOpen(tf, gI)+GetClose(tf, gI))/2.0; 
            } else p.zoneLimitTop=(GetOpen(tf, rI)+GetClose(tf, rI))/2.0;
         } 
         
         // --- FVG MEMORY INJECTION (SUPPLY) ---
         if (Enable_FVG_Zones) {
             for (int i = rI - 1; i >= MathMax(0, rI - FVG_Max_Scan_Bars); i--) {
                 if (i - 1 < 0) break;
                 double high_current = GetHigh(tf, i - 1); // Candle 3 High (Bottom of the gap)
                 double low_prev = GetLow(tf, i + 1);      // Candle 1 Low (Top of the gap)
                 
                 if (high_current < low_prev) { // Bearish FVG Found!
                     p.hasFVG = true;
                     p.fvgTop = low_prev;       
                     p.fvgBottom = high_current;
                     break; 
                 }
             }
         }
      } 
   } 
}

void DrawZigZagLines(string suffix, PointStruct &points[]) { 
   if (!Show_ZigZag_Lines) return;
   if (MQLInfoInteger(MQL_OPTIMIZATION)) return;
   ObjectsDeleteAll(0, "NCI_ZZ_" + suffix);
   if (suffix == "_HTF" && !ShowHTF) return;
   if (suffix == "_LTF" && !ShowLTF) return;

   int c=ArraySize(points); 
   if(c<2)return; 
   
   int width = (suffix == "_HTF") ? LineWidth + 1 : LineWidth; 

   for(int i=1;i<c;i++){ 
      int t=points[i].assignedTrend; 
      color cl=(t==1)?ColorUp:(t==-1)?ColorDown:ColorRange;
      string n="NCI_ZZ_" + suffix + IntegerToString(i); 
      ObjectCreate(0,n,OBJ_TREND,0,points[i-1].time,points[i-1].price,points[i].time,points[i].price); 
      ObjectSetInteger(0,n,OBJPROP_COLOR,cl); 
      ObjectSetInteger(0,n,OBJPROP_WIDTH,width); 
      ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false); 
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); 
   } 
   ChartRedraw();
}

void UpdateZigZagMap(ENUM_TIMEFRAMES tf, PointStruct &targetPoints[], int &targetTrend, string suffix) { 
   int totalBars = Bars(_Symbol, tf);
   if (totalBars < 500) return; 
   PointStruct Alarms[]; 
   int alarmCount = 0; 
   int startBar = MathMin(HistoryBars, totalBars - 10);
   for (int i = startBar; i >= 5; i--) { 
      if (IsGreen(tf, i)) { 
         if (CheckForPullback(tf, i, 1)) {
            ArrayResize(Alarms,alarmCount+1);
            Alarms[alarmCount].price=GetHigh(tf, i); 
            Alarms[alarmCount].time=GetTime(tf, i); 
            Alarms[alarmCount].type=1; 
            Alarms[alarmCount].barIndex=i; 
            alarmCount++; 
         }
      } 
      if (IsRed(tf, i)) { 
         if (CheckForPullback(tf, i, -1)) {
            ArrayResize(Alarms,alarmCount+1);
            Alarms[alarmCount].price=GetLow(tf, i); 
            Alarms[alarmCount].time=GetTime(tf, i); 
            Alarms[alarmCount].type=-1; 
            Alarms[alarmCount].barIndex=i; 
            alarmCount++; 
         }
      } 
   } 
   if (alarmCount < 2) return;
   ArrayResize(targetPoints, 0); 
   int state = 0; 
   PointStruct pendingPoint; 
   int lastCommittedIndex = startBar + 5;
   if (Alarms[0].type == 1) { 
      AddPoint(targetPoints, Alarms[0]); 
      lastCommittedIndex = Alarms[0].barIndex; 
      state = -1;
      pendingPoint.price = 999999; 
   } else { 
      AddPoint(targetPoints, Alarms[0]); 
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
         int hI = iHighest(_Symbol, tf, MODE_HIGH, count, searchStart);
         double hP = GetHigh(tf, hI); 
         if (hP > pendingPoint.price) { 
            pendingPoint.price=hP;
            pendingPoint.time=GetTime(tf, hI); 
            pendingPoint.barIndex=hI; 
            pendingPoint.type=1; 
         } 
         if (Alarms[i].type == -1) { 
            AddPoint(targetPoints, pendingPoint);
            lastCommittedIndex=pendingPoint.barIndex; 
            state=-1; 
            pendingPoint.price=999999; 
            i--; 
         } 
      } else if (state == -1) { 
         int lI = iLowest(_Symbol, tf, MODE_LOW, count, searchStart);
         double lP = GetLow(tf, lI); 
         if (lP < pendingPoint.price) { 
            pendingPoint.price=lP;
            pendingPoint.time=GetTime(tf, lI); 
            pendingPoint.barIndex=lI; 
            pendingPoint.type=-1; 
         } 
         if (Alarms[i].type == 1) { 
            AddPoint(targetPoints, pendingPoint);
            lastCommittedIndex=pendingPoint.barIndex; 
            state=1; 
            pendingPoint.price=0; 
            i--; 
         } 
      } 
   } 
   for(int i=0; i<ArraySize(targetPoints); i++) CalculateZoneLimits(tf, targetPoints[i]);

   static datetime cacheTime_HTF[]; static int cacheStatus_HTF[];
   static datetime cacheTime_LTF[]; static int cacheStatus_LTF[];

   bool resolvedPoints[];
   int ptsCount = ArraySize(targetPoints);
   ArrayResize(resolvedPoints, ptsCount);
   for(int i=0; i<ptsCount; i++) resolvedPoints[i] = true; 

   // =========================================================
   // TOGGLE: USE RETAIL ZONES VS STRICT SMC ZONES
   // =========================================================
   if (Use_Strict_SMC_Zones) {
       double activeMacroSupply = 0;
       double activeMacroDemand = 0;
       double extremeHigh = 0;
       double extremeLow = 999999;

       for (int i = 0; i < ptsCount; i++) {
           if (i == 0) {
               if (targetPoints[i].type == 1) {
                   activeMacroSupply = targetPoints[i].price;
                   extremeHigh = targetPoints[i].price;
               } else {
                   activeMacroDemand = targetPoints[i].price;
                   extremeLow = targetPoints[i].price;
               }
               resolvedPoints[i] = true;
               continue;
           }

           bool isValidated = false;
           bool isResolved = false;
           
           int cacheSize = (suffix == "_HTF") ? ArraySize(cacheTime_HTF) : ArraySize(cacheTime_LTF);
           for(int c = 0; c < cacheSize; c++) {
               datetime cTime = (suffix == "_HTF") ? cacheTime_HTF[c] : cacheTime_LTF[c];
               if(cTime == targetPoints[i].time) {
                   int cStatus = (suffix == "_HTF") ? cacheStatus_HTF[c] : cacheStatus_LTF[c];
                   isResolved = true;
                   isValidated = (cStatus == 1); 
                   break;
               }
           }

           if (targetPoints[i].type == -1) { 
               double targetToBreak = (activeMacroSupply > 0) ? activeMacroSupply : extremeHigh;
               
               if (targetToBreak > 0) {
                   if (!isResolved) {
                       datetime t_break = FindBreakoutTime(tf, targetPoints[i].barIndex, 0, targetToBreak, 1);
                       datetime t_fail = FindBreakoutTime(tf, targetPoints[i].barIndex, 0, targetPoints[i].price, -1);
                       
                       if (t_break > 0 && (t_fail == 0 || t_break < t_fail)) {
                           bool isOverwritten = false;
                           for (int j = i + 1; j < ArraySize(targetPoints); j++) {
                               if (targetPoints[j].type == -1 && targetPoints[j].time < t_break) {
                                   isOverwritten = true; break;
                               }
                           }
                           if (!isOverwritten) isValidated = true;
                       }

                       if (t_break > 0 || t_fail > 0) {
                           isResolved = true; 
                           
                           if (suffix == "_HTF") {
                               int s = ArraySize(cacheTime_HTF);
                               ArrayResize(cacheTime_HTF, s + 1); ArrayResize(cacheStatus_HTF, s + 1);
                               cacheTime_HTF[s] = targetPoints[i].time; cacheStatus_HTF[s] = isValidated ? 1 : -1;
                           } else {
                               int s = ArraySize(cacheTime_LTF);
                               ArrayResize(cacheTime_LTF, s + 1); ArrayResize(cacheStatus_LTF, s + 1);
                               cacheTime_LTF[s] = targetPoints[i].time; cacheStatus_LTF[s] = isValidated ? 1 : -1;
                           }
                       }
                   }
               } else {
                   isValidated = true;
                   isResolved = true;
               }

               if (isValidated) {
                   activeMacroDemand = targetPoints[i].price; 
                   extremeLow = targetPoints[i].price; 
                   activeMacroSupply = 0;
               } else {
                   targetPoints[i].zoneLimitTop = 0;
                   targetPoints[i].zoneLimitBottom = 0;
                   if (targetPoints[i].price < extremeLow) extremeLow = targetPoints[i].price;
               }

               resolvedPoints[i] = isResolved; // Lock the handshake
           }
           else if (targetPoints[i].type == 1) { 
               double targetToBreak = (activeMacroDemand > 0) ? activeMacroDemand : extremeLow;
               
               if (targetToBreak > 0 && targetToBreak != 999999) {
                   if (!isResolved) {
                       datetime t_break = FindBreakoutTime(tf, targetPoints[i].barIndex, 0, targetToBreak, -1);
                       datetime t_fail = FindBreakoutTime(tf, targetPoints[i].barIndex, 0, targetPoints[i].price, 1);
                       
                       if (t_break > 0 && (t_fail == 0 || t_break < t_fail)) {
                           bool isOverwritten = false;
                           for (int j = i + 1; j < ArraySize(targetPoints); j++) {
                               if (targetPoints[j].type == 1 && targetPoints[j].time < t_break) {
                                   isOverwritten = true; break;
                               }
                           }
                           if (!isOverwritten) isValidated = true;
                       }

                       if (t_break > 0 || t_fail > 0) {
                           isResolved = true; 

                           if (suffix == "_HTF") {
                               int s = ArraySize(cacheTime_HTF);
                               ArrayResize(cacheTime_HTF, s + 1); ArrayResize(cacheStatus_HTF, s + 1);
                               cacheTime_HTF[s] = targetPoints[i].time; cacheStatus_HTF[s] = isValidated ? 1 : -1;
                           } else {
                               int s = ArraySize(cacheTime_LTF);
                               ArrayResize(cacheTime_LTF, s + 1); ArrayResize(cacheStatus_LTF, s + 1);
                               cacheTime_LTF[s] = targetPoints[i].time; cacheStatus_LTF[s] = isValidated ? 1 : -1;
                           }
                       }
                   }
               } else {
                   isValidated = true;
                   isResolved = true;
               }

               if (isValidated) {
                   activeMacroSupply = targetPoints[i].price;
                   extremeHigh = targetPoints[i].price; 
                   activeMacroDemand = 0;
               } else {
                   targetPoints[i].zoneLimitTop = 0;
                   targetPoints[i].zoneLimitBottom = 0;
                   if (targetPoints[i].price > extremeHigh) extremeHigh = targetPoints[i].price;
               }

               resolvedPoints[i] = isResolved; // Lock the handshake
           }
       }
   }
   // =========================================================
   // END OF TOGGLE SWITCH
   // =========================================================

   CalculateTrendsAndLock(tf, targetPoints, targetTrend, suffix, resolvedPoints); 

   DrawZigZagLines(suffix, targetPoints);
}