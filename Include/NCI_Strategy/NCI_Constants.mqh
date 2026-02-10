//+------------------------------------------------------------------+
//| NCI_Constants.mqh - Inputs, Enums & Settings                     |
//+------------------------------------------------------------------+
#property strict

enum ENUM_REENTRY_MODE {
   MODE_SINGLE   = 0, 
   MODE_DOUBLE   = 1, 
   MODE_INFINITE = 2  
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
input bool Enable_ZiZ_Mode        = true; // If TRUE, IGNORES Sector A
input bool ZiZ_AllowTrend         = true;  // Trade LTF Trend Zone inside HTF Zone
input bool ZiZ_AllowBreakout      = false; // Trade LTF Breakout Zone inside HTF Zone

//--- 3. SHARED RISK SETTINGS (Global)
input group "Shared Risk Settings"
input double RiskPercent     = 1.0;  
input double MinRiskReward   = 2.0;
input ENUM_REENTRY_MODE EntryMode = MODE_DOUBLE; 

//--- 4. VISUAL SETTINGS
input group "Visual Settings"
input int HistoryBars       = 5000;
input int LineWidth         = 2;
input bool DrawZones        = true;

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

//--- 6. VOLATILITY GUARD
input group "Volatility Guard"
input bool   UseVolatilityGuard = true; 
input int    MaxSpreadPoints   = 30; 
input int    MaxCandleSizePips = 80; 

//--- 7. SCALING & ENTRY
input group "Entry Logic"
input double ReferenceZonePips_HTF = 235.0; // Reference size for H1
input double ReferenceZonePips_LTF = 60.0;  // Reference size for M15

input double BaseEntryDepth    = 0.40;  
input double BaseMaxDepth      = 0.75;
input double TPZoneDepth     = 0.0;

//--- 8. BUFFER SETTINGS
input group "Buffer Logic"
input bool   UseDynamicBuffer = false; 
input double BaseBufferPoints = 45.0;
input double MinBufferPoints  = 20;   
input double MaxBufferPoints  = 200;

//--- 9. RISK MANAGEMENT
input group "Risk Management"
input bool   EnableProfitLocking = true;
input double LockTriggerPercent  = 0.80;
input double LockPositionPercent = 0.70;
input bool AllowTrading      = true; // Master Safety Switch