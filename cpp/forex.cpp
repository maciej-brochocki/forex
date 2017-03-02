// forex.cpp : Defines the entry point for the console application.
//
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "algo.h"

//#define OHLC_DUMP
#ifdef OHLC_DUMP
#define CSV_FORMAT "%d.%d.%d %d:%d:00,%lf,%lf,%lf,%lf,%ld"
#else
#define CSV_FORMAT "%d.%d.%d,%d:%d,%lf,%lf,%lf,%lf,%ld"
#endif

/* open - open price of new bar or 0 if no more bars */
void OnBar(State& s, double openPrice)
{
	double D, newBet = Bet(s, openPrice);
	if (s.currPos)
	{
		MqlRates& rates = s.history[((*s.history_oldest_item_idx)+REQUIRED_HISTORY-1)%REQUIRED_HISTORY];
		double profit = NewProfit(s, s.currPos, s.currLimit, rates, s.history[((*s.history_oldest_item_idx)+REQUIRED_HISTORY-2)%REQUIRED_HISTORY].close, s.currPosSize, D);
		s.agentCash += profit;
		UpdateQuality(s, s.q, profit, D);
		int newPos = NewPos(s, s.currPos, s.currLimit, rates);
		if (s.currPos != newPos)
		{
			s.currPos = newPos;
			s.currPosSize = s.pendPosSize;
            s.pendPosSize = newBet;
			s.currLimit = 0;
		}
#ifdef PRINT_PLAYRES
		if (!s.mode)
			printf("%lf,%lf,%lf,%lf,%lf,%d,%lf,", rates.open, rates.high, rates.low, rates.close, s.currLimit, s.currPos, profit);
		else
			printf("%lf,%d,%lf\n", s.currLimit, s.currPos, profit);
#endif
		s.currLimit = AdaptNewLimit(s, s.currPos, openPrice, s.currLimit);
		if (!openPrice)
		{
			if (!s.mode)
				printf("ProTrend\n");
			else
				printf("\n\n\nAntyTrend\n");
			double avgCG, avgMDD, avgQ, stability;
			printf("\nBasic strategy\n");
#ifdef PRINT_P_M_RES
			printf("p,CG,MDD,q\n");
#endif
			avgCG = 0; avgMDD=0; stability=0;
			for (int p=0; p<s.p_count; p++)
			{
#ifdef PRINT_P_M_RES
				printf("%d,%lf,%lf,%lf\n", s.min_p+p, s.p_q[p].curr_profit, s.p_q[p].max_dd, s.p_q[p].quality);
#endif
				avgCG+=s.p_q[p].curr_profit; avgMDD+=s.p_q[p].max_dd;
				if (p>0) stability+=MathAbs(s.p_q[p].curr_profit-s.p_q[p-1].curr_profit);
			}
			printf("avgCG,avgMDD,q,diffmod\n%lf,%lf,%lf,%lf\n", avgCG/s.p_count, avgMDD/s.p_count, avgCG/avgMDD, stability/(s.p_count-1));
			printf("\n1-lvl adaptation results:\n");
#ifdef PRINT_P_M_RES
			printf("m,CG,MDD,q\n");
#endif
			avgCG = 0; avgMDD=0; avgQ=0; stability=0;
			for (int m=0; m<MAX_M; m++)
			{
#ifdef PRINT_P_M_RES
				printf("%d,%lf,%lf,%lf\n", m+1, s.m_q[m].curr_profit, s.m_q[m].max_dd, s.m_q[m].quality);
#endif
				avgCG+=s.m_q[m].curr_profit; avgMDD+=s.m_q[m].max_dd;
				if (m>0) stability+=MathAbs(s.m_q[m].curr_profit-s.m_q[m-1].curr_profit);
			}
			printf("avgCG,avgMDD,q,diffmod\n%lf,%lf,%lf,%lf\n", avgCG/MAX_M, avgMDD/MAX_M, avgCG/avgMDD, stability/(MAX_M-1));
			printf("\n2-lvl adaptation result:\nCG,MDD,q\n%lf,%lf,%lf\n", s.q.curr_profit, s.q.max_dd, s.q.curr_profit/s.q.max_dd);
		}
	}
	else
	{
		s.currPos = AdaptInitPos(s, openPrice);
		s.currPosSize = newBet;
        s.pendPosSize = newBet;
#ifdef PRINT_PLAYRES
		if (!s.mode)
			printf("%d,", s.currPos);
		else
			printf("%d\nO,H,L,C,lim,pos,prof,lim_TP,pos_TP,prof_TP\n", s.currPos);
#endif
	}
}

int ReadLine(FILE* f, MqlRates& rate)
{
	char line[256];
	int tmp[5];

	if (!fgets(line, 256, f))
		return -1;
	if (sscanf(line, CSV_FORMAT, &tmp[0], &tmp[1], &tmp[2], &tmp[3], &tmp[4],
		&rate.open, &rate.high, &rate.low, &rate.close, &rate.real_volume) != 10)
		return -1;
	return 0;
}

char* pairs[PAIRS] = {"EURUSD", "GBPUSD", "USDCHF", "USDJPY", "AUDUSD", "NZDUSD"};
int main(int argc, char* argv[])
{
	int sym, per;
	char filename[16];
	FILE* f;
	State* s;
	MqlRates rate;
	MqlRates history[REQUIRED_HISTORY];
	int history_oldest_item_idx = -1;

	if (argc != 8)
	{
		printf ("Too few parameters, syntax:\n");
		printf ("forex symbol period tMode stupidity\n");
		printf ("  symbol: 0-EURUSD / 1-GBPUSD / 2-USDCHF / 3-USDJPY / 4-AUDUSD / 5-NZDUSD\n");
		printf ("  period: 1 / 5 / 15 / 30 / 60 / 240 / 1440 / 10080 / 43200\n");
		printf ("  tMode: T is const(0)/avg. of N bars (1) | dynamic(0)/trailing(2)\n");
		printf ("  qMode: CG/(MDD+1)^W (0) CG/(MDD+D)^W (1)\n");
		printf ("  W: power of risk ;)\n");
		printf ("  adaptMode: AVG(0) MED(1) linReg(2)\n");
		printf ("  stupidity: stupidity level (0-4) or MM off (-1)\n");
		exit(-1);
	}
	sym = atoi(argv[1]);
	per = atoi(argv[2]);
	sprintf(filename, "%s%d.csv", pairs[sym], per);

	if ((f = fopen(filename, "r")) == NULL)
	{
		printf ("Error opening file\n");
		exit(-1);
	}

	s = (State*)malloc(2 * sizeof(State));
	for (int i=0; i<2; i++)
	{
		s[i].history = history;
		s[i].history_oldest_item_idx = &history_oldest_item_idx;
		InitAgentData(s[i], sym, per, i%2, atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), atoi(argv[6]), atoi(argv[7]));
	}

	//build history
	for (int i=0; i<REQUIRED_HISTORY; i++)
	{
		if (ReadLine(f, history[i]))
		{
			printf("Error: not enough lines in CSV to build history\n");
			exit(-2);
		}
	}
	history_oldest_item_idx = 0;
	while (!ReadLine(f, rate))
	{
		for (int i=0; i<2; i++)
		{
			OnBar(s[i], rate.open);
		}
		memcpy(&history[history_oldest_item_idx], &rate, sizeof(rate));
		history_oldest_item_idx = (history_oldest_item_idx + 1) % REQUIRED_HISTORY;
	}
	for (int i=0; i<2; i++)
	{
		OnBar(s[i], 0);
	}

	free(s);
	fclose(f);
	return 0;
}
