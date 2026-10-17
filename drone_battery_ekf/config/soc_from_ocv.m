function soc = soc_from_ocv(V, offset)
% SOC_FROM_OCV  Reverse lookup: resting voltage -> state of charge.
%   Used before takeoff, when the battery is at rest and V = OCV.
%   This gives the filter a sensible starting guess.

if nargin < 2, offset = 0; end
s   = linspace(0, 1, 1001);
soc = interp1(ocv_lookup(s, offset), s, V, 'linear', 'extrap');
soc = min(max(soc, 0), 1);
end
