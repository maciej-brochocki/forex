//-------------------------------------------
//|                    ReverseOnLimit.mq5   |
//|      Copyright 2012, Maciej Brochocki   |
//|               http://www.bestideas.pl   |
//-------------------------------------------

#property			copyright "Copyright 2012, Maciej Brochocki"

input int			OrderMagic = 1; // order magic number
input int         Mode = 0; // reverse on SL(0) or on TP(1) or combo (2)
input int         TMode = 1; // T is const(0) or avg. of N bars (1) or NRTR(2)
input int			QMode = 0; // CG/(MDD+1)^W (0) CG/(MDD+D)^W (1)
input int         W = 1; // power of risk ;)
input int         AdaptMode = 0; // AVG(0) MED(1) linReg(2)
input int         Stupidity = -1; // stupidity level (0-4) or MM off (-1)
input int         Tax = 50; // money redistribution parameter (0-100)

#define SLIP 0

#define MAX_P 903
#define N 5
#define DEPTH 75
#define MAX_M 200
#define REQUIRED_HISTORY (N + DEPTH + MAX_M)

struct Quality
{
	double curr_profit;
	double curr_max;
	double max_dd;
	double quality;
};
struct State
{
// platform specific config
   // static config
   int            agentMagic; // order magic number for agent
   string         symbol; // symbol for agent
   ENUM_TIMEFRAMES   period; // period for agent
   // dynamic state
   datetime			lastBarTime; // time of the last bar 
   int            currPos; // variable for storing the direction of the last trade (buy or sell)
   double         currPosSize; //value of current position size
   double         pendPosSize; //value of pending position size
   double         currLimit;

// algorithm config
   // static config
   int            mode; // algorithm used by agent: reverse on SL(0) or on TP(1)
   int            tMode; // algorithm's config parameter
   int			  qMode; // algorithm's config parameter
   int            w; // algorithm's config parameter
   int            adaptMode; // algorithm's config parameter
   int            stupidity; // money management config parameter
   // derived config
   int				digits; // number of digits after the decimal point in the price
   double			pip; // calculated pip
   int			  spread;
   int            minLimit; // algorithm's config parameter
   int            pairDir; // money management config parameter
   int            avg; // money management config parameter
   int            dev; // money management config parameter
   int            min_p; // algorithm's config parameter
   int            max_p; // algorithm's config parameter
   int            p_count; // algorithm's config parameter
   // dynamic state
   double         tCalcTmp; //tmp var for t calculation
   MqlRates       history[REQUIRED_HISTORY];
   int            history_oldest_item_idx;
   double         agentCash;
   Quality        q;
   // adaptation
   Quality        q_matrix[MAX_P*MAX_M];
   int            q_max_m_row;
   int            p_currPos[MAX_P];
   double         p_currLimit[MAX_P];
   Quality        p_q[MAX_P]; //only for per p results
   int            m_currPos[MAX_M]; //only for per m results
   double         m_currLimit[MAX_M]; //only for per m results
   Quality        m_q[MAX_M]; //only for per m results
};
State state[12]; // sates for all agents
int agentsNumber = 0; // number of agents used

