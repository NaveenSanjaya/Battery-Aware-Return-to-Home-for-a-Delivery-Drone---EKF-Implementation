function [ocv, slope] = ocv_lookup(soc, offset)
% OCV_LOOKUP  Open-circuit voltage of one cell and its slope dOCV/dSoC.
%
%   [ocv, slope] = ocv_lookup(soc)          nominal curve
%   [ocv, slope] = ocv_lookup(soc, offset)  curve shifted by offset (V)
%
%   soc   : state of charge as a fraction (0..1), scalar or vector
%   ocv   : resting voltage (V)
%   slope : tangent slope (V per unit SoC) - this is H for the EKF
%
% The table is a representative Li-ion (NMC) curve: steep near empty,
% flatter in the middle. 'pchip' gives a smooth curve with no kinks, so
% the slope does not jump between table points.

if nargin < 2, offset = 0; end

soc_tab = [0 5 10 20 30 40 50 60 70 80 90 100] / 100;
ocv_tab = [3.30 3.45 3.55 3.63 3.68 3.73 3.78 3.85 3.93 4.00 4.08 4.18];

s   = min(max(soc, 0), 1);                         % stay inside the table
ocv = interp1(soc_tab, ocv_tab, s, 'pchip') + offset;

if nargout > 1                                      % slope by finite difference
    h  = 0.005;
    hi = min(s + h, 1);
    lo = max(s - h, 0);
    slope = (interp1(soc_tab, ocv_tab, hi, 'pchip') - ...
             interp1(soc_tab, ocv_tab, lo, 'pchip')) ./ (hi - lo);
end
end
