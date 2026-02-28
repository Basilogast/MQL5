//+------------------------------------------------------------------+
//| NCI_ZigZag.mqh - Structure & Trend Engine                        |
//+------------------------------------------------------------------+
#property strict
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh"

// [Keep CalculateTrendsAndLock ... unchanged]
void CalculateTrendsAndLock(ENUM_TIMEFRAMES tf, PointStruct &points[], int &marketTrend) { 
   int count = ArraySize(points);
   if (count < 2) return; 
   int runningTrend = 0; 
   double lastSupplyLevel = 0; int lastSupplyIdx = -1;
   double lastDemandLevel = 0; int lastDemandIdx = -1; 
   double prevHigh = 0; double prevLow = 0;
   for (int i = 1; i < count; i++) { 
      PointStruct p = points[i];
      PointStruct prev = points[i-1]; 
      if (prev.type == 1) { lastSupplyLevel = prev.zoneLimitTop; lastSupplyIdx = prev.barIndex; prevHigh = prev.price;
      } 
      if (prev.type == -1) { lastDemandLevel = prev.zoneLimitBottom; lastDemandIdx = prev.barIndex;
      prevLow = prev.price; } 
      
      bool brokenSupply = false;
      bool brokenDemand = false; 
      
      if (lastSupplyIdx != -1) {
         brokenSupply = CheckForBreakout(tf, lastSupplyIdx, p.barIndex, lastSupplyLevel, 1);
      }
      
      if (lastDemandIdx != -1) {
         brokenDemand = CheckForBreakout(tf, lastDemandIdx, p.barIndex, lastDemandLevel, -1);
      }

      if (runningTrend == -1) { if (brokenSupply) runningTrend = 0;
      } 
      else if (runningTrend == 1) { if (brokenDemand) runningTrend = 0;
      } 
      else { 
         if (p.type == 1) { if (brokenSupply || (prevHigh != 0 && p.price > prevHigh)) { if (!brokenDemand) runningTrend = 1;
         } } 
         if (p.type == -1) { if (brokenDemand || (prevLow != 0 && p.price < prevLow)) { if (!brokenSupply) runningTrend = -1;
         } } 
         if (brokenSupply && p.type == 1 && prevHigh != 0 && p.price > prevHigh) runningTrend = 1;
         if (brokenDemand && p.type == -1 && prevLow != 0 && p.price < prevLow) runningTrend = -1;
      } 
      points[i].assignedTrend = runningTrend; 
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

// *** VISUAL UPDATE: Global Toggle + Dashboard Logic Preserved ***
void DrawZigZagLines(string suffix, PointStruct &points[]) { 
   // 1. GLOBAL SPEED TOGGLE (New)
   if (!Show_ZigZag_Lines) return;
   // 2. SPEED FIX: Stop here if optimizing
   if (MQLInfoInteger(MQL_OPTIMIZATION)) return;
   // 3. Clear old objects regardless of dashboard state (Good practice)
   ObjectsDeleteAll(0, "NCI_ZZ_" + suffix);
   // 4. DASHBOARD CHECK (Preserved)
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
   CalculateTrendsAndLock(tf, targetPoints, targetTrend); 

   // --- THE MEMORY CACHE (Declared outside for scope safety) ---
   static datetime cacheTime_HTF[]; static int cacheStatus_HTF[];
   static datetime cacheTime_LTF[]; static int cacheStatus_LTF[];

   // =========================================================
   // THE TOGGLE SWITCH: Strict SMC Logic
   // =========================================================
   if (Use_Strict_SMC_Zones) {

       // --- SWING VS INTERNAL STRUCTURE SEPARATOR ---
       double activeMacroSupply = 0;  // The Boss Ceiling
       double activeMacroDemand = 0;  // The Boss Floor
       double extremeHigh = 0;        // Extreme High of internal structure
       double extremeLow = 999999;    // Extreme Low of internal structure

       for (int i = 0; i < ArraySize(targetPoints); i++) {
           if (i == 0) {
               if (targetPoints[i].type == 1) {
                   activeMacroSupply = targetPoints[i].price;
                   extremeHigh = targetPoints[i].price;
               } else {
                   activeMacroDemand = targetPoints[i].price;
                   extremeLow = targetPoints[i].price;
               }
               continue;
           }

           bool isValidated = false;
           bool isResolved = false;
           
           // 1. CHECK THE MEMORY CACHE
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

                       // Lock it in Memory Cache
                       if (t_break > 0 || t_fail > 0) {
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

                       // Lock it in Memory Cache
                       if (t_break > 0 || t_fail > 0) {
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
           }
       }
   }
   // =========================================================
   // END OF TOGGLE SWITCH
   // =========================================================

   DrawZigZagLines(suffix, targetPoints);
}