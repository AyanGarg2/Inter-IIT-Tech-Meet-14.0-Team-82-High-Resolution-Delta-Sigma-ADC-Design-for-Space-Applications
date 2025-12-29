%% DELTA-SIGMA ADC: ENOB vs SAMPLING RATE TRADE-OFF ANALYSIS
% Fully dynamic decimation architecture that adapts to any OSR
% Ensures total decimation always matches OSR exactly

clear; clc; close all;

%% 1. CONFIGURATION
fprintf('========================================================\n');
fprintf('  ENOB vs SAMPLING RATE TRADE-OFF ANALYSIS\n');
fprintf('  Dynamic Decimation Architecture\n');
fprintf('========================================================\n\n');

% Fixed Parameters
Fs_modulator = 8.192e6;  % Fixed modulator frequency (8.192 MHz)
MODEL_NAME = 'INTER_IIT_2ndorder_without_noise_DSM';

% Sampling Rate Test Points
Fs_out_targets = [500, 1e3, 2e3];  % Hz

% Validate sampling rates
Fs_out_targets = Fs_out_targets(Fs_out_targets > 0 & Fs_out_targets < Fs_modulator);
if isempty(Fs_out_targets)
    error('No valid sampling rates! Must be 0 < Fs_out < %.2f MHz', Fs_modulator/1e6);
end

% Pre-allocate results
N_points = length(Fs_out_targets);
Results = struct();
Results.Fs_out = zeros(N_points, 1);
Results.OSR = zeros(N_points, 1);
Results.SNDR = zeros(N_points, 1);
Results.ENOB = zeros(N_points, 1);
Results.SFDR = zeros(N_points, 1);
Results.NoiseFloor = zeros(N_points, 1);
Results.FilterStages = cell(N_points, 1);
Results.TotalTaps = zeros(N_points, 1);
Results.CIC_R = zeros(N_points, 1);
Results.HB_Stages = zeros(N_points, 1);
Results.FIR_R = zeros(N_points, 1);
Results.ActualDecimation = zeros(N_points, 1);
Results.Success = false(N_points, 1);

fprintf('Configuration:\n');
fprintf('  Modulator Rate: %.3f MHz\n', Fs_modulator/1e6);
fprintf('  Test Points: %d sampling rates\n', N_points);
fprintf('  Range: %.1f Hz to %.1f kHz\n\n', min(Fs_out_targets), max(Fs_out_targets)/1e3);

%% 2. RUN SIMULINK ONCE TO GET BITSTREAM
fprintf('Running Simulink model: %s\n', MODEL_NAME);
try
    simOut = sim(MODEL_NAME, 'ReturnWorkspaceOutputs','on');
    fprintf('✓ Simulink simulation completed\n\n');
catch ME
    warning('Simulink run with outputs failed: %s', ME.message);
    try
        sim(MODEL_NAME);
        simOut = [];
        fprintf('✓ Simulink simulation completed (workspace mode)\n\n');
    catch ME2
        error('Failed to run Simulink model: %s', ME2.message);
    end
end

% Extract bitstream with robust error handling
v_bitstream = extract_bitstream(simOut);
v_bipolar = prepare_bitstream(v_bitstream);
fprintf('Bitstream Ready: %d samples @ %.3f MHz\n\n', length(v_bipolar), Fs_modulator/1e6);

%% 3. SWEEP THROUGH SAMPLING RATES
fprintf('Starting Trade-off Analysis...\n');
fprintf('================================================\n\n');

