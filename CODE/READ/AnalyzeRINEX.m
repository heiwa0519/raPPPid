function [] = AnalyzeRINEX(settings)
% This function performs a raw analysis of a RINEX file and, thereby, uses 
% many function from raPPPid. 
% 
% INPUT:
%   settings        struct, settings from GUI
% OUTPUT:
%	...
%
% Revision:
%   ...
%
% This function belongs to raPPPid, Copyright (c) 2023, M.F. Glaner
% *************************************************************************


% read RINEX header and epochs
[obs] = anheader(settings);
[RINEX, epochheader] = readRINEX(settings.INPUT.file_obs, obs.rinex_version);

% print some information
fprintf('\nStation: %s',  obs.stationname);
fprintf('\nReceiver: %s', obs.receiver_type);
fprintf('\nAntenna: %s',  obs.antenna_type);

% print observation types indicated in RINEX header
fprintf('\n\nObservation types (RINEX header)\n')
if obs.rinex_version == 3
    fprintf('GPS: '); print_obs_types(obs.types_gps_3, 3);
    fprintf('GLO: '); print_obs_types(obs.types_glo_3, 3);
    fprintf('GAL: '); print_obs_types(obs.types_gal_3, 3);
    fprintf('BDS: '); print_obs_types(obs.types_bds_3, 3);
else
    fprintf('GPS: '); print_obs_types(obs.types_gps, 2);
    fprintf('GLO: '); print_obs_types(obs.types_glo, 2);
    fprintf('GAL: '); print_obs_types(obs.types_gal, 2);
    fprintf('BDS: '); print_obs_types(obs.types_bds, 2);
end

% number of epochs
n = numel(epochheader);
fprintf('\n%s%.0f', 'Total number of epochs: ', n);
fprintf('\n%s%.0f\n', 'Observation interval [s]: ', obs.interval);
% hardcode some settings
settings.PROC.timeFrame(2) = 1; settings.PROC.timeFrame(2) = n;
settings.PROC.epochs(1) = 1; settings.PROC.epochs(2) = n;
settings.INPUT.num_freqs = max([ ... 
    settings.INPUT.use_GPS*numel(settings.INPUT.gps_freq(~strcmpi(settings.INPUT.gps_freq,'OFF'))), ...
    settings.INPUT.use_GLO*numel(settings.INPUT.glo_freq(~strcmpi(settings.INPUT.glo_freq,'OFF'))), ...
    settings.INPUT.use_GAL*numel(settings.INPUT.gal_freq(~strcmpi(settings.INPUT.gal_freq,'OFF'))), ...
    settings.INPUT.use_BDS*numel(settings.INPUT.bds_freq(~strcmpi(settings.INPUT.bds_freq,'OFF')))      ]);
settings.INPUT.proc_freqs = settings.INPUT.num_freqs;
settings.PROC.method = 'Code + Phase + Doppler';
settings.IONO.model = 'off';
settings.EXP.satellites_D = 1;

% Prepare variables
[Epoch, satellites, storeData, ~, ~, ~] = initProcessing(settings, obs);

% Looking for the observation types and the right column number
obs = find_obs_col(obs, settings);

% Create waitbar with option to cancel
f = waitbar(0,'0%','Name','Analyzing RINEX File', 'CreateCancelBtn','setappdata(gcbf,''canceling'',1)');
setappdata(f,'canceling',0);


%% LOOP OVER RINEX DATA
for q = 1:n
    % get observations
    [Epoch] = EpochlyReset_Epoch(Epoch);    
    [Epoch] = RINEX2epochData(RINEX, epochheader, Epoch, q, obs.no_obs_types, obs.rinex_version, settings.PROC.LLI, settings.INPUT.use_GPS, settings.INPUT.use_GLO, settings.INPUT.use_GAL, settings.INPUT.use_BDS);
    if ~Epoch.usable
        storeData.gpstime(q,1) = Epoch.gps_time;
        continue
    end
    [Epoch, obs] = prepareObservations(settings, obs, Epoch, q);
    % save relevant data
    prns = Epoch.sats;
    % increase epoch counter
    Epoch.tracked(prns) = Epoch.tracked(prns) + 1;
    % save Signal-to-noise ratio
    if ~isempty(Epoch.S1); satellites.SNR_1(q,prns) = Epoch.S1'; end
    if ~isempty(Epoch.S2); satellites.SNR_2(q,prns) = Epoch.S2'; end
    if ~isempty(Epoch.S3); satellites.SNR_3(q,prns) = Epoch.S3'; end
    % save Doppler measurements
    if ~isempty(Epoch.D1); satellites.D1(q,prns) = Epoch.D1'; end
    if ~isempty(Epoch.D2); satellites.D2(q,prns) = Epoch.D2'; end
    if ~isempty(Epoch.D3); satellites.D3(q,prns) = Epoch.D3'; end
    % observations
    storeData.C1(q,prns) = Epoch.C1;
    storeData.C1_bias(q,prns) = Epoch.C1_bias;
    if ~isempty(Epoch.C2); storeData.C2(q,prns) = Epoch.C2; end
    if ~isempty(Epoch.C3); storeData.C3(q,prns) = Epoch.C3; end
    if ~isempty(Epoch.L1); storeData.L1(q,prns) = Epoch.L1; end
    if ~isempty(Epoch.L2); storeData.L2(q,prns) = Epoch.L2; end
    if ~isempty(Epoch.L3); storeData.L3(q,prns) = Epoch.L3; end
    satellites.obs(q,prns)  = Epoch.tracked(prns);  	% save number of epochs satellite is tracked
    % time
    storeData.gpstime(q,1) = Epoch.gps_time;
    % tracked satellites
    satellites.obs(q,prns)  = Epoch.tracked(prns);  	% save number of epochs satellite is tracked

    % handle waitbar
    if mod(q,5) == 0
        % Check for clicked Cancel button
        if getappdata(f,'canceling'); delete(f); return; end
        % Update waitbar
        waitbar(q/n,f,sprintf('Progress: %.2f%%',q/n*100))
    end