//----------------------------------
//|   Init helper function (ALGO)  |
//----------------------------------
int spread[4] = {20, 30, 40, 30};
int minLimit[4] = {40, 60, 80, 60}; //EURUSD, GBPUSD, USDCHF, USDJPY
int pairDir[4] = {0, 0, 1, 1};
int avg[4][9] = {
   {23, 65, 108, 151, 192, 372, 944, 2151, 4394},
   {22, 42, 77, 112, 154, 410, 1045, 2607, 5267},
   {17, 47, 82, 125, 199, 425, 1093, 2446, 4939},
   {8, 27, 62, 113, 166, 340, 858, 1930, 3923}
};
int dev[4][9] = {
   {20, 50, 80, 125, 150, 276, 559, 1204, 2713},
   {19, 44, 65, 91, 122, 285, 656, 1581, 2953},
   {16, 45, 71, 107, 153, 319, 630, 1283, 2362},
   {7, 30, 56, 101, 128, 249, 538, 1096, 1933}
};
void InitAgentData(State& s)
{
	SymbolSelect(s.symbol, true);
	s.digits = (int)SymbolInfoInteger(s.symbol, SYMBOL_DIGITS);
	s.pip = 1;
	for (int i=0; i<s.digits; i++)
	{
	   s.pip = s.pip / 10;
	}
   int sym, per;
   if (s.symbol == "EURUSD") sym = 0;
   else if (s.symbol == "GBPUSD") sym = 1;
   else if (s.symbol == "USDCHF") sym = 2;
   else if (s.symbol == "USDJPY") sym = 3;
   switch(s.period) {
      case PERIOD_M1: per = 0; break;
      case PERIOD_M5: per = 1; break;
      case PERIOD_M15: per = 2; break;
      case PERIOD_M30: per = 3; break;
      case PERIOD_H1: per = 4; break;
      case PERIOD_H4: per = 5; break;
      case PERIOD_D1: per = 6; break;
      case PERIOD_W1: per = 7; break;
      case PERIOD_MN1: per = 8; break;
   }
   s.minLimit = minLimit[sym];
   s.pairDir = pairDir[sym];
   s.avg = avg[sym][per];
   s.dev = dev[sym][per];
   s.tCalcTmp = 0;
   s.history_oldest_item_idx = -1;
   s.agentCash = 10000 / agentsNumber;
   s.q.curr_max=0; s.q.curr_profit=0; s.q.max_dd=0; s.q.quality=0; //memset(&s.q, 0, sizeof(Quality));
   // adaptation
   if (s.tMode == 1)
   {
	   s.min_p = 150;
	   s.max_p = 850;
   }
   else
   {
	   s.min_p = s.minLimit;
	   s.max_p = s.avg + 5 * s.dev;
   }
   s.p_count = (s.max_p - s.min_p + 1);
   //s.q_matrix = (Quality*)malloc(s.p_count * MAX_M * sizeof(Quality));
   for (int x=0; x<s.p_count * MAX_M; x++) {s.q_matrix[x].curr_max=0; s.q_matrix[x].curr_profit=0; s.q_matrix[x].max_dd=0; s.q_matrix[x].quality=0;} //   memset(s.q_matrix, 0, s.p_count * MAX_M * sizeof(Quality));
   s.q_max_m_row = 0;
   //s.p_currPos = (int*)malloc(s.p_count * sizeof(int));
   for (int x=0; x<s.p_count; x++) s.p_currPos[x]=0; //   memset(s.p_currPos, 0, s.p_count * sizeof(int));
   //s.p_currLimit = (double*)malloc(s.p_count * sizeof(double));
   for (int x=0; x<s.p_count; x++) s.p_currLimit[x]=0; //   memset(s.p_currLimit, 0, s.p_count * sizeof(double));
   //s.p_q = (Quality*)malloc(s.p_count * sizeof(Quality));
   for (int x=0; x<s.p_count; x++) {s.p_q[x].curr_max=0; s.p_q[x].curr_profit=0; s.p_q[x].max_dd=0; s.p_q[x].quality=0;} //   memset(s.p_q, 0, s.p_count * sizeof(Quality));
   for (int x=0; x<MAX_M; x++) s.m_currPos[x]=0; //  memset(s.m_currPos, 0, MAX_M * sizeof(int));
   for (int x=0; x<MAX_M; x++) s.m_currLimit[x]=0; //  memset(s.m_currLimit, 0, MAX_M * sizeof(double));
   for (int x=0; x<MAX_M; x++) {s.m_q[x].curr_max=0; s.m_q[x].curr_profit=0; s.m_q[x].max_dd=0; s.m_q[x].quality=0;} //   memset(s.m_q, 0, MAX_M * sizeof(Quality));
}

//----------------------------------
//|   Init helper function (PLAT)  |
//----------------------------------
void InitPlatformData(State& s)
{
   s.lastBarTime = D'01.01.1971';
   s.currPos = 0;
   s.currPosSize = 0;
   s.currLimit = 0;
}

