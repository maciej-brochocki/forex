#include "algo.h"
#include <stdlib.h>
#include <string.h>
#include <float.h>
#include <math.h>
#include <vector>
#include <algorithm>
using namespace std;

//----------------------------------
//|   Init helper function (ALGO)  |
//----------------------------------
static int digits[PAIRS] = {4, 4, 4, 2, 4, 4};  //EURUSD, GBPUSD, USDCHF, USDJPY, AUDUSD, NZDUSD
static int spread[PAIRS] = {2, 2, 2, 1, 3, 4};
static int minLimit[PAIRS] = {10, 10, 10, 10, 10, 10}; //EURUSD, GBPUSD, USDCHF, USDJPY, AUDUSD, NZDUSD
static int pairDir[PAIRS] = {0, 0, 1, 1, 0, 0};
#ifdef STATS_5PIPS
static int avg[PAIRS][9] = {
   {23, 65, 108, 151, 192, 372, 944, 2151, 4394},
   {22, 42, 77, 112, 154, 410, 1045, 2607, 5267},
   {17, 47, 82, 125, 199, 425, 1093, 2446, 4939},
   {8, 27, 62, 113, 166, 340, 858, 1930, 3923},
   {0, 0, 0, 0, 0, 0, 0, 1427, 0},
   {0, 0, 0, 0, 0, 0, 0, 1162, 0},
};
static int dev[PAIRS][9] = {
   {20, 50, 80, 125, 150, 276, 559, 1204, 2713},
   {19, 44, 65, 91, 122, 285, 656, 1581, 2953},
   {16, 45, 71, 107, 153, 319, 630, 1283, 2362},
   {7, 30, 56, 101, 128, 249, 538, 1096, 1933},
   {0, 0, 0, 0, 0, 0, 0, 1027, 0},
   {0, 0, 0, 0, 0, 0, 0, 881, 0},
};
#else
static int avg[PAIRS][9] = {
   {2, 7, 11, 15, 19, 37, 94, 215, 439},
   {2, 4, 8, 11, 15, 41, 105, 261, 527},
   {2, 5, 8, 13, 20, 43, 109, 245, 494},
   {1, 3, 6, 11, 17, 34, 86, 193, 392},
   {0, 0, 0, 0, 0, 0, 0, 143, 0},
   {0, 0, 0, 0, 0, 0, 0, 116, 0},
};
static int dev[PAIRS][9] = {
   {2, 5, 8, 13, 15, 28, 56, 120, 271},
   {2, 4, 7, 9, 12, 29, 66, 158, 295},
   {2, 5, 7, 11, 15, 32, 63, 128, 236},
   {1, 3, 6, 10, 13, 25, 54, 110, 193},
   {0, 0, 0, 0, 0, 0, 0, 103, 0},
   {0, 0, 0, 0, 0, 0, 0, 88, 0},
};
#endif
void InitAgentData(State& s, int sym, int period, int m, int tM, int qM, int w, int aM, int stup)
{
	s.digits = digits[sym];
	s.spread = spread[sym];
	s.pip = 1;
	for (int i=0; i<s.digits; i++)
	{
	   s.pip = s.pip / 10;
	}
   int per;
   switch(period) {
      case 1: per = 0; break;
      case 5: per = 1; break;
      case 15: per = 2; break;
      case 30: per = 3; break;
      case 60: per = 4; break;
      case 240: per = 5; break;
      case 1440: per = 6; break;
      case 10080: per = 7; break;
      case 43200: per = 8; break;
   }
   s.minLimit = minLimit[sym];
   s.pairDir = pairDir[sym];
   s.avg = avg[sym][per];
   s.dev = dev[sym][per];
   s.currPos = 0;
   s.currPosSize = 0;
   s.currLimit = 0;
   s.mode = m;
   s.tMode = tM;
   s.qMode = qM;
   s.w = w;
   s.adaptMode = aM;
   s.stupidity = stup;
   s.agentCash = 10000;
   memset(&s.q, 0, sizeof(Quality));
   // adaptation
   if (s.tMode & 1)
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
   s.q_matrix = (Quality*)malloc(s.p_count * MAX_M * sizeof(Quality));
   memset(s.q_matrix, 0, s.p_count * MAX_M * sizeof(Quality));
   s.q_max_m_row = 0;
   s.p_currPos = (int*)malloc(s.p_count * sizeof(int));
   memset(s.p_currPos, 0, s.p_count * sizeof(int));
   s.p_currLimit = (double*)malloc(s.p_count * sizeof(double));
   memset(s.p_currLimit, 0, s.p_count * sizeof(double));
   s.p_q = (Quality*)malloc(s.p_count * sizeof(Quality));
   memset(s.p_q, 0, s.p_count * sizeof(Quality));
   memset(s.m_currPos, 0, MAX_M * sizeof(int));
   memset(s.m_currLimit, 0, MAX_M * sizeof(double));
   memset(s.m_q, 0, MAX_M * sizeof(Quality));
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
	int currPos = 1, lastPos;
	double lastLimit=0;
	for (int i=0; i<DEPTH; i++)
	{
		MqlRates& rates = s.history[((*s.history_oldest_item_idx)+N+i)%REQUIRED_HISTORY];
		lastLimit=NewLimit(s, s.tMode, currPos, rates.open, p, MAX_M + DEPTH-i, lastLimit);
		lastPos = currPos;
		currPos = NewPos(s, currPos, lastLimit, rates);
		if (lastPos != currPos)
		{
			lastLimit=0;
		}
	}
	return currPos;
}

