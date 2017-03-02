double NormalizeDouble(double a, int prec)
{
	return a;
}

double MathMin(double a, double b)
{
	return !(b<a)?a:b;
}

double MathMax(double a, double b)
{
	return (a<b)?b:a;
}

double MathAbs(double a)
{
	return (a<0)?-a:a;
}
