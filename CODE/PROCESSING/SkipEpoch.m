function [Epoch, storeData, Adjust] = SkipEpoch(Epoch, storeData, Adjust)
% This function skips one epoch of the processing if e.g. less than four
% satellites are visible.
%
% INPUT:
%	...
% OUTPUT:
%	...
%
% Revision:
%   ...
%
% This function belongs to raPPPid, Copyright (c) 2023, M.F. Glaner
% *************************************************************************


% save time and time after last reset of current epoch
storeData.gpstime(Epoch.q,1) = Epoch.gps_time;
storeData.dt_last_reset(Epoch.q) = Epoch.gps_time-Adjust.reset_time;


Epoch = Epoch.old;   
Epoch.code  = [];      
Epoch.phase = [];
Adjust.float = false;
Adjust.fixed = false;
if ~Adjust.float 
    % reset reference satellites GPS & Galileo and fixed EW/WL/NL
    Epoch = resetRefSatGPS(Epoch);
    Epoch = resetRefSatGAL(Epoch);
end