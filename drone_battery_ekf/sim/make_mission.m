function m = make_mission(name)
% MAKE_MISSION  Delivery route and the current the drone draws in each phase.
%
%   m = make_mission('short')  3 drops, finishes with charge to spare (Day 2 test)
%   m = make_mission('long')   6 drops, too long for one battery - the drone
%                              MUST decide when to turn back (Day 5)
%
% Positions are in metres, home is at (0, 0).

if nargin < 1, name = 'short'; end

switch lower(name)
    case 'short'
        m.wp = [1200  400;
                2200 -400;
                3000  600];
    case 'long'
        m.wp = [1500    0;
                3000  800;
                4500    0;
                6000  800;
                7500    0;
                9000  800];
    otherwise
        error('Unknown mission "%s". Use ''short'' or ''long''.', name);
end
m.name = name;
m.home = [0 0];

% Flight phases: how long they last and the current they draw (pack current, A)
m.v_cruise  = 10;     % cruise ground speed (m/s)
m.T_takeoff = 30;     % s
m.T_hover   = 30;     % s, hovering at each drop-off
m.T_land    = 40;     % s
m.I_takeoff = 30;     % A  (climbing: hardest work)
m.I_cruise  = 15;     % A
m.I_hover   = 20;     % A
m.I_land    = 18;     % A
m.wind      = 0;      % e.g. 0.2 = headwind, cruise needs 20% more current
end
