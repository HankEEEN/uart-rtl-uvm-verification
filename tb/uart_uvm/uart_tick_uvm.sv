`timescale 1ns/1ps

interface uart_tick_if;
    logic        clk = 1'b0;
    logic        rst = 1'b0;
    logic        tx_start = 1'b0;
    logic        rx_start = 1'b0;
    logic [7:0]  tx_data = 8'h00;
    logic [16:0] baud = 17'd9600;
    logic [3:0]  length = 4'd8;
    logic        parity_type = 1'b0;
    logic        parity_en = 1'b0;
    logic        stop2 = 1'b0;
    logic        expect_abort = 1'b0;
    logic        tx_done;
    logic        rx_done;
    logic        tx_err;
    logic        rx_err;
    logic [7:0]  rx_out;

    // Observation-only connections to the tick-based DUT.
    wire tx_tick;
    wire rx_tick;
    wire serial_tx;
    wire serial_rx;
    wire [2:0] tx_state;
    wire [2:0] rx_state;
    wire [2:0] tx_bit_index;
    wire [2:0] rx_bit_index;
    wire [3:0] rx_sample_count;
    wire [7:0] rx_data_reg;
endinterface

package uart_tick_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam int unsigned UART_TICK_CLK_HZ = 50_000_000;
    typedef enum bit {UART_TICK_RESET, UART_TICK_TRANSFER}
        uart_tick_item_kind_e;

    class uart_tick_env_config extends uvm_object;
        `uvm_object_utils(uart_tick_env_config)
        uvm_active_passive_enum is_active = UVM_ACTIVE;

        function new(string name = "uart_tick_env_config");
            super.new(name);
        endfunction
    endclass

    class uart_tick_item extends uvm_sequence_item;
        `uvm_object_utils(uart_tick_item)

        uart_tick_item_kind_e kind = UART_TICK_TRANSFER;
        bit [7:0]        tx_data;
        bit [16:0]       baud;
        bit [3:0]        length;
        bit              parity_type;
        bit              parity_en;
        bit              stop2;
        bit              expect_abort;
        int unsigned     reset_cycles;

        // Observation fields populated by the protocol monitor.
        bit [7:0]        serial_data;
        bit [7:0]        rx_data;
        bit              observed_parity;
        bit              start_bit_ok;
        bit              stop_bits_ok;
        bit              tx_done_seen;
        bit              rx_done_seen;
        bit              tx_error_seen;
        bit              rx_error_seen;
        bit              completed;
        bit              aborted;
        bit              timed_out;

        function new(string name = "uart_tick_item");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf(
                "kind=%s baud=%0d length=%0d parity_en=%0b parity_type=%0b stop2=%0b expect_abort=%0b tx=0x%02h serial=0x%02h rx=0x%02h",
                kind.name(), baud, length, parity_en, parity_type, stop2,
                expect_abort, tx_data, serial_data, rx_data);
        endfunction
    endclass

    class uart_tick_base_sequence extends uvm_sequence #(uart_tick_item);
        `uvm_object_utils(uart_tick_base_sequence)
        protected bit [15:0] lfsr = 16'h1ace;

        function new(string name = "uart_tick_base_sequence");
            super.new(name);
        endfunction

        function bit [7:0] next_data();
            bit feedback;
            feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
            lfsr = {lfsr[14:0], feedback};
            return lfsr[7:0];
        endfunction

        task send_reset(int unsigned cycles = 8);
            uart_tick_item req;
            req = uart_tick_item::type_id::create("reset_req");
            start_item(req);
            req.kind = UART_TICK_RESET;
            req.reset_cycles = cycles;
            finish_item(req);
        endtask

        task send_frame(bit [7:0] data, bit [16:0] selected_baud,
                        bit [3:0] selected_length, bit parity_enabled,
                        bit odd_parity, bit two_stop_bits);
            uart_tick_item req;
            req = uart_tick_item::type_id::create("frame_req");
            start_item(req);
            req.kind = UART_TICK_TRANSFER;
            req.tx_data = data;
            req.baud = selected_baud;
            req.length = selected_length;
            req.parity_en = parity_enabled;
            req.parity_type = odd_parity;
            req.stop2 = two_stop_bits;
            finish_item(req);
        endtask

        task send_aborted_frame(bit [7:0] data,
                                bit [16:0] selected_baud);
            uart_tick_item req;
            req = uart_tick_item::type_id::create("aborted_frame_req");
            start_item(req);
            req.kind = UART_TICK_TRANSFER;
            req.tx_data = data;
            req.baud = selected_baud;
            req.length = 4'd8;
            req.parity_en = 1'b1;
            req.parity_type = 1'b0;
            req.stop2 = 1'b0;
            req.expect_abort = 1'b1;
            finish_item(req);
        endtask

        virtual task body();
            `uvm_fatal("SEQ", "uart_tick_base_sequence must not run directly")
        endtask
    endclass

    class uart_tick_boot_reset_sequence extends uart_tick_base_sequence;
        `uvm_object_utils(uart_tick_boot_reset_sequence)
        function new(string name = "uart_tick_boot_reset_sequence");
            super.new(name);
        endfunction
        virtual task body();
            send_reset(8);
        endtask
    endclass

    class uart_tick_data_corner_sequence extends uart_tick_base_sequence;
        `uvm_object_utils(uart_tick_data_corner_sequence)
        function new(string name = "uart_tick_data_corner_sequence");
            super.new(name);
        endfunction
        virtual task body();
            send_frame(8'h00, 17'd9600, 4'd8, 1'b0, 1'b0, 1'b0);
            send_frame(8'hff, 17'd9600, 4'd8, 1'b1, 1'b0, 1'b0);
            send_frame(8'haa, 17'd9600, 4'd8, 1'b1, 1'b1, 1'b1);
            send_frame(8'h55, 17'd9600, 4'd8, 1'b0, 1'b0, 1'b1);
        endtask
    endclass

    class uart_tick_baud_sweep_sequence extends uart_tick_base_sequence;
        `uvm_object_utils(uart_tick_baud_sweep_sequence)
        function new(string name = "uart_tick_baud_sweep_sequence");
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

    // Exhaustive legal format cross: 4 lengths x 3 parity modes x 2 stops.
    class uart_tick_format_sweep_sequence extends uart_tick_base_sequence;
        `uvm_object_utils(uart_tick_format_sweep_sequence)
        function new(string name = "uart_tick_format_sweep_sequence");
            super.new(name);
        endfunction
        virtual task body();
            for (int unsigned len = 5; len <= 8; len++)
                for (int unsigned parity_mode = 0; parity_mode < 3;
                     parity_mode++)
                    for (int unsigned stops = 0; stops < 2; stops++)
                        send_frame(next_data(), 17'd128000, len[3:0],
                                   parity_mode != 0, parity_mode == 2,
                                   stops[0]);
        endtask
    endclass

    class uart_tick_reset_recovery_sequence extends uart_tick_base_sequence;
        `uvm_object_utils(uart_tick_reset_recovery_sequence)
        function new(string name = "uart_tick_reset_recovery_sequence");
            super.new(name);
        endfunction
        virtual task body();
            send_reset(8);
            send_frame(8'h3c, 17'd115200, 4'd7, 1'b1, 1'b1, 1'b1);
        endtask
    endclass

    class uart_tick_midframe_reset_sequence extends uart_tick_base_sequence;
        `uvm_object_utils(uart_tick_midframe_reset_sequence)
        function new(string name = "uart_tick_midframe_reset_sequence");
            super.new(name);
        endfunction
        virtual task body();
            send_aborted_frame(8'ha6, 17'd57600);
        endtask
    endclass

    class uart_tick_regression_sequence extends uvm_sequence #(uart_tick_item);
        `uvm_object_utils(uart_tick_regression_sequence)
        function new(string name = "uart_tick_regression_sequence");
            super.new(name);
        endfunction
        virtual task body();
            uart_tick_boot_reset_sequence boot;
            uart_tick_data_corner_sequence corners;
            uart_tick_baud_sweep_sequence baud_sweep;
            uart_tick_format_sweep_sequence format_sweep;
            uart_tick_midframe_reset_sequence midframe_reset;
            uart_tick_reset_recovery_sequence reset_recovery;

            boot = uart_tick_boot_reset_sequence::type_id::create("boot");
            corners = uart_tick_data_corner_sequence::type_id::create("corners");
            baud_sweep = uart_tick_baud_sweep_sequence::type_id::create(
                "baud_sweep");
            format_sweep = uart_tick_format_sweep_sequence::type_id::create(
                "format_sweep");
            midframe_reset = uart_tick_midframe_reset_sequence::type_id::create(
                "midframe_reset");
            reset_recovery = uart_tick_reset_recovery_sequence::type_id::create(
                "reset_recovery");

            boot.start(m_sequencer, this);
            corners.start(m_sequencer, this);
            baud_sweep.start(m_sequencer, this);
            format_sweep.start(m_sequencer, this);
            midframe_reset.start(m_sequencer, this);
            reset_recovery.start(m_sequencer, this);
        endtask
    endclass

    class uart_tick_driver extends uvm_driver #(uart_tick_item);
        `uvm_component_utils(uart_tick_driver)
        virtual uart_tick_if vif;

        function new(string name = "uart_tick_driver",
                     uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual uart_tick_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV/NOVIF", "uart_tick_if was not configured")
        endfunction

        function int unsigned effective_baud(bit [16:0] selected_baud);
            case (selected_baud)
                17'd4800, 17'd9600, 17'd14400, 17'd19200,
                17'd38400, 17'd57600, 17'd115200, 17'd128000:
                    return selected_baud;
                default: return 9600;
            endcase
        endfunction

        function int unsigned frame_timeout(bit [16:0] selected_baud);
            int unsigned rate = effective_baud(selected_baud);
            int unsigned longest_bit =
                (UART_TICK_CLK_HZ + rate - 1) / rate;
            return 16 * longest_bit + 4096;
        endfunction

        task drive_reset(uart_tick_item req);
            @(negedge vif.clk);
            vif.tx_start <= 1'b0;
            vif.rx_start <= 1'b0;
            vif.expect_abort <= 1'b0;
            vif.rst <= 1'b1;
            repeat (req.reset_cycles) @(posedge vif.clk);
            @(negedge vif.clk);
            vif.rst <= 1'b0;
            `uvm_info("DRV", $sformatf("Applied reset for %0d cycles",
                      req.reset_cycles), UVM_MEDIUM)
        endtask

        task drive_transfer(uart_tick_item req);
            int unsigned timeout_cycles = frame_timeout(req.baud);
            bit tx_complete = 1'b0;
            bit rx_complete = 1'b0;

            // Program the rate before requesting a frame. Three clocks let the
            // generator discard any registered tick from the previous rate and
            // install the new accumulator increment cleanly.
            @(negedge vif.clk);
            vif.rst <= 1'b0;
            vif.tx_start <= 1'b0;
            vif.rx_start <= 1'b0;
            vif.expect_abort <= 1'b0;
            vif.tx_data <= req.tx_data;
            vif.baud <= req.baud;
            vif.length <= req.length;
            vif.parity_type <= req.parity_type;
            vif.parity_en <= req.parity_en;
            vif.stop2 <= req.stop2;
            repeat (3) @(posedge vif.clk);

            @(negedge vif.clk);
            vif.tx_start <= 1'b1;
            vif.rx_start <= 1'b1;

            for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
                @(posedge vif.clk);
                if (vif.tx_done) begin
                    tx_complete = 1'b1;
                    vif.tx_start <= 1'b0;
                end
                if (vif.rx_done) begin
                    rx_complete = 1'b1;
                    vif.rx_start <= 1'b0;
                end
                if (tx_complete && rx_complete)
                    break;
            end

            if (!tx_complete || !rx_complete)
                `uvm_error("DRV/TIMEOUT", $sformatf(
                    "Transfer timed out (tx_done=%0b rx_done=%0b): %s",
                    tx_complete, rx_complete, req.convert2string()))

            @(negedge vif.clk);
            vif.tx_start <= 1'b0;
            vif.rx_start <= 1'b0;
            repeat (2) @(posedge vif.clk);
            `uvm_info("DRV", {"Completed stimulus: ", req.convert2string()},
                      UVM_MEDIUM)
        endtask

        task drive_aborted_transfer(uart_tick_item req);
            int unsigned timeout_cycles = frame_timeout(req.baud);
            bit start_seen = 1'b0;

            @(negedge vif.clk);
            vif.rst <= 1'b0;
            vif.tx_start <= 1'b0;
            vif.rx_start <= 1'b0;
            vif.expect_abort <= 1'b1;
            vif.tx_data <= req.tx_data;
            vif.baud <= req.baud;
            vif.length <= req.length;
            vif.parity_type <= req.parity_type;
            vif.parity_en <= req.parity_en;
            vif.stop2 <= req.stop2;
            repeat (3) @(posedge vif.clk);

            @(negedge vif.clk);
            vif.tx_start <= 1'b1;
            vif.rx_start <= 1'b1;

            for (int unsigned cycle = 0; cycle < timeout_cycles; cycle++) begin
                @(posedge vif.clk);
                if (vif.serial_tx === 1'b0) begin
                    start_seen = 1'b1;
                    break;
                end
            end
            if (!start_seen)
                `uvm_error("DRV/ABORTSTART",
                           "Timed out waiting for the frame to start")

            // Allow three more bit enables, then reset in the active frame.
            repeat (3) begin
                do @(posedge vif.clk); while (!vif.tx_tick);
            end
            @(negedge vif.clk);
            vif.rst <= 1'b1;
            vif.tx_start <= 1'b0;
            vif.rx_start <= 1'b0;
            repeat (4) @(posedge vif.clk);
            @(negedge vif.clk);
            vif.rst <= 1'b0;
            vif.expect_abort <= 1'b0;
            repeat (3) @(posedge vif.clk);
            `uvm_info("DRV", {"Aborted active frame with reset: ",
                      req.convert2string()}, UVM_MEDIUM)
        endtask

        virtual task run_phase(uvm_phase phase);
            uart_tick_item req;
            vif.rst <= 1'b0;
            vif.tx_start <= 1'b0;
            vif.rx_start <= 1'b0;
            vif.expect_abort <= 1'b0;
            forever begin
                seq_item_port.get_next_item(req);
                if (req.kind == UART_TICK_RESET)
                    drive_reset(req);
                else if (req.expect_abort)
                    drive_aborted_transfer(req);
                else
                    drive_transfer(req);
                seq_item_port.item_done();
            end
        endtask
    endclass

    class uart_tick_monitor extends uvm_monitor;
        `uvm_component_utils(uart_tick_monitor)
        virtual uart_tick_if vif;
        uvm_analysis_port #(uart_tick_item) observed_ap;

        function new(string name = "uart_tick_monitor",
                     uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            observed_ap = new("observed_ap", this);
            if (!uvm_config_db#(virtual uart_tick_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON/NOVIF", "uart_tick_if was not configured")
        endfunction

        function int unsigned effective_baud(bit [16:0] selected_baud);
            case (selected_baud)
                17'd4800, 17'd9600, 17'd14400, 17'd19200,
                17'd38400, 17'd57600, 17'd115200, 17'd128000:
                    return selected_baud;
                default: return 9600;
            endcase
        endfunction

        function int unsigned frame_timeout(bit [16:0] selected_baud);
            int unsigned rate = effective_baud(selected_baud);
            int unsigned longest_bit =
                (UART_TICK_CLK_HZ + rate - 1) / rate;
            return 16 * longest_bit + 4096;
        endfunction

        function void sample_status(uart_tick_item item);
            item.tx_done_seen |= vif.tx_done;
            item.rx_done_seen |= vif.rx_done;
            item.tx_error_seen |= vif.tx_err;
            item.rx_error_seen |= vif.rx_err;
            if (vif.rx_done) begin
                item.completed = 1'b1;
                item.rx_data = vif.rx_out;
            end
        endfunction

        task wait_for_start(uart_tick_item item, ref int budget,
                            output bit success);
            success = 1'b0;
            while (budget > 0 && !success && !item.aborted) begin
                @(posedge vif.clk);
                budget--;
                sample_status(item);
                if (vif.rst)
                    item.aborted = 1'b1;
                else if (vif.serial_tx === 1'b0)
                    success = 1'b1;
            end
        endtask

        task wait_rx_ticks(int unsigned wanted, uart_tick_item item,
                           ref int budget, output bit success);
            int unsigned seen = 0;
            success = 1'b0;
            while (budget > 0 && seen < wanted && !item.aborted) begin
                @(posedge vif.clk);
                budget--;
                sample_status(item);
                if (vif.rst)
                    item.aborted = 1'b1;
                else if (vif.rx_tick)
                    seen++;
            end
            success = (seen == wanted) && !item.aborted;
        endtask

        task monitor_resets();
            uart_tick_item item;
            forever begin
                @(posedge vif.rst);
                item = uart_tick_item::type_id::create("observed_reset");
                item.kind = UART_TICK_RESET;
                observed_ap.write(item);
            end
        endtask

        task monitor_transfers();
            uart_tick_item item;
            int budget;
            bit success;

            forever begin
                @(posedge vif.tx_start);
                item = uart_tick_item::type_id::create("observed_transfer");
                item.kind = UART_TICK_TRANSFER;
                item.tx_data = vif.tx_data;
                item.baud = vif.baud;
                item.length = vif.length;
                item.parity_type = vif.parity_type;
                item.parity_en = vif.parity_en;
                item.stop2 = vif.stop2;
                item.expect_abort = vif.expect_abort;
                item.start_bit_ok = 1'b1;
                item.stop_bits_ok = 1'b1;
                budget = frame_timeout(item.baud);

                wait_for_start(item, budget, success);
                if (!success && !item.aborted)
                    item.timed_out = 1'b1;

                // Detect the start edge, then sample at its midpoint. Every
                // following field is sampled sixteen RX enables later.
                if (!item.timed_out && !item.aborted) begin
                    wait_rx_ticks(8, item, budget, success);
                    if (!success)
                        item.timed_out = !item.aborted;
                    else
                        item.start_bit_ok = (vif.serial_tx === 1'b0);
                end

                for (int unsigned bit_index = 0;
                     bit_index < item.length && !item.timed_out && !item.aborted;
                     bit_index++) begin
                    wait_rx_ticks(16, item, budget, success);
                    if (!success)
                        item.timed_out = !item.aborted;
                    else
                        item.serial_data[bit_index] = vif.serial_tx;
                end

                if (item.parity_en && !item.timed_out && !item.aborted) begin
                    wait_rx_ticks(16, item, budget, success);
                    if (!success)
                        item.timed_out = !item.aborted;
                    else
                        item.observed_parity = vif.serial_tx;
                end

                if (!item.timed_out && !item.aborted) begin
                    wait_rx_ticks(16, item, budget, success);
                    if (!success)
                        item.timed_out = !item.aborted;
                    else
                        item.stop_bits_ok &= (vif.serial_tx === 1'b1);
                end

                if (item.stop2 && !item.timed_out && !item.aborted) begin
                    wait_rx_ticks(16, item, budget, success);
                    if (!success)
                        item.timed_out = !item.aborted;
                    else
                        item.stop_bits_ok &= (vif.serial_tx === 1'b1);
                end

                while (budget > 0 &&
                       !(item.tx_done_seen && item.rx_done_seen) &&
                       !item.aborted) begin
                    @(posedge vif.clk);
                    budget--;
                    sample_status(item);
                    if (vif.rst)
                        item.aborted = 1'b1;
                end

                if (!(item.tx_done_seen && item.rx_done_seen) && !item.aborted)
                    item.timed_out = 1'b1;
                item.rx_data = vif.rx_out;
                observed_ap.write(item);
                `uvm_info("MON", {"Observed transfer: ", item.convert2string()},
                          UVM_HIGH)
            end
        endtask

        virtual task run_phase(uvm_phase phase);
            fork
                monitor_resets();
                monitor_transfers();
            join
        endtask
    endclass

    // Independent tick/protocol checker. It does not reproduce the fractional
    // accumulator; the dedicated clk_gen UVM owns that exact timing model.
    class uart_tick_protocol_checker extends uvm_component;
        `uvm_component_utils(uart_tick_protocol_checker)
        virtual uart_tick_if vif;
        int unsigned rx_ticks_since_tx;
        int unsigned total_rx_ticks;
        int unsigned total_tx_ticks;
        int unsigned ratio_checks;

        function new(string name = "uart_tick_protocol_checker",
                     uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual uart_tick_if)::get(this, "", "vif", vif))
                `uvm_fatal("CHK/NOVIF", "uart_tick_if was not configured")
            rx_ticks_since_tx = 0;
            total_rx_ticks = 0;
            total_tx_ticks = 0;
            ratio_checks = 0;
        endfunction

        function int unsigned increment_for(bit [16:0] selected_baud);
            case (selected_baud)
                17'd4800: return 76_800; 17'd9600: return 153_600;
                17'd14400: return 230_400; 17'd19200: return 307_200;
                17'd38400: return 614_400; 17'd57600: return 921_600;
                17'd115200: return 1_843_200; 17'd128000: return 2_048_000;
                default: return 153_600;
            endcase
        endfunction

        virtual task run_phase(uvm_phase phase);
            int unsigned active_increment = 0;
            bit tracking = 1'b0;
            bit previous_rx_tick = 1'b0;
            bit previous_tx_tick = 1'b0;
            bit previous_tx_done = 1'b0;
            bit previous_rx_done = 1'b0;
            logic serial_before;
            bit tx_enable_at_edge;
            bit rx_enable_at_edge;
            logic [2:0] tx_state_before;
            logic [2:0] rx_state_before;
            logic [2:0] tx_bit_index_before;
            logic [2:0] rx_bit_index_before;
            logic [3:0] rx_sample_count_before;
            logic [7:0] rx_data_reg_before;

            forever begin
                @(posedge vif.clk);
                serial_before = vif.serial_tx;
                tx_enable_at_edge = vif.tx_tick;
                rx_enable_at_edge = vif.rx_tick;
                tx_state_before = vif.tx_state;
                rx_state_before = vif.rx_state;
                tx_bit_index_before = vif.tx_bit_index;
                rx_bit_index_before = vif.rx_bit_index;
                rx_sample_count_before = vif.rx_sample_count;
                rx_data_reg_before = vif.rx_data_reg;

                if (vif.rst) begin
                    tracking = 1'b0;
                    rx_ticks_since_tx = 0;
                    previous_rx_tick = 1'b0;
                    previous_tx_tick = 1'b0;
                end else begin
                    if (previous_rx_tick && vif.rx_tick)
                        `uvm_error("CHK/RXPULSE",
                                   "rx_tick remained asserted for multiple clocks")
                    if (previous_tx_tick && vif.tx_tick)
                        `uvm_error("CHK/TXPULSE",
                                   "tx_tick remained asserted for multiple clocks")
                    if (vif.tx_tick && !vif.rx_tick)
                        `uvm_error("CHK/COINCIDE",
                                   "tx_tick was not accompanied by rx_tick")

                    if (!tracking ||
                        active_increment != increment_for(vif.baud)) begin
                        active_increment = increment_for(vif.baud);
                        rx_ticks_since_tx = 0;
                        tracking = 1'b1;
                    end else begin
                        if (vif.rx_tick) begin
                            rx_ticks_since_tx++;
                            total_rx_ticks++;
                        end
                        if (vif.tx_tick) begin
                            total_tx_ticks++;
                            ratio_checks++;
                            if (rx_ticks_since_tx != 16)
                                `uvm_error("CHK/RATIO", $sformatf(
                                    "tx_tick followed %0d rx_ticks, expected 16",
                                    rx_ticks_since_tx))
                            rx_ticks_since_tx = 0;
                        end
                    end
                    previous_rx_tick = vif.rx_tick;
                    previous_tx_tick = vif.tx_tick;
                end

                @(negedge vif.clk);
                if (!vif.rst && vif.serial_tx !== serial_before &&
                    !tx_enable_at_edge)
                    `uvm_error("CHK/TXENABLE",
                               "Serial TX changed without tx_tick at clk edge")
                if (!vif.rst && !tx_enable_at_edge &&
                    (vif.tx_state !== tx_state_before ||
                     vif.tx_bit_index !== tx_bit_index_before))
                    `uvm_error("CHK/TXSTATE",
                               "TX state advanced without tx_tick")
                if (!vif.rst && !rx_enable_at_edge &&
                    (vif.rx_state !== rx_state_before ||
                     vif.rx_bit_index !== rx_bit_index_before ||
                     vif.rx_sample_count !== rx_sample_count_before ||
                     vif.rx_data_reg !== rx_data_reg_before))
                    `uvm_error("CHK/RXSTATE",
                               "RX state or datapath advanced without rx_tick")
                if (previous_tx_done && vif.tx_done)
                    `uvm_error("CHK/TXDONEWIDTH",
                               "tx_done exceeded one system-clock cycle")
                if (previous_rx_done && vif.rx_done)
                    `uvm_error("CHK/RXDONEWIDTH",
                               "rx_done exceeded one system-clock cycle")
                previous_tx_done = vif.tx_done;
                previous_rx_done = vif.rx_done;
            end
        endtask

        virtual function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (ratio_checks < 38)
                `uvm_error("CHK/RATIOCOV", $sformatf(
                    "Expected at least 38 checked TX ticks, saw %0d", ratio_checks))
            if (total_rx_ticks == 0 || total_tx_ticks == 0)
                `uvm_error("CHK/TICKCOV", "No tick activity was observed")
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("CHK/SUMMARY", $sformatf(
                "Observed %0d RX ticks, %0d TX ticks, and %0d ratio checks",
                total_rx_ticks, total_tx_ticks, ratio_checks), UVM_LOW)
        endfunction
    endclass

    class uart_tick_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(uart_tick_scoreboard)
        uvm_analysis_imp #(uart_tick_item, uart_tick_scoreboard) observed_export;
        int unsigned checked_transfers;
        int unsigned reset_count;
        int unsigned aborted_transfers;

        function new(string name = "uart_tick_scoreboard",
                     uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            observed_export = new("observed_export", this);
            checked_transfers = 0;
            reset_count = 0;
            aborted_transfers = 0;
        endfunction

        function bit [7:0] data_mask(bit [3:0] word_length);
            case (word_length)
                4'd5: return 8'h1f;
                4'd6: return 8'h3f;
                4'd7: return 8'h7f;
                4'd8: return 8'hff;
                default: return 8'h00;
            endcase
        endfunction

        function bit expected_parity(uart_tick_item item);
            bit data_xor = ^(item.tx_data & data_mask(item.length));
            return item.parity_type ? ~data_xor : data_xor;
        endfunction

        virtual function void write(uart_tick_item item);
            bit [7:0] expected_data;
            if (item.kind == UART_TICK_RESET) begin
                reset_count++;
                return;
            end

            if (item.expect_abort) begin
                aborted_transfers++;
                if (!item.aborted)
                    `uvm_error("SCO/NOABORT", {"Expected reset abort: ",
                               item.convert2string()})
                if (item.completed || item.tx_done_seen || item.rx_done_seen)
                    `uvm_error("SCO/ABORTDONE", {"Aborted frame completed: ",
                               item.convert2string()})
                return;
            end

            checked_transfers++;
            expected_data = item.tx_data & data_mask(item.length);

            if (item.timed_out)
                `uvm_error("SCO/TIMEOUT", {"Monitor timed out: ",
                           item.convert2string()})
            if (!item.completed || !item.rx_done_seen)
                `uvm_error("SCO/INCOMPLETE", {"RX did not complete: ",
                           item.convert2string()})
            if (item.aborted)
                `uvm_error("SCO/ABORT", {"Unexpected abort: ",
                           item.convert2string()})
            if (!item.tx_done_seen)
                `uvm_error("SCO/TXDONE", {"tx_done was not observed: ",
                           item.convert2string()})
            if (!item.start_bit_ok || !item.stop_bits_ok)
                `uvm_error("SCO/FRAME", {"Invalid start or stop bit: ",
                           item.convert2string()})
            if (item.serial_data !== expected_data)
                `uvm_error("SCO/SERIAL", $sformatf(
                    "Expected serial data 0x%02h: %s", expected_data,
                    item.convert2string()))
            if (item.rx_data !== expected_data)
                `uvm_error("SCO/RXDATA", $sformatf(
                    "Expected RX data 0x%02h: %s", expected_data,
                    item.convert2string()))
            if (item.parity_en &&
                item.observed_parity !== expected_parity(item))
                `uvm_error("SCO/PARITY", $sformatf(
                    "Expected parity=%0b observed=%0b: %s",
                    expected_parity(item), item.observed_parity,
                    item.convert2string()))
            if (item.tx_error_seen || item.rx_error_seen)
                `uvm_error("SCO/DUTERR", {"Unexpected DUT error: ",
                           item.convert2string()})
        endfunction

        virtual function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (checked_transfers != 38)
                `uvm_error("SCO/COUNT", $sformatf(
                    "Expected 38 transfers, checked %0d", checked_transfers))
            if (reset_count < 2)
                `uvm_error("SCO/RESET", $sformatf(
                    "Expected at least two resets, saw %0d", reset_count))
            if (aborted_transfers != 1)
                `uvm_error("SCO/ABORTCOUNT", $sformatf(
                    "Expected one mid-frame abort, saw %0d", aborted_transfers))
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("SCO/SUMMARY", $sformatf(
                "Checked %0d transfers, %0d mid-frame abort, and %0d resets",
                checked_transfers, aborted_transfers, reset_count), UVM_LOW)
        endfunction
    endclass

    class uart_tick_coverage extends uvm_subscriber #(uart_tick_item);
        `uvm_component_utils(uart_tick_coverage)
        int unsigned baud_hits[9];
        int unsigned length_hits[4];
        int unsigned parity_hits[3];
        int unsigned stop_hits[2];
        int unsigned format_hits[4][3][2];
        bit coverage_closed;

        function new(string name = "uart_tick_coverage",
                     uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function int unsigned baud_index(bit [16:0] selected_baud);
            case (selected_baud)
                17'd4800: return 0; 17'd9600: return 1;
                17'd14400: return 2; 17'd19200: return 3;
                17'd38400: return 4; 17'd57600: return 5;
                17'd115200: return 6; 17'd128000: return 7;
                default: return 8;
            endcase
        endfunction

        virtual function void write(uart_tick_item t);
            int unsigned parity_index;
            if (t.kind != UART_TICK_TRANSFER || !t.completed)
                return;
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
                `uvm_error("COV/BAUD", $sformatf(
                    "No hit for baud index %0d", i))
            end
            foreach (length_hits[i]) if (length_hits[i] == 0) begin
                coverage_closed = 1'b0;
                `uvm_error("COV/LENGTH", $sformatf(
                    "No hit for word length %0d", i + 5))
            end
            foreach (parity_hits[i]) if (parity_hits[i] == 0) begin
                coverage_closed = 1'b0;
                `uvm_error("COV/PARITY", $sformatf(
                    "No hit for parity mode %0d", i))
            end
            foreach (stop_hits[i]) if (stop_hits[i] == 0) begin
                coverage_closed = 1'b0;
                `uvm_error("COV/STOP", $sformatf(
                    "No hit for stop mode %0d", i))
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
                    "All baud and length x parity x stop bins were exercised",
                    UVM_LOW)
        endfunction
    endclass

    class uart_tick_agent extends uvm_agent;
        `uvm_component_utils(uart_tick_agent)
        uart_tick_env_config cfg;
        uart_tick_driver driver;
        uart_tick_monitor monitor;
        uvm_sequencer #(uart_tick_item) sequencer;

        function new(string name = "uart_tick_agent",
                     uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(uart_tick_env_config)::get(this, "", "cfg", cfg))
                cfg = uart_tick_env_config::type_id::create("cfg");
            is_active = cfg.is_active;
            monitor = uart_tick_monitor::type_id::create("monitor", this);
            if (is_active == UVM_ACTIVE) begin
                driver = uart_tick_driver::type_id::create("driver", this);
                sequencer = uvm_sequencer#(uart_tick_item)::type_id::create(
                    "sequencer", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (is_active == UVM_ACTIVE)
                driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class uart_tick_env extends uvm_env;
        `uvm_component_utils(uart_tick_env)
        uart_tick_agent agent;
        uart_tick_scoreboard scoreboard;
        uart_tick_coverage coverage;
        uart_tick_protocol_checker protocol_checker;

        function new(string name = "uart_tick_env",
                     uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = uart_tick_agent::type_id::create("agent", this);
            scoreboard = uart_tick_scoreboard::type_id::create(
                "scoreboard", this);
            coverage = uart_tick_coverage::type_id::create("coverage", this);
            protocol_checker = uart_tick_protocol_checker::type_id::create(
                "protocol_checker", this);
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.observed_ap.connect(scoreboard.observed_export);
            agent.monitor.observed_ap.connect(coverage.analysis_export);
        endfunction
    endclass

    class uart_tick_test extends uvm_test;
        `uvm_component_utils(uart_tick_test)
        uart_tick_env_config cfg;
        uart_tick_env env;

        function new(string name = "uart_tick_test",
                     uvm_component parent = null);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            cfg = uart_tick_env_config::type_id::create("cfg");
            cfg.is_active = UVM_ACTIVE;
            uvm_config_db#(uart_tick_env_config)::set(
                this, "env.agent", "cfg", cfg);
            env = uart_tick_env::type_id::create("env", this);
        endfunction

        virtual task run_phase(uvm_phase phase);
            uart_tick_regression_sequence regression;
            phase.raise_objection(this, "Tick UART regression is running");
            regression = uart_tick_regression_sequence::type_id::create(
                "regression");
            regression.start(env.agent.sequencer);
            repeat (10) @(posedge env.agent.driver.vif.clk);
            phase.drop_objection(this, "Tick UART regression completed");
        endtask
    endclass
endpackage

module uart_tick_uvm_tb;
    import uvm_pkg::*;
    import uart_tick_uvm_pkg::*;

    uart_tick_if vif();

    uart_top_tick dut (
        .clk        (vif.clk),
        .rst        (vif.rst),
        .tx_start   (vif.tx_start),
        .rx_start   (vif.rx_start),
        .tx_data    (vif.tx_data),
        .baud       (vif.baud),
        .length     (vif.length),
        .parity_type(vif.parity_type),
        .parity_en  (vif.parity_en),
        .stop2      (vif.stop2),
        .rx         (vif.serial_rx),
        .tx         (vif.serial_tx),
        .tx_done    (vif.tx_done),
        .rx_done    (vif.rx_done),
        .tx_err     (vif.tx_err),
        .rx_err     (vif.rx_err),
        .rx_out     (vif.rx_out)
    );

    assign vif.tx_tick = dut.tx_tick;
    assign vif.rx_tick = dut.rx_tick;
    assign vif.serial_rx = vif.serial_tx;
    assign vif.tx_state = dut.tx_dut.state_q;
    assign vif.rx_state = dut.rx_dut.state_q;
    assign vif.tx_bit_index = dut.tx_dut.bit_index;
    assign vif.rx_bit_index = dut.rx_dut.bit_index;
    assign vif.rx_sample_count = dut.rx_dut.sample_count;
    assign vif.rx_data_reg = dut.rx_dut.data_reg;

    always #10 vif.clk = ~vif.clk;

    initial begin
        uvm_config_db#(virtual uart_tick_if)::set(null, "*", "vif", vif);
        run_test("uart_tick_test");
    end

    initial if ($test$plusargs("DUMP_VCD")) begin
        $dumpfile("uart_tick.vcd");
        $dumpvars(0, uart_tick_uvm_tb);
    end
endmodule
