//+------------------------------------------------------------------+
//|                                     NCI_Pivot_Pullback_V3.0.mq5  |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "3.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND SETTINGS
input group "1. Trend Settings"
input int TrendEMA_Period = 200;    // Filter: Only buy above this line

//--- 2. PIVOT SETTINGS (Automated Key Levels)
input group "2. Pivot Settings"
input bool Trade_S1 = true;         // Trade bounces off Support 1?
input bool Trade_S2 = true;         // Trade bounces off Support 2 (Deep)?

//--- 3. RISK MANAGEMENT
input group "3. Risk Management"
input double RiskPercent    = 1.0;
input double StopLossPips   = 100;  // Fixed SL (Or place below S2)
input double TakeProfitPips = 300;
input int BreakEvenPips     = 100;
input int TrailingPips      = 150;

int TrendHandle;
CTrade trade;

// Global Variables to store Daily Levels
double P, S1, S2, R1, R2;
datetime LastDay = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(555444); // New Magic Number

   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   
   return (TrendHandle == INVALID_HANDLE) ? INIT_FAILED : INIT_SUCCEEDED;
}

void OnTick()
{
   ManageOpenPositions();
   CalculateDailyPivots(); // Update levels if it's a new day

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

   // 1. TREND FILTER (Cornerstone)
   bool IsUptrend = (Close[1] > TrendMA[1]);

   // 2. LEVEL INTERACTION (Did we touch the line?)
   // We check if the LOW of the candle went below the line, 
   // but the CLOSE stayed above it (Rejecting the level).
   
   bool TouchedS1 = (Low[1] <= S1 && Close[1] > S1); // Wick went through S1
   bool TouchedS2 = (Low[1] <= S2 && Close[1] > S2); // Wick went through S2
   
   // 3. CONFIRMATION (Green Candle Bounce)
   bool GreenCandle = (Close[1] > Open[1]);

   //--- ENTRY EXECUTION
   // Scenario A: Bounce off S1
   if (PositionsTotal() < 1 && IsUptrend && Trade_S1 && TouchedS1 && GreenCandle)
   {
      OpenTrade("Pivot S1 Bounce");
   }
   
   // Scenario B: Bounce off S2 (Deep Discount)
   else if (PositionsTotal() < 1 && IsUptrend && Trade_S2 && TouchedS2 && GreenCandle)
   {
      OpenTrade("Pivot S2 Deep Bounce");
   }
}

//--- CALCULATE PIVOTS (The "Floor Trader" Math)
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
      
      // Standard Pivot Formulas
      P = (high + low + close) / 3.0;
      S1 = (2 * P) - high;
      S2 = P - (high - low);
      R1 = (2 * P) - low;
      
      Print("New Daily Levels -> P: ", P, " S1: ", S1, " S2: ", S2);
   }
}

void OpenTrade(string comment)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lot = CalculateLotSize(StopLossPips);
   trade.Buy(lot, _Symbol, ask, ask - (StopLossPips * _Point), ask + (TakeProfitPips * _Point), comment);
}

//--- STANDARD HELPER FUNCTIONS ----------------------------------
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