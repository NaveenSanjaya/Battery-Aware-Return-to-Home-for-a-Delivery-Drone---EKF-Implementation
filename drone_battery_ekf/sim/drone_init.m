function d = drone_init(m)
% DRONE_INIT  Drone sitting at home, about to take off.
d.pos       = m.home;     % position (m)
d.mode      = 'takeoff';  % takeoff | cruise | hover | return | landing | landed
d.t_in_mode = 0;          % seconds spent in the current mode
d.wp_index  = 1;          % next drop-off to visit
d.dist_flown = 0;         % metres flown so far (work done)
end
