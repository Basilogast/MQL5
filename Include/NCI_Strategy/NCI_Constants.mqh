//+------------------------------------------------------------------+
//| NCI_Constants.mqh - Inputs, Enums & Settings                     |
//+------------------------------------------------------------------+
#property strict

enum ENUM_REENTRY_MODE {
   MODE_SINGLE   = 0, 
   MODE_DOUBLE   = 1, 
   MODE_INFINITE = 2  
};

// [NEW] ENTRY STYLE ENUMS
enum ENUM_ENTRY_STYLE {
   STYLE_BLIND_TOUCH  = 0, // Fire instantly when price touches zone
   STYLE_CONFIRMATION = 1  // Wait for closed candle pattern in zone
};

enum ENUM_CONFIRM_PATTERN {
   PATTERN_PINBAR    = 0,  // Long Wick Rejection
   PATTERN_ENGULFING = 1,  // Momentum Shift
   PATTERN_ANY       = 2   // Accept either Pinbar OR Engulfing
};

//--- 0. TIMEFRAME SETTINGS (FIXED)
input group "Timeframe Settings"
input ENUM_TIMEFRAMES TimeFrame_HTF = PERIOD_H1;  // High Timeframe (e.g. 1H)
input ENUM_TIMEFRAMES TimeFrame_LTF = PERIOD_M15; // Low Timeframe (e.g. 15M)

//--- 1. SECTOR A: SIMPLE STRATEGY (The Scattergun)
input group "Sector A: Simple Strategy"
input bool Enable_Simple_Mode     = false;  // Master Switch for Simple Mode

// Simple HTF Logic
input bool Simple_Trade_HTF       = false; // Trade 1H Zones?
input bool Simple_Trend_HTF       = true;  // 1H Trend Entries
input bool Simple_Breakout_HTF    = true;  // 1H Breakout Entries

// Simple LTF Logic
input bool Simple_Trade_LTF       = true;  // Trade 15M Zones?
input bool Simple_Trend_LTF       = true;  // 15M Trend Entries
input bool Simple_Breakout_LTF    = false; // 15M Breakout Entries
input bool Simple_UseTrendAlign   = true;  // Filter LTF trades with HTF Trend?

//--- 2. SECTOR B: ADVANCED STRATEGY (The Sniper)
input group "Sector B: Zone-in-Zone (ZiZ)"
input bool Enable_ZiZ_Mode        = true;  // If TRUE, IGNORES Sector A
input bool ZiZ_AllowTrend         = true;  // Trade LTF Trend Zone inside HTF Zone (Swings)
input bool ZiZ_AllowStairStep     = true;  // Trade LTF Zones ALIGNED with Trend (Steps)
input bool ZiZ_AllowStepSell      = false; // Master Switch to BLOCK Step Sells (Profit Killer)
input bool ZiZ_AllowBreakout      = false; // Trade LTF Breakout Zone inside HTF Zone
input bool UseToxicFilter         = true;  // Block bad Counter-Trend Scalps

//--- 3. SHARED RISK SETTINGS (Global)
input group "Shared Risk Settings"
input double RiskPercent     = 1.0;
input double MinRiskReward   = 2.0;
input ENUM_REENTRY_MODE EntryMode = MODE_DOUBLE;

//--- 4. VISUAL SETTINGS (Updated)
input group "Visual Settings"
input bool Show_ZigZag_Lines = true;   // Toggle ZigZag Lines (Turn OFF for speed)
input bool Show_Zone_Boxes   = true;   // Toggle Zone Boxes (Turn OFF for speed)
input int  HistoryBars       = 5000;
input int  LineWidth         = 2;
color SupplyColor     = clrMaroon; 
color DemandColor     = clrDarkGreen;
color FlippedColor    = clrGray; 
color ColorUp         = clrLimeGreen;
color ColorDown       = clrRed;
color ColorRange      = clrYellow;

//--- 5. STRUCTURE RULES
input group "Structure Rules"
input double MinBodyPercent = 0.50;  
input int MaxScanDistance   = 3;
input double BigCandleFactor = 1.3; 

//--- 6. VOLATILITY GUARD & FILTERS
input group "Volatility Guard & Filters"
input bool   UseVolatilityGuard = true;
input int    MaxSpreadPoints    = 25;      // Strict spread filter (2.5 pips)
input bool   Debug_Show_Spread  = true;    // Print Spread Log for every entry attempt
input int    MaxCandleSizePips  = 25;      // Strict candle filter (25 pips)

//--- 7. SCALING & ENTRY
input group "Entry Logic"
input double ReferenceZonePips_HTF = 235.0; // Reference size for H1
input double ReferenceZonePips_LTF = 60.0;  // Reference size for M15

