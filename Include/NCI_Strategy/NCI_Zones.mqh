//+------------------------------------------------------------------+
//| NCI_Zones.mqh - Zone Logic & Painting                            |
//+------------------------------------------------------------------+
#property strict

// Includes
#include "NCI_Constants.mqh"
#include "NCI_Structs.mqh"
#include "NCI_Helpers.mqh"

// --- ZONE HELPERS ---
void StartZone(MergedZoneState &state, PointStruct &p) { 
   state.isActive=true; state.top=p.zoneLimitTop; state.bottom=p.zoneLimitBottom; state.startTime=p.time; state.lastBarIndex=p.barIndex; 
}

void MergeZone(MergedZoneState &state, PointStruct &p, int type) { 
   if (type == 1) { state.top = MathMax(state.top, p.price); state.bottom = p.zoneLimitBottom; } 
   else { state.bottom = MathMin(state.bottom, p.price); state.top = p.zoneLimitTop; } 
   state.startTime = p.time; state.lastBarIndex = p.barIndex; 
}

void DrawSingleZone(datetime t1, datetime t2, double top, double bottom, int type, int id) { 
   if (top <= bottom) return; 
   string name = "NCI_Zone_M_" + IntegerToString(id) + "_" + TimeToString(t1); 
   color c = (type == 1) ? SupplyColor : DemandColor; 
   if(ObjectFind(0,name)<0) { ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bottom); ObjectSetInteger(0, name, OBJPROP_COLOR, c); ObjectSetInteger(0, name, OBJPROP_FILL, true); ObjectSetInteger(0, name, OBJPROP_BACK, true); ObjectSetInteger(0, name, OBJPROP_WIDTH, 1); } 
}

void DrawFlippedZone(MergedZoneState &state, datetime endTime) {
   string name = "NCI_Flip_" + TimeToString(state.startTime);
   if(ObjectFind(0,name)<0) {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, state.startTime, state.top, endTime, state.bottom);
      ObjectSetInteger(0, name, OBJPROP_COLOR, FlippedColor); 
      ObjectSetInteger(0, name, OBJPROP_FILL, true); 
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   } else {
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, endTime);
   }
}

// --- LOGIC FUNCTIONS ---

// *** 1. FUTURE TARGET SCANNER (Wait for Pullback) ***
// We look FORWARD from the current index to find the NEXT zone that will form.
// If no future zone exists yet, this returns 0 (Keeping the Gray Zone in "Semi-Immortal" state).
double FindFutureTarget(int currentIndex, int targetType, double referencePrice)
{
   int totalPoints = ArraySize(ZigZagPoints);
   
   // Scan FORWARD into the future (i + 1)
   for(int k = currentIndex + 1; k < totalPoints; k++) 
   {
      if (ZigZagPoints[k].type == targetType) {
         
         if (targetType == 1) { 
            // BUYING: Looking for a FUTURE Supply Zone
            // It must be ABOVE our entry (Valid Profit Target)
            if (ZigZagPoints[k].zoneLimitBottom > referencePrice) {
               return ZigZagPoints[k].zoneLimitTop; // Return the Far Side (Ceiling)
            }
         }
         
         if (targetType == -1) { 
            // SELLING: Looking for a FUTURE Demand Zone
            // It must be BELOW our entry (Valid Profit Target)
            if (ZigZagPoints[k].zoneLimitTop < referencePrice) {
               return ZigZagPoints[k].zoneLimitBottom; // Return the Far Side (Floor)
            }
         }
      }
   }
   return 0; // No future target formed yet -> Phase 1 (Semi-Immortal)
}

// *** 2. CHECK LIFE (LIVING RANGE) ***
datetime CheckZoneLife(int startBar, int type, double targetLevel, double selfBreakLevel)
{
   for(int i = startBar - 1; i > 0; i--) 
   {
      // --- A. PROFIT SIDE (Only if a Future Target exists) ---
      // If targetLevel is 0 (Phase 1), this block is SKIPPED.
      // The Zone is IMMORTAL to profit moves during Phase 1.
      if (targetLevel != 0) {
          if (type == 1) { 
             // Buy Trade: Did we Break UP through the Future Supply Top?
             if (CheckForBreakout(i+1, i, targetLevel, 1)) return GetTime(i); 
          } 
          else { 
             // Sell Trade: Did we Break DOWN through the Future Demand Bottom?
             if (CheckForBreakout(i+1, i, targetLevel, -1)) return GetTime(i); 
          }
      }

      // --- B. LOSS SIDE (Always Active) ---
      // Even in Phase 1 (Semi-Immortal), the zone CAN die if it fails self-break.
      if (type == 1) { 
          // Buy Trade: Did we Break DOWN through Support?
          if (CheckForBreakout(i+1, i, selfBreakLevel, -1)) return GetTime(i); 
      } 
      else { 
          // Sell Trade: Did we Break UP through Resistance?
          if (CheckForBreakout(i+1, i, selfBreakLevel, 1)) return GetTime(i); 
      }
   }
   return 0; // Zone stays alive
}

