%% Day 4 - Experiments E3 to E8: stress-testing the filter
%   E3  current sensor reads 0.8 A too high
%   E4  aged battery: only 85% of its rated capacity
%   E5  tuning: what happens when Q and R are set badly
%   E6  stress test: a much bigger unmodelled slow RC effect
%   E7  does uncertainty grow where the OCV curve is flat?
%   E8  summary: charge counting vs stages A, B, C over 20 random flights
%
% Run from the drone_battery_ekf folder. E8 flies 300 missions (about 1-3 min).

clear; clc; close all;
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'config'), fullfile(root, 'sim'), fullfile(root, 'estimators'));

p0 = battery_params();
m  = make_mission('short');

% Normal flight settings; every scenario starts from these
base = struct('soc_true0', 0.95, 'soc_guess0', NaN, 'sig_soc0', 0.03, ...
              'seed', 2, 'n_rest', 10);   % n_rest: average 10 resting readings before takeoff

%% Scenarios
sc = {};
sc{end+1} = scenario('E1', 'Normal flight',          p0, base);

o = base;  o.soc_true0 = 0.85;  o.soc_guess0 = 1.00;  o.sig_soc0 = 0.20;
sc{end+1} = scenario('E2', 'Wrong start (85%, assumed full)', p0, o);

p = p0;  p.sens.bias = 0.8;
sc{end+1} = scenario('E3', 'Sensor bias 0.8 A',      p, base);

p = p0;  p.true.Cn = 0.85 * p0.true.Cn;  o = base;  o.soc_true0 = 1.00;
sc{end+1} = scenario('E4', 'Aged battery (85% capacity)', p, o);

p = p0;  p.true.R2 = 0.004;  p.true.C2 = 1e5;        % slow RC 2.7x bigger (tau 400 s)
sc{end+1} = scenario('E6', 'Strong model mismatch',  p, base);

get_sc = @(code) sc{find(cellfun(@(s) strcmp(s.code, code), sc), 1)};

%% E3 and E4 - can stage C learn the bias and the capacity?
s3 = get_sc('E3');  r3B = run_stage(s3, m, 'B');  r3C = run_stage(s3, m, 'C');
s4 = get_sc('E4');  r4B = run_stage(s4, m, 'B');  r4C = run_stage(s4, m, 'C');

fprintf('==== E3: sensor bias 0.8 A ====\n');
print_row('Charge counting', flight_metrics(r3B, 'cc'));
print_row('EKF stage B',     flight_metrics(r3B, 'ekf'));
print_row('EKF stage C',     flight_metrics(r3C, 'ekf'));
fprintf('Stage C bias estimate at landing: %+.2f A (true %+.2f A)\n\n', r3C.x(3,end), s3.p.sens.bias);

fprintf('==== E4: aged battery (true capacity %.2f Ah, filter assumes %.2f Ah) ====\n', s4.p.true.Cn, s4.p.filt.Cn);
print_row('Charge counting', flight_metrics(r4B, 'cc'));
print_row('EKF stage B',     flight_metrics(r4B, 'ekf'));
print_row('EKF stage C',     flight_metrics(r4C, 'ekf'));
fprintf('Stage C at landing: capacity %.2f Ah (true %.2f), bias %+.2f A (true %+.2f)\n', ...
        r4C.x(4,end), s4.p.true.Cn, r4C.x(3,end), s4.p.sens.bias);
fprintf('True SoC at landing %.1f%%; charge counting believed %.1f%%\n\n', 100*r4B.soc(end), 100*r4B.soc_cc(end));

figE3 = figure('Name', 'E3 bias', 'Color', 'w', 'Position', [60 60 900 650]);
plot_errors(subplot(2,1,1), {r3B, r3C}, {'EKF stage B', 'EKF stage C'}, 'E3: SoC error with a 0.8 A sensor bias');
plot_param(subplot(2,1,2), r3C, 3, 1, s3.p.sens.bias, 'True bias', 'Bias (A)', ...
           'E3: stage C cannot pin down the bias within one flight');

