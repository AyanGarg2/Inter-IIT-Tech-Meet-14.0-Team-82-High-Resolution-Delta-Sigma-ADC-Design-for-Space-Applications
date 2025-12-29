%% DELTA-SIGMA ADC: SIMULINK BITSTREAM + 5-STAGE OPTIMIZED FILTERING
% Takes raw bitstream from Simulink and applies 5-stage optimized filter chain
% Target: 16+ ENOB | Fs_out: 2 kSps
% Architecture: CIC(256) -> HB(2) -> HB(2) -> HB(2) -> FIR(2)

clear; clc; close all;

%% 1. SYSTEM SPECIFICATIONS
Fs_out = 2e3;
OSR = 4096;
Fs_in = Fs_out * OSR;
MODEL_NAME = 'third_order';   % <-- set your model name here (without .slx)

fprintf('================================================\n');
fprintf('DSM BITSTREAM FROM SIMULINK + 5-STAGE FILTERING\n');
fprintf('================================================\n');

%% 2. RUN SIMULINK and IMPORT BITSTREAM
fprintf('1. Running Simulink model: %s\n', MODEL_NAME);

try
    simOut = sim(MODEL_NAME, 'ReturnWorkspaceOutputs','on');
    fprintf('   ✓ Simulink simulation completed successfully\n');
catch ME
    warning('Simulink run failed: %s\nAttempting plain sim call...', ME.message);
    sim(MODEL_NAME);
    simOut = [];
end

%% 3. EXTRACT BITSTREAM DATA
fprintf('\n2. Extracting Bitstream from Simulink...\n');

v_bitstream = [];

% Method 1: Try to get from simulation output object
if ~isempty(simOut)
    try
        if isprop(simOut, 'dsm_out')
            v_bitstream = simOut.dsm_out;
            fprintf('   ✓ Bitstream loaded from simOut.dsm_out\n');
        elseif isprop(simOut, 'dsmOut')
            v_bitstream = simOut.dsmOut;
            fprintf('   ✓ Bitstream loaded from simOut.dsmOut\n');
        elseif isprop(simOut, 'yout')
            v_bitstream = simOut.yout;
            fprintf('   ✓ Bitstream loaded from simOut.yout\n');
        end
    catch
        fprintf('   ⚠ Could not extract from simOut object\n');
    end
end

% Method 2: Try to get from base workspace
if isempty(v_bitstream)
    fprintf('   Attempting to load from workspace...\n');
    if evalin('base', 'exist(''dsm_out'', ''var'')')
        v_bitstream = evalin('base', 'dsm_out');
        fprintf('   ✓ Bitstream loaded from workspace variable "dsm_out"\n');
    elseif evalin('base', 'exist(''dsmOut'', ''var'')')
        v_bitstream = evalin('base', 'dsmOut');
        fprintf('   ✓ Bitstream loaded from workspace variable "dsmOut"\n');
    elseif evalin('base', 'exist(''out'', ''var'')')
        v_bitstream = evalin('base', 'out');
        fprintf('   ✓ Bitstream loaded from workspace variable "out"\n');
    end
end

% Method 3: Check current workspace
if isempty(v_bitstream)
    if exist('dsm_out', 'var')
        v_bitstream = dsm_out;
        fprintf('   ✓ Bitstream loaded from current workspace "dsm_out"\n');
    elseif exist('dsmOut', 'var')
        v_bitstream = dsmOut;
        fprintf('   ✓ Bitstream loaded from current workspace "dsmOut"\n');
    end
end

% Final check
if isempty(v_bitstream)
    error(['Could not find bitstream data!\n' ...
           'Please ensure your Simulink model has a "To Workspace" block\n' ...
           'connected to the DSM modulator output with variable name "dsm_out"']);
end

% Extract data if it's a timeseries or struct
if isobject(v_bitstream)
    if isprop(v_bitstream, 'Data')
        v_bitstream = v_bitstream.Data;
        fprintf('   ℹ Extracted .Data from timeseries object\n');
    elseif isprop(v_bitstream, 'signals')
        v_bitstream = v_bitstream.signals.values;
        fprintf('   ℹ Extracted .signals.values from struct\n');
    end
end

% Ensure column vector
v_bitstream = v_bitstream(:);

