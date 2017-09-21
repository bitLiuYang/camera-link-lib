-------------------------------------------------------------------------------
-- Title      : Camera link receiver
-------------------------------------------------------------------------------
-- File       : CLinkRx.vhd
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
use work.AxiStreamPkg.all;
use work.SsiPkg.all;
use work.StdRtlPkg.all;
use work.Pgp2bPkg.all;

--***********************************Entity Declaration*************************

entity CLinkRx is
generic
(
    TPD_G           : time                 := 1 ns;
    CLK_RATE_INT_G  : integer              := 125000000;
    LANE_G          : integer range 0 to 7 := 0
);
port
(
    -- System Interface
    systemReset     : in    std_logic;
    pciClk          : in    std_logic;
    evrClk          : in    std_logic;

    -- GT Interface
    rxClk           : in    std_logic; -- unused???
    rxRst           : in    std_logic;
    rxData          : in    std_logic_vector(15 downto 0);
    rxCtrl          : in    std_logic_vector( 1 downto 0); 
    rxDecErr        : in    std_logic_vector( 1 downto 0); 
    rxDispErr       : in    std_logic_vector( 1 downto 0); 
    
    -- Parallel Interface
    
    pciToCl_pack16      : in    std_logic;
    pciToCl_trgPolarity : in    std_logic;
    pciToCl_enable      : in    std_logic;
    pciToCl_numTrains   : in    std_logic_vector(31 downto 0);
    pciToCl_numCycles   : in    std_logic_vector(31 downto 0);
    pciToCl_serBaud     : in    std_logic_vector(31 downto 0);
    pciToCl_SerFifoRdEn : in    std_logic;
    
    evrToCl_trigger : in    std_logic;
    evrToCl_seconds : in    std_logic_vector(31 downto 0);
    evrToCl_nanosec : in    std_logic_vector(31 downto 0);

    linkStatus      : out   std_logic;
    cLinkLock       : out   std_logic;

    trgCount        : out   std_logic_vector(31 downto 0);
    trgToFrameDly   : out   std_logic_vector(31 downto 0);
    frameCount      : out   std_logic_vector(31 downto 0);
    frameRate       : out   std_logic_vector(31 downto 0);

    serTfgByte      : out   std_logic_vector( 7 downto 0);
    serTfgValid     : out   std_logic;

    dmaClk          : in  sl;
    dmaRst          : in  sl;    
    dmaStreamMaster : out   AxiStreamMasterType;
    dmaStreamSlave  : in    AxiStreamSlaveType
);
end CLinkRx;


