function [Epoch, satellites, storeData, obs, model_save, Adjust] = ...
    initProcessing(settings, obs)
% initProcessing is called once in PPP_main.m before starting the
% epoch-wise calculation. It is used for creating the structs 
% Epoch, satellites, storeData, model_save and Adjust and
% initializing the variables of them and the struct obs
%
% INPUT:
%   settings        struct, settings for processing (from GUI)
%   obs             struct, observation corresponding data
% OUTPUT:
%   Epoch       	struct, epoch-specific data for currently processed epoch
%   satellites      struct, satellite specific data (e.g. elevation)
%   storeData       struct, collects data from all epochs (not used during epoch-wise processing)
%   obs             struct, observation corresponding data
%   model_save      struct, collects the modelled corrections for all epochs
%   Adjust      	struct, contains all adjustment relevant data for currently processed epoch
%
% Revision:
%   ...
%
% This function belongs to raPPPid, Copyright (c) 2023, M.F. Glaner
% *************************************************************************



proc_frqs = settings.INPUT.proc_freqs;		% number of processed frequencies
num_frqs = settings.INPUT.num_freqs;        % number of input frequencies
% expected total number of processed epochs
tot_eps = settings.PROC.epochs(2)-settings.PROC.epochs(1)+1;    

% booleans for processed GNSS
isGPS = settings.INPUT.use_GPS;
isGLO = settings.INPUT.use_GLO;
isGAL = settings.INPUT.use_GAL;
isBDS = settings.INPUT.use_BDS;


%% Adjust
% determine number of in all epochs estimated parameters (e.g., xyz but not
% ambiguities)
NO_PARAM = DEF.NO_PARAM_ZD;
Adjust.NO_PARAM = NO_PARAM;        
% Initialize Adjust for 1st epoch
Adjust.float = false;
Adjust.fixed = false;
Adjust.est_ZWD = false;             % true if ZWD is estimated in current epoch
Adjust.float_reset_epochs = 1;      % 1st epoch of processing is like a reset of the solution
Adjust.fixed_reset_epochs = 1;
Adjust.reset_time = NaN;            % initialized in resetSolution.m in first epoch, time of last reset in gps-time [sow]
Adjust.param = [];
% to store the omc values for check_omc
if settings.PROC.check_omc
    Adjust.code_omc  = [];
    Adjust.phase_omc = [];
    if ~isnan(settings.PROC.omc_window)
        Adjust.code_omc  = NaN(settings.PROC.omc_window+1, 399);
        Adjust.phase_omc = NaN(settings.PROC.omc_window+1, 399);
    end
end


%% obs
obs.total_epochs = tot_eps;         % total number of epochs


%% Epoch
% time
Epoch.gps_time = [];
Epoch.gps_week = [];
Epoch.mjd = [];
Epoch.q = 1;
% observations
Epoch.sats = [];
Epoch.obs = [];
Epoch.LLI_bit_rinex = [];       % LLI bit from Rinex file
Epoch.ss_digit_rinex = [];      % signal strength value from Rinex file
Epoch.code  = [];
Epoch.phase = [];
Epoch.C1 = [];          % code observations on 1st frequency
Epoch.C2 = [];          % code observations on 2nd frequency
Epoch.C3 = [];          % code observations on 3rd frequency
Epoch.L1 = [];          % phase observations on 1st frequency
Epoch.L2 = [];          % phase observations on 1st frequency
Epoch.L3 = [];          % phase observations on 1st frequency
% boolean vectors for each GNSS
Epoch.gps = [];
Epoch.glo = [];
Epoch.gal = [];
Epoch.bds = [];
Epoch.other_systems = [];
Epoch.tracked    = zeros(399,1);        % number of epochs each satellite is tracked, reset when cycle slip or under cutoff
% cycle slip variables
Epoch.cs_found = [];
Epoch.cs_dL1dL2 = [];
Epoch.cs_dL1dL3 = [];
Epoch.cs_dL2dL3 = [];
if settings.OTHER.CS.l1c1
    % difference L1 minus C1 [m], 1st row = last epoch, 2nd row = 2nd last epoch, ...
    Epoch.cs_L1C1     = NaN(settings.OTHER.CS.l1c1_window,399);
    Epoch.cs_pred_SF  = NaN(399,1);         % predicted values of L1-C1 (3rd degree polynomial)
end
if settings.OTHER.CS.TimeDifference
   Epoch.cs_phase_obs = NaN(settings.OTHER.CS.TD_degree+1,399);
end
if settings.OTHER.mp_detection
    Epoch.mp_C1 = NaN(settings.OTHER.mp_degree+1,399);
    Epoch.mp_last = NaN(1,399);
end