% Convert bitstream to bipolar format (-1, +1)
v_bitstream = double(v_bitstream);
if min(v_bitstream) >= 0
    v_bipolar = 2*v_bitstream - 1;
    fprintf('   ℹ Converted bitstream from (0,1) to (-1,+1) format\n');
else
    bit_range = max(v_bitstream) - min(v_bitstream);
    if bit_range < 1.5
        v_bipolar = v_bitstream * 2;
        fprintf('   ℹ Scaled bitstream from [%.1f, %.1f] to [-1, +1] format\n', min(v_bitstream), max(v_bitstream));
    else
        v_bipolar = v_bitstream;
        fprintf('   ℹ Bitstream already in bipolar format\n');
    end
end

fprintf('   Bitstream Samples: %d\n', length(v_bipolar));
fprintf('   Bitstream Rate: %.3f MHz\n', Fs_in/1e6);
fprintf('   Bitstream Range: [%.1f, %.1f]\n', min(v_bipolar), max(v_bipolar));

% PAD BITSTREAM to make it divisible by total decimation (256*2*2*2*2 = 4096)
Total_Decimation = 256 * 2 * 2 * 2 * 2;  % = 4096 = OSR
Remainder = mod(length(v_bipolar), Total_Decimation);
if Remainder ~= 0
    Pad_Length = Total_Decimation - Remainder;
    v_bipolar = [v_bipolar; zeros(Pad_Length, 1)];
    fprintf('   ℹ Padded with %d zeros to make length divisible by %d\n', Pad_Length, Total_Decimation);
    fprintf('   New Bitstream Length: %d samples\n', length(v_bipolar));
end

%% 4. DESIGN 5-STAGE OPTIMIZED FILTER CHAIN
fprintf('\n3. Designing 5-Stage Optimized Filter Chain...\n');

Filters = cell(1, 5);

% --- STAGE 1: CIC (R=256) ---
CIC_R = 256;
CIC_M = 1;
CIC_N = 6;
CIC_Gain_Bits = 48;  % log2(256^6)
Filters{1} = dsp.CICDecimator(CIC_R, CIC_M, CIC_N);
fprintf('   Stage 1 - CIC Decimator:\n');
fprintf('     Decimation Factor    : %d\n', CIC_R);
fprintf('     Differential Delay   : %d\n', CIC_M);
fprintf('     Number of Sections   : %d\n', CIC_N);
fprintf('     CIC Gain (bits)      : %d\n', CIC_Gain_Bits);

% --- STAGE 2: HALFBAND 1 (R=2) ---
% Very relaxed transition (0.15) -> Tiny tap count (~10 taps)
hb1 = design(fdesign.decimator(2, 'halfband', 'N,TW', 10, 0.15), 'equiripple', 'SystemObject', true);
Filters{2} = dsp.FIRDecimator(2, hb1.Numerator);
fprintf('   Stage 2 - Halfband 1:\n');
fprintf('     Decimation Factor    : 2\n');
fprintf('     Number of Taps       : %d\n', length(hb1.Numerator));
fprintf('     Effective Multipliers: %d\n', ceil(length(hb1.Numerator)/2));

% --- STAGE 3: HALFBAND 2 (R=2) ---
% Moderate transition -> ~14 taps
hb2 = design(fdesign.decimator(2, 'halfband', 'N,TW', 14, 0.1), 'equiripple', 'SystemObject', true);
Filters{3} = dsp.FIRDecimator(2, hb2.Numerator);
fprintf('   Stage 3 - Halfband 2:\n');
fprintf('     Decimation Factor    : 2\n');
fprintf('     Number of Taps       : %d\n', length(hb2.Numerator));
fprintf('     Effective Multipliers: %d\n', ceil(length(hb2.Numerator)/2));

% --- STAGE 4: HALFBAND 3 (R=2) ---
% Added stage to reduce final FIR complexity
hb3 = design(fdesign.decimator(2, 'halfband', 'N,TW', 18, 0.08), 'equiripple', 'SystemObject', true);
Filters{4} = dsp.FIRDecimator(2, hb3.Numerator);
fprintf('   Stage 4 - Halfband 3:\n');
fprintf('     Decimation Factor    : 2\n');
fprintf('     Number of Taps       : %d\n', length(hb3.Numerator));
fprintf('     Effective Multipliers: %d\n', ceil(length(hb3.Numerator)/2));

