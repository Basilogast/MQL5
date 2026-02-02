//+------------------------------------------------------------------+
//|                                           EMA_Crossover_V1.mq5   |
//|                                  Copyright 2024, Trading Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property version   "1.06"
#property strict

#include <Trade\Trade.mqh>

//--- New parameters added for Forward-Validated optimization
input group "Indicator Settings"
input int      FastMAPeriod = 6;      // Optimized Robust Value
input int      SlowMAPeriod = 86;     // Optimized Robust Value
input int      TrendMAPeriod = 200;

input group "Risk Management"
input double   RiskPercent  = 1.0;    // Risk 1% of balance per trade
input double   StopLossPips = 200;    
input double   TakeProfitPips = 400;
input int      TrailingPips = 240;    // Highest Forward Performance
input int      BreakEvenPips = 200;   // Highest Forward Performance

int    FastHandle, SlowHandle, TrendHandle;
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(123456);

   FastHandle  = iMA(_Symbol, _Period, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   SlowHandle  = iMA(_Symbol, _Period, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   TrendHandle = iMA(_Symbol, _Period, TrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(FastHandle == INVALID_HANDLE || SlowHandle == INVALID_HANDLE || TrendHandle == INVALID_HANDLE)
   {
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manage trailing stops and break even
   ManageOpenPositions();

   if(!IsNewBar())
   {
      return;
   }

   double FastEMA[], SlowEMA[], TrendEMA[];
   ArraySetAsSeries(FastEMA, true);
   ArraySetAsSeries(SlowEMA, true);
   ArraySetAsSeries(TrendEMA, true);

   if(CopyBuffer(FastHandle, 0, 0, 3, FastEMA) < 3 || 
      CopyBuffer(SlowHandle, 0, 0, 3, SlowEMA) < 3 || 
      CopyBuffer(TrendHandle, 0, 0, 3, TrendEMA) < 3)
   {
      return;
   }

   bool BuyCondition = (FastEMA[2] < SlowEMA[2]) && (FastEMA[1] > SlowEMA[1]);
   bool TrendFilter  = (iClose(_Symbol, _Period, 1) > TrendEMA[1]);

   if(PositionsTotal() < 1 && BuyCondition && TrendFilter) 
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Calculate Lot Size based on RiskPercent logic
      double lot = CalculateLotSize(StopLossPips); 
      
      trade.Buy(lot, _Symbol, ask, ask-(StopLossPips*_Point), ask+(TakeProfitPips*_Point), "EMA 6-86 Forward Ready");
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Account Risk                         |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_pips)
{
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * (RiskPercent / 100.0);
   
   // Formula: Risk Amount / (Stop Loss distance * Tick Value)
   double lot = risk_amount / (sl_pips * 10 * tick_value); 
   
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   lot = NormalizeDouble(lot, 2);
   
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Manage Open Positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         ulong  ticket = PositionGetInteger(POSITION_TICKET);
         double current_sl = PositionGetDouble(POSITION_SL);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         // Break Even Logic
         if(current_sl < open_price && bid >= open_price + (BreakEvenPips * _Point))
         {
            trade.PositionModify(ticket, open_price + (10 * _Point), PositionGetDouble(POSITION_TP));
         }

         // Trailing Stop Logic
         double new_sl = bid - (TrailingPips * _Point);
         if(new_sl > current_sl + (_Point * 10)) 
         {
            trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| New Bar Detection                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime last;
   datetime cur = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   
   if(last == cur)
   {
      return false;
   }
   
   last = cur;
   return true;
}