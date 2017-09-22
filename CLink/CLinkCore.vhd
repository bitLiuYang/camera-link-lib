-------------------------------------------------------------------------------
-- File       : CLinkCore.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-09-05
-- Last update: 2017-09-22
-------------------------------------------------------------------------------
-- Description: CLinkCore top-level
-------------------------------------------------------------------------------
-- This file is part of 'axi-pcie-core'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'axi-pcie-core', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.StdRtlPkg.all;
use work.AxiLitePkg.all;
use work.AxiStreamPkg.all;
use work.TimingPkg.all;
use work.SsiPkg.all;
use work.CLinkPkg.all;

entity CLinkCore is
   generic (
      TPD_G            : time                 := 1 ns;
      SYS_CLK_FREQ_G   : real                 := 125.0E+6;
      DEFAULT_CLINK_G  : boolean              := true;  -- false = 1.25Gb/s, true = 2.5Gb/s
      LANE_G           : integer range 0 to 7 := 0;
      AXI_ERROR_RESP_G : slv(1 downto 0)      := AXI_RESP_DECERR_C;
      AXI_BASE_ADDR_G  : slv(31 downto 0)     := (others => '0'));
   port (
      -- RX Interface (rxClk domain)
      rxClk           : in  sl;
      rxRst           : in  sl;
      rxData          : in  slv(15 downto 0);
      rxCtrl          : in  slv(1 downto 0);
      rxDecErr        : in  slv(1 downto 0);
      rxDispErr       : in  slv(1 downto 0);
      -- TX Interface (txClk domain)
      txClk           : in  sl;
      txRst           : in  sl;
      txData          : out slv(15 downto 0);
      txCtrl          : out slv(1 downto 0);
      -- DMA Interface (sysClk domain)
      dmaObMaster     : in  AxiStreamMasterType;
      dmaObSlave      : out AxiStreamSlaveType;
      dmaIbMaster     : out AxiStreamMasterType;
      dmaIbSlave      : in  AxiStreamSlaveType;
      -- Timing Interface (evrClk domain)
      evrClk          : in  sl;
      evrRst          : in  sl;
      evrTimingBus    : in  TimingBusType;
      -- AXI-Lite Interface (sysClk domain)
      sysClk          : in  sl;
      sysRst          : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end CLinkCore;

architecture mapping of CLinkCore is

   constant NUM_AXI_MASTERS_C : natural := 2;

   constant REG_INDEX_C  : natural := 0;
   constant TRIG_INDEX_C : natural := 1;

   constant AXI_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXI_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXI_MASTERS_C, AXI_BASE_ADDR_G, 13, 12);

   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXI_MASTERS_C-1 downto 0);

   signal dmaObMasters : AxiStreamMasterArray(1 downto 0);
   signal dmaObSlaves  : AxiStreamSlaveArray(1 downto 0);
   signal dmaIbMasters : AxiStreamMasterArray(1 downto 0);
   signal dmaIbSlaves  : AxiStreamSlaveArray(1 downto 0);

   signal obMasters : AxiStreamMasterArray(1 downto 0);
   signal obSlaves  : AxiStreamSlaveArray(1 downto 0);
   signal ibMasters : AxiStreamMasterArray(1 downto 0);
   signal ibSlaves  : AxiStreamSlaveArray(1 downto 0);

   signal evrTrig      : sl;
   signal evrTimeStamp : slv(63 downto 0);

   signal rxStatus : CLinkRxStatusType;
   signal txStatus : CLinkTxStatusType;
   signal config   : CLinkConfigType;


