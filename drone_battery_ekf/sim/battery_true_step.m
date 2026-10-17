function [b, V] = battery_true_step(b, I, pt, dt)
% BATTERY_TRUE_STEP  The "real" battery: a 2-RC model, one time step.
%
%   b  : battery state (soc, V1, V2)
%   I  : true current drawn during this step (A, positive = discharge)
%   pt : true parameters (p.true from battery_params)
%   V  : terminal voltage of one cell at the END of the step (V)
%
% This model is deliberately richer than the filter's 1-RC model.

a1 = exp(-dt / (pt.R1 * pt.C1));
a2 = exp(-dt / (pt.R2 * pt.C2));

b.soc = b.soc - I * dt / (3600 * pt.Cn);
b.V1  = a1 * b.V1 + pt.R1 * (1 - a1) * I;
b.V2  = a2 * b.V2 + pt.R2 * (1 - a2) * I;

V = ocv_lookup(b.soc, pt.ocv_offset) - pt.R0 * I - b.V1 - b.V2;
end
