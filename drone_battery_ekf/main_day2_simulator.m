%% Day 2 - Test the simulator (no filter yet)
% Flies the 'short' delivery mission on the "real" battery and records
% what the sensors would report. Checks that everything looks realistic
% before we add the EKF on Day 3.
%
% Run from the drone_battery_ekf folder.

clear; clc; close all;
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'config'), fullfile(root, 'sim'));

rng(2);                                  % same random numbers every run
p  = battery_params();
m  = make_mission('short');
dt = p.dt;

%% Run the flight
soc0  = 0.95;                            % battery starts at 95%
batt  = battery_true_init(soc0);
drone = drone_init(m);

N = 3600;                                % room for up to 1 hour of logging
rec.t = nan(1,N); rec.I = nan(1,N); rec.Im = nan(1,N);
rec.V = nan(1,N); rec.Vm = nan(1,N); rec.ocv = nan(1,N);
rec.soc = nan(1,N); rec.pos = nan(N,2); rec.mode = strings(1,N);

wobble = 0;                              % small random load changes (gusts, manoeuvres)
dead = false;
for k = 1:N
    [drone, I_demand] = drone_step(drone, m, dt);
    if I_demand > 0
        wobble = 0.9*wobble + 0.3*randn;     % slowly varying, about +/-0.7 A
        I = max(I_demand + wobble, 0);
    else
        I = 0;
    end

    [batt, V] = battery_true_step(batt, I, p.true, dt);
    [Im, Vm]  = read_sensors(I, V, p.sens);

    rec.t(k) = k*dt;   rec.I(k) = I;   rec.Im(k) = Im;
    rec.V(k) = V;      rec.Vm(k) = Vm; rec.ocv(k) = ocv_lookup(batt.soc, p.true.ocv_offset);
    rec.soc(k) = batt.soc;  rec.pos(k,:) = drone.pos;  rec.mode(k) = drone.mode;

    if I > 0 && V < p.true.V_cutoff
        dead = true;  break;                 % battery died in the air
    end
    if strcmp(drone.mode, 'landed'), break; end
end
n = k;                                       % number of logged steps
f = fieldnames(rec);
for i = 1:numel(f)                           % trim unused space
    if strcmp(f{i}, 'pos'), rec.pos = rec.pos(1:n,:); else, rec.(f{i}) = rec.(f{i})(1:n); end
end
tm = rec.t / 60;                             % minutes

%% Summary
fprintf('Mission ''%s'': %s after %.1f min\n', m.name, ...
        ternary(dead, 'BATTERY DIED IN THE AIR', 'landed safely'), tm(end));
fprintf('Distance flown        : %.2f km\n', drone.dist_flown/1000);
fprintf('Charge used           : %.2f Ah (true SoC %.0f%% -> %.1f%%)\n', ...
        (soc0 - rec.soc(end))*p.true.Cn, 100*soc0, 100*rec.soc(end));
fprintf('Lowest cell voltage   : %.3f V (cutoff %.1f V)\n', min(rec.V), p.true.V_cutoff);
sag = rec.ocv - rec.V;
fprintf('Largest voltage sag   : %.0f mV per cell\n', 1000*max(sag));
soc_cc_end = soc0 - sum(rec.Im)*dt/(3600*p.true.Cn);   % charge counting with the biased sensor
fprintf('Charge counting error : %+.1f%% at landing (sensor bias + noise)\n', ...
        100*(soc_cc_end - rec.soc(end)));

%% Figure A - OCV curve: real battery vs what the filter believes
s = linspace(0, 1, 201);
[ocv_f, slope_f] = ocv_lookup(s, p.filt.ocv_offset);
ocv_t = ocv_lookup(s, p.true.ocv_offset);
figA = figure('Name', 'OCV curve', 'Color', 'w');
yyaxis left;  plot(100*s, ocv_f, 'b-', 100*s, ocv_t, 'k--', 'LineWidth', 1.3);
ylabel('OCV per cell (V)');
yyaxis right; plot(100*s, 1000*slope_f/100, 'LineWidth', 1); ylabel('Slope (mV per 1% SoC)');
xlabel('State of charge (%)'); grid on;
legend('Filter''s curve', 'Real battery (5 mV lower)', 'Slope', 'Location', 'northwest');
title('OCV curve: steep near empty, flatter in the middle');

%% Figure B - Mission map and current profile
figB = figure('Name', 'Mission', 'Color', 'w', 'Position', [100 100 900 650]);
subplot(2,1,1); hold on; grid on; axis equal;
plot(rec.pos(:,1)/1000, rec.pos(:,2)/1000, 'b-', 'LineWidth', 1.3);
plot(m.wp(:,1)/1000, m.wp(:,2)/1000, 'rs', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
plot(0, 0, 'k^', 'MarkerFaceColor', 'k', 'MarkerSize', 10);
text(m.wp(:,1)/1000 + 0.08, m.wp(:,2)/1000, compose('Drop %d', (1:size(m.wp,1))'));
xlabel('East (km)'); ylabel('North (km)'); title('Flight path: home \rightarrow 3 drop-offs \rightarrow home');
legend('Path', 'Drop-offs', 'Home', 'Location', 'bestoutside');

subplot(2,1,2); hold on; grid on;
plot(tm, rec.Im, 'Color', [0.7 0.7 0.7]);
plot(tm, rec.I, 'b', 'LineWidth', 1.2);
xlabel('Time (min)'); ylabel('Current (A)');
legend('Measured (biased, noisy)', 'True', 'Location', 'northeast');
title('Current: takeoff spike, cruise, hover at each drop, landing');

%% Figure C - Voltage sag and true SoC
figC = figure('Name', 'Voltage and SoC', 'Color', 'w', 'Position', [150 150 900 650]);
subplot(2,1,1); hold on; grid on;
plot(tm, rec.Vm, 'Color', [0.75 0.75 0.75]);
plot(tm, rec.ocv, 'k--', 'LineWidth', 1.2);
plot(tm, rec.V, 'b', 'LineWidth', 1.2);
ylabel('Cell voltage (V)');
legend('Measured', 'OCV (resting voltage)', 'True terminal voltage', 'Location', 'northeast');
title('The gap between the dashed and blue lines is the voltage sag');

subplot(2,1,2); grid on;
plot(tm, 100*rec.soc, 'k', 'LineWidth', 1.4);
xlabel('Time (min)'); ylabel('True SoC (%)');
title('True state of charge (the filter will have to estimate this)');

%% Save figures
out = fullfile(root, 'results', 'day2');
if ~exist(out, 'dir'), mkdir(out); end
save_fig(figA, fullfile(out, 'fig_ocv_curve.png'));
save_fig(figB, fullfile(out, 'fig_mission.png'));
save_fig(figC, fullfile(out, 'fig_voltage_soc.png'));
save(fullfile(out, 'day2_log.mat'), 'rec', 'p', 'm');
fprintf('\nFigures saved in %s\n', out);

%% ---------------- Local functions ----------------
function save_fig(fig, file)
if exist('exportgraphics', 'file')
    exportgraphics(fig, file, 'Resolution', 150);
else
    saveas(fig, file);
end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