begin

   ---------------------
   -- AXI-Lite Crossbar
   ---------------------
   U_XBAR : entity work.AxiLiteCrossbar
      generic map (
         TPD_G              => TPD_G,
         DEC_ERROR_RESP_G   => AXI_ERROR_RESP_G,
         NUM_SLAVE_SLOTS_G  => 1,
         NUM_MASTER_SLOTS_G => NUM_AXI_MASTERS_C,
         MASTERS_CONFIG_G   => AXI_CONFIG_C)
      port map (
         axiClk              => sysClk,
         axiClkRst           => sysRst,
         sAxiWriteMasters(0) => axilWriteMaster,
         sAxiWriteSlaves(0)  => axilWriteSlave,
         sAxiReadMasters(0)  => axilReadMaster,
         sAxiReadSlaves(0)   => axilReadSlave,
         mAxiWriteMasters    => axilWriteMasters,
         mAxiWriteSlaves     => axilWriteSlaves,
         mAxiReadMasters     => axilReadMasters,
         mAxiReadSlaves      => axilReadSlaves);

   U_Trig : entity work.LclsTriggerCore
      generic map (
         TPD_G                => TPD_G,
         AXIL_BASE_ADDR_G     => AXI_CONFIG_C(TRIG_INDEX_C).baseAddr,
         AXI_ERROR_RESP_G     => AXI_ERROR_RESP_G,
         NUM_OF_TRIG_PULSES_G => 1,
         DELAY_WIDTH_G        => 32,
         PULSE_WIDTH_G        => 32)
      port map (
         -- AXI-Lite Interface
         axilClk         => sysClk,
         axilRst         => sysRst,
         axilReadMaster  => axilReadMasters(TRIG_INDEX_C),
         axilReadSlave   => axilReadSlaves(TRIG_INDEX_C),
         axilWriteMaster => axilWriteMasters(TRIG_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(TRIG_INDEX_C),
         -- Timing Interface
         recClk          => evrClk,
         recRst          => evrRst,
         timingBus_i     => evrTimingBus,
         -- Trigger pulse outputs (recClk domain)
         trigPulse_o(0)  => evrTrig,
         timeStamp_o     => evrTimeStamp,
         pulseId_o       => open,
         bsa_o           => open,
         dmod_o          => open);

   U_Reg : entity work.CLinkReg
      generic map (
         TPD_G            => TPD_G,
         DEFAULT_CLINK_G  => DEFAULT_CLINK_G,
         AXI_ERROR_RESP_G => AXI_ERROR_RESP_G)
      port map (
         -- Configuration and Status (sysClk domain)
         rxStatus        => rxStatus,
         txStatus        => txStatus,
         config          => config,
         -- AXI Lite interface
         sysClk          => sysClk,
         sysRst          => sysRst,
         axilReadMaster  => axilReadMasters(REG_INDEX_C),
         axilReadSlave   => axilReadSlaves(REG_INDEX_C),
         axilWriteMaster => axilWriteMasters(REG_INDEX_C),
         axilWriteSlave  => axilWriteSlaves(REG_INDEX_C));

   U_Tx : entity work.CLinkTxWrapper
      generic map (
         TPD_G           => TPD_G,
         SYS_CLK_FREQ_G  => SYS_CLK_FREQ_G,
         DEFAULT_CLINK_G => DEFAULT_CLINK_G,
         LANE_G          => LANE_G)
      port map (
         -- System Interface
         sysClk      => sysClk,
         sysRst      => sysRst,
         -- GT Interface (txClk domain)      
         txClk       => txClk,
         txRst       => txRst,
         txData      => txData,
         txCtrl      => txCtrl,
         -- EVR Interface (evrClk domain)
         evrClk      => evrClk,
         evrRst      => evrRst,
         evrTrig     => evrTrig,
         -- DMA Interface (sysClk domain)
         serRxMaster => dmaObMaster,
         serRxSlave  => dmaObSlave,
         -- Configuration and Status (sysClk domain)
         txStatus    => txStatus,
         config      => config);

   U_Rx : entity work.CLinkRxWrapper
      generic map (
         TPD_G           => TPD_G,
         SYS_CLK_FREQ_G  => SYS_CLK_FREQ_G,
         DEFAULT_CLINK_G => DEFAULT_CLINK_G,
         LANE_G          => LANE_G)
      port map (
         -- System Interface
         sysClk        => sysClk,
         sysRst        => sysRst,
         -- GT Interface (rxClk domain)
         rxClk         => rxClk,
         rxRst         => rxRst,
         rxData        => rxData,
         rxCtrl        => rxCtrl,
         rxDecErr      => rxDecErr,
         rxDispErr     => rxDispErr,
         -- EVR Interface (evrClk domain)
         evrClk        => evrClk,
         evrRst        => evrRst,
         evrTrig       => evrTrig,
         evrTimeStamp  => evrTimeStamp,
         -- DMA Interfaces (sysClk domain)
         serTxMaster   => dmaIbMasters(0),
         serTxSlave    => dmaIbSlaves(0),
         camDataMaster => dmaIbMasters(1),
         camDataSlave  => dmaIbSlaves(1),
         -- Configuration and Status (sysClk domain)
         rxStatus      => rxStatus,
         config        => config);

   U_IbFifo : entity work.AxiStreamFifoV2
      generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         INT_PIPE_STAGES_G   => 1,
         PIPE_STAGES_G       => 1,
         VALID_THOLD_G       => 128,  -- Hold until enough to burst into the interleaving MUX
         VALID_BURST_MODE_G  => true,
         -- FIFO configurations
         BRAM_EN_G           => true,
         XIL_DEVICE_G        => "7SERIES",
         USE_BUILT_IN_G      => false,
         GEN_SYNC_FIFO_G     => true,
         CASCADE_SIZE_G      => 1,
         FIFO_ADDR_WIDTH_G   => 9,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => ssiAxiStreamConfig(4),
         MASTER_AXI_CONFIG_G => ssiAxiStreamConfig(4))
      port map (
         -- Slave Port
         sAxisClk    => sysClk,
         sAxisRst    => sysRst,
         sAxisMaster => dmaIbMasters(1),
         sAxisSlave  => dmaIbSlaves(1),
         -- Master Port
         mAxisClk    => sysClk,
         mAxisRst    => sysRst,
         mAxisMaster => ibMasters(1),
         mAxisSlave  => ibSlaves(1));

   -- No "store and forward" FIFO requires for UART "byte" serial stream
   ibMasters(0)   <= dmaIbMasters(0);
   dmaIbSlaves(0) <= ibSlaves(0);

   --------------
   -- MUX Module
   --------------               
   U_Mux : entity work.AxiStreamMux
      generic map (
         TPD_G          => TPD_G,
         NUM_SLAVES_G   => 2,
         MODE_G         => "INDEXED",
         ILEAVE_EN_G    => true,        -- Using interleaving MUX
         ILEAVE_REARB_G => 0,
         PIPE_STAGES_G  => 1)
      port map (
         -- Clock and reset
         axisClk      => sysClk,
         axisRst      => sysRst,
         -- Slaves
         sAxisMasters => ibMasters,
         sAxisSlaves  => ibSlaves,
         -- Master
         mAxisMaster  => dmaIbMaster,
         mAxisSlave   => dmaIbSlave);

end mapping;
