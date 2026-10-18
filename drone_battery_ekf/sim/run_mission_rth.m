function out = run_mission_rth(p, m, c, policy, rp, seed)
% RUN_MISSION_RTH  Fly a mission that is too long for one battery and let a
% policy decide when to turn back.
%
%   p      : battery_params()
%   m      : mission (use make_mission('long'))
%   c      : random conditions from draw_conditions (start SoC, bias, wind, age...)
%   policy : 'A', 'B', 'C' or 'D' (see rth_policy)
%   rp     : RTH settings (reserve, trip_frac, p_thr, V_thr, V_hold)
%   seed   : random seed for the sensor noise
%
%   out.died      : true if the battery died in the air
%   out.soc_land  : true SoC at landing
%   out.drops     : deliveries completed
%   out.t_rth     : second at which the policy turned back (NaN = never)
%   out.rec       : second-by-second record (for plots)
%
% The stage C EKF and charge counting always run, whichever policy decides.

% ---- Apply this mission's conditions ----
p.sens.bias = c.bias;
p.true.Cn = c.Cn;  p.true.R0 = c.R0;  p.true.R1 = c.R1;  p.true.C1 = c.C1;  p.true.R2 = c.R2;
m.wind = c.wind;
dt = p.dt;
rng(seed);

% ---- Before takeoff: average 10 resting readings for the starting guess ----
batt = battery_true_init(c.soc0);
V_rest = ocv_lookup(c.soc0, p.true.ocv_offset);
Vm0 = 0;
for i = 1:10
    [~, Vm_i] = read_sensors(0, V_rest, p.sens);
    Vm0 = Vm0 + Vm_i / 10;
end
soc_guess0 = soc_from_ocv(Vm0, p.filt.ocv_offset);

f      = ekf_init(p, 'C', soc_guess0, 0.03);     % stage C drives the decision
soc_cc = soc_guess0;                             % charge counting starts from the same guess
drone  = drone_init(m);
I_cr   = m.I_cruise;                             % learned cruise current (as measured)

% ---- Storage ----
N = 4000;
rec.t = nan(1,N);  rec.soc = nan(1,N);  rec.soc_hat = nan(1,N);  rec.sig = nan(1,N);
rec.soc_cc = nan(1,N);  rec.ps = nan(1,N);  rec.margin = nan(1,N);  rec.dsoc = nan(1,N);
rec.Vm = nan(1,N);  rec.pos = nan(N,2);  rec.mode = strings(1,N);

wobble = 0;  low_count = 0;
out.died = false;  out.t_rth = NaN;
for k = 1:N
    [drone, I_demand] = drone_step(drone, m, dt);
    if I_demand > 0
        wobble = 0.9*wobble + 0.3*randn;
        I = max(I_demand + wobble, 0);
    else
        I = 0;
    end

    [batt, V] = battery_true_step(batt, I, p.true, dt);
    [Im, Vm]  = read_sensors(I, V, p.sens);
    f         = ekf_step(f, Im, Vm, dt);
    soc_cc    = coulomb_count(soc_cc, Im, p.filt.Cn, dt);
    if strcmp(drone.mode, 'cruise')
        I_cr = 0.98*I_cr + 0.02*Im;              % slowly learn the real cruise current
    end

    % ---- What the drone knows, and the decision ----
    dist_home = norm(drone.pos - m.home);
    [ps, margin, dsoc] = p_safe_return(f, dist_home, I_cr, m, rp);
    if any(strcmp(drone.mode, {'cruise', 'hover'}))       % decide only while working
        s.Vm = Vm;  s.low_count = low_count;  s.ps = ps;  s.margin = margin;
        s.soc_cc  = soc_cc;
        s.dsoc_cc = trip_soc(dist_home, I_cr, 0, p.filt.Cn, m);   % no bias, label capacity
        [go_home, low_count] = rth_policy(policy, s, rp);
        if go_home
            drone.mode = 'return';  drone.t_in_mode = 0;
            out.t_rth = k;
        end
    end

    rec.t(k) = k*dt;  rec.soc(k) = batt.soc;  rec.soc_hat(k) = f.x(1);  rec.sig(k) = sqrt(f.P(1,1));
    rec.soc_cc(k) = soc_cc;  rec.ps(k) = ps;  rec.margin(k) = margin;  rec.dsoc(k) = dsoc;
    rec.Vm(k) = Vm;  rec.pos(k,:) = drone.pos;  rec.mode(k) = drone.mode;

    if I > 0 && (V < p.true.V_cutoff || batt.soc <= 0)
        out.died = true;  break;                 % battery died in the air
    end
    if strcmp(drone.mode, 'landed'), break; end
end

% ---- Trim and summarise ----
n = k;
names = fieldnames(rec);
for i = 1:numel(names)
    v = rec.(names{i});
    if size(v, 2) == N, rec.(names{i}) = v(:, 1:n); else, rec.(names{i}) = v(1:n, :); end
end
out.soc_land  = batt.soc;
out.drops     = drone.wp_index - 1;          % a drop counts once its hover is finished
e_ekf = rec.soc_hat - rec.soc;               % how well the estimators tracked SoC
e_cc  = rec.soc_cc  - rec.soc;
out.rmse_ekf  = sqrt(mean(e_ekf.^2));
out.rmse_cc   = sqrt(mean(e_cc.^2));
out.inside    = mean(abs(e_ekf) <= 3*rec.sig);
out.dist      = drone.dist_flown;
out.T         = n * dt;
out.rec       = rec;
end