architecture RTL of CLinkRx is

    constant AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(4);  -- 32-bit interface

    signal   pack16                         : std_logic;
    signal   serBaud                        : std_logic_vector( 31 downto 0);

    signal   linkStatus_i, frameSync        : std_logic := '0';

    signal   trgPolarity                    : std_logic := '0';
    signal   trigger, trigger_1             : std_logic := '0';

    signal   enable, enable_i               : std_logic := '0';

    signal   numTrains, numCycles,
             trgCount_i, frameCount_i,
             trgToFrameDly_i,
             trgToFrameDly_l,
             seconds_i, nanosec_i,
             seconds_l, nanosec_l,
             frameRate_i, frameRate_o,
             rateCount                     : std_logic_vector( 31 downto 0);

    signal   fval, lval, sertfg, dataCycle : std_logic := '0';
    signal   sertfg_1                      : std_logic := '0';

    signal   wordCount                     : std_logic_vector( 12 downto 0);
    signal   lineCount                     : std_logic_vector( 11 downto 0);

    signal   serSync                       : std_logic;
    signal   serStep                       : std_logic_vector(  1 downto 0);
    signal   serCycles                     : std_logic_vector( 31 downto 0);
    signal   serBit, serMax                : natural range 0 to 9;

    signal   serDelay                      : natural range 0 to 31   :=  0;
    signal   serClk                        : std_logic               := '0';

    signal   sFifoByte                     : std_logic_vector(  7 downto 0);
    signal   sFifoWrEn                     : std_logic;
    signal   sFifoFull                     : std_logic;
    signal   sFifoEmpty                    : std_logic;
    signal   sFifoReset                    : std_logic;

    signal   idleStream                    : std_logic_vector(495 downto 0);
    signal   idleCount                     : natural range 0 to 65535 :=  0;

    constant RATE_CMP_C : integer := ite(CLK_RATE_INT_G=125000000,  125499999,  62749999);
    constant cycles_1m  : integer := ite(CLK_RATE_INT_G=125000000,  117187500,  58593750);
    constant cycles_1p  : integer := ite(CLK_RATE_INT_G=125000000,  132812500,  66406250);
    constant cycles_2m  : integer := ite(CLK_RATE_INT_G=125000000,  238281250, 119140625);
    constant cycles_2p  : integer := ite(CLK_RATE_INT_G=125000000,  261718750, 130859375);
    constant cycles_3m  : integer := ite(CLK_RATE_INT_G=125000000,  359375000, 179687500);
    constant cycles_3p  : integer := ite(CLK_RATE_INT_G=125000000,  390625000, 195312500);
    constant cycles_4m  : integer := ite(CLK_RATE_INT_G=125000000,  480468750, 240234375);
    constant cycles_4p  : integer := ite(CLK_RATE_INT_G=125000000,  519531250, 259765625);
    constant cycles_5m  : integer := ite(CLK_RATE_INT_G=125000000,  601562500, 300781250);
    constant cycles_5p  : integer := ite(CLK_RATE_INT_G=125000000,  648437500, 324218750);
    constant cycles_6m  : integer := ite(CLK_RATE_INT_G=125000000,  722656250, 361328125);
    constant cycles_6p  : integer := ite(CLK_RATE_INT_G=125000000,  777343750, 388671875);
    constant cycles_7m  : integer := ite(CLK_RATE_INT_G=125000000,  843750000, 421875000);
    constant cycles_7p  : integer := ite(CLK_RATE_INT_G=125000000,  906250000, 453125000);
    constant cycles_8m  : integer := ite(CLK_RATE_INT_G=125000000,  964843750, 482421875);
    constant cycles_8p  : integer := ite(CLK_RATE_INT_G=125000000, 1035156250, 517578125);
    constant cycles_9m  : integer := ite(CLK_RATE_INT_G=125000000, 1085937500, 542968750);
    constant cycles_9p  : integer := ite(CLK_RATE_INT_G=125000000, 1164062500, 582031250);

    signal   rx16Master : AxiStreamMasterType;
    signal   rx16Slave  : AxiStreamSlaveType;

    signal   fifoErr    : std_logic         := '0';

    signal   rx4k       : std_logic_vector(  3 downto 0) := (others => '0');
    signal   rx4kCount  : std_logic_vector( 13 downto 0) := (others => '1');

