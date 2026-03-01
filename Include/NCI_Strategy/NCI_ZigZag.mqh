//+------------------------------------------------------------------+
//| NCI_ZigZag.mqh - Structure & Trend Engine                        |
//+------------------------------------------------------------------+
#property strict
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh"

// --- [FIXED] TREND CALCULATOR (AMNESIA BUG PATCHED) ---
void CalculateTrendsAndLock(ENUM_TIMEFRAMES tf, PointStruct &points[], int &marketTrend, string suffix, bool &resolved[]) { 
   int count = ArraySize(points);
   if (count < 2) return; 
   int runningTrend = 0; 
   double lastSupplyLevel = 0; int lastSupplyIdx = -1;
   double lastDemandLevel = 0; int lastDemandIdx = -1; 
   double prevHigh = 0; double prevLow = 0;

   // --- STATIC MEMORY CACHE ---
   static datetime tCacheTime_HTF[]; static int tCacheTrend_HTF[];
   static double tCacheSL_HTF[]; static int tCacheSI_HTF[];
   static double tCacheDL_HTF[]; static int tCacheDI_HTF[];
   static double tCachePH_HTF[]; static double tCachePL_HTF[];

   static datetime tCacheTime_LTF[]; static int tCacheTrend_LTF[];
   static double tCacheSL_LTF[]; static int tCacheSI_LTF[];
   static double tCacheDL_LTF[]; static int tCacheDI_LTF[];
   static double tCachePH_LTF[]; static double tCachePL_LTF[];

   for (int i = 1; i < count; i++) { 
      PointStruct p = points[i];
      PointStruct prev = points[i-1]; 

      // 1. CHECK THE MEMORY CACHE (ONLY IF THE POINT IS FULLY RESOLVED BY SMC!)
      bool useCache = false;
      if (resolved[i]) { 
         int cacheSize = (suffix == "_HTF") ? ArraySize(tCacheTime_HTF) : ArraySize(tCacheTime_LTF);
         for (int c = 0; c < cacheSize; c++) {
            datetime cTime = (suffix == "_HTF") ? tCacheTime_HTF[c] : tCacheTime_LTF[c];
            if (cTime == p.time) {
               useCache = true;
               if (suffix == "_HTF") {
                  runningTrend = tCacheTrend_HTF[c];
                  lastSupplyLevel = tCacheSL_HTF[c]; lastSupplyIdx = tCacheSI_HTF[c];
                  lastDemandLevel = tCacheDL_HTF[c]; lastDemandIdx = tCacheDI_HTF[c];
                  prevHigh = tCachePH_HTF[c]; prevLow = tCachePL_HTF[c];
               } else {
                  runningTrend = tCacheTrend_LTF[c];
                  lastSupplyLevel = tCacheSL_LTF[c]; lastSupplyIdx = tCacheSI_LTF[c];
                  lastDemandLevel = tCacheDL_LTF[c]; lastDemandIdx = tCacheDI_LTF[c];
                  prevHigh = tCachePH_LTF[c]; prevLow = tCachePL_LTF[c];
               }
               points[i].assignedTrend = runningTrend;
               break;
            }
         }
      }

      if (useCache) continue; // IF CACHED, SKIP THE MATH!

      // 2. IF NOT CACHED, CALCULATE IT
      if (prev.type == 1 && prev.zoneLimitTop > 0) { 
          lastSupplyLevel = prev.zoneLimitTop; 
          lastSupplyIdx = prev.barIndex; 
          prevHigh = prev.price;
      } 
      if (prev.type == -1 && prev.zoneLimitBottom > 0) { 
          lastDemandLevel = prev.zoneLimitBottom; 
          lastDemandIdx = prev.barIndex;
          prevLow = prev.price; 
      } 
      
      bool brokenSupply = false;
      bool brokenDemand = false; 
      
      if (lastSupplyIdx != -1 && lastSupplyLevel > 0) {
         brokenSupply = CheckForBreakout(tf, lastSupplyIdx, p.barIndex, lastSupplyLevel, 1);
      }
      
      if (lastDemandIdx != -1 && lastDemandLevel > 0) {
         brokenDemand = CheckForBreakout(tf, lastDemandIdx, p.barIndex, lastDemandLevel, -1);
      }

      // --- THE AMNESIA FIX: CUT THE CORD TO ANCIENT MEMORIES ---
      if (runningTrend == -1) { 
          if (brokenSupply) {
              runningTrend = 0;
              // Downtrend is dead. Erase the ancient Boss Demand memory so it doesn't falsely pull us back!
              lastDemandLevel = 0; lastDemandIdx = -1; prevLow = 0; brokenDemand = false;
          }
      } 
      else if (runningTrend == 1) { 
          if (brokenDemand) {
              runningTrend = 0;
              // Uptrend is dead. Erase the ancient Boss Supply memory so it doesn't falsely pull us back!
              lastSupplyLevel = 0; lastSupplyIdx = -1; prevHigh = 0; brokenSupply = false;
          }
      } 
      else { 
         if (p.type == 1) { 
             if (brokenSupply || (prevHigh != 0 && p.price > prevHigh)) { 
                 if (!brokenDemand) {
                     runningTrend = 1;
                     // New Uptrend officially born! Clear old Demand memories.
                     lastDemandLevel = 0; lastDemandIdx = -1; prevLow = 0;
                 }
             } 
         } 
         if (p.type == -1) { 
             if (brokenDemand || (prevLow != 0 && p.price < prevLow)) { 
                 if (!brokenSupply) {
                     runningTrend = -1;
                     // New Downtrend officially born! Clear old Supply memories.
                     lastSupplyLevel = 0; lastSupplyIdx = -1; prevHigh = 0;
                 }
             } 
         } 
         // Fallback Overrides
         if (runningTrend == 0) {
             if (brokenSupply && p.type == 1 && prevHigh != 0 && p.price > prevHigh) {
                 runningTrend = 1;
                 lastDemandLevel = 0; lastDemandIdx = -1; prevLow = 0;
             }
             if (brokenDemand && p.type == -1 && prevLow != 0 && p.price < prevLow) {
                 runningTrend = -1;
                 lastSupplyLevel = 0; lastSupplyIdx = -1; prevHigh = 0;
             }
         }
      } 
      points[i].assignedTrend = runningTrend; 

      // 3. SAVE TO MEMORY CACHE (ONLY IF THE POINT IS FULLY RESOLVED BY SMC!)
      if (resolved[i]) {
         if (suffix == "_HTF") {
            int s = ArraySize(tCacheTime_HTF);
            ArrayResize(tCacheTime_HTF, s + 1); ArrayResize(tCacheTrend_HTF, s + 1);
            ArrayResize(tCacheSL_HTF, s + 1); ArrayResize(tCacheSI_HTF, s + 1);
            ArrayResize(tCacheDL_HTF, s + 1); ArrayResize(tCacheDI_HTF, s + 1);
            ArrayResize(tCachePH_HTF, s + 1); ArrayResize(tCachePL_HTF, s + 1);

            tCacheTime_HTF[s] = p.time; tCacheTrend_HTF[s] = runningTrend;
            tCacheSL_HTF[s] = lastSupplyLevel; tCacheSI_HTF[s] = lastSupplyIdx;
            tCacheDL_HTF[s] = lastDemandLevel; tCacheDI_HTF[s] = lastDemandIdx;
            tCachePH_HTF[s] = prevHigh; tCachePL_HTF[s] = prevLow;
         } else {
            int s = ArraySize(tCacheTime_LTF);
            ArrayResize(tCacheTime_LTF, s + 1); ArrayResize(tCacheTrend_LTF, s + 1);
            ArrayResize(tCacheSL_LTF, s + 1); ArrayResize(tCacheSI_LTF, s + 1);
            ArrayResize(tCacheDL_LTF, s + 1); ArrayResize(tCacheDI_LTF, s + 1);
            ArrayResize(tCachePH_LTF, s + 1); ArrayResize(tCachePL_LTF, s + 1);

            tCacheTime_LTF[s] = p.time; tCacheTrend_LTF[s] = runningTrend;
            tCacheSL_LTF[s] = lastSupplyLevel; tCacheSI_LTF[s] = lastSupplyIdx;
            tCacheDL_LTF[s] = lastDemandLevel; tCacheDI_LTF[s] = lastDemandIdx;
            tCachePH_LTF[s] = prevHigh; tCachePL_LTF[s] = prevLow;
         }
      }
   } 
   marketTrend = runningTrend;
}

