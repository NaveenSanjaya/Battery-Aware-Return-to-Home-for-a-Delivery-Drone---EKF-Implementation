function M = flight_metrics(r, which)
% FLIGHT_METRICS  How well an estimator tracked the true SoC in one flight.
%
%   M = flight_metrics(rec, 'ekf')   the EKF estimate
%   M = flight_metrics(rec, 'cc')    the charge-counting estimate
%
%   M.rmse    : root-mean-square SoC error (fraction)
%   M.final   : error at landing (fraction, + = estimate too high)
%   M.maxabs  : largest error
%   M.inside  : fraction of time the truth was inside the EKF's +/-3 sigma
%   M.nis     : mean normalised innovation squared (about 1 = consistent)
%   M.nees    : mean normalised SoC error squared, e^2/P (about 1 = consistent)
%   M.conv    : last time (s) the error was 2% or more (0 = never)

if strcmp(which, 'cc'), est = r.soc_cc; else, est = r.x(1,:); end
e = est - r.soc;

M.rmse   = sqrt(mean(e.^2));
M.final  = e(end);
M.maxabs = max(abs(e));
bad = find(abs(e) >= 0.02, 1, 'last');
if isempty(bad), M.conv = 0; else, M.conv = r.t(bad); end

if strcmp(which, 'cc')
    M.inside = NaN;  M.nis = NaN;  M.nees = NaN;
else
    M.inside = mean(abs(e) <= 3*sqrt(r.Pd(1,:)));
    M.nis    = mean(r.nis);
    M.nees   = mean(e.^2 ./ r.Pd(1,:));
end
end
