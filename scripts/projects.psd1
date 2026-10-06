@{
    # Each project maps a short command-line name to its file list and testbench top.
    clk_gen = @{
        FileList = "filelists/clk_gen.f"
        Top      = "uart_clk_gen_tb"
        IsUvm    = $true
    }
    uart_tx = @{
        FileList = "filelists/uart_tx.f"
        Top      = "uart_tb"
        IsUvm    = $true
    }
    uart_tick_uvm = @{
        FileList = "filelists/uart_tick_uvm.f"
        Top      = "uart_tick_uvm_tb"
        IsUvm    = $true
    }
}
