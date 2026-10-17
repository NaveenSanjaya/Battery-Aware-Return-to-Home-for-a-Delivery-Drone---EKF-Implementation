%% Day 1 - The EKF by hand (SoC only)
% Goal: understand predict, update and the Kalman gain K with real numbers.
% Run one section at a time (Ctrl+Enter). Change numbers and re-run.
%
% Simplifications for Day 1 (all removed later):
%   - one state only: SoC
%   - no R1-C1 polarisation, no bias state, known capacity

clear; clc; close all;

%% Part 1: one predict + update step (matches the hand calculation)
dt    = 10;       % s   (10 s so the SoC change is easy to see)
Cn    = 5;        % Ah  battery capacity
R0    = 0.008;    % ohm internal resistance
Q     = 1e-6;     % process noise: how much we distrust the model (SoC^2)
R     = 0.01^2;   % measurement noise: 10 mV voltage sensor (V^2)

% Near 79% SoC the OCV curve is roughly a straight line through
% (70%, 3.93 V) with slope 0.7 V per unit SoC (= 7 mV per 1% SoC).
ocv_lin   = @(s) 3.93 + 0.7*(s - 0.70);
slope_lin = @(s) 0.7;

soc = 0.80;       % current guess: 80%
P   = 0.05^2;     % current uncertainty: +/-5% (1 sigma)
Im  = 20;         % measured current (A)
Vm  = 3.80;       % measured voltage (V)

[soc_new, P_new, d] = ekf_step_1d(soc, P, Im, Im, Vm, dt, Cn, R0, Q, R, ocv_lin, slope_lin);
print_step(soc, P, d);

%% Part 2: turn the knobs - how does K react?
% Same step, three situations. Watch K, the new SoC and the new sigma.
cases = { 'Baseline (10 mV sensor, +/-5% guess)', 0.05^2, 0.01^2;
          'Noisy sensor (50 mV)',                  0.05^2, 0.05^2;
          'Confident guess (+/-1%)',               0.01^2, 0.01^2 };

fprintf('\n%-38s %8s %10s %10s\n', 'Situation', 'K', 'new SoC', 'new sigma');
for i = 1:size(cases, 1)
    [s_i, P_i, d_i] = ekf_step_1d(soc, cases{i,2}, Im, Im, Vm, dt, Cn, R0, Q, cases{i,3}, ocv_lin, slope_lin);
    fprintf('%-38s %8.3f %9.2f%% %9.2f%%\n', cases{i,1}, d_i.K, 100*s_i, 100*sqrt(P_i));
end
fprintf(['\nLesson: K is big when we are unsure of our guess and trust the sensor;\n' ...
         'K is small when the sensor is noisy or we are already confident.\n']);

%% Part 3: a 10-minute discharge - EKF vs charge counting
% Truth: battery really starts at 75%. Both estimators wrongly think 80%.
% The current sensor also reads 0.3 A too high (bias).
rng(1);                                   % same random numbers every run

soc_tab = [0 5 10 20 30 40 50 60 70 80 90 100] / 100;
ocv_tab = [3.30 3.45 3.55 3.63 3.68 3.73 3.78 3.85 3.93 4.00 4.08 4.18];
ocv_fun   = @(s) interp1(soc_tab, ocv_tab, min(max(s, 0), 1), 'linear');
slope_fun = @(s) (ocv_fun(min(s + 0.005, 1)) - ocv_fun(max(s - 0.005, 0))) ...
                 / (min(s + 0.005, 1) - max(s - 0.005, 0));

dt   = 1;  N = 600;                       % 1 s steps, 10 minutes
I    = 15 * ones(1, N);                   % true current (A)
bias = 0.3;  sigI = 0.2;  sigV = 0.01;    % sensor errors

% --- Simulate the truth and the sensors ---
soc_true = zeros(1, N);  soc_true(1) = 0.75;
for k = 2:N
    soc_true(k) = soc_true(k-1) - I(k-1)*dt/(3600*Cn);
end
Im = I + bias + sigI*randn(1, N);                           % measured current
Vm = ocv_fun(soc_true) - R0*I + sigV*randn(1, N);           % measured voltage

