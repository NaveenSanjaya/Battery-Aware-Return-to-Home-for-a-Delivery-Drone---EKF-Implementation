function f = ekf_init(p, stage, soc0, sig_soc0)
% EKF_INIT  Set up the filter: starting guess, starting uncertainty, tuning.
%
%   f = ekf_init(p, stage, soc0, sig_soc0)
%
%   p        : parameters from battery_params (the filter uses p.filt only)
%   stage    : which states the filter is allowed to learn
%              'A' -> SoC, V1                         (basic EKF)
%              'B' -> SoC, V1, R0                     (main filter: also learns resistance)
%              'C' -> SoC, V1, R0, bias b, capacity Cn (everything)
%   soc0     : starting SoC guess (fraction)
%   sig_soc0 : how unsure we are about that guess (1 sigma, fraction)
%
% The state is always x = [SoC; V1; b; Cn; R0]. States a stage does not
% learn are frozen at their nominal values (zero uncertainty and zero
% process noise), which is the same as leaving them out of the filter.

f.stage = upper(stage);

% What the filter believes about the battery
f.R1 = p.filt.R1;   f.C1 = p.filt.C1;
f.ocv_offset = p.filt.ocv_offset;

% Noise settings
f.sigI = p.sens.sigI;                               % current sensor noise (A)
f.Rv   = p.sens.sigV^2 ...                          % voltage sensor noise
       + (p.filt.R0 * p.sens.sigI)^2 ...            % current noise seen through R0
       + p.filt.sig_model^2;                        % allowance for model error (V^2)

% Starting guess and uncertainty (1 sigma) for [SoC, V1, b, Cn, R0]
x0  = [soc0; 0; 0; p.filt.Cn; p.filt.R0];
sd0 = [sig_soc0, 0.01, 1.0, 0.5, 0.004];            % SoC, 10 mV, 1 A, 0.5 Ah, 4 mOhm

% Process noise per step: how much each state may drift in ways the
% model does not explain (variances)
q = [1e-8, 1e-6, 1e-6, 1e-7, 1e-9];

switch f.stage
    case 'A', learn = [1 1 0 0 0];
    case 'B', learn = [1 1 0 0 1];
    case 'C', learn = [1 1 1 1 1];
    otherwise, error('Stage must be ''A'', ''B'' or ''C''.');
end
sd0(~learn) = 0;
q(~learn)   = 0;

f.learn = logical(learn);
f.x = x0;
f.P = diag(sd0.^2);
f.q = q;
end