% variables for ambiguity fixing
Epoch.WL_12 = NaN(399,1);                  % WL Ambiguities between 1st and 2nd frequency
Epoch.WL_23 = NaN(399,1);                  % ...
Epoch.WL_13 = NaN(399,1);                  % ...
Epoch.NL_12 = NaN(399,1);                  % NL Ambiguities between 1st and 2nd frequency
Epoch.NL_23 = NaN(399,1);                  % ...               
Epoch.refSatGPS = 0;                    % GPS reference satellite, default/none = 0
Epoch.refSatGPS_idx = [];               % index of GPS reference satellite in Epoch.sats, default/none = []
Epoch.refSatGAL = 0;                    % Galileo reference satellite, default/none = 0
Epoch.refSatGAL_idx = [];               % index of Galileo reference satellite in Epoch.sats, default/none = []
Epoch.refSatBDS = 0;                    % BeiDou reference satellite, default/none = 0
Epoch.refSatBDS_idx = [];               % index of BeiDou reference satellite in Epoch.sats, default/none = []
% Multipath LCs
Epoch.mp1 = [];                         
Epoch.mp2 = [];
Epoch.mp1_var = [];
Epoch.mp2_var = [];
Epoch.MP_c = [];
Epoch.MP_p = [];
% frequency
Epoch.f1 = [];
Epoch.f2 = [];
Epoch.f3 = [];
Epoch.f1_glo = [];      % frequency of Glonass satellites on 1st processed frequency
Epoch.f2_glo = [];      % frequency of Glonass satellites on 2nd processed frequency
Epoch.f3_glo = [];      % frequency of Glonass satellites on 3rd processed frequency
% wavelength
Epoch.l1 = [];
Epoch.l2 = [];
Epoch.l3 = [];
% biases
Epoch.C1_bias = [];
Epoch.C2_bias = [];
Epoch.C3_bias = [];
Epoch.L1_bias = [];
Epoch.L2_bias = [];
Epoch.L3_bias = [];
% other
Epoch.sats = [];
Epoch.no_sats = [];
Epoch.delta_windup = [];
Epoch.rinex_header = [];
Epoch.usable = [];
Epoch.exclude = [];
Epoch.fixable = [];
% broadcast column
Epoch.BRDCcolumn = NaN(399,1);



%% storeData
storeData.gpstime = zeros(tot_eps,1);
storeData.dt_last_reset = zeros(tot_eps,1);
storeData.NO_PARAM = NO_PARAM;
storeData.obs_interval = obs.interval;
storeData.float = false(tot_eps,1);         % set to true when float position is achieved
% Adjusted Parameters and Covariance
storeData.param     = zeros(tot_eps, Adjust.NO_PARAM);
storeData.param_sigma = cell(tot_eps,1);    % cell as covariance matrix of parameters changes size over time
storeData.param_var = zeros(tot_eps,Adjust.NO_PARAM);
storeData.exclude = zeros(tot_eps,399);   	% boolean for sat under cutoff angle, 1 = under cutoff
% DOPs
storeData.PDOP = zeros(tot_eps,1);
storeData.HDOP = zeros(tot_eps,1);
storeData.VDOP = zeros(tot_eps,1);
% modelled zenith hydrostatic and wet delay
storeData.zhd = zeros(tot_eps,1);
storeData.zwd = zeros(tot_eps,1);

% variables depending on the number of processed frequencies
storeData.N_1    = zeros(tot_eps,399);              % float ambiguities
storeData.N_var_1 = zeros(tot_eps,399);             % variance of float ambiguities
storeData.residuals_code_1 = zeros(tot_eps,399);
if strcmpi(settings.PROC.method,'Code + Phase'); storeData.residuals_phase_1 = zeros(tot_eps,399); end
if proc_frqs > 1
    storeData.N_2    = zeros(tot_eps,399);
    storeData.N_var_2 = zeros(tot_eps,399);
    storeData.residuals_code_2 = zeros(tot_eps,399);
    if strcmpi(settings.PROC.method,'Code + Phase'); storeData.residuals_phase_2 = zeros(tot_eps,399); end
end
if proc_frqs > 2
    storeData.N_3    = zeros(tot_eps,399);
    storeData.N_var_3 = zeros(tot_eps,399);
    storeData.residuals_code_3 = zeros(tot_eps,399);
    if strcmpi(settings.PROC.method,'Code + Phase'); storeData.residuals_phase_3 = zeros(tot_eps,399); end
end