//---------------------------------
//|   Init helper function (MIX)  |
//---------------------------------
void InitAgentCfg(State& s, int mag, string sym, ENUM_TIMEFRAMES p, int m, int tM, int qM, int w, int aM, int stup)
{
// platform specific config
   s.agentMagic = mag;
   s.symbol = sym;
   s.period = p;
   InitPlatformData(s);
// algorithm config
   s.mode = m;
   s.tMode = tM;
   s.qMode = qM;
   s.w = w;
   s.adaptMode = aM;
   s.stupidity = stup;
   InitAgentData(s);
}

//--------------------------------------------
//|   Expert initialization function (PLAT)  |
//--------------------------------------------
int OnInit()
{
   if (Mode < 2)
   {
      agentsNumber = 1;
      InitAgentCfg(state[0], OrderMagic, _Symbol, _Period, Mode, TMode, QMode, W, AdaptMode, Stupidity);
   }
   else
   {
      agentsNumber = 12;
      InitAgentCfg(state[0], OrderMagic + 0, "EURUSD", PERIOD_H1, 0, 1, 0, 1, 0, Stupidity);
      InitAgentCfg(state[1], OrderMagic + 1, "EURUSD", PERIOD_H1, 0, 1, 0, 1, 2, Stupidity);
      InitAgentCfg(state[2], OrderMagic + 2, "EURUSD", PERIOD_H1, 1, 1, 0, 1, 0, Stupidity);
      InitAgentCfg(state[3], OrderMagic + 3, "GBPUSD", PERIOD_H1, 0, 1, 0, 1, 0, Stupidity);
      InitAgentCfg(state[4], OrderMagic + 4, "GBPUSD", PERIOD_H1, 1, 1, 0, 1, 0, Stupidity);
      InitAgentCfg(state[5], OrderMagic + 5, "GBPUSD", PERIOD_H1, 1, 1, 0, 1, 2, Stupidity);
      InitAgentCfg(state[6], OrderMagic + 6, "USDCHF", PERIOD_H1, 0, 1, 0, 1, 0, Stupidity);
      InitAgentCfg(state[7], OrderMagic + 7, "USDCHF", PERIOD_H1, 0, 1, 0, 1, 2, Stupidity);
      InitAgentCfg(state[8], OrderMagic + 8, "USDCHF", PERIOD_H1, 1, 1, 0, 1, 0, Stupidity);
      InitAgentCfg(state[9], OrderMagic + 9, "USDJPY", PERIOD_H1, 0, 1, 0, 1, 0, Stupidity);
      InitAgentCfg(state[10], OrderMagic + 10, "USDJPY", PERIOD_H1, 0, 1, 0, 1, 2, Stupidity);
      InitAgentCfg(state[11], OrderMagic + 11, "USDJPY", PERIOD_H1, 1, 1, 0, 1, 0, Stupidity);
   }
	return(0);
}

//----------------------------------------------
//|   Expert deinitialization function (PLAT)  |
//----------------------------------------------
void OnDeinit(const int reason)
{
	return;
}

//----------------------------------
//|   Expert tick function (PLAT)  |
//----------------------------------
void OnTick()
{
   for (int i=0; i<agentsNumber; i++)
   {
      AgentOnTick(state[i]);
   }
	return;
}

//-----------------------------------------------------
//|   Returns true, if the bar has just begun (PLAT)  |
//-----------------------------------------------------
bool NewBar(State& s)
{
	datetime New_Time[1];
	int copied = CopyTime(s.symbol, s.period, 0, 1, New_Time);

	if(copied>0)
	{
		if(s.lastBarTime != New_Time[0])
		{
			s.lastBarTime = New_Time[0];
			return(true);
		}
	}
	else
	{
		Alert(__FUNCTION__, "- CopyTime error: ", GetLastError());
		ResetLastError();
		return(false);
	}
	return(false);
}

//-------------------------------------
//|   Returns true on success (PLAT)  |
//-------------------------------------
bool executeOrder(MqlTradeRequest& request, string errInfoPrefix)
{
	MqlTradeCheckResult checkResult;
	ZeroMemory(checkResult);
	if(OrderCheck(request, checkResult))
	{
		MqlTradeResult result;
		ZeroMemory(result);
		if (!OrderSend(request, result))
		{
			Print(errInfoPrefix, " - OrderSend error:", result.comment);
			return(false);
		}
	}
	else
	{
		Print(errInfoPrefix, " - OrderCheck error:", checkResult.comment);
		return(false);
	}
	return(true);
}

