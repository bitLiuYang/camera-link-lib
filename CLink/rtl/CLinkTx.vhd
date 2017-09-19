-------------------------------------------------------------------------------
-- Title      : Camera link transmitter
-------------------------------------------------------------------------------
-- File       : CLinkTx.vhd
-- Created    : 2017-08-22
-- Platform   : 
-- Standard   : VHDL'93/02
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
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;

use work.CLinkPkg.all;

--***********************************Entity Declaration*************************

entity CLinkTx is
generic
(
    TPD_G            : time               := 1 ns;
    CLK_RATE_INT_G : integer              := 125000000;
    LANE_G         : integer range 0 to 7 := 0
);
port
(
    -- System Interface
    systemReset : in    std_logic;
    pciClk      : in    std_logic;
    evrClk      : in    std_logic;

    -- GTP Interface
    txClk       : in    std_logic;
    txData      : out   std_logic_vector(15 downto 0);
    txCtrl      : out   std_logic_vector( 1 downto 0); 

    -- Parallel Interface
    evrToCl_trigger      : in    std_logic;
    pciToCl_pack16       : in    std_logic;
    pciToCl_trgPolarity  : in    std_logic;
    pciToCl_trgCC        : in    std_logic_vector( 1 downto 0); 
    pciToCl_serBaud      : in    std_logic_vector( 31 downto 0); 
    pciToCl_serFifoWrEn  : in    std_logic;
    pciToCl_serFifoWr    : in    std_logic_vector( 7 downto 0); 
    clToPci_serFifoAFull : out   std_logic
);
end CLinkTx;

architecture RTL of CLinkTx is

    signal pack16               : std_logic;
    signal trgPolarity, trigger : std_logic;
    signal trgCC                : std_logic_vector( 1 downto 0);
    signal serBaud              : std_logic_vector(31 downto 0);

    signal sFifoByte           : std_logic_vector( 7 downto 0);
    signal sFifoRdEn           : std_logic;
    signal sFifoFull           : std_logic;
    signal sFifoEmpty          : std_logic;
    signal sFifoValid          : std_logic;
    signal sFifoReset          : std_logic;

    signal camcc_1, camcc      : std_logic_vector( 4 downto 1) := "0000";
    signal sertc_1, sertc      : std_logic                     := '1';

    signal serSend             : std_logic                     := '0';
    signal serBits             : std_logic_vector( 9 downto 0);
    signal sendBit             : integer range 0 to 9;
    signal serCycles           : std_logic_vector(31 downto 0) := (others => '0');

    signal cycleCount          : std_logic_vector(2 downto 0)  := "000";

begin

    -- Synchronizer_trigger : entity work.Synchronizer
    Synchronizer_trigger : entity work.SynchronizerOneShot
        port map (
            clk     => txClk,
            dataIn  => evrToCl_trigger,
            dataOut => trigger);

    Synchronizer_pack16 : entity work.Synchronizer
        port map (
            clk     => txClk,
            dataIn  => pciToCl_pack16,
            dataOut => pack16);

    Synchronizer_trgPolarity : entity work.Synchronizer
        port map (
            clk     => txClk,
            dataIn  => pciToCl_trgPolarity,
            dataOut => trgPolarity);

    SynchronizerFifo_trgCC : entity work.SynchronizerFifo
        generic map (
            DATA_WIDTH_G =>  2)
        port map (
            wr_clk  => pciClk,
            din     => pciToCl_trgCC,
            rd_clk  => txClk,
            dout    => trgCC);

    SynchronizerFifo_serBaud : entity work.SynchronizerFifo
        generic map (
            DATA_WIDTH_G => 32)
        port map (
            wr_clk  => pciClk,
            din     => pciToCl_serBaud,
            rd_clk  => txClk,
            dout    => serBaud);

    U_SerTc_Fifo: entity work.FifoAsync 
       generic map (
          FWFT_EN_G    => true,
          DATA_WIDTH_G => 8,
          ADDR_WIDTH_G => 8)
       port map (
            rst    => systemReset,
            wr_clk => pciClk,
            rd_clk => txClk,
            din    => pciToCl_serFifoWr,
            wr_en  => pciToCl_serFifoWrEn,
            rd_en  => sFifoRdEn,
            dout   => sFifoByte ,
            full   => sFifoFull ,
            almost_full   => clToPci_serFifoAFull ,
            empty  => sFifoEmpty,
            valid  => sFifoValid);

    process( txClk, systemReset )
    begin
        if ( systemReset = '1' ) then
            txData    <= (others => '0');
            txCtrl    <= "00";

            camcc_1    <= "0000";
            sertc_1    <= '1';

            camcc      <= "0000";
            sertc      <= '1';

            cycleCount<= "000";
        elsif ( txClk'event and txClk = '1' ) then
            camcc_1    <= camcc;
            sertc_1    <= sertc;

            if ( trgPolarity = '0' ) then                              -- normal
                if    ( trgCC = "00" ) then
                    camcc <= "000" & trigger;
                elsif ( trgCC = "01" ) then
                    camcc <= "00"  & trigger &   "0";
                elsif ( trgCC = "10" ) then
                    camcc <= "0"   & trigger &  "00";
                else
                    camcc <=         trigger & "000";
                end if;
            else                                                     -- inverted
                if    ( trgCC = "00" ) then
                    camcc <= "000" & (not trigger);
                elsif ( trgCC = "01" ) then
                    camcc <= "00"  & (not trigger) &   "0";
                elsif ( trgCC = "10" ) then
                    camcc <= "0"   & (not trigger) &  "00";
                else
                    camcc <=         (not trigger) & "000";
                end if;
            end if;

            if ( sFifoRdEn = '1' ) then
                sFifoRdEn <= '0';
            end if;

            if ( serSend = '0' ) and ( sFifoValid = '1' ) then  -- got byte
                serSend    <= '1';
                serBits    <= '1' & sFifoByte & '0';
                sendBit    <=  0;
                sertc      <= '0';
                serCycles  <= (others => '0');

                sFifoRdEn <= '1';
            elsif ( serSend = '1' ) then
                if ( serCycles < CLK_RATE_INT_G ) then
                    serCycles <= serCycles + serBaud;
                elsif ( sendBit > 8 ) then          -- finished all the 10 bits
                    serSend   <= '0';
                    sertc      <= '1';
                else                                                 -- next bit
                    sendBit   <= sendBit + 1;
                    sertc     <= serBits( sendBit + 1 );
                    serCycles <= (others => '0');
                end if;
            end if;

            if ( camcc /= camcc_1 ) or ( sertc /= sertc_1 ) or
               ( cycleCount(2) = '1' ) then                -- send control word
                cycleCount <= (others => '0');
                txData     <= X"00" & '1' & pack16 & '1' & sertc & camcc;
                txCtrl     <= "00";
            else                                              -- send comma word
                cycleCount <= cycleCount + 1;
                txData     <= X"C5BC";
                txCtrl     <= "01";
            end if;
        end if;
    end process;

end RTL;

