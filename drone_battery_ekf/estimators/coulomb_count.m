function soc = coulomb_count(soc, Im, Cn, dt)
% COULOMB_COUNT  Baseline: track SoC by adding up the measured current.
%   No voltage, no correction - so any start error or sensor bias stays.
soc = soc - Im * dt / (3600 * Cn);
end
