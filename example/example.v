module example(input OSC_50_B3B,

               output [3:0] LED,
               
               // using the HPS requires a *lot* of memory signals to
               // be connected...
               output [14:0] DDR3_A,
               output [2:0]  DDR3_BA,
               output        DDR3_CK_p,
               output        DDR3_CK_n,
               output        DDR3_CKE,
               output        DDR3_CS_n,
               output        DDR3_RAS_n,
               output        DDR3_CAS_n,
               output        DDR3_WE_n,
               output        DDR3_RESET_n,
               inout  [39:0] DDR3_DQ,
               inout  [4:0]  DDR3_DQS_p,
               inout  [4:0]  DDR3_DQS_n,
               output        DDR3_ODT,
               output [4:0]  DDR3_DM,
               input         DDR3_RZQ
               );

   // give an easier name to our clock
   wire clk = OSC_50_B3B;

   // data is read in from here each clock cycle
   wire [31:0] sampler;
   // data is played out to here each clock cycle
   wire [31:0] player;
   // the widths of both of these, and other settings, can be
   // configured in Qsys by editing hps_system.qsys and regenerating

   // when the sampler turns on, this goes high
   wire sampler_active;
   // when the player turns on, this goes high
   wire player_active;

   // we'll connect the sampler input to the player output, as a demo
   assign sampler = player;

   // declare our hps instance (defined in hps_system.qsys, needs to
   // be generated...)
   hps_system hps(.clk_clk(clk),
                  .reset_reset_n(1),

                  // data is read in here each clock cycle
                  .sample_export(sampler),
                  
                  // data is played out here on each clock cycle
                  .play_export(player),

                  // connect the active outputs / active low reset
                  // outputs
                  .sample_reset_reset_n(sampler_active),
                  .play_reset_reset_n(player_active),

                  // manually connect sampler_active to player_enable
                  // this will force player on as soon as sampler
                  // turns on!
                  .play_enable_export(sampler_active),

                  // all of the memory connections (there are a lot)
                  .memory_mem_a(DDR3_A),
                  .memory_mem_ba(DDR3_BA),
                  .memory_mem_ck(DDR3_CK_p),
                  .memory_mem_ck_n(DDR3_CK_n),
                  .memory_mem_cke(DDR3_CKE),
                  .memory_mem_cs_n(DDR3_CS_n),
                  .memory_mem_ras_n(DDR3_RAS_n),
                  .memory_mem_cas_n(DDR3_CAS_n),
                  .memory_mem_we_n(DDR3_WE_n),
                  .memory_mem_reset_n(DDR3_RESET_n),
                  .memory_mem_dq(DDR3_DQ),
                  .memory_mem_dqs(DDR3_DQS_p),
                  .memory_mem_dqs_n(DDR3_DQS_n),
                  .memory_mem_odt(DDR3_ODT),
                  .memory_mem_dm(DDR3_DM),
                  .memory_oct_rzqin(DDR3_RZQ)
                  );

   // for visual interest, we'll display a binary counter on the LEDs
   reg [27:0] counter;
   always @(posedge clk)
     counter <= counter + 1;
   assign LED = counter[27:24];
endmodule
