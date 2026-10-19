%% Day 5 - The return-to-home decision: four policies compared
% The drone flies the 'long' route (6 drop-offs, too far for one battery)
% and must decide when to turn back. Four policies decide:
%   A  voltage threshold (what many simple drones do)
%   B  charge counting + "do I still have enough to get home?"
%   C  EKF estimate + the same question, ignoring uncertainty
%   D  EKF risk-aware: turn back when P(home with reserve) < 95%
%
% Part 1: one demo mission, all four policies
% Part 2: Monte Carlo - 500 random missions x 4 policies
% Part 3: threshold sweep - safety vs wasted battery
%
% Run from the drone_battery_ekf folder. Full run: about 5-10 minutes.
% For a quick test set N_MC = 50 and N_SWEEP = 30 first.

clear; clc; close all;
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'config'), fullfile(root, 'sim'), ...
        fullfile(root, 'estimators'), fullfile(root, 'decision'));

N_MC    = 500;      % missions in the Monte Carlo study
N_SWEEP = 200;      % missions in the threshold sweep

p = battery_params();
m = make_mission('long');

% Return-to-home settings
rp.reserve   = 0.10;    % always land with at least 10% SoC
rp.trip_frac = 0.10;    % trip-cost uncertainty: 10% of the trip (wind, load)
rp.p_thr     = 0.95;    % policy D: turn back when P(safe) < 95%
rp.V_thr     = 3.5;     % policy A: turn back when cell voltage < 3.5 V ...
rp.V_hold    = 5;       %   ... for 5 seconds in a row

policies = {'A', 'B', 'C', 'D'};
pnames   = {'A: voltage threshold', 'B: charge counting', 'C: EKF estimate only', 'D: EKF risk-aware'};
pcol     = [0.95 0.6 0.1; 0.85 0.2 0.2; 0 0.3 0.9; 0.75 0 0.75];

%% Part 1 - one demo mission: aged battery, sensor reads 0.5 A low, headwind
c_demo = struct('soc0', 0.95, 'bias', -0.5, 'wind', 0.10, 'Cn', 0.85*p.true.Cn, ...
                'R0', p.true.R0, 'R1', p.true.R1, 'C1', p.true.C1, 'R2', p.true.R2);
demo = cell(1, 4);
fprintf('==== Part 1: demo mission (aged battery 85%%, bias -0.5 A, wind +10%%) ====\n');
for j = 1:4
    demo{j} = run_mission_rth(p, m, c_demo, policies{j}, rp, 7);
    o = demo{j};
    fprintf('  %-22s turned back at %4.1f min | deliveries %d | landed with %5.1f%% | %s\n', ...
            pnames{j}, o.t_rth/60, o.drops, 100*o.soc_land, ternary(o.died, 'BATTERY DIED', 'safe'));
end

