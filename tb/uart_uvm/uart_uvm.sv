`timescale 1ns/1ps

// Pin-level contract between the class-based testbench and the RTL.
interface uart_if;
    logic        clk = 1'b0;
    logic        rst = 1'b0;
    logic        tx_start = 1'b0;
    logic        rx_start = 1'b0;
    logic [7:0]  tx_data = 8'h00;
    logic [16:0] baud = 17'd9600;
    logic [3:0]  length = 4'd8;
    logic        parity_type = 1'b0; // 0: even, 1: odd
    logic        parity_en = 1'b0;
    logic        stop2 = 1'b0;
    logic        tx_done;
    logic        rx_done;
    logic        tx_err;
    logic        rx_err;
    logic [7:0]  rx_out;

    // Observation-only probes used for independent serial-frame checking.
    wire tx_clk;
    wire rx_clk;
    wire serial_tx;
    wire serial_rx;
endinterface

package uart_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef enum bit {UART_RESET, UART_TRANSFER} uart_item_kind_e;

    // Environment policy is configurable so the agent remains reusable.
    class uart_env_config extends uvm_object;
        `uvm_object_utils(uart_env_config)
        uvm_active_passive_enum is_active = UVM_ACTIVE;

        function new(string name = "uart_env_config");
            super.new(name);
        endfunction
    endclass

    // No field is rand: Questa Starter cannot license constrained randomization.
    class uart_item extends uvm_sequence_item;
        `uvm_object_utils(uart_item)

        uart_item_kind_e kind = UART_TRANSFER;
        bit [7:0]        tx_data;
        bit [16:0]       baud;
        bit [3:0]        length;
        bit              parity_type;
        bit              parity_en;
        bit              stop2;
        int unsigned     reset_cycles;

        // Results populated only by the monitor.
        bit [7:0]        serial_data;
        bit [7:0]        rx_data;
        bit              observed_parity;
        bit              start_bit_ok;
        bit              stop_bits_ok;
        bit              tx_done_seen;
        bit              tx_error_seen;
        bit              rx_error_seen;
        bit              completed;
        bit              aborted;

        function new(string name = "uart_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf(
                "kind=%s baud=%0d length=%0d parity_en=%0b parity_type=%0b stop2=%0b tx=0x%02h serial=0x%02h rx=0x%02h",
                kind.name(), baud, length, parity_en, parity_type, stop2,
                tx_data, serial_data, rx_data);
        endfunction
    endclass

    // Scenario sequences share transaction-construction helpers through this base.
    class uart_base_sequence extends uvm_sequence #(uart_item);
        `uvm_object_utils(uart_base_sequence)
        protected bit [15:0] lfsr = 16'h1ACE;

        function new(string name = "uart_base_sequence");
            super.new(name);
        endfunction

        // Deterministic pseudo-random data is reproducible and needs no randomize().
        function bit [7:0] next_data();
            bit feedback;
            feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
            lfsr = {lfsr[14:0], feedback};
            return lfsr[7:0];
        endfunction

        task send_reset(int unsigned cycles = 8);
            uart_item req = uart_item::type_id::create("reset_req");
            start_item(req);
            req.kind = UART_RESET;
            req.reset_cycles = cycles;
            finish_item(req);
        endtask

        task send_frame(bit [7:0] data, bit [16:0] selected_baud,
                        bit [3:0] selected_length, bit parity_enabled,
                        bit odd_parity, bit two_stop_bits);
            uart_item req = uart_item::type_id::create("frame_req");
            start_item(req);
            req.kind = UART_TRANSFER;
            req.tx_data = data;
            req.baud = selected_baud;
            req.length = selected_length;
            req.parity_en = parity_enabled;
            req.parity_type = odd_parity;
            req.stop2 = two_stop_bits;
            finish_item(req);
        endtask

        virtual task body();
            `uvm_fatal("SEQ", "uart_base_sequence must not be started directly")
        endtask
    endclass

    class uart_boot_reset_sequence extends uart_base_sequence;
        `uvm_object_utils(uart_boot_reset_sequence)
        function new(string name = "uart_boot_reset_sequence"); 
            super.new(name); 
        endfunction
        virtual task body(); 
            send_reset(8); 
        endtask
    endclass

    // Stuck-at, bit-order, masking, parity, and stop-bit data corners.
    class uart_data_corner_sequence extends uart_base_sequence;
        `uvm_object_utils(uart_data_corner_sequence)
        function new(string name = "uart_data_corner_sequence"); 
            super.new(name); 
        endfunction

        virtual task body();
            send_frame(8'h00, 17'd9600, 4'd8, 1'b0, 1'b0, 1'b0);
            send_frame(8'hFF, 17'd9600, 4'd8, 1'b1, 1'b0, 1'b0);
            send_frame(8'hAA, 17'd9600, 4'd8, 1'b1, 1'b1, 1'b1);
            send_frame(8'h55, 17'd9600, 4'd8, 1'b0, 1'b0, 1'b1);
        endtask
    endclass

    // All divider settings plus the unsupported-baud fallback to 9600.
    class uart_baud_sweep_sequence extends uart_base_sequence;
        `uvm_object_utils(uart_baud_sweep_sequence)
        function new(string name = "uart_baud_sweep_sequence"); 
            super.new(name); 
        endfunction

        virtual task body();
            bit [16:0] rates[9] = '{17'd4800, 17'd9600, 17'd14400,
                                    17'd19200, 17'd38400, 17'd57600,
                                    17'd115200, 17'd128000, 17'd12345};
            foreach (rates[i])
                send_frame(next_data(), rates[i], 4'd8, i[0], i[1], i[0]);
        endtask
    endclass

    // Exhaustive legal format cross at a fast baud keeps runtime practical.
    class uart_format_sweep_sequence extends uart_base_sequence;
        `uvm_object_utils(uart_format_sweep_sequence)
        function new(string name = "uart_format_sweep_sequence"); super.new(name); endfunction

        virtual task body();
            for (int unsigned len = 5; len <= 8; len++)
                for (int unsigned parity_mode = 0; parity_mode < 3; parity_mode++)
                    for (int unsigned stops = 0; stops < 2; stops++)
                        send_frame(next_data(), 17'd128000, len[3:0],
                                   parity_mode != 0, parity_mode == 2, stops[0]);
        endtask
    endclass

    class uart_reset_recovery_sequence extends uart_base_sequence;
        `uvm_object_utils(uart_reset_recovery_sequence)
        function new(string name = "uart_reset_recovery_sequence"); 
            super.new(name); 
        endfunction

        virtual task body();
            send_reset(8);
            send_frame(8'h3C, 17'd115200, 4'd7, 1'b1, 1'b1, 1'b1);
        endtask
    endclass

    // A regression composes focused scenarios; each scenario remains reusable.
    class uart_regression_sequence extends uvm_sequence #(uart_item);
        `uvm_object_utils(uart_regression_sequence)
        function new(string name = "uart_regression_sequence"); 
            super.new(name); 
        endfunction

        virtual task body();
            uart_boot_reset_sequence boot;
            uart_data_corner_sequence data_corners;
            uart_baud_sweep_sequence baud_sweep;
            uart_format_sweep_sequence format_sweep;
            uart_reset_recovery_sequence reset_recovery;

            boot = uart_boot_reset_sequence::type_id::create("boot");
            data_corners = uart_data_corner_sequence::type_id::create("data_corners");
            baud_sweep = uart_baud_sweep_sequence::type_id::create("baud_sweep");
            format_sweep = uart_format_sweep_sequence::type_id::create("format_sweep");
            reset_recovery = uart_reset_recovery_sequence::type_id::create("reset_recovery");
            boot.start(m_sequencer, this);
            data_corners.start(m_sequencer, this);
            baud_sweep.start(m_sequencer, this);
            format_sweep.start(m_sequencer, this);
            reset_recovery.start(m_sequencer, this);
        endtask
    endclass

    class uart_driver extends uvm_driver #(uart_item);
        `uvm_component_utils(uart_driver)
        virtual uart_if vif;

        function new(string name = "uart_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV/NOVIF", "uart_if was not configured")
        endfunction

        function int unsigned tx_period_cycles(bit [16:0] selected_baud);
            case (selected_baud)
                17'd4800: return 10416; 17'd9600: return 5208;
                17'd14400: return 3472; 17'd19200: return 2604;
                17'd38400: return 1302; 17'd57600: return 868;
                17'd115200: return 434; 17'd128000: return 392;
                default: return 5208;
            endcase
        endfunction

        task drive_reset(uart_item req);
            @(negedge vif.clk);
            vif.tx_start <= 1'b0;
            vif.rx_start <= 1'b0;
            vif.rst <= 1'b1;
            repeat (req.reset_cycles) @(posedge vif.clk);
            @(negedge vif.clk);
            vif.rst <= 1'b0;
            `uvm_info("DRV", $sformatf("Applied reset for %0d cycles",
                      req.reset_cycles), UVM_MEDIUM)
        endtask

        task drive_transfer(uart_item req);
            int unsigned timeout_cycles = 16 * tx_period_cycles(req.baud) + 1024;
            bit tx_complete = 1'b0;
            bit rx_complete = 1'b0;

            @(negedge vif.clk);
            vif.rst <= 1'b0;
            vif.tx_data <= req.tx_data;
            vif.baud <= req.baud;
            vif.length <= req.length;
            vif.parity_type <= req.parity_type;
            vif.parity_en <= req.parity_en;
            vif.stop2 <= req.stop2;
            vif.tx_start <= 1'b1;
            vif.rx_start <= 1'b1;

            // A bounded handshake prevents a broken DUT from hanging regression.
            for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
                @(posedge vif.clk);
                if (vif.tx_done) begin tx_complete = 1'b1; vif.tx_start <= 1'b0; end
                if (vif.rx_done) begin rx_complete = 1'b1; vif.rx_start <= 1'b0; end
                if (tx_complete && rx_complete) break;
            end
            if (!tx_complete || !rx_complete)
                `uvm_error("DRV/TIMEOUT", $sformatf(
                    "Transfer timed out (tx_done=%0b rx_done=%0b): %s",
                    tx_complete, rx_complete, req.convert2string()))

            // Do not release the item while either completion pulse is still
            // asserted.  Otherwise the next request can be mistaken for an
            // immediate completion and overwrite an active frame's controls.
            while (vif.tx_done || vif.rx_done)
                @(posedge vif.clk);
            @(negedge vif.clk);
            vif.tx_start <= 1'b0;
            vif.rx_start <= 1'b0;
            `uvm_info("DRV", {"Completed stimulus: ", req.convert2string()}, UVM_MEDIUM)
        endtask

        virtual task run_phase(uvm_phase phase);
            uart_item req;
            vif.rst <= 1'b0;
            vif.tx_start <= 1'b0;
            vif.rx_start <= 1'b0;
            forever begin
                seq_item_port.get_next_item(req);
                if (req.kind == UART_RESET) drive_reset(req);
                else drive_transfer(req);
                seq_item_port.item_done();
            end
        endtask
    endclass

    class uart_monitor extends uvm_monitor;
        `uvm_component_utils(uart_monitor)
        virtual uart_if vif;
        uvm_analysis_port #(uart_item) observed_ap;

        function new(string name = "uart_monitor", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            observed_ap = new("observed_ap", this);
            if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON/NOVIF", "uart_if was not configured")
        endfunction

        task monitor_resets();
            uart_item item;
            forever begin
                @(posedge vif.rst);
                item = uart_item::type_id::create("observed_reset");
                item.kind = UART_RESET;
                observed_ap.write(item);
            end
        endtask

        task monitor_transfers();
            uart_item item;
            forever begin
                // Allocate per observation: subscribers may retain object handles.
                @(posedge vif.tx_start);
                item = uart_item::type_id::create("observed_transfer");
                item.kind = UART_TRANSFER;
                item.tx_data = vif.tx_data;
                item.baud = vif.baud;
                item.length = vif.length;
                item.parity_type = vif.parity_type;
                item.parity_en = vif.parity_en;
                item.stop2 = vif.stop2;
                item.start_bit_ok = 1'b1;
                item.stop_bits_ok = 1'b1;

                // Observe tx_done concurrently because it can pulse before the
                // receiver finishes the final oversampling interval.
                fork : tx_done_observer
                    begin
                        @(posedge vif.tx_done);
                        item.tx_done_seen = 1'b1;
                    end
                join_none

                // Start-edge synchronization followed by mid-bit TX sampling.
                @(negedge vif.serial_tx);
                @(negedge vif.tx_clk);
                item.start_bit_ok = (vif.serial_tx === 1'b0);
                for (int unsigned bit_index = 0; bit_index < item.length; bit_index++) begin
                    @(negedge vif.tx_clk);
                    item.serial_data[bit_index] = vif.serial_tx;
                    item.tx_error_seen |= vif.tx_err;
                    item.rx_error_seen |= vif.rx_err;
                end
                if (item.parity_en) begin
                    @(negedge vif.tx_clk);
                    item.observed_parity = vif.serial_tx;
                end
                @(negedge vif.tx_clk);
                item.stop_bits_ok &= (vif.serial_tx === 1'b1);
                if (item.stop2) begin
                    @(negedge vif.tx_clk);
                    item.stop_bits_ok &= (vif.serial_tx === 1'b1);
                end

                // rx_done follows the serialized frame; sample it with a timeout.
                for (int unsigned cycle = 0; cycle < 22000; cycle++) begin
                    @(posedge vif.clk);
                    item.tx_error_seen |= vif.tx_err;
                    item.rx_error_seen |= vif.rx_err;
                    if (vif.rst) begin item.aborted = 1'b1; break; end
                    if (vif.rx_done) begin item.completed = 1'b1; break; end
                end

                // Depending on divider phase, RX can complete slightly before
                // TX.  Preserve the observation until both protocol endpoints
                // have reported completion.
                if (!item.tx_done_seen && !item.aborted)
                    for (int unsigned cycle = 0; cycle < 22000; cycle++) begin
                        @(posedge vif.clk);
                        if (vif.tx_done) begin
                            item.tx_done_seen = 1'b1;
                            break;
                        end
                    end
                disable tx_done_observer;
                item.rx_data = vif.rx_out;
                observed_ap.write(item);
                `uvm_info("MON", {"Observed transfer: ", item.convert2string()}, UVM_HIGH)
            end
        endtask

        virtual task run_phase(uvm_phase phase);
            fork monitor_resets(); monitor_transfers(); join
        endtask
    endclass

    class uart_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(uart_scoreboard)
        uvm_analysis_imp #(uart_item, uart_scoreboard) observed_export;
        int unsigned checked_transfers;
        int unsigned reset_count;

        function new(string name = "uart_scoreboard", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            observed_export = new("observed_export", this);
            checked_transfers = 0;
            reset_count = 0;
        endfunction

        function bit [7:0] data_mask(bit [3:0] length);
            case (length)
                4'd5: return 8'h1F; 4'd6: return 8'h3F;
                4'd7: return 8'h7F; 4'd8: return 8'hFF;
                default: return 8'h00;
            endcase
        endfunction

        function bit expected_parity(uart_item item);
            bit data_xor = ^(item.tx_data & data_mask(item.length));
            return item.parity_type ? ~data_xor : data_xor;
        endfunction

        virtual function void write(uart_item item);
            bit [7:0] expected_data;
            if (item.kind == UART_RESET) begin reset_count++; return; end
            checked_transfers++;
            expected_data = item.tx_data & data_mask(item.length);

            if (!item.completed)
                `uvm_error("SCO/INCOMPLETE", {"Transfer did not complete: ", item.convert2string()})
            if (item.aborted)
                `uvm_error("SCO/ABORT", {"Unexpected aborted transfer: ", item.convert2string()})
            if (!item.tx_done_seen)
                `uvm_error("SCO/TXDONE", {"tx_done was not observed: ", item.convert2string()})
            if (!item.start_bit_ok || !item.stop_bits_ok)
                `uvm_error("SCO/FRAME", {"Invalid start or stop bit: ", item.convert2string()})
            if (item.serial_data !== expected_data)
                `uvm_error("SCO/SERIAL", $sformatf(
                    "Serial payload expected=0x%02h: %s", expected_data, item.convert2string()))
            if (item.rx_data !== expected_data)
                `uvm_error("SCO/RXDATA", $sformatf(
                    "Receiver payload expected=0x%02h: %s", expected_data, item.convert2string()))
            if (item.parity_en && item.observed_parity !== expected_parity(item))
                `uvm_error("SCO/PARITY", $sformatf(
                    "Parity expected=%0b observed=%0b: %s",
                    expected_parity(item), item.observed_parity, item.convert2string()))
            if (item.tx_error_seen || item.rx_error_seen)
                `uvm_error("SCO/DUTERR", {"Unexpected DUT error: ", item.convert2string()})
        endfunction

        virtual function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (checked_transfers != 38)
                `uvm_error("SCO/COUNT", $sformatf(
                    "Expected 38 transfers, checked %0d", checked_transfers))
            if (reset_count < 2)
                `uvm_error("SCO/RESET", $sformatf(
                    "Expected at least two resets, saw %0d", reset_count))
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("SCO/SUMMARY", $sformatf(
                "Checked %0d transfers and observed %0d resets",
                checked_transfers, reset_count), UVM_LOW)
        endfunction
    endclass

    // Counter-based coverage avoids covergroup licensing while enforcing closure.
    class uart_coverage extends uvm_subscriber #(uart_item);
        `uvm_component_utils(uart_coverage)
        int unsigned baud_hits[9];
        int unsigned length_hits[4];
        int unsigned parity_hits[3]; // disabled, even, odd
        int unsigned stop_hits[2];
        int unsigned format_hits[4][3][2];
        bit          coverage_closed;

        function new(string name = "uart_coverage", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function int unsigned baud_index(bit [16:0] baud);
            case (baud)
                17'd4800: return 0; 17'd9600: return 1; 17'd14400: return 2;
                17'd19200: return 3; 17'd38400: return 4; 17'd57600: return 5;
                17'd115200: return 6; 17'd128000: return 7; default: return 8;
            endcase
        endfunction

        virtual function void write(uart_item t);
            int unsigned parity_index;
            if (t.kind != UART_TRANSFER || !t.completed) return;
            baud_hits[baud_index(t.baud)]++;
            if (t.length >= 5 && t.length <= 8)
                length_hits[t.length - 5]++;
            parity_index = t.parity_en ? (t.parity_type ? 2 : 1) : 0;
            parity_hits[parity_index]++;
            stop_hits[t.stop2]++;
            if (t.length >= 5 && t.length <= 8)
                format_hits[t.length - 5][parity_index][t.stop2]++;
        endfunction

        virtual function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            coverage_closed = 1'b1;
            foreach (baud_hits[i]) if (baud_hits[i] == 0) begin
                coverage_closed = 1'b0;
                `uvm_error("COV/BAUD", $sformatf("No hit for baud bin %0d", i))
            end
            foreach (length_hits[i]) if (length_hits[i] == 0) begin
                coverage_closed = 1'b0;
                `uvm_error("COV/LENGTH", $sformatf("No hit for length %0d", i + 5))
            end
            foreach (parity_hits[i]) if (parity_hits[i] == 0) begin
                coverage_closed = 1'b0;
                `uvm_error("COV/PARITY", $sformatf("No hit for parity mode %0d", i))
            end
            foreach (stop_hits[i]) if (stop_hits[i] == 0) begin
                coverage_closed = 1'b0;
                `uvm_error("COV/STOP", $sformatf("No hit for stop mode %0d", i))
            end
            foreach (format_hits[length_i, parity_i, stop_i])
                if (format_hits[length_i][parity_i][stop_i] == 0) begin
                    coverage_closed = 1'b0;
                    `uvm_error("COV/FORMAT", $sformatf(
                        "No hit for length=%0d parity_mode=%0d stop2=%0d",
                        length_i + 5, parity_i, stop_i))
                end
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            if (coverage_closed)
                `uvm_info("COV/SUMMARY",
                          "Required baud and length x parity x stop bins were exercised",
                          UVM_LOW)
        endfunction
    endclass

    class uart_agent extends uvm_agent;
        `uvm_component_utils(uart_agent)
        uart_env_config cfg;
        uart_driver driver;
        uart_monitor monitor;
        uvm_sequencer #(uart_item) sequencer;

        function new(string name = "uart_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(uart_env_config)::get(this, "", "cfg", cfg))
                cfg = uart_env_config::type_id::create("cfg");
            is_active = cfg.is_active;
            monitor = uart_monitor::type_id::create("monitor", this);
            if (is_active == UVM_ACTIVE) begin
                driver = uart_driver::type_id::create("driver", this);
                sequencer = uvm_sequencer#(uart_item)::type_id::create("sequencer", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (is_active == UVM_ACTIVE)
                driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class uart_env extends uvm_env;
        `uvm_component_utils(uart_env)
        uart_agent agent;
        uart_scoreboard scoreboard;
        uart_coverage coverage;

        function new(string name = "uart_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = uart_agent::type_id::create("agent", this);
            scoreboard = uart_scoreboard::type_id::create("scoreboard", this);
            coverage = uart_coverage::type_id::create("coverage", this);
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.observed_ap.connect(scoreboard.observed_export);
            agent.monitor.observed_ap.connect(coverage.analysis_export);
        endfunction
    endclass

    class uart_test extends uvm_test;
        `uvm_component_utils(uart_test)
        uart_env_config cfg;
        uart_env env;

        function new(string name = "uart_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            cfg = uart_env_config::type_id::create("cfg");
            cfg.is_active = UVM_ACTIVE;
            uvm_config_db#(uart_env_config)::set(this, "env.agent", "cfg", cfg);
            env = uart_env::type_id::create("env", this);
        endfunction

        virtual task run_phase(uvm_phase phase);
            uart_regression_sequence regression_seq;
            phase.raise_objection(this, "UART regression is running");
            regression_seq = uart_regression_sequence::type_id::create("regression_seq");
            regression_seq.start(env.agent.sequencer);
            repeat (10) @(posedge env.agent.driver.vif.clk);
            phase.drop_objection(this, "UART regression completed");
        endtask
    endclass
endpackage

module uart_tb;
    import uvm_pkg::*;
    import uart_uvm_pkg::*;
    uart_if vif();

    uart_top dut (
        .clk(vif.clk), .rst(vif.rst), .tx_start(vif.tx_start),
        .rx_start(vif.rx_start), .tx_data(vif.tx_data), .baud(vif.baud),
        .length(vif.length), .parity_type(vif.parity_type),
        .parity_en(vif.parity_en), .stop2(vif.stop2),
        .rx(vif.serial_rx), .tx(vif.serial_tx),
        .tx_done(vif.tx_done), .rx_done(vif.rx_done),
        .tx_err(vif.tx_err), .rx_err(vif.rx_err), .rx_out(vif.rx_out)
    );

    assign vif.tx_clk = dut.tx_clk;
    assign vif.rx_clk = dut.rx_clk;
    // The DUT has conventional external UART pins. This testbench chooses
    // loopback; a future RX agent can drive serial_rx independently.
    assign vif.serial_rx = vif.serial_tx;
    always #10 vif.clk = ~vif.clk; // 50 MHz

    initial begin
        uvm_config_db#(virtual uart_if)::set(null, "*", "vif", vif);
        run_test("uart_test");
    end

    // Questa records WLF by default; request the larger VCD only when needed.
    initial if ($test$plusargs("DUMP_VCD")) begin
        $dumpfile("uart.vcd");
        $dumpvars(0, uart_tb);
    end
endmodule
