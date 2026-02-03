//+------------------------------------------------------------------+
//|                                     NCI_Dynamic_Pullback_V1.4.mq5|
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "1.40"
#property strict

#include <Trade\Trade.mqh>

//--- 1. TREND (The Big Picture)
input group "1. Trend Settings"
input int TrendEMA_Period = 200;    // Long-term direction

//--- 2. ZONE (The Value Area)
input group "2. Zone Settings"
input int ZoneFastEMA     = 20;     // Top of Buy Zone
input int ZoneSlowEMA     = 50;     // Bottom of Buy Zone

//--- 3. STABILITY FILTERS (New)
input group "3. Stability Filters"
input double MinFastSlope = 0.00015; // 20 EMA Slope (Momentum)
input int ADX_Period      = 14;      
input int ADX_Min         = 20;      // ADX > 20 (Filters dead markets)

//--- 4. CONFIRMATION
input group "4. Confirmation"
input bool RequireGreenCandle = true; 
input double MinTrendSlope    = 0.00005; 

//--- 5. RISK MANAGEMENT
input group "5. Risk Management"
input double RiskPercent    = 1.0;
input double StopLossPips   = 150;  
input double TakeProfitPips = 450;  
input int TrailingPips      = 200;
input int BreakEvenPips     = 150;

int FastHandle, SlowHandle, TrendHandle, ADXHandle;
CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(888999);

   FastHandle  = iMA(_Symbol, _Period, ZoneFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   SlowHandle  = iMA(_Symbol, _Period, ZoneSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   TrendHandle = iMA(_Symbol, _Period, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   ADXHandle   = iADX(_Symbol, _Period, ADX_Period); // New ADX Handle

   return (FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE || 
           TrendHandle == INVALID_HANDLE || ADXHandle == INVALID_HANDLE) 
           ? INIT_FAILED : INIT_SUCCEEDED;
}

void OnTick()
{
   ManageOpenPositions();
   if (!IsNewBar()) return;

   //--- Define Arrays
   double FastMA[], SlowMA[], TrendMA[], ADX[], Close[], Open[], Low[];
   ArraySetAsSeries(FastMA, true); 
   ArraySetAsSeries(SlowMA, true); 
   ArraySetAsSeries(TrendMA, true);
   ArraySetAsSeries(ADX, true);
   ArraySetAsSeries(Close, true);  
   ArraySetAsSeries(Open, true);
   ArraySetAsSeries(Low, true);

   //--- Copy Data
   if (CopyBuffer(FastHandle, 0, 0, 20, FastMA) < 20 ||
       CopyBuffer(SlowHandle, 0, 0, 20, SlowMA) < 20 ||
       CopyBuffer(TrendHandle, 0, 0, 20, TrendMA) < 20 ||
       CopyBuffer(ADXHandle, 0, 0, 20, ADX) < 20 || // Copy ADX
       CopyClose(_Symbol, _Period, 0, 3, Close) < 3 ||
       CopyOpen(_Symbol, _Period, 0, 3, Open) < 3 ||
       CopyLow(_Symbol, _Period, 0, 3, Low) < 3)
      return;

   //--- STRATEGY LOGIC -------------------------------------------

   // 1. TREND ALIGNMENT (New)
   // Ensure the Zone is open and ordered (20 > 50).
   bool IsAligned = (FastMA[1] > SlowMA[1]);

   // 2. ADX STABILITY (New)
   // Ensure the market has actual power (Not sleeping).
   bool StrongTrend = (ADX[1] > ADX_Min);

   // 3. FAST SLOPE (Momentum)
   double FastSlope = FastMA[1] - FastMA[5];
   bool GoodMomentum = (FastSlope > MinFastSlope);

   // 4. LONG TERM TREND
   double BigSlope = TrendMA[1] - TrendMA[10];
   bool IsUptrend = (BigSlope > MinTrendSlope) && (Close[1] > TrendMA[1]);

   // 5. THE DIP & TRIGGER
   bool DipIntoZone = (Low[1] < FastMA[1]); 
   bool ZoneHold    = (Close[1] > SlowMA[1]); 
   bool BreakBackUp = (Close[1] > FastMA[1]);
   bool BullishCandle = (Close[1] > Open[1]);

   //--- ENTRY EXECUTION
   // Added 'IsAligned' and 'StrongTrend'
   if (PositionsTotal() < 1 && IsUptrend && IsAligned && StrongTrend && GoodMomentum && DipIntoZone && ZoneHold && BreakBackUp && BullishCandle)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lot = CalculateLotSize(StopLossPips);
      
      trade.Buy(lot, _Symbol, ask, ask - (StopLossPips * _Point), ask + (TakeProfitPips * _Point), "NCI Pullback V1.4 Stable");
   }
}

//--- HELPER FUNCTIONS (Same as before) --------------------------
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