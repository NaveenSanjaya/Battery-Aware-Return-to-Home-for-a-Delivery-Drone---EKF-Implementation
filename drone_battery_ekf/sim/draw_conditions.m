function c = draw_conditions(p)
% DRAW_CONDITIONS  Random conditions for one Monte Carlo mission.
%   Every policy flies the same conditions, so the comparison is fair.
u = @(a, b) a + (b - a) * rand;

c.soc0  = u(0.60, 1.00);              % starting charge
c.bias  = u(-1.0, 1.0);               % current-sensor bias (A)
c.wind  = u(-0.20, 0.20);             % cruise needs -20%..+20% current
c.Cn    = p.true.Cn * u(0.80, 1.00);  % battery age: 80-100% of rated capacity
c.R0    = p.true.R0 * u(0.85, 1.15);  % the real battery's parameters vary too
c.R1    = p.true.R1 * u(0.85, 1.15);
c.C1    = p.true.C1 * u(0.85, 1.15);
c.R2    = p.true.R2 * u(0.85, 1.15);
end
