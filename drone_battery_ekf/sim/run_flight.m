function rec = run_flight(p, m, opts)
% RUN_FLIGHT  Fly one mission: real battery + sensors + EKF + charge counting.
%
%   rec = run_flight(p, m, opts)
%
%   opts.soc_true0  : true starting SoC (fraction)
%   opts.soc_guess0 : what the estimators assume at takeoff;
%                     NaN = read it from the resting voltage (normal use)
%   opts.sig_soc0   : EKF starting uncertainty on SoC (1 sigma)
%   opts.stage      : EKF stage 'A', 'B' or 'C' (see ekf_init)
%   opts.seed       : random seed (same seed = same noise = fair comparison)
%
%   rec : everything recorded each second (truth, sensors, estimates)

dt = p.dt;
rng(opts.seed);

% ---- Before takeoff: battery at rest, so voltage = OCV ----
batt = battery_true_init(opts.soc_true0);
[~, Vm0] = read_sensors(0, ocv_lookup(opts.soc_true0, p.true.ocv_offset), p.sens);
soc_guess0 = opts.soc_guess0;
if isnan(soc_guess0)
    soc_guess0 = soc_from_ocv(Vm0, p.filt.ocv_offset);
end

f      = ekf_init(p, opts.stage, soc_guess0, opts.sig_soc0);
soc_cc = soc_guess0;                         % charge counting starts from the same guess
drone  = drone_init(m);

% ---- Storage ----
N  = 3600;
nx = numel(f.x);
rec.t = nan(1,N);  rec.I = nan(1,N);  rec.Im = nan(1,N);
rec.V = nan(1,N);  rec.Vm = nan(1,N); rec.V_pred = nan(1,N);
rec.soc = nan(1,N); rec.soc_cc = nan(1,N);
rec.x = nan(nx,N); rec.Pd = nan(nx,N);
rec.y = nan(1,N);  rec.S = nan(1,N);  rec.nis = nan(1,N);
rec.pos = nan(N,2); rec.mode = strings(1,N);

% ---- Fly ----
wobble = 0;
rec.dead = false;
for k = 1:N
    [drone, I_demand] = drone_step(drone, m, dt);
    if I_demand > 0
        wobble = 0.9*wobble + 0.3*randn;     % small random load changes
        I = max(I_demand + wobble, 0);
    else
        I = 0;
    end

    [batt, V] = battery_true_step(batt, I, p.true, dt);   % truth
    [Im, Vm]  = read_sensors(I, V, p.sens);               % what the drone sees
    [f, info] = ekf_step(f, Im, Vm, dt);                  % EKF
    soc_cc    = coulomb_count(soc_cc, Im, p.filt.Cn, dt); % baseline

    rec.t(k) = k*dt;  rec.I(k) = I;  rec.Im(k) = Im;
    rec.V(k) = V;     rec.Vm(k) = Vm; rec.V_pred(k) = info.V_pred;
    rec.soc(k) = batt.soc;  rec.soc_cc(k) = soc_cc;
    rec.x(:,k) = f.x;  rec.Pd(:,k) = diag(f.P);
    rec.y(k) = info.y; rec.S(k) = info.S; rec.nis(k) = info.nis;
    rec.pos(k,:) = drone.pos;  rec.mode(k) = drone.mode;

    if I > 0 && V < p.true.V_cutoff
        rec.dead = true;  break;             % battery died in the air
    end
    if strcmp(drone.mode, 'landed'), break; end
end

% ---- Trim unused storage ----
n = k;
names = fieldnames(rec);
for i = 1:numel(names)
    v = rec.(names{i});
    if ~isnumeric(v) && ~isstring(v), continue; end
    if size(v, 2) == N,     rec.(names{i}) = v(:, 1:n);
    elseif size(v, 1) == N, rec.(names{i}) = v(1:n, :);
    end
end
rec.soc_guess0 = soc_guess0;
rec.dist_flown = drone.dist_flown;
rec.opts = opts;
end