for idx = 1:N_points
    Fs_out = Fs_out_targets(idx);
    OSR_desired = Fs_modulator / Fs_out;
    OSR = round(OSR_desired);
    
    % Validate OSR
    if OSR < 2
        warning('[%d/%d] OSR = %d is too low (min 2). Skipping Fs_out = %.1f Hz', ...
                idx, N_points, OSR, Fs_out);
        continue;
    end
    
    fprintf('[%d/%d] Fs_out = %.1f Hz → OSR = %d\n', idx, N_points, Fs_out, OSR);
    
    % Design optimal filter chain
    try
        [Filters, FilterInfo] = design_adaptive_filter_chain(OSR, Fs_out);
        fprintf('  ✓ Chain: %s\n', FilterInfo.description);
        fprintf('    Decimation: CIC(%d) × HB(2^%d) × FIR(%d) = %d\n', ...
                FilterInfo.cic_r, FilterInfo.hb_stages, FilterInfo.fir_r, FilterInfo.total_decimation);
        
        % Critical verification
        if FilterInfo.total_decimation ~= OSR
            error('Decimation mismatch: got %d, expected %d', FilterInfo.total_decimation, OSR);
        end
    catch ME
        warning('  ✗ Filter design failed: %s\n\n', ME.message);
        continue;
    end
    
    % Process signal
    try
        v_padded = pad_bitstream(v_bipolar, OSR);
        y_out = apply_filter_chain(v_padded, Filters, FilterInfo);
        
        % Validate output
        if isempty(y_out) || all(isnan(y_out)) || length(y_out) < 100
            error('Invalid filter output');
        end
        
        % Calculate metrics
        [sndr, enob, sfdr, noise_floor] = calculate_metrics(y_out, Fs_out);
        
        % Store results
        Results.Fs_out(idx) = Fs_out;
        Results.OSR(idx) = OSR;
        Results.SNDR(idx) = sndr;
        Results.ENOB(idx) = enob;
        Results.SFDR(idx) = sfdr;
        Results.NoiseFloor(idx) = noise_floor;
        Results.FilterStages{idx} = FilterInfo.description;
        Results.TotalTaps(idx) = FilterInfo.total_taps;
        Results.CIC_R(idx) = FilterInfo.cic_r;
        Results.HB_Stages(idx) = FilterInfo.hb_stages;
        Results.FIR_R(idx) = FilterInfo.fir_r;
        Results.ActualDecimation(idx) = FilterInfo.total_decimation;
        Results.Success(idx) = true;
        
        fprintf('  → ENOB = %.2f bits | SNDR = %.2f dB | SFDR = %.2f dB\n', enob, sndr, sfdr);
        fprintf('     Complexity: %d taps | Output samples: %d\n\n', FilterInfo.total_taps, length(y_out));
        
    catch ME
        warning('  ✗ Processing failed: %s\n\n', ME.message);
        continue;
    end
end

fprintf('================================================\n');
fprintf('✓ Trade-off Analysis Complete!\n\n');

%% 4. FILTER RESULTS
valid_idx = Results.Success;
n_valid = sum(valid_idx);

if n_valid == 0
    error('No valid results obtained! Check Simulink model and bitstream.');
end

fprintf('Successfully processed %d/%d test points\n\n', n_valid, N_points);

% Keep only valid results
fields = fieldnames(Results);
for f = 1:length(fields)
    field_name = fields{f};
    if strcmp(field_name, 'Success')
        continue;
    end
    if ~iscell(Results.(field_name))
        Results.(field_name) = Results.(field_name)(valid_idx);
    else
        Results.(field_name) = Results.(field_name)(valid_idx);
    end
end

%% 5. RESULTS TABLE
fprintf('========================================================\n');
fprintf('              RESULTS SUMMARY\n');
fprintf('========================================================\n\n');
fprintf('%-10s | %-8s | %-8s | %-8s | %-8s | %-10s | %-14s\n', ...
        'Fs_out', 'OSR', 'ENOB', 'SNDR', 'SFDR', 'Taps', 'Architecture');
fprintf('%-10s | %-8s | %-8s | %-8s | %-8s | %-10s | %-14s\n', ...
        '[Hz]', '', '[bits]', '[dB]', '[dB]', '', '');
fprintf('----------------------------------------------------------------------------------------\n');

for idx = 1:length(Results.Fs_out)
    if Results.Fs_out(idx) >= 1000
        fs_str = sprintf('%.1f kHz', Results.Fs_out(idx)/1e3);
    else
        fs_str = sprintf('%.0f Hz', Results.Fs_out(idx));
    end
    fprintf('%-10s | %-8d | %8.2f | %8.2f | %8.2f | %10d | %-14s\n', ...
            fs_str, Results.OSR(idx), Results.ENOB(idx), Results.SNDR(idx), ...
            Results.SFDR(idx), Results.TotalTaps(idx), Results.FilterStages{idx});
end
fprintf('========================================================\n\n');

% Analysis
[max_enob, max_idx] = max(Results.ENOB);
fprintf('🏆 Peak Performance:\n');
fprintf('   Fs = %.1f Hz | ENOB = %.2f bits | OSR = %d\n', ...
        Results.Fs_out(max_idx), max_enob, Results.OSR(max_idx));
fprintf('   Architecture: %s\n\n', Results.FilterStages{max_idx});

