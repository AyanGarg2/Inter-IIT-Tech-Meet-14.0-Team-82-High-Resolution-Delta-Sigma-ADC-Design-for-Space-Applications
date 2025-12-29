`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Comprehensive Testbench for Decimator Chain ADC System
// 
// This testbench tests a complete sigma-delta ADC decimation chain:
// - Stage 1: CIC decimator (256x)
// - Stage 2: HB1 decimator (2x)
// - Stage 3: HB2 decimator (2x)
// - Stage 4: HB3 decimator (2x)
// - Stage 5: FIR decimator (2x)
// Total decimation: 4096x
//
// Test Cases:
// 1. Reset functionality
// 2. DC input signals (positive, negative, zero)
// 3. Low-frequency sine wave input
// 4. Step response
// 5. Ramp input
// 6. Alternating pattern
// 7. Clock enable test
////////////////////////////////////////////////////////////////////////////////

module tb_Decimator_Chain_Top;

  // Parameters
  parameter CLK_PERIOD = 10;           // 10ns = 100 MHz clock
  parameter TOTAL_DECIMATION = 4096;   // Total decimation factor
  parameter OUTPUT_PERIOD = CLK_PERIOD * TOTAL_DECIMATION;
  
  // Testbench signals
  reg clk;
  reg reset;
  reg clk_enable;
  reg signed [1:0] filter_in;
  wire signed [21:0] filter_out;
  wire ce_out;
  
  // Test control variables
  integer i, j;
  integer output_count;
  integer test_number;
  real sine_phase;
  real sine_value;
  real dc_level;
  
  // File handle for output logging
  integer output_file;
  
  // Accumulator for sigma-delta simulation
  real sigma_delta_integrator;
  real input_signal;
  
  // Statistics
  real max_output, min_output;
  real sum_output;
  integer valid_outputs;
  
  ////////////////////////////////////////////////////////////////////////////
  // DUT Instantiation
  ////////////////////////////////////////////////////////////////////////////
  Decimator_Chain_Top DUT (
    .clk(clk),
    .reset(reset),
    .clk_enable(clk_enable),
    .filter_in(filter_in),
    .filter_out(filter_out),
    .ce_out(ce_out)
  );
  
  ////////////////////////////////////////////////////////////////////////////
  // Clock Generation
  ////////////////////////////////////////////////////////////////////////////
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end
  
  ////////////////////////////////////////////////////////////////////////////
  // Sigma-Delta Modulator Simulation
  // This function simulates a 1-bit sigma-delta ADC output
  // Input: analog signal value (-1.0 to +1.0)
  // Output: 2-bit representation of 1-bit modulator (-1 or +1)
  ////////////////////////////////////////////////////////////////////////////
  function signed [1:0] sigma_delta_modulator;
    input real analog_input;
    real quantizer_input;
    real quantizer_output;
    begin
      // Simple 1st order sigma-delta modulator simulation
      quantizer_input = sigma_delta_integrator + analog_input;
      
      // 1-bit quantizer
      if (quantizer_input >= 0.0)
        quantizer_output = 1.0;
      else
        quantizer_output = -1.0;
      
      // Update integrator with quantization error
      sigma_delta_integrator = quantizer_input - quantizer_output;
      
      // Convert to 2-bit signed representation
      if (quantizer_output > 0)
        sigma_delta_modulator = 2'b01;  // +1
      else
        sigma_delta_modulator = 2'b11;  // -1
    end
  endfunction
  
  ////////////////////////////////////////////////////////////////////////////
  // Output Monitor
  // Captures and logs output data when ce_out is asserted
  ////////////////////////////////////////////////////////////////////////////
  always @(posedge clk) begin
    if (ce_out) begin
      output_count = output_count + 1;
      
      // Convert fixed-point to real (22-bit output)
      // Assuming the output is in a fixed-point format
      
      // Log to file
      $fwrite(output_file, "%0d,%0d,%e\n", 
              output_count, 
              filter_out, 
              $itor(filter_out) / (2.0**20));
      
      // Update statistics
      if (filter_out > max_output) max_output = filter_out;
      if (filter_out < min_output) min_output = filter_out;
      sum_output = sum_output + $itor(filter_out);
      valid_outputs = valid_outputs + 1;
      
      // Display periodic updates
      if (output_count % 10 == 0) begin
        $display("Time=%0t ns | Output #%0d | Value (hex)=%h | Value (decimal)=%0d | Value (real)=%f", 
                 $time, output_count, filter_out, filter_out, $itor(filter_out)/(2.0**20));
      end
    end
  end
  
  ////////////////////////////////////////////////////////////////////////////
  // Test Sequence
  ////////////////////////////////////////////////////////////////////////////
  initial begin
    // Initialize
    reset = 1;
    clk_enable = 0;
    filter_in = 0;
    output_count = 0;
    test_number = 0;
    sigma_delta_integrator = 0.0;
    
    // Statistics initialization
    max_output = -2097152.0;  // Most negative 22-bit signed number
    min_output = 2097151.0;   // Most positive 22-bit signed number
    sum_output = 0.0;
    valid_outputs = 0;
    
    // Open output file
    output_file = $fopen("decimator_output.csv", "w");
    $fwrite(output_file, "Sample,RawValue,NormalizedValue\n");
    
    $display("================================================================================");
    $display("          Decimator Chain ADC System Testbench");
    $display("================================================================================");
    $display("Clock Period: %0d ns (%.1f MHz)", CLK_PERIOD, 1000.0/CLK_PERIOD);
    $display("Total Decimation: %0d", TOTAL_DECIMATION);
    $display("Expected Output Rate: %.3f kHz", 1000.0/(OUTPUT_PERIOD));
    $display("Output Data Width: 22 bits");
    $display("================================================================================\n");
    
    // Wait for some clock cycles
    repeat(10) @(posedge clk);
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 1: Reset Test
    ////////////////////////////////////////////////////////////////////////////
    test_number = 1;
    $display("\n[TEST %0d] RESET TEST - Verifying reset functionality", test_number);
    $display("------------------------------------------------------------------------");
    
    reset = 1;
    clk_enable = 1;
    filter_in = 2'b01;  // Apply input during reset
    
    repeat(100) @(posedge clk);
    
    // Check that outputs are zero after reset
    if (filter_out === 22'h000000) begin
      $display("[PASS] Output is zero after reset");
    end else begin
      $display("[FAIL] Output is not zero after reset: %h", filter_out);
    end
    
    // Release reset
    @(posedge clk);
    reset = 0;
    $display("[INFO] Reset released at time %0t ns", $time);
    
    // Wait for pipeline to fill
    repeat(100) @(posedge clk);
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 2: DC Input Test - Positive Maximum
    ////////////////////////////////////////////////////////////////////////////
    test_number = 2;
    output_count = 0;
    sigma_delta_integrator = 0.0;
    max_output = -2097152.0;
    min_output = 2097151.0;
    sum_output = 0.0;
    valid_outputs = 0;
    
    $display("\n[TEST %0d] DC INPUT TEST - Positive Maximum (+0.9)", test_number);
    $display("------------------------------------------------------------------------");
    dc_level = 0.9;  // Slightly below max to avoid saturation
    
    // Apply DC input for enough samples to get 50 output samples
    for (i = 0; i < TOTAL_DECIMATION * 50; i = i + 1) begin
      @(posedge clk);
      filter_in = sigma_delta_modulator(dc_level);
    end
    
    // Report statistics
    $display("[INFO] Generated %0d output samples", valid_outputs);
    if (valid_outputs > 0) begin
      $display("[INFO] Average output: %f (expected ~%f)", 
               (sum_output/valid_outputs)/(2.0**20), dc_level);
      $display("[INFO] Max output: %f", max_output/(2.0**20));
      $display("[INFO] Min output: %f", min_output/(2.0**20));
    end
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 3: DC Input Test - Negative Maximum
    ////////////////////////////////////////////////////////////////////////////
    test_number = 3;
    output_count = 0;
    sigma_delta_integrator = 0.0;
    max_output = -2097152.0;
    min_output = 2097151.0;
    sum_output = 0.0;
    valid_outputs = 0;
    
    $display("\n[TEST %0d] DC INPUT TEST - Negative Maximum (-0.9)", test_number);
    $display("------------------------------------------------------------------------");
    dc_level = -0.9;
    
    for (i = 0; i < TOTAL_DECIMATION * 50; i = i + 1) begin
      @(posedge clk);
      filter_in = sigma_delta_modulator(dc_level);
    end
    
    $display("[INFO] Generated %0d output samples", valid_outputs);
    if (valid_outputs > 0) begin
      $display("[INFO] Average output: %f (expected ~%f)", 
               (sum_output/valid_outputs)/(2.0**20), dc_level);
      $display("[INFO] Max output: %f", max_output/(2.0**20));
      $display("[INFO] Min output: %f", min_output/(2.0**20));
    end
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 4: DC Input Test - Zero
    ////////////////////////////////////////////////////////////////////////////
    test_number = 4;
    output_count = 0;
    sigma_delta_integrator = 0.0;
    max_output = -2097152.0;
    min_output = 2097151.0;
    sum_output = 0.0;
    valid_outputs = 0;
    
    $display("\n[TEST %0d] DC INPUT TEST - Zero Level", test_number);
    $display("------------------------------------------------------------------------");
    dc_level = 0.0;
    
    for (i = 0; i < TOTAL_DECIMATION * 50; i = i + 1) begin
      @(posedge clk);
      filter_in = sigma_delta_modulator(dc_level);
    end
    
    $display("[INFO] Generated %0d output samples", valid_outputs);
    if (valid_outputs > 0) begin
      $display("[INFO] Average output: %f (expected ~0.0)", 
               (sum_output/valid_outputs)/(2.0**20));
      $display("[INFO] Max output: %f", max_output/(2.0**20));
      $display("[INFO] Min output: %f", min_output/(2.0**20));
    end
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 5: DC Input Test - Mid-level Positive
    ////////////////////////////////////////////////////////////////////////////
    test_number = 5;
    output_count = 0;
    sigma_delta_integrator = 0.0;
    max_output = -2097152.0;
    min_output = 2097151.0;
    sum_output = 0.0;
    valid_outputs = 0;
    
    $display("\n[TEST %0d] DC INPUT TEST - Mid-level (+0.5)", test_number);
    $display("------------------------------------------------------------------------");
    dc_level = 0.5;
    
    for (i = 0; i < TOTAL_DECIMATION * 50; i = i + 1) begin
      @(posedge clk);
      filter_in = sigma_delta_modulator(dc_level);
    end
    
    $display("[INFO] Generated %0d output samples", valid_outputs);
    if (valid_outputs > 0) begin
      $display("[INFO] Average output: %f (expected ~%f)", 
               (sum_output/valid_outputs)/(2.0**20), dc_level);
      $display("[INFO] Max output: %f", max_output/(2.0**20));
      $display("[INFO] Min output: %f", min_output/(2.0**20));
    end
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 6: Sine Wave Input - Low Frequency
    ////////////////////////////////////////////////////////////////////////////
    test_number = 6;
    output_count = 0;
    sigma_delta_integrator = 0.0;
    max_output = -2097152.0;
    min_output = 2097151.0;
    sum_output = 0.0;
    valid_outputs = 0;
    
    $display("\n[TEST %0d] SINE WAVE INPUT - Low Frequency", test_number);
    $display("------------------------------------------------------------------------");
    
    // Generate 10 complete cycles of sine wave
    // Sine frequency: Output_rate / 100 (so 100 output samples per cycle)
    sine_phase = 0.0;
    
    for (i = 0; i < TOTAL_DECIMATION * 1000; i = i + 1) begin
      sine_value = 0.8 * $sin(sine_phase);  // 0.8 amplitude
      sine_phase = sine_phase + (2.0 * 3.14159265359 / (TOTAL_DECIMATION * 100.0));
      
      @(posedge clk);
      filter_in = sigma_delta_modulator(sine_value);
    end
    
    $display("[INFO] Generated %0d output samples for sine wave", valid_outputs);
    if (valid_outputs > 0) begin
      $display("[INFO] Max output: %f (expected ~0.8)", max_output/(2.0**20));
      $display("[INFO] Min output: %f (expected ~-0.8)", min_output/(2.0**20));
      $display("[INFO] Average output: %f (expected ~0.0)", 
               (sum_output/valid_outputs)/(2.0**20));
    end
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 7: Step Response
    ////////////////////////////////////////////////////////////////////////////
    test_number = 7;
    output_count = 0;
    sigma_delta_integrator = 0.0;
    
    $display("\n[TEST %0d] STEP RESPONSE TEST - 0 to +0.8", test_number);
    $display("------------------------------------------------------------------------");
    
    // Start at zero
    dc_level = 0.0;
    for (i = 0; i < TOTAL_DECIMATION * 20; i = i + 1) begin
      @(posedge clk);
      filter_in = sigma_delta_modulator(dc_level);
    end
    
    $display("[INFO] Step applied at time %0t ns", $time);
    
    // Apply step
    dc_level = 0.8;
    for (i = 0; i < TOTAL_DECIMATION * 100; i = i + 1) begin
      @(posedge clk);
      filter_in = sigma_delta_modulator(dc_level);
    end
    
    $display("[INFO] Step response captured for 100 output samples");
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 8: Ramp Input
    ////////////////////////////////////////////////////////////////////////////
    test_number = 8;
    output_count = 0;
    sigma_delta_integrator = 0.0;
    
    $display("\n[TEST %0d] RAMP INPUT TEST - Slow ramp from -0.8 to +0.8", test_number);
    $display("------------------------------------------------------------------------");
    
    // Ramp over 200 output samples
    for (i = 0; i < TOTAL_DECIMATION * 200; i = i + 1) begin
      dc_level = -0.8 + (1.6 * $itor(i) / $itor(TOTAL_DECIMATION * 200));
      @(posedge clk);
      filter_in = sigma_delta_modulator(dc_level);
    end
    
    $display("[INFO] Ramp input completed over 200 output samples");
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 9: Alternating Pattern
    ////////////////////////////////////////////////////////////////////////////
    test_number = 9;
    output_count = 0;
    sigma_delta_integrator = 0.0;
    
    $display("\n[TEST %0d] ALTERNATING PATTERN - Square wave (low frequency)", test_number);
    $display("------------------------------------------------------------------------");
    
    // Alternate between +0.7 and -0.7 every 50 output samples
    for (j = 0; j < 10; j = j + 1) begin
      dc_level = (j % 2 == 0) ? 0.7 : -0.7;
      for (i = 0; i < TOTAL_DECIMATION * 50; i = i + 1) begin
        @(posedge clk);
        filter_in = sigma_delta_modulator(dc_level);
      end
    end
    
    $display("[INFO] Alternating pattern completed");
    
    ////////////////////////////////////////////////////////////////////////////
    // TEST 10: Extended Run with Random Clk_Enable
    ////////////////////////////////////////////////////////////////////////////
    test_number = 10;
    output_count = 0;
    sigma_delta_integrator = 0.0;
    
    $display("\n[TEST %0d] CLOCK ENABLE TEST - Random clk_enable toggling", test_number);
    $display("------------------------------------------------------------------------");
    
    dc_level = 0.5;
    for (i = 0; i < TOTAL_DECIMATION * 100; i = i + 1) begin
      @(posedge clk);
      // Randomly disable clock enable (10% of the time)
      if ($random % 10 == 0)
        clk_enable = 0;
      else
        clk_enable = 1;
      
      if (clk_enable)
        filter_in = sigma_delta_modulator(dc_level);
    end
    
    // Restore clock enable
    clk_enable = 1;
    $display("[INFO] Clock enable test completed");
    
    ////////////////////////////////////////////////////////////////////////////
    // Test Completion
    ////////////////////////////////////////////////////////////////////////////
    repeat(1000) @(posedge clk);  // Let pipeline flush
    
    $display("\n================================================================================");
    $display("                    ALL TESTS COMPLETED");
    $display("================================================================================");
    $display("Total simulation time: %0t ns", $time);
    $display("Output data saved to: decimator_output.csv");
    $display("================================================================================\n");
    
    $fclose(output_file);
    $finish;
  end
  
  ////////////////////////////////////////////////////////////////////////////
  // Timeout Watchdog
  ////////////////////////////////////////////////////////////////////////////
  initial begin
    #500_000_000;  // 500 ms timeout
    $display("\n[ERROR] Simulation timeout!");
    $fclose(output_file);
    $finish;
  end
  
  ////////////////////////////////////////////////////////////////////////////
  // Waveform Dump (for viewing in GTKWave or ModelSim)
  ////////////////////////////////////////////////////////////////////////////
  initial begin
    $dumpfile("decimator_chain_tb.vcd");
    $dumpvars(0, tb_Decimator_Chain_Top);
  end
  
endmodule

