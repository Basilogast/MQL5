//+------------------------------------------------------------------+
//|                                     NCI_Deep_Pullback_V2.1.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "2.10"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND (The Cornerstone)
input group "1. Trend Settings"
input int TrendEMA_Period = 200;    // Long-term direction. We only buy above this.

//--- 2. DEEP PULLBACK (The Trigger)
input group "2. Deep Value Trigger (RSI)"
input int RSI_Period      = 14;     
input int RSI_Oversold    = 45;     // ADJUSTED: 45 is the "Bull Market Support".
                                    // 30 is too strict for strong uptrends.

//--- 3. CONFIRMATION
input group "3. Confirmation"
input bool RequireGreenCandle = true; // Must close higher than open to confirm bounce.

//--- 4. RISK MANAGEMENT
input group "4. Risk Management"
input double RiskPercent    = 2.0;  
input double StopLossPips   = 100;  
input double TakeProfitPips = 300;  
input int BreakEvenPips     = 100;
input int TrailingPips      = 150;

int TrendHandle, RSIHandle;
CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(777666); 

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
   // Price must be above the 200 EMA (Bull Market).
   bool IsUptrend = (Close[1] > TrendMA[1]);

   // 2. VALUE TRIGGER (RSI Cross)
   // Condition A: RSI dipped into the "Value Zone" (Below 45) recently.
   // We look back 1 or 2 candles to catch the bottom of the "V".
   bool WasOversold = (RSI[1] < RSI_Oversold) || (RSI[2] < RSI_Oversold);
   
   // Condition B: RSI is now recovering (Turning Up).
   bool RSIRising = (RSI[0] > RSI[1]);

   // 3. CANDLE CONFIRMATION
   bool GreenCandle = (Close[1] > Open[1]);

   //--- ENTRY EXECUTION
   // We buy if Uptrend + Dip to 45 + RSI turning up + Green Candle
   if (PositionsTotal() < 1 && IsUptrend && WasOversold && RSIRising && GreenCandle)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lot = CalculateLotSize(StopLossPips);
      
      trade.Buy(lot, _Symbol, ask, ask - (StopLossPips * _Point), ask + (TakeProfitPips * _Point), "NCI Bull Dip V2.1");
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