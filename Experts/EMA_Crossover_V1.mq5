//+------------------------------------------------------------------+
//|                                           EMA_Crossover_V1.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "1.12" // Version updated
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

//--- UPDATED: Removed Distance, Kept RSI
input group "RSI Filter (Anti-Spike)"
input int RSI_Period = 14;     
input int RSI_Overbought = 70; // Don't buy if RSI is above this level

int FastHandle, SlowHandle, TrendHandle, ADXHandle, RSIHandle;
CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(123456);

   FastHandle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   SlowHandle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   TrendHandle = iMA(_Symbol, _Period, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ADXHandle = iADX(_Symbol, _Period, ADX_Period);
   RSIHandle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE); // RSI Init

   return (FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE ||
           TrendHandle == INVALID_HANDLE || ADXHandle == INVALID_HANDLE ||
           RSIHandle == INVALID_HANDLE
           ? INIT_FAILED
           : INIT_SUCCEEDED);
}

void OnTick()
{
   ManageOpenPositions();
   if (!IsNewBar())
      return;

   double FastEMA[], SlowEMA[], TrendEMA[], ADXValues[], RSIValues[], PriceClose[];
   ArraySetAsSeries(FastEMA, true);
   ArraySetAsSeries(SlowEMA, true);
   ArraySetAsSeries(TrendEMA, true);
   ArraySetAsSeries(ADXValues, true);
   ArraySetAsSeries(RSIValues, true);
   ArraySetAsSeries(PriceClose, true);

   if (CopyBuffer(FastHandle, 0, 0, 10, FastEMA) < 10 ||
       CopyBuffer(SlowHandle, 0, 0, 10, SlowEMA) < 10 ||
       CopyBuffer(TrendHandle, 0, 0, 10, TrendEMA) < 10 ||
       CopyBuffer(ADXHandle, 0, 0, 10, ADXValues) < 10 ||
       CopyBuffer(RSIHandle, 0, 0, 10, RSIValues) < 10 || 
       CopyClose(_Symbol, _Period, 0, 10, PriceClose) < 10)
      return;

   //--- LOGIC
   bool PriceCrossFast = (PriceClose[2] < FastEMA[2]) && (PriceClose[1] > FastEMA[1]);
   bool EMA_Alignment = (FastEMA[1] > SlowEMA[1]);
   bool TrendFilter = (PriceClose[1] > TrendEMA[1]);
   bool StrongTrend = (ADXValues[1] > ADX_Threshold);

   //--- SLOPE FILTER
   double SlopeDiff = SlowEMA[1] - SlowEMA[6];
   bool GoodSlope = (SlopeDiff > MinSlope);

   //--- RSI FILTER (Replaces Max Distance)
   // If RSI is > 70, market is exhausted. We wait for a cooldown.
   bool NotOverbought = (RSIValues[1] < RSI_Overbought);

   //--- ENTRY
   if (PositionsTotal() < 1 && PriceCrossFast && EMA_Alignment && TrendFilter && StrongTrend && GoodSlope && NotOverbought)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lot = CalculateLotSize(StopLossPips);
      trade.Buy(lot, _Symbol, ask, ask - (StopLossPips * _Point), ask + (TakeProfitPips * _Point), "Early Entry V1.12 RSI");
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