figE4 = figure('Name', 'E4 aged', 'Color', 'w', 'Position', [80 80 900 650]);
plot_errors(subplot(2,1,1), {r4B, r4C}, {'EKF stage B', 'EKF stage C'}, 'E4: SoC error with an aged battery (85% capacity)');
plot_param(subplot(2,1,2), r4C, 4, 1, s4.p.true.Cn, 'True capacity', 'Capacity (Ah)', ...
           'E4: stage C moves its capacity estimate toward the truth');
yline(s4.p.filt.Cn, ':', 'Rated (label) capacity', 'HandleVisibility', 'off');

%% E5 - tuning: turn the Q and R knobs
s1 = get_sc('E1');
tune = [1 1; 0.01 1; 100 1; 1 0.01; 1 100];          % [Q scale, R scale]
tune_names = {'Q x1, R x1 (chosen)', 'Q x0.01', 'Q x100', 'R x0.01', 'R x100'};
rT = cell(1, size(tune,1));
fprintf('==== E5: tuning (stage B, normal flight) ====\n');
for i = 1:size(tune,1)
    o = s1.opts;  o.stage = 'B';  o.q_scale = tune(i,1);  o.r_scale = tune(i,2);
    rT{i} = run_flight(s1.p, m, o);
    print_row(tune_names{i}, flight_metrics(rT{i}, 'ekf'));
end
fprintf('\n');

figE5 = figure('Name', 'E5 tuning', 'Color', 'w', 'Position', [100 100 900 650]);
subplot(2,1,1); hold on; grid on;
cols = lines(numel(rT));
for i = 1:numel(rT)
    plot(rT{i}.t/60, 100*(rT{i}.x(1,:) - rT{i}.soc), 'Color', cols(i,:), 'LineWidth', 1.2);
end
yline(0, 'k:', 'HandleVisibility', 'off');
ylabel('SoC error (%)'); xlabel('Time (min)'); legend(tune_names, 'Location', 'best');
title('E5: SoC error for different tunings');
subplot(2,1,2);
MT = cellfun(@(r) flight_metrics(r, 'ekf'), rT, 'UniformOutput', false);
MT = [MT{:}];
yyaxis left;  bar(100*[MT.rmse]);  ylabel('RMSE (% SoC)');
yyaxis right; plot(1:numel(MT), 100*[MT.inside], 'o-', 'LineWidth', 1.5); ylabel('Truth inside \pm3\sigma (%)'); ylim([0 105]);
set(gca, 'XTick', 1:numel(MT), 'XTickLabel', tune_names); grid on;
title('Accuracy (bars) and honesty (line) for each tuning');

%% E6 - stress test: strong model mismatch
s6 = get_sc('E6');
r6A = run_stage(s6, m, 'A');  r6B = run_stage(s6, m, 'B');  r6C = run_stage(s6, m, 'C');
fprintf('==== E6: strong model mismatch (slow RC R2 = %.1f mOhm) ====\n', 1000*s6.p.true.R2);
print_row('Charge counting', flight_metrics(r6A, 'cc'));
print_row('EKF stage A',     flight_metrics(r6A, 'ekf'));
print_row('EKF stage B',     flight_metrics(r6B, 'ekf'));
print_row('EKF stage C',     flight_metrics(r6C, 'ekf'));
fprintf('\n');

figE6 = figure('Name', 'E6 stress', 'Color', 'w', 'Position', [120 120 900 380]);
plot_errors(gca, {r6A, r6B, r6C}, {'EKF stage A', 'EKF stage B', 'EKF stage C'}, ...
            'E6: SoC error when the real battery differs strongly from the model');

