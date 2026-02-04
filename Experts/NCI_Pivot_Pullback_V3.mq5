//+------------------------------------------------------------------+
//|                            NCI_Pivot_Pullback_V6.0_Structural.mq5|
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "6.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND SETTINGS
input group "1. Trend Settings"
input int TrendEMA_Period = 200;

//--- 2. PIVOT SETTINGS
input group "2. Pivot Settings"
input bool Trade_S1 = true;
input bool Trade_S2 = true;

//--- 3. EXIT SETTINGS
input group "3. Exit Settings"
input bool UseDynamicTargets = true; // Aim for P or S1

//--- 4. RISK MANAGEMENT (STRUCTURAL)
input group "4. Structural Risk"
input double RiskPercent    = 1.0;   // Risk 1% of equity per trade
input double SafetyBuffer   = 100;   // Points (not pips) to place SL below the level (100 pts = 10 pips)
input double TakeProfitPips = 300;   // Backup TP only

//--- 5. VISUAL SETTINGS
input group "5. Visual Debugging"
input bool ShowLines = true;      
input color Color_P  = clrBlue;   
input color Color_S1 = clrRed;    
input color Color_S2 = clrDarkRed;

int TrendHandle;
CTrade trade;

// Global Variables
double P, S1, S2, S3; // Added S3 for safety below S2
datetime LastDay = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(555444);
   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   return (TrendHandle == INVALID_HANDLE) ? INIT_FAILED : INIT_SUCCEEDED;
}

void OnTick()
{
   ManageOpenPositions();
   CalculateDailyPivots();

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
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // STOP LOSS: Place below S2 (The Structural Basement)
      double structuralSL = S2 - (SafetyBuffer * _Point);
      
      // TAKE PROFIT: Target Pivot (P)
      double targetTP = UseDynamicTargets ? P : (entryPrice + TakeProfitPips * _Point);
      
      OpenDynamicTrade("S1 Buy -> SL below S2", entryPrice, structuralSL, targetTP);
   }
   else if (PositionsTotal() < 1 && IsUptrend && Trade_S2 && TouchedS2 && GreenCandle)
   {
      double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // STOP LOSS: Place below S3 (Deepest Structural Support)
      double structuralSL = S3 - (SafetyBuffer * _Point);
      
      // TAKE PROFIT: Target S1 (The previous floor)
      double targetTP = UseDynamicTargets ? S1 : (entryPrice + TakeProfitPips * _Point);
      
      OpenDynamicTrade("S2 Buy -> SL below S3", entryPrice, structuralSL, targetTP);
   }
}

//--- NEW: DYNAMIC RISK CALCULATOR
void OpenDynamicTrade(string comment, double entry, double sl, double tp)
{
   // 1. Calculate Distance to Stop Loss
   double sl_distance = entry - sl;
   
   // Safety check: Don't trade if SL is ABOVE entry (Error) or too close (Spread risk)
   if (sl_distance <= 0) return;

   // 2. Get Account Risk Money
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (RiskPercent / 100.0);
   
   // 3. Calculate Pip Value and Lot Size
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Formula: Lots = Money / (Points_Distance * Value_Per_Point)
   double lot_size = risk_money / ((sl_distance / tick_size) * tick_value);
   
   // 4. Normalize Lots to Broker Limits
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathFloor(lot_size / step) * step; // Round down to step
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));

   // 5. Execute
   trade.Buy(lot_size, _Symbol, entry, sl, tp, comment);
}

//--- CALCULATE PIVOTS (Added S3)
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
      S3 = low - 2 * (high - P); // Standard S3 Formula
      
      if (ShowLines)
      {
         datetime endOfDay = currentDay + 86400; 
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

void ManageOpenPositions()
{
   // Basic Trailing Logic Only
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetSymbol(i) == _Symbol)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double sl = PositionGetDouble(POSITION_SL);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         // Simple trailing logic to protect gains
         double new_sl = bid - (150 * _Point); // 15 pips trail
         if (new_sl > sl + (_Point * 10))
            trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
      }
   }
}

bool IsNewBar()
{
   static datetime last_time;
   datetime curr_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last_time == curr_time) return false;
   last_time = curr_time;
   return true;
}