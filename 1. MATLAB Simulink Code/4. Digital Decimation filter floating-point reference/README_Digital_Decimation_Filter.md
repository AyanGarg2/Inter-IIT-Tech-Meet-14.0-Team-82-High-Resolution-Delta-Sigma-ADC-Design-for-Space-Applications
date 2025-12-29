# Tiny Tap ΔΣ ADC Decimator Chain (5-Stage)

This project implements a **5-stage, area-optimized digital decimation chain** for a 1-bit **Delta-Sigma Modulator (DSM)** and also **generates Verilog HDL** for each stage plus a simple top-level wrapper.

Target spec:

- **Output sample rate**: 2 kHz  
- **Oversampling ratio (OSR)**: 4096 → **Modulator rate** = 8.192 MHz  
- **Goal**: **> 16 ENOB** with **minimal logic / multipliers**  
- **Architecture**:  
  `CIC(256) → HB(2) → HB(2) → HB(2) → FIR(2)`  

The script is a complete flow from **DSM simulation → filtering → ENOB estimate → HDL generation**.

---

## 1. Block Diagram / Architecture

Overall signal path:

```text
Analogue Input (sine @ ~50 Hz)
          │
   4th-Order ΔΣ Modulator (1-bit)
          │  Fs = 8.192 MHz
          ▼
      1-bit Bitstream (±1)
          │
          ▼
  [Stage 1] CIC Decimator   R = 256
          │   (no multipliers)
          ▼
  [Stage 2] Halfband FIR    R = 2
          │
          ▼
  [Stage 3] Halfband FIR    R = 2
          │
          ▼
  [Stage 4] Halfband FIR    R = 2
          │
          ▼
  [Stage 5] Final FIR LPF   R = 2
          │
          ▼
     Output @ 2 kHz
```

Total decimation factor = `256 × 2 × 2 × 2 × 2 = 4096 = OSR`.

The last FIR is deliberately made **small (~27 taps)** by relaxing its transition band and letting the three halfbands “do the heavy lifting”.

---

## 2. Toolbox / Software Requirements

You need the following in MATLAB:

1. **Delta-Sigma Toolbox** (Richard Schreier)  
   - Functions used: `synthesizeNTF`, `realizeNTF`, `stuffABCD`, `simulateDSM`  
   - Add it to your MATLAB path before running.

2. **DSP System Toolbox**  
   - `dsp.CICDecimator`, `dsp.FIRDecimator`  
   - Filter design: `fdesign.decimator`, `design`

3. **Fixed-Point Designer**  
   - `fi`, `numerictype`, fixed-point data types for filters.

4. **HDL Coder**  
   - `generatehdl` for Verilog generation.

MATLAB version: any reasonably recent version that supports the above functions.

---

## 3. Files

Typical minimal setup:

- `tiny_tap_dsadc.m`  
  The main script (the one you have).

- `hdl_src_tiny/` (created automatically)  
  Contains:
  - `Stage1_CIC.v`
  - `Stage2_HB1.v`
  - `Stage3_HB2.v`
  - `Stage4_HB3.v`
  - `Stage5_FIR.v`
  - `Decimator_Chain_Top.v` (wrapper)

You can rename the script file to anything; just keep the content same.

---

## 4. How to Run

1. **Open MATLAB.**

2. **Add required folders to the path**:  
   - Folder containing the script.  
   - Folder containing the Delta-Sigma Toolbox.

3. **Check toolboxes**:  
   Make sure DSP System Toolbox, Fixed-Point Designer, and HDL Coder are installed.

4. **Run the script**:
   ```matlab
   tiny_tap_dsadc   % or whatever you named the .m file
   ```

5. **What you should see**:
   - Command window prints:
     - Basic info and stage details (tap counts, effective multipliers).  
     - Final **SNDR** and **ENOB**.  
   - A MATLAB figure with:
     - Power Spectral Density (PSD) of the output.  
   - A folder `hdl_src_tiny/` with Verilog files.

---

## 5. Script Flow (Step-by-Step)

### 5.1 System Specifications

```matlab
Fs_out = 2e3;     % Final output sample rate
OSR    = 4096;    % Oversampling ratio
Fs_in  = Fs_out * OSR;  % Modulator sampling rate (8.192 MHz)
```