% --- STAGE 5: FINAL FIR (R=2) ---
% Optimized: Relaxed transition width, only ~27 taps
d5 = design(fdesign.decimator(2, 'lowpass', 0.35, 0.65, 0.01, 96), 'equiripple', 'SystemObject', true);
Filters{5} = dsp.FIRDecimator(2, d5.Numerator);
fprintf('   Stage 5 - Final FIR:\n');
fprintf('     Decimation Factor    : 2\n');
fprintf('     Number of Taps       : %d (Optimized!)\n', length(d5.Numerator));

fprintf('\n   Total Decimation: %d\n', 256*2*2*2*2);
fprintf('   Output Rate: %.3f kHz\n', Fs_out/1e3);

% Configure Fixed-Point for all filters
NumStages = 5;
DATA_WIDTH = 22;
FRAC_WIDTH = 18;

for k = 1:NumStages
    obj = Filters{k};
    if isa(obj, 'dsp.CICDecimator')
        obj.FixedPointDataType = 'Specify word and fraction lengths';
        obj.SectionWordLengths = 58;
        obj.OutputWordLength = 58;
        obj.OutputFractionLength = 0;
    elseif isa(obj, 'dsp.FIRDecimator')
        obj.FullPrecisionOverride = false;
        obj.CoefficientsDataType = 'Custom';
        obj.CustomCoefficientsDataType = numerictype('Signedness','Auto','WordLength',16,'FractionLength',15);
        obj.ProductDataType = 'Custom';
        obj.CustomProductDataType = numerictype('Signedness','Auto','WordLength',38,'FractionLength',33);
        obj.AccumulatorDataType = 'Custom';
        obj.CustomAccumulatorDataType = numerictype('Signedness','Auto','WordLength',54,'FractionLength',33);
        obj.OutputDataType = 'Custom';
        obj.CustomOutputDataType = numerictype('Signedness','Auto','WordLength',DATA_WIDTH,'FractionLength',FRAC_WIDTH);
    end
end

fprintf('   ✓ All filters configured with fixed-point arithmetic (22-bit data)\n');

%% 5. APPLY 5-STAGE FILTER CHAIN
fprintf('\n4. Applying 5-Stage Filter Chain to Bitstream...\n');

% Convert to fixed-point
sig = fi(v_bipolar, 1, 2, 0);
fprintf('   Input: %d samples @ %.3f MHz\n', length(sig), Fs_in/1e6);

% Stage 1: CIC Decimator
fprintf('   → Stage 1 (CIC): Processing...');
sig = step(Filters{1}, sig);
% Apply CIC gain compensation and scale to Q4.18
val_norm = double(sig) * (2^(-CIC_Gain_Bits)) * 0.85;
sig = fi(val_norm, 1, DATA_WIDTH, FRAC_WIDTH);
fprintf(' %d samples @ %.3f kHz\n', length(sig), Fs_in/CIC_R/1e3);

% Stage 2: Halfband 1 (R=2)
fprintf('   → Stage 2 (HB1): Processing...');
sig = step(Filters{2}, sig);
fprintf(' %d samples @ %.3f kHz\n', length(sig), Fs_in/(CIC_R*2)/1e3);

% Stage 3: Halfband 2 (R=2)
fprintf('   → Stage 3 (HB2): Processing...');
sig = step(Filters{3}, sig);
fprintf(' %d samples @ %.3f kHz\n', length(sig), Fs_in/(CIC_R*4)/1e3);

% Stage 4: Halfband 3 (R=2)
fprintf('   → Stage 4 (HB3): Processing...');
sig = step(Filters{4}, sig);
fprintf(' %d samples @ %.3f kHz\n', length(sig), Fs_in/(CIC_R*8)/1e3);

% Stage 5: Final FIR (R=2)
fprintf('   → Stage 5 (FIR): Processing...');
sig = step(Filters{5}, sig);
fprintf(' %d samples @ %.3f kHz\n', length(sig), Fs_out/1e3);

% Convert back to double
y_all = double(sig);
fprintf('   ✓ Filtering complete!\n');

%% 6. PREPARE DATA FOR ANALYSIS
fprintf('\n5. Preparing Data for Analysis...\n');

% Remove transient samples
N_transient = min(1024, round(0.1 * length(y_all)));
fprintf('   Removing %d transient samples...\n', N_transient);

if length(y_all) <= N_transient
    error('Insufficient data! Need more than %d samples.', N_transient);
end

y_steady = y_all(N_transient+1 : end);
fprintf('   Steady-state samples: %d\n', length(y_steady));

