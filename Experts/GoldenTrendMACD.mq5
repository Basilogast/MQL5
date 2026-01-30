//+------------------------------------------------------------------+
//|                                              GoldenTrendMACD.mq5 |
//|                                Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Expert\Expert.mqh>
//--- available signals
#include <Expert\Signal\SignalMACD.mqh>
//--- available trailing
#include <Expert\Trailing\TrailingNone.mqh>
//--- available money management
#include <Expert\Money\MoneyFixedLot.mqh>
//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
//--- inputs for expert
input string             Expert_Title             ="GoldenTrendMACD"; // Document name
ulong                    Expert_MagicNumber       =2144060332;        //
bool                     Expert_EveryTick         =false;             //
//--- inputs for main signal
input int                Signal_ThresholdOpen     =10;                // Signal threshold value to open [0...100]
input int                Signal_ThresholdClose    =10;                // Signal threshold value to close [0...100]
input double             Signal_PriceLevel        =0.0;               // Price level to execute a deal
input double             Signal_StopLevel         =50.0;              // Stop Loss level (in points)
input double             Signal_TakeLevel         =50.0;              // Take Profit level (in points)
input int                Signal_Expiration        =4;                 // Expiration of pending orders (in bars)
input int                Signal_MACD_PeriodFast  =12;                 // MACD(12,24,9,PRICE_CLOSE) Period of fast EMA
input int                Signal_MACD_PeriodSlow  =24;                 // MACD(12,24,9,PRICE_CLOSE) Period of slow EMA
input int                Signal_MACD_PeriodSignal=9;                  // MACD(12,24,9,PRICE_CLOSE) Period of averaging of difference
input ENUM_APPLIED_PRICE Signal_MACD_Applied      =PRICE_CLOSE;       // MACD(12,24,9,PRICE_CLOSE) Prices series
input double             Signal_MACD_Weight       =1.0;               // MACD(12,24,9,PRICE_CLOSE) Weight [0...1.0]
//--- inputs for money
input double             Money_FixLot_Percent     =10.0;              // Percent
input double             Money_FixLot_Lots        =0.1;               // Fixed volume

//+------------------------------------------------------------------+
//| DEBUG VARIABLES                                                  |
//+------------------------------------------------------------------+
int debug_macd_handle = INVALID_HANDLE; // Handle for our debug indicator

//+------------------------------------------------------------------+
//| Global expert object                                             |
//+------------------------------------------------------------------+
CExpert ExtExpert;
//+------------------------------------------------------------------+
//| Initialization function of the expert                            |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initializing expert
   if(!ExtExpert.Init(Symbol(),Period(),Expert_EveryTick,Expert_MagicNumber))
     {
      //--- failed
      printf(__FUNCTION__+": error initializing expert");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
//--- Creating signal
   CExpertSignal *signal=new CExpertSignal;
   if(signal==NULL)
     {
      //--- failed
      printf(__FUNCTION__+": error creating signal");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
//---
   ExtExpert.InitSignal(signal);
   signal.ThresholdOpen(Signal_ThresholdOpen);
   signal.ThresholdClose(Signal_ThresholdClose);
   signal.PriceLevel(Signal_PriceLevel);
   signal.StopLevel(Signal_StopLevel);
   signal.TakeLevel(Signal_TakeLevel);
   signal.Expiration(Signal_Expiration);
//--- Creating filter CSignalMACD
   CSignalMACD *filter0=new CSignalMACD;
   if(filter0==NULL)
     {
      //--- failed
      printf(__FUNCTION__+": error creating filter0");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
   signal.AddFilter(filter0);
//--- Set filter parameters
   filter0.PeriodFast(Signal_MACD_PeriodFast);
   filter0.PeriodSlow(Signal_MACD_PeriodSlow);
   filter0.PeriodSignal(Signal_MACD_PeriodSignal);
   filter0.Applied(Signal_MACD_Applied);
   filter0.Weight(Signal_MACD_Weight);
//--- Creation of trailing object
   CTrailingNone *trailing=new CTrailingNone;
   if(trailing==NULL)
     {
      //--- failed
      printf(__FUNCTION__+": error creating trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
//--- Add trailing to expert (will be deleted automatically))
   if(!ExtExpert.InitTrailing(trailing))
     {
      //--- failed
      printf(__FUNCTION__+": error initializing trailing");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
//--- Set trailing parameters
//--- Creation of money object
   CMoneyFixedLot *money=new CMoneyFixedLot;
   if(money==NULL)
     {
      //--- failed
      printf(__FUNCTION__+": error creating money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
//--- Add money to expert (will be deleted automatically))
   if(!ExtExpert.InitMoney(money))
     {
      //--- failed
      printf(__FUNCTION__+": error initializing money");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
//--- Set money parameters
   money.Percent(Money_FixLot_Percent);
   money.Lots(Money_FixLot_Lots);
//--- Check all trading objects parameters
   if(!ExtExpert.ValidationSettings())
     {
      //--- failed
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }
//--- Tuning of all necessary indicators
   if(!ExtExpert.InitIndicators())
     {
      //--- failed
      printf(__FUNCTION__+": error initializing indicators");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   //=========================================================
   // DEBUG INIT: Create a separate MACD handle to verify logic
   //=========================================================
   debug_macd_handle = iMACD(Symbol(), Period(), 
                             Signal_MACD_PeriodFast, 
                             Signal_MACD_PeriodSlow, 
                             Signal_MACD_PeriodSignal, 
                             Signal_MACD_Applied);
   
   if(debug_macd_handle == INVALID_HANDLE) {
      Print("CRITICAL ERROR: Failed to create Debug MACD Handle.");
   }
   //=========================================================

//--- ok
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Deinitialization function of the expert                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ExtExpert.Deinit();
   // Release Debug Handle
   if(debug_macd_handle != INVALID_HANDLE) IndicatorRelease(debug_macd_handle);
  }
//+------------------------------------------------------------------+
//| "Tick" event handler function                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   ExtExpert.OnTick();
   
   //=========================================================
   // DEBUG PRINTING LOGIC
   //=========================================================
   if(debug_macd_handle != INVALID_HANDLE)
     {
      // Define arrays to hold values
      double macd_main[];
      double macd_signal[];
      
      // Sort array from newest to oldest (Index 0 is current candle)
      ArraySetAsSeries(macd_main, true);
      ArraySetAsSeries(macd_signal, true);
      
      // Copy the last 2 bars (0 and 1)
      // Buffer 0 = Main Line, Buffer 1 = Signal Line
      if(CopyBuffer(debug_macd_handle, 0, 0, 2, macd_main) > 0 && 
         CopyBuffer(debug_macd_handle, 1, 0, 2, macd_signal) > 0)
        {
         // Print to Journal
         // We print Candle [1] (Completed candle) because that is usually what triggers signals
         Print("DEBUG MACD >> ",
               " Main[0]: ", DoubleToString(macd_main[0], 5), 
               " | Signal[0]: ", DoubleToString(macd_signal[0], 5),
               " | Main[1]: ", DoubleToString(macd_main[1], 5), 
               " | Signal[1]: ", DoubleToString(macd_signal[1], 5),
               " | Price: ", DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), 5)
               );
        }
     }
   //=========================================================
  }
//+------------------------------------------------------------------+
//| "Trade" event handler function                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
   ExtExpert.OnTrade();
  }
//+------------------------------------------------------------------+
//| "Timer" event handler function                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ExtExpert.OnTimer();
  }
//+------------------------------------------------------------------+