begin

    Synchronizer_pack16 : entity work.Synchronizer
        port map (
            clk     => rxClk,
            dataIn  => pciToCl_pack16,
            dataOut => pack16);

    Synchronizer_trgPolarity : entity work.Synchronizer
        port map (
            clk     => rxClk,
            dataIn  => pciToCl_trgPolarity,
            dataOut => trgPolarity);

    Synchronizer_enable : entity work.Synchronizer
        port map (
            clk     => rxClk,
            dataIn  => pciToCl_enable,
            dataOut => enable);

    SynchronizerFifo_numTrains : entity work.SynchronizerFifo
        generic map (
            DATA_WIDTH_G => 32)
        port map (
            wr_clk  => pciClk,
            din     => pciToCl_numTrains,
            rd_clk  => rxClk,
            dout    => numTrains);

    SynchronizerFifo_numCycles : entity work.SynchronizerFifo
        generic map (
            DATA_WIDTH_G => 32)
        port map (
            wr_clk  => pciClk,
            din     => pciToCl_numCycles,
            rd_clk  => rxClk,
            dout    => numCycles);

    SynchronizerFifo_serBaud : entity work.SynchronizerFifo
        generic map (
            DATA_WIDTH_G => 32)
        port map (
            wr_clk  => pciClk,
            din     => pciToCl_serBaud,
            rd_clk  => rxClk,
            dout    => serBaud);

    Synchronizer_trigger : entity work.Synchronizer
        port map (
            clk     => rxClk,
            dataIn  => evrToCl_trigger,
            dataOut => trigger);

    SynchronizerFifo_seconds : entity work.SynchronizerFifo
        generic map (
            DATA_WIDTH_G => 32)
        port map (
            wr_clk  => evrClk,
            din     => evrToCl_seconds,
            rd_clk  => rxClk,
            dout    => seconds_i);

    SynchronizerFifo_nanosec : entity work.SynchronizerFifo
        generic map (
            DATA_WIDTH_G => 32)
        port map (
            wr_clk  => evrClk,
            din     => evrToCl_nanosec,
            rd_clk  => rxClk,
            dout    => nanosec_i);

    U_SerTfgFifo: entity work.FifoAsync 
       generic map (
          FWFT_EN_G    => true,
          DATA_WIDTH_G => 8,
          ADDR_WIDTH_G => 8)
       port map (
         rst    => systemReset, 
         wr_clk => rxClk,
         rd_clk => pciClk,
         din    => sFifoByte ,
         wr_en  => sFifoWrEn,
         rd_en  => pciToCl_SerFifoRdEn,
         dout   => serTfgByte,
         full   => sFifoFull ,
         empty  => sFifoEmpty,
         valid  => serTfgValid);

    RxBuffer_Inst : entity work.CLinkRxBuffer
        generic map (
            TPD_G            => TPD_G,
            CASCADE_SIZE_G   => 1,
            SLAVE_READY_EN_G => false,
            LANE_G           => LANE_G)
        port map (
            seconds         => seconds_l,
            nanosec         => nanosec_l,
            trgToFrameDly   => trgToFrameDly_l,
            frameCount      => frameCount_i,
            frameRate       => frameRate_o,

            -- 16-bit Streaming RX Interface
            rx16Master      => rx16Master,
            rx16Slave       => rx16Slave,
            -- 32-bit Streaming TX Interface
            dmaClk          => dmaClk,
            dmaRst          => dmaRst,
            dmaStreamMaster => dmaStreamMaster,
            dmaStreamSlave  => dmaStreamSlave,
            -- FIFO Overflow Error Strobe
            fifoError       => fifoErr,
            -- Global Signals
            clk             => rxClk,
            rst             => systemReset);          

    trgCount    <= trgCount_i;
    frameCount  <= frameCount_i;

    linkStatus  <= linkStatus_i;
    sFifoReset  <= not linkStatus_i;

    process( rxClk, systemReset ) is
        variable varMaster : AxiStreamMasterType;
    begin
        varMaster := AXI_STREAM_MASTER_INIT_C;

        if (systemReset = '1') then
            linkStatus_i   <= '0';
            cLinkLock      <= '0';
            frameSync      <= '0';

            trgCount_i      <= (others => '0');
            trgToFrameDly_i <= (others => '0');
            frameCount_i    <= (others => '0');
            frameRate_i     <= (others => '0');
            frameRate_o     <= (others => '0');
            rateCount       <= (others => '0');

            dataCycle       <= '0';
            idleCount       <=  0;

            rx4k            <= (others => '0');
            rx4kCount       <= (others => '1');

            -- reset the FIFOs
            sFifoWrEn     <= '0';
        elsif (rxClk'event and rxClk = '1') then
            trigger_1 <= trigger;
            if (trigger /= trigger_1) and (trigger = trgPolarity) then
                trgCount_i      <= trgCount_i + 1;
                trgToFrameDly_i <= (others => '0');
            else
                trgToFrameDly_i <= trgToFrameDly_i + 1;
            end if;

            if (rateCount > RATE_CMP_C) and (rx4k(0) = '1') and
               (rxCtrl = "00") and (rxData(1) = '0') and (fval = '1') then
                frameRate   <= frameRate_i;
                frameRate_o <= frameRate_i;

                frameRate_i <= (others => '0');
                rateCount   <= (others => '0');
            else
                if (rx4k(0) = '1') and
                   (rxCtrl = "00") and (rxData(1) = '0') and (fval = '1') then
                    frameRate_i <= frameRate_i + 1;
                end if;

                rateCount <= rateCount + 1;
            end if;

            varMaster.tValid := '0';

            if (rxData = X"C5BC") and (rxCtrl = "01") then       -- comma word
                rx4k <= rx4k(2 downto 0) & '1';

                if (rx4k(2 downto 0) = "111") then
                    if (linkStatus_i = '0') then
                        linkStatus_i <= '1';
                        cLinkLock    <= '0';
                        frameSync    <= '0';

                        fval          <= '0';
                        lval          <= '0';
                    end if;

                    rx4kCount <= (others => '0');
                else
                    if (rx4kCount(13) = '1') then
                        linkStatus_i <= '0';
                        cLinkLock    <= '0';
                        frameSync    <= '0';

                        fval          <= '0';
                        lval          <= '0';
                    else
                        rx4kCount    <= rx4kCount + 1;
                    end if;
                end if;
            elsif (linkStatus_i = '0') then
                rx4k <= rx4k(2 downto 0) & '0';
                if (rx4kCount(13) = '1') then
                    linkStatus_i <= '0';
                    cLinkLock    <= '0';
                    frameSync    <= '0';

                    fval         <= '0';
                    lval         <= '0';
                else
                    rx4kCount    <= rx4kCount + 1;
                end if;
            else
                rx4k <= rx4k(2 downto 0) & '0';
                if (rx4kCount(13) = '1') then
                    linkStatus_i <= '0';
                    cLinkLock    <= '0';
                    frameSync    <= '0';

                    fval         <= '0';
                    lval         <= '0';
                else
                    rx4kCount    <= rx4kCount + 1;
                end if;

                if (rx4k(0) = '1') then                          -- control word
                    cLinkLock <= rxData(15);
                    sertfg     <= rxData( 4);
                    fval       <= rxData( 1);
                    lval       <= rxData( 0);

                    if (fval = '1') and (rxData(1) = '0') then
                        frameSync <= '1';
                    end if;

                    if (frameSync = '1') then
                        if    (fval = '0') and (rxData(1) = '1') then  -- frame
                            trgToFrameDly   <= trgToFrameDly_i;     -- latch EVR
                            trgToFrameDly_l <= trgToFrameDly_i;
                            seconds_l       <= seconds_i;
                            nanosec_l       <= nanosec_i;

                            enable_i        <= enable;

                            lineCount      <= (others => '0');

                            if (lval = '0') and (rxData(0) = '1') then  -- line
                                wordCount  <= (others => '0');
                            end if;
                        elsif (fval = '1') and (rxData(1) = '0') then    -- end
                            enable_i     <= '0';

                            frameCount_i <= frameCount_i + 1;

                            if (lval = '1') and (rxData(0) = '0') then  -- line
                                lineCount     <= lineCount + 1;
                            end if;
                        elsif (lval = '0') and (rxData(0) = '1') then   -- line
                            wordCount     <= (others => '0');
                        elsif (lval = '1') and (rxData(0) = '0') then    -- end
                            lineCount     <= lineCount + 1;
                        end if;
                    end if;
                elsif (frameSync = '1') then         -- synchronized valid data
                    wordCount <= wordCount + 1;

                    varMaster.tData(15 downto 0) := rxData;
                    varMaster.tDest( 3 downto 0) := "0000";
                    varMaster.tStrb(          0) := '1';
                    varMaster.tKeep(          0) := '1';

                    if (lineCount = 0) and (wordCount = 0) then
                        axiStreamSetUserBit( SSI_PGP2B_CONFIG_C, varMaster, SSI_SOF_C,  '1', 0 );
                        axiStreamSetUserBit( SSI_PGP2B_CONFIG_C, varMaster, SSI_EOFE_C, '0', 0 );

                        varMaster.tLast  := '0';
                        varMaster.tValid := enable_i;
                    else
                        axiStreamSetUserBit( SSI_PGP2B_CONFIG_C, varMaster, SSI_SOF_C,  '0', 0 );
                        axiStreamSetUserBit( SSI_PGP2B_CONFIG_C, varMaster, SSI_EOFE_C, '0', 0 );

                        if    (lineCount > numTrains-1) or  (wordCount > numCycles-1) then
                            varMaster.tValid := '0';
                        elsif (lineCount = numTrains-1) and (wordCount = numCycles-1) then
                            varMaster.tLast  := '1';
                            varMaster.tValid := enable_i;
                        else
                            varMaster.tLast  := '0';
                            varMaster.tValid := enable_i;
                        end if;
                    end if;
                end if;
            end if;

            rx16Master <= varMaster;

            -- decode RS232
            sertfg_1 <= sertfg;
            if (linkStatus_i = '0') then
                serSync    <= '0';
                serCycles  <= (others => '0');

                sFifoWrEn <= '0';
            else
                if (serSync = '0') then
                    if    (sertfg = '0') then
                        serCycles <= (others => '0');
                    elsif (serCycles > cycles_9m) then
                                                     -- 9b5, ready for start bit
                        serSync   <= '1';
                        serBit    <=  0;
                        serMax    <=  9;
                        serStep   <= "00";
                        serCycles <= (others => '0');
                    else
                        serCycles <= serCycles + serBaud;
                    end if;

                    sFifoWrEn <= '0';
                else
                    case serStep is
                        when "00" =>                    -- wait for falling edge
                            if (sertfg_1 = '1') and (sertfg = '0') then
                                sFifoByte <= (others => '0');
                                serStep   <= "10";            -- expect a 0-bit
                            end if;

                            sFifoWrEn <= '0';
                        when "10" => -- expect at least one 0-bit, wait for rising edge or problem
                            if ((serMax = 9) and (serCycles > cycles_9p)) or
                               ((serMax = 8) and (serCycles > cycles_8p)) or
                               ((serMax = 7) and (serCycles > cycles_7p)) or
                               ((serMax = 6) and (serCycles > cycles_6p)) or
                               ((serMax = 5) and (serCycles > cycles_5p)) or
                               ((serMax = 4) and (serCycles > cycles_4p)) or
                               ((serMax = 3) and (serCycles > cycles_3p)) or
                               ((serMax = 2) and (serCycles > cycles_2p)) or
                               ((serMax = 1) and (serCycles > cycles_1p))    then -- low for too long, problem
                                serSync   <= '0';
                                serBit    <=  0;
                                serMax    <=  9;
                                serStep   <= "00";
                                serCycles <= (others => '0');
                            elsif (sertfg = '1') then             -- rising edge
                                if    (serCycles > cycles_1m) and
                                      (serCycles < cycles_1p)     then
                                                             -- only got one bit
                                    serBit  <= serBit + 1;
                                    serMax  <= serMax;
                                    serStep <= "11";

                                    if (serBit > 0) then
                                        sFifoByte(                 serBit-1) <= '0';
                                    end if;
                                elsif (serCycles > cycles_2m) and
                                      (serCycles < cycles_2p)     then
                                                                   -- got 2 bits
                                    serBit  <= serBit + 2;
                                    serMax  <= serMax - 1;
                                    serStep <= "11";

                                    if (serBit > 0) then
                                        sFifoByte(serBit   downto serBit-1) <= "00";
                                    else
                                        sFifoByte(serBit   downto serBit  ) <= "0";
                                    end if;
                                elsif (serCycles > cycles_3m) and
                                      (serCycles < cycles_3p)     then
                                                                   -- got 3 bits
                                    serBit  <= serBit + 3;
                                    serMax  <= serMax - 2;
                                    serStep <= "11";

                                    if (serBit > 0) then
                                        sFifoByte(serBit+1 downto serBit-1) <= "000";
                                    else
                                        sFifoByte(serBit+1 downto serBit  ) <= "00";
                                    end if;
                                elsif (serCycles > cycles_4m) and
                                      (serCycles < cycles_4p)     then
                                                                   -- got 4 bits
                                    serBit  <= serBit + 4;
                                    serMax  <= serMax - 3;
                                    serStep <= "11";

                                    if (serBit > 0) then
                                        sFifoByte(serBit+2 downto serBit-1) <= "0000";
                                    else
                                        sFifoByte(serBit+2 downto serBit  ) <= "000";
                                    end if;
                                elsif (serCycles > cycles_5m) and
                                      (serCycles < cycles_5p)     then
                                                                   -- got 5 bits
                                    serBit  <= serBit + 5;
                                    serMax  <= serMax - 4;
                                    serStep <= "11";

                                    if (serBit > 0) then
                                        sFifoByte(serBit+3 downto serBit-1) <= "00000";
                                    else
                                        sFifoByte(serBit+3 downto serBit  ) <= "0000";
                                    end if;
                                elsif (serCycles > cycles_6m) and
                                      (serCycles < cycles_6p)     then
                                                                   -- got 6 bits
                                    serBit  <= serBit + 6;
                                    serMax  <= serMax - 5;
                                    serStep <= "11";

                                    if (serBit > 0) then
                                        sFifoByte(serBit+4 downto serBit-1) <= "000000";
                                    else
                                        sFifoByte(serBit+4 downto serBit  ) <= "00000";
                                    end if;
                                elsif (serCycles > cycles_7m) and
                                      (serCycles < cycles_7p)     then
                                                                   -- got 7 bits
                                    serBit  <= serBit + 7;
                                    serMax  <= serMax - 6;
                                    serStep <= "11";

                                    if (serBit > 0) then
                                        sFifoByte(serBit+5 downto serBit-1) <= "0000000";
                                    else
                                        sFifoByte(serBit+5 downto serBit  ) <= "000000";
                                    end if;
                                elsif (serCycles > cycles_8m) and
                                      (serCycles < cycles_8p)     then
                                                                   -- got 8 bits
                                    serBit  <= serBit + 8;
                                    serMax  <= serMax - 7;
                                    serStep <= "11";

                                    if (serBit > 0) then
                                        sFifoByte(serBit+6 downto serBit-1) <= "00000000";
                                    else
                                        sFifoByte(serBit+6 downto serBit  ) <= "0000000";
                                    end if;
                                elsif (serCycles > cycles_9m) and
                                      (serCycles < cycles_9p)     then
                                                                   -- got 9 bits
                                    serBit  <= serBit + 9;
                                    serMax  <= serMax - 8;
                                    serStep <= "11";

                                    if (serBit = 0) then
                                        sFifoByte(serBit+7 downto serBit  ) <= "00000000";
                                    end if;
                                else                 -- width not right, problem
                                    serSync <= '0';
                                    serBit  <=  0;
                                    serMax  <=  9;
                                    serStep <= "00";
                                end if;

                                serCycles <= (others => '0');
                            else
                                serCycles <= serCycles + serBaud;
                            end if;

                            sFifoWrEn <= '0';
                        when "11" =>            -- wait for falling edge or idle
                            if ((serMax = 9) and (serCycles > cycles_9m)) or
                               ((serMax = 8) and (serCycles > cycles_8m)) or
                               ((serMax = 7) and (serCycles > cycles_7m)) or
                               ((serMax = 6) and (serCycles > cycles_6m)) or
                               ((serMax = 5) and (serCycles > cycles_5m)) or
                               ((serMax = 4) and (serCycles > cycles_4m)) or
                               ((serMax = 3) and (serCycles > cycles_3m)) or
                               ((serMax = 2) and (serCycles > cycles_2m)) or
                               ((serMax = 1) and (serCycles > cycles_1m))    then -- got (remaining bits and) stop bit
                                serBit     <=  0;
                                serMax     <=  9;
                                serStep    <= "00";
                                serCycles  <= (others => '0');

                                sFifoWrEn <= '1';

                                if    (serBit = 1) then
                                    sFifoByte(7 downto 0) <= (others => '1');
                                elsif (serBit = 2) then
                                    sFifoByte(7 downto 1) <= (others => '1');
                                elsif (serBit = 3) then
                                    sFifoByte(7 downto 2) <= (others => '1');
                                elsif (serBit = 4) then
                                    sFifoByte(7 downto 3) <= (others => '1');
                                elsif (serBit = 5) then
                                    sFifoByte(7 downto 4) <= (others => '1');
                                elsif (serBit = 6) then
                                    sFifoByte(7 downto 5) <= (others => '1');
                                elsif (serBit = 7) then
                                    sFifoByte(7 downto 6) <= (others => '1');
                                elsif (serBit = 8) then
                                    sFifoByte(7 downto 7) <= (others => '1');
                                end if;
                            elsif (sertfg = '0') then            -- falling edge
                                if    (serCycles > cycles_1m) and
                                      (serCycles < cycles_1p)     then
                                                             -- only got one bit
                                    if (serMax > 2) then
                                        serBit  <= serBit + 1;
                                        serMax  <= serMax - 2;
                                        serStep <= "10";

                                        sFifoByte(                 serBit-1) <= '1';
                                    else             -- the next bit cannot be 0
                                        serSync <= '0';
                                        serBit  <=  0;
                                        serMax  <=  9;
                                        serStep <= "00";
                                    end if;
                                elsif (serCycles > cycles_2m) and
                                      (serCycles < cycles_2p)     then
                                                                   -- got 2 bits
                                    if (serMax > 3) then
                                        serBit  <= serBit + 2;
                                        serMax  <= serMax - 3;
                                        serStep <= "10";

                                        sFifoByte(serBit   downto serBit-1) <= "11";
                                    else             -- the next bit cannot be 0
                                        serSync <= '0';
                                        serBit  <=  0;
                                        serMax  <=  9;
                                        serStep <= "00";
                                    end if;
                                elsif (serCycles > cycles_3m) and
                                      (serCycles < cycles_3p)     then
                                                                   -- got 3 bits
                                    if (serMax > 4) then
                                        serBit  <= serBit + 3;
                                        serMax  <= serMax - 4;
                                        serStep <= "10";

                                        sFifoByte(serBit+1 downto serBit-1) <= "111";
                                    else             -- the next bit cannot be 0
                                        serSync <= '0';
                                        serBit  <=  0;
                                        serMax  <=  9;
                                        serStep <= "00";
                                    end if;
                                elsif (serCycles > cycles_4m) and
                                      (serCycles < cycles_4p)     then
                                                                   -- got 4 bits
                                    if (serMax > 5) then
                                        serBit  <= serBit + 4;
                                        serMax  <= serMax - 5;
                                        serStep <= "10";

                                        sFifoByte(serBit+2 downto serBit-1) <= "1111";
                                    else             -- the next bit cannot be 0
                                        serSync <= '0';
                                        serBit  <=  0;
                                        serMax  <=  9;
                                        serStep <= "00";
                                    end if;
                                elsif (serCycles > cycles_5m) and
                                      (serCycles < cycles_5p)     then
                                                                   -- got 5 bits
                                    if (serMax > 6) then
                                        serBit  <= serBit + 5;
                                        serMax  <= serMax - 6;
                                        serStep <= "10";

                                        sFifoByte(serBit+3 downto serBit-1) <= "11111";
                                    else             -- the next bit cannot be 0
                                        serSync <= '0';
                                        serBit  <=  0;
                                        serMax  <=  9;
                                        serStep <= "00";
                                    end if;
                                elsif (serCycles > cycles_6m) and
                                      (serCycles < cycles_6p)     then
                                                                   -- got 6 bits
                                    if (serMax > 7) then
                                        serBit  <= serBit + 6;
                                        serMax  <= serMax - 7;
                                        serStep <= "10";

                                        sFifoByte(serBit+4 downto serBit-1) <= "111111";
                                    else             -- the next bit cannot be 0
                                        serSync <= '0';
                                        serBit  <=  0;
                                        serMax  <=  9;
                                        serStep <= "00";
                                    end if;
                                elsif (serCycles > cycles_7m) and
                                      (serCycles < cycles_7p)     then
                                                                   -- got 7 bits
                                    if (serMax > 8) then
                                        serBit  <= serBit + 7;
                                        serMax  <= serMax - 8;
                                        serStep <= "10";

                                        sFifoByte(serBit+5 downto serBit-1) <= "1111111";
                                    else             -- the next bit cannot be 0
                                        serSync <= '0';
                                        serBit  <=  0;
                                        serMax  <=  9;
                                        serStep <= "00";
                                    end if;
                                else                                  -- problem
                                    serSync <= '0';
                                    serBit  <=  0;
                                    serMax  <=  9;
                                    serStep <= "00";
                                end if;

                                serCycles   <= (others => '0');

                                sFifoWrEn  <= '0';
                            else
                                serCycles   <= serCycles + serBaud;

                                sFifoWrEn  <= '0';
                            end if;
                        when others =>                                  -- never
                            sFifoWrEn <= '0';
                    end case;
                end if;
            end if;
        end if;
    end process;


    process( rxClk )
    begin
        if (rxClk'event and rxClk = '1') then
            if (serDelay > 19) then
                serDelay <= 0;
                serClk   <= not serClk;
            else
                serDelay <= serDelay + 1;
            end if;
        end if;
    end process;

end RTL;