// [Keep CalculateZoneLimits ... unchanged]
void CalculateZoneLimits(ENUM_TIMEFRAMES tf, PointStruct &p) { 
   p.zoneLimitTop = p.price; 
   p.zoneLimitBottom = p.price;
   int bars = Bars(_Symbol, tf);

   if (p.type == 1) { 
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
      } 
   } else { 
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
         int c1=i-1;
         int c2=i-2; 
         if(IsRed(tf, c1)){ 
            if(IsStrongBody(tf, c1)){ 
               bool confirm = false;
               if(IsRed(tf, c2)) confirm = true; 
               else if(GetClose(tf, c2) < GetOpen(tf, i)) confirm = true;
               if(confirm) { 
                  ArrayResize(Alarms,alarmCount+1);
                  Alarms[alarmCount].price=GetHigh(tf, i); 
                  Alarms[alarmCount].time=GetTime(tf, i); 
                  Alarms[alarmCount].type=1; 
                  Alarms[alarmCount].barIndex=i; 
                  alarmCount++; 
               } 
            } else { 
               double rl=GetLow(tf, c1);
               for(int k=1;k<=MaxScanDistance;k++){ 
                  int n=c1-k;
                  if(n<0||GetHigh(tf, n)>GetHigh(tf, i))break; 
                  if(IsRed(tf, n)&&IsStrongBody(tf, n)&&GetClose(tf, n)<rl){ 
                     ArrayResize(Alarms,alarmCount+1);
                     Alarms[alarmCount].price=GetHigh(tf, i); 
                     Alarms[alarmCount].time=GetTime(tf, i); 
                     Alarms[alarmCount].type=1; 
                     Alarms[alarmCount].barIndex=i; 
                     alarmCount++; 
                     break; 
                  } 
               } 
            } 
         } 
      } 
      if (IsRed(tf, i)) { 
         int c1=i-1;
         int c2=i-2; 
         if(IsGreen(tf, c1)){ 
            if(IsStrongBody(tf, c1)){ 
               bool confirm = false;
               if(IsGreen(tf, c2)) confirm = true; 
               else if(GetClose(tf, c2) > GetOpen(tf, i)) confirm = true;
               if(confirm) { 
                  ArrayResize(Alarms,alarmCount+1);
                  Alarms[alarmCount].price=GetLow(tf, i); 
                  Alarms[alarmCount].time=GetTime(tf, i); 
                  Alarms[alarmCount].type=-1; 
                  Alarms[alarmCount].barIndex=i; 
                  alarmCount++; 
               } 
            } else { 
               double rh=GetHigh(tf, c1);
               for(int k=1;k<=MaxScanDistance;k++){ 
                  int n=c1-k;
                  if(n<0||GetLow(tf, n)<GetLow(tf, i))break; 
                  if(IsGreen(tf, n)&&IsStrongBody(tf, n)&&GetClose(tf, n)>rh){ 
                     ArrayResize(Alarms,alarmCount+1);
                     Alarms[alarmCount].price=GetLow(tf, i); 
                     Alarms[alarmCount].time=GetTime(tf, i); 
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

   // --- THE RESOLVED FLAG ARRAY ---
   bool resolvedPoints[];
   int ptsCount = ArraySize(targetPoints);
   ArrayResize(resolvedPoints, ptsCount);
   for(int i=0; i<ptsCount; i++) resolvedPoints[i] = true; 

   // =========================================================
   // THE TOGGLE SWITCH: Strict SMC Logic
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

           if (targetPoints[i].type == -1) { // PENDING DEMAND (Floor)
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
                           isResolved = true; // ZONE HAS OFFICIALLY WON OR DIED!
                           
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
           else if (targetPoints[i].type == 1) { // PENDING SUPPLY (Ceiling)
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
                           isResolved = true; // ZONE HAS OFFICIALLY WON OR DIED!

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