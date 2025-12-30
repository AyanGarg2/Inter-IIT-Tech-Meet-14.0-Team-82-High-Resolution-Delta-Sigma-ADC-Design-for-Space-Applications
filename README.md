# High-Resolution Delta–Sigma ADC Design for Space Applications

This repository contains the complete system-level design, modeling, digital implementation, and ASIC flow of a **high-resolution Delta–Sigma (ΔΣ) Analog-to-Digital Converter** developed as part of **Inter-IIT Tech Meet 14.0 (ISRO – VLSI Problem Statement)**.

The project targets **low-bandwidth, high-precision sensor applications** typically encountered in space systems, achieving **16–19 bits ENOB** at **0.5–2 kS/s** Nyquist sampling rates.

---

## 📌 Project Overview

Space payloads demand extremely high-resolution data conversion at very low signal bandwidths, where **flicker (1/f) noise**, stability, and power efficiency dominate the design trade space. This work explores the complete ΔΣ ADC signal chain—from modulator architecture selection to ASIC-ready digital decimation filtering.

### Key Objectives
- Study and compare ΔΣ modulator architectures (2nd–4th order)
- Perform ENOB vs sampling-rate trade-off analysis
- Analyze flicker noise impact and mitigation strategies
- Design a hardware-efficient multistage digital decimation filter
- Implement and verify RTL using fixed-point arithmetic
- Complete ASIC synthesis, place-and-route, and post-layout analysis

---

## 🧠 Architecture Summary

- **Modulator**:  
  - 4th-order Discrete-Time CIFF  
  - 1-bit quantizer  
  - OSR = 4096  

- **Digital Decimation Chain**:  
  - CIC (SINC) filter  
  - Three Halfband FIR stages  
  - Final compensation FIR  
  - Total decimation = 4096  

- **Output**:  
  - 20-bit digital output  
  - >16 bits ENOB preserved after filtering  

---

## 📊 Key Results

| Metric | Value |
|------|------|
| ENOB (ideal) | 17.92 bits |
| ENOB (with 1/f noise) | 16.70 bits |
| SNDR (ideal) | 109.63 dB |
| SNDR (with noise) | 102.29 dB |
| Output Rate | 2 kS/s |
| Power (ASIC) | 2.57 mW |
| Area | ~0.167 mm² |
| Technology | UMC 90 nm CMOS |

The selected 4th-order architecture demonstrated **strong architectural desensitization to flicker noise**, eliminating the need for hardware chopping or auto-zeroing.

---

## 🛠 Tools & Technologies

- **System Modeling**: MATLAB, Simulink, Delta-Sigma Toolbox  
- **Digital Design**: Verilog HDL  
- **Simulation**: MATLAB, HDL simulators  
- **ASIC Flow**: Cadence Genus & Innovus  
- **PDK**: UMC 90 nm CMOS  
