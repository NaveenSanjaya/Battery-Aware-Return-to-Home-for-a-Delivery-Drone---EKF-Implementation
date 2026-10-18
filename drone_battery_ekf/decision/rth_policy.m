function [go_home, low_count] = rth_policy(policy, s, rp)
% RTH_POLICY  The four turn-back rules. Returns true when the drone should go home.
%
%   policy : 'A' voltage threshold
%            'B' charge counting + margin rule
%            'C' EKF estimate + margin rule (ignores uncertainty)
%            'D' EKF risk-aware: P(safe return) below a threshold
%   s      : what the drone knows this second (fields used below)
%   rp     : settings (rp.V_thr, rp.V_hold, rp.reserve, rp.p_thr)

low_count = s.low_count;
switch policy
    case 'A'   % voltage stays below the threshold for V_hold seconds
        if s.Vm < rp.V_thr, low_count = low_count + 1; else, low_count = 0; end
        go_home = low_count >= rp.V_hold;
    case 'B'   % charge counting says the margin is gone
        go_home = s.soc_cc - s.dsoc_cc - rp.reserve < 0;
    case 'C'   % EKF estimate says the margin is gone
        go_home = s.margin < 0;
    case 'D'   % EKF is no longer sure enough of getting home with the reserve
        go_home = s.ps < rp.p_thr;
    otherwise
        error('Unknown policy "%s".', policy);
end
end
