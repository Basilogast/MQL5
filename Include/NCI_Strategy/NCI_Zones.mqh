//+------------------------------------------------------------------+
//| NCI_Zones.mqh - Zone Logic & Painting                            |
//+------------------------------------------------------------------+
#property strict
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh"

void StartZone(MergedZoneState &state, PointStruct &p) { 
   state.isActive=true; 
   state.top=p.zoneLimitTop; state.bottom=p.zoneLimitBottom; state.startTime=p.time; state.lastBarIndex=p.barIndex;
}

void MergeZone(MergedZoneState &state, PointStruct &p, int type) { 
   if (type == 1) { state.top = MathMax(state.top, p.price);
   state.bottom = p.zoneLimitBottom; } 
   else { state.bottom = MathMin(state.bottom, p.price); state.top = p.zoneLimitTop;
   } 
   state.startTime = p.time; state.lastBarIndex = p.barIndex;
}

void DrawSingleZone(string suffix, datetime t1, datetime t2, double top, double bottom, int type, int id) { 
   if (top <= bottom) return;
   if (!Show_Zone_Boxes) return;
   if (MQLInfoInteger(MQL_OPTIMIZATION)) return;
   if (suffix == "_HTF" && !ShowHTF) return;
   if (suffix == "_LTF" && !ShowLTF) return;
   string name = "NCI_Zone_" + suffix + IntegerToString(id) + "_" + TimeToString(t1);
   color c;
   if (suffix == "_HTF") {
       c = (type == 1) ? clrIndianRed : clrMediumSeaGreen;
   } else {
       c = (type == 1) ? SupplyColor : DemandColor;
   }

   if(ObjectFind(0,name)<0) { 
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, (t2==0)?TimeCurrent():t2, bottom);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c); 
      ObjectSetInteger(0, name, OBJPROP_FILL, true); 
      ObjectSetInteger(0, name, OBJPROP_BACK, true); 
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   } else {
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, (t2==0)?TimeCurrent():t2);
   }
}

void DrawFlippedZone(string suffix, MergedZoneState &state, datetime endTime) {
   if (!Show_Zone_Boxes) return;
   if (MQLInfoInteger(MQL_OPTIMIZATION)) return;
   if (suffix == "_HTF" && !ShowHTF) return;
   if (suffix == "_LTF" && !ShowLTF) return;
   string name = "NCI_Flip_" + suffix + TimeToString(state.startTime);
   color c = FlippedColor;
   if (suffix == "_HTF") c = clrSilver;
   if(ObjectFind(0,name)<0) {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, state.startTime, state.top, endTime, state.bottom);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_FILL, true); 
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   } else {
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, endTime);
   }
}

double FindFutureTarget(PointStruct &points[], int currentIndex, int targetType, double referencePrice)
{
   int totalPoints = ArraySize(points);
   for(int k = currentIndex + 1; k < totalPoints; k++) 
   {
      if (points[k].type == targetType) {
         if (targetType == 1) { 
            if (points[k].zoneLimitBottom > referencePrice) return points[k].zoneLimitTop;
         }
         if (targetType == -1) { 
            if (points[k].zoneLimitTop < referencePrice) return points[k].zoneLimitBottom;
         }
      }
   }
   return 0;
}

datetime CheckZoneLife(ENUM_TIMEFRAMES tf, int startBar, int type, double targetLevel, double selfBreakLevel, bool isFlipped = false)
{
   for(int i = startBar - 1; i > 0; i--) 
   {
      // 1. Kiểm tra xem có chạm Target (Hoàn thành sứ mệnh) không
      if (targetLevel != 0) {
          if (type == 1) { if (CheckForBreakout(tf, i+1, i, targetLevel, 1)) return GetTime(tf, i);
          } 
          else { if (CheckForBreakout(tf, i+1, i, targetLevel, -1)) return GetTime(tf, i);
          }
      }
      
      // 2. [ĐÃ FIX BUG] Kiểm tra xem có bị giá đâm xuyên qua không (Áp dụng cho cả Zone thường lẫn Zone Xám)
      if (type == 1) { 
          if (CheckForBreakout(tf, i+1, i, selfBreakLevel, -1)) return GetTime(tf, i);
      } 
      else { 
          if (CheckForBreakout(tf, i+1, i, selfBreakLevel, 1)) return GetTime(tf, i);
      }
   }
   return 0;
}