// CONFIRMATION ENTRY SETTINGS
input ENUM_ENTRY_STYLE     EntryStyle         = STYLE_CONFIRMATION;
input ENUM_CONFIRM_PATTERN ConfirmationSignal = PATTERN_ANY;
input double               MinWickPercent     = 0.60; // Wick must be >= 60% of candle for Pinbar

input double BaseEntryDepth    = 0.40;      // Zone Arming/Entry Line
input double BaseMaxDepth      = 0.75;      // Zone Invalidation Line
input double TPZoneDepth       = 0.0;
input double Breakout_HTF_Buffer_Pips = 50.0; // Buffer for Breakout Zone proximity

input double Normal_Max_Entry_Clamp = 0.60; // Max allowed depth for normal entry
input double Normal_Max_Limit_Clamp = 0.80; // Max allowed depth for normal limit 

//--- 8. BUFFER SETTINGS
input group "Buffer Logic"
input bool   UseDynamicBuffer = false;
input double BaseBufferPoints = 45.0;
input double MinBufferPoints  = 20;   
input double MaxBufferPoints  = 200;

//--- 9. RISK MANAGEMENT (Basic)
input group "Risk Management (Basic)"
input int    MaxOpenTrades           = 2;     // Max simultaneous trades allowed
input int    MinMinutesBetweenTrades = 15;    // Minimum minutes between opening trades
input bool   EnableProfitLocking     = true;

// Standard Trades (Swing/Scalp)
input double LockTriggerPercent  = 0.80; // % of Distance to TP
input double LockPositionPercent = 0.70; // % of Distance to TP
// Stair-Step Trades (High RR)
input double Step_LockTriggerPercent  = 0.60; // Trigger closer to lock
input double Step_LockPositionPercent = 0.55; // Lock stays at 60%

// RR LOCKING (Backup - Now Step-Specific capable)
input bool   Enable_RR_Locking   = true;  // [ENABLED]
input bool   RR_Lock_Step_Only   = false; // If true, RR lock ONLY applies to Step trades
input double RR_Lock_Trigger     = 4.0;   // Trigger at 1:4 RR
input double RR_Lock_Target      = 3.5;   // Bank at 1:3.5 RR

//--- 10. SMART TRAILING & EXITS
input group "Smart Trailing & Exits"
// Smart Structure Trail (Stair-Step)
input bool   Enable_Smart_Trail      = false; // [DISABLED]
input double Smart_Trail_Buffer_Pips = 10.0;  

// Friday End-of-Week Close (Cash RR Logic)
input bool   Enable_Friday_Close     = true;      // Close high profit trades on Friday
input int    Friday_Close_Hour       = 20;        // Server hour to start checking
input double Account_Initial_Balance = 10000.0;   // FTMO Initial Balance for Risk Calc
input double Friday_Min_RR           = 3.0;       // Close if Profit > (RiskAmount * 3.0)

//--- 11. TIME FILTER
input group "Time Filter Settings"
input bool   UseTimeFilter = true; // Enable Session Filtering
input int    StartHour     = 7;    // Start Trading (Server Time)
input int    EndHour       = 16;   // Stop Entering New Trades (Server Time)

input bool AllowTrading      = true; // Master Safety Switch

//--- 12. ADR MARKET REGIMES (Unified Volatility Router)
input group "ADR Market Regimes"
input bool   Use_ADR_Filter        = true;    // [MASTER SWITCH] Enable ADR Filtering
input int    ADR_Period            = 5;       // Days to average

// Normal Trend (ZiZ) Bounds
input double ADR_Min_Pips          = 70.0;    // Floor for Normal Trend Mode
input double ADR_Max_Pips          = 85.0;    // Ceiling for Normal Trend Mode

// Range Fade (Low Volatility)
input bool   Enable_SectorC_Range  = true;    // Enable Range Fade below threshold
input double SectorC_Max_ADR       = 70.0;    // Below this ADR = Range Mode

// Storm Mode (High Volatility)
input bool   Enable_SectorE_Storm  = true;    // Enable Deep Entries for High Volatility
input double SectorE_Min_ADR       = 85.0;    // Above this = Storm Mode
input double Storm_Entry_Depth     = 0.70;    // 60% Deep (Wait for crash)
input double Storm_Buffer_Pips     = 15.0;    // Wide Stop Loss
input double Storm_Max_Entry_Clamp = 0.85;    // Max allowed depth for Storm entry
input double Storm_Max_Limit_Clamp = 0.90;    // Max allowed depth for Storm limit

// Statistics Report Output
input double Stats_ADR_Low         = 70.0;    // Threshold for "Low Volatility" Report
input double Stats_ADR_High        = 85.0;    // Threshold for "High Volatility" Report