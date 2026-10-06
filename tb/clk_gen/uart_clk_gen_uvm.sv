`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

interface uart_clk_if;
    logic        clk = 1'b0;
    logic        rst = 1'b1;
    logic [16:0] baud = 9600;
    logic        tx_clk;
    logic        rx_clk;
endinterface

typedef enum bit {TX_CLOCK, RX_CLOCK} uart_clock_kind_e;

class uart_clk_item extends uvm_sequence_item;
    `uvm_object_utils(uart_clk_item)

    rand bit [16:0] baud;
    bit               do_reset;
    int unsigned      hold_cycles;
    uart_clock_kind_e clock_kind;
    int unsigned      half_cycles;

    constraint supported_baud_c {
        baud inside {4800, 9600, 14400, 19200, 38400, 57600, 115200, 128000};
    }

    function new(string name = "uart_clk_item");
        super.new(name);
    endfunction
endclass

class uart_clk_sequence extends uvm_sequence #(uart_clk_item);
    `uvm_object_utils(uart_clk_sequence)

    function new(string name = "uart_clk_sequence");
        super.new(name);
    endfunction

    function int unsigned tx_period_for(bit [16:0] baud);
        case (baud)
            4800:   return 10416;
            9600:   return 5208;
            14400:  return 3472;
            19200:  return 2604;
            38400:  return 1302;
            57600:  return 868;
            115200: return 434;
            128000: return 392;
            default: return 5208;
        endcase
    endfunction

    task send_setting(bit [16:0] selected_baud, bit reset_request);
        uart_clk_item item;
        item = uart_clk_item::type_id::create("item");
        start_item(item);
        item.baud = selected_baud;
        item.do_reset = reset_request;
        // Three TX periods leave several complete TX and RX half periods
        // after the configuration register has updated.
        item.hold_cycles = reset_request ? 3 : 3 * tx_period_for(selected_baud) + 16;
        finish_item(item);
    endtask

    virtual task body();
        bit [16:0] rates[8] = '{4800, 9600, 14400, 19200,
                                38400, 57600, 115200, 128000};
        uart_clk_item random_item;

        send_setting(9600, 1'b1);
        foreach (rates[i]) begin
            send_setting(rates[i], 1'b0);
            if (i == 3)
                send_setting(rates[i], 1'b1); // Check a reset during operation.
        end
        send_setting(12345, 1'b0); // Unsupported baud selects the 9600 default.

        repeat (4) begin
            random_item = uart_clk_item::type_id::create("random_item");
            start_item(random_item);
            random_item.baud = rates[$urandom_range(0, 7)];
            random_item.do_reset = 1'b0;
            random_item.hold_cycles = 3 * tx_period_for(random_item.baud) + 16;
            finish_item(random_item);
        end
    endtask
endclass

class uart_clk_driver extends uvm_driver #(uart_clk_item);
    `uvm_component_utils(uart_clk_driver)

    virtual uart_clk_if vif;

    function new(string name = "uart_clk_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual uart_clk_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "uart_clk_if was not configured")
    endfunction

    task run_phase(uvm_phase phase);
        uart_clk_item item;
        forever begin
            seq_item_port.get_next_item(item);
            @(negedge vif.clk);
            vif.rst  <= item.do_reset;
            vif.baud <= item.baud;
            `uvm_info("DRV", $sformatf("baud=%0d reset=%0b hold=%0d",
                      item.baud, item.do_reset, item.hold_cycles), UVM_MEDIUM)
            repeat (item.hold_cycles) @(posedge vif.clk);
            seq_item_port.item_done();
        end
    endtask
endclass

class uart_clk_monitor extends uvm_monitor;
    `uvm_component_utils(uart_clk_monitor)

    virtual uart_clk_if vif;
    uvm_analysis_port #(uart_clk_item) observed;

    function new(string name = "uart_clk_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        observed = new("observed", this);
        if (!uvm_config_db#(virtual uart_clk_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "uart_clk_if was not configured")
    endfunction

    task publish_sample(bit [16:0] sampled_baud,
                        uart_clock_kind_e kind, int unsigned cycles);
        uart_clk_item sample;
        sample = uart_clk_item::type_id::create("sample");
        sample.baud = sampled_baud;
        sample.clock_kind = kind;
        sample.half_cycles = cycles;
        observed.write(sample);
    endtask

    task run_phase(uvm_phase phase);
        longint unsigned cycle_number = 0; // Total input-clock cycles elapsed; used as an edge timestamp
        longint unsigned last_tx_edge = 0; // Cycle number of the previous tx_clk transition
        longint unsigned last_rx_edge = 0; // Cycle number of the previous rx_clk transition
        bit have_tx_edge = 0;              // Indicates that a valid TX edge is available as a measurement start
        bit have_rx_edge = 0;              // Indicates that a valid RX edge is available as a measurement start
        bit tracking = 0;                  // Indicates that valid output periods are being tracked for the current baud
        bit was_reset = 0;                 // Records the previous reset state to avoid duplicate reset reports
        bit last_tx = 0;                   // Previously sampled tx_clk level, used to detect a transition
        bit last_rx = 0;                   // Previously sampled rx_clk level, used to detect a transition
        bit [16:0] tracked_baud = 0;        // Baud rate associated with the current measurements
        uart_clk_item reset_sample;         // Reset-event transaction sent to the scoreboard

        forever begin
            // The DUT updates on posedge; sample on negedge after its NBA updates.
            @(negedge vif.clk);
            cycle_number++;

            if (vif.rst) begin
                if (vif.tx_clk !== 1'b0 || vif.rx_clk !== 1'b0)
                    `uvm_error("MON", "TX/RX clocks must be low during reset")
                if (!was_reset) begin
                    reset_sample = uart_clk_item::type_id::create("reset_sample");
                    reset_sample.do_reset = 1'b1;
                    observed.write(reset_sample);
                end
                was_reset = 1;
                tracking = 0;
                have_tx_edge = 0;
                have_rx_edge = 0;
            end else begin
                was_reset = 0;
                if (!tracking || vif.baud != tracked_baud) begin
                    // Ignore the partial period spanning a reset or baud change.
                    tracked_baud = vif.baud;
                    last_tx = vif.tx_clk;
                    last_rx = vif.rx_clk;
                    have_tx_edge = 0;
                    have_rx_edge = 0;
                    tracking = 1;
                end else begin
                    if (vif.tx_clk !== last_tx) begin
                        if (have_tx_edge)
                            publish_sample(tracked_baud, TX_CLOCK,
                                           int'(cycle_number - last_tx_edge));
                        last_tx_edge = cycle_number;
                        have_tx_edge = 1;
                    end
                    if (vif.rx_clk !== last_rx) begin
                        if (have_rx_edge)
                            publish_sample(tracked_baud, RX_CLOCK,
                                           int'(cycle_number - last_rx_edge));
                        last_rx_edge = cycle_number;
                        have_rx_edge = 1;
                    end
                    last_tx = vif.tx_clk;
                    last_rx = vif.rx_clk;
                end
            end
        end
    endtask
endclass

class uart_clk_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(uart_clk_scoreboard)

    uvm_analysis_imp #(uart_clk_item, uart_clk_scoreboard) received;
    int unsigned tx_hits[9];
    int unsigned rx_hits[9];
    int unsigned reset_hits;

    function new(string name = "uart_clk_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        received = new("received", this);
        foreach (tx_hits[i]) begin
            tx_hits[i] = 0;
            rx_hits[i] = 0;
        end
        reset_hits = 0;
    endfunction

    function int unsigned baud_index(bit [16:0] baud);
        case (baud)
            4800:   return 0;
            9600:   return 1;
            14400:  return 2;
            19200:  return 3;
            38400:  return 4;
            57600:  return 5;
            115200: return 6;
            128000: return 7;
            default: return 8;
        endcase
    endfunction

    function int unsigned expected_half(bit [16:0] baud,
                                        uart_clock_kind_e kind);
        if (kind == TX_CLOCK) begin
            case (baud)
                4800:   return 5208;
                9600:   return 2604;
                14400:  return 1736;
                19200:  return 1302;
                38400:  return 651;
                57600:  return 434;
                115200: return 217;
                128000: return 196;
                default: return 2604;
            endcase
        end
        case (baud)
            4800:   return 326;
            9600:   return 163;
            14400:  return 109;
            19200:  return 81;
            38400:  return 41;
            57600:  return 27;
            115200: return 14;
            128000: return 12;
            default: return 163;
        endcase
    endfunction

    function void write(uart_clk_item item);
        int unsigned expected;
        int unsigned index;
        if (item.do_reset) begin
            reset_hits++;
            return;
        end

        index = baud_index(item.baud);
        expected = expected_half(item.baud, item.clock_kind);
        if (item.half_cycles != expected)
            `uvm_error("SCO", $sformatf("%s baud=%0d: got %0d input cycles per half period, expected %0d",
                       item.clock_kind.name(), item.baud, item.half_cycles, expected))
        else begin
            if (item.clock_kind == TX_CLOCK)
                tx_hits[index]++;
            else
                rx_hits[index]++;
        end
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        foreach (tx_hits[i]) begin
            if (tx_hits[i] == 0 || rx_hits[i] == 0)
                `uvm_error("SCO", $sformatf("Missing TX or RX measurement for baud index %0d", i))
        end
        if (reset_hits < 2)
            `uvm_error("SCO", "Initial and mid-test resets were not both observed")
    endfunction
endclass

class uart_clk_agent extends uvm_agent;
    `uvm_component_utils(uart_clk_agent)

    uart_clk_driver driver;
    uart_clk_monitor monitor;
    uvm_sequencer #(uart_clk_item) sequencer;

    function new(string name = "uart_clk_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver = uart_clk_driver::type_id::create("driver", this);
        monitor = uart_clk_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer#(uart_clk_item)::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

class uart_clk_env extends uvm_env;
    `uvm_component_utils(uart_clk_env)

    uart_clk_agent agent;
    uart_clk_scoreboard scoreboard;

    function new(string name = "uart_clk_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = uart_clk_agent::type_id::create("agent", this);
        scoreboard = uart_clk_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.observed.connect(scoreboard.received);
    endfunction
endclass

class uart_clk_test extends uvm_test;
    `uvm_component_utils(uart_clk_test)

    uart_clk_env env;

    function new(string name = "uart_clk_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uart_clk_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        uart_clk_sequence seq;
        phase.raise_objection(this);
        seq = uart_clk_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        repeat (3) @(posedge env.agent.driver.vif.clk);
        phase.drop_objection(this);
    endtask
endclass

module uart_clk_gen_tb;
    uart_clk_if vif();

    uart_clk_gen dut (
        .clk    (vif.clk),
        .rst    (vif.rst),
        .baud   (vif.baud),
        .tx_clk (vif.tx_clk),
        .rx_clk (vif.rx_clk)
    );

    always #10 vif.clk = ~vif.clk; // 50 MHz

    initial begin
        uvm_config_db#(virtual uart_clk_if)::set(null, "*", "vif", vif);
        run_test("uart_clk_test");
    end
endmodule