N_fft = 8192;
if length(y_steady) < N_fft
    N_fft = 2^floor(log2(length(y_steady)));
end

v1 = y_steady(1:N_fft);
fprintf('   FFT Length: %d samples\n', N_fft);
fprintf('   Analysis Duration: %.3f seconds\n', N_fft/Fs_out);

%% 7. SAC ISRO METHOD CALCULATION
fprintf('\n6. Calculating SNDR (SAC ISRO Method)...\n');

% Remove DC offset
DC_offset = mean(v1);
v1 = v1 - DC_offset;
fprintf('   DC Offset Removed: %.6e\n', DC_offset);

% Create frequency vector
fv = Fs_out / 2 * linspace(0, 1, N_fft / 2 + 1);
Freq_Resolution = Fs_out / N_fft;
fprintf('   Frequency Resolution: %.4f Hz\n', Freq_Resolution);

% Apply Hanning window and compute FFT
windowed_signal = v1 .* hanning(N_fft);
fft_outv = fft(windowed_signal, N_fft);
Ptot = abs(fft_outv).^2;
fft_onesided = Ptot(1:N_fft/2+1);

% Find signal peak
[Peak_Value, max_idx] = max(fft_onesided);
Signal_Freq = fv(max_idx);
fprintf('   Signal detected at %.4f Hz (Bin %d)\n', Signal_Freq, max_idx);

% Define signal bins (±20 bins around peak)
span = 20;
sigbin_start = max(1, max_idx - span);
sigbin_end = min(length(fft_onesided), max_idx + span);
sigbin = sigbin_start : sigbin_end;
Signal_Bins = length(sigbin);

fprintf('   Signal Bins: %d to %d (%d bins total)\n', sigbin_start, sigbin_end, Signal_Bins);

% Calculate Powers
sigpow = sum(fft_onesided(sigbin));
all_bins = 3:length(fft_onesided);
noise_bins = setdiff(all_bins, sigbin);
npow = sum(fft_onesided(noise_bins));

Signal_Power_dB = 10*log10(sigpow);
Noise_Power_dB = 10*log10(npow);

fprintf('   Signal Power: %.2f dB\n', Signal_Power_dB);
fprintf('   Noise Power: %.2f dB\n', Noise_Power_dB);

% Calculate SNDR and ENOB
sndr = 10*log10(sigpow / npow);
enob = (sndr - 1.76) / 6.02;

% Additional Metrics
Noise_Floor = 10*log10(mean(fft_onesided(noise_bins)));
SFDR = 10*log10(Peak_Value / max(fft_onesided(noise_bins)));

% Output Statistics
Output_RMS = std(v1);
Output_Peak = max(abs(v1));
Crest_Factor = Output_Peak / Output_RMS;

%% 8. COMPREHENSIVE RESULTS
fprintf('\n\n');
fprintf('========================================================\n');
fprintf('        5-STAGE OPTIMIZED FILTER - RESULTS             \n');
fprintf('========================================================\n\n');

fprintf('--- SIMULINK MODEL ---\n');
fprintf('Model Name               : %s\n', MODEL_NAME);
fprintf('Simulation Status        : ✓ Completed\n');
fprintf('Output Type              : Raw Bitstream (1-bit)\n');
fprintf('\n');

fprintf('--- SYSTEM SPECIFICATIONS ---\n');
fprintf('Target ENOB              : 16 bits\n');
fprintf('Output Sample Rate       : %.3f kHz\n', Fs_out/1e3);
fprintf('Oversampling Ratio (OSR) : %d\n', OSR);
fprintf('Modulator Sample Rate    : %.3f MHz\n', Fs_in/1e6);
fprintf('\n');