void DrawParallelZones() { 
   ObjectsDeleteAll(0, "NCI_Zone_");
   ObjectsDeleteAll(0, "NCI_Flip_"); 
   
   activeFlippedSupply.isActive = false; 
   activeFlippedDemand.isActive = false; 
   
   int count = ArraySize(ZigZagPoints); 
   if (count == 0) return; 
   
   MergedZoneState supply; supply.isActive = false; 
   MergedZoneState demand; demand.isActive = false; 
   
   for (int i = 0; i < count; i++) { 
      PointStruct p = ZigZagPoints[i]; 
      
      if (p.type == 1) { // SUPPLY ZONE LOGIC
         if (!supply.isActive) StartZone(supply, p); 
         else { 
            bool isBroken = CheckForBreakout(supply.lastBarIndex, p.barIndex, supply.top, 1);
            if (p.price > supply.top) isBroken = true; 

            if (isBroken) { 
               datetime preciseBreakTime = FindBreakoutTime(supply.lastBarIndex, p.barIndex, supply.top, 1);
               if (preciseBreakTime == 0) preciseBreakTime = p.time; 

               DrawSingleZone(supply.startTime, preciseBreakTime, supply.top, supply.bottom, 1, i-1); 
               
               if (p.assignedTrend != 1) { 
                   MergedZoneState flip = supply;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   
                   // *** USE FUTURE TARGET SCANNER ***
                   // If no pullback yet, futureTarget = 0.
                   double futureTarget = FindFutureTarget(i, 1, supply.top); 
                   
                   datetime deathTime = CheckZoneLife(p.barIndex, 1, futureTarget, supply.bottom);
                   
                   if (deathTime == 0) {
                      activeFlippedDemand = flip;
                      activeFlippedDemand.endTime = 0; 
                      DrawFlippedZone(flip, TimeCurrent()+PeriodSeconds()*50); 
                   } else {
                      DrawFlippedZone(flip, deathTime); 
                   }
               }
               StartZone(supply, p); 
            } else { 
               // Standard Merge Logic
               bool shouldMerge = false; 
               if (p.zoneLimitTop > supply.top) shouldMerge = true; 
               else { 
                  bool isOverlapping = (MathMax(supply.bottom, p.zoneLimitBottom) <= MathMin(supply.top, p.zoneLimitTop)); 
                  if (isOverlapping) shouldMerge = true; 
               } 
               if (shouldMerge) { 
                  DrawSingleZone(supply.startTime, p.time, supply.top, supply.bottom, 1, i-1); 
                  MergeZone(supply, p, 1); 
               } else { 
                  DrawSingleZone(supply.startTime, p.time, supply.top, supply.bottom, 1, i-1); 
                  StartZone(supply, p); 
               } 
            } 
         } 
      } 
      else if (p.type == -1) { // DEMAND ZONE LOGIC
         if (!demand.isActive) StartZone(demand, p); 
         else { 
            bool isBroken = CheckForBreakout(demand.lastBarIndex, p.barIndex, demand.bottom, -1);
            if (p.price < demand.bottom) isBroken = true; 

            if (isBroken) { 
               datetime preciseBreakTime = FindBreakoutTime(demand.lastBarIndex, p.barIndex, demand.bottom, -1);
               if (preciseBreakTime == 0) preciseBreakTime = p.time; 

               DrawSingleZone(demand.startTime, preciseBreakTime, demand.top, demand.bottom, -1, i-1); 
               
               if (p.assignedTrend != -1) { 
                   MergedZoneState flip = demand;
                   flip.isActive = true;
                   flip.startTime = preciseBreakTime; 
                   
                   // *** USE FUTURE TARGET SCANNER ***
                   // If no pullback yet, futureTarget = 0.
                   double futureTarget = FindFutureTarget(i, -1, demand.bottom); 
                   
                   datetime deathTime = CheckZoneLife(p.barIndex, -1, futureTarget, demand.top);
                   
                   if (deathTime == 0) {
                      activeFlippedSupply = flip;
                      activeFlippedSupply.endTime = 0; 
                      DrawFlippedZone(flip, TimeCurrent()+PeriodSeconds()*50); 
                   } else {
                      DrawFlippedZone(flip, deathTime); 
                   }
               }
               StartZone(demand, p); 
            } else { 
               // Standard Merge Logic
               bool shouldMerge = false; 
               if (p.zoneLimitBottom < demand.bottom) shouldMerge = true; 
               else { 
                  bool isOverlapping = (MathMax(demand.bottom, p.zoneLimitBottom) <= MathMin(demand.top, p.zoneLimitTop)); 
                  if (isOverlapping) shouldMerge = true; 
               } 
               if (shouldMerge) { 
                  DrawSingleZone(demand.startTime, p.time, demand.top, demand.bottom, -1, i-1); 
                  MergeZone(demand, p, -1); 
               } else { 
                  DrawSingleZone(demand.startTime, p.time, demand.top, demand.bottom, -1, i-1); 
                  StartZone(demand, p); 
               } 
            } 
         } 
      } 
   } 
   
   if (supply.isActive) DrawSingleZone(supply.startTime, TimeCurrent()+PeriodSeconds()*50, supply.top, supply.bottom, 1, 999991); 
   if (demand.isActive) DrawSingleZone(demand.startTime, TimeCurrent()+PeriodSeconds()*50, demand.top, demand.bottom, -1, 999992); 
   
   activeSupply = supply; 
   activeDemand = demand; 
   
   if(DrawZones) ChartRedraw(); 
}