//--------------------------------------------
//|   Extension of standard function (PLAT)  |
//--------------------------------------------
ulong OrderGetTicketWithMagic(int m)
{
   ulong ticket;
   int total=OrdersTotal();
   for (int i=0; i<total; i++)
   {
      if ((ticket=OrderGetTicket(i))>0)
      {
         if (OrderGetInteger(ORDER_MAGIC) == m)
         {
            return ticket;
         }
      }
   }
   return 0;
}

//---------------------------------------
//|   UpdateLimit - moves limit (PLAT)  |
//---------------------------------------
void UpdateLimit(State& s, ulong ticket, double limit, double newBet, bool stopOrders)
{
	MqlTradeRequest request;

	if (ticket>0)
	{
		// modifying a pending order
		ZeroMemory(request);
	   request.action = TRADE_ACTION_MODIFY;
		request.order = ticket;
		request.sl = 0;
		request.tp = 0;
		request.price = limit;
		executeOrder(request, __FUNCTION__);
	}
	else
	{
		// placing a pending order
		ZeroMemory(request);
	   request.action = TRADE_ACTION_PENDING;
		request.magic = s.agentMagic;
		request.symbol = s.symbol;
		request.volume = s.currPosSize + newBet;
		request.sl = 0;
		request.tp = 0;
		request.type_filling = ORDER_FILLING_IOC;
		request.price = limit;
		if (stopOrders)
		{
   		if (s.currPos == 1)
   		{
   			request.type = ORDER_TYPE_SELL_STOP;
   		}
   		else
   		{
   			request.type = ORDER_TYPE_BUY_STOP;
   		}
		}
		else
		{
   		if (s.currPos == 1)
   		{
   			request.type = ORDER_TYPE_SELL_LIMIT;
   		}
   		else
   		{
   			request.type = ORDER_TYPE_BUY_LIMIT;
   		}
		}
		executeOrder(request, __FUNCTION__);
	}
	
	return;
}

//-------------------------------------------
//|   PlaceOrder - placing an order (PLAT)  |
//-------------------------------------------
void PlaceOrder(State& s, int currPos, double bet)
{
	MqlTick last_tick;
	if(SymbolInfoTick(s.symbol, last_tick))
	{
		// placing an immediate order
		MqlTradeRequest request;
		ZeroMemory(request);
		request.action = TRADE_ACTION_DEAL;
		request.magic = s.agentMagic;
		request.symbol = s.symbol;
		request.volume = bet;
		request.sl = 0;
		request.tp = 0;
		if (currPos == 1)
		{
			request.price = last_tick.ask;
			request.type = ORDER_TYPE_BUY;
		}
		else
		{
			request.price = last_tick.bid;
			request.type = ORDER_TYPE_SELL;
		}
		executeOrder(request, __FUNCTION__);
	}
	else
	{
		Print(__FUNCTION__, "- SymbolInfoTick error: ", GetLastError());
	}
	return;
}

//---------------------------------
//|   Actual tick function (MIX)  |
//---------------------------------
void AgentOnTick(State& s)
{
   ulong ticket = 0;
	if(NewBar(s))
	{
   	double openPrice, openPrices[1];
   	CopyOpen(s.symbol, s.period, 0, 1, openPrices);
   	openPrice = openPrices[0];
   	if (s.history_oldest_item_idx == -1)
   	{
   	   CopyRates(s.symbol, s.period, 1, REQUIRED_HISTORY, s.history);
   	   s.history_oldest_item_idx = 0;
   	}
   	else
   	{
         MqlRates rates[1];
         CopyRates(s.symbol, s.period, 1, 1, rates);
         s.history[s.history_oldest_item_idx] = rates[0];
         s.history_oldest_item_idx = (s.history_oldest_item_idx + 1) % REQUIRED_HISTORY;
   	}
   	
      double D, newBet = Bet(s, openPrice);
   	if(s.currPos)
   	{
   		MqlRates rates = s.history[((s.history_oldest_item_idx)+REQUIRED_HISTORY-1)%REQUIRED_HISTORY];
   		double profit = NewProfit(s, s.currPos, s.currLimit, rates, s.history[((s.history_oldest_item_idx)+REQUIRED_HISTORY-2)%REQUIRED_HISTORY].close, s.currPosSize, D);
   		s.agentCash += profit;
   		UpdateQuality(s, s.q, profit, D);
//         int newPos = NewPos(s, s.currPos, s.history[(s.history_oldest_item_idx+REQUIRED_HISTORY-1)%REQUIRED_HISTORY], 1);
//         if (s.currPos != newPos)
         if ((ticket=OrderGetTicketWithMagic(s.agentMagic))==0)
         {
            s.currPos *= -1;
            s.currPosSize = s.pendPosSize;
            s.pendPosSize = newBet;
         }
   		s.currLimit = AdaptNewLimit(s, s.currPos, openPrice);
      }
      else
   	{
   		s.currPos = AdaptInitPos(s);
         s.currPosSize = newBet;
         s.pendPosSize = newBet;
   		PlaceOrder(s, s.currPos, newBet);
   	}
		UpdateLimit(s, ticket, s.currLimit, newBet, (s.mode == 0));
	}
}