end

% kill waitbar
delete(f)

%% PLOTS
rgb = distinguishable_colors(40);      % colors for plot, no GNSS has more than 40 satellites
% GNSS to invastigate
isGPS = settings.INPUT.use_GPS;          
isGLO = settings.INPUT.use_GLO;
isGAL = settings.INPUT.use_GAL;
isBDS = settings.INPUT.use_BDS;
% create some time variables
epochs = 1:numel(storeData.gpstime);       % vector, 1:#epochs
sow = storeData.gpstime;        % time of epochs in seconds of week
sow = round(10*sow)/10;         % needed if observation in RINEX are not to full second
seconds = sow - sow(1);
hours = seconds / 3600;
[~, hour, min, sec] = sow2dhms(storeData.gpstime(1));
label_x_sec = ['[s], 1st Epoch: ', sprintf('%02d',hour),   'h:',   sprintf('%02d',min),   'm:',   sprintf('%02.0f',sec),   's'];
label_x_h   = ['[h], 1st Epoch: ', sprintf('%02d',hour),   'h:',   sprintf('%02d',min),   'm:',   sprintf('%02.0f',sec),   's'];
label_x_time =  ['Time, 1st Epoch: ', sprintf('%02d',hour),   'h:',   sprintf('%02d',min),   'm:',   sprintf('%02.0f',sec),   's'];
label_x_epc = 'Epochs';
% get stored observations
C1 = storeData.C1; C1(C1==0) = NaN;
C2 = storeData.C2; C2(C2==0) = NaN;
C3 = storeData.C3; C3(C3==0) = NaN;
L1 = storeData.L1; L1(L1==0) = NaN;
L2 = storeData.L2; L2(L2==0) = NaN;
L3 = storeData.L3; L3(L3==0) = NaN;

%     -+-+-+-+- Figures: Signal Quality Plots  -+-+-+-+-
satellites.CL_1 = C1 - L1;
satellites.CL_2 = C2 - L2;
satellites.CL_3 = C3 - L3;
signQualPlot(satellites, label_x_h, hours, isGPS, isGLO, isGAL, isBDS, settings);


% -+-+-+-+- Figure: Satellite Visibility Plot -+-+-+-+-
vis_plotSatConstellation(hours, epochs, label_x_h, satellites, storeData.exclude, isGPS, isGLO, isGAL, isBDS)


if obs.interval < 5     % this plots make only sense for high-rate observation data
    % -+-+-+-+- Figure: Code Difference  -+-+-+-+-
    settings.OTHER.mp_thresh = NaN;
    degree_C = settings.OTHER.mp_degree;
    storeData.mp_C1_diff_n = NaN(n,399);   	% code (L1) difference of last n epochs
    storeData.mp_C1_diff_n(degree_C+1:end,:) = diff(C1, degree_C,1);
    CodeDifference(epochs, storeData, label_x_epc, [], rgb, settings, satellites);
    
    % -+-+-+-+- Figure: Phase Difference  -+-+-+-+-
    degree_L = settings.OTHER.CS.TD_degree;	
    storeData.cs_L1_diff = NaN(n,399);   	% phase (L1) difference of last n epochs
    storeData.cs_L1_diff(degree_L+1:end,:) = diff(L1, degree_L,1);
    storeData.float_reset_epochs = [];
    PhaseDifference(epochs, storeData, label_x_epc, [], rgb, settings, satellites);
    
    % -+-+-+-+- Figure: Doppler Difference  -+-+-+-+-
    degree_D = 3;
    D1 = satellites.D1; D1(D1==0) = NaN;    
    storeData.D1_diff = NaN(n,399);         % Doppler (D1) difference of last n epochs
    storeData.D1_diff(degree_D+1:end,:) = diff(D1, degree_D,1);
    DopplerDifference(epochs, storeData, label_x_epc, [], rgb, settings, satellites);
    
% for each satellite
%     if isGPS; vis_cs_time_difference(storeData, 'G', degree_L, NaN); end
%     if isGLO; vis_cs_time_difference(storeData, 'R', degree_L, NaN); end
%     if isGAL; vis_cs_time_difference(storeData, 'E', degree_L, NaN); end
%     if isBDS; vis_cs_time_difference(storeData, 'C', degree_L, NaN); end
end




function [] = print_obs_types(obs_type_string, v)
% print observation types from RINEX header
if isempty(obs_type_string) 
    fprintf('\n');      % GNSS was not recorded
    return
end
n = numel(obs_type_string);
for i = 1:v:n           % loop to print 
    fprintf('%s ', obs_type_string(i:i+v-1));
end
fprintf('\n');




