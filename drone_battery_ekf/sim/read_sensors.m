function [Im, Vm] = read_sensors(I, V, ps)
% READ_SENSORS  What the drone's sensors report (imperfect).
%
%   I, V : true current (A) and true cell voltage (V)
%   ps   : sensor settings (p.sens from battery_params)
%   Im   : measured current = true + constant bias + noise
%   Vm   : measured cell voltage = true + noise

Im = I + ps.bias + ps.sigI * randn;
Vm = V + ps.sigV * randn;
end
