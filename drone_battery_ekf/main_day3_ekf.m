%% Day 3 - First EKF: experiments E1 (normal flight) and E2 (wrong start)
% Flies the 'short' mission and compares three ways of tracking SoC:
%   Charge counting  - adds up the measured current (baseline)
%   EKF stage A      - learns SoC and V1
%   EKF stage B      - also learns the resistance R0 (our main filter)
%
% Run from the drone_battery_ekf folder.

clear; clc; close all;
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'config'), fullfile(root, 'sim'), fullfile(root, 'estimators'));

p = battery_params();
m = make_mission('short');

% E1: battery at 95%, starting guess read from the resting voltage
E1 = struct('soc_true0', 0.95, 'soc_guess0', NaN,  'sig_soc0', 0.03, 'seed', 2);
% E2: battery really at 85%, but everyone assumes it is full
E2 = struct('soc_true0', 0.85, 'soc_guess0', 1.00, 'sig_soc0', 0.20, 'seed', 2);

E1.stage = 'A';  r1A = run_flight(p, m, E1);
E1.stage = 'B';  r1B = run_flight(p, m, E1);
E2.stage = 'A';  r2A = run_flight(p, m, E2);
E2.stage = 'B';  r2B = run_flight(p, m, E2);

%% Results table
fprintf('%-26s %9s %9s %9s %11s %7s %12s\n', 'Run', 'RMSE', 'Final', 'Max', 'In +/-3sig', 'NIS', 'Conv. <2%');
show('E1  charge counting', r1A, 'cc');
show('E1  EKF stage A',     r1A, 'ekf');
show('E1  EKF stage B (R0)', r1B, 'ekf');
show('E2  charge counting', r2A, 'cc');
show('E2  EKF stage A',     r2A, 'ekf');
show('E2  EKF stage B (R0)', r2B, 'ekf');
fprintf('\nStage B resistance estimate at landing (E1): %.2f mOhm  (filter started at %.1f, real R0 = %.1f mOhm)\n', ...
        1000*r1B.x(5,end), 1000*p.filt.R0, 1000*p.true.R0);

%% Figure 1 - Does the model explain the measured voltage? (E1, stage B)
tm = r1B.t / 60;
fig1 = figure('Name', 'E1 voltage', 'Color', 'w', 'Position', [100 100 900 600]);
subplot(2,1,1); hold on; grid on;
plot(tm, r1B.Vm, 'Color', [0.75 0.75 0.75]);
plot(tm, r1B.V_pred, 'b', 'LineWidth', 1.1);
ylabel('Cell voltage (V)'); legend('Measured', 'EKF expected (before update)', 'Location', 'northeast');
title('E1: the EKF''s model follows the measured voltage, including every sag');
subplot(2,1,2); hold on; grid on;
plot(tm, 1000*r1B.y, 'Color', [0.3 0.3 0.3]);
plot(tm,  3000*sqrt(r1B.S), 'r--', tm, -3000*sqrt(r1B.S), 'r--');
ylabel('Innovation (mV)'); xlabel('Time (min)');
legend('Innovation (measured - expected)', '\pm3\surd S (expected size)', 'Location', 'northeast');
title('Innovations look like random noise inside their expected size: the filter is healthy');

%% Figure 2 - SoC tracking (E1 and E2)
fig2 = figure('Name', 'SoC tracking', 'Color', 'w', 'Position', [120 120 900 650]);
plot_soc(subplot(2,1,1), r1A, r1B, 'E1: normal flight (guess read from resting voltage)');
plot_soc(subplot(2,1,2), r2A, r2B, 'E2: battery at 85% but assumed full');

%% Figure 3 - SoC error with the EKF's own +/-3 sigma band
fig3 = figure('Name', 'SoC error', 'Color', 'w', 'Position', [140 140 900 650]);
plot_err(subplot(2,1,1), r1A, r1B, 'E1: error');
plot_err(subplot(2,1,2), r2A, r2B, 'E2: error');

