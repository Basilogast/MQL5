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

      // 1. CHECK THE MEMORY CACHE
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

      // 2. UPDATE THE PRIVATE NOTEBOOK WITH NEW BOSSES & INTERNAL STRUCTURE
      if (prev.type == 1) { 
          internalHigh = prev.price;
          // Only true validated Bosses have a zoneLimitTop > 0
          if (prev.zoneLimitTop > 0) activeBossSupply = prev.zoneLimitTop; 
      } 
      if (prev.type == -1) { 
          internalLow = prev.price;
          // Only true validated Bosses have a zoneLimitBottom > 0
          if (prev.zoneLimitBottom > 0) activeBossDemand = prev.zoneLimitBottom; 
      } 
      
      // 3. SCAN FOR BREAKOUTS IN THE CURRENT LEG
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

      // 4. THE SMC STATE MACHINE (NINJA IMMUNE & DOMINO SAFE)
      bool stateChanged = false; // THE STOP SIGN FLAG

      if (runningTrend == 1) { 
          if (brokeDemandBoss) {
              runningTrend = 0; // Trend is Dead (Limbo) -> YELLOW
              activeBossDemand = 0; // Erase the shattered Boss from notebook
              stateChanged = true; // Raise the Stop Sign!
          }
      } 
      else if (runningTrend == -1) { 
          if (brokeSupplyBoss) {
              runningTrend = 0; // Trend is Dead (Limbo) -> YELLOW
              activeBossSupply = 0; // Erase the shattered Boss from notebook
              stateChanged = true; // Raise the Stop Sign!
          }
      } 
      else { // runningTrend == 0
          if (brokeInternalHigh) { 
              runningTrend = 1; // New Uptrend confirmed! -> GREEN
              activeBossDemand = 0; // Clear opposing memory
              stateChanged = true; // Raise the Stop Sign!
          } 
          else if (brokeInternalLow) { 
              runningTrend = -1; // New Downtrend confirmed! -> RED
              activeBossSupply = 0; // Clear opposing memory
              stateChanged = true; // Raise the Stop Sign!
          } 
      } 
      
      // 5. Fallback for massive single-leg direct reversals
      // --- THE FIX: ONLY RUN FALLBACK IF THE STOP SIGN IS NOT RAISED ---
      if (!stateChanged && runningTrend == 0) {
          if (brokeSupplyBoss) { runningTrend = 1; activeBossDemand = 0; }
          else if (brokeDemandBoss) { runningTrend = -1; activeBossSupply = 0; }
      }

      points[i].assignedTrend = runningTrend; 

      // 6. SAVE TO MEMORY CACHE
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