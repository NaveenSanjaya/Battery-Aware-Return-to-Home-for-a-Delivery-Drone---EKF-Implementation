function [ps, margin, dsoc, sig_total] = p_safe_return(f, dist_home, I_cruise, m, rp)
% P_SAFE_RETURN  Probability of getting home with the reserve still left.
%
%   f         : EKF (stage C) with estimate f.x and uncertainty f.P
%   dist_home : distance to home (m)
%   I_cruise  : learned cruise current as measured (A)
%   m         : mission
%   rp        : RTH settings: rp.reserve (fraction), rp.trip_frac (fraction)
%
%   ps        : P(safe return) = Phi(margin / sig_total)
%   margin    : SoC estimate - charge needed - reserve
%   dsoc      : charge needed to get home (fraction)
%   sig_total : combined uncertainty of SoC and of the trip (fraction)

soc = f.x(1);  b = f.x(3);  Cn = f.x(4);
dsoc   = trip_soc(dist_home, I_cruise, b, Cn, m);
margin = soc - dsoc - rp.reserve;

sig_soc   = sqrt(f.P(1,1));          % from the EKF: how unsure is the SoC
sig_trip  = rp.trip_frac * dsoc;     % wind and load surprises on the way home
sig_total = sqrt(sig_soc^2 + sig_trip^2);

ps = 0.5 * erfc(-margin / (sqrt(2) * sig_total));   % normal CDF, base MATLAB
end