efficiency = Results.ENOB ./ Results.TotalTaps * 1000;
[max_eff, eff_idx] = max(efficiency);
fprintf('⚡ Most Efficient:\n');
fprintf('   Fs = %.1f Hz | ENOB = %.2f bits | %.3f ENOB/kTap\n\n', ...
        Results.Fs_out(eff_idx), Results.ENOB(eff_idx), max_eff);

%% 6. PLOTS
fprintf('Generating plots...\n');

fig = figure('Name', 'ENOB vs Sampling Rate', 'Color', 'w', 'Position', [50 50 1600 1000]);

% Plot 1: ENOB vs Sampling Rate
subplot(2,3,1);
semilogx(Results.Fs_out, Results.ENOB, 'b-o', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'b');
hold on;
yline(16, 'r--', 'LineWidth', 2, 'Label', '16-bit');
yline(14, 'g--', 'LineWidth', 1.5, 'Label', '14-bit');
xlabel('Sampling Rate [Hz]', 'FontWeight', 'bold');
ylabel('ENOB [bits]', 'FontWeight', 'bold');
title('ENOB vs Sampling Rate', 'FontSize', 12, 'FontWeight', 'bold');
grid on; grid minor;

% Plot 2: SNDR
subplot(2,3,2);
semilogx(Results.Fs_out, Results.SNDR, 'r-s', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'r');
hold on;
yline(98, 'b--', 'LineWidth', 2, 'Label', '98 dB (16-bit)');
xlabel('Sampling Rate [Hz]', 'FontWeight', 'bold');
ylabel('SNDR [dB]', 'FontWeight', 'bold');
title('SNDR vs Sampling Rate', 'FontSize', 12, 'FontWeight', 'bold');
grid on; grid minor;

% Plot 3: OSR
subplot(2,3,3);
loglog(Results.Fs_out, Results.OSR, 'g-^', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'g');
xlabel('Sampling Rate [Hz]', 'FontWeight', 'bold');
ylabel('OSR', 'FontWeight', 'bold');
title('Oversampling Ratio', 'FontSize', 12, 'FontWeight', 'bold');
grid on; grid minor;

% Plot 4: Complexity
subplot(2,3,4);
yyaxis left;
semilogx(Results.Fs_out, Results.TotalTaps, 'b-o', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'b');
ylabel('Total Taps', 'FontWeight', 'bold', 'Color', 'b');
yyaxis right;
semilogx(Results.Fs_out, Results.HB_Stages, 'r-s', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'r');
ylabel('HB Stages', 'FontWeight', 'bold', 'Color', 'r');
xlabel('Sampling Rate [Hz]', 'FontWeight', 'bold');
title('Filter Complexity', 'FontSize', 12, 'FontWeight', 'bold');
grid on; grid minor;

% Plot 5: ENOB vs OSR (Theory)
subplot(2,3,5);
loglog(Results.OSR, Results.ENOB, 'k-o', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'k');
hold on;
OSR_th = logspace(log10(min(Results.OSR)), log10(max(Results.OSR)), 100);
ENOB_th = 1.76 * log2(OSR_th) - 3.5;
loglog(OSR_th, ENOB_th, 'r--', 'LineWidth', 2);
xlabel('OSR', 'FontWeight', 'bold');
ylabel('ENOB [bits]', 'FontWeight', 'bold');
title('ENOB vs OSR', 'FontSize', 12, 'FontWeight', 'bold');
legend('Measured', 'Theoretical', 'Location', 'best');
grid on; grid minor;

% Plot 6: Efficiency
subplot(2,3,6);
semilogx(Results.Fs_out, efficiency, 'm-d', 'LineWidth', 2.5, 'MarkerSize', 8, 'MarkerFaceColor', 'm');
hold on;
plot(Results.Fs_out(eff_idx), efficiency(eff_idx), 'ro', 'MarkerSize', 12, 'LineWidth', 3);
xlabel('Sampling Rate [Hz]', 'FontWeight', 'bold');
ylabel('ENOB per kTap', 'FontWeight', 'bold');
title('Design Efficiency', 'FontSize', 12, 'FontWeight', 'bold');
grid on; grid minor;

fprintf('✓ Plots complete\n\n');

