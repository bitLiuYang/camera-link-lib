-------------------------------------------------------------------------------
-- File       : CLinkReg.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-09-20
-- Last update: 2017-09-25
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- This file is part of 'SLAC PGP Gen3 Card'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC PGP Gen3 Card', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

use work.StdRtlPkg.all;
use work.AxiLitePkg.all;
use work.CLinkPkg.all;

entity CLinkReg is
   generic (
      TPD_G            : time            := 1 ns;
      DEFAULT_CLINK_G  : boolean         := true;  -- false = 1.25Gb/s, true = 2.5Gb/s
      AXI_ERROR_RESP_G : slv(1 downto 0) := AXI_RESP_DECERR_C);
   port (
      -- Configuration and Status (sysClk domain)
      rxStatus        : in  CLinkRxStatusType;
      txStatus        : in  CLinkTxStatusType;
      config          : out CLinkConfigType;
      rxUserRst       : out sl;
      txUserRst       : out sl;
      loopback        : out slv(2 downto 0);
      -- AXI-Lite Register Interface (sysClk domain)
      sysClk          : in  sl;
      sysRst          : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end CLinkReg;

architecture rtl of CLinkReg is

   type RegType is record
      config         : CLinkConfigType;
      axilReadSlave  : AxiLiteReadSlaveType;
      axilWriteSlave : AxiLiteWriteSlaveType;
   end record;

   constant REG_INIT_C : RegType := (
      config         => CLINK_CONFIG_INIT_C,
      axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C);

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

begin

   --------------------- 
   -- AXI Lite Interface
   --------------------- 
   comb : process (axilReadMaster, axilWriteMaster, r, rxStatus, sysRst,
                   txStatus) is
      variable v      : RegType;
      variable regCon : AxiLiteEndPointType;
   begin
      -- Latch the current value
      v := r;

      -- Reset the strobes
      v.config.rxUserRst := '0';
      v.config.txUserRst := '0';

      -- Determine the transaction type
      axiSlaveWaitTxn(regCon, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

      -- Map the registers
      axiSlaveRegister(regCon, x"00", 0, v.config.enable);
      axiSlaveRegister(regCon, x"04", 0, v.config.trgPolarity);
      axiSlaveRegister(regCon, x"08", 0, v.config.pack16);
      axiSlaveRegister(regCon, x"0C", 0, v.config.trgCC);

      axiSlaveRegister(regCon, x"10", 0, v.config.numTrains);
      axiSlaveRegister(regCon, x"14", 0, v.config.numCycles);
      axiSlaveRegister(regCon, x"18", 0, v.config.serBaud);
      axiSlaveRegister(regCon, x"1C", 0, v.config.loopback);

      axiSlaveRegister(regCon, x"20", 0, v.config.rxUserRst);
      axiSlaveRegister(regCon, x"24", 0, v.config.txUserRst);

      axiSlaveRegisterR(regCon, x"40", 0, rxStatus.rxRst);
      axiSlaveRegisterR(regCon, x"44", 0, rxStatus.evrRst);
      axiSlaveRegisterR(regCon, x"48", 0, rxStatus.linkStatus);
      axiSlaveRegisterR(regCon, x"4C", 0, rxStatus.cLinkLock);

      axiSlaveRegisterR(regCon, x"50", 0, rxStatus.trgCount);
      axiSlaveRegisterR(regCon, x"54", 0, rxStatus.trgToFrameDly);
      axiSlaveRegisterR(regCon, x"58", 0, rxStatus.frameCount);
      axiSlaveRegisterR(regCon, x"5C", 0, rxStatus.frameRate);

      axiSlaveRegisterR(regCon, x"60", 0, rxStatus.rxClkFreq);
      axiSlaveRegisterR(regCon, x"64", 0, rxStatus.evrClkFreq);

      axiSlaveRegisterR(regCon, x"80", 0, txStatus.txRst);
      axiSlaveRegisterR(regCon, x"84", 0, txStatus.txClkFreq);
      axiSlaveRegisterR(regCon, x"88", 0, txStatus.evrTrigRate);

      axiSlaveRegisterR(regCon, x"FC", 0, ite(DEFAULT_CLINK_G, toSlv(1, 32), toSlv(0, 32)));

      -- Closeout the transaction
      axiSlaveDefault(regCon, v.axilWriteSlave, v.axilReadSlave, AXI_ERROR_RESP_G);

      -- Synchronous Reset
      if (sysRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

      -- Outputs
      axilWriteSlave <= r.axilWriteSlave;
      axilReadSlave  <= r.axilReadSlave;
      config         <= r.config;
      loopBack       <= r.config.loopback;

   end process comb;

   seq : process (sysClk) is
   begin
      if (rising_edge(sysClk)) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   U_rxUserRst : entity work.PwrUpRst
      generic map (
         TPD_G      => TPD_G,
         DURATION_G => 12500000)
      port map (
         arst   => r.config.rxUserRst,
         clk    => sysClk,
         rstOut => rxUserRst);

   U_txUserRst : entity work.PwrUpRst
      generic map (
         TPD_G      => TPD_G,
         DURATION_G => 12500000)
      port map (
         arst   => r.config.txUserRst,
         clk    => sysClk,
         rstOut => txUserRst);

end rtl;