//-------------------------------------
//|   Returns the limit value (ALGO)  |
//-------------------------------------
double NewLimit(State&s, int tMode, int currPos, double openPrice, int p, int past, double lastLimit)
{
   double limit;
	if (s.mode == 0)
	{
		if (currPos == 1)
		{
			limit = NormalizeDouble(Limit(s, tMode, openPrice, -1, p, past, lastLimit), s.digits);
		}
		else
		{
			limit = NormalizeDouble(Limit(s, tMode, openPrice, 1, p, past, lastLimit), s.digits);
		}
	}
	else
	{
		if (currPos == 1)
		{
			limit = NormalizeDouble(Limit(s, tMode, openPrice, 1, p, past, lastLimit), s.digits);
		}
		else
		{
			limit = NormalizeDouble(Limit(s, tMode, openPrice, -1, p, past, lastLimit), s.digits);
		}
	}
	return limit;
}

//-------------------------------------
//|   Returns the limit value (ALGO)  |
//-------------------------------------
double Limit(State& s, int tMode, double open, int dir, int p, int past, double lastLimit)
{
   double x = 0, newLimit;
   if (tMode & 1)
   {
	   for (int i=0; i<N; i++)
	   {
	      MqlRates& rates = s.history[((*s.history_oldest_item_idx)+REQUIRED_HISTORY-past-N+i)%REQUIRED_HISTORY];
	      x += rates.high - rates.low;
	   }
	   x = x / N * p / 100;
	   x = MathMax(x, s.minLimit * s.pip);
   }
   else
   {
      x = p * s.pip;
   }
   if (dir == 1)
      newLimit = open + x;
   else
      newLimit = open - x;
   if ((tMode & 2) && lastLimit)
   {
	   if (dir == 1)
		   newLimit = MathMin(newLimit, lastLimit);
	   else
		   newLimit = MathMax(newLimit, lastLimit);
   }
   return newLimit;
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
      if (s.pairDir == 0)
      {
         lots = (s.agentCash) / //agent's cash
            (100000 /*quantity*/ *
            ((open / 100 /* leverage */) + // deposit
            (s.avg + (5 - s.stupidity) * s.dev) * s.pip)); // safety buffer
      }
      else
      {
         lots = (s.agentCash) / //agent's cash
            (1000 + // deposit
            (100000 /*quantity*/ *
            (s.avg + (5 - s.stupidity) * s.dev) * s.pip) / open); // safety buffer
      }
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
	      if (limit < rates.open)
			  printf("!");
	      if (rates.high >= limit)
	      {
			  profit = (previousClose + rates.close) - 2 * limit - (s.spread + 2 * SLIP) * s.pip;
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
	      if (limit > rates.open)
			  printf("!");
	      // buy
	      if (rates.low <= limit)
	      {
	          profit = 2 * limit - (previousClose + rates.close) - (s.spread + 2 * SLIP) * s.pip;
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
	      if (limit < rates.open)
			  printf("!");
	      if (rates.high >= limit)
	      {
	          profit = 2 * limit - (previousClose + rates.close) - s.spread * s.pip;
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
	      if (limit > rates.open)
			  printf("!");
	      // sell
	      if (rates.low <= limit)
	      {
			  profit = (previousClose + rates.close) - 2 * limit - s.spread * s.pip;
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

int AdaptInitPos(State& s, double openPrice)
{
	int currPos = 0, lastPos;
	double profit, D;
	MqlRates& rates = s.history[((*s.history_oldest_item_idx)+N+DEPTH)%REQUIRED_HISTORY];
	for(int p=0; p<s.p_count; p++)
	{
		s.p_currPos[p] = InitPos(s, s.min_p + p);
		s.p_currLimit[p] = NewLimit(s, s.tMode, s.p_currPos[p], rates.open, s.min_p + p, MAX_M, s.p_currLimit[p]);
	}
	
	for(int m=0; m<MAX_M; m++)
	{
		for(int p=0; p<s.p_count; p++)
		{
			profit = NewProfit(s, s.p_currPos[p], s.p_currLimit[p], rates, s.history[((*s.history_oldest_item_idx)+N+DEPTH+m-1)%REQUIRED_HISTORY].close, 0.1, D);
			for (int i=0; i<m+1; i++)
			{
				UpdateQuality(s, s.q_matrix[i*s.p_count + p], profit, D);
			}
			lastPos = s.p_currPos[p];
			s.p_currPos[p] = NewPos(s, s.p_currPos[p], s.p_currLimit[p], rates);
			if (lastPos != s.p_currPos[p])
			{
				s.p_currLimit[p] = 0;
			}
		}
		rates = s.history[((*s.history_oldest_item_idx)+N+DEPTH+m+1)%REQUIRED_HISTORY];
		for(int p=0; p<s.p_count; p++)
		{
			if (m+1 < MAX_M)
			{
				s.p_currLimit[p] = NewLimit(s, s.tMode, s.p_currPos[p], rates.open, s.min_p + p, MAX_M-m-1, s.p_currLimit[p]);
			}
			else
			{
				s.p_currLimit[p] = NewLimit(s, s.tMode, s.p_currPos[p], openPrice, s.min_p + p, MAX_M-m-1, s.p_currLimit[p]);
			}
		}
	}
	double totalMaxQ = -1000000000;
	double mMaxQ;
	double* pMaxQ = (double*)malloc(s.p_count * sizeof(double));
	memset(pMaxQ, 0, s.p_count * sizeof(double));
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
	vector<double> pQ;
	for(int p=0; p<s.p_count; p++)
	{
		if (s.adaptMode == 1)
		{
			for(int m=0; m<MAX_M; m++)
			{
				pQ.push_back(s.q_matrix[m * s.p_count + p].quality);
			}
			sort(pQ.begin(), pQ.end());
			pMaxQ[p] = pQ[MAX_M/2];
			pQ.clear();
		} else if (s.adaptMode == 2)
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
	free(pMaxQ);
	
	return currPos;
}

inline int round(double x)
{
   return int(x > 0.0 ? x + 0.5 : x - 0.5);
}

double AdaptNewLimit(State&s, int currPos, double openPrice, double lastLimit)
{
	double limit, profit, D, lastLimits[MAX_M];
	int lastPos;
	memset(&s.q_matrix[s.q_max_m_row * s.p_count], 0, s.p_count * sizeof(Quality));
	s.q_max_m_row = (s.q_max_m_row + 1) % MAX_M;

	MqlRates& rates = s.history[((*s.history_oldest_item_idx)+REQUIRED_HISTORY-1)%REQUIRED_HISTORY];
	for(int m=0; m<MAX_M; m++)
	{
		profit = NewProfit(s, s.m_currPos[m], s.m_currLimit[m], rates, s.history[((*s.history_oldest_item_idx)+REQUIRED_HISTORY-2)%REQUIRED_HISTORY].close, 0.1, D);
		UpdateQuality(s, s.m_q[m], profit, D);
		lastPos = s.m_currPos[m];
		s.m_currPos[m] = NewPos(s, s.m_currPos[m], s.m_currLimit[m], rates);
		if (lastPos != s.m_currPos[m])
		{
			lastLimits[m] = 0;
		}
		else
		{
			lastLimits[m] = s.m_currLimit[m];
		}
	}
	for(int p=0; p<s.p_count; p++)
	{
		profit = NewProfit(s, s.p_currPos[p], s.p_currLimit[p], rates, s.history[((*s.history_oldest_item_idx)+REQUIRED_HISTORY-2)%REQUIRED_HISTORY].close, 0.1, D);
		UpdateQuality(s, s.p_q[p], profit, D);
		for (int i=0; i<MAX_M; i++)
		{
			UpdateQuality(s, s.q_matrix[i*s.p_count + p], profit, D);
		}
		lastPos = s.p_currPos[p];
		s.p_currPos[p] = NewPos(s, s.p_currPos[p], s.p_currLimit[p], rates);
		if (lastPos != s.p_currPos[p])
		{
			s.p_currLimit[p] = 0;
		}
		s.p_currLimit[p] = NewLimit(s, s.tMode, s.p_currPos[p], openPrice, s.min_p + p, 0, s.p_currLimit[p]);
	}

	double totalMaxQ = -DBL_MAX;
	double mMaxQ;
	double* pMaxQ = (double*)malloc(s.p_count * sizeof(double));
	memset(pMaxQ, 0, s.p_count * sizeof(double));
	for(int m=0; m<MAX_M; m++)
	{
		mMaxQ = -DBL_MAX;
		for(int p=0; p<s.p_count; p++)
		{
			if (s.q_matrix[m * s.p_count + p].quality > mMaxQ)
			{
				mMaxQ = s.q_matrix[m * s.p_count + p].quality;
				s.m_currLimit[(s.q_max_m_row+MAX_M-m-1)%MAX_M] = NewLimit(s, 0, s.m_currPos[(s.q_max_m_row+MAX_M-m-1)%MAX_M], openPrice, round(MathAbs((s.p_currLimit[p]-openPrice)/s.pip)), 0, lastLimits[(s.q_max_m_row+MAX_M-m-1)%MAX_M]);
			}
			if (s.adaptMode == 0)
			{
				pMaxQ[p] += s.q_matrix[m * s.p_count + p].quality;
			}
		}
	}
	limit = 0;
	vector<double> pQ;
	for(int p=0; p<s.p_count; p++)
	{
		if (s.adaptMode == 1)
		{
			for(int m=0; m<MAX_M; m++)
			{
				pQ.push_back(s.q_matrix[m * s.p_count + p].quality);
			}
			sort(pQ.begin(), pQ.end());
			pMaxQ[p] = pQ[MAX_M/2];
			pQ.clear();
		} else if (s.adaptMode == 2)
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
			limit = NewLimit(s, 0, currPos, openPrice, round(MathAbs((s.p_currLimit[p]-openPrice)/s.pip)), 0, lastLimit);
		}
	}
	free(pMaxQ);

	if (!limit)
	{
		limit = NewLimit(s, 0, currPos, openPrice, round(MathAbs((s.p_currLimit[s.min_p+(s.p_count/2)]-openPrice)/s.pip)), 0, lastLimit); //so we have sth for this strange assert
		printf("?");
	}
	return limit;
}
