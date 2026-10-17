function b = battery_true_init(soc0)
% BATTERY_TRUE_INIT  The real battery at rest before takeoff.
b.soc = soc0;   % true state of charge (fraction)
b.V1  = 0;      % fast RC voltage (V) - zero after resting
b.V2  = 0;      % slow RC voltage (V)
end