//----------------------------------------------------
//|   Returns a new position (1=buy, -1=sell) (ALGO) |
//----------------------------------------------------
int NewPos(State& s, int currPos, double limit, MqlRates& rates)
{
   if (s.mode == 0)
   {
      // reverse on SL
	   if (currPos == -1)
	   {
	      if (rates.high >= limit)
	      {
	         currPos = 1;
	      }
	   }
	   else
	   {
	      // buy
	      if (rates.low <= limit)
	      {
	         currPos = -1;
	      }
	   }
   }
   else
   {
      // reverse on TP
	   if (currPos == 1)
	   {
	      if (rates.high >= limit)
	      {
	         currPos = -1;
	      }
	   }
	   else
	   {
	      // sell
	      if (rates.low <= limit)
	      {
	         currPos = 1;
	      }
	   }
   }
   return currPos;
}

//----------------------------------------------------------
//|   Returns the initial position (1=buy, -1=sell) (ALGO) |
//----------------------------------------------------------
int InitPos(State& s, int p)
{
	int currPos = 1;
	for (int i=0; i<DEPTH; i++)
	{
		MqlRates rates = s.history[((s.history_oldest_item_idx)+N+i)%REQUIRED_HISTORY];
		currPos = NewPos(s, currPos, NewLimit(s, s.tMode, currPos, rates.open, p, MAX_M + DEPTH-i), rates);
	}
	return currPos;
}

//-------------------------------------
//|   Returns the limit value (ALGO)  |
//-------------------------------------
double NewLimit(State&s, int tMode, int currPos, double openPrice, int p, int past)
{
   double limit;
	if (s.mode == 0)
	{
		if (currPos == 1)
		{
			limit = NormalizeDouble(Limit(s, tMode, openPrice, -1, p, past), s.digits);
		}
		else
		{
			limit = NormalizeDouble(Limit(s, tMode, openPrice, 1, p, past), s.digits);
		}
	}
	else
	{
		if (currPos == 1)
		{
			limit = NormalizeDouble(Limit(s, tMode, openPrice, 1, p, past), s.digits);
		}
		else
		{
			limit = NormalizeDouble(Limit(s, tMode, openPrice, -1, p, past), s.digits);
		}
	}
	return limit;
}

//-------------------------------------
//|   Returns the limit value (ALGO)  |
//-------------------------------------
double Limit(State& s, int tMode, double open, int dir, int p, int past)
{
   double x = 0;
   if (tMode == 2)
   {
      if (!s.tCalcTmp) s.tCalcTmp = open;
      if (dir == 1)
      {
         s.tCalcTmp = MathMin(s.tCalcTmp, open);
         return s.tCalcTmp + p * s.pip;
      }
      else
      {
         s.tCalcTmp = MathMax(s.tCalcTmp, open);
         return s.tCalcTmp - p * s.pip;
      }
   }
   else if (tMode == 1)
   {
	   for (int i=0; i<N; i++)
	   {
	      MqlRates rates = s.history[((s.history_oldest_item_idx)+REQUIRED_HISTORY-past-N+i)%REQUIRED_HISTORY];
	      x += rates.high - rates.low;
	   }
	   x = x / N * p / 100;
	   x = MathMax(x, s.minLimit * s.pip);
   }
   else if (tMode ==0)
   {
      x = p * s.pip;
   }
   if (dir == 1)
      return open + x;
   else
      return open - x;
}