%% E7 - uncertainty vs the flat part of the OCV curve
r7B = run_stage(s1, m, 'B');  r7C = run_stage(s1, m, 'C');
figE7 = figure('Name', 'E7 flat OCV', 'Color', 'w', 'Position', [140 140 900 420]);
keep = r7B.t > 60;  keepC = r7C.t > 60;              % skip the first minute (start-up)
yyaxis left; hold on; grid on;
plot(100*r7B.soc(keep),  100*sqrt(r7B.Pd(1,keep)),  'b-', 'LineWidth', 1.3);
plot(100*r7C.soc(keepC), 100*sqrt(r7C.Pd(1,keepC)), 'm-', 'LineWidth', 1.3);
ylabel('\sigma_{SoC} (% SoC)');
yyaxis right;
s = linspace(0.15, 0.95, 200);  [~, sl] = ocv_lookup(s);
plot(100*s, 1000*sl/100, 'Color', [0.85 0.45 0.1], 'LineWidth', 1);
ylabel('OCV slope (mV per 1% SoC)');
set(gca, 'XDir', 'reverse');  xlabel('True SoC (%)  \leftarrow flight goes this way');
legend('Stage B uncertainty', 'Stage C uncertainty', 'OCV slope', 'Location', 'northwest');
title('E7: where the curve is flat (low slope), stage C becomes less sure');

%% E8 - summary over 20 random flights per scenario
seeds  = 1:20;
stages = {'A', 'B', 'C'};
nS = numel(sc);  nSeed = numel(seeds);
R = struct('rmse', nan(nS,4,nSeed), 'inside', nan(nS,4,nSeed), 'final', nan(nS,4,nSeed), ...
           'nis', nan(nS,4,nSeed), 'nees', nan(nS,4,nSeed));   % column 1 = charge counting, 2-4 = stages
fprintf('==== E8: 20 flights x %d scenarios x 3 stages ====\n', nS);
tic;
for i = 1:nS
    for j = 1:nSeed
        for k = 1:numel(stages)
            o = sc{i}.opts;  o.seed = seeds(j);  o.stage = stages{k};
            r = run_flight(sc{i}.p, m, o);
            if k == 1, R = store(R, i, 1, j, flight_metrics(r, 'cc')); end
            R = store(R, i, k+1, j, flight_metrics(r, 'ekf'));
        end
    end
    fprintf('  %s done (%.0f s)\n', sc{i}.code, toc);
end

meth = {'Charge counting', 'Stage A', 'Stage B', 'Stage C'};
fprintf('\nMean over %d flights:  RMSE (truth inside +/-3 sigma)\n', nSeed);
fprintf('%-34s', 'Scenario');  fprintf('%-18s', meth{:});  fprintf('\n');
rows = {};
for i = 1:nS
    fprintf('%-34s', [sc{i}.code ' ' sc{i}.name]);
    for c = 1:4
        rm = 100*mean(R.rmse(i,c,:));  in = 100*mean(R.inside(i,c,:));
        if c == 1, fprintf('%-18s', sprintf('%.2f%%', rm));
        else,      fprintf('%-18s', sprintf('%.2f%% (%3.0f%%)', rm, in)); end
        rows(end+1, :) = {sc{i}.code, sc{i}.name, meth{c}, rm, in, ...
                          100*mean(R.final(i,c,:)), mean(R.nis(i,c,:)), mean(R.nees(i,c,:))}; %#ok<SAGROW>
    end
    fprintf('\n');
end
T = cell2table(rows, 'VariableNames', {'code', 'scenario', 'method', 'rmse_pct', ...
               'inside3sigma_pct', 'final_err_pct', 'mean_nis', 'mean_nees'});

figE8 = figure('Name', 'E8 summary', 'Color', 'w', 'Position', [160 160 950 650]);
labels = cellfun(@(s) s.code, sc, 'UniformOutput', false);
subplot(2,1,1);
bar(100*mean(R.rmse, 3));  grid on;  set(gca, 'XTickLabel', labels);
ylabel('Mean RMSE (% SoC)');  legend(meth, 'Location', 'northwest');
title(sprintf('E8: accuracy over %d random flights per scenario (lower is better)', nSeed));
subplot(2,1,2);
bar(100*mean(R.inside(:,2:4,:), 3));  grid on;  set(gca, 'XTickLabel', labels);  ylim([0 105]);
yline(99.7, 'k--', 'ideal 99.7%', 'HandleVisibility', 'off');
ylabel('Truth inside \pm3\sigma (%)');  legend(meth(2:4), 'Location', 'southwest');
title('Honesty: how often the truth was inside the filter''s own band (higher is better)');

