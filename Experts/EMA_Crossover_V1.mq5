//+------------------------------------------------------------------+
//|                                           EMA_Crossover_V1.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "1.14" // Version updated
#property strict

#include <Trade\Trade.mqh>

input group "Indicator Settings" 
input int FastMAPeriod = 6;  
input int SlowMAPeriod = 86;
input int TrendMAPeriod = 200;

input group "Trend Strength (ADX)" 
input int ADX_Period = 14;
input int ADX_Threshold = 25;

input group "Risk Management" 
input double RiskPercent = 1.0;
input double StopLossPips = 200;
input double TakeProfitPips = 400;
input int TrailingPips = 240;
input int BreakEvenPips = 200;

input group "Slope Filter"
input double MinSlope = 0.00020; 

input group "RSI Filter (Anti-Spike)"
input int RSI_Period = 14;     
input int RSI_Overbought = 70; 

//--- NEW: CRASH GUARD INPUT
input group "Crash Guard"
input int MediumMAPeriod = 50; // Price must be above this EMA to confirm recovery

int FastHandle, SlowHandle, TrendHandle, ADXHandle, RSIHandle, MediumHandle;
CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(123456);

   FastHandle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   SlowHandle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   TrendHandle = iMA(_Symbol, _Period, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ADXHandle = iADX(_Symbol, _Period, ADX_Period);
   RSIHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE); 
   
   //--- NEW: Initialize Medium MA Handle
   MediumHandle = iMA(_Symbol, _Period, MediumMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   return (FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE ||
           TrendHandle == INVALID_HANDLE || ADXHandle == INVALID_HANDLE ||
           RSIHandle == INVALID_HANDLE || MediumHandle == INVALID_HANDLE
           ? INIT_FAILED
           : INIT_SUCCEEDED);
}

void OnTick()
{
   ManageOpenPositions();
   if (!IsNewBar())
      return;

   double FastEMA[], SlowEMA[], TrendEMA[], ADXValues[], RSIValues[], PriceClose[], MediumEMA[];
   ArraySetAsSeries(FastEMA, true);
   ArraySetAsSeries(SlowEMA, true);
   ArraySetAsSeries(TrendEMA, true);
   ArraySetAsSeries(ADXValues, true);
   ArraySetAsSeries(RSIValues, true);
   ArraySetAsSeries(PriceClose, true);
   ArraySetAsSeries(MediumEMA, true);

   if (CopyBuffer(FastHandle, 0, 0, 20, FastEMA) < 20 ||
       CopyBuffer(SlowHandle, 0, 0, 20, SlowEMA) < 20 ||
       CopyBuffer(TrendHandle, 0, 0, 20, TrendEMA) < 20 ||
       CopyBuffer(ADXHandle, 0, 0, 20, ADXValues) < 20 ||
       CopyBuffer(RSIHandle, 0, 0, 20, RSIValues) < 20 || 
       CopyBuffer(MediumHandle, 0, 0, 20, MediumEMA) < 20 || // Copy Medium MA Data
       CopyClose(_Symbol, _Period, 0, 20, PriceClose) < 20)
      return;

   //--- LOGIC
   bool PriceCrossFast = (PriceClose[2] < FastEMA[2]) && (PriceClose[1] > FastEMA[1]);
   bool EMA_Alignment = (FastEMA[1] > SlowEMA[1]);
   bool TrendFilter = (PriceClose[1] > TrendEMA[1]);
   bool StrongTrend = (ADXValues[1] > ADX_Threshold);

   //--- SLOPE FILTER
   double SlopeDiff = SlowEMA[1] - SlowEMA[6];
   bool GoodSlope = (SlopeDiff > MinSlope);

   //--- RSI FILTER
   bool NotOverbought = (RSIValues[1] < RSI_Overbought);

   //--- TREND ALIGNMENT
   double TrendSlope = TrendEMA[1] - TrendEMA[10]; 
   bool TrendIsRising = (TrendSlope > 0);

   //--- NEW: CRASH GUARD LOGIC
   // Price must be above the 50 EMA to ensure we aren't in a "Dead Cat Bounce"
   bool AboveCrashLine = (PriceClose[1] > MediumEMA[1]);

   //--- ENTRY: Added '&& AboveCrashLine'
   if (PositionsTotal() < 1 && PriceCrossFast && EMA_Alignment && TrendFilter && StrongTrend && GoodSlope && NotOverbought && TrendIsRising && AboveCrashLine)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lot = CalculateLotSize(StopLossPips);
      trade.Buy(lot, _Symbol, ask, ask - (StopLossPips * _Point), ask + (TakeProfitPips * _Point), "Early Entry V1.14 CrashGuard");
   }
}

double CalculateLotSize(double sl_pips)
{
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * (RiskPercent / 100.0);
   double lot = risk_amount / (sl_pips * 10 * tick_value);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = NormalizeDouble(lot, 2);
   return (lot < min_lot) ? min_lot : (lot > max_lot) ? max_lot : lot;
}

void ManageOpenPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetSymbol(i) == _Symbol)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double current_sl = PositionGetDouble(POSITION_SL);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

         if (current_sl < open_price && bid >= open_price + (BreakEvenPips * _Point))
            trade.PositionModify(ticket, open_price + (10 * _Point), PositionGetDouble(POSITION_TP));

         double new_sl = bid - (TrailingPips * _Point);
         if (new_sl > current_sl + (_Point * 10))
            trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
      }
   }
}

bool IsNewBar()
{
   static datetime last;
   datetime cur = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   if (last == cur)
      return false;
   last = cur;
   return true;
}