% Ambiguity Fixing is enabled
if settings.AMBFIX.bool_AMBFIX
    storeData.fixed = false(tot_eps,1);         % true if fixed solution in this epoch
    storeData.ttff = NaN;                       % time/epoch to first fix
    storeData.refSatGPS = NaN(tot_eps,1);       % GPS reference satellite
    storeData.refSatGAL = NaN(tot_eps,1);       % Galileo reference satellite
    storeData.refSatBDS = NaN(tot_eps,1);       % BeiDou reference satellite
    storeData.xyz_fix = zeros(tot_eps,3);    	% fixed coordinates
    storeData.param_var_fix = zeros(tot_eps,3);	% variances of fixed coordinates
    storeData.HMW_12 = zeros(tot_eps,399);       % HMW LC between 1st and 2nd frequency
    if proc_frqs >= 2
        storeData.HMW_23 = zeros(tot_eps,399);  	% HMW LC between 2nd and 3rd frequency
		storeData.HMW_13 = zeros(tot_eps,399);  % HMW LC between 1st and 3rd frequency
    end
    % code and phase residuals fixed solution
    storeData.residuals_code_fix_1  = zeros(tot_eps,399); 
    storeData.residuals_phase_fix_1 = zeros(tot_eps,399); 
    if proc_frqs >= 2
        storeData.residuals_code_fix_2  = zeros(tot_eps,399);
        storeData.residuals_phase_fix_2 = zeros(tot_eps,399);
    end
    if proc_frqs >= 3
        storeData.residuals_code_fix_3  = zeros(tot_eps,399);
        storeData.residuals_phase_fix_3 = zeros(tot_eps,399);
    end
    % fixed ambiguities
    if contains(settings.IONO.model,'IF-LC')
        storeData.N_WL_12      = NaN(tot_eps,399); 	% WL ambiguities
        storeData.N_NL_12      = NaN(tot_eps,399); 	% NL ambiguities
        if proc_frqs >= 2
            storeData.N_WL_23	= NaN(tot_eps,399); 	% EW ambiguities
            storeData.N_NL_23 	= NaN(tot_eps,399); 	% EN ambiguities
        end
    else
        storeData.N1_fixed  = NaN(tot_eps,399);  	% fixed ambiguities 1st frequency
        storeData.N2_fixed  = NaN(tot_eps,399);  	% fixed ambiguities 2nd frequency
        storeData.N3_fixed  = NaN(tot_eps,399);   	% fixed ambiguities 3rd frequency
		storeData.iono_fixed = zeros(tot_eps,399);  % fixed ionospheric delay estimation
    end
end
% for saving ionosphere correction data
if strcmpi(settings.IONO.model,'Estimate with ... as constraint') || strcmpi(settings.IONO.model,'Correct with ...')
    storeData.iono_corr = zeros(tot_eps,399);  % iono-range-correction on 1st frequency
    storeData.iono_mf   = zeros(tot_eps,399);  % mf from iono-correction
    storeData.iono_vtec = zeros(tot_eps,399);  % interpolated vtec
end

% cycle slip detection
% L1-C1
if settings.OTHER.CS.l1c1 
    storeData.cs_pred_SF  = zeros(tot_eps,399);   % predicted values
    storeData.cs_L1C1     = zeros(tot_eps,399);   % actual values
end
% dLi-dLj
if settings.OTHER.CS.DF 
    storeData.cs_dL1dL2   = zeros(tot_eps,399);   % dL1-dL2 = (L1 - L1_old) - (L2 - L2_old)
    if settings.INPUT.num_freqs > 2
        storeData.cs_dL1dL3   = zeros(tot_eps,399);
        storeData.cs_dL2dL3   = zeros(tot_eps,399);
    end
end
% Doppler
if settings.OTHER.CS.Doppler 
    storeData.cs_L1D1_diff	= zeros(tot_eps,399); % difference between L1 and predicted L1
    storeData.cs_L2D2_diff	= zeros(tot_eps,399); % difference between L2 and predicted L2
    storeData.cs_L3D3_diff	= zeros(tot_eps,399); % difference between L3 and predicted L3
end
% time difference
if settings.OTHER.CS.TimeDifference 
    storeData.cs_L1_diff	= zeros(tot_eps,399); % phase (L1) difference of last n epochs
end

% multipath detection
if settings.OTHER.mp_detection
    storeData.mp_C1_diff_n = zeros(tot_eps,399); % code (C1) difference of last n epochs
end


% when ionosphere is estimated
if strcmpi(settings.IONO.model,'Estimate with ... as constraint') || strcmpi(settings.IONO.model,'Estimate')  
    storeData.constraint = false(tot_eps,1);      % set to true when ionospheric constraint is used
    storeData.iono_est = zeros(tot_eps,399);      % values of estimated ionospheric delay