void DrawFVGZone(string suffix, datetime t1, datetime t2, double top, double bottom, int type, int id) {
   if (!Show_FVG_Boxes) return;
   if (top <= bottom) return;
   if (MQLInfoInteger(MQL_OPTIMIZATION)) return;
   
   if (suffix == "_HTF" && !ShowHTF) return;
   if (suffix == "_LTF" && !ShowLTF) return;

   string name = "NCI_FVG_" + suffix + IntegerToString(id) + "_" + TimeToString(t1);
   color c = (type == 1) ? FVG_Bear_Color : FVG_Bull_Color;
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, (t2 == 0) ? TimeCurrent() : t2, bottom);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c); 
      ObjectSetInteger(0, name, OBJPROP_FILL, false); 
      ObjectSetInteger(0, name, OBJPROP_BACK, false); 
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   } else {
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, (t2 == 0) ? TimeCurrent() : t2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_FILL, false); 
      ObjectSetInteger(0, name, OBJPROP_BACK, false); 
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   }
}

void DrawParallelZones(ENUM_TIMEFRAMES tf, PointStruct &points[], MergedZoneState &activeSup, MergedZoneState &activeDem, MergedZoneState &activeFlipSup, MergedZoneState &activeFlipDem, string suffix) { 
   if (!MQLInfoInteger(MQL_OPTIMIZATION) && Show_Zone_Boxes) {
       ObjectsDeleteAll(0, "NCI_Zone_" + suffix);
       ObjectsDeleteAll(0, "NCI_Flip_" + suffix); 
       ObjectsDeleteAll(0, "NCI_FVG_" + suffix); 
   }
   
   activeFlipSup.isActive = false; 
   activeFlipDem.isActive = false;
   int count = ArraySize(points);
   if (count == 0) return; 
   
   MergedZoneState supply; supply.isActive = false; 
   MergedZoneState demand; demand.isActive = false;
   MergedZoneState fvgSupply; fvgSupply.isActive = false;
   MergedZoneState fvgDemand; fvgDemand.isActive = false;
   for (int i = 0; i < count; i++) { 
      PointStruct p = points[i];
      if (p.zoneLimitTop == 0 && p.zoneLimitBottom == 0) continue;

      if (p.type == 1) { // SUPPLY
         if (!supply.isActive) {
             StartZone(supply, p);
             if (p.hasFVG) { fvgSupply.isActive = true; fvgSupply.top = p.fvgTop; fvgSupply.bottom = p.fvgBottom; fvgSupply.startTime = p.time;
             } 
             else { fvgSupply.isActive = false;
             }
         }
         else { 
            datetime preciseBreakTime = FindBreakoutTime(tf, supply.lastBarIndex, p.barIndex, supply.top, 1);
            // --- [NEW] INDEPENDENT FVG DEATH SCANNER (HISTORICAL) ---
            if (fvgSupply.isActive) {
                // Bearish FVG dies if price breaks ABOVE its top (Stop Loss side)
                datetime fvgDeadTime = FindBreakoutTime(tf, supply.lastBarIndex, p.barIndex, fvgSupply.top, 1);
                if (fvgDeadTime > 0) {
                    DrawFVGZone(suffix, fvgSupply.startTime, fvgDeadTime, fvgSupply.top, fvgSupply.bottom, 1, i-1);
                    fvgSupply.isActive = false; // Kill it!
                }
            }

            if (preciseBreakTime > 0) { 
               DrawSingleZone(suffix, supply.startTime, preciseBreakTime, supply.top, supply.bottom, 1, i-1);
               if (fvgSupply.isActive) { DrawFVGZone(suffix, fvgSupply.startTime, preciseBreakTime, fvgSupply.top, fvgSupply.bottom, 1, i-1); fvgSupply.isActive = false;
               }
               
               if (Use_Strict_SMC_Zones || p.assignedTrend != 1) { 
                   if (activeFlipDem.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlipDem.endTime > 0 && activeFlipDem.endTime < preciseBreakTime) end = activeFlipDem.endTime;
                       DrawFlippedZone(suffix, activeFlipDem, end); 
                       activeFlipDem.isActive = false;
                   }
                   if (activeFlipSup.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlipSup.endTime > 0 && activeFlipSup.endTime < preciseBreakTime) end = activeFlipSup.endTime;
                       DrawFlippedZone(suffix, activeFlipSup, end); 
                       activeFlipSup.isActive = false;
                   }

                   MergedZoneState flip = supply;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   double futureTarget = FindFutureTarget(points, i, 1, supply.top);
                   datetime deathTime = CheckZoneLife(tf, p.barIndex, 1, futureTarget, supply.bottom, true);
                   
                   activeFlipDem = flip;
                   if (deathTime == 0) {
                      activeFlipDem.endTime = 0;
                      DrawFlippedZone(suffix, flip, TimeCurrent()+PeriodSeconds(tf)*50); 
                   } else {
                      activeFlipDem.endTime = deathTime;
                      DrawFlippedZone(suffix, flip, deathTime); 
                   }
               }
               StartZone(supply, p);
               if (p.hasFVG) { fvgSupply.isActive = true; fvgSupply.top = p.fvgTop; fvgSupply.bottom = p.fvgBottom; fvgSupply.startTime = p.time;
               } 
               else { fvgSupply.isActive = false;
               }
            } else { 
               bool shouldMerge = false;
               if (p.zoneLimitTop > supply.top) shouldMerge = true; 
               else { 
                  bool isOverlapping = (MathMax(supply.bottom, p.zoneLimitBottom) <= MathMin(supply.top, p.zoneLimitTop));
                  if (isOverlapping) shouldMerge = true; 
               } 
               if (shouldMerge) { 
                  DrawSingleZone(suffix, supply.startTime, p.time, supply.top, supply.bottom, 1, i-1);
                  if (fvgSupply.isActive) DrawFVGZone(suffix, fvgSupply.startTime, p.time, fvgSupply.top, fvgSupply.bottom, 1, i-1);
                  MergeZone(supply, p, 1); 
                  if (p.hasFVG) { fvgSupply.isActive = true;
                  fvgSupply.top = p.fvgTop; fvgSupply.bottom = p.fvgBottom; fvgSupply.startTime = p.time; }
               } else { 
                  DrawSingleZone(suffix, supply.startTime, p.time, supply.top, supply.bottom, 1, i-1);
                  if (fvgSupply.isActive) DrawFVGZone(suffix, fvgSupply.startTime, p.time, fvgSupply.top, fvgSupply.bottom, 1, i-1);
                  StartZone(supply, p); 
                  if (p.hasFVG) { fvgSupply.isActive = true; fvgSupply.top = p.fvgTop;
                  fvgSupply.bottom = p.fvgBottom; fvgSupply.startTime = p.time; } 
                  else { fvgSupply.isActive = false;
                  }
               } 
            } 
         } 
      } 
      else if (p.type == -1) { // DEMAND
         if (!demand.isActive) {
             StartZone(demand, p);
             if (p.hasFVG) { fvgDemand.isActive = true; fvgDemand.top = p.fvgTop; fvgDemand.bottom = p.fvgBottom; fvgDemand.startTime = p.time;
             } 
             else { fvgDemand.isActive = false;
             }
         }
         else { 
            datetime preciseBreakTime = FindBreakoutTime(tf, demand.lastBarIndex, p.barIndex, demand.bottom, -1);
            // --- [NEW] INDEPENDENT FVG DEATH SCANNER (HISTORICAL) ---
            if (fvgDemand.isActive) {
                // Bullish FVG dies if price breaks BELOW its bottom (Stop Loss side)
                datetime fvgDeadTime = FindBreakoutTime(tf, demand.lastBarIndex, p.barIndex, fvgDemand.bottom, -1);
                if (fvgDeadTime > 0) {
                    DrawFVGZone(suffix, fvgDemand.startTime, fvgDeadTime, fvgDemand.top, fvgDemand.bottom, -1, i-1);
                    fvgDemand.isActive = false; // Kill it!
                }
            }

            if (preciseBreakTime > 0) { 
               DrawSingleZone(suffix, demand.startTime, preciseBreakTime, demand.top, demand.bottom, -1, i-1);
               if (fvgDemand.isActive) { DrawFVGZone(suffix, fvgDemand.startTime, preciseBreakTime, fvgDemand.top, fvgDemand.bottom, -1, i-1); fvgDemand.isActive = false;
               }

               if (Use_Strict_SMC_Zones || p.assignedTrend != -1) { 
                   if (activeFlipDem.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlipDem.endTime > 0 && activeFlipDem.endTime < preciseBreakTime) end = activeFlipDem.endTime;
                       DrawFlippedZone(suffix, activeFlipDem, end); 
                       activeFlipDem.isActive = false;
                   }
                   if (activeFlipSup.isActive) {
                       datetime end = preciseBreakTime;
                       if (activeFlipSup.endTime > 0 && activeFlipSup.endTime < preciseBreakTime) end = activeFlipSup.endTime;
                       DrawFlippedZone(suffix, activeFlipSup, end); 
                       activeFlipSup.isActive = false;
                   }

                   MergedZoneState flip = demand;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   double futureTarget = FindFutureTarget(points, i, -1, demand.bottom);
                   datetime deathTime = CheckZoneLife(tf, p.barIndex, -1, futureTarget, demand.top, true);
                   
                   activeFlipSup = flip;
                   if (deathTime == 0) {
                      activeFlipSup.endTime = 0;
                      DrawFlippedZone(suffix, flip, TimeCurrent()+PeriodSeconds(tf)*50); 
                   } else {
                      activeFlipSup.endTime = deathTime;
                      DrawFlippedZone(suffix, flip, deathTime); 
                   }
               }
               StartZone(demand, p);
               if (p.hasFVG) { fvgDemand.isActive = true; fvgDemand.top = p.fvgTop; fvgDemand.bottom = p.fvgBottom; fvgDemand.startTime = p.time;
               } 
               else { fvgDemand.isActive = false;
               }
            } else { 
               bool shouldMerge = false;
               if (p.zoneLimitBottom < demand.bottom) shouldMerge = true; 
               else { 
                  bool isOverlapping = (MathMax(demand.bottom, p.zoneLimitBottom) <= MathMin(demand.top, p.zoneLimitTop));
                  if (isOverlapping) shouldMerge = true; 
               } 
               if (shouldMerge) { 
                  DrawSingleZone(suffix, demand.startTime, p.time, demand.top, demand.bottom, -1, i-1);
                  if (fvgDemand.isActive) DrawFVGZone(suffix, fvgDemand.startTime, p.time, fvgDemand.top, fvgDemand.bottom, -1, i-1);
                  MergeZone(demand, p, -1); 
                  if (p.hasFVG) { fvgDemand.isActive = true;
                  fvgDemand.top = p.fvgTop; fvgDemand.bottom = p.fvgBottom; fvgDemand.startTime = p.time; }
               } else { 
                  DrawSingleZone(suffix, demand.startTime, p.time, demand.top, demand.bottom, -1, i-1);
                  if (fvgDemand.isActive) DrawFVGZone(suffix, fvgDemand.startTime, p.time, fvgDemand.top, fvgDemand.bottom, -1, i-1);
                  StartZone(demand, p); 
                  if (p.hasFVG) { fvgDemand.isActive = true; fvgDemand.top = p.fvgTop;
                  fvgDemand.bottom = p.fvgBottom; fvgDemand.startTime = p.time; } 
                  else { fvgDemand.isActive = false;
                  }
               } 
            } 
         } 
      } 
   } 
   
   if (supply.isActive) {
      int startBar = iBarShift(_Symbol, tf, supply.startTime);
      // --- [NEW] INDEPENDENT FVG DEATH SCANNER (LIVE EDGE) ---
      if (fvgSupply.isActive) {
          datetime fvgDeadTime = FindBreakoutTime(tf, startBar, 0, fvgSupply.top, 1);
          if (fvgDeadTime > 0) {
              DrawFVGZone(suffix, fvgSupply.startTime, fvgDeadTime, fvgSupply.top, fvgSupply.bottom, 1, 999993);
              fvgSupply.isActive = false; // Kill it!
          }
      }

      datetime deadTime = FindBreakoutTime(tf, startBar, 0, supply.top, 1);
      if(deadTime > 0) {
         DrawSingleZone(suffix, supply.startTime, deadTime, supply.top, supply.bottom, 1, 999991);
         supply.isActive = false;
         if (fvgSupply.isActive) { DrawFVGZone(suffix, fvgSupply.startTime, deadTime, fvgSupply.top, fvgSupply.bottom, 1, 999991); fvgSupply.isActive = false;
         }
         
         if (activeFlipDem.isActive) {
             datetime end = deadTime;
             if (activeFlipDem.endTime > 0 && activeFlipDem.endTime < deadTime) end = activeFlipDem.endTime;
             DrawFlippedZone(suffix, activeFlipDem, end); 
             activeFlipDem.isActive = false;
         }
         if (activeFlipSup.isActive) {
             datetime end = deadTime;
             if (activeFlipSup.endTime > 0 && activeFlipSup.endTime < deadTime) end = activeFlipSup.endTime;
             DrawFlippedZone(suffix, activeFlipSup, end); 
             activeFlipSup.isActive = false;
         }

         MergedZoneState flip = supply;
         flip.isActive = true;
         flip.startTime = deadTime;
         int breakBar = iBarShift(_Symbol, tf, deadTime);
         double futureTarget = FindFutureTarget(points, count-1, 1, supply.top);
         datetime deathTime = CheckZoneLife(tf, breakBar, 1, futureTarget, supply.bottom, true);
         
         activeFlipDem = flip;
         if (deathTime == 0) {
             activeFlipDem.endTime = 0;
             DrawFlippedZone(suffix, flip, TimeCurrent()+PeriodSeconds(tf)*50); 
         } else {
             activeFlipDem.endTime = deathTime;
             DrawFlippedZone(suffix, flip, deathTime); 
         }
      }
   }
   
   if (demand.isActive) {
      int startBar = iBarShift(_Symbol, tf, demand.startTime);
      // --- [NEW] INDEPENDENT FVG DEATH SCANNER (LIVE EDGE) ---
      if (fvgDemand.isActive) {
          datetime fvgDeadTime = FindBreakoutTime(tf, startBar, 0, fvgDemand.bottom, -1);
          if (fvgDeadTime > 0) {
              DrawFVGZone(suffix, fvgDemand.startTime, fvgDeadTime, fvgDemand.top, fvgDemand.bottom, -1, 999994);
              fvgDemand.isActive = false; // Kill it!
          }
      }

      datetime deadTime = FindBreakoutTime(tf, startBar, 0, demand.bottom, -1);
      if(deadTime > 0) {
         DrawSingleZone(suffix, demand.startTime, deadTime, demand.top, demand.bottom, -1, 999992);
         demand.isActive = false;
         if (fvgDemand.isActive) { DrawFVGZone(suffix, fvgDemand.startTime, deadTime, fvgDemand.top, fvgDemand.bottom, -1, 999992); fvgDemand.isActive = false;
         }
         
         if (activeFlipDem.isActive) {
             datetime end = deadTime;
             if (activeFlipDem.endTime > 0 && activeFlipDem.endTime < deadTime) end = activeFlipDem.endTime;
             DrawFlippedZone(suffix, activeFlipDem, end); 
             activeFlipDem.isActive = false;
         }
         if (activeFlipSup.isActive) {
             datetime end = deadTime;
             if (activeFlipSup.endTime > 0 && activeFlipSup.endTime < deadTime) end = activeFlipSup.endTime;
             DrawFlippedZone(suffix, activeFlipSup, end); 
             activeFlipSup.isActive = false;
         }

         MergedZoneState flip = demand;
         flip.isActive = true;
         flip.startTime = deadTime;
         int breakBar = iBarShift(_Symbol, tf, deadTime);
         double futureTarget = FindFutureTarget(points, count-1, -1, demand.bottom);
         datetime deathTime = CheckZoneLife(tf, breakBar, -1, futureTarget, demand.top, true);
         
         activeFlipSup = flip;
         if (deathTime == 0) {
             activeFlipSup.endTime = 0;
             DrawFlippedZone(suffix, flip, TimeCurrent()+PeriodSeconds(tf)*50); 
         } else {
             activeFlipSup.endTime = deathTime;
             DrawFlippedZone(suffix, flip, deathTime); 
         }
      }
   }
   
   if (supply.isActive) DrawSingleZone(suffix, supply.startTime, TimeCurrent()+PeriodSeconds(tf)*50, supply.top, supply.bottom, 1, 999991);
   if (demand.isActive) DrawSingleZone(suffix, demand.startTime, TimeCurrent()+PeriodSeconds(tf)*50, demand.top, demand.bottom, -1, 999992); 
   
   if (fvgSupply.isActive) DrawFVGZone(suffix, fvgSupply.startTime, TimeCurrent()+PeriodSeconds(tf)*50, fvgSupply.top, fvgSupply.bottom, 1, 999993);
   if (fvgDemand.isActive) DrawFVGZone(suffix, fvgDemand.startTime, TimeCurrent()+PeriodSeconds(tf)*50, fvgDemand.top, fvgDemand.bottom, -1, 999994);

   // --- DATA BRIDGE FIX: FORCE SYNC TO GLOBAL VARIABLES ---
   if (suffix == "_HTF") {
       activeFVGSupply_HTF = fvgSupply;
       activeFVGDemand_HTF = fvgDemand;
       activeFlippedSupply_HTF = activeFlipSup; 
       activeFlippedDemand_HTF = activeFlipDem; 
   } else if (suffix == "_LTF") {
       activeFVGSupply_LTF = fvgSupply;
       activeFVGDemand_LTF = fvgDemand;
       activeFlippedSupply_LTF = activeFlipSup; 
       activeFlippedDemand_LTF = activeFlipDem; 
   }
   
   activeSup = supply; 
   activeDem = demand;
   if(!MQLInfoInteger(MQL_OPTIMIZATION) && Show_Zone_Boxes) ChartRedraw(); 
}