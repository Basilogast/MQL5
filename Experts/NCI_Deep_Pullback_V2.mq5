//+------------------------------------------------------------------+
//|                                     NCI_Deep_Pullback_V2.0.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND (The Cornerstone)
input group "1. Trend Settings"
input int TrendEMA_Period = 200;    // Long-term direction. We only buy above this.

//--- 2. DEEP PULLBACK (The Trigger)
input group "2. Deep Value Trigger (RSI)"
input int RSI_Period      = 14;     
input int RSI_Oversold    = 30;     // The "Key Level" proxy. 
                                    // We wait for RSI to drop below this (Deep discount).

//--- 3. CONFIRMATION
input group "3. Confirmation"
input bool RequireGreenCandle = true; // Must close higher than open to confirm bounce.

//--- 4. RISK MANAGEMENT
input group "4. Risk Management"
input double RiskPercent    = 2.0;  // Higher risk allowed because win rate is higher on deep dips.
input double StopLossPips   = 100;  // Tighter SL (since we are at the bottom)
input double TakeProfitPips = 300;  // 1:3 Ratio
input int BreakEvenPips     = 100;
input int TrailingPips      = 150;

int TrendHandle, RSIHandle;
CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(777666); // New Magic Number

   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   RSIHandle   = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);

   return (TrendHandle == INVALID_HANDLE || RSIHandle == INVALID_HANDLE) 
           ? INIT_FAILED : INIT_SUCCEEDED;
}

void OnTick()
{
   ManageOpenPositions();
   if (!IsNewBar()) return;

   //--- Define Arrays
   double TrendMA[], RSI[], Close[], Open[];
   ArraySetAsSeries(TrendMA, true); 
   ArraySetAsSeries(RSI, true);
   ArraySetAsSeries(Close, true);  
   ArraySetAsSeries(Open, true);

   //--- Copy Data
   if (CopyBuffer(TrendHandle, 0, 0, 3, TrendMA) < 3 ||
       CopyBuffer(RSIHandle, 0, 0, 3, RSI) < 3 ||
       CopyClose(_Symbol, _Period, 0, 3, Close) < 3 ||
       CopyOpen(_Symbol, _Period, 0, 3, Open) < 3)
      return;

   //--- STRATEGY LOGIC -------------------------------------------

   // 1. TREND FILTER
   // Price must be above the 200 EMA. 
   // We don't want to buy a "deep dip" that is actually a market crash.
   bool IsUptrend = (Close[1] > TrendMA[1]);

   // 2. DEEP VALUE TRIGGER (RSI Cross)
   // Condition A: RSI was below 30 recently (at candle 1 or 2).
   bool WasOversold = (RSI[1] < RSI_Oversold) || (RSI[2] < RSI_Oversold);
   
   // Condition B: RSI is now pointing UP (Recovering).
   bool RSIRising = (RSI[0] > RSI[1]);

   // Condition C: RSI is back above the danger zone (optional safety).
   // bool SafeRSI = (RSI[1] > RSI_Oversold); 

   // 3. CANDLE CONFIRMATION
   bool GreenCandle = (Close[1] > Open[1]);

   //--- ENTRY EXECUTION
   // We buy if Uptrend + Was Oversold + RSI is turning up + Green Candle
   if (PositionsTotal() < 1 && IsUptrend && WasOversold && RSIRising && GreenCandle)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lot = CalculateLotSize(StopLossPips);
      
      trade.Buy(lot, _Symbol, ask, ask - (StopLossPips * _Point), ask + (TakeProfitPips * _Point), "NCI Deep Value V2.0");
   }
}

//--- HELPER FUNCTIONS -------------------------------------------
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