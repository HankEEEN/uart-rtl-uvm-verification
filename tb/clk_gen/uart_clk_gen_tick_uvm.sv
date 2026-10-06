`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

interface uart_clk_tick_if;
    logic        clk = 1'b0;
    logic        rst = 1'b1;
    logic [16:0] baud = 17'd9600;
    logic        tx_tick;
    logic        rx_tick;
endinterface

class uart_clk_tick_item extends uvm_sequence_item;
    `uvm_object_utils(uart_clk_tick_item)

    bit [16:0]   baud;
    bit          do_reset;
    int unsigned hold_cycles;
    bit          tx_tick;
    bit          rx_tick;

    function new(string name = "uart_clk_tick_item");
        super.new(name);
    endfunction
endclass

class uart_clk_tick_sequence extends uvm_sequence #(uart_clk_tick_item);
    `uvm_object_utils(uart_clk_tick_sequence)

    localparam int unsigned CLK_HZ = 50_000_000;

    function new(string name = "uart_clk_tick_sequence");
        super.new(name);
    endfunction

    function int unsigned increment_for(bit [16:0] selected_baud);
        case (selected_baud)
            17'd4800:   return 76_800;
            17'd9600:   return 153_600;
            17'd14400:  return 230_400;
            17'd19200:  return 307_200;
            17'd38400:  return 614_400;
            17'd57600:  return 921_600;
            17'd115200: return 1_843_200;
            17'd128000: return 2_048_000;
            default:    return 153_600;
        endcase
    endfunction

    function int unsigned observation_cycles(bit [16:0] selected_baud);
        int unsigned increment = increment_for(selected_baud);
        int unsigned longest_interval = (CLK_HZ + increment - 1) / increment;
        // Forty RX ticks include at least two derived TX ticks.
        return 40 * longest_interval + 8;
    endfunction

    task send_setting(bit [16:0] selected_baud, bit reset_request,
                      int unsigned cycles = 0);
        uart_clk_tick_item req;
        req = uart_clk_tick_item::type_id::create("req");
        start_item(req);
        req.baud = selected_baud;
        req.do_reset = reset_request;
        req.hold_cycles = (cycles != 0) ? cycles :
                          observation_cycles(selected_baud);
        finish_item(req);
    endtask

    virtual task body();
        bit [16:0] rates[8] = '{17'd4800, 17'd9600, 17'd14400,
                                17'd19200, 17'd38400, 17'd57600,
                                17'd115200, 17'd128000};

        send_setting(17'd9600, 1'b1, 4);
        foreach (rates[i]) begin
            send_setting(rates[i], 1'b0);
            if (i == 3) begin
                send_setting(rates[i], 1'b1, 4);
                send_setting(rates[i], 1'b0);
            end
        end
        // Verify the documented unsupported-rate fallback to 9600 baud.
        send_setting(17'd12345, 1'b0);
    endtask
endclass

class uart_clk_tick_driver extends uvm_driver #(uart_clk_tick_item);
    `uvm_component_utils(uart_clk_tick_driver)

    virtual uart_clk_tick_if vif;

    function new(string name = "uart_clk_tick_driver",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_clk_tick_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV/NOVIF", "uart_clk_tick_if was not configured")
    endfunction

    task run_phase(uvm_phase phase);
        uart_clk_tick_item req;
        forever begin
            seq_item_port.get_next_item(req);
            @(negedge vif.clk);
            vif.baud <= req.baud;
            vif.rst  <= req.do_reset;
            `uvm_info("DRV", $sformatf("baud=%0d reset=%0b hold=%0d",
                      req.baud, req.do_reset, req.hold_cycles), UVM_MEDIUM)
            repeat (req.hold_cycles) @(posedge vif.clk);
            seq_item_port.item_done();
        end
    endtask
endclass

class uart_clk_tick_monitor extends uvm_monitor;
    `uvm_component_utils(uart_clk_tick_monitor)

    virtual uart_clk_tick_if vif;
    uvm_analysis_port #(uart_clk_tick_item) observed_ap;

    function new(string name = "uart_clk_tick_monitor",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        observed_ap = new("observed_ap", this);
        if (!uvm_config_db#(virtual uart_clk_tick_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON/NOVIF", "uart_clk_tick_if was not configured")
    endfunction

    task run_phase(uvm_phase phase);
        uart_clk_tick_item sample;
        forever begin
            // Sample after the DUT's posedge nonblocking assignments settle.
            @(negedge vif.clk);
            sample = uart_clk_tick_item::type_id::create("sample");
            sample.baud = vif.baud;
            sample.do_reset = vif.rst;
            sample.tx_tick = vif.tx_tick;
            sample.rx_tick = vif.rx_tick;
            observed_ap.write(sample);
        end
    endtask
endclass

class uart_clk_tick_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uart_clk_tick_scoreboard)

    localparam longint unsigned CLK_HZ = 50_000_000;

    uvm_analysis_imp #(uart_clk_tick_item,
                       uart_clk_tick_scoreboard) observed_export;

    longint unsigned phase_acc;
    longint unsigned active_increment;
    int unsigned     oversample_count;
    int unsigned     rx_hits[9];
    int unsigned     tx_hits[9];
    int unsigned     reset_cycles;

    function new(string name = "uart_clk_tick_scoreboard",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        observed_export = new("observed_export", this);
        phase_acc = 0;
        active_increment = 153_600;
        oversample_count = 0;
        reset_cycles = 0;
        foreach (rx_hits[i]) begin
            rx_hits[i] = 0;
            tx_hits[i] = 0;
        end
    endfunction

    function longint unsigned increment_for(bit [16:0] selected_baud);
        case (selected_baud)
            17'd4800:   return 76_800;
            17'd9600:   return 153_600;
            17'd14400:  return 230_400;
            17'd19200:  return 307_200;
            17'd38400:  return 614_400;
            17'd57600:  return 921_600;
            17'd115200: return 1_843_200;
            17'd128000: return 2_048_000;
            default:    return 153_600;
        endcase
    endfunction

    function int unsigned baud_index(bit [16:0] selected_baud);
        case (selected_baud)
            17'd4800:   return 0;
            17'd9600:   return 1;
            17'd14400:  return 2;
            17'd19200:  return 3;
            17'd38400:  return 4;
            17'd57600:  return 5;
            17'd115200: return 6;
            17'd128000: return 7;
            default:    return 8;
        endcase
    endfunction

    function void write(uart_clk_tick_item sample);
        longint unsigned selected;
        longint unsigned sum;
        bit expected_rx;
        bit expected_tx;
        int unsigned index;

        expected_rx = 1'b0;
        expected_tx = 1'b0;

        if (sample.do_reset) begin
            phase_acc = 0;
            active_increment = 153_600;
            oversample_count = 0;
            reset_cycles++;
        end else begin
            selected = increment_for(sample.baud);
            if (active_increment != selected) begin
                phase_acc = 0;
                active_increment = selected;
                oversample_count = 0;
            end else begin
                sum = phase_acc + active_increment;
                if (sum >= CLK_HZ) begin
                    phase_acc = sum - CLK_HZ;
                    expected_rx = 1'b1;
                    if (oversample_count == 15) begin
                        oversample_count = 0;
                        expected_tx = 1'b1;
                    end else begin
                        oversample_count++;
                    end
                end else begin
                    phase_acc = sum;
                end
            end
        end

        if (sample.rx_tick !== expected_rx)
            `uvm_error("SCO/RXTICK", $sformatf(
                "baud=%0d expected rx_tick=%0b got=%0b",
                sample.baud, expected_rx, sample.rx_tick))
        if (sample.tx_tick !== expected_tx)
            `uvm_error("SCO/TXTICK", $sformatf(
                "baud=%0d expected tx_tick=%0b got=%0b",
                sample.baud, expected_tx, sample.tx_tick))
        if (sample.tx_tick && !sample.rx_tick)
            `uvm_error("SCO/RATIO", "tx_tick occurred without rx_tick")

        index = baud_index(sample.baud);
        if (sample.rx_tick) rx_hits[index]++;
        if (sample.tx_tick) tx_hits[index]++;
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        foreach (rx_hits[i]) begin
            if (rx_hits[i] < 32)
                `uvm_error("SCO/RXCOV", $sformatf(
                    "Baud index %0d produced only %0d RX ticks", i, rx_hits[i]))
            if (tx_hits[i] < 2)
                `uvm_error("SCO/TXCOV", $sformatf(
                    "Baud index %0d produced only %0d TX ticks", i, tx_hits[i]))
        end
        if (reset_cycles < 8)
            `uvm_error("SCO/RESET", "Initial and mid-test reset were not observed")
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCO/SUMMARY",
                  "Fractional timing, reset, fallback, and 16:1 tick ratio checked",
                  UVM_LOW)
    endfunction
endclass

class uart_clk_tick_agent extends uvm_agent;
    `uvm_component_utils(uart_clk_tick_agent)

    uart_clk_tick_driver driver;
    uart_clk_tick_monitor monitor;
    uvm_sequencer #(uart_clk_tick_item) sequencer;

    function new(string name = "uart_clk_tick_agent",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver = uart_clk_tick_driver::type_id::create("driver", this);
        monitor = uart_clk_tick_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer#(uart_clk_tick_item)::type_id::create(
            "sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

class uart_clk_tick_env extends uvm_env;
    `uvm_component_utils(uart_clk_tick_env)

    uart_clk_tick_agent agent;
    uart_clk_tick_scoreboard scoreboard;

    function new(string name = "uart_clk_tick_env",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = uart_clk_tick_agent::type_id::create("agent", this);
        scoreboard = uart_clk_tick_scoreboard::type_id::create(
            "scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.observed_ap.connect(scoreboard.observed_export);
    endfunction
endclass

class uart_clk_tick_test extends uvm_test;
    `uvm_component_utils(uart_clk_tick_test)

    uart_clk_tick_env env;

    function new(string name = "uart_clk_tick_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uart_clk_tick_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        uart_clk_tick_sequence seq;
        phase.raise_objection(this);
        seq = uart_clk_tick_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        repeat (5) @(posedge env.agent.driver.vif.clk);
        phase.drop_objection(this);
    endtask
endclass

module uart_clk_gen_tick_tb;
    uart_clk_tick_if vif();

    uart_clk_gen_tick dut (
        .clk    (vif.clk),
        .rst    (vif.rst),
        .baud   (vif.baud),
        .tx_tick(vif.tx_tick),
        .rx_tick(vif.rx_tick)
    );

    always #10 vif.clk = ~vif.clk;

    initial begin
        uvm_config_db#(virtual uart_clk_tick_if)::set(null, "*", "vif", vif);
        run_test("uart_clk_tick_test");
    end
endmodule