fprintf('--- 5-STAGE FILTER CHAIN (AREA OPTIMIZED) ---\n');
fprintf('Architecture             : CIC(256) -> HB -> HB -> HB -> FIR(2)\n');
fprintf('Number of Stages         : 5\n');
fprintf('Total Decimation         : %d\n', 256*2*2*2*2);
fprintf('\n');
fprintf('  Stage 1 - CIC Decimator:\n');
fprintf('    Decimation           : %d\n', CIC_R);
fprintf('    Sections             : %d\n', CIC_N);
fprintf('    CIC Gain (bits)      : %d\n', CIC_Gain_Bits);
fprintf('  Stage 2 - Halfband 1:\n');
fprintf('    Decimation           : 2\n');
fprintf('    Taps                 : %d (Eff. Mult: %d)\n', length(hb1.Numerator), ceil(length(hb1.Numerator)/2));
fprintf('  Stage 3 - Halfband 2:\n');
fprintf('    Decimation           : 2\n');
fprintf('    Taps                 : %d (Eff. Mult: %d)\n', length(hb2.Numerator), ceil(length(hb2.Numerator)/2));
fprintf('  Stage 4 - Halfband 3:\n');
fprintf('    Decimation           : 2\n');
fprintf('    Taps                 : %d (Eff. Mult: %d)\n', length(hb3.Numerator), ceil(length(hb3.Numerator)/2));
fprintf('  Stage 5 - Final FIR:\n');
fprintf('    Decimation           : 2\n');
fprintf('    Taps                 : %d ✓ OPTIMIZED!\n', length(d5.Numerator));
fprintf('\n');

fprintf('--- DATA SUMMARY ---\n');
fprintf('Bitstream Samples        : %d\n', length(v_bipolar));
fprintf('Filtered Samples         : %d\n', length(y_all));
fprintf('Transient Samples        : %d\n', N_transient);
fprintf('Steady-state Samples     : %d\n', length(y_steady));
fprintf('Analysis Samples (FFT)   : %d\n', N_fft);
fprintf('\n');

fprintf('--- OUTPUT SIGNAL STATISTICS ---\n');
fprintf('DC Offset                : %.6e\n', DC_offset);
fprintf('RMS Value                : %.6f\n', Output_RMS);
fprintf('Peak Value               : %.6f\n', Output_Peak);
fprintf('Crest Factor             : %.2f\n', Crest_Factor);
fprintf('\n');

fprintf('--- PERFORMANCE METRICS ---\n');
fprintf('Signal Power             : %.2f dB\n', Signal_Power_dB);
fprintf('Noise Power              : %.2f dB\n', Noise_Power_dB);
fprintf('Noise Floor (avg)        : %.2f dB\n', Noise_Floor);
fprintf('SNDR                     : %.2f dB ★★★\n', sndr);
fprintf('ENOB                     : %.2f bits ★★★\n', enob);
fprintf('SFDR                     : %.2f dB\n', SFDR);
fprintf('\n');

fprintf('--- PERFORMANCE vs TARGET ---\n');
fprintf('Target ENOB              : 16 bits\n');
fprintf('Achieved ENOB            : %.2f bits\n', enob);
fprintf('ENOB Difference          : %.2f bits\n', enob - 16);
if enob >= 16
    fprintf('STATUS                   : ✓✓✓ TARGET MET ✓✓✓\n');
    fprintf('MARGIN                   : +%.2f bits\n', enob - 16);
else
    fprintf('STATUS                   : ✗ BELOW TARGET\n');
    fprintf('SHORTFALL                : %.2f bits\n', 16 - enob);
end
fprintf('\n');

fprintf('========================================================\n');
fprintf('                   END OF ANALYSIS                      \n');
fprintf('========================================================\n\n');

%% 9. GENERATE PLOTS
fprintf('7. Generating Plots...\n');

figure('Name', '5-Stage Optimized Filter Analysis', 'Color', 'w', 'Position', [50 50 1400 900]);

% Plot 1: Bitstream (First 1000 samples)
subplot(3,3,1);
n_show = min(1000, length(v_bipolar));
t_bit = (0:n_show-1) / Fs_in * 1e6;
plot(t_bit, v_bipolar(1:n_show), 'b', 'LineWidth', 1);
xlabel('Time [μs]'); ylabel('Amplitude');
title('Raw Bitstream from Simulink');
grid on; ylim([-1.5 1.5]);

% Plot 2: Filtered Output (First 50ms)
subplot(3,3,2);
t_plot = (0:N_fft-1) / Fs_out;
n_plot = min(round(0.05*Fs_out), N_fft);
plot(t_plot(1:n_plot)*1000, v1(1:n_plot), 'g', 'LineWidth', 1.5);
xlabel('Time [ms]'); ylabel('Amplitude');
title('Filtered Output (First 50ms)');
grid on;

% Plot 3: Histogram
subplot(3,3,3);
histogram(v1, 50, 'FaceColor', 'b', 'EdgeColor', 'k', 'FaceAlpha', 0.7);
xlabel('Amplitude'); ylabel('Count');
title('Amplitude Distribution');
grid on;