//-------------------------------------------------
//|   Returns size of the position to open (ALGO) |
//-------------------------------------------------
double Bet(State& s, double open)
{
   double newBet;
   if (s.stupidity == -1)
   {
      newBet = 0.1;
   }
   else
   {
      double lots;
      double cash = ((100-Tax)/100.0) * s.agentCash + (Tax/100.0) * (AccountInfoDouble(ACCOUNT_BALANCE) / agentsNumber);
      if (s.pairDir == 0)
      {
         lots = cash / //agent's cash
            (100000 /*quantity*/ *
            ((open / 100 /* leverage */) + // deposit
            (s.avg + (5 /*- s.stupidity*/) * s.dev) * s.pip)); // safety buffer
      }
      else
      {
         lots = cash / //agent's cash
            (1000 + // deposit
            (100000 /*quantity*/ *
            (s.avg + (5 /*- s.stupidity*/) * s.dev) * s.pip) / open); // safety buffer
      }
      lots /= s.stupidity;
      newBet = MathMin(NormalizeDouble(lots, 2), 2.5);
      newBet = MathMax(newBet, 0.01);
   }
	return(newBet);
}

//-----------------------------------------
//|   Returns a new partial profit (ALGO) |
//-----------------------------------------
double NewProfit(State& s, int currPos, double limit, MqlRates& rates, double previousClose, double bet, double& D)
{
	double profit;
   if (s.mode == 0)
   {
      // reverse on SL
	   if (currPos == -1)
	   {
	      if (rates.high >= limit)
	      {
			  profit = (previousClose + rates.close) - 2 * limit - (rates.spread + SLIP) * s.pip;
			  D = MathMax(previousClose - rates.low, rates.high - previousClose);
	      }
		  else
		  {
			  profit = previousClose - rates.close;
			  D = MathMax(rates.high - previousClose, 0);
		  }
	   }
	   else
	   {
	      // buy
	      if (rates.low <= limit)
	      {
	          profit = 2 * limit - (previousClose + rates.close) - (rates.spread + SLIP) * s.pip;
			  D = MathMax(previousClose - rates.low, rates.high - previousClose);
	      }
		  else
		  {
			  profit = rates.close - previousClose;
			  D = MathMax(previousClose - rates.low, 0);
		  }
	   }
   }
   else
   {
      // reverse on TP
	   if (currPos == 1)
	   {
	      if (rates.high >= limit)
	      {
	          profit = 2 * limit - (previousClose + rates.close) - rates.spread * s.pip;
			  D = MathMax(previousClose - rates.low, rates.high - previousClose);
	      }
		  else
		  {
			  profit = rates.close - previousClose;
			  D = MathMax(previousClose - rates.low, 0);
		  }
	   }
	   else
	   {
	      // sell
	      if (rates.low <= limit)
	      {
			  profit = (previousClose + rates.close) - 2 * limit - rates.spread * s.pip;
			  D = MathMax(previousClose - rates.low, rates.high - previousClose);
	      }
		  else
		  {
			  profit = previousClose - rates.close;
			  D = MathMax(rates.high - previousClose, 0);
		  }
	   }
   }
	if (s.pairDir == 0)
	{
		D *= 100000 /*quantity*/ * bet;
		return profit * 100000 /*quantity*/ * bet;
	}
	else
	{
		D *= 100000 /*quantity*/ * bet / rates.close;
		return profit * 100000 /*quantity*/ * bet / rates.close;
	}
}

void UpdateQuality(State& s, Quality& q, double part_profit, double D)
{
	q.curr_profit += part_profit;
	if (q.curr_profit > q.curr_max)
		q.curr_max = q.curr_profit;
	if (s.qMode == 0)
	{
		if (q.curr_max - q.curr_profit > q.max_dd)
			q.max_dd = q.curr_max - q.curr_profit;
	}
	else
	{
		if (q.curr_max - q.curr_profit + D > q.max_dd)
			q.max_dd = q.curr_max - q.curr_profit + D;
	}
	q.quality = (q.curr_profit<0 ? -1 : 1) * log(MathAbs(q.curr_profit)+1) - s.w * log(q.max_dd + 1);
}

