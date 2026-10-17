function [d, I] = drone_step(d, m, dt)
% DRONE_STEP  Move the drone one time step and return the current it draws.
%
% The drone follows a simple sequence:
%   takeoff -> cruise to drop 1 -> hover -> cruise to drop 2 -> ... -> return -> landing -> landed
%
% To make the drone turn back early, the caller sets  d.mode = 'return'.

d.t_in_mode = d.t_in_mode + dt;

switch d.mode
    case 'takeoff'
        I = m.I_takeoff;
        if d.t_in_mode >= m.T_takeoff
            d = set_mode(d, 'cruise');
        end

    case 'cruise'
        I = m.I_cruise * (1 + m.wind);
        [d, arrived] = fly_towards(d, m.wp(d.wp_index, :), m.v_cruise, dt);
        if arrived
            d = set_mode(d, 'hover');
        end

    case 'hover'
        I = m.I_hover;
        if d.t_in_mode >= m.T_hover
            d.wp_index = d.wp_index + 1;
            if d.wp_index > size(m.wp, 1)
                d = set_mode(d, 'return');      % all deliveries done
            else
                d = set_mode(d, 'cruise');
            end
        end

    case 'return'
        I = m.I_cruise * (1 + m.wind);
        [d, arrived] = fly_towards(d, m.home, m.v_cruise, dt);
        if arrived
            d = set_mode(d, 'landing');
        end

    case 'landing'
        I = m.I_land;
        if d.t_in_mode >= m.T_land
            d = set_mode(d, 'landed');
        end

    case 'landed'
        I = 0;

    otherwise
        error('Unknown drone mode "%s".', d.mode);
end
end

% ---------------------------------------------------------------
function d = set_mode(d, mode)
d.mode = mode;
d.t_in_mode = 0;
end

function [d, arrived] = fly_towards(d, target, v, dt)
gap  = target - d.pos;
dist = norm(gap);
step = v * dt;
if dist <= step                     % close enough: land on the target
    d.pos = target;
    d.dist_flown = d.dist_flown + dist;
    arrived = true;
else
    d.pos = d.pos + step * gap / dist;
    d.dist_flown = d.dist_flown + step;
    arrived = false;
end
end