- Output band is around **0–1 kHz** (Nyquist of 2 kHz).  
- A **4th-order DSM** is synthesized for these specs.

### 5.2 Input Signal & DSM Simulation

- Defines a near-50 Hz sine wave:
  ```matlab
  Target_Fin = 50;
  ...
  Amp = 0.5;
  u = Amp * sin(2*pi*Fin*(0:N_in_total-1)/Fs_in);
  ```
- `Fin` is **quantized to an FFT bin** → cleaner SNDR measurement.  
- Uses Delta-Sigma Toolbox:
  ```matlab
  ntf = synthesizeNTF(DSM_Order, OSR, 1);
  [a,g,b,c] = realizeNTF(ntf);
  ABCD = stuffABCD(a, g, b, c);
  v_bitstream = simulateDSM(u, ABCD);
  v_bipolar_all = 2*double(v_bitstream(:)) - 1;  % 0/1 → -1/+1
  ```

### 5.3 Chunking / Padding

To avoid huge memory spikes, the script processes the DSM output in chunks:

```matlab
ChunkSize = 100 * OSR; % samples per chunk at modulator rate
...
NumChunks = length(v_bipolar_all) / ChunkSize;
```

- If the number of samples is not an exact multiple of `ChunkSize`, it pads with zeros.  
- This doesn’t affect the steady-state FFT window.

### 5.4 Filter Chain Definition

```matlab
Filters = cell(1, 5);
```

1. **Stage 1 – CIC (R=256, N=6)**  
   ```matlab
   Filters{1} = dsp.CICDecimator(256, 1, 6);
   ```
   - No multipliers.  
   - Huge internal gain: `256^6` ≈ 2^48 (hence `CIC_Gain_Bits = 48`).

2. **Stage 2 – Halfband 1 (R=2)**  
   - Loose transition (`TW = 0.15`) → very few taps (~10).  
   ```matlab
   hb1 = design(fdesign.decimator(2, 'halfband', 'N,TW', 10, 0.15), ...);
   Filters{2} = dsp.FIRDecimator(2, hb1.Numerator);
   ```

3. **Stage 3 – Halfband 2 (R=2)**  
   - Slightly tighter transition.  
   ```matlab
   hb2 = design(fdesign.decimator(2, 'halfband', 'N,TW', 14, 0.1), ...);
   ```

4. **Stage 4 – Halfband 3 (R=2)**  
   - Even tighter (`TW = 0.08`).  
   ```matlab
   hb3 = design(fdesign.decimator(2, 'halfband', 'N,TW', 18, 0.08), ...);
   ```

5. **Stage 5 – Final FIR (R=2)**  
   - Low-pass with **relaxed pass/stop bands**:
     - Passband edge = 0.35 (normalized)  
     - Stopband edge = 0.65  
     - Stopband attenuation = 96 dB  
   - Result: ~27 taps instead of ~49.  
   ```matlab
   d5 = design(fdesign.decimator(2, 'lowpass', 0.35, 0.65, 0.01, 96), ...);
   ```

The script prints tap counts and effective multipliers (halfband symmetry reduces real multipliers by ~half).

### 5.5 Fixed-Point Configuration

Common fixed-point design:

- **CIC**:
  - Internal wordlengths: 58 bits (safe for gain).  
  - Output is integer (`OutputFractionLength = 0`).

- **FIR stages**:
  - Coefficients: Q1.15 (16-bit).  
  - Products: 38 bits, accumulators: 54 bits.  
  - Output: **Q4.18**, total `DATA_WIDTH = 22`, `FRAC_WIDTH = 18`.

This is chosen to comfortably support **≈ 16 ENOB** without overflow.

### 5.6 Processing Loop

For each input chunk:

1. Convert the chunk to fixed-point:
   ```matlab
   sig = fi(chunk_in, 1, 2, 0);  % 2-bit signed integer
   ```

2. Pass through all 5 stages:
   ```matlab
   for k = 1:NumStages
       sig = step(Filters{k}, sig);
       if k == 1
           % After CIC, scale down its huge gain:
           val_norm = double(sig) * (2^(-CIC_Gain_Bits)) * 0.85;
           sig = fi(val_norm, 1, DATA_WIDTH, FRAC_WIDTH);
       end
   end
   ```