%% 7. EXPORT
csv_file = sprintf('ENOB_SamplingRate_%s.csv', datestr(now, 'yyyymmdd_HHMMSS'));
T = table(Results.Fs_out, Results.OSR, Results.ENOB, Results.SNDR, Results.SFDR, ...
          Results.NoiseFloor, Results.TotalTaps, Results.CIC_R, Results.HB_Stages, ...
          Results.FIR_R, Results.ActualDecimation, ...
          'VariableNames', {'Fs_out_Hz', 'OSR', 'ENOB_bits', 'SNDR_dB', 'SFDR_dB', ...
                            'NoiseFloor_dB', 'TotalTaps', 'CIC_Dec', 'HB_Stages', ...
                            'FIR_Dec', 'TotalDec'});
writetable(T, csv_file);
fprintf('✓ Results saved: %s\n\n', csv_file);

fprintf('========================================================\n');
fprintf('            ANALYSIS COMPLETE ✓\n');
fprintf('========================================================\n');

%% ======================================================================
%%                      HELPER FUNCTIONS
%% ======================================================================

function v_bitstream = extract_bitstream(simOut)
    v_bitstream = [];
    
    % Try simOut properties
    if ~isempty(simOut)
        names = {'dsm_out', 'dsmOut', 'yout', 'output', 'bitstream'};
        for i = 1:length(names)
            try
                if isprop(simOut, names{i})
                    v_bitstream = simOut.(names{i});
                    break;
                end
            catch
            end
        end
    end
    
    % Try workspace
    if isempty(v_bitstream)
        names = {'dsm_out', 'dsmOut', 'yout', 'output', 'bitstream'};
        for i = 1:length(names)
            try
                if evalin('base', sprintf('exist(''%s'', ''var'')', names{i}))
                    v_bitstream = evalin('base', names{i});
                    break;
                end
            catch
            end
        end
    end
    
    if isempty(v_bitstream)
        error('Bitstream not found! Check Simulink output configuration.');
    end
    
    % Extract data from timeseries/struct
    if isobject(v_bitstream)
        if isprop(v_bitstream, 'Data')
            v_bitstream = v_bitstream.Data;
        elseif isprop(v_bitstream, 'signals')
            v_bitstream = v_bitstream.signals.values;
        end
    end
end

function v_bipolar = prepare_bitstream(v_bitstream)
    v_bitstream = double(v_bitstream(:));
    
    if isempty(v_bitstream)
        error('Bitstream is empty');
    end
    
    % Remove NaN
    v_bitstream = v_bitstream(~isnan(v_bitstream));
    
    % Convert to bipolar
    if min(v_bitstream) >= 0 && max(v_bitstream) <= 1
        v_bipolar = 2*v_bitstream - 1;
    else
        v_bipolar = v_bitstream;
        if max(abs(v_bipolar)) > 1.5
            v_bipolar = v_bipolar / max(abs(v_bipolar));
        end
    end
end

function v_padded = pad_bitstream(v_bipolar, OSR)
    rem = mod(length(v_bipolar), OSR);
    if rem ~= 0
        v_padded = [v_bipolar; zeros(OSR - rem, 1)];
    else
        v_padded = v_bipolar;
    end
end