int AdaptInitPos(State& s)
{
	int currPos = 0;
	double profit, D;
	MqlRates rates = s.history[((s.history_oldest_item_idx)+N+DEPTH)%REQUIRED_HISTORY];
	for(int p=0; p<s.p_count; p++)
	{
		s.p_currPos[p] = InitPos(s, s.min_p + p);
		s.p_currLimit[p] = NewLimit(s, s.tMode, s.p_currPos[p], rates.open, s.min_p + p, MAX_M);
	}
	
	for(int m=0; m<MAX_M; m++)
	{
		rates = s.history[((s.history_oldest_item_idx)+N+DEPTH+m)%REQUIRED_HISTORY];
		for(int p=0; p<s.p_count; p++)
		{
			profit = NewProfit(s, s.p_currPos[p], s.p_currLimit[p], rates, s.history[((s.history_oldest_item_idx)+N+DEPTH+m-1)%REQUIRED_HISTORY].close, 0.1, D);
			for (int i=0; i<m+1; i++)
			{
				UpdateQuality(s, s.q_matrix[i*s.p_count + p], profit, D);
			}
			s.p_currPos[p] = NewPos(s, s.p_currPos[p], s.p_currLimit[p], rates);
			s.p_currLimit[p] = NewLimit(s, s.tMode, s.p_currPos[p], rates.open, s.min_p + p, MAX_M-m-1);
		}
	}
	double totalMaxQ = -1000000000;
	double mMaxQ;
	double pMaxQ[MAX_P]; //double* pMaxQ = (double*)malloc(s.p_count * sizeof(double));
	for(int x=0; x<s.p_count; x++) pMaxQ[x]=0; //memset(pMaxQ, 0, s.p_count * sizeof(double));
	for(int m=0; m<MAX_M; m++)
	{
		mMaxQ = -1000000000;
		for(int p=0; p<s.p_count; p++)
		{
			if (s.q_matrix[m * s.p_count + p].quality > mMaxQ)
			{
				mMaxQ = s.q_matrix[m * s.p_count + p].quality;
				s.m_currPos[MAX_M-m-1] = s.p_currPos[p];
				s.m_currLimit[MAX_M-m-1] = s.p_currLimit[p];
			}
			if (s.adaptMode == 0)
			{
				pMaxQ[p] += s.q_matrix[m * s.p_count + p].quality;
			}
		}
	}
	for(int p=0; p<s.p_count; p++)
	{
	   if (s.adaptMode == 2)
		{
			double alfa=0;
			for(int m=0; m<MAX_M; m++)
			{
				int j = (s.q_max_m_row+MAX_M-m-1)%MAX_M;
				alfa += (j+1) * s.q_matrix[m * s.p_count + p].curr_profit;
			}
			alfa *= 6;
			alfa /= (MAX_M * (MAX_M+1) * (2*MAX_M+1));
			double risk=0;
			for(int m=0; m<MAX_M; m++)
			{
				int j = (s.q_max_m_row+MAX_M-m-1)%MAX_M;
				risk += pow (alfa * (j+1) - s.q_matrix[m * s.p_count + p].curr_profit, 2);
			}
			pMaxQ[p] = alfa / pow(risk, s.w);
		}
		if (pMaxQ[p] > totalMaxQ)
		{
			totalMaxQ = pMaxQ[p];
			currPos = s.p_currPos[p];
			s.currLimit = s.p_currLimit[p];
		}
	}
//	free(pMaxQ);
	
	return currPos;
}

int int_round(double x)
{
   return int(x > 0.0 ? x + 0.5 : x - 0.5);
}