%% Figure 4 - Stage B learns the resistance
fig4 = figure('Name', 'R0 estimate', 'Color', 'w', 'Position', [160 160 900 350]);
hold on; grid on;
sdR = 3000*sqrt(r1B.Pd(5,:));
fill([tm fliplr(tm)], [1000*r1B.x(5,:)+sdR fliplr(1000*r1B.x(5,:)-sdR)], [0.85 0.9 1], 'EdgeColor', 'none');
plot(tm, 1000*r1B.x(5,:), 'b', 'LineWidth', 1.3);
yline(1000*p.true.R0, 'k--', 'Real R0');
yline(1000*p.filt.R0, ':', 'Filter''s starting value');
ylabel('R0 (m\Omega)'); xlabel('Time (min)');
legend('\pm3\sigma', 'Stage B estimate', 'Location', 'southeast');
title('E1: stage B learns that the real battery has more resistance than assumed');

%% Save
out = fullfile(root, 'results', 'day3');
if ~exist(out, 'dir'), mkdir(out); end
save_fig(fig1, fullfile(out, 'fig_e1_voltage_innovation.png'));
save_fig(fig2, fullfile(out, 'fig_soc_tracking.png'));
save_fig(fig3, fullfile(out, 'fig_soc_error.png'));
save_fig(fig4, fullfile(out, 'fig_r0_estimate.png'));
save(fullfile(out, 'day3_runs.mat'), 'r1A', 'r1B', 'r2A', 'r2B', 'p', 'm');
fprintf('Figures saved in %s\n', out);

%% ---------------- Local functions ----------------
function show(name, r, which)
if strcmp(which, 'cc'), est = r.soc_cc; else, est = r.x(1,:); end
e = est - r.soc;
bad = find(abs(e) >= 0.02, 1, 'last');            % last time the error was 2% or more
if isempty(bad), conv = 0; else, conv = r.t(bad); end
if strcmp(which, 'cc')
    fprintf('%-26s %8.2f%% %+8.2f%% %8.2f%% %11s %7s %12s\n', name, 100*sqrt(mean(e.^2)), 100*e(end), 100*max(abs(e)), '-', '-', '-');
else
    inside = mean(abs(e) <= 3*sqrt(r.Pd(1,:)));
    if conv >= r.t(end), cs = 'never'; else, cs = sprintf('%d s', conv); end
    fprintf('%-26s %8.2f%% %+8.2f%% %8.2f%% %10.0f%% %7.2f %12s\n', name, 100*sqrt(mean(e.^2)), 100*e(end), 100*max(abs(e)), 100*inside, mean(r.nis), cs);
end
end

function plot_soc(ax, rA, rB, ttl)
axes(ax); hold on; grid on;
tm = rB.t / 60;
s3 = 3*sqrt(rB.Pd(1,:));
fill([tm fliplr(tm)], 100*[rB.x(1,:)+s3 fliplr(rB.x(1,:)-s3)], [0.85 0.9 1], 'EdgeColor', 'none');
plot(tm, 100*rB.soc, 'k', 'LineWidth', 1.6);
plot(tm, 100*rB.soc_cc, 'r--', 'LineWidth', 1.2);
plot(rA.t/60, 100*rA.x(1,:), 'Color', [0.95 0.6 0.1], 'LineWidth', 1.1);
plot(tm, 100*rB.x(1,:), 'b', 'LineWidth', 1.2);
ylabel('SoC (%)'); title(ttl);
legend('Stage B \pm3\sigma', 'True', 'Charge counting', 'EKF stage A', 'EKF stage B', 'Location', 'northeast');
end

function plot_err(ax, rA, rB, ttl)
axes(ax); hold on; grid on;
tm = rB.t / 60;
s3 = 300*sqrt(rB.Pd(1,:));
fill([tm fliplr(tm)], [s3 -fliplr(s3)], [0.85 0.9 1], 'EdgeColor', 'none');
plot(tm, 100*(rB.soc_cc - rB.soc), 'r--', 'LineWidth', 1.1);
plot(rA.t/60, 100*(rA.x(1,:) - rA.soc), 'Color', [0.95 0.6 0.1], 'LineWidth', 1.1);
plot(tm, 100*(rB.x(1,:) - rB.soc), 'b', 'LineWidth', 1.2);
yline(0, 'k:');
ylabel('Error (% SoC)'); xlabel('Time (min)'); title(ttl);
legend('Stage B \pm3\sigma', 'Charge counting', 'EKF stage A', 'EKF stage B', 'Location', 'best');
end

function save_fig(fig, file)
if exist('exportgraphics', 'file')
    exportgraphics(fig, file, 'Resolution', 150);
else
    saveas(fig, file);
end
end