% Figure 1: how the decision is made (policy D's flight)
d = demo{4}.rec;  tm = d.t/60;  tD = demo{4}.t_rth/60;
fig1 = figure('Name', 'Demo decision', 'Color', 'w', 'Position', [60 60 950 800]);
subplot(3,1,1); hold on; grid on;
plot(tm, 100*d.ps, 'm', 'LineWidth', 1.4);
yline(100*rp.p_thr, 'k--', '95% threshold', 'HandleVisibility', 'off');
for j = 1:4
    if ~isnan(demo{j}.t_rth)
        xline(demo{j}.t_rth/60, '-', policies{j}, 'Color', pcol(j,:), 'LineWidth', 1.2, 'HandleVisibility', 'off');
    end
end
ylim([0 105]); ylabel('P(safe return) (%)');
title('Policy D turns back as soon as it is no longer 95% sure of getting home with the reserve');

subplot(3,1,2); hold on; grid on;
fill([tm fliplr(tm)], 100*[d.soc_hat+3*d.sig fliplr(d.soc_hat-3*d.sig)], [0.92 0.85 1], 'EdgeColor', 'none');
plot(tm, 100*d.soc, 'k', 'LineWidth', 1.5);
plot(tm, 100*d.soc_hat, 'm', 'LineWidth', 1.2);
plot(tm, 100*d.soc_cc, 'r--', 'LineWidth', 1.1);
plot(tm, 100*(d.dsoc + rp.reserve), 'Color', [0.2 0.6 0.2], 'LineWidth', 1.3);
xline(tD, 'm:', 'HandleVisibility', 'off');
ylabel('SoC (%)');
legend('EKF \pm3\sigma', 'True SoC', 'EKF estimate', 'Charge counting', 'Needed to get home + reserve', 'Location', 'northeast');
title('Turning back is safe while the estimate stays clearly above the green line');

subplot(3,1,3); hold on; grid on;
for j = 1:4
    plot(demo{j}.rec.t/60, 100*demo{j}.rec.soc, 'Color', pcol(j,:), 'LineWidth', 1.3);
end
yline(100*rp.reserve, 'k--', '10% reserve', 'HandleVisibility', 'off');
yline(0, 'k-', 'HandleVisibility', 'off');
ylabel('True SoC (%)'); xlabel('Time (min)'); legend(pnames, 'Location', 'northeast');
title('What really happened to the battery under each policy');

% Figure 2: map of the four flights
fig2 = figure('Name', 'Demo map', 'Color', 'w', 'Position', [80 80 950 450]);
hold on; grid on; axis equal;
plot(m.wp(:,1)/1000, m.wp(:,2)/1000, 's', 'Color', [0.5 0.5 0.5], 'MarkerFaceColor', [0.8 0.8 0.8], 'MarkerSize', 8, 'HandleVisibility', 'off');
plot(0, 0, 'k^', 'MarkerFaceColor', 'k', 'MarkerSize', 10, 'HandleVisibility', 'off');
for j = 1:4
    P = demo{j}.rec.pos;
    plot(P(:,1)/1000, P(:,2)/1000 + 0.03*(j-2.5), 'Color', pcol(j,:), 'LineWidth', 1.4);   % small offset so lines do not overlap
end
for j = 1:4
    o = demo{j};
    if ~isnan(o.t_rth)
        q = o.rec.pos(o.t_rth, :);
        plot(q(1)/1000, q(2)/1000 + 0.03*(j-2.5), 'o', 'Color', pcol(j,:), 'MarkerFaceColor', pcol(j,:), 'HandleVisibility', 'off');
    end
    if o.died
        q = o.rec.pos(end, :);
        plot(q(1)/1000, q(2)/1000, 'kx', 'MarkerSize', 14, 'LineWidth', 2.5, 'HandleVisibility', 'off');
        text(q(1)/1000 + 0.1, q(2)/1000 - 0.15, 'battery died', 'Color', pcol(j,:));
    end
end
xlabel('East (km)'); ylabel('North (km)'); legend(pnames, 'Location', 'northeastoutside');
title('Demo mission: dots = turn-back points, grey squares = drop-offs, triangle = home');

%% Part 2 - Monte Carlo: N_MC random missions x 4 policies
rng(2026);
cond = cell(N_MC, 1);
for i = 1:N_MC, cond{i} = draw_conditions(p); end

died = false(N_MC, 4);  land = nan(N_MC, 4);  drops = nan(N_MC, 4);
acc = nan(N_MC, 3);                                  % EKF RMSE, CC RMSE, EKF inside +/-3 sigma (policy D flights)
fprintf('\n==== Part 2: Monte Carlo, %d missions x 4 policies ====\n', N_MC);
tic;
for i = 1:N_MC
    for j = 1:4
        o = run_mission_rth(p, m, cond{i}, policies{j}, rp, 10000 + i);   % same noise for every policy
        died(i,j) = o.died;  land(i,j) = o.soc_land;  drops(i,j) = o.drops;
        if j == 4, acc(i,:) = [o.rmse_ekf, o.rmse_cc, o.inside]; end
    end
    if mod(i, 50) == 0, fprintf('  %d / %d missions (%.0f s)\n', i, N_MC, toc); end
end
S = summarise(died, land, drops, rp.reserve);

fprintf('\n%-24s %10s %16s %16s %12s\n', 'Policy', 'Died', 'Reserve broken', 'Unused battery', 'Deliveries');
for j = 1:4
    fprintf('%-24s %9.1f%% %15.1f%% %15.1f%% %12.2f\n', pnames{j}, 100*S.died(j), 100*S.breach(j), 100*S.unused(j), S.drops(j));
end
fprintf('\nEstimator accuracy over the %d policy-D flights: EKF (stage C) RMSE %.2f%%, charge counting RMSE %.2f%%, truth inside EKF +/-3 sigma %.0f%%\n', ...
        N_MC, 100*mean(acc(:,1)), 100*mean(acc(:,2)), 100*mean(acc(:,3)));
aged = cellfun(@(c) c.Cn < 0.9*p.true.Cn, cond);
fprintf('\nBattery died, aged batteries only (capacity < 90%%, %d missions):  ', sum(aged));
fprintf('%s %.1f%%   ', policies{1}, 100*mean(died(aged,1)), policies{2}, 100*mean(died(aged,2)), ...
        policies{3}, 100*mean(died(aged,3)), policies{4}, 100*mean(died(aged,4)));
fprintf('\n');

fig3 = figure('Name', 'Monte Carlo', 'Color', 'w', 'Position', [100 100 950 650]);
vals = {100*S.died, 100*S.breach, 100*S.unused, S.drops};
ttl  = {'Battery died in the air (%)', 'Landed below the 10% reserve, or died (%)', ...
        'Unused battery at landing, above reserve (%)', 'Deliveries completed (mean)'};
for q = 1:4
    subplot(2,2,q);
    hb = bar(vals{q}, 'FaceColor', 'flat');  hb.CData = pcol;  grid on;
    set(gca, 'XTickLabel', policies);
    lo = min(0, min(vals{q}));  hi = max(vals{q});
    ylim([1.25*lo - 0.5*(lo < 0), 1.2*hi + 0.5]);       % headroom so value labels do not hit the title
    title(ttl{q});
    for j = 1:4
        text(j, vals{q}(j), sprintf('%.1f', vals{q}(j)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
end
sgtitle(sprintf('Monte Carlo: %d random missions (start charge, sensor bias, wind, battery age, battery parameters)', N_MC));

%% Part 3 - threshold sweep: safety vs wasted battery
D_thr = [0.80 0.90 0.95 0.99 0.999];
A_thr = [3.40 3.45 3.50 3.55 3.60];
nS = min(N_SWEEP, N_MC);
SD = sweep(p, m, cond(1:nS), rp, 'D', 'p_thr', D_thr);
SA = sweep(p, m, cond(1:nS), rp, 'A', 'V_thr', A_thr);
SB = summarise(died(1:nS,2), land(1:nS,2), drops(1:nS,2), rp.reserve);
SC = summarise(died(1:nS,3), land(1:nS,3), drops(1:nS,3), rp.reserve);

fprintf('\n==== Part 3: threshold sweep (%d missions) ====\n', nS);
fprintf('Policy D (risk-aware):\n');
for k = 1:numel(D_thr)
    fprintf('  P(safe) < %5.1f%%: died %4.1f%%, reserve broken %4.1f%% (promised <= %4.1f%%), unused %4.1f%%, deliveries %.2f\n', ...
            100*D_thr(k), 100*SD.died(k), 100*SD.breach(k), 100*(1-D_thr(k)), 100*SD.unused(k), SD.drops(k));
end
fprintf('Policy A (voltage):\n');
for k = 1:numel(A_thr)
    fprintf('  V < %.2f V: died %4.1f%%, reserve broken %4.1f%%, unused %4.1f%%, deliveries %.2f\n', ...
            A_thr(k), 100*SA.died(k), 100*SA.breach(k), 100*SA.unused(k), SA.drops(k));
end

fig4 = figure('Name', 'Trade-off', 'Color', 'w', 'Position', [120 120 800 550]);
hold on; grid on;
plot(100*SA.unused, 100*SA.breach, 'o-', 'Color', pcol(1,:), 'LineWidth', 1.5, 'MarkerFaceColor', pcol(1,:));
plot(100*SB.unused, 100*SB.breach, 's', 'Color', pcol(2,:), 'MarkerFaceColor', pcol(2,:), 'MarkerSize', 10);
plot(100*SC.unused, 100*SC.breach, 'd', 'Color', pcol(3,:), 'MarkerFaceColor', pcol(3,:), 'MarkerSize', 10);
plot(100*SD.unused, 100*SD.breach, 'o-', 'Color', pcol(4,:), 'LineWidth', 1.5, 'MarkerFaceColor', pcol(4,:));
for k = 1:numel(A_thr), text(100*SA.unused(k)+0.4, 100*SA.breach(k)+1.5, sprintf('%.2f V', A_thr(k)), 'Color', pcol(1,:)); end
for k = 1:numel(D_thr), text(100*SD.unused(k)+0.4, 100*SD.breach(k)+1.5, sprintf('%g%%', 100*D_thr(k)), 'Color', pcol(4,:)); end
xlabel('Unused battery at landing (% SoC)  \rightarrow more wasted range');
ylabel('Missions that broke the reserve or died (%)  \rightarrow less safe');
legend('A: voltage threshold', 'B: charge counting', 'C: EKF estimate only', 'D: EKF risk-aware', 'Location', 'northeast');
title('Safety vs wasted battery: bottom-left is best');

%% Save
out = fullfile(root, 'results', 'day5');
if ~exist(out, 'dir'), mkdir(out); end
save_fig(fig1, fullfile(out, 'fig_demo_decision.png'));
save_fig(fig2, fullfile(out, 'fig_demo_map.png'));
save_fig(fig3, fullfile(out, 'fig_monte_carlo.png'));
save_fig(fig4, fullfile(out, 'fig_tradeoff.png'));
T = table(pnames', 100*S.died', 100*S.breach', 100*S.unused', S.drops', ...
          'VariableNames', {'policy', 'died_pct', 'reserve_broken_pct', 'unused_pct', 'deliveries'});
writetable(T, fullfile(out, 'monte_carlo_summary.csv'));
TS = table([repmat({'D'}, numel(D_thr), 1); repmat({'A'}, numel(A_thr), 1)], [D_thr'; A_thr'], ...
           100*[SD.died'; SA.died'], 100*[SD.breach'; SA.breach'], 100*[SD.unused'; SA.unused'], [SD.drops'; SA.drops'], ...
           'VariableNames', {'policy', 'threshold', 'died_pct', 'reserve_broken_pct', 'unused_pct', 'deliveries'});
writetable(TS, fullfile(out, 'threshold_sweep.csv'));
for j = 1:4, demo{j} = rmfield(demo{j}, 'rec'); end   % keep the .mat small
save(fullfile(out, 'day5_results.mat'), 'died', 'land', 'drops', 'acc', 'cond', 'S', 'SD', 'SA', 'demo', 'rp');
fprintf('\nFigures and CSV files saved in %s\n', out);

%% ---------------- Local functions ----------------
function S = summarise(died, land, drops, reserve)
% Per policy (column): died, reserve broken (died or landed below reserve),
% unused battery above the reserve (landed missions only), deliveries.
n = size(died, 2);
S.died = mean(died, 1);
S.breach = mean(died | land < reserve, 1);
S.unused = nan(1, n);
for j = 1:n, S.unused(j) = mean(land(~died(:,j), j) - reserve); end
S.drops = mean(drops, 1);
end

function S = sweep(p, m, cond, rp, policy, field, values)
n = numel(cond);  K = numel(values);
died = false(n, K);  land = nan(n, K);  drops = nan(n, K);
for k = 1:K
    r = rp;  r.(field) = values(k);
    for i = 1:n
        o = run_mission_rth(p, m, cond{i}, policy, r, 10000 + i);
        died(i,k) = o.died;  land(i,k) = o.soc_land;  drops(i,k) = o.drops;
    end
    fprintf('  sweep %s %s = %g done\n', policy, field, values(k));
end
S = summarise(died, land, drops, rp.reserve);
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end

function save_fig(fig, file)
if exist('exportgraphics', 'file')
    exportgraphics(fig, file, 'Resolution', 150);
else
    saveas(fig, file);
end
end
