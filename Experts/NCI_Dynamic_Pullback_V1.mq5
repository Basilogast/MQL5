//+------------------------------------------------------------------+
//|                                     NCI_Dynamic_Pullback_V1.mq5  |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND (The Big Picture)
input group "1. Trend Settings (NCI Cornerstone)"
input int TrendEMA_Period = 200;    // Long-term direction filter

//--- 2. ZONE (The Value Area)
input group "2. Zone Settings (Dynamic Support)"
input int ZoneFastEMA     = 20;     // Top of the Buy Zone
input int ZoneSlowEMA     = 50;     // Bottom of the Buy Zone (Crash Guard)

//--- 3. MOMENTUM & CONFIRMATION
input group "3. Confirmation Triggers"
input bool RequireGreenCandle = true; // Confirmation: Close > Open
input double MinTrendSlope    = 0.00010; // Momentum: 200 EMA must be rising

//--- 4. RISK MANAGEMENT
input group "4. Risk Management"
input double RiskPercent    = 1.0;
input double StopLossPips   = 150;  // Tight stop below the zone
input double TakeProfitPips = 450;  // 1:3 Risk/Reward Ratio
input int TrailingPips      = 200;
input int BreakEvenPips     = 150;

int FastHandle, SlowHandle, TrendHandle;
CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(888999);

   // Initialize Indicators
   FastHandle  = iMA(_Symbol, _Period, ZoneFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   SlowHandle  = iMA(_Symbol, _Period, ZoneSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE || TrendHandle == INVALID_HANDLE)
      return INIT_FAILED;
      
   return INIT_SUCCEEDED;
}

void OnTick()
{
   ManageOpenPositions();
   if (!IsNewBar()) return;

   //--- Define Arrays
   double FastMA[], SlowMA[], TrendMA[], Close[], Open[], Low[];
   ArraySetAsSeries(FastMA, true); 
   ArraySetAsSeries(SlowMA, true); 
   ArraySetAsSeries(TrendMA, true);
   ArraySetAsSeries(Close, true);  
   ArraySetAsSeries(Open, true);
   ArraySetAsSeries(Low, true);

   //--- Copy Data
   if (CopyBuffer(FastHandle, 0, 0, 20, FastMA) < 20 ||
       CopyBuffer(SlowHandle, 0, 0, 20, SlowMA) < 20 ||
       CopyBuffer(TrendHandle, 0, 0, 20, TrendMA) < 20 ||
       CopyClose(_Symbol, _Period, 0, 3, Close) < 3 ||
       CopyOpen(_Symbol, _Period, 0, 3, Open) < 3 ||
       CopyLow(_Symbol, _Period, 0, 3, Low) < 3)
      return;

   //--- STRATEGY LOGIC (NCI FLOW) --------------------------------

   // STEP 1: TREND
   // Is the 200 EMA rising? (Momentum check)
   double Slope = TrendMA[1] - TrendMA[10];
   bool IsUptrend = (Slope > MinTrendSlope) && (Close[1] > TrendMA[1]);

   // STEP 2: ZONE (Pullback)
   // Did Price dip into our "Value Zone" (below 20 EMA) recently?
   // We check the Low of the previous candle.
   bool DipIntoZone = (Low[1] < FastMA[1]);
   
   // Safety: Price must still be above the 50 EMA (Crash Guard)
   bool ZoneHold = (Close[1] > SlowMA[1]);

   // STEP 3: CONFIRMATION (The Trigger)
   // Did Price close back ABOVE the 20 EMA?
   bool BreakBackUp = (Close[1] > FastMA[1]);
   
   // Is it a Green Candle? (Buyers are in control)
   bool BullishCandle = (Close[1] > Open[1]);

   //--- ENTRY EXECUTION
   if (PositionsTotal() < 1 && IsUptrend && DipIntoZone && ZoneHold && BreakBackUp && BullishCandle)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lot = CalculateLotSize(StopLossPips);
      
      trade.Buy(lot, _Symbol, ask, ask - (StopLossPips * _Point), ask + (TakeProfitPips * _Point), "NCI Dynamic Pullback");
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

         // Break Even Logic
         if (sl < open_price && bid >= open_price + (BreakEvenPips * _Point))
            trade.PositionModify(ticket, open_price + (10 * _Point), PositionGetDouble(POSITION_TP));

         // Trailing Stop Logic
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