//+------------------------------------------------------------------+
//|                                           EMA_Crossover_V1.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version "1.08"
#property strict

#include <Trade\Trade.mqh>

input group "Indicator Settings" input int FastMAPeriod = 6; // Now used for Hull Logic (Faster)
input int SlowMAPeriod = 86;
input int TrendMAPeriod = 200;

input group "Trend Strength (ADX)" input int ADX_Period = 14;
input int ADX_Threshold = 25;

input group "Risk Management" input double RiskPercent = 1.0;
input double StopLossPips = 200;
input double TakeProfitPips = 400;
input int TrailingPips = 240;
input int BreakEvenPips = 200;

int FastHandle, SlowHandle, TrendHandle, ADXHandle;
CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(123456);

   //--- We use MODE_SMMA here as a base for faster responsiveness in this logic
   FastHandle = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   SlowHandle = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   TrendHandle = iMA(_Symbol, _Period, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   ADXHandle = iADX(_Symbol, _Period, ADX_Period);

   return (FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE ||
                   TrendHandle == INVALID_HANDLE || ADXHandle == INVALID_HANDLE
               ? INIT_FAILED
               : INIT_SUCCEEDED);
}

void OnTick()
{
   ManageOpenPositions();
   if (!IsNewBar())
      return;

   double FastEMA[], SlowEMA[], TrendEMA[], ADXValues[], PriceClose[];
   ArraySetAsSeries(FastEMA, true);
   ArraySetAsSeries(SlowEMA, true);
   ArraySetAsSeries(TrendEMA, true);
   ArraySetAsSeries(ADXValues, true);
   ArraySetAsSeries(PriceClose, true);

   if (CopyBuffer(FastHandle, 0, 0, 3, FastEMA) < 3 ||
       CopyBuffer(SlowHandle, 0, 0, 3, SlowEMA) < 3 ||
       CopyBuffer(TrendHandle, 0, 0, 3, TrendEMA) < 3 ||
       CopyBuffer(ADXHandle, 0, 0, 3, ADXValues) < 3 ||
       CopyClose(_Symbol, _Period, 0, 3, PriceClose) < 3)
      return;

   //--- EARLY ENTRY LOGIC: Price Crosses Fast EMA
   //--- Instead of waiting for EMA 6 to cross EMA 86 (Slow),
   //--- we enter when Price crosses EMA 6 while the trend is already confirmed.
   bool PriceCrossFast = (PriceClose[2] < FastEMA[2]) && (PriceClose[1] > FastEMA[1]);
   bool EMA_Alignment = (FastEMA[1] > SlowEMA[1]);
   bool TrendFilter = (PriceClose[1] > TrendEMA[1]);
   bool StrongTrend = (ADXValues[1] > ADX_Threshold);

   if (PositionsTotal() < 1 && PriceCrossFast && EMA_Alignment && TrendFilter && StrongTrend)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double lot = CalculateLotSize(StopLossPips);
      trade.Buy(lot, _Symbol, ask, ask - (StopLossPips * _Point), ask + (TakeProfitPips * _Point), "Early Entry V1.08");
   }
}

//--- Lot Size and Management logic remains strictly identical to V1.06/V1.07
double CalculateLotSize(double sl_pips)
{
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * (RiskPercent / 100.0);
   double lot = risk_amount / (sl_pips * 10 * tick_value);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = NormalizeDouble(lot, 2);
   return (lot < min_lot) ? min_lot : (lot > max_lot) ? max_lot
                                                      : lot;
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