%% Save
out = fullfile(root, 'results', 'day4');
if ~exist(out, 'dir'), mkdir(out); end
save_fig(figE3, fullfile(out, 'fig_e3_bias.png'));
save_fig(figE4, fullfile(out, 'fig_e4_aged.png'));
save_fig(figE5, fullfile(out, 'fig_e5_tuning.png'));
save_fig(figE6, fullfile(out, 'fig_e6_stress.png'));
save_fig(figE7, fullfile(out, 'fig_e7_flat_ocv.png'));
save_fig(figE8, fullfile(out, 'fig_e8_summary.png'));
writetable(T, fullfile(out, 'e8_summary.csv'));
save(fullfile(out, 'day4_runs.mat'), 'r3B', 'r3C', 'r4B', 'r4C', 'rT', 'r6A', 'r6B', 'r6C', 'r7B', 'r7C', 'R', 'T', 'sc');
fprintf('\nFigures and e8_summary.csv saved in %s\n', out);

%% ---------------- Local functions ----------------
function s = scenario(code, name, p, opts)
s.code = code;  s.name = name;  s.p = p;  s.opts = opts;
end

function r = run_stage(s, m, stage)
o = s.opts;  o.stage = stage;
r = run_flight(s.p, m, o);
end

function R = store(R, i, c, j, M)
R.rmse(i,c,j) = M.rmse;  R.inside(i,c,j) = M.inside;  R.final(i,c,j) = M.final;
R.nis(i,c,j)  = M.nis;   R.nees(i,c,j)   = M.nees;
end

function print_row(name, M)
if isnan(M.inside)
    fprintf('  %-22s RMSE %5.2f%%  final %+6.2f%%\n', name, 100*M.rmse, 100*M.final);
else
    fprintf('  %-22s RMSE %5.2f%%  final %+6.2f%%  inside +/-3sig %3.0f%%  NIS %.2f  NEES %.2f\n', ...
            name, 100*M.rmse, 100*M.final, 100*M.inside, M.nis, M.nees);
end
end

function plot_errors(ax, runs, names, ttl)
axes(ax); hold on; grid on;
last = runs{end};  tm = last.t/60;  s3 = 300*sqrt(last.Pd(1,:));
fill([tm fliplr(tm)], [s3 -fliplr(s3)], [0.9 0.85 1], 'EdgeColor', 'none');
plot(runs{1}.t/60, 100*(runs{1}.soc_cc - runs{1}.soc), 'r--', 'LineWidth', 1.1);
cols = [0.95 0.6 0.1; 0 0 1; 0.75 0 0.75];
cols = cols(end-numel(runs)+1:end, :);
for i = 1:numel(runs)
    plot(runs{i}.t/60, 100*(runs{i}.x(1,:) - runs{i}.soc), 'Color', cols(i,:), 'LineWidth', 1.2);
end
yline(0, 'k:', 'HandleVisibility', 'off');
ylabel('SoC error (%)'); xlabel('Time (min)'); title(ttl);
legend([{[names{end} ' \pm3\sigma'], 'Charge counting'}, names], 'Location', 'best');
end

function plot_param(ax, r, idx, scale, truth, truth_lbl, ylab, ttl)
axes(ax); hold on; grid on;
tm = r.t/60;  v = scale*r.x(idx,:);  s3 = 3*scale*sqrt(r.Pd(idx,:));
fill([tm fliplr(tm)], [v+s3 fliplr(v-s3)], [0.9 0.85 1], 'EdgeColor', 'none');
plot(tm, v, 'm', 'LineWidth', 1.3);
yline(truth, 'k--', truth_lbl, 'HandleVisibility', 'off');
ylabel(ylab); xlabel('Time (min)'); title(ttl);
legend('Stage C \pm3\sigma', 'Stage C estimate', 'Location', 'best');
end

function save_fig(fig, file)
if exist('exportgraphics', 'file')
    exportgraphics(fig, file, 'Resolution', 150);
else
    saveas(fig, file);
end
end