% --- Run the EKF and charge counting ---
Q = (dt/(3600*Cn))^2 * sigI^2 + 1e-9;     % current noise pushed through the model
R = sigV^2;
soc_ekf = zeros(1, N);  P_ekf = zeros(1, N);  K_ekf = zeros(1, N);
soc_cc  = zeros(1, N);
soc_ekf(1) = 0.80;  P_ekf(1) = 0.05^2;  soc_cc(1) = 0.80;
for k = 2:N
    [soc_ekf(k), P_ekf(k), d] = ekf_step_1d(soc_ekf(k-1), P_ekf(k-1), Im(k-1), Im(k), Vm(k), ...
                                            dt, Cn, R0, Q, R, ocv_fun, slope_fun);
    K_ekf(k)  = d.K;
    soc_cc(k) = soc_cc(k-1) - Im(k-1)*dt/(3600*Cn);
end

% --- Plot ---
t = (0:N-1) / 60;                         % minutes
sig3 = 3*sqrt(P_ekf);
figure('Name', 'Day 1: EKF vs charge counting', 'Color', 'w');

subplot(3,1,1); hold on; grid on;
fill([t fliplr(t)], 100*[soc_ekf+sig3 fliplr(soc_ekf-sig3)], [0.8 0.88 1], ...
     'EdgeColor', 'none', 'DisplayName', 'EKF \pm3\sigma');
plot(t, 100*soc_true, 'k',  'LineWidth', 1.5, 'DisplayName', 'True SoC');
plot(t, 100*soc_ekf,  'b',  'LineWidth', 1.2, 'DisplayName', 'EKF');
plot(t, 100*soc_cc,   'r--','LineWidth', 1.2, 'DisplayName', 'Charge counting');
ylabel('SoC (%)'); legend('Location', 'northeast');
title('EKF corrects a wrong start; charge counting never does');

subplot(3,1,2); grid on;
plot(t, K_ekf, 'b'); ylabel('Kalman gain K');
title('K is large at first (unsure), then settles');

subplot(3,1,3); grid on;
plot(t, 100*sqrt(P_ekf), 'b'); ylabel('\sigma_{SoC} (%)'); xlabel('Time (min)');
title('Uncertainty shrinks fast, then stays small');

fprintf('\nFinal error  EKF: %+.2f%%   charge counting: %+.2f%%\n', ...
        100*(soc_ekf(end) - soc_true(end)), 100*(soc_cc(end) - soc_true(end)));

%% ---------------- Local functions ----------------
function [soc, P, d] = ekf_step_1d(soc, P, Im_prev, Im_now, Vm, dt, Cn, R0, Q, R, ocv_fun, slope_fun)
% One EKF step for a single state (SoC).
    % 1. Predict: charge counting moves the guess, uncertainty grows
    d.soc_pred = soc - Im_prev*dt/(3600*Cn);
    d.P_pred   = P + Q;                          % F = 1 for this model

    % 2. Compare: what voltage do we expect at the predicted SoC?
    d.V_pred = ocv_fun(d.soc_pred) - R0*Im_now;
    d.y      = Vm - d.V_pred;                    % innovation (the surprise)
    d.H      = slope_fun(d.soc_pred);            % tangent slope dOCV/dSoC

    % 3. Update: move by K x surprise, uncertainty shrinks
    d.S = d.H^2 * d.P_pred + R;                  % expected size of the surprise
    d.K = d.P_pred * d.H / d.S;                  % Kalman gain
    soc = d.soc_pred + d.K * d.y;
    P   = (1 - d.K*d.H) * d.P_pred;
end

function print_step(soc0, P0, d)
    fprintf('Start:    SoC = %.2f%%  (sigma %.2f%%)\n', 100*soc0, 100*sqrt(P0));
    fprintf('Predict:  SoC = %.2f%%  (sigma %.2f%%)\n', 100*d.soc_pred, 100*sqrt(d.P_pred));
    fprintf('Expected voltage %.4f V, innovation %+.4f V\n', d.V_pred, d.y);
    fprintf('H = %.2f V per unit SoC,  S = %.6f V^2,  K = %.3f\n', d.H, d.S, d.K);
    fprintf('Update:   SoC = %.2f%%  (sigma %.2f%%)\n', ...
            100*(d.soc_pred + d.K*d.y), 100*sqrt((1 - d.K*d.H)*d.P_pred));
end
