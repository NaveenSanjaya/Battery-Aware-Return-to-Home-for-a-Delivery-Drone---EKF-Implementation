function p = battery_params()
% BATTERY_PARAMS  All battery and sensor numbers in one place.
%
%   p.filt : what the EKF BELIEVES (simple 1-RC model, nominal values)
%   p.true : the "real" battery in the simulator (2-RC model, values
%            deliberately a bit different, so the filter is tested honestly)
%   p.sens : sensor imperfections
%
% All battery values are PER CELL. The pack is 6 cells in series (6S),
% so the current is the same for every cell and pack voltage = 6 x cell.

p.Ns = 6;                      % cells in series
p.dt = 1;                      % time step (s)

% ---------- What the filter believes (nominal) ----------
p.filt.Cn         = 5.0;       % capacity (Ah)
p.filt.R0         = 0.008;     % ohmic resistance (ohm)
p.filt.R1         = 0.006;     % polarisation resistance (ohm)
p.filt.C1         = 5000;      % polarisation capacitance (F) -> tau = 30 s
p.filt.ocv_offset = 0;         % shift of the OCV curve (V)

% ---------- The "real" battery (truth) ----------
p.true.Cn         = 5.0;               % change this to test an aged battery
p.true.R0         = p.filt.R0 * 1.10;  % 10% higher than the filter thinks
p.true.R1         = p.filt.R1 * 0.90;  % 10% lower
p.true.C1         = p.filt.C1 * 1.10;  % 10% higher
p.true.R2         = 0.004;             % second, slow RC pair the filter
p.true.C2         = 100000;            %   does not know about (tau = 400 s)
p.true.ocv_offset = -0.005;            % real OCV curve sits 5 mV lower
p.true.V_cutoff   = 3.0;               % below this (per cell) = battery dead

% ---------- Sensors ----------
p.sens.bias = 0.5;             % current sensor reads 0.5 A too high (A)
p.sens.sigI = 0.2;             % current sensor noise (A, 1 sigma)
p.sens.sigV = 0.01;            % voltage sensor noise per cell (V, 1 sigma)
end