double AdaptNewLimit(State&s, int currPos, double openPrice)
{
	double limit, profit, D;
	for(int x=0;x<s.p_count;x++) {s.q_matrix[s.q_max_m_row * s.p_count+x].curr_max=0; s.q_matrix[s.q_max_m_row * s.p_count+x].curr_profit=0; s.q_matrix[s.q_max_m_row * s.p_count+x].max_dd=0; s.q_matrix[s.q_max_m_row * s.p_count+x].quality=0;} //	memset(&s.q_matrix[s.q_max_m_row * s.p_count], 0, s.p_count * sizeof(Quality));
	s.q_max_m_row = (s.q_max_m_row + 1) % MAX_M;

	MqlRates rates = s.history[((s.history_oldest_item_idx)+REQUIRED_HISTORY-1)%REQUIRED_HISTORY];
	for(int m=0; m<MAX_M; m++)
	{
		profit = NewProfit(s, s.m_currPos[m], s.m_currLimit[m], rates, s.history[((s.history_oldest_item_idx)+REQUIRED_HISTORY-2)%REQUIRED_HISTORY].close, 0.1, D);
		UpdateQuality(s, s.m_q[m], profit, D);
		s.m_currPos[m] = NewPos(s, s.m_currPos[m], s.m_currLimit[m], rates);
	}
	for(int p=0; p<s.p_count; p++)
	{
		profit = NewProfit(s, s.p_currPos[p], s.p_currLimit[p], rates, s.history[((s.history_oldest_item_idx)+REQUIRED_HISTORY-2)%REQUIRED_HISTORY].close, 0.1, D);
		UpdateQuality(s, s.p_q[p], profit, D);
		for (int i=0; i<MAX_M; i++)
		{
			UpdateQuality(s, s.q_matrix[i*s.p_count + p], profit, D);
		}
		s.p_currPos[p] = NewPos(s, s.p_currPos[p], s.p_currLimit[p], rates);
		s.p_currLimit[p] = NewLimit(s, s.tMode, s.p_currPos[p], openPrice, s.min_p + p, 0);
	}

	double totalMaxQ = -DBL_MAX;
	double mMaxQ;
	double pMaxQ[MAX_P]; //double* pMaxQ = (double*)malloc(s.p_count * sizeof(double));
	for(int x=0; x<s.p_count; x++) pMaxQ[x]=0; //memset(pMaxQ, 0, s.p_count * sizeof(double));
	for(int m=0; m<MAX_M; m++)
	{
		mMaxQ = -DBL_MAX;
		for(int p=0; p<s.p_count; p++)
		{
			if (s.q_matrix[m * s.p_count + p].quality > mMaxQ)
			{
				mMaxQ = s.q_matrix[m * s.p_count + p].quality;
				s.m_currLimit[(s.q_max_m_row+MAX_M-m-1)%MAX_M] = NewLimit(s, 0, s.m_currPos[(s.q_max_m_row+MAX_M-m-1)%MAX_M], openPrice, int_round(MathAbs((s.p_currLimit[p]-openPrice)/s.pip)), 0);
			}
			if (s.adaptMode == 0)
			{
				pMaxQ[p] += s.q_matrix[m * s.p_count + p].quality;
			}
		}
	}
	limit = NewLimit(s, 0, currPos, openPrice, int_round(MathAbs((s.p_currLimit[s.min_p+(s.p_count/2)]-openPrice)/s.pip)), 0); //so we have sth for this strange assert
	for(int p=0; p<s.p_count; p++)
	{
	   if (s.adaptMode == 2)
		{
			double alfa=0;
			for(int m=0; m<MAX_M; m++)
			{
				int j = (s.q_max_m_row+MAX_M-m-1)%MAX_M;
				alfa += (j+1) * s.q_matrix[m * s.p_count + p].curr_profit;
			}
			alfa *= 6;
			alfa /= (MAX_M * (MAX_M+1) * (2*MAX_M+1));
			double risk=0;
			for(int m=0; m<MAX_M; m++)
			{
				int j = (s.q_max_m_row+MAX_M-m-1)%MAX_M;
				risk += pow (alfa * (j+1) - s.q_matrix[m * s.p_count + p].curr_profit, 2);
			}
			pMaxQ[p] = alfa / pow(risk, s.w);
		}
		if (pMaxQ[p] > totalMaxQ)
		{
			totalMaxQ = pMaxQ[p];
			limit = NewLimit(s, 0, currPos, openPrice, int_round(MathAbs((s.p_currLimit[p]-openPrice)/s.pip)), 0);
		}
	}
//	free(pMaxQ);

	return limit;
}
