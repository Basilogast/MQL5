//+------------------------------------------------------------------+
//|                          NCI_Pivot_Pro_Swing_V7.0.mq5            |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "7.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND SETTINGS
input group "1. Trend Settings"
input int TrendEMA_Period = 200;

//--- 2. PIVOT SETTINGS
input group "2. Pivot Settings"
input bool Trade_S1 = true;
input bool Trade_S2 = true;

//--- 3. EXIT SETTINGS (PRO SWING)
input group "3. Exit Settings"
input bool UseStructuralTarget = true; // True = Aim for R1 (if bought at S1) or P (if bought at S2)
input double HardFloorBuffer   = 50;   // Points below Pivot to place the "Step Up" SL (5 pips)

//--- 4. RISK MANAGEMENT
input group "4. Structural Risk"
input double RiskPercent    = 1.0;   
input double SafetyBuffer   = 100;   // SL Buffer below S2/S3
input double BackupTP_Pips  = 300;   

//--- 5. VISUAL SETTINGS
input bool ShowLines = true;      
input color Color_R1 = clrGreen;  // Added R1 Color
input color Color_P  = clrBlue;   
input color Color_S1 = clrRed;    
input color Color_S2 = clrDarkRed;

int TrendHandle;
CTrade trade;

// Global Variables
double R1, P, S1, S2, S3; 
datetime LastDay = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(555444);
   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   return (TrendHandle == INVALID_HANDLE) ? INIT_FAILED : INIT_SUCCEEDED;
}

void OnTick()
{
   CalculateDailyPivots();
   ManageOpenPositions(); // New Smart Logic Inside

   if (!IsNewBar()) return;

   //--- Define Arrays
   double TrendMA[], Close[], Open[], Low[];
   ArraySetAsSeries(TrendMA, true); 
   ArraySetAsSeries(Close, true);  
   ArraySetAsSeries(Open, true);
   ArraySetAsSeries(Low, true);

   if (CopyBuffer(TrendHandle, 0, 0, 3, TrendMA) < 3 ||
       CopyClose(_Symbol, _Period, 0, 3, Close) < 3 ||
       CopyOpen(_Symbol, _Period, 0, 3, Open) < 3 ||
       CopyLow(_Symbol, _Period, 0, 3, Low) < 3)
      return;

   //--- STRATEGY LOGIC -------------------------------------------
   bool IsUptrend = (Close[1] > TrendMA[1]);
   bool TouchedS1 = (Low[1] <= S1 && Close[1] > S1); 
   bool TouchedS2 = (Low[1] <= S2 && Close[1] > S2); 
   bool GreenCandle = (Close[1] > Open[1]);

   //--- ENTRY EXECUTION
   if (PositionsTotal() < 1 && IsUptrend && Trade_S1 && TouchedS1 && GreenCandle)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = S2 - (SafetyBuffer * _Point); // Risk: Below S2
      
      // TARGET: Aim for R1 (The Extension)
      double tp = UseStructuralTarget ? R1 : (entry + BackupTP_Pips * _Point);
      
      OpenDynamicTrade("S1 Buy -> Target R1", entry, sl, tp);
   }
   else if (PositionsTotal() < 1 && IsUptrend && Trade_S2 && TouchedS2 && GreenCandle)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = S3 - (SafetyBuffer * _Point); // Risk: Below S3
      
      // TARGET: Aim for P (The Recovery)
      double tp = UseStructuralTarget ? P : (entry + BackupTP_Pips * _Point);
      
      OpenDynamicTrade("S2 Buy -> Target P", entry, sl, tp);
   }
}

//--- SMART MANAGEMENT (The "Step Up" Logic)
void ManageOpenPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetSymbol(i) == _Symbol)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double sl = PositionGetDouble(POSITION_SL);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         string comment = PositionGetString(POSITION_COMMENT);

         // LOGIC: If we bought at S1, we are watching P (The Pivot)
         if (StringFind(comment, "S1 Buy") >= 0)
         {
            // Condition: Price has conquered P
            if (bid > P)
            {
               double new_floor = P - (HardFloorBuffer * _Point); // 5 pips below P
               
               // Only move UP, and only if we haven't already moved it there
               if (new_floor > sl + (_Point * 10))
               {
                  trade.PositionModify(ticket, new_floor, PositionGetDouble(POSITION_TP));
                  Print("Step Up! Price crossed Pivot. SL moved to P - Buffer.");
               }
            }
         }
         // Note: We do NOT use a pip-trailing stop here. We trust the wall.
      }
   }
}

//--- CALCULATE PIVOTS (Added R1)
void CalculateDailyPivots()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if (LastDay != currentDay)
   {
      LastDay = currentDay;
      double high = iHigh(_Symbol, PERIOD_D1, 1);
      double low  = iLow(_Symbol, PERIOD_D1, 1);
      double close= iClose(_Symbol, PERIOD_D1, 1);
      
      P = (high + low + close) / 3.0;
      S1 = (2 * P) - high;
      S2 = P - (high - low);
      S3 = low - 2 * (high - P); 
      R1 = (2 * P) - low; // Target for S1 Buys
      
      if (ShowLines)
      {
         datetime endOfDay = currentDay + 86400; 
         DrawSegment("R1_" + TimeToString(currentDay), currentDay, endOfDay, R1, Color_R1, STYLE_SOLID);
         DrawSegment("P_" + TimeToString(currentDay), currentDay, endOfDay, P, Color_P, STYLE_SOLID);
         DrawSegment("S1_" + TimeToString(currentDay), currentDay, endOfDay, S1, Color_S1, STYLE_SOLID);
         DrawSegment("S2_" + TimeToString(currentDay), currentDay, endOfDay, S2, Color_S2, STYLE_DASH);
      }
   }
}

void DrawSegment(string name, datetime t1, datetime t2, double price, color col, ENUM_LINE_STYLE style)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); 
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void OpenDynamicTrade(string comment, double entry, double sl, double tp)
{
   double sl_distance = entry - sl;
   if (sl_distance <= 0) return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (RiskPercent / 100.0);
   
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot_size = risk_money / ((sl_distance / tick_size) * tick_value);
   
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathFloor(lot_size / step) * step;
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));

   trade.Buy(lot_size, _Symbol, entry, sl, tp, comment);
}

bool IsNewBar()
{
   static datetime last_time;
   datetime curr_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last_time == curr_time) return false;
   last_time = curr_time;
   return true;
}