function [Filters, Info] = design_adaptive_filter_chain(OSR, ~)
    % DYNAMIC DECIMATION: CIC × 2^HB × FIR = OSR (GUARANTEED)
    
    if OSR < 2
        error('OSR must be >= 2');
    end
    
    % Step 1: Choose CIC decimation (prefer power of 2)
    cic_opts = [256, 128, 64, 32, 16, 8, 4, 2];
    CIC_R = 1;
    for c = cic_opts
        if mod(OSR, c) == 0
            CIC_R = c;
            break;
        end
    end
    
    if CIC_R == 1
        % Use largest factor if no power of 2 works
        factors = factor(OSR);
        CIC_R = max(factors(factors <= 64));
        if CIC_R < 2
            CIC_R = 2;
        end
    end
    
    % Step 2: Extract halfband stages (powers of 2)
    R_rem = OSR / CIC_R;
    HB_count = 0;
    while mod(R_rem, 2) == 0 && R_rem > 1
        HB_count = HB_count + 1;
        R_rem = R_rem / 2;
    end
    
    % Step 3: Final FIR handles remainder
    FIR_R = R_rem;
    
    % Verify
    total_dec = CIC_R * (2^HB_count) * FIR_R;
    assert(total_dec == OSR, 'Decimation error: %d ≠ %d', total_dec, OSR);
    
    % Build filters
    Filters = cell(1, 2 + HB_count);
    total_taps = 0;
    
    % CIC
    Filters{1} = dsp.CICDecimator(CIC_R, 1, 6);
    Filters{1}.FixedPointDataType = 'Specify word and fraction lengths';
    Filters{1}.SectionWordLengths = 58;
    Filters{1}.OutputWordLength = 58;
    Filters{1}.OutputFractionLength = 0;
    
    % Halfbands
    for k = 1:HB_count
        if k == 1
            N = 10; TW = 0.15;
        elseif k == 2
            N = 14; TW = 0.10;
        elseif k == 3
            N = 18; TW = 0.08;
        else
            N = 22; TW = 0.06;
        end
        
        hb = design(fdesign.decimator(2, 'halfband', 'N,TW', N, TW), 'equiripple', 'SystemObject', true);
        Filters{k+1} = dsp.FIRDecimator(2, hb.Numerator);
        config_fir_fixed(Filters{k+1});
        total_taps = total_taps + length(hb.Numerator);
    end
    
    % Final FIR
    if FIR_R > 1
        N = min(51, 15 + round(8 * log2(FIR_R)));
        try
            fir = design(fdesign.decimator(FIR_R, 'lowpass', 0.35, 0.65, 0.01, 80), 'equiripple', 'SystemObject', true);
        catch
            fir = design(fdesign.decimator(FIR_R, 'lowpass', 'N,Fc', N, 0.4), 'window', 'SystemObject', true);
        end
        Filters{end} = dsp.FIRDecimator(FIR_R, fir.Numerator);
    else
        fir = design(fdesign.lowpass('N,Fc', 27, 0.4), 'window', 'SystemObject', true);
        Filters{end} = dsp.FIRDecimator(1, fir.Numerator);
    end
    config_fir_fixed(Filters{end});
    total_taps = total_taps + length(fir.Numerator);
    
    % Info
    Info.cic_r = CIC_R;
    Info.hb_stages = HB_count;
    Info.fir_r = FIR_R;
    Info.total_decimation = total_dec;
    Info.total_taps = total_taps;
    Info.description = sprintf('CIC(%d)→%dxHB→FIR(%d)', CIC_R, HB_count, FIR_R);
end

function config_fir_fixed(fir)
    fir.FullPrecisionOverride = false;
    fir.CoefficientsDataType = 'Custom';
    fir.CustomCoefficientsDataType = numerictype('Signedness','Auto','WordLength',16,'FractionLength',15);
    fir.ProductDataType = 'Custom';
    fir.CustomProductDataType = numerictype('Signedness','Auto','WordLength',38,'FractionLength',33);
    fir.AccumulatorDataType = 'Custom';
    fir.CustomAccumulatorDataType = numerictype('Signedness','Auto','WordLength',54,'FractionLength',33);
    fir.OutputDataType = 'Custom';
    fir.CustomOutputDataType = numerictype('Signedness','Auto','WordLength',22,'FractionLength',18);
end

function y = apply_filter_chain(v, Filters, ~)
    sig = fi(v, 1, 2, 0);
    
    % CIC
    sig = step(Filters{1}, sig);
    val = double(sig) * (2^-48) * 0.85;
    sig = fi(val, 1, 22, 18);
    
    % Rest
    for k = 2:length(Filters)
        sig = step(Filters{k}, sig);
    end
    
    y = double(sig);
end

function [sndr, enob, sfdr, nf] = calculate_metrics(y, ~)
    % Remove transient
    N_tr = min(1024, round(0.1 * length(y)));
    ys = y(N_tr+1:end);
    
    % FFT
    N = 2^floor(log2(length(ys)));
    N = max(N, 256);
    v = ys(1:min(N, length(ys)));
    v = v - mean(v);
    
    win = hanning(length(v));
    fft_out = fft(v .* win, N);
    P = abs(fft_out).^2;
    P = P(1:floor(N/2)+1);
    
    % Find peak
    [Ppeak, idx] = max(P(3:end));
    idx = idx + 2;
    
    % Signal vs noise
    span = min(20, floor(length(P) * 0.05));
    sig_bins = max(3, idx-span) : min(length(P), idx+span);
    noise_bins = setdiff(3:length(P), sig_bins);
    
    Psig = sum(P(sig_bins));
    Pnoise = sum(P(noise_bins));
    
    sndr = 10*log10(Psig / Pnoise);
    enob = (sndr - 1.76) / 6.02;
    sfdr = 10*log10(Ppeak / max(P(noise_bins)));
    nf = 10*log10(mean(P(noise_bins)));
end