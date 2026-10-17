function [f, info] = ekf_step(f, Im, Vm, dt)
% EKF_STEP  One predict + update of the battery EKF.
%
%   f    : filter (from ekf_init), holds the estimate f.x and uncertainty f.P
%   Im   : measured current during this step (A)
%   Vm   : measured cell voltage at the end of the step (V)
%   info : innovation, its expected size, gain, ... (for plots and checks)
%
% State x = [SoC; V1; b; Cn; R0].

soc = f.x(1);  v1 = f.x(2);  b = f.x(3);  Cn = f.x(4);  R0 = f.x(5);
I = Im - b;                                   % bias-corrected current
a = exp(-dt / (f.R1 * f.C1));                 % how much of V1 survives one step

% ---------- 1. Predict: move the estimate with the model ----------
x_pred = [soc - I*dt/(3600*Cn);               % charge counting
          a*v1 + f.R1*(1 - a)*I;              % slow voltage relaxes toward R1*I
          b;                                  % bias, capacity and resistance
          Cn;                                 %   stay the same (apart from
          R0];                                %   slow random wander)

F = eye(5);                                   % Jacobian of the process model
F(1,3) = dt/(3600*Cn);                        %   dSoC/db
F(1,4) = I*dt/(3600*Cn^2);                    %   dSoC/dCn
F(2,2) = a;                                   %   dV1/dV1
F(2,3) = -f.R1*(1 - a);                       %   dV1/db

G = [-dt/(3600*Cn); f.R1*(1 - a); 0; 0; 0];   % how current-sensor noise enters
Q = G * f.sigI^2 * G' + diag(f.q);
P_pred = F * f.P * F' + Q;                    % uncertainty grows

% ---------- 2. Compare: expected vs measured voltage ----------
[ocv, docv] = ocv_lookup(x_pred(1), f.ocv_offset);
I_pred = Im - x_pred(3);
V_pred = ocv - x_pred(2) - x_pred(5)*I_pred;
y = Vm - V_pred;                              % innovation (the surprise)

H = [docv, -1, x_pred(5), 0, -I_pred];        % Jacobian of the measurement model
S = H * P_pred * H' + f.Rv;                   % expected size of the surprise (one number)

% ---------- 3. Update: move by K x surprise ----------
K = P_pred * H' / S;                          % Kalman gain (5x1)
x = x_pred + K * y;
IKH = eye(5) - K*H;
P = IKH * P_pred * IKH' + K * f.Rv * K';      % Joseph form: stays symmetric and positive
P = (P + P') / 2;

x(1) = min(max(x(1), 0), 1);                  % SoC stays in [0, 1]
x(4) = max(x(4), 0.5);                        % capacity stays positive
x(5) = max(x(5), 1e-4);                       % resistance stays positive

f.x = x;  f.P = P;
info.y = y;  info.S = S;  info.K = K;  info.V_pred = V_pred;
info.nis = y^2 / S;                           % normalised innovation squared
end
