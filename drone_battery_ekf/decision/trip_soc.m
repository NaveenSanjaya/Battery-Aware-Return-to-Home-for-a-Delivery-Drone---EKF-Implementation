function dsoc = trip_soc(dist_home, I_cruise, b, Cn, m)
% TRIP_SOC  Charge (as a fraction of SoC) needed to fly home and land.
%
%   dist_home : straight-line distance to home (m)
%   I_cruise  : cruise current as the SENSOR reads it (A), learned in flight
%   b         : estimated current-sensor bias (A); 0 if unknown
%   Cn        : capacity to divide by (Ah)
%   m         : mission (speed, landing time and current)
%
% The cruise part uses the same drain rate the filter uses, (I - b)/Cn,
% because that combination is what the voltage makes observable (Day 4).
% I_cruise is a MEASURED current, so the bias is removed from it; the
% landing current m.I_land is a nominal TRUE current, so it is used as is.

t_cruise = dist_home / m.v_cruise;                      % s
charge   = (I_cruise - b) * t_cruise + m.I_land * m.T_land;   % A*s
dsoc     = charge / (3600 * Cn);
end