end
% for saving the code and phase observations
storeData.C1 = zeros(tot_eps,399);
storeData.C2 = zeros(tot_eps,399);
storeData.C3 = zeros(tot_eps,399);
storeData.L1 = zeros(tot_eps,399);
storeData.L2 = zeros(tot_eps,399);
storeData.L3 = zeros(tot_eps,399);
% for saving the applied code and phase biases
storeData.C1_bias = zeros(tot_eps,399);
storeData.C2_bias = zeros(tot_eps,399);
storeData.C3_bias = zeros(tot_eps,399);
storeData.L1_bias = zeros(tot_eps,399);
storeData.L2_bias = zeros(tot_eps,399);
storeData.L3_bias = zeros(tot_eps,399);
% Multipath-Linear-Combination
if settings.INPUT.num_freqs >= 2    % 2-Frequency MP-LC
    storeData.mp1 = zeros(tot_eps,399);
    storeData.mp2 = zeros(tot_eps,399);
end
if settings.INPUT.num_freqs >= 3    % 3-Frequency MP-LC
    storeData.MP_c = zeros(tot_eps,399);
    storeData.MP_p = zeros(tot_eps,399);
end


%% satellites
satellites.elev   = zeros(tot_eps,399);
satellites.az     = zeros(tot_eps,399);
satellites.obs    = zeros(tot_eps,399);   	% true if satellite observed
satellites.status = zeros(tot_eps,399);  	% info about satellite status

% variables depending on the number of frequencies
% Signal-to-Noise-Ration
satellites.SNR_1 =  zeros(tot_eps,399);
if num_frqs > 1; satellites.SNR_2 = zeros(tot_eps,399); end
if num_frqs > 2; satellites.SNR_3 = zeros(tot_eps,399); end
if settings.EXP.satellites_D
    satellites.D1 =  zeros(tot_eps,399);
    if num_frqs > 1; satellites.D2 = zeros(tot_eps,399); end
    if num_frqs > 2; satellites.D3 = zeros(tot_eps,399); end
end


%% model_save
model_save = [];
if settings.EXP.model_save
    model_save.phase  = zeros(tot_eps,399,proc_frqs);          % modelled phase ranges
    model_save.code   = zeros(tot_eps,399,proc_frqs);          % modelled code ranges
    model_save.rho    = zeros(tot_eps,399);     	% theoretical range, maybe recalculated in iteration of epoch
    model_save.dT_sat = zeros(tot_eps,399);     	% Satellite clock correction
    model_save.dTrel  = zeros(tot_eps,399);       % Relativistic clock correction
    model_save.dT_sat_rel = zeros(tot_eps,399);	% Satellite clock  + relativistic correction
    model_save.Ttr    = zeros(tot_eps,399); 		% Signal transmission time
    model_save.k	  = zeros(tot_eps,399);  		% Column of ephemerides
    model_save.trop   = zeros(tot_eps,399);   	% Troposphere delay for elevation
    model_save.ZTD    = zeros(tot_eps,399);	 	% Troposphere total zenith delay (if estimated only ZHD)
    model_save.iono   = zeros(tot_eps,399,proc_frqs);          % Ionosphere delay
    model_save.mfw    = zeros(tot_eps,399);     	% Wet tropo mapping function
    model_save.zwd    = zeros(tot_eps,1);     		% zenith wet delay
    model_save.zhd    = zeros(tot_eps,1);     		% zenith hydrostatic delay
    model_save.delta_windup = zeros(tot_eps,399); % Phase windup effect in cycles
    model_save.windup      = zeros(tot_eps,399,proc_frqs);     % Phase windup effect, scaled to frequency
    model_save.solid_tides = zeros(tot_eps,399);	% Solid tides range correction
    model_save.ocean_loading = zeros(tot_eps,399);	% Ocean loading range correction
    model_save.PCO_rec = zeros(tot_eps,399,proc_frqs);	% Receiver phase center offset corrections
    model_save.PCV_rec = zeros(tot_eps,399,proc_frqs);	% Receiver phase center variation corrections
    model_save.ARP_ECEF = zeros(tot_eps,399,proc_frqs);  	% Receiver antenna reference point correction
    model_save.PCO_sat = zeros(tot_eps,399,proc_frqs);	% Satellite antenna phase center offset
    model_save.PCV_sat = zeros(tot_eps,399,proc_frqs);	% Satellite antenna phase center variation
    model_save.ECEF_X = zeros(tot_eps,399,3);    	% Sat Position before correcting the earth rotation during runtime tau
    model_save.ECEF_V = zeros(tot_eps,399,3); 	% Sat Velocity before correcting the earth rotation during runtime tau
    model_save.Rot_X = zeros(tot_eps,399,3);   	% Sat Position after correcting the earth rotation during runtime tau
    model_save.Rot_V = zeros(tot_eps,399,3);   	% Sat Velocity after correcting the earth rotation during runtime tau
end