3. Collect the decimated output in `y_all`.

A waitbar shows progress for long runs.

### 5.7 SNDR & ENOB Calculation

- Remove transient samples.  
- Take an FFT with Hann window.  
- Extract:
  - **Signal power** around the main tone (±20 bins).  
  - **Noise+distortion power** from all other bins (excluding DC, etc.).

ENOB is computed from SNDR using:

```text
ENOB = (SNDR[dB] - 1.76) / 6.02
```

The script prints **SNDR** and **ENOB** at the end.

### 5.8 Plot

The figure shows the **PSD at 2 kHz output rate** with the signal bins highlighted.

---

## 6. HDL Generation

At the end, the script generates Verilog for each stage and a small wrapper:

```matlab
outDir = 'hdl_src_tiny';
...
generatehdl(Filters{1}, 'Name', 'Stage1_CIC',  ... );
generatehdl(Filters{2}, 'Name', 'Stage2_HB1',  ... );
...
generatehdl(Filters{5}, 'Name', 'Stage5_FIR',  ... );
```

- Testbench generation is **off** (to keep things clean).  
- Coefficient multipliers use **CSD** encoding for area savings.

### 6.1 Top-Level Wrapper: `Decimator_Chain_Top.v`

Automatically written as:

```verilog
module Decimator_Chain_Top (
    input  wire clk, reset, clk_enable,
    input  wire [1:0] filter_in,
    output wire [21:0] filter_out,
    output wire        ce_out
);
    ...
endmodule
```

Key points:

- **Input**: `filter_in[1:0]`  
  - Represents the decimated version of the 1-bit DSM stream; in the script we use 2-bit fixed-point (`fi(...,1,2,0)`).  
- **Output**: `filter_out[21:0]`  
  - Q4.18 fixed-point sample at **2 kHz**.  
- **Clock enables**:
  - `ce_out` is asserted when a new output sample is valid.  
  - Internal `ce` signals chain from one stage to the next.  
- **CIC scaling in hardware**:
  ```verilog
  assign w_cic_scaled = w_cic_out[57:36]; // take top 22 bits
  ```

You can integrate `Decimator_Chain_Top` into a larger FPGA / ASIC design, connect the DSM bitstream front-end, and capture `filter_out` for further processing.

---

## 7. Customization Guide

Common things you might want to tweak:

1. **Output rate / OSR**  
   ```matlab
   Fs_out = 2e3;
   OSR    = 4096;
   Fs_in  = Fs_out * OSR;
   ```
   If you change OSR or Fs_out, you must:
   - Re-synthesize the NTF.  
   - Re-evaluate CIC gain (`CIC_Gain_Bits`).  
   - Possibly re-design filter stages.

2. **Modulator order**
   ```matlab
   DSM_Order = 4;
   ntf = synthesizeNTF(DSM_Order, OSR, 1);
   ```
   Higher order → better noise shaping but more stability concerns.

3. **Input tone / amplitude**
   ```matlab
   Target_Fin = 50;  % Hz
   Amp        = 0.5; % Full-scale = 1
   ```
   You can sweep these to check SFDR and ENOB at different tone locations.

4. **Filter specs / taps**
   - Change `N` and `TW` in `fdesign.decimator` for each stage.  
   - Change passband/stopband edges in the final FIR to trade area vs rejection.

5. **Fixed-point wordlengths**
   - `DATA_WIDTH`, `FRAC_WIDTH` control output precision and area.  
   - CIC SectionWordLengths and accumulator widths can be optimized further after hardware experimentation.

---

## 8. Notes & Tips

- If you see **ENOB below target**, try:
  - Increasing the final FIR stopband attenuation.  
  - Adjusting transition bands for halfbands.  
  - Increasing accumulator precision.

- If MATLAB throws errors like **unknown functions**:
  - Check that the Delta-Sigma Toolbox is added to path.  
  - Check that all required toolboxes are installed.

- If HDL generation fails:
  - Verify HDL Coder license.  
  - Ensure the filter objects are supported by `generatehdl`.

---
