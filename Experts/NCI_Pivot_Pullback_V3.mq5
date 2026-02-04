//+------------------------------------------------------------------+
//|                            NCI_Pivot_Pullback_V3.2_History.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "3.20"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND SETTINGS
input group "1. Trend Settings"
input int TrendEMA_Period = 200;

//--- 2. PIVOT SETTINGS
input group "2. Pivot Settings"
input bool Trade_S1 = true;
input bool Trade_S2 = true;

//--- 3. VISUAL SETTINGS
input group "3. Visual Debugging"
input bool ShowLines = true;      
input color Color_P  = clrBlue;   
input color Color_S1 = clrRed;    
input color Color_S2 = clrDarkRed;

//--- 4. RISK MANAGEMENT
input group "4. Risk Management"
input double RiskPercent    = 1.0;
input double StopLossPips   = 100;
input double TakeProfitPips = 300;
input int BreakEvenPips     = 100;
input int TrailingPips      = 150;

int TrendHandle;
CTrade trade;

// Global Variables
double P, S1, S2;
datetime LastDay = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(555444);
   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   return (TrendHandle == INVALID_HANDLE) ? INIT_FAILED : INIT_SUCCEEDED;
}

// NOTE: We REMOVED OnDeinit() so lines stay on the chart!

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
      OpenTrade("Pivot S1 Bounce");
   }
   else if (PositionsTotal() < 1 && IsUptrend && Trade_S2 && TouchedS2 && GreenCandle)
   {
      OpenTrade("Pivot S2 Deep Bounce");
   }
}

//--- CALCULATE & DRAW PIVOTS (HISTORY MODE)
void CalculateDailyPivots()
{
   datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
   if (LastDay != currentDay)
   {
      LastDay = currentDay;
      
      // Get Yesterday's Data
      double high = iHigh(_Symbol, PERIOD_D1, 1);
      double low  = iLow(_Symbol, PERIOD_D1, 1);
      double close= iClose(_Symbol, PERIOD_D1, 1);
      
      // Calculate
      P = (high + low + close) / 3.0;
      S1 = (2 * P) - high;
      S2 = P - (high - low);
      
      // DRAW PERMANENT HISTORY LINES
      if (ShowLines)
      {
         // Calculate End of Day time (start + 24 hours)
         datetime endOfDay = currentDay + 86400; 
         
         // Draw unique segments for this specific day
         DrawSegment("P_" + TimeToString(currentDay), currentDay, endOfDay, P, Color_P, STYLE_SOLID);
         DrawSegment("S1_" + TimeToString(currentDay), currentDay, endOfDay, S1, Color_S1, STYLE_SOLID);
         DrawSegment("S2_" + TimeToString(currentDay), currentDay, endOfDay, S2, Color_S2, STYLE_DASH);
      }
   }
}

//--- HELPER: DRAW SEGMENT (Start to End Time)
void DrawSegment(string name, datetime t1, datetime t2, double price, color col, ENUM_LINE_STYLE style)
{
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); // Do not extend to infinity
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void OpenTrade(string comment)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lot = CalculateLotSize(StopLossPips);
   trade.Buy(lot, _Symbol, ask, ask - (StopLossPips * _Point), ask + (TakeProfitPips * _Point), comment);
}

double CalculateLotSize(double sl_pips)
{
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amt   = balance * (RiskPercent / 100.0);
   double lot        = risk_amt / (sl_pips * 10 * tick_value);
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return NormalizeDouble(MathMax(min, MathMin(max, lot)), 2);
}

void ManageOpenPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetSymbol(i) == _Symbol)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double sl = PositionGetDouble(POSITION_SL);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         if (sl < open_price && bid >= open_price + (BreakEvenPips * _Point))
            trade.PositionModify(ticket, open_price + (10 * _Point), PositionGetDouble(POSITION_TP));

         double new_sl = bid - (TrailingPips * _Point);
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