% Plot 4: PSD - Linear Scale
subplot(3,3,4);
plot(fv, 10*log10(fft_onesided), 'b', 'LineWidth', 1);
hold on;
plot(fv(sigbin), 10*log10(fft_onesided(sigbin)), 'r', 'LineWidth', 2);
plot(fv(max_idx), 10*log10(Peak_Value), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
xlabel('Frequency [Hz]'); ylabel('Power [dB]');
title(sprintf('PSD - Linear Scale (SNDR: %.2f dB)', sndr));
legend('Noise Floor', 'Signal', 'Peak', 'Location', 'best');
grid on; xlim([0 Fs_out/2]);

% Plot 5: PSD - Log Scale
subplot(3,3,5);
semilogx(fv, 10*log10(fft_onesided), 'b', 'LineWidth', 1.5);
hold on;
semilogx(fv(sigbin), 10*log10(fft_onesided(sigbin)), 'r', 'LineWidth', 2);
semilogx(fv(max_idx), 10*log10(Peak_Value), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
xlabel('Frequency [Hz]'); ylabel('Power [dB]');
title(sprintf('PSD - Log Scale (ENOB: %.2f bits)', enob));
legend('Noise Floor', 'Signal', 'Peak', 'Location', 'best');
grid on; xlim([max(1, fv(3)), Fs_out/2]);

% Plot 6: Zoomed PSD around Signal
subplot(3,3,6);
zoom_start = max(1, max_idx - 100);
zoom_end = min(length(fft_onesided), max_idx + 100);
zoom_range = zoom_start:zoom_end;
plot(fv(zoom_range), 10*log10(fft_onesided(zoom_range)), 'b', 'LineWidth', 1.5);
hold on;
plot(fv(sigbin), 10*log10(fft_onesided(sigbin)), 'r', 'LineWidth', 2);
plot(fv(max_idx), 10*log10(Peak_Value), 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
xlabel('Frequency [Hz]'); ylabel('Power [dB]');
title('PSD - Zoomed Around Signal');
legend('Spectrum', 'Signal Bins', 'Peak'); grid on;

% Plot 7: Full Time Domain
subplot(3,3,7);
t_all = (0:length(y_all)-1) / Fs_out;
plot(t_all*1000, y_all, 'b', 'LineWidth', 1);
xlabel('Time [ms]'); ylabel('Amplitude');
title('Complete Filtered Output');
grid on; xlim([0 min(100, max(t_all)*1000)]);

% Plot 8: Signal Quality Metrics
subplot(3,3,8);
metrics = [sndr/120*100; enob/16*100; SFDR/120*100];
bar(metrics, 'FaceColor', 'b', 'EdgeColor', 'k');
hold on; yline(100, 'r--', 'LineWidth', 2);
set(gca, 'XTickLabel', {'SNDR', 'ENOB', 'SFDR'});
ylabel('% of Target');
title('Performance Metrics (% of Target)');
ylim([0 120]); grid on;

% Plot 9: Performance Summary
subplot(3,3,9);
axis off;
text_str = {
    '\bf\fontsize{12}5-STAGE FILTER RESULTS', '', ...
    sprintf('\\bf\\fontsize{14}SNDR: %.2f dB', sndr), ...
    sprintf('\\bf\\fontsize{14}ENOB: %.2f bits', enob), '', ...
    sprintf('Target: 16 bits'), ...
    sprintf('Status: %s', iif(enob >= 16, '\color{green}✓ PASS', '\color{red}✗ FAIL')), '', ...
    '───────────────────────', ...
    sprintf('Architecture:'), ...
    sprintf('CIC(256)->HB->HB->HB->FIR'), ...
    sprintf('Final FIR: %d taps', length(d5.Numerator)), '', ...
    sprintf('Signal: %.2f Hz', Signal_Freq), ...
    sprintf('SFDR: %.2f dB', SFDR), ...
    sprintf('Noise: %.2f dB', Noise_Floor)
};
text(0.05, 0.95, text_str, 'VerticalAlignment', 'top', 'FontSize', 9, 'FontName', 'Courier');

fprintf('\n✓ Analysis Complete!\n');
fprintf('✓ All plots generated successfully\n\n');

%% Helper function
function out = iif(condition, true_val, false_val)
    if condition
        out = true_val;
    else
        out = false_val;
    end
end